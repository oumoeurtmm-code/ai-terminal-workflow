#!/bin/bash
set -euo pipefail

# ── AWS Lab 02: Cleanup ───────────────────────────────────────────────────────
# Destroys all resources created by deploy.sh in the correct teardown order
# Usage: bash scripts/cleanup.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS Lab 02 — Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

export AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_TAG="aws-cert-study"

# Helper: find resource by tag
find_vpc() {
  aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" \
    --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION" 2>/dev/null
}

VPC_ID=$(find_vpc)
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "No VPC found with Project=$PROJECT_TAG — nothing to clean up."
  exit 0
fi
echo "Found VPC: $VPC_ID"

# ── STEP 1: Terminate EC2 instances ───────────────────────────────────────────
echo "▶ Terminating EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=instance-state-name,Values=running,stopped,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text --region "$AWS_REGION")
if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$AWS_REGION" > /dev/null
  echo "  Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$AWS_REGION"
  echo "  Instances terminated."
else
  echo "  No instances found."
fi

# ── STEP 2: Delete NAT Gateway + release EIP ──────────────────────────────────
echo "▶ Deleting NAT Gateways..."
NAT_IDS=$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Project,Values=$PROJECT_TAG" "Name=state,Values=available,pending" \
  --query 'NatGateways[].NatGatewayId' --output text --region "$AWS_REGION")
if [ -n "$NAT_IDS" ] && [ "$NAT_IDS" != "None" ]; then
  for NAT_ID in $NAT_IDS; do
    EIP_ALLOC=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_ID" \
      --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text --region "$AWS_REGION")
    aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" --region "$AWS_REGION" > /dev/null
    echo "  Deleted NAT Gateway $NAT_ID — waiting..."
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID" --region "$AWS_REGION" 2>/dev/null || sleep 30
    if [ -n "$EIP_ALLOC" ] && [ "$EIP_ALLOC" != "None" ]; then
      aws ec2 release-address --allocation-id "$EIP_ALLOC" --region "$AWS_REGION" 2>/dev/null || true
      echo "  Released Elastic IP $EIP_ALLOC"
    fi
  done
else
  echo "  No NAT Gateways found."
fi

# ── STEP 3: Detach and delete Internet Gateway ────────────────────────────────
echo "▶ Removing Internet Gateway..."
IGW_IDS=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[].InternetGatewayId' --output text --region "$AWS_REGION")
for IGW_ID in $IGW_IDS; do
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
  echo "  Deleted IGW $IGW_ID"
done

# ── STEP 4: Delete subnets ────────────────────────────────────────────────────
echo "▶ Deleting subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].SubnetId' --output text --region "$AWS_REGION")
for SUBNET_ID in $SUBNET_IDS; do
  aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$AWS_REGION"
  echo "  Deleted subnet $SUBNET_ID"
done

# ── STEP 5: Delete route tables (non-main) ────────────────────────────────────
echo "▶ Deleting route tables..."
RTB_IDS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
  --output text --region "$AWS_REGION")
for RTB_ID in $RTB_IDS; do
  aws ec2 delete-route-table --route-table-id "$RTB_ID" --region "$AWS_REGION" 2>/dev/null || true
  echo "  Deleted route table $RTB_ID"
done

# ── STEP 6: Delete security groups (non-default) ─────────────────────────────
echo "▶ Deleting security groups..."
SG_IDS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text --region "$AWS_REGION")
for SG_ID in $SG_IDS; do
  aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" 2>/dev/null || true
  echo "  Deleted security group $SG_ID"
done

# ── STEP 7: Delete VPC ────────────────────────────────────────────────────────
echo "▶ Deleting VPC $VPC_ID..."
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$AWS_REGION"
echo "  VPC deleted."

# ── STEP 8: Clean up IAM ──────────────────────────────────────────────────────
echo "▶ Cleaning up IAM role and instance profile..."
aws iam remove-role-from-instance-profile \
  --instance-profile-name "aws-cert-study-ssm-profile" \
  --role-name "aws-cert-study-ssm-role" 2>/dev/null || true
aws iam delete-instance-profile \
  --instance-profile-name "aws-cert-study-ssm-profile" 2>/dev/null || true
aws iam detach-role-policy \
  --role-name "aws-cert-study-ssm-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
aws iam delete-role \
  --role-name "aws-cert-study-ssm-role" 2>/dev/null || true
echo "  IAM cleaned up."

# ── VERIFY ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Cleanup complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Verifying no tagged resources remain..."
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values="$PROJECT_TAG" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table --region "$AWS_REGION" 2>/dev/null || echo " (resourcegroupstaggingapi not available in this region)"
echo ""
