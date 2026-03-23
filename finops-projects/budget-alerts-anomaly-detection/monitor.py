#!/usr/bin/env python3
"""
Budget Alerts & Anomaly Detection — Financial Health Monitor
Terminal dashboard showing budget status, anomalies, and risk assessment.

Usage:
    python3 monitor.py
    python3 monitor.py --watch          # Refresh every 5 minutes
    SLACK_WEBHOOK_URL=https://... python3 monitor.py

Requirements:
    pip install boto3 requests
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)


# ── Colors ────────────────────────────────────────────────────────────────────
C = {
    "reset":  "\033[0m",
    "bold":   "\033[1m",
    "dim":    "\033[2m",
    "red":    "\033[91m",
    "yellow": "\033[93m",
    "green":  "\033[92m",
    "cyan":   "\033[96m",
}


def c(color: str, text: str) -> str:
    return f"{C.get(color, '')}{text}{C['reset']}"


WIDTH = 60


def section(title: str) -> None:
    print(f"\n{c('dim', '─' * WIDTH)}")
    print(f"  {c('bold', title)}")
    print(c("dim", "─" * WIDTH))


# ── AWS data ──────────────────────────────────────────────────────────────────

def get_budgets(budgets_client: object, account_id: str) -> list:
    try:
        resp = budgets_client.describe_budgets(AccountId=account_id)
        return resp.get("Budgets", [])
    except ClientError as e:
        if "AccessDenied" in str(e):
            print(c("yellow", "  WARNING: No permission to read budgets"))
        return []


def get_anomalies(ce_client: object) -> list:
    try:
        end = datetime.today()
        start = end - timedelta(days=7)
        resp = ce_client.get_anomalies(
            DateInterval={
                "StartDate": start.strftime("%Y-%m-%d"),
                "EndDate": end.strftime("%Y-%m-%d"),
            }
        )
        return resp.get("Anomalies", [])
    except ClientError:
        return []


def get_daily_spend(ce_client: object) -> tuple[float, float]:
    """Returns (today_spend, yesterday_spend)."""
    try:
        today = datetime.today()
        yesterday = today - timedelta(days=1)
        two_days_ago = today - timedelta(days=2)
        resp = ce_client.get_cost_and_usage(
            TimePeriod={
                "Start": two_days_ago.strftime("%Y-%m-%d"),
                "End": today.strftime("%Y-%m-%d"),
            },
            Granularity="DAILY",
            Metrics=["BlendedCost"],
        )
        periods = resp["ResultsByTime"]
        yesterday_spend = float(periods[-1]["Total"]["BlendedCost"]["Amount"]) if periods else 0
        prev_spend = float(periods[-2]["Total"]["BlendedCost"]["Amount"]) if len(periods) > 1 else 0
        return yesterday_spend, prev_spend
    except ClientError:
        return 0.0, 0.0


# ── Risk assessment ───────────────────────────────────────────────────────────

def assess_risk(budgets: list, anomalies: list, spend_today: float, spend_yesterday: float) -> str:
    if anomalies:
        return "HIGH"
    max_pct = 0.0
    for b in budgets:
        limit = float(b.get("BudgetLimit", {}).get("Amount", 0))
        actual = float((b.get("CalculatedSpend") or {}).get("ActualSpend", {}).get("Amount", 0))
        if limit > 0:
            pct = actual / limit * 100
            max_pct = max(max_pct, pct)
    if max_pct >= 80:
        return "HIGH"
    if max_pct >= 60:
        return "MEDIUM"
    if spend_today > spend_yesterday * 1.5 and spend_yesterday > 0:
        return "MEDIUM"
    return "LOW"


# ── Slack notification ────────────────────────────────────────────────────────

def send_slack(webhook_url: str, risk: str, budgets: list, anomalies: list) -> None:
    try:
        import urllib.request
        color = {"LOW": "good", "MEDIUM": "warning", "HIGH": "danger"}.get(risk, "good")
        budget_lines = []
        for b in budgets:
            name = b["BudgetName"]
            limit = float(b.get("BudgetLimit", {}).get("Amount", 0))
            actual = float((b.get("CalculatedSpend") or {}).get("ActualSpend", {}).get("Amount", 0))
            pct = actual / limit * 100 if limit > 0 else 0
            budget_lines.append(f"• {name}: ${actual:.2f}/${limit:.2f} ({pct:.0f}%)")

        payload = {
            "attachments": [{
                "color": color,
                "title": f"AWS Financial Health: {risk}",
                "text": "\n".join(budget_lines) or "No budgets configured",
                "footer": "aws-cert-study cost monitor",
                "ts": int(time.time()),
            }]
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(webhook_url, data=data, headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=5)
        print(c("dim", "  Slack notification sent"))
    except Exception as e:
        print(c("yellow", f"  Slack notification failed: {e}"))


# ── Dashboard ─────────────────────────────────────────────────────────────────

def render(account_id: str) -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n{'═' * WIDTH}")
    print(f"  {c('bold', 'FINANCIAL HEALTH DASHBOARD')}")
    print(f"  {c('dim', now)}")
    print(f"{'═' * WIDTH}")

    try:
        session = boto3.session.Session()
        ce = session.client("ce", region_name="us-east-1")
        budgets_client = session.client("budgets", region_name="us-east-1")
    except NoCredentialsError:
        print(c("red", "\nERROR: AWS credentials not configured.\n"))
        sys.exit(1)

    budgets = get_budgets(budgets_client, account_id)
    anomalies = get_anomalies(ce)
    spend_today, spend_yesterday = get_daily_spend(ce)
    risk = assess_risk(budgets, anomalies, spend_today, spend_yesterday)

    # ── Budgets ───────────────────────────────────────────────────────────────
    section("BUDGET STATUS")
    if not budgets:
        print(c("yellow", "  No budgets found. Run: bash scripts/create-budgets.sh"))
    for b in budgets:
        name = b["BudgetName"]
        limit = float(b.get("BudgetLimit", {}).get("Amount", 0))
        actual = float((b.get("CalculatedSpend") or {}).get("ActualSpend", {}).get("Amount", 0))
        forecast = float((b.get("CalculatedSpend") or {}).get("ForecastedSpend", {}).get("Amount", 0))
        pct = (actual / limit * 100) if limit > 0 else 0

        if pct >= 80:
            status_color, status = "red", "HIGH"
        elif pct >= 60:
            status_color, status = "yellow", "MEDIUM"
        else:
            status_color, status = "green", "OK"

        bar_filled = int(pct / 5)
        bar = "█" * min(bar_filled, 20) + "░" * (20 - min(bar_filled, 20))
        print(f"  {name}")
        print(f"    Actual  : ${actual:.2f} / ${limit:.2f}  ({pct:.0f}%)")
        print(f"    Forecast: ${forecast:.2f}")
        print(f"    Status  : {c(status_color, status)}  {c(status_color, bar)}")

    # ── Anomalies ─────────────────────────────────────────────────────────────
    section("ANOMALY DETECTION  (Last 7 Days)")
    if not anomalies:
        print(c("green", "  No anomalies detected"))
    else:
        print(c("red", f"  {len(anomalies)} anomaly/anomalies detected:"))
        for a in anomalies:
            impact = float((a.get("Impact") or {}).get("TotalImpact", 0))
            start = a.get("AnomalyStartDate", "unknown")
            print(f"  Impact: ${impact:.2f}  |  Detected: {start}")

    # ── Spend rate ────────────────────────────────────────────────────────────
    section("SPEND RATE")
    if spend_yesterday > 0 and spend_today > 0:
        change = ((spend_today - spend_yesterday) / spend_yesterday) * 100
        color = "red" if change > 50 else "yellow" if change > 20 else "green"
        print(f"  Yesterday: ${spend_yesterday:.4f}")
        print(f"  Today    : ${spend_today:.4f}  ({c(color, f'{change:+.1f}%')})")
    else:
        print("  Spend rate data not available yet")

    # ── Risk ──────────────────────────────────────────────────────────────────
    section("RISK ASSESSMENT")
    risk_color = {"LOW": "green", "MEDIUM": "yellow", "HIGH": "red"}.get(risk, "green")
    actions = {
        "LOW":    "No immediate action required",
        "MEDIUM": "Monitor closely — check if Lab 05 ASG is still running",
        "HIGH":   "ACTION REQUIRED — check for runaway instances or unexpected spend",
    }
    print(f"  Overall Risk : {c(risk_color, c('bold', risk))}")
    print(f"  Action       : {actions[risk]}")
    print(f"\n  {c('dim', 'Tip: Remember to run cleanup.sh after Lab 05 — Auto Scaling = cost scaling')}")
    print(f"{'═' * WIDTH}\n")

    return risk


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="AWS Financial Health Monitor")
    parser.add_argument("--watch", action="store_true", help="Refresh every 5 minutes")
    args = parser.parse_args()

    try:
        account_id = boto3.client("sts").get_caller_identity()["Account"]
    except NoCredentialsError:
        print(c("red", "ERROR: AWS credentials not configured."))
        sys.exit(1)

    slack_url = os.environ.get("SLACK_WEBHOOK_URL", "")

    if args.watch:
        print(c("dim", "  Watch mode — refreshing every 5 minutes. Ctrl+C to stop."))
        while True:
            risk = render(account_id)
            if slack_url:
                session = boto3.session.Session()
                budgets_client = session.client("budgets", region_name="us-east-1")
                budgets = get_budgets(budgets_client, account_id)
                ce = session.client("ce", region_name="us-east-1")
                anomalies = get_anomalies(ce)
                send_slack(slack_url, risk, budgets, anomalies)
            try:
                time.sleep(300)
            except KeyboardInterrupt:
                print("\nStopped.")
                break
    else:
        risk = render(account_id)
        if slack_url:
            session = boto3.session.Session()
            budgets_client = session.client("budgets", region_name="us-east-1")
            budgets = get_budgets(budgets_client, account_id)
            ce = session.client("ce", region_name="us-east-1")
            anomalies = get_anomalies(ce)
            send_slack(slack_url, risk, budgets, anomalies)


if __name__ == "__main__":
    main()
