#!/bin/bash
set -euo pipefail

# ── AWS Lab 03: RDS + EC2 Two-Tier App ────────────────────────────────────────
# Deploy an EC2 app server + RDS MySQL database in a two-tier VPC architecture
# Usage: bash scripts/deploy.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS Lab 03 — RDS + EC2 Two-Tier App"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── CONFIG ────────────────────────────────────────────────────────────────────
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="${AWS_REGION:-us-east-1}"
export PROJECT_TAG="aws-cert-study"
export ENV_TAG="learning"

VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_1_CIDR="10.0.2.0/24"
PRIVATE_SUBNET_2_CIDR="10.0.3.0/24"
EC2_INSTANCE_TYPE="t3.micro"
DB_INSTANCE_CLASS="db.t3.micro"
DB_ENGINE="mysql"
DB_ENGINE_VERSION="8.0"
DB_NAME="labdb"
DB_USERNAME="admin"
DB_IDENTIFIER="aws-cert-study-rds"

echo ""
echo "Account : $AWS_ACCOUNT_ID"
echo "Region  : $AWS_REGION"
echo ""

# ── TAGS HELPER ───────────────────────────────────────────────────────────────
tag_resource() {
  local resource_id="$1"
  local name="$2"
  aws ec2 create-tags --resources "$resource_id" --tags \
    Key=Name,Value="$name" \
    Key=Project,Value="$PROJECT_TAG" \
    Key=Environment,Value="$ENV_TAG" \
    Key=ManagedBy,Value=manual \
    --region "$AWS_REGION"
}

# ── STEP 1: VPC ───────────────────────────────────────────────────────────────
echo "▶ Creating VPC ($VPC_CIDR)..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --query 'Vpc.VpcId' --output text \
  --region "$AWS_REGION")
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$AWS_REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support --region "$AWS_REGION"
tag_resource "$VPC_ID" "aws-cert-study-vpc"
echo "  VPC_ID=$VPC_ID"
export VPC_ID

# ── STEP 2: SUBNETS ───────────────────────────────────────────────────────────
echo "▶ Creating public subnet (EC2 app server)..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PUBLIC_SUBNET_CIDR" \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' --output text \
  --region "$AWS_REGION")
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch --region "$AWS_REGION"
tag_resource "$PUBLIC_SUBNET_ID" "aws-cert-study-public"
echo "  PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID"
export PUBLIC_SUBNET_ID

echo "▶ Creating private subnet 1 (RDS primary - us-east-1a)..."
PRIVATE_SUBNET_1_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PRIVATE_SUBNET_1_CIDR" \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' --output text \
  --region "$AWS_REGION")
tag_resource "$PRIVATE_SUBNET_1_ID" "aws-cert-study-private-1"
echo "  PRIVATE_SUBNET_1_ID=$PRIVATE_SUBNET_1_ID"
export PRIVATE_SUBNET_1_ID

echo "▶ Creating private subnet 2 (RDS standby - us-east-1b)..."
PRIVATE_SUBNET_2_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PRIVATE_SUBNET_2_CIDR" \
  --availability-zone "${AWS_REGION}b" \
  --query 'Subnet.SubnetId' --output text \
  --region "$AWS_REGION")
tag_resource "$PRIVATE_SUBNET_2_ID" "aws-cert-study-private-2"
echo "  PRIVATE_SUBNET_2_ID=$PRIVATE_SUBNET_2_ID"
export PRIVATE_SUBNET_2_ID

# ── STEP 3: INTERNET GATEWAY ──────────────────────────────────────────────────
echo "▶ Creating and attaching Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' --output text \
  --region "$AWS_REGION")
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
tag_resource "$IGW_ID" "aws-cert-study-igw"
echo "  IGW_ID=$IGW_ID"
export IGW_ID

# ── STEP 4: PUBLIC ROUTE TABLE ────────────────────────────────────────────────
echo "▶ Creating public route table..."
PUBLIC_RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' --output text \
  --region "$AWS_REGION")
aws ec2 create-route --route-table-id "$PUBLIC_RTB_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" --region "$AWS_REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUBLIC_RTB_ID" --subnet-id "$PUBLIC_SUBNET_ID" --region "$AWS_REGION" > /dev/null
tag_resource "$PUBLIC_RTB_ID" "aws-cert-study-public-rtb"
echo "  PUBLIC_RTB_ID=$PUBLIC_RTB_ID"
export PUBLIC_RTB_ID

