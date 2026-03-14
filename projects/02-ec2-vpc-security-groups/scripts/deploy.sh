#!/bin/bash
set -euo pipefail

# ── AWS Lab 02: EC2 + VPC + Security Groups ───────────────────────────────────
# Deploy a hardened EC2 instance in a custom VPC with SSM access (no open SSH)
# Usage: bash scripts/deploy.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS Lab 02 — EC2 + VPC + Security Groups"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── CONFIG ────────────────────────────────────────────────────────────────────
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="${AWS_REGION:-us-east-1}"
export PROJECT_TAG="aws-cert-study"
export ENV_TAG="learning"

VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"
INSTANCE_TYPE="t3.micro"

echo ""
echo "Account : $AWS_ACCOUNT_ID"
echo "Region  : $AWS_REGION"
echo ""

# ── TAGS HELPER ───────────────────────────────────────────────────────────────
TAGS="ResourceType=vpc,Tags=[{Key=Project,Value=$PROJECT_TAG},{Key=Environment,Value=$ENV_TAG},{Key=ManagedBy,Value=manual}]"

tag_resource() {
  local resource_id="$1"
  local name="$2"
  aws ec2 create-tags --resources "$resource_id" --tags \
    Key=Name,Value="$name" \
    Key=Project,Value="$PROJECT_TAG" \
    Key=Environment,Value="$ENV_TAG" \
    Key=ManagedBy,Value=manual \
    --region "$AWS_REGION"
}

# ── STEP 1: VPC ───────────────────────────────────────────────────────────────
echo "▶ Creating VPC ($VPC_CIDR)..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --query 'Vpc.VpcId' --output text \
  --region "$AWS_REGION")
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$AWS_REGION"
tag_resource "$VPC_ID" "aws-cert-study-vpc"
echo "  VPC_ID=$VPC_ID"
export VPC_ID

# ── STEP 2: SUBNETS ───────────────────────────────────────────────────────────
echo "▶ Creating public subnet ($PUBLIC_SUBNET_CIDR)..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PUBLIC_SUBNET_CIDR" \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' --output text \
  --region "$AWS_REGION")
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch --region "$AWS_REGION"
tag_resource "$PUBLIC_SUBNET_ID" "aws-cert-study-public"
echo "  PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID"
export PUBLIC_SUBNET_ID

echo "▶ Creating private subnet ($PRIVATE_SUBNET_CIDR)..."
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PRIVATE_SUBNET_CIDR" \
  --availability-zone "${AWS_REGION}b" \
  --query 'Subnet.SubnetId' --output text \
  --region "$AWS_REGION")
tag_resource "$PRIVATE_SUBNET_ID" "aws-cert-study-private"
echo "  PRIVATE_SUBNET_ID=$PRIVATE_SUBNET_ID"
export PRIVATE_SUBNET_ID

# ── STEP 3: INTERNET GATEWAY ──────────────────────────────────────────────────
echo "▶ Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' --output text \
  --region "$AWS_REGION")
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
tag_resource "$IGW_ID" "aws-cert-study-igw"
echo "  IGW_ID=$IGW_ID"
export IGW_ID

# ── STEP 4: PUBLIC ROUTE TABLE ────────────────────────────────────────────────
echo "▶ Creating public route table..."
PUBLIC_RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' --output text \
  --region "$AWS_REGION")
aws ec2 create-route --route-table-id "$PUBLIC_RTB_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" --region "$AWS_REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUBLIC_RTB_ID" --subnet-id "$PUBLIC_SUBNET_ID" --region "$AWS_REGION" > /dev/null
tag_resource "$PUBLIC_RTB_ID" "aws-cert-study-public-rtb"
echo "  PUBLIC_RTB_ID=$PUBLIC_RTB_ID"
export PUBLIC_RTB_ID

# ── STEP 5: NAT GATEWAY (for private subnet outbound) ─────────────────────────
echo "▶ Allocating Elastic IP for NAT Gateway..."
EIP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --query 'AllocationId' --output text \
  --region "$AWS_REGION")
echo "  EIP_ALLOC_ID=$EIP_ALLOC_ID"

echo "▶ Creating NAT Gateway (takes ~60 seconds)..."
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_SUBNET_ID" \
  --allocation-id "$EIP_ALLOC_ID" \
  --query 'NatGateway.NatGatewayId' --output text \
  --region "$AWS_REGION")
