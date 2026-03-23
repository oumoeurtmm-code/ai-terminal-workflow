#!/usr/bin/env python3
"""
AWS Cost Explorer Dashboard
Terminal dashboard showing cost breakdown, trends, and recommendations.

Usage:
    python3 dashboard.py
    python3 dashboard.py --days 7
    python3 dashboard.py --days 90

Requirements:
    pip install boto3
"""

import argparse
import sys
from collections import defaultdict
from datetime import datetime, timedelta

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)


# ── Config ────────────────────────────────────────────────────────────────────

WIDTH = 60
BAR_WIDTH = 20

COLORS = {
    "reset":  "\033[0m",
    "bold":   "\033[1m",
    "green":  "\033[92m",
    "yellow": "\033[93m",
    "red":    "\033[91m",
    "cyan":   "\033[96m",
    "dim":    "\033[2m",
}


def c(color: str, text: str) -> str:
    return f"{COLORS.get(color, '')}{text}{COLORS['reset']}"


def bar(value: float, total: float, width: int = BAR_WIDTH) -> str:
    if total == 0:
        return "░" * width
    filled = int((value / total) * width)
    return "█" * filled + "░" * (width - filled)


def section(title: str) -> None:
    print(f"\n{c('dim', '─' * WIDTH)}")
    print(f"  {c('bold', title)}")
    print(c("dim", "─" * WIDTH))


# ── AWS calls ─────────────────────────────────────────────────────────────────

def get_cost_by_service(client, start: str, end: str) -> dict:
    resp = client.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["BlendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )
    totals = defaultdict(float)
    for period in resp["ResultsByTime"]:
        for group in period["Groups"]:
            svc = group["Keys"][0]
            cost = float(group["Metrics"]["BlendedCost"]["Amount"])
            totals[svc] += cost
    return dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))


def get_cost_by_tag(client, start: str, end: str) -> dict:
    try:
        resp = client.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["BlendedCost"],
            GroupBy=[{"Type": "TAG", "Key": "Project"}],
        )
        totals = defaultdict(float)
        for period in resp["ResultsByTime"]:
            for group in period["Groups"]:
                tag = group["Keys"][0].replace("Project$", "") or "(untagged)"
                cost = float(group["Metrics"]["BlendedCost"]["Amount"])
                totals[tag] += cost
        return dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))
    except ClientError:
        return {}


def get_daily_trend(client, days: int = 7) -> list:
    end = datetime.today()
    start = end - timedelta(days=days)
    resp = client.get_cost_and_usage(
        TimePeriod={
            "Start": start.strftime("%Y-%m-%d"),
            "End": end.strftime("%Y-%m-%d"),
        },
        Granularity="DAILY",
        Metrics=["BlendedCost"],
    )
    return [
        {
            "date": p["TimePeriod"]["Start"],
            "cost": float(p["Total"]["BlendedCost"]["Amount"]),
        }
        for p in resp["ResultsByTime"]
    ]


def get_forecast(client) -> float:
    try:
        today = datetime.today()
        # Forecast to end of month
        if today.month == 12:
            eom = datetime(today.year + 1, 1, 1)
        else:
            eom = datetime(today.year, today.month + 1, 1)

        if today.strftime("%Y-%m-%d") >= eom.strftime("%Y-%m-%d"):
            return 0.0

        resp = client.get_cost_forecast(
            TimePeriod={
                "Start": today.strftime("%Y-%m-%d"),
                "End": eom.strftime("%Y-%m-%d"),
            },
            Metric="BLENDED_COST",
            Granularity="MONTHLY",
        )
        return float(resp["Total"]["Amount"])
    except ClientError:
        return 0.0


# ── Recommendations ───────────────────────────────────────────────────────────

def recommend(by_service: dict, total: float) -> list:
    recs = []
    services = list(by_service.items())

    if services:
        top_svc, top_cost = services[0]
        pct = (top_cost / total * 100) if total > 0 else 0
        if pct > 40:
            recs.append(
                f"{top_svc} is {pct:.0f}% of spend — "
                "run cleanup.sh after each lab session to avoid idle costs"
            )

    if "Amazon RDS" in by_service and by_service["Amazon RDS"] > 0.01:
        recs.append(
            "RDS costs money even when idle — stop or delete instances between labs"
        )

    if "Amazon EC2" in by_service:
        recs.append(
            "Check for stopped EC2 instances with attached EBS volumes — "
            "EBS charges continue even when instance is stopped"
        )

    if not recs:
        recs.append("Costs look healthy — keep tagging all resources at creation")
        recs.append("Enable S3 Intelligent-Tiering if objects are rarely accessed")

    return recs[:3]