# ── STEP 5: SECURITY GROUPS ───────────────────────────────────────────────────
echo "▶ Creating EC2 security group..."
EC2_SG_ID=$(aws ec2 create-security-group \
  --group-name "aws-cert-study-ec2-sg" \
  --description "Lab 03 - EC2 app server - SSM + MySQL egress" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text \
  --region "$AWS_REGION")
# Egress: 443 for SSM, 3306 for RDS
aws ec2 authorize-security-group-egress \
  --group-id "$EC2_SG_ID" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" > /dev/null
# Remove default allow-all egress (will add 3306 after RDS SG is created)
aws ec2 revoke-security-group-egress \
  --group-id "$EC2_SG_ID" \
  --protocol -1 --port -1 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" 2>/dev/null || true
tag_resource "$EC2_SG_ID" "aws-cert-study-ec2-sg"
echo "  EC2_SG_ID=$EC2_SG_ID"
export EC2_SG_ID

echo "▶ Creating RDS security group..."
RDS_SG_ID=$(aws ec2 create-security-group \
  --group-name "aws-cert-study-rds-sg" \
  --description "Lab 03 - RDS MySQL - inbound from EC2 SG only" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text \
  --region "$AWS_REGION")
# Inbound: MySQL 3306 from EC2 SG only
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG_ID" \
  --protocol tcp --port 3306 \
  --source-group "$EC2_SG_ID" \
  --region "$AWS_REGION" > /dev/null
# Remove default allow-all egress from RDS SG
aws ec2 revoke-security-group-egress \
  --group-id "$RDS_SG_ID" \
  --protocol -1 --port -1 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" 2>/dev/null || true
tag_resource "$RDS_SG_ID" "aws-cert-study-rds-sg"
echo "  RDS_SG_ID=$RDS_SG_ID"
export RDS_SG_ID

# Add MySQL egress to EC2 SG (now that RDS SG exists)
aws ec2 authorize-security-group-egress \
  --group-id "$EC2_SG_ID" \
  --protocol tcp --port 3306 \
  --source-group "$RDS_SG_ID" \
  --region "$AWS_REGION" > /dev/null
echo "  EC2 SG egress: 443 (SSM) + 3306 -> RDS SG"

# ── STEP 6: IAM ROLE ──────────────────────────────────────────────────────────
echo "▶ Creating IAM role (SSM + Secrets Manager)..."
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

aws iam create-role \
  --role-name "aws-cert-study-lab03-role" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --tags Key=Project,Value="$PROJECT_TAG" Key=Environment,Value="$ENV_TAG" \
  > /dev/null 2>&1 || echo "  (role already exists)"

aws iam attach-role-policy \
  --role-name "aws-cert-study-lab03-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true

aws iam attach-role-policy \
  --role-name "aws-cert-study-lab03-role" \
  --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite" 2>/dev/null || true

INSTANCE_PROFILE_NAME="aws-cert-study-lab03-profile"
aws iam create-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" > /dev/null 2>&1 || true
aws iam add-role-to-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --role-name "aws-cert-study-lab03-role" 2>/dev/null || true

echo "  IAM role ready. Waiting 10s for propagation..."
sleep 10

# ── STEP 7: SECRETS MANAGER ───────────────────────────────────────────────────
echo "▶ Storing DB credentials in Secrets Manager..."
DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)

SECRET_ARN=$(aws secretsmanager create-secret \
  --name "aws-cert-study/lab03/db-credentials" \
  --description "Lab 03 RDS MySQL credentials" \
  --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"$DB_PASSWORD\",\"dbname\":\"$DB_NAME\"}" \
  --tags Key=Project,Value="$PROJECT_TAG" Key=Environment,Value="$ENV_TAG" \
  --query 'ARN' --output text \
  --region "$AWS_REGION" 2>/dev/null || \
  aws secretsmanager update-secret \
    --secret-id "aws-cert-study/lab03/db-credentials" \
    --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"$DB_PASSWORD\",\"dbname\":\"$DB_NAME\"}" \
    --query 'ARN' --output text \
    --region "$AWS_REGION")

echo "  SECRET_ARN=$SECRET_ARN"
export SECRET_ARN DB_PASSWORD

