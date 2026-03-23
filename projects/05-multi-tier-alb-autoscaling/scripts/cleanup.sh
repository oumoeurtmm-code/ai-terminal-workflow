#!/bin/bash
# =============================================================================
# Lab 05 — Multi-Tier Architecture: ALB + Auto Scaling — Cleanup
# Destroys ALL resources in reverse order to prevent orphaned dependencies
# =============================================================================

set -euo pipefail

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export LAB_NAME="lab05-alb-autoscaling"

# Load env from deploy (if available)
[[ -f /tmp/lab05-env.sh ]] && source /tmp/lab05-env.sh && echo "Loaded env from /tmp/lab05-env.sh"

echo ""
echo "======================================================"
echo "  Lab 05 — Cleanup"
echo "======================================================"
echo "  Account : $AWS_ACCOUNT_ID"
echo "  Region  : $AWS_DEFAULT_REGION"
echo ""

# ── Discover resources by tag if env not set ──────────────────────────────────
if [[ -z "${ASG_NAME:-}" ]]; then
  ASG_NAME="${LAB_NAME}-asg"
  echo "  Note: ASG_NAME not set in env, using default: $ASG_NAME"
fi

if [[ -z "${ALB_NAME:-}" ]]; then
  ALB_NAME="${LAB_NAME}-alb"
fi

if [[ -z "${TG_NAME:-}" ]]; then
  TG_NAME="${LAB_NAME}-tg"
fi

if [[ -z "${LT_NAME:-}" ]]; then
  LT_NAME="${LAB_NAME}-lt"
fi

# ── Step 1: Delete Auto Scaling Group ────────────────────────────────────────
echo "[1/10] Deleting Auto Scaling Group: $ASG_NAME"

aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --force-delete 2>/dev/null && \
  echo "  Deleted ASG: $ASG_NAME" || \
  echo "  ASG not found (skipping): $ASG_NAME"

echo "  Waiting for instances to terminate..."
sleep 15

# ── Step 2: Delete Launch Template ───────────────────────────────────────────
echo ""
echo "[2/10] Deleting Launch Template: $LT_NAME"

LT_ID="${LT_ID:-$(aws ec2 describe-launch-templates \
  --filters "Name=launch-template-name,Values=${LT_NAME}" \
  --query 'LaunchTemplates[0].LaunchTemplateId' \
  --output text 2>/dev/null)}"

if [[ -n "$LT_ID" && "$LT_ID" != "None" ]]; then
  aws ec2 delete-launch-template --launch-template-id "$LT_ID" 2>/dev/null && \
    echo "  Deleted: $LT_ID" || echo "  Not found: $LT_ID"
else
  echo "  Launch template not found"
fi

# ── Step 3: Delete CloudWatch Alarms ─────────────────────────────────────────
echo ""
echo "[3/10] Deleting CloudWatch alarms..."

aws cloudwatch delete-alarms \
  --alarm-names "${LAB_NAME}-high-cpu" 2>/dev/null && \
  echo "  Deleted alarm: ${LAB_NAME}-high-cpu" || \
  echo "  Alarm not found (skipping)"

# ── Step 4: Delete ALB Listener ──────────────────────────────────────────────
echo ""
echo "[4/10] Deleting ALB Listener..."

ALB_ARN_LOOKUP=$(aws elbv2 describe-load-balancers \
  --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>/dev/null || echo "")

if [[ -n "$ALB_ARN_LOOKUP" && "$ALB_ARN_LOOKUP" != "None" ]]; then
  ALB_ARN="${ALB_ARN:-$ALB_ARN_LOOKUP}"
  LISTENERS=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --query 'Listeners[*].ListenerArn' \
    --output text 2>/dev/null || echo "")
  for listener in $LISTENERS; do
    aws elbv2 delete-listener --listener-arn "$listener" 2>/dev/null && \
      echo "  Deleted listener: $listener"
  done
fi

# ── Step 5: Delete ALB ────────────────────────────────────────────────────────
echo ""
echo "[5/10] Deleting Application Load Balancer: $ALB_NAME"

