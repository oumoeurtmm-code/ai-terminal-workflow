"""
Workflow 3: Cloud Cost Report Analysis
Generates an executive summary and optimization recommendations from AWS cost data.
"""

CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"
BOLD = "\033[1m"


def run(client):
    cost_data = {
        "period": "March 2026",
        "total": "$487.32",
        "change": "+12.4% vs last month",
        "breakdown": {
            "EC2": "$210.50",
            "RDS": "$145.20",
            "S3": "$42.10",
            "Lambda": "$0.82",
            "Other": "$88.70",
        },
    }

    print(f"\n{YELLOW}  Period:{RESET} {cost_data['period']}")
    print(f"{YELLOW}  Total: {RESET} {cost_data['total']}  ({cost_data['change']})")
    print(f"{YELLOW}  Breakdown:{RESET}")
    for service, amount in cost_data["breakdown"].items():
        print(f"    {service:8s}  {amount}")
    print()

    breakdown_str = "\n".join(
        f"  {svc}: {amt}" for svc, amt in cost_data["breakdown"].items()
    )

    message = client.messages.create(
        model="claude-3-haiku-20240307",
        max_tokens=400,
        messages=[
            {
                "role": "user",
                "content": (
                    "You are a FinOps analyst. Write a brief executive summary of this AWS cost "
                    "report and provide 2 specific cost optimization recommendations.\n\n"
                    f"Period: {cost_data['period']}\n"
                    f"Total: {cost_data['total']} ({cost_data['change']})\n"
                    f"Service Breakdown:\n{breakdown_str}"
                ),
            }
        ],
    )

    response_text = message.content[0].text

    print(f"{GREEN}{BOLD}  AI Response:{RESET}")
    for line in response_text.strip().splitlines():
        print(f"  {line}")

    return response_text