# ── STEP 8: DB SUBNET GROUP ───────────────────────────────────────────────────
echo "▶ Creating DB subnet group (requires 2 AZs)..."
aws rds create-db-subnet-group \
  --db-subnet-group-name "aws-cert-study-db-subnet-group" \
  --db-subnet-group-description "Lab 03 - private subnets for RDS" \
  --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
  --tags Key=Project,Value="$PROJECT_TAG" Key=Environment,Value="$ENV_TAG" \
  --region "$AWS_REGION" > /dev/null 2>&1 || echo "  (subnet group already exists)"
echo "  DB subnet group ready."

# ── STEP 9: RDS INSTANCE ──────────────────────────────────────────────────────
echo "▶ Creating RDS MySQL instance (this takes 5-10 minutes)..."
aws rds create-db-instance \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --db-instance-class "$DB_INSTANCE_CLASS" \
  --engine "$DB_ENGINE" \
  --engine-version "$DB_ENGINE_VERSION" \
  --master-username "$DB_USERNAME" \
  --master-user-password "$DB_PASSWORD" \
  --db-name "$DB_NAME" \
  --allocated-storage 20 \
  --storage-type gp2 \
  --no-multi-az \
  --no-publicly-accessible \
  --db-subnet-group-name "aws-cert-study-db-subnet-group" \
  --vpc-security-group-ids "$RDS_SG_ID" \
  --backup-retention-period 0 \
  --no-deletion-protection \
  --tags Key=Project,Value="$PROJECT_TAG" Key=Environment,Value="$ENV_TAG" Key=ManagedBy,Value=manual \
  --region "$AWS_REGION" > /dev/null 2>&1 || echo "  (RDS instance already exists)"

echo "  Waiting for RDS to become available (~8 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$AWS_REGION"

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].Endpoint.Address' --output text \
  --region "$AWS_REGION")
echo "  RDS_ENDPOINT=$RDS_ENDPOINT"
export RDS_ENDPOINT

# ── STEP 10: EC2 INSTANCE ─────────────────────────────────────────────────────
echo "▶ Fetching latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text \
  --region "$AWS_REGION")
echo "  AMI_ID=$AMI_ID"

echo "▶ Launching EC2 app server..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$EC2_INSTANCE_TYPE" \
  --subnet-id "$PUBLIC_SUBNET_ID" \
  --security-group-ids "$EC2_SG_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
  --associate-public-ip-address \
  --user-data "$(cat <<'USERDATA'
#!/bin/bash
yum install -y mysql
USERDATA
)" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=aws-cert-study-app-server},{Key=Project,Value=aws-cert-study},{Key=Environment,Value=learning},{Key=ManagedBy,Value=manual}]" \
    "ResourceType=volume,Tags=[{Key=Project,Value=aws-cert-study},{Key=Environment,Value=learning}]" \
  --query 'Instances[0].InstanceId' --output text \
  --region "$AWS_REGION")
echo "  INSTANCE_ID=$INSTANCE_ID — waiting for running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
echo "  EC2 app server running."
export INSTANCE_ID AMI_ID

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ Lab 03 deployed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " VPC:             $VPC_ID"
echo " Public Subnet:   $PUBLIC_SUBNET_ID"
echo " Private Subnet 1: $PRIVATE_SUBNET_1_ID"
echo " Private Subnet 2: $PRIVATE_SUBNET_2_ID"
echo " EC2 SG:          $EC2_SG_ID"
echo " RDS SG:          $RDS_SG_ID"
echo " RDS Endpoint:    $RDS_ENDPOINT"
echo " EC2 Instance:    $INSTANCE_ID"
echo " Secret:          aws-cert-study/lab03/db-credentials"
echo ""
echo " Connect via SSM (wait ~2 min for agent registration):"
echo " aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
echo ""
echo " Then connect to RDS from inside the instance:"
echo " SECRET=\$(aws secretsmanager get-secret-value --secret-id aws-cert-study/lab03/db-credentials --query SecretString --output text --region $AWS_REGION)"
echo " DB_PASS=\$(echo \$SECRET | python3 -c \"import sys,json; print(json.load(sys.stdin)['password'])\")"
echo " mysql -h $RDS_ENDPOINT -u $DB_USERNAME -p\$DB_PASS $DB_NAME"
echo ""
echo " ⚠️  Remember to run cleanup.sh when done to avoid charges!"
echo ""
