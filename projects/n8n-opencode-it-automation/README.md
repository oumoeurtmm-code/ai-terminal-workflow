# n8n + OpenCode IT Automation

![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat)
![Stack](https://img.shields.io/badge/stack-n8n_%C2%B7_OpenCode_%C2%B7_Okta_%C2%B7_Entra-6366f1?style=flat)
![AI](https://img.shields.io/badge/AI-Claude_Code_%C2%B7_Gemini_%C2%B7_Grok_%C2%B7_Perplexity-22d3ee?style=flat)

Multi-model AI orchestration for IT provisioning, access control, and cloud ops — powered by Claude Code, Gemini, Grok, and Perplexity through OpenCode, orchestrated via n8n.

---

## Overview

This project automates the most time-consuming IT workflows using a multi-model AI architecture. n8n handles orchestration and system integrations (Okta, Entra, Slack, cloud APIs), while OpenCode routes tasks to the right AI model based on what each one does best.

| Model | Role |
|---|---|
| **Claude Code** | Script generation — PowerShell, Bash, Python |
| **Gemini** | Policy reasoning, entitlement decisions, runbook drafting |
| **Grok** | Real-time ops analysis, anomaly detection |
| **Perplexity** | Research, compliance lookups, incident diagnostics |

---

## Architecture

```
HRIS / ITSM / Slack
        │
        ▼
   n8n Orchestrator
        │
        ├─── OpenCode (multi-model brain)
        │         ├── Claude Code  →  scripts
        │         ├── Gemini       →  policy decisions
        │         ├── Grok         →  ops analysis
        │         └── Perplexity   →  research
        │
        ├─── Okta (IAM)
        ├─── Microsoft Entra (identity)
        ├─── AWS · Azure · GCP (cloud IAM)
        └─── Slack (notifications + approvals)
```

---

## Workflows

### Workflow 1 — New Hire Provisioning

Triggered by an HRIS webhook (Workday, BambooHR, etc.). The CoordinatorAgent (Gemini + Perplexity) decides entitlements, Claude Code generates any needed scripts, and n8n applies actions across Okta and Entra. High-risk roles gate on Slack manager approval before provisioning.

**Time saved:** ~90 min manual → ~8 min automated

### Workflow 2 — Access Request Decision

Triggered by a Slack slash command or ITSM ticket. The PolicyAgent evaluates the request against zero-trust policy and returns one of three decisions:

- `auto_grant` — standard access, applied immediately
- `needs_approval` — elevated permissions, routed to manager
- `deny` — policy violation, requester notified with reason

**Time saved:** ~30 min manual → ~3 min automated

### Workflow 3 — Cloud Ops Monitoring

Runs on a 15-minute schedule. Pulls metrics from CloudWatch, Azure Monitor, and GCP Logging, then passes a compacted payload to the OpsAgent (Grok). On anomaly detection, the RunbookAgent auto-generates a response runbook and fires a Slack alert to `#it-ops`.

**Time saved:** ~60 min manual monitoring → ~1 min automated

---

## Prerequisites

- **n8n** — self-hosted or n8n Cloud
- **OpenCode** — running with Claude Code, Gemini, Grok, and Perplexity configured
- **Okta** — admin API token
- **Microsoft Entra** — app registration with Graph API permissions
- **Slack** — bot token with `chat:write`, `commands` scopes
- AWS/Azure/GCP credentials for the ops monitoring workflow

---

## Setup

### 1. Configure n8n credentials

In your n8n instance, add the following credentials:

| Credential | Type | Used by |
|---|---|---|
| OpenCode | HTTP Header Auth | All workflows |
| Okta | HTTP Header Auth | Workflows 1 & 2 |
| Microsoft Entra | OAuth2 | Workflows 1 & 2 |
| Slack | Slack API | All workflows |

### 2. Set n8n variables

Set these as **n8n Variables** (Settings → Variables) so they're available across all workflows:

```
OPENCODE_URL        https://your-opencode-instance
OPENCODE_API_KEY    your-opencode-api-key
OKTA_DOMAIN         your-org.okta.com
OKTA_API_TOKEN      your-okta-ssws-token
ENTRA_ACCESS_TOKEN  your-microsoft-graph-bearer-token
SLACK_CHANNEL_OPS   #it-ops
SLACK_CHANNEL_ALERTS #it-alerts
SLACK_CHANNEL_APPROVAL #it-approvals
```

### 3. Import workflows

In n8n: **Workflows → Import from file**

| File | Workflow |
|---|---|
| `workflows/new-hire-provisioning.json` | New Hire Provisioning |
| `workflows/access-request.json` | Access Request Decision |

> Workflow 3 (Ops Monitoring) is configured inline via the Schedule Trigger node — no separate import needed.

### 4. Activate and test

Activate each workflow, then test with a sample payload:

```bash
curl -X POST https://your-n8n-instance/webhook/new-hire \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jordan",
    "lastName": "Riley",
    "email": "j.riley@company.com",
    "department": "Engineering",
    "jobTitle": "Backend Engineer",
    "managerEmail": "sarah.kim@company.com",
    "startDate": "2026-03-16",
    "location": "Remote - US West",
    "employeeId": "EMP-20241",
    "riskLevel": "standard"
  }'
```

---

## Project Structure

```
n8n-opencode-it-automation/
├── index.html                        # Live project page (synced to portfolio)
├── README.md                         # This file
└── workflows/
    ├── new-hire-provisioning.json    # Workflow 1 — n8n export
    └── access-request.json           # Workflow 2 — n8n export
```

---

## Risk Levels

The provisioning workflow uses a `riskLevel` field to control the approval gate:

| Level | Behavior |
|---|---|
| `standard` | Auto-provisioned, no approval required |
| `elevated` | Slack notification sent to manager, proceeds after acknowledgment |
| `high` | Hard approval gate — provisioning blocked until manager approves in Slack |

---

## Links

- [Live project page](https://oumoeurtmm-code.github.io/projects/n8n-opencode-it-automation/)
- [Portfolio](https://oumoeurtmm-code.github.io)
- [ai-terminal-workflow](https://github.com/oumoeurtmm-code/ai-terminal-workflow)
