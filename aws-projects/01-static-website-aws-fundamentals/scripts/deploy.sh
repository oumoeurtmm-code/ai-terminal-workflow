#!/usr/bin/env bash
# =============================================================================
# Deploy Script — AWS Cert Study Project 01
# Automates all deployment steps from the README.
#
# Usage:
#   bash deploy.sh
#
# The script will:
#   1. Validate AWS CLI is configured
#   2. Create S3 buckets (website + logs)
#   3. Configure website hosting, versioning, logging
#   4. Upload website files
#   5. Create CloudFront distribution with OAC
#   6. Create CloudWatch alarm
#   7. Print the live website URL
#
# All resource IDs are saved to .env.project for use by cleanup.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env.project"
WEBSITE_DIR="$PROJECT_DIR/website"

echo ""
echo "=============================================="
echo "  AWS Cert Study — Deploy Script"
echo "=============================================="
echo ""

# --------------------------------------------------------------------------
# Step 0: Validate prerequisites
# --------------------------------------------------------------------------
log_info "Checking prerequisites..."

if ! command -v aws &>/dev/null; then
    log_error "AWS CLI is not installed. Install it from:"
    echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS CLI is not configured or credentials are invalid. Run: aws configure"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    log_error "Python 3 is required for this script."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
TIMESTAMP=$(date +%s)
BUCKET_NAME="aws-cert-study-${AWS_ACCOUNT_ID}-${TIMESTAMP}"
LOG_BUCKET_NAME="${BUCKET_NAME}-logs"

log_success "AWS CLI configured. Account: $AWS_ACCOUNT_ID | Region: $AWS_REGION"

# --------------------------------------------------------------------------
# Step 1: Create S3 website bucket
# --------------------------------------------------------------------------
log_info "Creating S3 website bucket: $BUCKET_NAME ..."

aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION"

log_success "Bucket created."

# Enable versioning
log_info "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Block all public access (CloudFront will access via OAC)
log_info "Blocking public access..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable static website hosting
log_info "Enabling static website hosting..."
aws s3api put-bucket-website \
    --bucket "$BUCKET_NAME" \
    --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"error.html"}}'

# Apply tags
log_info "Applying tags..."
aws s3api put-bucket-tagging \
    --bucket "$BUCKET_NAME" \
    --tagging '{
        "TagSet": [
            {"Key": "Project", "Value": "aws-cert-study"},
            {"Key": "Environment", "Value": "learning"},
            {"Key": "ManagedBy", "Value": "deploy.sh"}
        ]
    }'

log_success "S3 website bucket configured."

# --------------------------------------------------------------------------
# Step 2: Create S3 logs bucket
# --------------------------------------------------------------------------
log_info "Creating S3 logs bucket: $LOG_BUCKET_NAME ..."

aws s3api create-bucket \
    --bucket "$LOG_BUCKET_NAME" \
    --region "$AWS_REGION"

# Apply lifecycle policy to logs bucket
aws s3api put-bucket-lifecycle-configuration \
    --bucket "$LOG_BUCKET_NAME" \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "MoveLogsToIA",
            "Status": "Enabled",
            "Filter": {"Prefix": "s3-access-logs/"},
            "Transitions": [
                {"Days": 30, "StorageClass": "STANDARD_IA"},
                {"Days": 90, "StorageClass": "GLACIER"}
            ],
            "Expiration": {"Days": 365}
        }]
    }'

log_success "Logs bucket configured with lifecycle policy."

# Enable server access logging
log_info "Enabling S3 access logging..."
aws s3api put-bucket-logging \
    --bucket "$BUCKET_NAME" \
    --bucket-logging-status '{
        "LoggingEnabled": {
            "TargetBucket": "'"$LOG_BUCKET_NAME"'",
            "TargetPrefix": "s3-access-logs/"
        }
    }'

# --------------------------------------------------------------------------
# Step 3: Upload website files
# --------------------------------------------------------------------------
log_info "Uploading website files..."

if [[ ! -d "$WEBSITE_DIR" ]]; then
    log_error "Website directory not found at $WEBSITE_DIR"
    exit 1
fi

aws s3 cp "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" --recursive --quiet
log_success "Website files uploaded."

# --------------------------------------------------------------------------
# Step 4: Create CloudFront Origin Access Control
# --------------------------------------------------------------------------
log_info "Creating CloudFront Origin Access Control..."

OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config '{
        "Name": "aws-cert-study-oac-'"$TIMESTAMP"'",
        "Description": "OAC for aws-cert-study static website",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }' \
    --query 'OriginAccessControl.Id' \
    --output text)

log_success "OAC created: $OAC_ID"

# --------------------------------------------------------------------------
# Step 5: Create CloudFront Distribution
# --------------------------------------------------------------------------
log_info "Creating CloudFront distribution (this takes 5-15 minutes)..."

DISTRIBUTION_ID=$(aws cloudfront create-distribution \
    --distribution-config '{
        "CallerReference": "aws-cert-study-'"$TIMESTAMP"'",
        "Comment": "AWS Certification Study - Static Website",
        "DefaultCacheBehavior": {
            "TargetOriginId": "S3Origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
            "Compress": true,
            "AllowedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"],
                "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
            }
        },
        "Origins": {
            "Quantity": 1,
            "Items": [{
                "Id": "S3Origin",
                "DomainName": "'"$BUCKET_NAME"'.s3.amazonaws.com",
                "S3OriginConfig": {"OriginAccessIdentity": ""},
                "OriginAccessControlId": "'"$OAC_ID"'"
            }]
        },
        "Enabled": true,
        "DefaultRootObject": "index.html",
        "PriceClass": "PriceClass_100",
        "HttpVersion": "http2"
    }' \
    --query 'Distribution.Id' \
    --output text)

log_success "Distribution created: $DISTRIBUTION_ID"

# --------------------------------------------------------------------------
# Step 6: Update S3 bucket policy to allow CloudFront OAC
# --------------------------------------------------------------------------
log_info "Updating S3 bucket policy for CloudFront OAC access..."

DISTRIBUTION_ARN="arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"

aws s3api put-bucket-policy \
    --bucket "$BUCKET_NAME" \
    --policy '{
        "Version": "2012-10-17",
        "Statement": [{
            "Sid": "AllowCloudFrontOAC",
            "Effect": "Allow",
            "Principal": {"Service": "cloudfront.amazonaws.com"},
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::'"$BUCKET_NAME"'/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "'"$DISTRIBUTION_ARN"'"
                }
            }
        }]
    }'

log_success "Bucket policy updated."

# --------------------------------------------------------------------------
# Step 7: Create CloudWatch alarm
# --------------------------------------------------------------------------
log_info "Creating CloudWatch alarm..."

aws cloudwatch put-metric-alarm \
    --alarm-name "CloudFront-4xx-Errors-High" \
    --alarm-description "Alert when CloudFront 4xx error rate exceeds 5%" \
    --namespace AWS/CloudFront \
    --metric-name 4xxErrorRate \
    --dimensions Name=DistributionId,Value="$DISTRIBUTION_ID" \
                 Name=Region,Value=Global \
    --statistic Average \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching

log_success "CloudWatch alarm created."

# --------------------------------------------------------------------------
# Step 8: Save all resource IDs to .env.project
# --------------------------------------------------------------------------
log_info "Saving resource IDs to $ENV_FILE ..."

cat > "$ENV_FILE" <<EOF
# AWS Cert Study Project 01 — Resource IDs
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Source this file to re-export variables for cleanup.sh
#
#   source $ENV_FILE

export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export LOG_BUCKET_NAME="$LOG_BUCKET_NAME"
export DISTRIBUTION_ID="$DISTRIBUTION_ID"
export OAC_ID="$OAC_ID"
EOF

log_success "Resource IDs saved."

# --------------------------------------------------------------------------
# Step 9: Wait for CloudFront and print live URL
# --------------------------------------------------------------------------
log_info "Waiting for CloudFront distribution to go live..."
aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"

CF_DOMAIN=$(aws cloudfront get-distribution \
    --id "$DISTRIBUTION_ID" \
    --query 'Distribution.DomainName' \
    --output text)

echo ""
echo "=============================================="
echo -e "${GREEN}  Deployment Complete!${NC}"
echo "=============================================="
echo ""
echo "  Live URL:          https://$CF_DOMAIN"
echo "  S3 Bucket:         $BUCKET_NAME"
echo "  Distribution ID:   $DISTRIBUTION_ID"
echo ""
echo "  To clean up all resources when done:"
echo "    source $ENV_FILE"
echo "    bash $PROJECT_DIR/scripts/cleanup.sh"
echo ""
