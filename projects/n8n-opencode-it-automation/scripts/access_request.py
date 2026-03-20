"""
Workflow 2: IT Access Request Review
Applies least-privilege principles to evaluate an access request.
"""

CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"
BOLD = "\033[1m"


def run(client):
    request = {
        "requester": "Jane Smith",
        "resource": "AWS Production S3",
        "access_level": "Read/Write",
        "justification": "deploy application assets",
    }

    print(f"\n{YELLOW}  Requester:    {RESET} {request['requester']}")
    print(f"{YELLOW}  Resource:     {RESET} {request['resource']}")
    print(f"{YELLOW}  Access Level: {RESET} {request['access_level']}")
    print(f"{YELLOW}  Justification:{RESET} {request['justification']}")
    print()

    message = client.messages.create(
        model="claude-3-haiku-20240307",
        max_tokens=400,
        messages=[
            {
                "role": "user",
                "content": (
                    "You are an IT security policy reviewer applying least-privilege principles. "
                    "Evaluate this access request and provide a decision (APPROVE or DENY) "
                    "with a 2-sentence reason.\n\n"
                    f"Requester: {request['requester']}\n"
                    f"Resource: {request['resource']}\n"
                    f"Access Level: {request['access_level']}\n"
                    f"Justification: {request['justification']}"
                ),
            }
        ],
    )

    response_text = message.content[0].text

    print(f"{GREEN}{BOLD}  AI Response:{RESET}")
    for line in response_text.strip().splitlines():
        print(f"  {line}")

    return response_text
