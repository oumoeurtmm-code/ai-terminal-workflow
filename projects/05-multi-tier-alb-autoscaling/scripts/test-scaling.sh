#!/bin/bash
# =============================================================================
# Lab 05 — Test Auto Scaling
# Generates load to trigger scale-out events and monitors ASG activity
# =============================================================================

set -euo pipefail

# Load env
[[ -f /tmp/lab05-env.sh ]] && source /tmp/lab05-env.sh

ALB_DNS="${ALB_DNS:?ERROR: Set ALB_DNS before running (e.g., export ALB_DNS=your-alb-dns.elb.amazonaws.com)}"
ASG_NAME="${ASG_NAME:-lab05-alb-autoscaling-asg}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo "======================================================"
echo -e "  ${BOLD}Lab 05 — Auto Scaling Load Test${NC}"
echo "======================================================"
echo "  ALB : http://$ALB_DNS"
echo "  ASG : $ASG_NAME"
echo ""

# ── Verify ALB is healthy ─────────────────────────────────────────────────────
echo -e "  ${DIM}Checking ALB health...${NC}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS" --max-time 10 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo -e "  ALB: ${GREEN}healthy (HTTP $HTTP_STATUS)${NC}"
else
  echo -e "  ALB: ${YELLOW}HTTP $HTTP_STATUS — instances may still be starting up${NC}"
  echo "  Wait 2-3 minutes after deploy before running this script"
fi

# ── Check initial instance count ──────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Initial ASG State${NC}"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Count:length(Instances)}' \
  --output table

# ── Observe ALB routing ───────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}ALB Request Routing — 10 requests${NC}"
echo -e "  ${DIM}Watch the Instance ID change as ALB cycles across targets${NC}"
echo ""

for i in $(seq 1 10); do
  RESPONSE=$(curl -s "http://$ALB_DNS" --max-time 5 2>/dev/null || echo "TIMEOUT")
  INSTANCE=$(echo "$RESPONSE" | grep -oP 'i-[a-f0-9]+' | head -1 || echo "unknown")
  AZ=$(echo "$RESPONSE" | grep -A1 'Availability Zone' | grep -oP 'us-[a-z]+-[0-9][a-z]' | head -1 || echo "unknown")
  echo -e "  Request $i → Instance: ${CYAN}${INSTANCE}${NC}  AZ: ${GREEN}${AZ}${NC}"
  sleep 1
done

# ── Generate load (curl loop) ─────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Generating Load — 60 seconds${NC}"
echo -e "  ${DIM}Sending concurrent requests to spike CPU and trigger scale-out${NC}"
echo "  Target CPU threshold: 50% (target tracking policy)"
echo ""

LOAD_PID_FILE="/tmp/lab05-load-pids"
> "$LOAD_PID_FILE"

# Start 10 parallel curl loops
for worker in $(seq 1 10); do
  (while true; do
    curl -s "http://$ALB_DNS" -o /dev/null --max-time 3 2>/dev/null || true
  done) &
  echo $! >> "$LOAD_PID_FILE"
done

echo -e "  ${GREEN}Load test running (10 workers)${NC}"
echo "  Monitoring ASG every 15 seconds for 90 seconds..."
echo ""

# Monitor for 90 seconds
for check in $(seq 1 6); do
  sleep 15
  COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text 2>/dev/null || echo "?")
  INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy`].InstanceId' \
    --output text 2>/dev/null | wc -w)
  echo -e "  Check $check/6 — Desired: ${CYAN}${COUNT}${NC}  Healthy: ${GREEN}${INSTANCES}${NC}  ($(date +%H:%M:%S))"
done

# Stop load test
echo ""
echo "  Stopping load test..."
while read -r pid; do
  kill "$pid" 2>/dev/null || true
done < "$LOAD_PID_FILE"
rm -f "$LOAD_PID_FILE"
echo -e "  ${GREEN}Load stopped${NC}"

# ── Show scaling activity ─────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Recent Scaling Activity${NC}"
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 5 \
  --query 'Activities[*].{Description:Description,Status:StatusCode,Start:StartTime}' \
  --output table 2>/dev/null

# ── Final state ───────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Final ASG State${NC}"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize}' \
  --output table

echo ""
echo "======================================================"
echo -e "  ${GREEN}Load test complete${NC}"
echo "======================================================"
echo ""
echo "  The ASG will scale back in after the scale-in cooldown (300s)."
echo "  Monitor costs: bash scripts/finops-check.sh"
echo "  Clean up when done: bash scripts/cleanup.sh"
echo ""
echo "  GIF tip: Record this session for docs/gifs/02-scaling-event.gif"
echo ""
