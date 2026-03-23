# AWS Cost Explorer Dashboard

![Status](https://img.shields.io/badge/status-complete-brightgreen?style=flat)
![Stack](https://img.shields.io/badge/stack-Cost_Explorer_%C2%B7_Python_%C2%B7_boto3-FF9900?style=flat&logo=amazon-aws)
![Phase](https://img.shields.io/badge/FinOps-Inform_Phase-00B4D8?style=flat)

Pull real AWS cost data from the Cost Explorer API, analyze it, and display a formatted terminal dashboard — the foundation of the FinOps Inform phase.

> **Lab 05 Integration**: Run this alongside Lab 05 (ALB + Auto Scaling) to see real-time cost impact of auto-scaling events.

---

## What This Builds

```
AWS Cost Explorer API
        │
        ▼
  query-costs.sh          # Raw data via AWS CLI
        │
        ▼
   dashboard.py           # Formatted terminal dashboard
        │
        ├── Cost by Service (last 30 days)
        ├── Cost by Project Tag (showback report)
        ├── Daily trend (7-day sparkline)
        └── Top 3 optimization recommendations
```

---

## What You'll Learn

- **Cost Explorer API** — `GetCostAndUsage`, `GetCostForecast`, `GetDimensionValues`
- **Showback vs Chargeback** — reporting costs back to teams by tag
- **FinOps Inform Phase** — building visibility before you can optimize
- **Cost Allocation Tags** — why tagging everything at creation matters
- **boto3 Cost Explorer client** — programmatic access to billing data

---

## Prerequisites

```bash
# AWS CLI v2
aws --version

# Python 3.8+ with boto3
python3 --version
pip install boto3

# Cost Explorer must be enabled (it's on by default, verify below)
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --query 'ResultsByTime[0].Total'
```

> Cost Explorer has a small API cost: **$0.01 per API request**. The scripts in this project make ~5 requests total per run.

---

## Setup

```bash
# 1. Set your account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION=us-east-1

# 2. (Optional) Create a restricted IAM policy for Cost Explorer reads
bash scripts/setup.sh

# 3. Query your costs via CLI
bash scripts/query-costs.sh

# 4. Launch the full Python dashboard
pip install boto3
python3 dashboard.py
python3 dashboard.py --days 7   # Last 7 days
python3 dashboard.py --days 90  # Last quarter
```

---

## Scripts

| Script | What it does |
|--------|-------------|
| `scripts/setup.sh` | Creates a read-only IAM policy for Cost Explorer access |
| `scripts/query-costs.sh` | Queries costs via AWS CLI — by service and by tag |
| `scripts/cleanup.sh` | Removes the IAM policy created in setup |
| `dashboard.py` | Full Python dashboard with ASCII charts and recommendations |

---

## Sample Output

```
╔══════════════════════════════════════════════════════════╗
║           AWS COST EXPLORER DASHBOARD                    ║
║                  Last 30 Days                            ║
╚══════════════════════════════════════════════════════════╝

  Total Spend:    $2.47
  Daily Average:  $0.08
  MoM Change:     +12.4%
  Forecast (EOM): $2.80

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  COST BY SERVICE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  EC2            $1.20  ████████████░░░░░░░░  48.6%
  RDS            $0.80  ████████░░░░░░░░░░░░  32.4%
  S3             $0.30  ███░░░░░░░░░░░░░░░░░  12.1%
  CloudFront     $0.12  █░░░░░░░░░░░░░░░░░░░   4.9%
  Other          $0.05  ░░░░░░░░░░░░░░░░░░░░   2.0%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  COST BY PROJECT TAG (Showback)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  aws-cert-study   $2.47  ████████████████████  100%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TOP RECOMMENDATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. EC2 is your top cost driver — run cleanup.sh after each lab session
  2. RDS instances cost money even when idle — stop or delete between labs
  3. Enable S3 Intelligent-Tiering if objects are rarely accessed
```

---

## FinOps Integration with Lab 05

When running Lab 05 (ALB + Auto Scaling), use this dashboard to:

1. **Baseline before deploy** — record current costs
2. **Monitor during lab** — watch EC2 costs increase as ASG scales out
3. **Verify after cleanup** — confirm costs return to baseline

```bash
# Run before Lab 05 deploy
python3 dashboard.py --days 1 > before-lab05.txt

# After Lab 05 runs for an hour
python3 dashboard.py --days 1 > after-lab05.txt

# Diff to see exact lab cost
diff before-lab05.txt after-lab05.txt
```

---

## Expected Costs

| Operation | Cost |
|-----------|------|
| Cost Explorer API calls (5 per run) | ~$0.05 |
| IAM policy creation | Free |
| Total for this project | < $0.10 |

> Cost Explorer data is updated once per day. Real-time cost data requires AWS Cost & Usage Reports (CUR).

---

## Cleanup

```bash
bash scripts/cleanup.sh
```

Removes the IAM policy created in setup. Cost Explorer itself cannot be disabled — it is always-on.

---

## Key Concepts

| Concept | Exam Relevance |
|---------|---------------|
| Cost Explorer API | SAA-C03 · CLF-C02 |
| Cost allocation tags | SAA-C03 · FinOps |
| Showback vs chargeback | FinOps Foundation |
| Cost forecasting | SAA-C03 · FinOps |
| Granularity (DAILY/MONTHLY/HOURLY) | Cost Explorer specifics |

---

## Links

- [AWS Cost Explorer docs](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html)
- [boto3 CE client](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ce.html)
- [Lab 05 — ALB + Auto Scaling](../../projects/05-multi-tier-alb-autoscaling/README.md)
- [Budget Alerts & Anomaly Detection](../budget-alerts-anomaly-detection/README.md)
