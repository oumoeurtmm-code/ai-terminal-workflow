# IT Automation Demo Scripts

Python scripts that demonstrate IT automation workflows using the Anthropic API directly.
These replace the broken n8n workflows with clean, runnable code suitable for portfolio GIF recording.

## Workflows

| Script | What it does |
|---|---|
| `new_hire_provisioning.py` | Generates a 5-task IT provisioning checklist for a new employee |
| `access_request.py` | Reviews an access request using least-privilege security policy |
| `cloud_cost_report.py` | Produces an executive summary + 2 FinOps recommendations from cost data |

## Setup

```bash
# 1. Install dependency
pip install -r scripts/requirements.txt

# 2. Set your Anthropic API key
export ANTHROPIC_API_KEY=your-key-here

# 3. Run all 3 workflows in sequence
python scripts/run_demo.py
```

## Run a single workflow

```bash
cd scripts
python -c "
import anthropic, new_hire_provisioning
client = anthropic.Anthropic()
new_hire_provisioning.run(client)
"
```

Replace `new_hire_provisioning` with `access_request` or `cloud_cost_report` as needed.

## Notes

- Model: `claude-3-haiku-20240307` (fast and cost-efficient for demos)
- `max_tokens`: 400 per call
- No external dependencies beyond `anthropic`
- Color output uses ANSI escape codes — works in any modern terminal
