# Lab 05 — Multi-Tier Architecture: ALB + Auto Scaling

![Status](https://img.shields.io/badge/status-in_progress-blue?style=flat)
![Stack](https://img.shields.io/badge/stack-ALB_%C2%B7_ASG_%C2%B7_EC2_%C2%B7_CloudWatch_%C2%B7_SNS-FF9900?style=flat&logo=amazon-aws)
![FinOps](https://img.shields.io/badge/FinOps-Integrated-00B4D8?style=flat)

Deploy a production-grade multi-tier AWS architecture with an Application Load Balancer, Auto Scaling Group, and integrated FinOps cost monitoring. The capstone lab of the series.

---

## Table of Contents

1. [Architecture](#architecture)
2. [What You'll Build](#what-youll-build)
3. [What You'll Learn](#what-youll-learn)
4. [Prerequisites](#prerequisites)
5. [Lab Walkthrough](#lab-walkthrough)
6. [FinOps Integration](#finops-integration)
7. [GIF Recordings](#gif-recordings)
8. [Expected Costs](#expected-costs)
9. [Cleanup](#cleanup)
10. [Key Concepts](#key-concepts)

---

## Architecture

```
Internet
    │
    ▼ (HTTP :80)
┌─────────────────────────────────────────┐
│   Application Load Balancer             │
│   (internet-facing, 2 AZs)             │
└────────────┬────────────────────────────┘
             │ (forward to Target Group)
    ┌────────┴────────┐
    ▼                 ▼
┌───────────┐   ┌───────────┐
│ EC2 t3.micro│   │ EC2 t3.micro│  ← Auto Scaling Group
│ us-east-1a│   │ us-east-1b│    min=1, desired=2, max=3
│  httpd    │   │  httpd    │
└───────────┘   └───────────┘

CloudWatch ──→ CPU Alarm ──→ SNS Topic ──→ Email / Scaling Events

FinOps Layer:
  AWS Budgets ──→ SNS ──→ Email (if spend exceeds threshold)
  Cost Anomaly Detection ──→ SNS ──→ Alert on unexpected spend
  Cost Explorer Dashboard ──→ Terminal (real-time cost view)
```

**VPC Layout:**

```
VPC: 10.0.0.0/16
├── Public Subnet 1 (us-east-1a): 10.0.1.0/24
│     └── ALB + EC2 instances
└── Public Subnet 2 (us-east-1b): 10.0.2.0/24
      └── ALB + EC2 instances

Security Groups:
  ALB SG  → inbound :80 from 0.0.0.0/0
  EC2 SG  → inbound :80 from ALB SG only
```

---

## What You'll Build

| Resource | Detail |
|----------|--------|
| VPC | 10.0.0.0/16, DNS enabled |
| Public Subnets | 2 subnets across 2 AZs |
| Internet Gateway | Routes public traffic |
| Application Load Balancer | internet-facing, HTTP |
| ALB Target Group | HTTP health check on / |
| Security Groups | ALB SG + EC2 SG (least privilege) |
| Launch Template | Amazon Linux 2, t3.micro, Apache web app |
| Auto Scaling Group | min=1, desired=2, max=3 |
| Scaling Policy | Target tracking: CPU at 50% |
| CloudWatch Alarm | Alert + SNS when CPU > 70% |
| SNS Topic | Scale event notifications |
| FinOps Guardrails | Budgets + Anomaly Detection (via FinOps projects) |

---

## What You'll Learn

**AWS Services (SAA-C03 exam topics):**
- Application Load Balancer — listeners, target groups, health checks, routing
- Auto Scaling Groups — launch templates, scaling policies, health checks
- Target Tracking Scaling — how CPU-based scaling works
- CloudWatch Alarms — metrics, periods, thresholds, actions
- VPC networking — public subnets, IGW, security group chaining
- SNS — fan-out notifications for operational events

**FinOps Concepts:**
- Cost impact of Auto Scaling (more instances = higher bill)
- Budget alerts as financial guardrails
- Real-time cost monitoring during infrastructure changes
- Tag-based cost allocation for a running lab

---

## Prerequisites

```bash
# AWS CLI v2
aws --version   # aws-cli/2.x.x

# Active credentials
aws sts get-caller-identity

# Python 3 + boto3 (for FinOps dashboard)
python3 --version
pip install boto3

# jq (optional, for pretty JSON output)
jq --version
```

**FinOps Projects (optional but recommended):**

```bash
ls finops-projects/aws-cost-explorer-dashboard/
ls finops-projects/budget-alerts-anomaly-detection/
```

---

## Lab Walkthrough

### Step 1 — Set Environment Variables

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION=us-east-1
export EMAIL_ADDRESS=your@email.com    # for budget alerts
```

### Step 2 — Set Up FinOps Guardrails (Do This First)

Before deploying any infrastructure, set up your cost guardrails:

```bash
# Creates 3 budgets + SNS alerts
export EMAIL_ADDRESS=your@email.com
bash finops-projects/budget-alerts-anomaly-detection/scripts/create-budgets.sh

# Creates anomaly detection monitor
bash finops-projects/budget-alerts-anomaly-detection/scripts/setup-anomaly.sh
```

> **Why first?** Auto Scaling can silently scale your fleet (and your bill). Guardrails catch runaway spend before you notice.

### Step 3 — Deploy the Lab

```bash
bash projects/05-multi-tier-alb-autoscaling/scripts/deploy.sh
```

This runs 12 steps and takes 3-5 minutes. At the end you'll have:
- ALB DNS name (your app URL)
- 2 EC2 instances registered with the ALB
- Auto Scaling ready to kick in

### Step 4 — Access the Application

```bash
# Open in browser (or curl)
echo "http://$ALB_DNS"
curl http://$ALB_DNS
```

You should see a page showing the Instance ID, Availability Zone, and Private IP. Refresh multiple times — watch the ALB rotate between instances in different AZs.

### Step 5 — Observe ALB Routing

```bash
# Make 10 requests and watch the instance IDs change
for i in {1..10}; do
  curl -s http://$ALB_DNS | grep -oP 'i-[a-f0-9]+'
  sleep 1
done
```

Expected: alternating between two different instance IDs across two AZs.

### Step 6 — Check Target Group Health

```bash
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].{ID:Target.Id,State:TargetHealth.State}' \
  --output table
```

Both instances should show `healthy`.

### Step 7 — Check ASG State

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names lab05-alb-autoscaling-asg \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:length(Instances)}' \
  --output table
```

### Step 8 — Trigger Auto Scaling

```bash
# Run the load test script
bash scripts/test-scaling.sh
```

This sends concurrent HTTP requests to spike CPU. Watch for:
- CloudWatch CPU alarm state change
- ASG scaling activity (new instance launching)
- SNS notification (if email subscribed)

```bash
# Watch scaling events in real-time
watch -n 15 "aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name lab05-alb-autoscaling-asg \
  --max-items 3 \
  --query 'Activities[*].{Description:Description,Status:StatusCode}' \
  --output table"
```

### Step 9 — View CloudWatch Metrics

```bash
# Get CPU utilization for the ASG
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions "Name=AutoScalingGroupName,Value=lab05-alb-autoscaling-asg" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --query 'Datapoints[*].{Time:Timestamp,CPU:Average}' \
  --output table
```

### Step 10 — FinOps Check

```bash
# Show current lab cost impact and budget status
bash scripts/finops-check.sh
```

Or run the full Cost Explorer dashboard:

```bash
python3 finops-projects/aws-cost-explorer-dashboard/dashboard.py --days 1
```

### Step 11 — Exam-Relevant CLI Commands

```bash
# List all ALBs
aws elbv2 describe-load-balancers --output table

# Describe scaling policies
aws autoscaling describe-policies \
  --auto-scaling-group-name lab05-alb-autoscaling-asg

# Describe target groups with health
aws elbv2 describe-target-groups --output table

# View CloudWatch alarm state
aws cloudwatch describe-alarms \
  --alarm-names lab05-alb-autoscaling-high-cpu \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'
```

### Step 12 — Clean Up

```bash
bash scripts/cleanup.sh
```

Then clean up FinOps guardrails:

```bash
bash finops-projects/budget-alerts-anomaly-detection/scripts/cleanup.sh
```

---

## FinOps Integration

This lab integrates with two FinOps projects to demonstrate real-world cost management:

### AWS Cost Explorer Dashboard

```
finops-projects/aws-cost-explorer-dashboard/
```

Use it to:
- Baseline costs before deploy: `python3 dashboard.py --days 1 > before.txt`
- Monitor during the lab: `python3 dashboard.py --days 1`
- Verify cleanup: run again after cleanup, confirm EC2 line drops to $0

### Budget Alerts & Anomaly Detection

```
finops-projects/budget-alerts-anomaly-detection/
```

Protects you from:
- ASG scaling to max (3 instances) unexpectedly
- Forgetting to run cleanup.sh after the lab
- Unexpected data transfer charges from load testing

**Real-world parallel:** Every production auto-scaling system should have budget alerts. Auto Scaling is one of the most common sources of unexpected AWS bills — especially when scaling policies are misconfigured.

---

## GIF Recordings

Record these sessions to document the lab for your portfolio:

| GIF | What to Record | Script |
|-----|---------------|--------|
| `01-alb-routing.gif` | Curl loop showing ALB rotating across instances (Instance ID changing) | Manual curl loop |
| `02-scaling-event.gif` | `test-scaling.sh` running + ASG desired count increasing from 2→3 | `bash scripts/test-scaling.sh` |
| `03-cloudwatch-metrics.gif` | CloudWatch console — CPU spike → alarm ALARM state → scale-out | Console |
| `04-cost-explorer.gif` | Cost Explorer dashboard running + showing EC2 cost | `python3 finops-projects/aws-cost-explorer-dashboard/dashboard.py` |
| `05-budget-alert.gif` | Budget status + anomaly check output | `bash finops-projects/budget-alerts-anomaly-detection/scripts/check-anomalies.sh` |

**Recommended tool**: [vhs](https://github.com/charmbracelet/vhs) — terminal GIF recorder from Charm

```bash
# Install vhs (go required)
go install github.com/charmbracelet/vhs@latest

# Or use asciinema
pip install asciinema
asciinema rec docs/gifs/02-scaling-event.cast
# Convert to GIF: asciinema-agg
```

---

## Expected Costs

| Resource | Rate | 1 hr | 4 hrs |
|----------|------|------|-------|
| EC2 t3.micro × 2 | $0.0104/hr each | $0.021 | $0.083 |
| ALB | $0.008/hr min + LCU | $0.008 | $0.032 |
| EC2 t3.micro × 3 (max) | $0.0312/hr | $0.031 | $0.125 |
| **Typical lab session (2 instances, 2 hrs)** | — | — | **~$0.06** |

> Free tier: t3.micro is **not** free-tier eligible (t2.micro is). If you have free tier hours remaining on t2.micro, change `INSTANCE_TYPE` in `deploy.sh` to `t2.micro`.

**Always run cleanup.sh when done.** ALB and EC2 charges accumulate every hour.

---

## Cleanup

```bash
# Destroy all lab resources
bash scripts/cleanup.sh

# Verify no resources remain
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Lab,Values=05-alb-autoscaling \
  --query 'ResourceTagMappingList[].ResourceARN'
# Should return: []

# Remove FinOps guardrails
bash finops-projects/budget-alerts-anomaly-detection/scripts/cleanup.sh
```

---

## Key Concepts

| Concept | Exam Note |
|---------|-----------|
| ALB vs NLB vs CLB | ALB = Layer 7 (HTTP/HTTPS), NLB = Layer 4 (TCP/UDP), CLB = legacy |
| Target Tracking vs Step Scaling | Target tracking is simpler and preferred; step scaling gives more control |
| Health check grace period | Time after launch before ALB health checks begin (120s here) |
| Scale-in protection | Prevent specific instances from being terminated during scale-in |
| Launch Template vs Launch Config | Launch Templates are the modern approach; support versioning |
| ELB vs ALB | ELB is the family name; ALB is a type of ELB |
| Cross-zone load balancing | ALBs have this enabled by default; NLBs do not |
| Sticky sessions | ALB supports session affinity via cookies (not used here) |
| FinOps: Cost of scaling | Each new instance = new cost; scaling policies must be tuned |

---

## Links

- [Lab 04 — Lambda + API Gateway](../04-lambda-api-gateway/README.md)
- [AWS Cost Explorer Dashboard](../../finops-projects/aws-cost-explorer-dashboard/README.md)
- [Budget Alerts & Anomaly Detection](../../finops-projects/budget-alerts-anomaly-detection/README.md)
- [Portfolio](https://oumoeurtmm-code.github.io)
- [Repository](https://github.com/oumoeurtmm-code/ai-terminal-workflow)
