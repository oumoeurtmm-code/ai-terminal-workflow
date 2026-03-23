#!/bin/bash
# =============================================================================
# AWS Cost Explorer Dashboard — Query Costs
# Pulls cost data by service and by Project tag using AWS CLI
# =============================================================================

set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  echo ""
  echo "Usage: bash scripts/query-costs.sh [--days N]"
  echo ""
  echo "Options:"
  echo "  --days N    Number of days to query (default: 30)"
  echo "  --help      Show this help"
  echo ""
  echo "Examples:"
  echo "  bash scripts/query-costs.sh"
  echo "  bash scripts/query-costs.sh --days 7"
  echo "  bash scripts/query-costs.sh --days 90"
  echo ""
}

# ── Parse args ────────────────────────────────────────────────────────────────
DAYS=30
while [[ $# -gt 0 ]]; do
  case $1 in
    --days) DAYS="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

# ── Date range ────────────────────────────────────────────────────────────────
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${DAYS}d +%Y-%m-%d)

echo ""
echo "======================================================"
echo "  AWS Cost Explorer — Query Results"
echo "  Period: $START_DATE → $END_DATE ($DAYS days)"
echo "======================================================"

# ── Query 1: Total cost ───────────────────────────────────────────────────────
echo ""
echo "── TOTAL COST ──────────────────────────────────────"

TOTAL=$(aws ce get-cost-and-usage \
  --time-period "Start=${START_DATE},End=${END_DATE}" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --query 'ResultsByTime[*].Total.BlendedCost.Amount' \
  --output json | python3 -c "
import json, sys
amounts = json.load(sys.stdin)
total = sum(float(a) for a in amounts)
print(f'\${total:.4f}')
")

echo "  Total (${DAYS}d): $TOTAL"

# ── Query 2: Cost by service ──────────────────────────────────────────────────
echo ""
echo "── COST BY SERVICE ─────────────────────────────────"

aws ce get-cost-and-usage \
  --time-period "Start=${START_DATE},End=${END_DATE}" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[*].Groups[*].{Service:Keys[0],Cost:Metrics.BlendedCost.Amount}' \
  --output json | python3 -c "
import json, sys
data = json.load(sys.stdin)
rows = []
for month in data:
    for item in month:
        rows.append((item['Service'], float(item['Cost'])))

# Aggregate by service
from collections import defaultdict
totals = defaultdict(float)
for svc, cost in rows:
    totals[svc] += cost

sorted_svcs = sorted(totals.items(), key=lambda x: x[1], reverse=True)
total = sum(v for _, v in sorted_svcs)

print(f'  {\"SERVICE\":<40} {\"COST\":>10}  {\"SHARE\":>7}')
print(f'  {\"-\"*40} {\"-\"*10}  {\"-\"*7}')
for svc, cost in sorted_svcs[:10]:
    if cost > 0.001:
        pct = (cost/total*100) if total > 0 else 0
        bar = '█' * int(pct/5) + '░' * (20 - int(pct/5))
        print(f'  {svc:<40} \${cost:>9.4f}  {pct:>6.1f}%')
"

# ── Query 3: Cost by Project tag ──────────────────────────────────────────────
echo ""
echo "── COST BY PROJECT TAG (Showback) ──────────────────"

aws ce get-cost-and-usage \
  --time-period "Start=${START_DATE},End=${END_DATE}" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Project \
  --query 'ResultsByTime[*].Groups[*].{Tag:Keys[0],Cost:Metrics.BlendedCost.Amount}' \
  --output json | python3 -c "
import json, sys
data = json.load(sys.stdin)
rows = []
for month in data:
    for item in month:
        tag = item['Tag'].replace('Project\$', '') or '(untagged)'
        rows.append((tag, float(item['Cost'])))

from collections import defaultdict
totals = defaultdict(float)
for tag, cost in rows:
    totals[tag] += cost

sorted_tags = sorted(totals.items(), key=lambda x: x[1], reverse=True)
print(f'  {\"PROJECT TAG\":<30} {\"COST\":>10}')
print(f'  {\"-\"*30} {\"-\"*10}')
for tag, cost in sorted_tags:
    if cost > 0.001:
        print(f'  {tag:<30} \${cost:>9.4f}')
" 2>/dev/null || echo "  (No tag data — ensure resources are tagged with Project=aws-cert-study)"

# ── Query 4: 7-day daily trend ────────────────────────────────────────────────
echo ""
echo "── 7-DAY DAILY TREND ───────────────────────────────"

TREND_START=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)

aws ce get-cost-and-usage \
  --time-period "Start=${TREND_START},End=${END_DATE}" \
  --granularity DAILY \
  --metrics BlendedCost \
  --query 'ResultsByTime[*].{Date:TimePeriod.Start,Cost:Total.BlendedCost.Amount}' \
  --output json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'  {\"DATE\":<12} {\"COST\":>10}  TREND')
print(f'  {\"-\"*12} {\"-\"*10}  {\"-\"*20}')
for row in data:
    cost = float(row['Cost'])
    bars = int(cost * 200) if cost > 0 else 0
    bar = '█' * min(bars, 20)
    print(f'  {row[\"Date\"]:<12} \${cost:>9.4f}  {bar}')
"

echo ""
echo "======================================================"
echo "  For a full dashboard: python3 dashboard.py"
echo "======================================================"
echo ""
