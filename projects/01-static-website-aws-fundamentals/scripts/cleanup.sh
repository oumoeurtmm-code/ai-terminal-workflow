#!/usr/bin/env bash
# =============================================================================
# Cleanup Script — AWS Cert Study Project 01
# Deletes all resources created in this project to avoid surprise bills.
#
# Usage:
#   bash cleanup.sh
#
# If you ran the project in a different terminal, re-export variables first:
#   export BUCKET_NAME="your-bucket-name"
#   export LOG_BUCKET_NAME="your-bucket-name-logs"
#   export DISTRIBUTION_ID="your-distribution-id"
#   export OAC_ID="your-oac-id"
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "  AWS Cert Study — Resource Cleanup Script"
echo "=============================================="
echo ""

# --------------------------------------------------------------------------
# Validate required environment variables
# --------------------------------------------------------------------------
MISSING_VARS=false

for var in BUCKET_NAME LOG_BUCKET_NAME DISTRIBUTION_ID OAC_ID; do
    if [[ -z "${!var:-}" ]]; then
        log_warn "Variable $var is not set."
        MISSING_VARS=true
    fi
done

if [[ "$MISSING_VARS" == "true" ]]; then
    echo ""
    log_error "One or more required variables are missing."
    echo "Please re-export them and re-run this script:"
    echo ""
    echo "  export BUCKET_NAME=\"your-bucket-name\""
    echo "  export LOG_BUCKET_NAME=\"your-bucket-name-logs\""
    echo "  export DISTRIBUTION_ID=\"your-distribution-id\""
    echo "  export OAC_ID=\"your-oac-id\""
    echo ""
    echo "You can find these values in the AWS Console or by running:"
    echo "  aws cloudfront list-distributions"
    echo "  aws s3 ls | grep aws-cert-study"
    exit 1
fi

echo "Resources to be deleted:"
echo "  S3 Bucket (website):    $BUCKET_NAME"
echo "  S3 Bucket (logs):       $LOG_BUCKET_NAME"
echo "  CloudFront Distribution: $DISTRIBUTION_ID"
echo "  Origin Access Control:  $OAC_ID"
echo ""
echo "This will permanently delete all resources listed above."
read -r -p "Type 'yes' to confirm: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log_warn "Cleanup cancelled."
    exit 0
fi

echo ""

# --------------------------------------------------------------------------
# Step 1: Delete CloudWatch Alarm
# --------------------------------------------------------------------------
log_info "Deleting CloudWatch alarm..."
if aws cloudwatch delete-alarms \
    --alarm-names "CloudFront-4xx-Errors-High" 2>/dev/null; then
    log_success "CloudWatch alarm deleted."
else
    log_warn "CloudWatch alarm not found or already deleted."
fi

# --------------------------------------------------------------------------
# Step 2: Disable CloudFront Distribution
# --------------------------------------------------------------------------
log_info "Disabling CloudFront distribution $DISTRIBUTION_ID ..."

