#!/bin/bash
# =============================================================================
# AWS Cost Explorer Dashboard — Setup
# Creates a read-only IAM policy for Cost Explorer API access
# =============================================================================

set -euo pipefail

# ── Variables ────────────────────────────────────────────────────────────────
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
POLICY_NAME="CostExplorerReadOnly-LabPolicy"

echo ""
echo "======================================================"
echo "  AWS Cost Explorer Dashboard — Setup"
echo "======================================================"
echo "  Account : $AWS_ACCOUNT_ID"
echo "  Region  : $AWS_DEFAULT_REGION"
echo ""

# ── Step 1: Create IAM policy ─────────────────────────────────────────────────
echo "[1/3] Creating Cost Explorer read-only IAM policy..."

POLICY_DOCUMENT='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CostExplorerReadOnly",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "ce:GetDimensionValues",
        "ce:GetTags",
        "ce:GetUsageForecast",
        "ce:ListCostAllocationTags"
      ],
      "Resource": "*"
    }
  ]
}'

POLICY_ARN=$(aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOCUMENT" \
  --description "Read-only access to Cost Explorer API for lab dashboard" \
  --query 'Policy.Arn' \
  --output text 2>/dev/null) || {
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    echo "  Policy already exists — using: $POLICY_ARN"
  }

export CE_POLICY_ARN="$POLICY_ARN"
echo "  Policy ARN: $CE_POLICY_ARN"

# ── Step 2: Verify Cost Explorer is accessible ────────────────────────────────
echo ""
echo "[2/3] Verifying Cost Explorer API access..."

TEST_START=$(date -d '2 days ago' +%Y-%m-%d 2>/dev/null || date -v-2d +%Y-%m-%d)
TEST_END=$(date +%Y-%m-%d)

aws ce get-cost-and-usage \
  --time-period "Start=${TEST_START},End=${TEST_END}" \
  --granularity DAILY \
  --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
  --output text > /dev/null && echo "  Cost Explorer API: accessible" || {
    echo "  WARNING: Could not reach Cost Explorer API — check IAM permissions"
  }

# ── Step 3: Export environment variables ──────────────────────────────────────
echo ""
echo "[3/3] Environment setup..."

export CE_POLICY_ARN
export AWS_ACCOUNT_ID
export AWS_DEFAULT_REGION

echo ""
echo "======================================================"
echo "  Setup Complete"
echo "======================================================"
echo ""
echo "  Policy ARN : $CE_POLICY_ARN"
echo ""
echo "  Next steps:"
echo "    bash scripts/query-costs.sh     # Query costs via CLI"
echo "    python3 dashboard.py            # Launch terminal dashboard"
echo ""
echo "  Cleanup when done:"
echo "    bash scripts/cleanup.sh"
echo ""
