# Budget Alerts & Anomaly Detection

![Status](https://img.shields.io/badge/status-complete-brightgreen?style=flat)
![Stack](https://img.shields.io/badge/stack-AWS_Budgets_%C2%B7_Cost_Anomaly_Detection_%C2%B7_SNS-FF9900?style=flat&logo=amazon-aws)
![Phase](https://img.shields.io/badge/FinOps-Operate_Phase-00B4D8?style=flat)

Set up financial guardrails before you need them — monthly budgets with threshold alerts and anomaly detection to catch unexpected spend before it becomes a problem.

> **Lab 05 Integration**: Auto Scaling can scale your bill as fast as it scales your fleet. This project protects Lab 05 from surprise charges by alerting you before costs spike.

---

## What This Builds

```
AWS Budgets
  ├── Monthly overall budget ($10 limit)
  │     ├── Alert at 80% ($8.00)
  │     └── Alert at 100% ($10.00)
  ├── Per-project budget (Project=aws-cert-study tag)
  └── EC2-specific budget ($5 limit — Lab 05 guard)

AWS Cost Anomaly Detection
  ├── Monitor: SERVICE dimension
  └── Subscription: alert on $2+ anomaly → SNS → Email/Slack

SNS Topic
  └── Email notifications + optional Slack webhook
```

---

## What You'll Learn

- **AWS Budgets** — creating cost and usage budgets with threshold alerts
- **Cost Anomaly Detection** — ML-based anomaly detection vs static thresholds
- **SNS for FinOps** — routing cost alerts to email and Slack
- **FinOps Operate Phase** — continuous governance, not just one-time optimization
- **Tag-based budgets** — filtering spend by Project tag for chargeback

---

## Prerequisites

```bash
# AWS CLI v2 configured
aws sts get-caller-identity

# Email address for alerts
export EMAIL_ADDRESS=your@email.com

# SNS topic will be created by setup script
```

> **IAM Permissions needed**: `budgets:*`, `ce:CreateAnomalyMonitor`, `ce:CreateAnomalySubscription`, `sns:*`

---

## Setup

```bash
# Step 1: Set variables
export EMAIL_ADDRESS=your@email.com
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION=us-east-1

# Step 2: Create budgets + SNS alerts
bash scripts/create-budgets.sh

# Step 3: Set up anomaly detection
bash scripts/setup-anomaly.sh

# Step 4: Verify everything is working
bash scripts/check-anomalies.sh

# Step 5: Python monitor (optional — with Slack integration)
pip install boto3
export SLACK_WEBHOOK_URL=https://hooks.slack.com/...   # optional
python3 monitor.py
```

---

## Scripts

| Script | What it does |
|--------|-------------|
| `scripts/create-budgets.sh` | Creates 3 budgets + SNS topic + email subscription |
| `scripts/setup-anomaly.sh` | Creates Cost Anomaly Monitor and Subscription |
| `scripts/check-anomalies.sh` | Queries active anomalies and budget utilization |
| `scripts/cleanup.sh` | Removes all budgets, monitors, subscriptions, SNS topic |
| `monitor.py` | Python financial health dashboard with Slack notifications |

---

## Sample Alert Email

```
AWS Budgets Notification
Budget Name: aws-cert-study-monthly
Account: 123456789012
Alert Type: ACTUAL
Alert Threshold: 80.00%
Threshold Type: PERCENTAGE
Notification Type: ACTUAL

Budgeted Amount: $10.00
Alert Amount: $8.00
Current Amount: $8.23

You've exceeded your budget threshold.
```

---

## Sample monitor.py Output

```
╔══════════════════════════════════════════════════════════╗
║          FINANCIAL HEALTH DASHBOARD                      ║
╚══════════════════════════════════════════════════════════╝

  BUDGET STATUS
  ─────────────────────────────────────────────────────────
  aws-cert-study-monthly      $2.47 / $10.00    25%  [GREEN]
  aws-cert-study-project      $2.47 / $8.00     31%  [GREEN]
  aws-cert-study-ec2          $1.20 / $5.00     24%  [GREEN]

  ANOMALY DETECTION
  ─────────────────────────────────────────────────────────
  No active anomalies detected.
  Monitor: lab-anomaly-monitor (SERVICE dimension)

  RISK ASSESSMENT
  ─────────────────────────────────────────────────────────
  Overall Risk:  LOW
  Action:        No immediate action required
  Tip:           Remember to run cleanup.sh after Lab 05
```

---

## FinOps Integration with Lab 05

Lab 05 deploys an Auto Scaling Group — instances can spin up automatically. This project protects you:

| Scenario | Protection |
|----------|-----------|
| ASG scales to max (3 instances) | EC2 budget alert at $5 |
| Forgot to run cleanup.sh | Anomaly detection catches overnight spend |
| Unexpected data transfer | SNS alert before bill arrives |

```bash
# Set up guardrails BEFORE deploying Lab 05
bash scripts/create-budgets.sh
bash scripts/setup-anomaly.sh

# Deploy Lab 05
bash ../../projects/05-multi-tier-alb-autoscaling/scripts/deploy.sh

# Monitor during lab
bash scripts/check-anomalies.sh

# After lab — clean up both
bash ../../projects/05-multi-tier-alb-autoscaling/scripts/cleanup.sh
bash scripts/cleanup.sh
```

---

## Expected Costs

| Resource | Cost |
|----------|------|
| AWS Budgets (first 2 budgets) | Free |
| AWS Budgets (3rd budget) | $0.02/day |
| Cost Anomaly Detection | Free |
| SNS (email notifications) | Free (first 1,000/month) |
| **Total per month** | ~$0.60 |

> Pro tip: Delete budgets after each lab session to stay in the free tier.

---

## Cleanup

```bash
bash scripts/cleanup.sh
```

Removes all budgets, anomaly monitors, subscriptions, and the SNS topic.

---

## Key Concepts

| Concept | Exam Relevance |
|---------|---------------|
| AWS Budgets | SAA-C03 · CLF-C02 · FinOps |
| Cost Anomaly Detection | SAA-C03 · FinOps |
| SNS for alerts | SAA-C03 |
| Budget vs actual vs forecast | FinOps Foundation |
| Tag-based budget filters | FinOps · SAA-C03 |

---

## Links

- [AWS Budgets docs](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Cost Anomaly Detection docs](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html)
- [Lab 05 — ALB + Auto Scaling](../../projects/05-multi-tier-alb-autoscaling/README.md)
- [Cost Explorer Dashboard](../aws-cost-explorer-dashboard/README.md)
