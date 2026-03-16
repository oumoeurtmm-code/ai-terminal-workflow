#!/bin/bash
set -euo pipefail

# ── AWS Lab 04: Cleanup ───────────────────────────────────────────────────────
# Destroys all resources created by deploy.sh in the correct teardown order
# Usage: bash scripts/cleanup.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS Lab 04 — Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

export AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_TAG="aws-cert-study"
FUNCTION_NAME="aws-cert-study-lab04-fn"
API_NAME="aws-cert-study-lab04-api"
ROLE_NAME="aws-cert-study-lab04-role"

# ── STEP 1: Delete API Gateway REST API ───────────────────────────────────────
echo "▶ Finding API Gateway REST API: $API_NAME..."
API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='${API_NAME}'].id" --output text \
  --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  echo "  Found API_ID=$API_ID — deleting..."
  aws apigateway delete-rest-api \
    --rest-api-id "$API_ID" \
    --region "$AWS_REGION" 2>/dev/null || true
  echo "  API Gateway REST API deleted."
else
  echo "  No API Gateway found."
fi

# ── STEP 2: Remove Lambda permission statements ────────────────────────────────
echo "▶ Removing Lambda permission statements..."
aws lambda remove-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "apigw-get-items" \
  --region "$AWS_REGION" 2>/dev/null || echo "  (GET permission not found)"
aws lambda remove-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "apigw-post-items" \
  --region "$AWS_REGION" 2>/dev/null || echo "  (POST permission not found)"
echo "  Lambda permissions removed."

# ── STEP 3: Delete Lambda function ────────────────────────────────────────────
echo "▶ Deleting Lambda function: $FUNCTION_NAME..."
aws lambda delete-function \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" 2>/dev/null || echo "  (function not found)"
echo "  Lambda function deleted."

# ── STEP 4: Detach policies and delete IAM role ───────────────────────────────
echo "▶ Cleaning up IAM role: $ROLE_NAME..."
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
aws iam delete-role \
  --role-name "$ROLE_NAME" 2>/dev/null || echo "  (role not found)"
echo "  IAM role deleted."

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