# ── Main dashboard ────────────────────────────────────────────────────────────

def main(days: int = 30) -> None:
    end = datetime.today()
    start = end - timedelta(days=days)
    start_str = start.strftime("%Y-%m-%d")
    end_str = end.strftime("%Y-%m-%d")

    print(f"\n{'═' * WIDTH}")
    print(f"  {c('bold', 'AWS COST EXPLORER DASHBOARD')}")
    print(f"  {c('dim', f'Last {days} days  ({start_str} → {end_str})')}")
    print(f"{'═' * WIDTH}")

    # Init boto3
    try:
        session = boto3.session.Session()
        client = session.client("ce", region_name="us-east-1")
    except NoCredentialsError:
        print(c("red", "\nERROR: AWS credentials not configured."))
        print("Run: aws configure  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID)\n")
        sys.exit(1)

    # Fetch data
    print(c("dim", "\n  Fetching cost data..."), end="", flush=True)
    try:
        by_service = get_cost_by_service(client, start_str, end_str)
        by_tag = get_cost_by_tag(client, start_str, end_str)
        trend = get_daily_trend(client, min(days, 7))
        forecast = get_forecast(client)
    except ClientError as e:
        print(c("red", f"\nERROR: {e.response['Error']['Message']}"))
        sys.exit(1)

    print(c("dim", " done"))

    total = sum(by_service.values())
    daily_avg = total / days if days > 0 else 0

    # ── Summary ───────────────────────────────────────────────────────────────
    section("SUMMARY")
    print(f"  Total Spend    : {c('bold', f'${total:.4f}')}")
    print(f"  Daily Average  : ${daily_avg:.4f}")
    if forecast > 0:
        print(f"  Forecast (EOM) : ${forecast:.4f}")

    # ── By service ────────────────────────────────────────────────────────────
    section("COST BY SERVICE")
    print(f"  {'SERVICE':<36} {'COST':>8}  {'SHARE':>6}  CHART")
    for svc, cost in list(by_service.items())[:10]:
        if cost < 0.0001:
            continue
        pct = (cost / total * 100) if total > 0 else 0
        b = bar(cost, total)
        short = svc[:34] if len(svc) > 34 else svc
        print(f"  {short:<36} ${cost:>7.4f}  {pct:>5.1f}%  {c('cyan', b)}")

    # ── By tag ────────────────────────────────────────────────────────────────
    if by_tag:
        section("COST BY PROJECT TAG  (Showback)")
        print(f"  {'TAG':<30} {'COST':>10}")
        for tag, cost in by_tag.items():
            if cost < 0.0001:
                continue
            color = "green" if tag != "(untagged)" else "yellow"
            print(f"  {c(color, f'{tag:<30}')} ${cost:>9.4f}")
        if "(untagged)" in by_tag and by_tag["(untagged)"] > 0.001:
            print(f"\n  {c('yellow', 'WARNING')}: Untagged resources found.")
            print("  Add tags at creation: Project=aws-cert-study")

    # ── 7-day trend ───────────────────────────────────────────────────────────
    section("7-DAY DAILY TREND")
    max_day = max((d["cost"] for d in trend), default=1) or 1
    for day in trend:
        b = bar(day["cost"], max_day)
        cost_str = f"${day['cost']:.4f}"
        print(f"  {day['date']}  {cost_str:>9}  {c('cyan', b)}")

    # ── Recommendations ───────────────────────────────────────────────────────
    section("RECOMMENDATIONS")
    recs = recommend(by_service, total)
    for i, rec in enumerate(recs, 1):
        print(f"  {c('yellow', str(i))}. {rec}")

    # ── Lab 05 tip ────────────────────────────────────────────────────────────
    print(f"\n{c('dim', '─' * WIDTH)}")
    print(f"  {c('dim', 'Tip: Run against Lab 05 to see real-time cost impact of ALB + Auto Scaling')}")
    print(f"  {c('dim', 'Set up guardrails first: finops-projects/budget-alerts-anomaly-detection/')}")
    print(f"{'═' * WIDTH}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AWS Cost Explorer Terminal Dashboard")
    parser.add_argument("--days", type=int, default=30, help="Days to query (default: 30)")
    args = parser.parse_args()
    main(days=args.days)
