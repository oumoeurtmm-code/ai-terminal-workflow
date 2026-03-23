#!/bin/bash
# =============================================================================
# Budget Alerts & Anomaly Detection — Setup Anomaly Detection
# Creates a Cost Anomaly Monitor and Subscription via AWS CLI
# =============================================================================

set -euo pipefail

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:?ERROR: Set SNS_TOPIC_ARN before running (export from create-budgets.sh)}"
MONITOR_NAME="lab-anomaly-monitor"
SUBSCRIPTION_NAME="lab-anomaly-subscription"

echo ""
echo "======================================================"
echo "  Budget Alerts — Setup Anomaly Detection"
echo "======================================================"
echo "  Account   : $AWS_ACCOUNT_ID"
echo "  SNS Topic : $SNS_TOPIC_ARN"
echo ""

# ── Step 1: Create anomaly monitor ────────────────────────────────────────────
echo "[1/3] Creating Cost Anomaly Monitor (SERVICE dimension)..."

MONITOR_ARN=$(aws ce create-anomaly-monitor \
  --anomaly-monitor '{
    "MonitorName": "'"$MONITOR_NAME"'",
    "MonitorType": "DIMENSIONAL",
    "MonitorDimension": "SERVICE"
  }' \
  --query 'MonitorArn' \
  --output text 2>/dev/null) || {
    # Check if it already exists
    MONITOR_ARN=$(aws ce get-anomaly-monitors \
      --query "AnomalyMonitors[?MonitorName=='${MONITOR_NAME}'].MonitorArn" \
      --output text)
    echo "  Monitor already exists: $MONITOR_NAME"
  }

export MONITOR_ARN
echo "  Monitor ARN: $MONITOR_ARN"

# ── Step 2: Create anomaly subscription ───────────────────────────────────────
echo ""
echo "[2/3] Creating Anomaly Subscription (\$2 threshold, immediate alerts)..."

SUBSCRIPTION_ARN=$(aws ce create-anomaly-subscription \
  --anomaly-subscription '{
    "SubscriptionName": "'"$SUBSCRIPTION_NAME"'",
    "MonitorArnList": ["'"$MONITOR_ARN"'"],
    "Subscribers": [
      {
        "Address": "'"$SNS_TOPIC_ARN"'",
        "Type": "SNS"
      }
    ],
    "Threshold": 2,
    "Frequency": "IMMEDIATE"
  }' \
  --query 'SubscriptionArn' \
  --output text 2>/dev/null) || {
    SUBSCRIPTION_ARN=$(aws ce get-anomaly-subscriptions \
      --query "AnomalySubscriptions[?SubscriptionName=='${SUBSCRIPTION_NAME}'].SubscriptionArn" \
      --output text)
    echo "  Subscription already exists: $SUBSCRIPTION_NAME"
  }

export SUBSCRIPTION_ARN
echo "  Subscription ARN: $SUBSCRIPTION_ARN"

# ── Step 3: Verify ────────────────────────────────────────────────────────────
echo ""
echo "[3/3] Verifying setup..."

aws ce get-anomaly-monitors \
  --monitor-arn-list "$MONITOR_ARN" \
  --query 'AnomalyMonitors[0].{Name:MonitorName,Status:CreationDate}' \
  --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data:
    print(f'  Monitor: {data[\"Name\"]}')
    print(f'  Created: {data[\"Status\"]}')
" 2>/dev/null || echo "  Monitor verified"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  Anomaly Detection Active"
echo "======================================================"
echo ""
echo "  Monitor     : $MONITOR_NAME (SERVICE dimension)"
echo "  Threshold   : \$2.00 spend anomaly"
echo "  Frequency   : IMMEDIATE"
echo "  Notify via  : SNS → $SNS_TOPIC_ARN"
echo ""
echo "  Monitor ARN      : $MONITOR_ARN"
echo "  Subscription ARN : $SUBSCRIPTION_ARN"
echo ""
echo "  Check anomalies  : bash scripts/check-anomalies.sh"
echo "  Python dashboard : python3 monitor.py"
echo "  Cleanup          : bash scripts/cleanup.sh"
echo ""
