# AWS Lab 02 — EC2 + VPC + Security Groups

**Goal:** Deploy a hardened EC2 instance inside a custom VPC with public/private subnets, proper security groups, and SSM access (no open SSH).

## Architecture

```
Internet
    │
[Internet Gateway]
    │
[Public Subnet 10.0.1.0/24]
    │
[EC2 — Amazon Linux 2023]   ← SSM Session Manager (no port 22)
    │
[Private Subnet 10.0.2.0/24]
    │
[NAT Gateway]  ← outbound only
```

## What You'll Learn

- VPC design: CIDR blocks, subnets, route tables, IGW, NAT Gateway
- Security Groups: least-privilege inbound/outbound rules
- EC2: AMI selection, instance types, IAM instance profile
- SSM Session Manager: secure shell without SSH or open ports
- Tagging: cost allocation across all resources

## Resources Created

| Resource | Name | Notes |
|---|---|---|
| VPC | `aws-cert-study-vpc` | CIDR: 10.0.0.0/16 |
| Public Subnet | `aws-cert-study-public` | 10.0.1.0/24, AZ-a |
| Private Subnet | `aws-cert-study-private` | 10.0.2.0/24, AZ-b |
| Internet Gateway | `aws-cert-study-igw` | Attached to VPC |
| NAT Gateway | `aws-cert-study-nat` | In public subnet |
| Security Group | `aws-cert-study-sg` | No port 22 open |
| EC2 Instance | `aws-cert-study-ec2` | Amazon Linux 2023, t3.micro |
| IAM Role | `aws-cert-study-ssm-role` | AmazonSSMManagedInstanceCore |

## Deploy

```bash
bash scripts/deploy.sh
```

## Cleanup (always run after lab)

```bash
bash scripts/cleanup.sh
```

## Tagging Standard

All resources tagged: `Project=aws-cert-study`, `Environment=learning`, `Owner=your-name`, `CostCenter=personal-dev`, `ManagedBy=manual`
