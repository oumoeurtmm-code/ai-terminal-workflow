"""
Workflow 1: New Hire IT Provisioning
Generates a concise IT setup checklist for a new employee.
"""

CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"
BOLD = "\033[1m"


def run(client):
    employee = {
        "name": "John Doe",
        "role": "IT Engineer",
        "department": "Engineering",
        "start_date": "2026-03-19",
    }

    print(f"\n{YELLOW}  Employee:{RESET} {employee['name']}")
    print(f"{YELLOW}  Role:    {RESET} {employee['role']}")
    print(f"{YELLOW}  Dept:    {RESET} {employee['department']}")
    print(f"{YELLOW}  Start:   {RESET} {employee['start_date']}")
    print()

    message = client.messages.create(
        model="claude-3-haiku-20240307",
        max_tokens=400,
        messages=[
            {
                "role": "user",
                "content": (
                    "You are an IT provisioning assistant. Generate a concise IT provisioning "
                    "checklist for this new hire. List 5 key IT setup tasks with brief descriptions.\n\n"
                    f"Name: {employee['name']}\n"
                    f"Role: {employee['role']}\n"
                    f"Department: {employee['department']}\n"
                    f"Start Date: {employee['start_date']}"
                ),
            }
        ],
    )

    response_text = message.content[0].text

    print(f"{GREEN}{BOLD}  AI Response:{RESET}")
    for line in response_text.strip().splitlines():
        print(f"  {line}")

    return response_text
