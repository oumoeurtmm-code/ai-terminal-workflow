#!/bin/bash
# =============================================================================
# Budget Alerts & Anomaly Detection — Create Budgets
# Creates 3 AWS Budgets with SNS alerts and email subscription
# =============================================================================

set -euo pipefail

# ── Variables ────────────────────────────────────────────────────────────────
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
EMAIL_ADDRESS="${EMAIL_ADDRESS:?ERROR: Set EMAIL_ADDRESS before running this script}"
SNS_TOPIC_NAME="aws-cert-study-budget-alerts"

echo ""
echo "======================================================"
echo "  Budget Alerts & Anomaly Detection — Create Budgets"
echo "======================================================"
echo "  Account : $AWS_ACCOUNT_ID"
echo "  Region  : $AWS_DEFAULT_REGION"
echo "  Email   : $EMAIL_ADDRESS"
echo ""

# ── Step 1: Create SNS topic ──────────────────────────────────────────────────
echo "[1/5] Creating SNS topic for budget alerts..."

SNS_TOPIC_ARN=$(aws sns create-topic \
  --name "$SNS_TOPIC_NAME" \
  --tags "Key=Project,Value=aws-cert-study" \
         "Key=Environment,Value=learning" \
         "Key=Owner,Value=your-name" \
         "Key=CostCenter,Value=personal-dev" \
         "Key=ManagedBy,Value=manual" \
  --query 'TopicArn' \
  --output text)

export SNS_TOPIC_ARN
echo "  SNS Topic ARN: $SNS_TOPIC_ARN"

# ── Step 2: Subscribe email ───────────────────────────────────────────────────
echo ""
echo "[2/5] Subscribing $EMAIL_ADDRESS to alerts..."

aws sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$EMAIL_ADDRESS" \
  --output text > /dev/null

echo "  Subscription pending — check $EMAIL_ADDRESS to confirm"

# ── Step 3: Create monthly overall budget ─────────────────────────────────────
echo ""
echo "[3/5] Creating monthly overall budget (\$10 limit)..."

BUDGET_MONTHLY='{
  "BudgetName": "aws-cert-study-monthly",
  "BudgetLimit": {
    "Amount": "10",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}'

NOTIFICATIONS_MONTHLY='[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "SNS",
        "Address": "'"$SNS_TOPIC_ARN"'"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "'"$EMAIL_ADDRESS"'"
      }
    ]
  },
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 100,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "SNS",
        "Address": "'"$SNS_TOPIC_ARN"'"
      },
      {
        "SubscriptionType": "EMAIL",
        "Address": "'"$EMAIL_ADDRESS"'"
      }
    ]
  }
]'

aws budgets create-budget \
  --account-id "$AWS_ACCOUNT_ID" \
  --budget "$BUDGET_MONTHLY" \
  --notifications-with-subscribers "$NOTIFICATIONS_MONTHLY" 2>/dev/null && \
  echo "  Created: aws-cert-study-monthly (\$10/month, alerts at 80% and 100%)" || \
  echo "  Budget already exists: aws-cert-study-monthly"

# ── Step 4: Create project-tagged budget ──────────────────────────────────────
echo ""
echo "[4/5] Creating per-project budget (\$8 limit, Project=aws-cert-study)..."

BUDGET_PROJECT='{
  "BudgetName": "aws-cert-study-project",
  "BudgetLimit": {
    "Amount": "8",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "TagKeyValue": ["user:Project$aws-cert-study"]
  }
}'

NOTIFICATIONS_PROJECT='[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 75,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "'"$EMAIL_ADDRESS"'"
      }
    ]
  }
]'

aws budgets create-budget \
  --account-id "$AWS_ACCOUNT_ID" \
  --budget "$BUDGET_PROJECT" \
  --notifications-with-subscribers "$NOTIFICATIONS_PROJECT" 2>/dev/null && \
  echo "  Created: aws-cert-study-project (\$8/month, alert at 75%)" || \
  echo "  Budget already exists: aws-cert-study-project"

# ── Step 5: Create EC2-specific budget (Lab 05 guard) ─────────────────────────
echo ""
echo "[5/5] Creating EC2-specific budget (\$5 limit — Lab 05 guard)..."

BUDGET_EC2='{
  "BudgetName": "aws-cert-study-ec2",
  "BudgetLimit": {
    "Amount": "5",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "Service": ["Amazon Elastic Compute Cloud - Compute"]
  }
}'

NOTIFICATIONS_EC2='[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 70,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "'"$EMAIL_ADDRESS"'"
      }
    ]
  }
]'

aws budgets create-budget \
  --account-id "$AWS_ACCOUNT_ID" \
  --budget "$BUDGET_EC2" \
  --notifications-with-subscribers "$NOTIFICATIONS_EC2" 2>/dev/null && \
  echo "  Created: aws-cert-study-ec2 (\$5/month, alert at 70%)" || \
  echo "  Budget already exists: aws-cert-study-ec2"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  Budgets Created"
echo "======================================================"
echo ""
echo "  Budgets:"
echo "    aws-cert-study-monthly  \$10/month — alerts at 80% and 100%"
echo "    aws-cert-study-project   \$8/month — alert at 75%"
echo "    aws-cert-study-ec2       \$5/month — alert at 70% (Lab 05 guard)"
echo ""
echo "  SNS Topic : $SNS_TOPIC_ARN"
echo "  Email     : $EMAIL_ADDRESS (confirm subscription in inbox)"
echo ""
echo "  Next step: bash scripts/setup-anomaly.sh"
echo "  Cleanup  : bash scripts/cleanup.sh"
echo ""

export SNS_TOPIC_ARN
export AWS_ACCOUNT_ID
