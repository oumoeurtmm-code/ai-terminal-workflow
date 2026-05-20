# aws-cloud-labs

![AWS](https://img.shields.io/badge/AWS-Cloud_Engineering-FF9900?style=flat&logo=amazon-aws&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-Cost_Aware-00B4D8?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0xIDE1aC0ydi02aDJ2NnptMC04aC0yVjdoMnYyeiIvPjwvc3ZnPg==&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat)
![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat)

Hands-on AWS lab series built for **cloud engineering and FinOps practice** — each project deploys real infrastructure, covers exam-relevant concepts, and includes a full cleanup script to prevent runaway costs.

> Built by an IT professional with 13+ years in enterprise infrastructure, now going deep on AWS, FinOps, and AI-assisted cloud automation.

---

## AWS Labs

| # | Project | Stack | Status | Docs | Live |
|---|---------|-------|--------|------|------|
| 01 | Static Website on AWS | S3 · CloudFront · IAM · CloudWatch | ✅ Complete | [README](projects/01-static-website-aws-fundamentals/README.md) | [View](https://oumoeurtmm-code.github.io/projects/01-static-website-aws-fundamentals/) |
| 02 | EC2 + VPC + Security Groups | EC2 · VPC · Subnets · SGs · SSM | ✅ Complete | [README](projects/02-ec2-vpc-security-groups/README.md) | [View](https://oumoeurtmm-code.github.io/projects/02-ec2-vpc-security-groups/) |
| 03 | RDS + EC2 Two-Tier App | RDS · EC2 · VPC · Secrets Manager | ✅ Complete | [README](projects/03-rds-ec2-two-tier/README.md) | [View](https://oumoeurtmm-code.github.io/projects/03-rds-ec2-two-tier/) |
| 04 | Lambda + API Gateway | Lambda · API GW · IAM · CloudWatch | ✅ Complete | [README](projects/04-lambda-api-gateway/README.md) | [View](https://oumoeurtmm-code.github.io/projects/04-lambda-api-gateway/) |
| 05 | Multi-Tier with ALB + Auto Scaling | ALB · ASG · CloudWatch · SNS · FinOps | 🔵 In Progress | [README](projects/05-multi-tier-alb-autoscaling/README.md) | — |

---

## FinOps Projects

Cost engineering projects that run alongside the AWS labs — using real AWS APIs and Python to build visibility, alerting, and optimization workflows.

| Project | Stack | Status | Docs |
|---------|-------|--------|------|
| AWS Cost Explorer Dashboard | Cost Explorer API · Python · boto3 | 🔵 In Progress | [README](finops-projects/aws-cost-explorer-dashboard/README.md) |
| Budget Alerts & Anomaly Detection | AWS Budgets · Cost Anomaly Detection · SNS | 🔵 In Progress | [README](finops-projects/budget-alerts-anomaly-detection/README.md) |
| Cost Optimization | Savings Plans · Right-sizing · Trusted Advisor | 🔵 In Progress | [README](finops-projects/cost_optimization/README.md) |
| FinOps Best Practices | FinOps Foundation lifecycle docs | 📝 Reference | [README](finops-projects/best_practices/README.md) |

---

## Other Projects

| Project | Stack | Status | Docs | Live |
|---------|-------|--------|------|------|
| n8n + OpenCode IT Automation | n8n · OpenCode · Claude Code · Okta · Entra | ✅ Complete | [README](projects/n8n-opencode-it-automation/README.md) | [View](https://oumoeurtmm-code.github.io/projects/n8n-opencode-it-automation/) |
| Project Tracker | HTML · JS | ✅ Live | — | [View](https://oumoeurtmm-code.github.io/projects/project-tracker/) |

---

## Philosophy

Every project follows the same pattern:

```
Deploy → Learn → Clean Up
```

1. **Deploy** — automated scripts create all infrastructure, no console-clicking required
2. **Learn** — step-by-step README with CLI commands, exam notes, and FinOps callouts
3. **Clean Up** — automated cleanup scripts destroy every resource to prevent runaway costs

---

## Getting Started

### Prerequisites

```bash
# AWS CLI v2
aws --version           # aws-cli/2.x.x

# Verify authentication
aws sts get-caller-identity
```

### Quick Start — Run Any Lab

```bash
# Clone the repo
git clone https://github.com/oumoeurtmm-code/aws-cloud-labs.git
cd aws-cloud-labs

# Deploy a lab (example: Lab 01)
bash projects/01-static-website-aws-fundamentals/scripts/deploy.sh

# Always clean up after your session
bash projects/01-static-website-aws-fundamentals/scripts/cleanup.sh
```

---

## Tagging Standard

All AWS resources use consistent tags for cost allocation and resource tracking:

| Tag Key | Value |
|---------|-------|
| `Project` | `aws-cert-study` |
| `Environment` | `learning` |
| `Owner` | `oumoeurtmm` |
| `CostCenter` | `personal-dev` |
| `ManagedBy` | `manual` |

Verify no resources remain after cleanup:

```bash
aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=aws-cert-study \
    --query 'ResourceTagMappingList[].ResourceARN'
# Should return: []
```

---

## FinOps Principles Applied

- **Shift-Left Costing** — evaluate cost impact before implementing any change
- **Resource Lifecycle** — every resource created has an explicit cleanup strategy
- **Tagging First** — all resources tagged at creation for cost allocation
- **No Hardcoded Names** — resource identifiers use environment variables
- **CNCF-Preferred Tools** — open-source tooling defaults to CNCF-backed projects

---

## Repository Structure

```
aws-cloud-labs/
├── projects/
│   ├── 01-static-website-aws-fundamentals/   # S3 · CloudFront · IAM · CloudWatch
│   ├── 02-ec2-vpc-security-groups/           # EC2 · VPC · Subnets · SSM
│   ├── 03-rds-ec2-two-tier/                  # RDS · EC2 · Secrets Manager
│   ├── 04-lambda-api-gateway/                # Lambda · API GW · CloudWatch
│   ├── 05-multi-tier-alb-autoscaling/        # ALB · ASG · CloudWatch · FinOps
│   ├── n8n-opencode-it-automation/           # n8n · Claude · Okta · Entra
│   └── project-tracker/
├── finops-projects/
│   ├── aws-cost-explorer-dashboard/          # Cost Explorer API + Python viz
│   ├── budget-alerts-anomaly-detection/      # AWS Budgets + Anomaly Detection
│   ├── cost_optimization/                    # Savings Plans + Right-sizing
│   ├── best_practices/                       # FinOps Foundation lifecycle
│   └── open_source_tools/
└── security-projects/                        # (planned)
```

> Project pages are automatically synced to [oumoeurtmm-code.github.io](https://oumoeurtmm-code.github.io) via GitHub Actions on every push.

---

<div align="center">
  <sub>Built with curiosity · Powered by cloud · Secured by default</sub>
</div>
