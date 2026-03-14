# ai-terminal-workflow

![AWS](https://img.shields.io/badge/AWS-Cloud_Engineering-FF9900?style=flat&logo=amazon-aws&logoColor=white)
![FinOps](https://img.shields.io/badge/FinOps-Cost_Aware-00B4D8?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0xIDE1aC0ydi02aDJ2NnptMC04aC0yVjdoMnYyeiIvPjwvc3ZnPg==&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat)
![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat)

Hands-on AWS lab series built for **cloud engineering and certification prep** — each project deploys real infrastructure, teaches exam-relevant concepts, and includes a full cleanup script to avoid unexpected charges.

> Built by an IT professional going deep on AWS, FinOps, and AI-assisted automation.

---

## Projects

### AWS Labs

| # | Project | Stack | Status | Docs | Live |
|---|---------|-------|--------|------|------|
| 01 | Static Website on AWS | S3 · CloudFront · IAM · CloudWatch | ✅ Complete | [README](projects/01-static-website-aws-fundamentals/README.md) | [View](https://oumoeurtmm-code.github.io/projects/01-static-website-aws-fundamentals/) |
| 02 | EC2 + VPC + Security Groups | EC2 · VPC · Subnets · SGs · SSM | 🔵 In Progress | [README](projects/02-ec2-vpc-security-groups/README.md) | — |
| 03 | RDS + EC2 Two-Tier App | RDS · EC2 · VPC · Secrets Manager | ⬜ Planned | — | — |
| 04 | Lambda + API Gateway | Lambda · API GW · IAM · CloudWatch | ⬜ Planned | — | — |
| 05 | Multi-Tier with ALB + Auto Scaling | ALB · ASG · CloudWatch · SNS | ⬜ Planned | — | — |

### Other Projects

| Project | Stack | Status | Docs | Live |
|---------|-------|--------|------|------|
| n8n + OpenCode IT Automation | n8n · OpenCode · Claude Code · Okta · Entra | 🔵 Active | [README](projects/n8n-opencode-it-automation/README.md) | [View](https://oumoeurtmm-code.github.io/projects/n8n-opencode-it-automation/) |
| Project Tracker | HTML · JS | ✅ Live | — | [View](https://oumoeurtmm-code.github.io/projects/project-tracker/) |

---

## Philosophy

Every project follows the same pattern:

```
Deploy → Learn → Clean Up
```

1. **Deploy** — automated scripts create all infrastructure, no console clicking required
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
git clone https://github.com/oumoeurtmm-code/ai-terminal-workflow.git
cd ai-terminal-workflow

# Deploy a lab (example: project 01)
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
| `Owner` | `your-name` |
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

## FinOps Principles

- **Shift-Left Costing** — evaluate cost impact before implementing any change
- **Resource Lifecycle** — every resource created has an explicit cleanup strategy
- **Tagging First** — all resources tagged at creation for cost allocation
- **CNCF-Preferred Tools** — open-source tooling defaults to CNCF-backed projects
- **No Hardcoded Names** — resource identifiers use environment variables

---

## Repository Structure

```
ai-terminal-workflow/
├── projects/
│   ├── 01-static-website-aws-fundamentals/
│   │   ├── README.md          # Full walkthrough + exam notes
│   │   ├── index.html         # Live portfolio page (synced to .github.io)
│   │   ├── scripts/
│   │   │   ├── deploy.sh
│   │   │   └── cleanup.sh
│   │   ├── website/           # Static site source files
│   │   └── docs/screenshots/
│   ├── 02-ec2-vpc-security-groups/
│   │   ├── README.md
│   │   └── scripts/
│   ├── n8n-opencode-it-automation/
│   │   ├── index.html         # Live portfolio page (synced to .github.io)
│   │   └── workflows/         # n8n workflow JSON exports
│   └── project-tracker/
│       └── index.html         # Live tracker (synced to .github.io)
├── finops-projects/           # FinOps study notes and reference material
├── security-projects/         # (planned)
└── brain-dump/                # Working notes and ideas
```

> Project pages (`index.html`) are automatically synced to [oumoeurtmm-code.github.io](https://oumoeurtmm-code.github.io) via GitHub Actions on every push.

---

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for how to submit issues and pull requests.

---

<div align="center">
  <sub>Built with curiosity · Powered by cloud · Secured by default</sub>
</div>
