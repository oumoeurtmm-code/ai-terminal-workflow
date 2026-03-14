#!/bin/bash
set -euo pipefail

# ── AWS Lab 03: Cleanup ───────────────────────────────────────────────────────
# Destroys all resources created by deploy.sh in the correct teardown order
# Usage: bash scripts/cleanup.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS Lab 03 — Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

export AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_TAG="aws-cert-study"
DB_IDENTIFIER="aws-cert-study-rds"

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

# ── STEP 2: Delete RDS instance ───────────────────────────────────────────────
echo "▶ Deleting RDS instance (takes 3-5 minutes)..."
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].DBInstanceStatus' --output text \
  --region "$AWS_REGION" 2>/dev/null || echo "not-found")

if [ "$RDS_STATUS" != "not-found" ] && [ "$RDS_STATUS" != "None" ]; then
  aws rds delete-db-instance \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --skip-final-snapshot \
    --region "$AWS_REGION" > /dev/null 2>&1 || true
  echo "  Waiting for RDS deletion (~5 minutes)..."
  aws rds wait db-instance-deleted \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --region "$AWS_REGION" 2>/dev/null || sleep 60
  echo "  RDS instance deleted."
else
  echo "  No RDS instance found."
fi

# ── STEP 3: Delete DB subnet group ────────────────────────────────────────────
echo "▶ Deleting DB subnet group..."
aws rds delete-db-subnet-group \
  --db-subnet-group-name "aws-cert-study-db-subnet-group" \
  --region "$AWS_REGION" 2>/dev/null || echo "  (subnet group not found)"

# ── STEP 4: Delete Secrets Manager secret ─────────────────────────────────────
echo "▶ Deleting Secrets Manager secret..."
aws secretsmanager delete-secret \
  --secret-id "aws-cert-study/lab03/db-credentials" \
  --force-delete-without-recovery \
  --region "$AWS_REGION" 2>/dev/null || echo "  (secret not found)"
echo "  Secret deleted."

# ── STEP 5: Find VPC ──────────────────────────────────────────────────────────
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=$PROJECT_TAG" \
  --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION" 2>/dev/null)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "No VPC found — skipping network cleanup."
else
  echo "Found VPC: $VPC_ID"

  # ── STEP 6: Detach and delete Internet Gateway ──────────────────────────────
  echo "▶ Removing Internet Gateway..."
  IGW_IDS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[].InternetGatewayId' --output text --region "$AWS_REGION")
  for IGW_ID in $IGW_IDS; do
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
    echo "  Deleted IGW $IGW_ID"
  done

  # ── STEP 7: Delete subnets ──────────────────────────────────────────────────
  echo "▶ Deleting subnets..."
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].SubnetId' --output text --region "$AWS_REGION")
  for SUBNET_ID in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$AWS_REGION" 2>/dev/null || true
    echo "  Deleted subnet $SUBNET_ID"
  done

  # ── STEP 8: Delete route tables (non-main) ─────────────────────────────────
  echo "▶ Deleting route tables..."
  RTB_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
    --output text --region "$AWS_REGION")
  for RTB_ID in $RTB_IDS; do
    aws ec2 delete-route-table --route-table-id "$RTB_ID" --region "$AWS_REGION" 2>/dev/null || true
    echo "  Deleted route table $RTB_ID"
  done

  # ── STEP 9: Delete security groups ─────────────────────────────────────────
  echo "▶ Deleting security groups..."
  SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text --region "$AWS_REGION")
  for SG_ID in $SG_IDS; do
    aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" 2>/dev/null || true
    echo "  Deleted security group $SG_ID"
  done

  # ── STEP 10: Delete VPC ────────────────────────────────────────────────────
  echo "▶ Deleting VPC $VPC_ID..."
  aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$AWS_REGION"
  echo "  VPC deleted."
fi

# ── STEP 11: Clean up IAM ─────────────────────────────────────────────────────
echo "▶ Cleaning up IAM role and instance profile..."
aws iam remove-role-from-instance-profile \
  --instance-profile-name "aws-cert-study-lab03-profile" \
  --role-name "aws-cert-study-lab03-role" 2>/dev/null || true
aws iam delete-instance-profile \
  --instance-profile-name "aws-cert-study-lab03-profile" 2>/dev/null || true
aws iam detach-role-policy \
  --role-name "aws-cert-study-lab03-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
aws iam detach-role-policy \
  --role-name "aws-cert-study-lab03-role" \
  --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite" 2>/dev/null || true
aws iam delete-role \
  --role-name "aws-cert-study-lab03-role" 2>/dev/null || true
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
  --output table --region "$AWS_REGION" 2>/dev/null || true
echo ""
