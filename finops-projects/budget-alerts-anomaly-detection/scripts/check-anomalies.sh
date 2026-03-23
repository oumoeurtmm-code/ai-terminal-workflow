#!/bin/bash
# =============================================================================
# Budget Alerts & Anomaly Detection — Check Status
# Shows active anomalies and budget utilization with color-coded output
# =============================================================================

set -euo pipefail

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo "======================================================"
echo -e "  ${BOLD}Financial Health Check${NC}"
echo "  Account: $AWS_ACCOUNT_ID"
echo "======================================================"

# ── Budget utilization ────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}BUDGET STATUS${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────${NC}"

aws budgets describe-budgets \
  --account-id "$AWS_ACCOUNT_ID" \
  --query 'Budgets[*].{Name:BudgetName,Limit:BudgetLimit.Amount,Actual:CalculatedSpend.ActualSpend.Amount,Forecasted:CalculatedSpend.ForecastedSpend.Amount}' \
  --output json 2>/dev/null | python3 -c "
import json, sys

RED = '\033[0;31m'
YELLOW = '\033[0;33m'
GREEN = '\033[0;32m'
BOLD = '\033[1m'
NC = '\033[0m'

data = json.load(sys.stdin)
if not data:
    print('  No budgets found. Run: bash scripts/create-budgets.sh')
    sys.exit(0)

for b in data:
    name = b['Name']
    limit = float(b.get('Limit', 0))
    actual = float(b.get('Actual') or 0)
    forecast = float(b.get('Forecasted') or 0)
    pct = (actual / limit * 100) if limit > 0 else 0

    if pct >= 100:
        color = RED
        status = 'OVER BUDGET'
    elif pct >= 80:
        color = RED
        status = 'HIGH'
    elif pct >= 60:
        color = YELLOW
        status = 'MEDIUM'
    else:
        color = GREEN
        status = 'OK'

    bar_filled = int(pct / 5)
    bar = '█' * min(bar_filled, 20) + '░' * (20 - min(bar_filled, 20))
    print(f'  {name}')
    print(f'    Actual:    \${actual:.2f} / \${limit:.2f}  ({pct:.1f}%)')
    print(f'    Forecast:  \${forecast:.2f}')
    print(f'    Status:    {color}{status}{NC}  {color}{bar}{NC}')
    print()
" 2>/dev/null || echo -e "  ${YELLOW}Could not retrieve budgets${NC}"

# ── Anomaly detection ─────────────────────────────────────────────────────────
echo -e "  ${BOLD}ANOMALY DETECTION${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────${NC}"

SEVEN_DAYS_AGO=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

ANOMALIES=$(aws ce get-anomalies \
  --date-interval "StartDate=${SEVEN_DAYS_AGO},EndDate=${TODAY}" \
  --query 'Anomalies[*].{Service:AnomalyScore.MaxScore,Impact:Impact.TotalImpact,Start:AnomalyStartDate,Status:Feedback}' \
  --output json 2>/dev/null || echo "[]")

echo "$ANOMALIES" | python3 -c "
import json, sys

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
NC = '\033[0m'

data = json.load(sys.stdin)
if not data:
    print(f'  {GREEN}No anomalies detected in the last 7 days{NC}')
else:
    print(f'  {RED}ANOMALIES FOUND:{NC}')
    for a in data:
        impact = float(a.get('Impact') or 0)
        start = a.get('Start', 'unknown')
        print(f'    Impact: \${impact:.2f}  |  Detected: {start}')
" 2>/dev/null || echo -e "  ${YELLOW}Anomaly data unavailable (monitor may still be initializing)${NC}"

echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────${NC}"
echo -e "  Run ${CYAN}python3 monitor.py${NC} for the full dashboard"
echo -e "  Run ${CYAN}bash scripts/cleanup.sh${NC} to remove all guardrails"
echo ""
