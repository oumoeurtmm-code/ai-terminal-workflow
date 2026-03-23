#!/bin/bash
# =============================================================================
# Budget Alerts & Anomaly Detection — Cleanup
# Removes all budgets, anomaly monitors, subscriptions, and SNS topic
# =============================================================================

set -euo pipefail

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNS_TOPIC_NAME="aws-cert-study-budget-alerts"
SNS_TOPIC_ARN="arn:aws:sns:${AWS_DEFAULT_REGION:-us-east-1}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"

echo ""
echo "======================================================"
echo "  Budget Alerts & Anomaly Detection — Cleanup"
echo "======================================================"
echo "  Account: $AWS_ACCOUNT_ID"
echo ""

# ── Step 1: Delete budgets ────────────────────────────────────────────────────
echo "[1/4] Deleting budgets..."

for BUDGET_NAME in "aws-cert-study-monthly" "aws-cert-study-project" "aws-cert-study-ec2"; do
  aws budgets delete-budget \
    --account-id "$AWS_ACCOUNT_ID" \
    --budget-name "$BUDGET_NAME" 2>/dev/null && \
    echo "  Deleted: $BUDGET_NAME" || \
    echo "  Not found (skipping): $BUDGET_NAME"
done

# ── Step 2: Delete anomaly subscriptions ──────────────────────────────────────
echo ""
echo "[2/4] Deleting anomaly subscriptions..."

SUBSCRIPTION_ARNS=$(aws ce get-anomaly-subscriptions \
  --query 'AnomalySubscriptions[*].SubscriptionArn' \
  --output text 2>/dev/null || echo "")

if [[ -n "$SUBSCRIPTION_ARNS" ]]; then
  for arn in $SUBSCRIPTION_ARNS; do
    aws ce delete-anomaly-subscription --subscription-arn "$arn" 2>/dev/null && \
      echo "  Deleted subscription: $arn" || \
      echo "  Could not delete: $arn"
  done
else
  echo "  No anomaly subscriptions found"
fi

# ── Step 3: Delete anomaly monitors ───────────────────────────────────────────
echo ""
echo "[3/4] Deleting anomaly monitors..."

MONITOR_ARNS=$(aws ce get-anomaly-monitors \
  --query 'AnomalyMonitors[*].MonitorArn' \
  --output text 2>/dev/null || echo "")

if [[ -n "$MONITOR_ARNS" ]]; then
  for arn in $MONITOR_ARNS; do
    aws ce delete-anomaly-monitor --monitor-arn "$arn" 2>/dev/null && \
      echo "  Deleted monitor: $arn" || \
      echo "  Could not delete: $arn"
  done
else
  echo "  No anomaly monitors found"
fi

# ── Step 4: Delete SNS topic ──────────────────────────────────────────────────
echo ""
echo "[4/4] Deleting SNS topic..."

aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null && \
  echo "  Deleted: $SNS_TOPIC_NAME" || \
  echo "  SNS topic not found (already deleted or never created)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  Cleanup Complete"
echo "======================================================"
echo ""
echo "  Removed:"
echo "    3 AWS Budgets"
echo "    Anomaly monitor + subscription"
echo "    SNS topic: $SNS_TOPIC_NAME"
echo ""
echo "  All guardrails removed — no ongoing costs from this project"
echo ""

# Verify budgets gone
REMAINING=$(aws budgets describe-budgets \
  --account-id "$AWS_ACCOUNT_ID" \
  --query 'Budgets[?starts_with(BudgetName, `aws-cert-study`)].BudgetName' \
  --output text 2>/dev/null || echo "")

if [[ -n "$REMAINING" ]]; then
  echo "  WARNING: Some budgets may still exist: $REMAINING"
fi
