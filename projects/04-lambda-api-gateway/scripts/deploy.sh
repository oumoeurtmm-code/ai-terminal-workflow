#!/bin/bash
set -euo pipefail

# ── AWS Lab 04: Lambda + API Gateway ──────────────────────────────────────────
# Deploy a serverless REST API with Lambda (Python 3.12) and API Gateway REST
# Usage: bash scripts/deploy.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS Lab 04 — Lambda + API Gateway"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── CONFIG ────────────────────────────────────────────────────────────────────
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="${AWS_REGION:-us-east-1}"
export PROJECT_TAG="aws-cert-study"
export ENV_TAG="learning"

ROLE_NAME="aws-cert-study-lab04-role"
FUNCTION_NAME="aws-cert-study-lab04-fn"
API_NAME="aws-cert-study-lab04-api"
STAGE_NAME="lab"

echo ""
echo "Account : $AWS_ACCOUNT_ID"
echo "Region  : $AWS_REGION"
echo ""

# ── STEP 1: IAM ROLE ──────────────────────────────────────────────────────────
echo "▶ Creating IAM role for Lambda..."
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --tags Key=Project,Value="$PROJECT_TAG" Key=Environment,Value="$ENV_TAG" \
  > /dev/null 2>&1 || echo "  (role already exists)"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "  ROLE_ARN=$ROLE_ARN"
echo "  Waiting 10s for IAM propagation..."
sleep 10

# ── STEP 2: ZIP AND DEPLOY LAMBDA FUNCTION ────────────────────────────────────
echo "▶ Packaging Lambda function..."
# Write handler source to /tmp and zip it
cat > /tmp/handler.py << 'PYEOF'
import json
import os

ITEMS = [
    {"id": 1, "name": "EC2 Instance", "type": "compute"},
    {"id": 2, "name": "S3 Bucket", "type": "storage"},
    {"id": 3, "name": "RDS Database", "type": "database"},
]


def lambda_handler(event, context):
    method = event.get("httpMethod", "GET")

    if method == "GET":
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "items": ITEMS,
                "count": len(ITEMS),
                "stage": os.environ.get("STAGE", "unknown")
            })
        }
    elif method == "POST":
        body = json.loads(event.get("body") or "{}")
        new_item = {
            "id": len(ITEMS) + 1,
            "name": body.get("name", "Unnamed"),
            "type": body.get("type", "unknown")
        }
        ITEMS.append(new_item)
        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"created": new_item, "total": len(ITEMS)})
        }
    else:
        return {
            "statusCode": 405,
            "body": json.dumps({"error": "Method not allowed"})
        }
PYEOF

cd /tmp && zip -q function.zip handler.py && cd - > /dev/null
echo "  Packaged → /tmp/function.zip"

echo "▶ Deploying Lambda function: $FUNCTION_NAME..."
FUNCTION_ARN=$(aws lambda create-function \
  --function-name "$FUNCTION_NAME" \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler handler.lambda_handler \
  --zip-file fileb:///tmp/function.zip \
  --memory-size 128 \
  --timeout 10 \
  --environment "Variables={STAGE=lab04}" \
  --tags Project="$PROJECT_TAG",Environment="$ENV_TAG",ManagedBy=manual \
  --query 'FunctionArn' --output text \
  --region "$AWS_REGION" 2>/dev/null || \
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file fileb:///tmp/function.zip \
    --query 'FunctionArn' --output text \
    --region "$AWS_REGION")

echo "  FUNCTION_ARN=$FUNCTION_ARN"
export FUNCTION_ARN

# ── STEP 3: CREATE REST API GATEWAY ──────────────────────────────────────────
echo "▶ Creating API Gateway REST API: $API_NAME..."
API_ID=$(aws apigateway create-rest-api \
  --name "$API_NAME" \
  --description "Lab 04 - Lambda + API Gateway REST API" \
  --endpoint-configuration types=REGIONAL \
  --tags Project="$PROJECT_TAG",Environment="$ENV_TAG",ManagedBy=manual \
  --query 'id' --output text \
  --region "$AWS_REGION")
echo "  API_ID=$API_ID"
export API_ID

# ── STEP 4: GET ROOT RESOURCE ID ─────────────────────────────────────────────
echo "▶ Getting root resource ID..."
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[?path==`/`].id' --output text \
  --region "$AWS_REGION")
echo "  ROOT_RESOURCE_ID=$ROOT_RESOURCE_ID"

# ── STEP 5: CREATE /items RESOURCE ───────────────────────────────────────────
echo "▶ Creating /items resource..."
ITEMS_RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_RESOURCE_ID" \
  --path-part "items" \
  --query 'id' --output text \
  --region "$AWS_REGION")
echo "  ITEMS_RESOURCE_ID=$ITEMS_RESOURCE_ID"
export ITEMS_RESOURCE_ID

# ── STEP 6: CREATE GET METHOD ─────────────────────────────────────────────────
echo "▶ Creating GET method on /items..."
aws apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$ITEMS_RESOURCE_ID" \
  --http-method GET \
  --authorization-type NONE \
  --region "$AWS_REGION" > /dev/null

aws apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$ITEMS_RESOURCE_ID" \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations" \
  --region "$AWS_REGION" > /dev/null
echo "  GET /items → Lambda (PROXY)"

# ── STEP 7: CREATE POST METHOD ────────────────────────────────────────────────
echo "▶ Creating POST method on /items..."
aws apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$ITEMS_RESOURCE_ID" \
  --http-method POST \
  --authorization-type NONE \
  --region "$AWS_REGION" > /dev/null

aws apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$ITEMS_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations" \
  --region "$AWS_REGION" > /dev/null
echo "  POST /items → Lambda (PROXY)"

# ── STEP 8: ADD LAMBDA INVOKE PERMISSIONS ─────────────────────────────────────
echo "▶ Adding Lambda permissions for API Gateway..."
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "apigw-get-items" \
  --action "lambda:InvokeFunction" \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/GET/items" \
  --region "$AWS_REGION" > /dev/null 2>&1 || echo "  (GET permission already exists)"

aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "apigw-post-items" \
  --action "lambda:InvokeFunction" \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/POST/items" \
  --region "$AWS_REGION" > /dev/null 2>&1 || echo "  (POST permission already exists)"
echo "  Lambda permissions granted."

# ── STEP 9: DEPLOY API TO STAGE ───────────────────────────────────────────────
echo "▶ Deploying API to stage: $STAGE_NAME..."
DEPLOYMENT_ID=$(aws apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name "$STAGE_NAME" \
  --stage-description "Lab 04 deployment" \
  --description "Initial deployment" \
  --query 'id' --output text \
  --region "$AWS_REGION")
echo "  DEPLOYMENT_ID=$DEPLOYMENT_ID"

INVOKE_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE_NAME}/items"
export INVOKE_URL

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Lab 04 deployed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " IAM Role:       $ROLE_ARN"
echo " Function ARN:   $FUNCTION_ARN"
echo " API ID:         $API_ID"
echo " Invoke URL:     $INVOKE_URL"
echo ""
echo " Test commands:"
echo ""
echo " # GET — list all items"
echo " curl -s $INVOKE_URL | python3 -m json.tool"
echo ""
echo " # POST — create a new item"
echo ' curl -s -X POST \'
echo "   -H 'Content-Type: application/json' \\"
echo "   -d '{\"name\": \"Lambda Function\", \"type\": \"compute\"}' \\"
echo "   $INVOKE_URL | python3 -m json.tool"
echo ""
echo " ⚠️  Remember to run cleanup.sh when done!"
echo ""
