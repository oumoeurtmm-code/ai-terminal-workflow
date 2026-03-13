# Contributing

Thanks for your interest in improving this lab series. This is a personal learning project — contributions that improve accuracy, clarity, or add new labs are welcome.

---

## Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/your-username/ai-terminal-workflow.git`
3. **Create a branch**: `git checkout -b feature/your-change`
4. **Make your changes** (see standards below)
5. **Push** and open a **Pull Request** using the PR template

---

## Project Standards

### Scripts

- Use `set -euo pipefail` at the top of every script
- Export all resource IDs so `cleanup.sh` can reference them
- `cleanup.sh` must handle partially-deployed or already-deleted resources without hard failures
- No hardcoded resource names — use environment variables
- Always verify cleanup with `resourcegroupstaggingapi get-resources`

### AWS Resources

- Tag every resource at creation with at minimum: `Project`, `Environment`, `ManagedBy`
- Use the standard tagging values: `Project=aws-cert-study`, `Environment=learning`, `ManagedBy=manual`
- Default region: `us-east-1` — use `$AWS_REGION` variable throughout

### Documentation

- Every lab README must include:
  - Badges (difficulty, time, cost, status, stack)
  - Quick Start section (deploy + cleanup one-liners)
  - Mermaid architecture diagram
  - FinOps cost table
  - Step-by-step walkthrough with exam notes
  - Screenshot prompts at each key step
  - Knowledge check questions
  - Cleanup instructions (automated + manual)
  - Certification relevance table
- Use relative paths — never hardcode user home directories
- Screenshot prompts use the format:
  ```
  > **Screenshot (console):** Navigate to **Service → Page** and take a screenshot showing X.
  > Save as `docs/screenshots/NN-descriptive-name.png`
  ```

### FinOps

- Every lab must include a cost table before the walkthrough
- Highlight expensive resources (NAT Gateway, EC2 running costs) with cost alerts
- Every resource created must have an explicit cleanup step

---

## Reporting Issues

Use the issue templates:
- **Lab Issue** — script errors, incorrect docs, outdated console steps
- **Feature Request** — new labs, improvements, additions

---

## Questions

Open a GitHub Issue with the `question` label.
