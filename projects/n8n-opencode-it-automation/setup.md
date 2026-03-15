# Setup Guide — n8n + OpenCode IT Automation

Quickstart for running this project locally with Docker. No cloud account or n8n Cloud subscription required.

---

## Prerequisites

### Software

| Requirement | Version | Notes |
|---|---|---|
| Docker Desktop | 4.x+ | [docker.com/get-started](https://www.docker.com/get-started) |
| Docker Compose | v2+ | Included with Docker Desktop |
| curl or Postman | any | For testing webhook triggers |

### API Keys

You need **two** API keys to run the full workflow suite. Both have free tiers.

| Service | Required for | Free tier | Link |
|---|---|---|---|
| **Anthropic (Claude)** | `cloud-cost-report` narrative generation | Free credits on signup | [console.anthropic.com](https://console.anthropic.com/) |
| **Google AI (Gemini)** | `cloud-cost-report` recommendations, policy reasoning | Free tier — Gemini Flash | [aistudio.google.com](https://aistudio.google.com/app/apikey) |

> **Perplexity is optional.** The workflows are designed to run entirely on Claude + Gemini. Perplexity is only needed if you add the OpenCode orchestration layer (see README.md). You do not need a Perplexity account to get started.

---

## 1. Configure Environment Variables

Copy the example env file and fill in your values:

```bash
cd projects/n8n-opencode-it-automation
cp .env.example .env
```

Open `.env` and set at minimum:

```
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=your-secure-password
N8N_ENCRYPTION_KEY=generate-with-openssl-rand-hex-32
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_AI_API_KEY=AIza...
```

Generate a random encryption key:

```bash
openssl rand -hex 32
```

---

## 2. Start n8n Locally

```bash
docker compose up -d
```

Wait ~15 seconds for the container to initialize, then open:

```
http://localhost:5678
```

Log in with the `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD` you set in `.env`.

**Useful commands:**

```bash
# View logs
docker compose logs -f n8n

# Stop n8n
docker compose down

# Stop and wipe all data (credentials, workflows)
docker compose down -v
```

---

## 3. Set n8n Variables

The workflows reference credentials and channel names via **n8n Variables** (not hardcoded). Set these before importing workflows.

Navigate to: **Settings → Variables → Add Variable**

| Variable name | Example value | Required for |
|---|---|---|
| `ANTHROPIC_API_KEY` | `sk-ant-...` | cloud-cost-report |
| `GOOGLE_AI_API_KEY` | `AIza...` | cloud-cost-report, access-request |
| `SLACK_CHANNEL_FINOPS` | `#cloud-costs` | cloud-cost-report |
| `SLACK_CHANNEL_OPS` | `#it-ops` | all workflows |
| `SLACK_CHANNEL_ALERTS` | `#it-alerts` | new-hire-provisioning |
| `SLACK_CHANNEL_APPROVAL` | `#it-approvals` | new-hire, access-request |
| `OPENCODE_URL` | `http://your-opencode-host` | new-hire, access-request (if using OpenCode) |
| `OPENCODE_API_KEY` | `your-api-key` | new-hire, access-request (if using OpenCode) |
| `OKTA_DOMAIN` | `your-org.okta.com` | new-hire, access-request |
| `OKTA_API_TOKEN` | `SSWS ...` | new-hire, access-request |
| `ENTRA_ACCESS_TOKEN` | `Bearer eyJ...` | new-hire, access-request |

---

## 4. Set Credentials in n8n

For the **Slack** node to work, add a Slack credential:

1. Go to **Credentials → Add Credential → Slack API**
2. Paste your Slack Bot Token (starts with `xoxb-`)
3. Ensure the bot has scopes: `chat:write`, `channels:read`

For **Anthropic** and **Google AI**, the workflows use HTTP Request nodes with API keys from Variables — no separate credential type needed.

---

## 5. Import the Workflow JSONs

In n8n: **Workflows → Import from file** (or drag-and-drop the JSON).

| File | What it does |
|---|---|
| `workflows/new-hire-provisioning.json` | Provisions Okta + Entra accounts on HRIS webhook |
| `workflows/access-request.json` | Evaluates access requests via AI policy engine |
| `workflows/cloud-cost-report.json` | Weekly AWS cost summary via Claude + Gemini → Slack |

After importing each workflow:
1. Open it and verify node credentials are linked
2. Click **Save**
3. Toggle **Active** to enable

---

## 6. Test the Workflows

### Cloud Cost Report (cloud-cost-report.json)

This workflow is the easiest to test locally — it uses built-in sample cost data when AWS credentials are not configured.

Click **Test workflow** in n8n, or trigger manually:

```bash
# The schedule trigger fires Monday 08:00 UTC; for immediate testing use "Execute workflow" in the UI
```

Expected result: Two Slack messages in `#cloud-costs` (or your configured channel) — one from Claude with the narrative, one from Gemini with optimization recommendations.

### New Hire Provisioning (new-hire-provisioning.json)

After activating the workflow, send a test POST:

```bash
curl -X POST http://localhost:5678/webhook/new-hire \
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

To test the high-risk approval gate, change `"riskLevel"` to `"high"`.

### Access Request (access-request.json)

```bash
curl -X POST http://localhost:5678/webhook/access-request \
  -H "Content-Type: application/json" \
  -d '{
    "userName": "Marcus Thompson",
    "userEmail": "m.thompson@company.com",
    "department": "Engineering",
    "userRole": "Backend Engineer",
    "system": "AWS Production Account",
    "permission": "IAM PowerUser",
    "duration": "temporary-48h",
    "reason": "Investigate billing anomaly in prod",
    "ticketId": "JIRA-4821",
    "managerEmail": "sarah.kim@company.com"
  }'
```

---

## Troubleshooting

**n8n UI not loading**
- Wait 20–30 seconds after `docker compose up -d` — n8n needs time to initialize
- Check logs: `docker compose logs n8n`

**Workflow execution errors on Claude node**
- Verify `ANTHROPIC_API_KEY` is set in n8n Variables (Settings → Variables)
- Confirm your Anthropic account has available credits

**Slack messages not sending**
- Check the Slack credential is active in n8n (Credentials → your Slack credential)
- Confirm the bot is invited to the target channel: `/invite @your-bot-name`

**AWS Cost Explorer returns no data**
- The `Parse and Compact Cost Data` node falls back to sample data automatically
- For real data, configure `AWS_SIGV4_AUTH` or use the n8n AWS credential node

**Webhook not reachable from external services (Slack slash commands, HRIS)**
- Use ngrok to expose localhost: `ngrok http 5678`
- Update `WEBHOOK_URL` in `.env` to your ngrok URL and restart: `docker compose up -d`