tag_resource "$NAT_GW_ID" "aws-cert-study-nat" 2>/dev/null || true
echo "  NAT_GW_ID=$NAT_GW_ID — waiting for available state..."
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID" --region "$AWS_REGION"
echo "  NAT Gateway ready."
export NAT_GW_ID EIP_ALLOC_ID

# ── STEP 6: PRIVATE ROUTE TABLE ───────────────────────────────────────────────
echo "▶ Creating private route table..."
PRIVATE_RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' --output text \
  --region "$AWS_REGION")
aws ec2 create-route --route-table-id "$PRIVATE_RTB_ID" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "$NAT_GW_ID" --region "$AWS_REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRIVATE_RTB_ID" --subnet-id "$PRIVATE_SUBNET_ID" --region "$AWS_REGION" > /dev/null
tag_resource "$PRIVATE_RTB_ID" "aws-cert-study-private-rtb"
echo "  PRIVATE_RTB_ID=$PRIVATE_RTB_ID"
export PRIVATE_RTB_ID

# ── STEP 7: SECURITY GROUP ────────────────────────────────────────────────────
echo "▶ Creating Security Group (no port 22 — SSM only)..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "aws-cert-study-sg" \
  --description "Lab 02 - SSM access only, no open SSH" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text \
  --region "$AWS_REGION")
# HTTPS outbound only (SSM needs 443 outbound)
aws ec2 authorize-security-group-egress \
  --group-id "$SG_ID" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" > /dev/null
# Remove default allow-all egress
aws ec2 revoke-security-group-egress \
  --group-id "$SG_ID" \
  --protocol -1 --port -1 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" 2>/dev/null || true
tag_resource "$SG_ID" "aws-cert-study-sg"
echo "  SG_ID=$SG_ID"
export SG_ID

# ── STEP 8: IAM ROLE FOR SSM ──────────────────────────────────────────────────
echo "▶ Creating IAM role for SSM Session Manager..."
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

aws iam create-role \
  --role-name "aws-cert-study-ssm-role" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --tags Key=Project,Value="$PROJECT_TAG" Key=Environment,Value="$ENV_TAG" \
  --region "$AWS_REGION" > /dev/null 2>&1 || echo "  (role already exists)"

aws iam attach-role-policy \
  --role-name "aws-cert-study-ssm-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true

INSTANCE_PROFILE_NAME="aws-cert-study-ssm-profile"
aws iam create-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" 2>/dev/null || true
aws iam add-role-to-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --role-name "aws-cert-study-ssm-role" 2>/dev/null || true

echo "  SSM role and instance profile ready."
echo "  Waiting 10s for IAM propagation..."
sleep 10

# ── STEP 9: EC2 INSTANCE ──────────────────────────────────────────────────────
echo "▶ Fetching latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text \
  --region "$AWS_REGION")
echo "  AMI_ID=$AMI_ID"

echo "▶ Launching EC2 instance ($INSTANCE_TYPE)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$PRIVATE_SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
  --no-associate-public-ip-address \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=aws-cert-study-ec2},{Key=Project,Value=$PROJECT_TAG},{Key=Environment,Value=$ENV_TAG},{Key=ManagedBy,Value=manual}]" \
    "ResourceType=volume,Tags=[{Key=Project,Value=$PROJECT_TAG},{Key=Environment,Value=$ENV_TAG}]" \
  --query 'Instances[0].InstanceId' --output text \
  --region "$AWS_REGION")
echo "  INSTANCE_ID=$INSTANCE_ID — waiting for running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
echo "  EC2 instance running."
export INSTANCE_ID AMI_ID

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Lab 02 deployed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " VPC:             $VPC_ID"
echo " Public Subnet:   $PUBLIC_SUBNET_ID"
echo " Private Subnet:  $PRIVATE_SUBNET_ID"
echo " Internet GW:     $IGW_ID"
echo " NAT Gateway:     $NAT_GW_ID"
echo " Security Group:  $SG_ID"
echo " EC2 Instance:    $INSTANCE_ID"
echo ""
echo " Connect via SSM Session Manager:"
echo " aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
echo ""
echo " ⚠️  Remember to run cleanup.sh when done to avoid charges!"
echo ""
