#!/bin/bash
# =============================================================================
# Lab 05 — Multi-Tier Architecture: ALB + Auto Scaling
# Deploys: VPC · Public Subnets · IGW · ALB · Launch Template · ASG · CloudWatch
# FinOps Integration: budget guardrails + cost tagging
# =============================================================================

set -euo pipefail

# ── Environment Variables ─────────────────────────────────────────────────────
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export LAB_NAME="lab05-alb-autoscaling"
export TIMESTAMP=$(date +%s)

# VPC
export VPC_CIDR="10.0.0.0/16"
export SUBNET1_CIDR="10.0.1.0/24"
export SUBNET2_CIDR="10.0.2.0/24"
export AZ1="${AWS_DEFAULT_REGION}a"
export AZ2="${AWS_DEFAULT_REGION}b"

# ASG
export AMI_ID="ami-0c02fb55956c7d316"  # Amazon Linux 2 (us-east-1)
export INSTANCE_TYPE="t3.micro"
export ASG_MIN=1
export ASG_MAX=3
export ASG_DESIRED=2

# ALB
export ALB_NAME="${LAB_NAME}-alb"
export TG_NAME="${LAB_NAME}-tg"
export ASG_NAME="${LAB_NAME}-asg"
export LT_NAME="${LAB_NAME}-lt"
export SNS_TOPIC_NAME="${LAB_NAME}-notifications"

# Standard tags for all resources
TAGS="Key=Project,Value=aws-cert-study Key=Environment,Value=learning Key=Owner,Value=your-name Key=CostCenter,Value=personal-dev Key=ManagedBy,Value=manual Key=Lab,Value=05-alb-autoscaling"

echo ""
echo "======================================================"
echo "  Lab 05 — ALB + Auto Scaling Deploy"
echo "======================================================"
echo "  Account : $AWS_ACCOUNT_ID"
echo "  Region  : $AWS_DEFAULT_REGION"
echo "  AZs     : $AZ1 + $AZ2"
echo "  AMI     : $AMI_ID ($INSTANCE_TYPE)"
echo "  ASG     : min=$ASG_MIN desired=$ASG_DESIRED max=$ASG_MAX"
echo ""
echo "  FinOps Reminder: Run 'bash scripts/finops-check.sh' after deploy"
echo "  to set up cost guardrails before starting the lab."
echo ""

# ── Step 1: Create VPC ────────────────────────────────────────────────────────
echo "======================================================"
echo "  [1/12] Creating VPC..."
echo "======================================================"

VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 create-tags --resources "$VPC_ID" \
  --tags Key=Name,Value="${LAB_NAME}-vpc" $TAGS

aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support

export VPC_ID
echo "  VPC: $VPC_ID"

# ── Step 2: Create Subnets ────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [2/12] Creating public subnets across 2 AZs..."
echo "======================================================"

SUBNET1_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET1_CIDR" \
  --availability-zone "$AZ1" \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags --resources "$SUBNET1_ID" \
  --tags Key=Name,Value="${LAB_NAME}-subnet-public-1" $TAGS

aws ec2 modify-subnet-attribute --subnet-id "$SUBNET1_ID" --map-public-ip-on-launch

SUBNET2_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET2_CIDR" \
  --availability-zone "$AZ2" \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags --resources "$SUBNET2_ID" \
  --tags Key=Name,Value="${LAB_NAME}-subnet-public-2" $TAGS

aws ec2 modify-subnet-attribute --subnet-id "$SUBNET2_ID" --map-public-ip-on-launch

export SUBNET1_ID SUBNET2_ID
echo "  Subnet 1 ($AZ1): $SUBNET1_ID"
echo "  Subnet 2 ($AZ2): $SUBNET2_ID"

# ── Step 3: Internet Gateway + Route Table ────────────────────────────────────
echo ""
echo "======================================================"
echo "  [3/12] Creating Internet Gateway and routing..."
echo "======================================================"

IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 create-tags --resources "$IGW_ID" \
  --tags Key=Name,Value="${LAB_NAME}-igw" $TAGS

aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-tags --resources "$RTB_ID" \
  --tags Key=Name,Value="${LAB_NAME}-rtb-public" $TAGS

aws ec2 create-route \
  --route-table-id "$RTB_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" > /dev/null

aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET1_ID" > /dev/null
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET2_ID" > /dev/null

export IGW_ID RTB_ID
echo "  IGW: $IGW_ID"
echo "  Route Table: $RTB_ID"

# ── Step 4: Security Groups ───────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [4/12] Creating security groups..."
echo "======================================================"

# ALB security group — allow HTTP from anywhere
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name "${LAB_NAME}-alb-sg" \
  --description "Lab 05 ALB — allows inbound HTTP from internet" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags --resources "$ALB_SG_ID" \
  --tags Key=Name,Value="${LAB_NAME}-alb-sg" $TAGS

aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null

echo "  ALB Security Group: $ALB_SG_ID"

# EC2 security group — allow HTTP only from ALB
EC2_SG_ID=$(aws ec2 create-security-group \
  --group-name "${LAB_NAME}-ec2-sg" \
  --description "Lab 05 EC2 — allows inbound HTTP from ALB only" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags --resources "$EC2_SG_ID" \
  --tags Key=Name,Value="${LAB_NAME}-ec2-sg" $TAGS

aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG_ID" \
  --protocol tcp --port 80 \
  --source-group "$ALB_SG_ID" > /dev/null

export ALB_SG_ID EC2_SG_ID
echo "  EC2 Security Group: $EC2_SG_ID"

# ── Step 5: Target Group ──────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [5/12] Creating ALB Target Group..."
echo "======================================================"

TG_ARN=$(aws elbv2 create-target-group \
  --name "$TG_NAME" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --health-check-path / \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 add-tags --resource-arns "$TG_ARN" \
  --tags Key=Name,Value="$TG_NAME" Key=Project,Value=aws-cert-study Key=Lab,Value=05-alb-autoscaling

export TG_ARN
echo "  Target Group: $TG_ARN"

# ── Step 6: Application Load Balancer ────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [6/12] Creating Application Load Balancer..."
echo "======================================================"

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "$ALB_NAME" \
  --subnets "$SUBNET1_ID" "$SUBNET2_ID" \
  --security-groups "$ALB_SG_ID" \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

aws elbv2 add-tags --resource-arns "$ALB_ARN" \
  --tags Key=Name,Value="$ALB_NAME" Key=Project,Value=aws-cert-study Key=Lab,Value=05-alb-autoscaling

# Create listener
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --query 'Listeners[0].ListenerArn' \
  --output text)

export ALB_ARN LISTENER_ARN
echo "  ALB ARN: $ALB_ARN"
echo "  Listener: $LISTENER_ARN"
echo "  Waiting for ALB to become active..."

aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

export ALB_DNS
echo "  ALB DNS: $ALB_DNS"

# ── Step 7: Launch Template ───────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [7/12] Creating Launch Template..."
echo "======================================================"

# User data: install Apache, display instance metadata on the page
USER_DATA=$(cat <<'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
  <title>Lab 05 — ALB + Auto Scaling</title>
  <style>
    body { font-family: monospace; background: #0d1117; color: #c9d1d9; padding: 40px; }
    .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 24px; max-width: 500px; }
    h1 { color: #58a6ff; }
    .label { color: #8b949e; font-size: 12px; }
    .value { color: #3fb950; font-size: 18px; font-weight: bold; }
    .badge { background: #1f6feb; color: white; padding: 4px 10px; border-radius: 4px; font-size: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Lab 05 — Multi-Tier AWS</h1>
    <span class="badge">Auto Scaling Group</span>
    <br><br>
    <div class="label">Instance ID</div>
    <div class="value">$INSTANCE_ID</div>
    <br>
    <div class="label">Availability Zone</div>
    <div class="value">$AZ</div>
    <br>
    <div class="label">Private IP</div>
    <div class="value">$LOCAL_IP</div>
    <br>
    <div class="label">Served via</div>
    <div class="value">Application Load Balancer</div>
  </div>
</body>
</html>
HTML
EOF
)

ENCODED_USER_DATA=$(echo "$USER_DATA" | base64 | tr -d '\n')

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "$LT_NAME" \
  --version-description "Lab 05 initial version" \
  --launch-template-data "{
    \"ImageId\": \"${AMI_ID}\",
    \"InstanceType\": \"${INSTANCE_TYPE}\",
    \"SecurityGroupIds\": [\"${EC2_SG_ID}\"],
    \"UserData\": \"${ENCODED_USER_DATA}\",
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [
        {\"Key\": \"Name\", \"Value\": \"${LAB_NAME}-instance\"},
        {\"Key\": \"Project\", \"Value\": \"aws-cert-study\"},
        {\"Key\": \"Environment\", \"Value\": \"learning\"},
        {\"Key\": \"Owner\", \"Value\": \"your-name\"},
        {\"Key\": \"Lab\", \"Value\": \"05-alb-autoscaling\"}
      ]
    }]
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' \
  --output text)

export LT_ID
echo "  Launch Template: $LT_ID"

# ── Step 8: Auto Scaling Group ────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [8/12] Creating Auto Scaling Group..."
echo "======================================================"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest" \
  --min-size "$ASG_MIN" \
  --max-size "$ASG_MAX" \
  --desired-capacity "$ASG_DESIRED" \
  --vpc-zone-identifier "${SUBNET1_ID},${SUBNET2_ID}" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 120 \
  --tags \
    "Key=Name,Value=${LAB_NAME}-instance,PropagateAtLaunch=true" \
    "Key=Project,Value=aws-cert-study,PropagateAtLaunch=true" \
    "Key=Environment,Value=learning,PropagateAtLaunch=true" \
    "Key=Owner,Value=your-name,PropagateAtLaunch=true" \
    "Key=Lab,Value=05-alb-autoscaling,PropagateAtLaunch=true"

echo "  ASG: $ASG_NAME"
echo "  Capacity: min=$ASG_MIN desired=$ASG_DESIRED max=$ASG_MAX"

# ── Step 9: Scaling Policies ──────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [9/12] Creating Target Tracking Scaling Policy..."
echo "======================================================"

POLICY_ARN=$(aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "$ASG_NAME" \
  --policy-name "${LAB_NAME}-cpu-target-tracking" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 50.0,
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 120
  }' \
  --query 'PolicyARN' \
  --output text)

echo "  Scaling Policy: Target CPU = 50%"
echo "  Scale-out cooldown: 120s | Scale-in cooldown: 300s"

# ── Step 10: SNS Topic for notifications ──────────────────────────────────────
echo ""
echo "======================================================"
echo "  [10/12] Creating SNS Topic for scaling notifications..."
echo "======================================================"

SNS_ARN=$(aws sns create-topic \
  --name "$SNS_TOPIC_NAME" \
  --query 'TopicArn' \
  --output text)

aws sns tag-resource \
  --resource-arn "$SNS_ARN" \
  --tags Key=Project,Value=aws-cert-study Key=Lab,Value=05-alb-autoscaling 2>/dev/null || true

aws autoscaling put-notification-configuration \
  --auto-scaling-group-name "$ASG_NAME" \
  --topic-arn "$SNS_ARN" \
  --notification-types \
    "autoscaling:EC2_INSTANCE_LAUNCH" \
    "autoscaling:EC2_INSTANCE_TERMINATE"

export SNS_ARN
echo "  SNS Topic: $SNS_ARN"
echo "  Notifications: LAUNCH + TERMINATE events"

# ── Step 11: CloudWatch Alarm ─────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [11/12] Creating CloudWatch CPU alarm..."
echo "======================================================"

aws cloudwatch put-metric-alarm \
  --alarm-name "${LAB_NAME}-high-cpu" \
  --alarm-description "Lab 05 — CPU exceeds 70% for 2 periods" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 120 \
  --evaluation-periods 2 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --dimensions "Name=AutoScalingGroupName,Value=${ASG_NAME}" \
  --alarm-actions "$SNS_ARN" \
  --ok-actions "$SNS_ARN"

echo "  CloudWatch Alarm: ${LAB_NAME}-high-cpu (trigger at CPU > 70%)"

# ── Step 12: Summary ──────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  [12/12] Verifying resources..."
echo "======================================================"

INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text | wc -w)

echo "  ASG Instances: $INSTANCE_COUNT (desired: $ASG_DESIRED — may take 1-2 min)"

echo ""
echo "======================================================"
echo "  Lab 05 Deploy Complete"
echo "======================================================"
echo ""
echo "  VPC              : $VPC_ID"
echo "  Subnets          : $SUBNET1_ID | $SUBNET2_ID"
echo "  ALB DNS          : http://$ALB_DNS"
echo "  Target Group     : $TG_ARN"
echo "  Auto Scaling Grp : $ASG_NAME (min=$ASG_MIN max=$ASG_MAX)"
echo "  Launch Template  : $LT_ID"
echo "  SNS Topic        : $SNS_ARN"
echo ""
echo "  Access the app   : http://$ALB_DNS"
echo "  Test scaling     : bash scripts/test-scaling.sh"
echo "  Check costs      : bash scripts/finops-check.sh"
echo "  Clean up         : bash scripts/cleanup.sh"
echo ""
echo "  FinOps: EC2 costs begin immediately. Run cleanup.sh when done."
echo ""

# Export all key variables for use by other scripts
cat > /tmp/lab05-env.sh <<ENV
export VPC_ID="${VPC_ID}"
export SUBNET1_ID="${SUBNET1_ID}"
export SUBNET2_ID="${SUBNET2_ID}"
export IGW_ID="${IGW_ID}"
export RTB_ID="${RTB_ID}"
export ALB_SG_ID="${ALB_SG_ID}"
export EC2_SG_ID="${EC2_SG_ID}"
export TG_ARN="${TG_ARN}"
export ALB_ARN="${ALB_ARN}"
export ALB_DNS="${ALB_DNS}"
export LISTENER_ARN="${LISTENER_ARN}"
export LT_ID="${LT_ID}"
export ASG_NAME="${ASG_NAME}"
export SNS_ARN="${SNS_ARN}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}"
ENV
echo "  Environment saved to /tmp/lab05-env.sh"
echo "  Source it in new shells: source /tmp/lab05-env.sh"
