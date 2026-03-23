#!/bin/bash
# =============================================================================
# Lab 05 — FinOps Integration Check
# Sets up cost guardrails and shows current lab cost impact
# Integrates with finops-projects/aws-cost-explorer-dashboard/
#             and finops-projects/budget-alerts-anomaly-detection/
# =============================================================================

set -euo pipefail

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Load lab env if available
[[ -f /tmp/lab05-env.sh ]] && source /tmp/lab05-env.sh

# Paths to FinOps projects (relative to this script's location)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COST_EXPLORER_DIR="${WORKSPACE_ROOT}/finops-projects/aws-cost-explorer-dashboard"
BUDGET_DIR="${WORKSPACE_ROOT}/finops-projects/budget-alerts-anomaly-detection"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo "======================================================"
echo -e "  ${BOLD}Lab 05 — FinOps Check${NC}"
echo "======================================================"
echo "  Account : $AWS_ACCOUNT_ID"
echo "  Region  : $AWS_DEFAULT_REGION"
echo ""

# ── Step 1: Set up budget guardrails ─────────────────────────────────────────
echo -e "  ${BOLD}[1/4] Budget Guardrails${NC}"

if [[ -f "${BUDGET_DIR}/scripts/create-budgets.sh" ]]; then
  EXISTING_BUDGET=$(aws budgets describe-budgets \
    --account-id "$AWS_ACCOUNT_ID" \
    --query 'Budgets[?BudgetName==`aws-cert-study-ec2`].BudgetName' \
    --output text 2>/dev/null || echo "")

  if [[ -n "$EXISTING_BUDGET" ]]; then
    echo -e "  ${GREEN}Budget guardrails already active${NC}"
  else
    echo -e "  ${YELLOW}No budget found — setting up guardrails now${NC}"
    echo "  (Set EMAIL_ADDRESS env var to receive alerts)"
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
      bash "${BUDGET_DIR}/scripts/create-budgets.sh"
    else
      echo -e "  ${YELLOW}Skipping budget creation — set EMAIL_ADDRESS first:${NC}"
      echo -e "  ${DIM}export EMAIL_ADDRESS=your@email.com${NC}"
      echo -e "  ${DIM}bash finops-projects/budget-alerts-anomaly-detection/scripts/create-budgets.sh${NC}"
    fi
  fi
else
  echo -e "  ${YELLOW}FinOps project not found at: $BUDGET_DIR${NC}"
fi

# ── Step 2: Current lab cost (today) ─────────────────────────────────────────
echo ""
echo -e "  ${BOLD}[2/4] Current Lab Cost (Today)${NC}"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

# Query cost for Lab=05-alb-autoscaling tag (may not appear until tomorrow due to CE lag)
TAGGED_COST=$(aws ce get-cost-and-usage \
  --time-period "Start=${YESTERDAY},End=${TODAY}" \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter '{"Tags":{"Key":"Lab","Values":["05-alb-autoscaling"]}}' \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
  --output text 2>/dev/null || echo "0")

echo "  Tagged lab cost (yesterday): \$$TAGGED_COST"
echo -e "  ${DIM}Note: Cost Explorer data has a ~24h delay. Check again tomorrow for today's charges.${NC}"

# ── Step 3: EC2 spend rate ────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}[3/4] EC2 Cost Rate${NC}"

# Show running instances in this lab
ASG_NAME="${ASG_NAME:-lab05-alb-autoscaling-asg}"
INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].DesiredCapacity' \
  --output text 2>/dev/null || echo "0")

echo "  Running instances (ASG desired): $INSTANCE_COUNT"

if [[ "$INSTANCE_COUNT" -gt 0 ]]; then
  # t3.micro costs ~$0.0104/hr in us-east-1
  HOURLY_RATE=$(echo "$INSTANCE_COUNT * 0.0104" | bc 2>/dev/null || echo "~$(($INSTANCE_COUNT * 1))¢/hr")
  DAILY_RATE=$(echo "$INSTANCE_COUNT * 0.0104 * 24" | bc 2>/dev/null || echo "calculating...")
  echo "  Estimated EC2 cost: \$$HOURLY_RATE/hr | \$$DAILY_RATE/day"
  echo "  (t3.micro @ \$0.0104/hr × $INSTANCE_COUNT instances)"

  if [[ "$INSTANCE_COUNT" -ge 3 ]]; then
    echo -e "  ${RED}WARNING: ASG is at max capacity — scale-in may not have completed${NC}"
    echo "  Run test-scaling.sh only if intentional. Cleanup when done."
  fi
fi

# ALB cost (always-on while deployed)
echo ""
echo "  ALB cost: ~\$0.008/hr (minimum) + \$0.008 per LCU-hour"
echo "  Combined estimate (2 instances + ALB): ~\$0.029/hr"

# ── Step 4: Cost optimization recommendations ─────────────────────────────────
echo ""
echo -e "  ${BOLD}[4/4] FinOps Recommendations${NC}"

echo -e "  ${CYAN}1.${NC} Run cleanup.sh as soon as you finish the lab — EC2 + ALB charges accumulate by the hour"
echo -e "  ${CYAN}2.${NC} If testing long-term: set ASG min=0 to stop all instances during off-hours"
echo -e "  ${CYAN}3.${NC} ALB charges even with 0 instances — delete the ALB when not in use"
echo -e "  ${CYAN}4.${NC} Use the Cost Explorer dashboard to see actual charges 24 hrs after the lab"

# Run Python dashboard if available
echo ""
if [[ -f "${COST_EXPLORER_DIR}/dashboard.py" ]] && command -v python3 &>/dev/null; then
  echo -e "  ${DIM}Launching Cost Explorer dashboard (--days 2)...${NC}"
  python3 "${COST_EXPLORER_DIR}/dashboard.py" --days 2 2>/dev/null || \
    echo -e "  ${YELLOW}Run manually: python3 finops-projects/aws-cost-explorer-dashboard/dashboard.py${NC}"
else
  echo -e "  For full cost breakdown: ${CYAN}python3 finops-projects/aws-cost-explorer-dashboard/dashboard.py${NC}"
fi

echo ""
echo "======================================================"
echo -e "  ${GREEN}FinOps check complete${NC}"
echo "======================================================"
echo ""
echo "  Clean up when done: bash scripts/cleanup.sh"
echo "  Check anomalies  : bash ${BUDGET_DIR}/scripts/check-anomalies.sh"
echo ""