if [[ -n "${ALB_ARN:-}" && "$ALB_ARN" != "None" ]]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" 2>/dev/null && \
    echo "  Deleted ALB: $ALB_NAME" || echo "  ALB already deleted"
  echo "  Waiting for ALB to finish deleting..."
  sleep 20
fi

# ── Step 6: Delete Target Group ───────────────────────────────────────────────
echo ""
echo "[6/10] Deleting Target Group: $TG_NAME"

TG_ARN="${TG_ARN:-$(aws elbv2 describe-target-groups \
  --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null)}"

if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN" 2>/dev/null && \
    echo "  Deleted: $TG_ARN" || echo "  Not found: $TG_NAME"
fi

# ── Step 7: Delete Security Groups ───────────────────────────────────────────
echo ""
echo "[7/10] Deleting security groups..."

VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${LAB_NAME}-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null)}"

if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  for SG_NAME in "${LAB_NAME}-ec2-sg" "${LAB_NAME}-alb-sg"; do
    SG_ID=$(aws ec2 describe-security-groups \
      --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
      --query 'SecurityGroups[0].GroupId' \
      --output text 2>/dev/null)
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
      aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null && \
        echo "  Deleted: $SG_NAME ($SG_ID)" || echo "  Could not delete: $SG_NAME"
    fi
  done
fi

# ── Step 8: Delete Route Tables + Subnets ────────────────────────────────────
echo ""
echo "[8/10] Deleting subnets and route tables..."

if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  # Delete non-main route tables
  RTB_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId' \
    --output text 2>/dev/null)

  for rtb in $RTB_IDS; do
    # Disassociate first
    ASSOC_IDS=$(aws ec2 describe-route-tables \
      --route-table-ids "$rtb" \
      --query 'RouteTables[0].Associations[*].RouteTableAssociationId' \
      --output text 2>/dev/null)
    for assoc in $ASSOC_IDS; do
      aws ec2 disassociate-route-table --association-id "$assoc" 2>/dev/null || true
    done
    aws ec2 delete-route-table --route-table-id "$rtb" 2>/dev/null && \
      echo "  Deleted route table: $rtb" || true
  done

  # Delete subnets
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].SubnetId' \
    --output text)
  for subnet in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null && \
      echo "  Deleted subnet: $subnet" || echo "  Could not delete subnet: $subnet"
  done
fi

# ── Step 9: Detach + Delete IGW, then VPC ────────────────────────────────────
echo ""
echo "[9/10] Deleting Internet Gateway and VPC..."

if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  IGW_IDS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query 'InternetGateways[*].InternetGatewayId' \
    --output text)
  for igw in $IGW_IDS; do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" 2>/dev/null && \
      echo "  Deleted IGW: $igw"
  done

  aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null && \
    echo "  Deleted VPC: $VPC_ID" || echo "  Could not delete VPC: $VPC_ID"
fi

# ── Step 10: Delete SNS Topic ─────────────────────────────────────────────────
echo ""
echo "[10/10] Deleting SNS topic..."

SNS_NAME="${LAB_NAME}-notifications"
SNS_ARN="${SNS_ARN:-arn:aws:sns:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:${SNS_NAME}}"

aws sns delete-topic --topic-arn "$SNS_ARN" 2>/dev/null && \
  echo "  Deleted SNS: $SNS_NAME" || echo "  SNS topic not found"

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  Verification — Resources tagged Lab=05-alb-autoscaling"
echo "======================================================"

REMAINING=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Lab,Values=05-alb-autoscaling" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text 2>/dev/null)

if [[ -z "$REMAINING" ]]; then
  echo "  All lab resources removed — no ongoing costs"
else
  echo "  WARNING: These resources may still exist:"
  echo "$REMAINING" | tr '\t' '\n' | sed 's/^/  /'
fi

# Cleanup temp env file
rm -f /tmp/lab05-env.sh

echo ""
echo "======================================================"
echo "  Cleanup Complete"
echo "======================================================"
echo ""
echo "  Also check FinOps guardrails:"
echo "    cd finops-projects/budget-alerts-anomaly-detection"
echo "    bash scripts/cleanup.sh"
echo ""
