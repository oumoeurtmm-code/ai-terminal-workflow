#!/usr/bin/env python3
"""
n8n + OpenCode IT Automation Demo
Runs 3 IT automation workflows powered by the Anthropic API.
"""

import os
import sys
import time

import anthropic

import new_hire_provisioning
import access_request
import cloud_cost_report

# ANSI color codes — no external deps
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
BOLD = "\033[1m"
RESET = "\033[0m"
DIM = "\033[2m"

BANNER = f"""
{CYAN}{BOLD}╔══════════════════════════════════════════════════════╗
║       n8n + OpenCode IT Automation Demo              ║
║       Powered by Anthropic Claude                    ║
╚══════════════════════════════════════════════════════╝{RESET}
"""

WORKFLOWS = [
    ("Workflow 1: New Hire IT Provisioning", new_hire_provisioning.run),
    ("Workflow 2: Access Request Review", access_request.run),
    ("Workflow 3: Cloud Cost Report Analysis", cloud_cost_report.run),
]


def separator(title: str) -> None:
    width = 56
    bar = "─" * width
    print(f"\n{CYAN}{bar}{RESET}")
    print(f"{CYAN}{BOLD}  {title}{RESET}")
    print(f"{CYAN}{bar}{RESET}")


def main() -> None:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(
            f"{YELLOW}[warn]{RESET} ANTHROPIC_API_KEY not set. "
            "Export it before running:\n  export ANTHROPIC_API_KEY=your-key",
            file=sys.stderr,
        )
        sys.exit(1)

    print(BANNER)
    print(f"{DIM}  Running {len(WORKFLOWS)} automation workflows...{RESET}\n")
    time.sleep(0.5)

    client = anthropic.Anthropic(api_key=api_key)

    for name, fn in WORKFLOWS:
        separator(name)
        time.sleep(0.5)
        fn(client)
        time.sleep(0.5)

    bar = "─" * 56
    print(f"\n{GREEN}{bar}{RESET}")
    print(f"{GREEN}{BOLD}  All workflows complete.{RESET}")
    print(f"{GREEN}{bar}{RESET}\n")


if __name__ == "__main__":
    main()