# Check if distribution exists
DIST_STATUS=$(aws cloudfront get-distribution \
    --id "$DISTRIBUTION_ID" \
    --query 'Distribution.Status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$DIST_STATUS" == "NOT_FOUND" ]]; then
    log_warn "CloudFront distribution not found — may already be deleted."
else
    DIST_ENABLED=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.DistributionConfig.Enabled' \
        --output text)

    if [[ "$DIST_ENABLED" == "true" ]]; then
        # Get current config and ETag
        ETAG=$(aws cloudfront get-distribution \
            --id "$DISTRIBUTION_ID" \
            --query 'ETag' \
            --output text)

        # Fetch distribution config, disable it, and update
        aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query 'DistributionConfig' \
            --output json > /tmp/cf-config-cleanup.json

        # Set Enabled to false using Python (available on all platforms)
        python3 -c "
import json, sys
with open('/tmp/cf-config-cleanup.json') as f:
    config = json.load(f)
config['Enabled'] = False
print(json.dumps(config))
" > /tmp/cf-config-disabled.json

        aws cloudfront update-distribution \
            --id "$DISTRIBUTION_ID" \
            --distribution-config file:///tmp/cf-config-disabled.json \
            --if-match "$ETAG" > /dev/null

        log_info "Distribution disabled. Waiting for deployment (this takes 5-15 minutes)..."
        aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
        log_success "Distribution is disabled."
    else
        log_info "Distribution is already disabled."
        aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
    fi

    # Delete the distribution
    ETAG=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' \
        --output text)

    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$ETAG"

    log_success "CloudFront distribution deleted."
fi

# --------------------------------------------------------------------------
# Step 3: Delete Origin Access Control
# --------------------------------------------------------------------------
log_info "Deleting Origin Access Control $OAC_ID ..."
if aws cloudfront delete-origin-access-control \
    --id "$OAC_ID" 2>/dev/null; then
    log_success "Origin Access Control deleted."
else
    log_warn "OAC not found or already deleted."
fi

# --------------------------------------------------------------------------
# Step 4: Empty and delete the website bucket
# --------------------------------------------------------------------------
log_info "Emptying website bucket $BUCKET_NAME ..."

# Delete all versioned objects (required when versioning is enabled)
VERSIONS=$(aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
    --output json 2>/dev/null || echo '{"Objects": []}')

if [[ "$(echo "$VERSIONS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("Objects") or []))')" -gt 0 ]]; then
    echo "$VERSIONS" | aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete file:///dev/stdin > /dev/null 2>&1 || true
fi

# Delete all delete markers
DELETE_MARKERS=$(aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
    --output json 2>/dev/null || echo '{"Objects": []}')

if [[ "$(echo "$DELETE_MARKERS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("Objects") or []))')" -gt 0 ]]; then
    echo "$DELETE_MARKERS" | aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete file:///dev/stdin > /dev/null 2>&1 || true
fi

# Final sync delete and bucket removal
aws s3 rm s3://"$BUCKET_NAME" --recursive --quiet 2>/dev/null || true

log_info "Deleting website bucket..."
if aws s3api delete-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    log_success "Website bucket deleted."
else
    log_warn "Website bucket not found or already deleted."
fi

# --------------------------------------------------------------------------
# Step 5: Empty and delete the logs bucket
# --------------------------------------------------------------------------
log_info "Emptying logs bucket $LOG_BUCKET_NAME ..."
aws s3 rm s3://"$LOG_BUCKET_NAME" --recursive --quiet 2>/dev/null || true

log_info "Deleting logs bucket..."
if aws s3api delete-bucket --bucket "$LOG_BUCKET_NAME" 2>/dev/null; then
    log_success "Logs bucket deleted."
else
    log_warn "Logs bucket not found or already deleted."
fi

# --------------------------------------------------------------------------
# Step 6: Clean up temp files
# --------------------------------------------------------------------------
rm -f /tmp/cf-config-cleanup.json /tmp/cf-config-disabled.json

# --------------------------------------------------------------------------
# Final verification
# --------------------------------------------------------------------------
echo ""
log_info "Running final verification..."

REMAINING=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=aws-cert-study \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output json 2>/dev/null || echo "[]")

REMAINING_COUNT=$(echo "$REMAINING" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')

if [[ "$REMAINING_COUNT" -eq 0 ]]; then
    log_success "Verification passed. No tagged project resources found."
else
    log_warn "Found $REMAINING_COUNT resource(s) still tagged with Project=aws-cert-study:"
    echo "$REMAINING"
    echo ""
    log_warn "You may need to delete these manually in the AWS Console."
fi

echo ""
echo "=============================================="
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo "=============================================="
echo ""
echo "Your AWS bill for this project should be $0.00"
echo "(assuming you stayed within Free Tier limits)."
echo ""
echo "Check your cost dashboard at:"
echo "  https://console.aws.amazon.com/billing/home#/bills"
echo ""
