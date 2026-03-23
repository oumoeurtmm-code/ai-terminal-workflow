#!/bin/bash
# =============================================================================
# AWS Cost Explorer Dashboard — Cleanup
# Removes the IAM policy created in setup.sh
# =============================================================================

set -euo pipefail

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_NAME="CostExplorerReadOnly-LabPolicy"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

echo ""
echo "======================================================"
echo "  AWS Cost Explorer Dashboard — Cleanup"
echo "======================================================"
echo ""

# ── Remove IAM policy ─────────────────────────────────────────────────────────
echo "[1/2] Deleting IAM policy: $POLICY_NAME"

# Detach from any entities first
aws iam list-entities-for-policy \
  --policy-arn "$POLICY_ARN" \
  --query 'PolicyUsers[*].UserName' \
  --output text 2>/dev/null | tr '\t' '\n' | while read -r user; do
    [[ -n "$user" ]] && aws iam detach-user-policy --user-name "$user" --policy-arn "$POLICY_ARN" && echo "  Detached from user: $user"
  done

aws iam list-entities-for-policy \
  --policy-arn "$POLICY_ARN" \
  --query 'PolicyRoles[*].RoleName' \
  --output text 2>/dev/null | tr '\t' '\n' | while read -r role; do
    [[ -n "$role" ]] && aws iam detach-role-policy --role-name "$role" --policy-arn "$POLICY_ARN" && echo "  Detached from role: $role"
  done

aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null && \
  echo "  Deleted: $POLICY_NAME" || \
  echo "  Policy not found (already deleted or never created)"

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "[2/2] Verification..."

aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null && \
  echo "  WARNING: Policy still exists" || \
  echo "  Confirmed: Policy does not exist"

echo ""
echo "======================================================"
echo "  Cleanup Complete"
echo "======================================================"
echo ""
echo "  Note: Cost Explorer cannot be disabled — it is always-on."
echo "  API call costs (~\$0.01/call) stop when you stop calling it."
echo ""
