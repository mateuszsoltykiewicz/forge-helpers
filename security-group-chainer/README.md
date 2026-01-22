# Security Group Chainer

Automated security group rule creation between AWS security groups based on FirewallTier tags.

## Features

- ✅ **Async Monitoring**: Resolves circular dependencies by waiting independently for each SG
- ✅ **VPC Auto-Discovery**: Automatically discovers VPC ID by tags (Customer, Project, Region, Environment)
- ✅ **Circuit Breaker**: Prevents cascading failures with automatic recovery
- ✅ **Retry Logic**: Handles transient AWS API errors with exponential backoff
- ✅ **SSM Integration**: Configuration stored in AWS SSM Parameter Store
- ✅ **Graceful Failure**: Always exits with code 0, reports failures in YAML
- ✅ **Idempotent**: Safe to re-run, checks for existing rules
- ✅ **Bidirectional**: Creates both ingress and egress rules

## Architecture

```
┌─────────────────────────────────────────┐
│ Terraform null_resource                 │
│  └─> docker run sg-chainer              │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Docker Container (Python 3.11 Alpine)   │
│                                          │
│  1. Load config from SSM or YAML        │
│  2. Async wait for SG creation          │
│  3. Create ingress/egress rules         │
│  4. Generate YAML report                │
│  5. Exit 0 (graceful failure)           │
└─────────────────────────────────────────┘
```

## Configuration Format

```yaml
version: "1.0"

# AWS Region and VPC settings
region: "us-east-2"

# VPC ID - leave empty for auto-discovery by tags
vpc_id: ""  # Optional: set explicitly or leave empty for auto-discovery

# Customer and Project identifiers (required for VPC auto-discovery)
customer_name: "Sanofi"
project_name: "Cronus"
environment: "shared"  # Options: development, staging, production, shared
current_deployment: "Primary"  # Optional: used as fallback if multiple VPCs found

# VPC Discovery Settings (used when vpc_id is empty)
vpc_discovery:
  timeout_seconds: 1800      # 30 minutes
  polling_interval_seconds: 15

# Chain execution settings
timeout_seconds: 3600
polling_interval_seconds: 10
circuit_breaker_threshold: 5

chains:
  - name: alb-to-eks
    master_tier: ALB
    slave_tier: EKSNodes
    ports: [80, 443]
    protocol: tcp
    bidirectional: true
```

## VPC Auto-Discovery

The chainer can automatically discover VPC ID by tags, enabling parallel execution with Terraform.

### How It Works

1. **Tags Used for Discovery**: `Customer`, `Project`, `Region`, `Environment`
2. **Fallback**: If multiple VPCs match, uses `CurrentDeployment` tag to disambiguate
3. **Polling**: Waits up to `vpc_discovery.timeout_seconds` for VPC to be created
4. **Graceful Failure**: If VPC not found, exits with code 0 and error in report

### Usage with Auto-Discovery

```yaml
# configuration.yaml
region: "us-east-2"
vpc_id: ""  # Empty = auto-discovery

customer_name: "Sanofi"
project_name: "Cronus"
environment: "shared"
current_deployment: "Primary"

vpc_discovery:
  timeout_seconds: 1800      # Wait up to 30 minutes
  polling_interval_seconds: 15
```

```bash
# Run chainer WITHOUT providing VPC ID
python src/chainer.py \
  --mode=apply \
  --yaml-config configuration.yaml \
  --region us-east-2

# Chainer will:
# 1. Poll EC2 API for VPC with matching tags
# 2. Wait up to 1800s for VPC to appear
# 3. Once found, proceed with chain creation
```

### VPC Discovery Report

```yaml
vpc_discovery:
  method: "auto-discovery"  # or "explicit"
  vpc_id: "vpc-05e7222e3c3689386"
  duration_seconds: 45.3
  attempts: 4
  tags_used:
    Customer: "Sanofi"
    Project: "Cronus"
    Region: "us-east-2"
    Environment: "shared"
    CurrentDeployment: "Primary"
```

### Parallel Execution with Terraform

```bash
# Start Terraform in background
terraform apply -auto-approve &
TERRAFORM_PID=$!

# Start chainer immediately (will wait for VPC)
python src/chainer.py \
  --mode=apply \
  --yaml-config configuration.yaml &
CHAINER_PID=$!

# Wait for both to complete
wait $TERRAFORM_PID
wait $CHAINER_PID
```

## Build Docker Image

```bash
cd forge-helpers/security-group-chainer
docker build -t ghcr.io/forge/sg-chainer:latest .
docker push ghcr.io/forge/sg-chainer:latest
```

## Usage

### From Docker

```bash
docker run --rm \
  -e AWS_REGION=us-east-1 \
  -e VPC_ID=vpc-xxx \
  -e SSM_PARAMETER=/forge/security-group-chains \
  -v ~/.aws:/root/.aws:ro \
  ghcr.io/forge/sg-chainer:latest \
  --mode=apply
```

### From Python (local development)

```bash
cd forge-helpers/security-group-chainer
pip install -r requirements.txt

python src/chainer.py \
  --mode=apply \
  --vpc-id vpc-xxx \
  --region us-east-1 \
  --ssm-parameter /forge/security-group-chains \
  --output /tmp/report.yaml
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `VPC_ID` | VPC ID to filter security groups | No (if auto-discovery enabled) |
| `AWS_REGION` | AWS region | Yes |
| `SSM_PARAMETER` | SSM parameter name for config | No (if YAML_CONFIG provided) |
| `YAML_CONFIG` | Path to local YAML config | No (if SSM_PARAMETER provided) |

## Command Line Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--mode` | Operation mode: `apply` or `destroy` | `apply` |
| `--ssm-parameter` | SSM parameter name | - |
| `--yaml-config` | Local YAML config path | - |
| `--vpc-id` | VPC ID | - |
| `--region` | AWS region | `us-east-1` |
| `--output` | Output path for YAML report | `/tmp/chainer-report.yaml` |

## Report Format

```yaml
security_group_chainer_report:
  metadata:
    timestamp: "2026-01-13T10:30:00"
    duration_seconds: 45.2
    mode: apply
    vpc_id: vpc-xxx
    region: us-east-1
  
  summary:
    total_chains: 4
    successful: 3
    partial_success: 0
    failed: 1
    overall_status: partial
  
  chains:
    - name: alb-to-eks
      status: success
      master_tier: ALB
      slave_tier: EKSNodes
      actions:
        - "✅ eks-nodes-sg ← alb-sg (ingress)"
        - "✅ alb-sg → eks-nodes-sg (egress)"
```

## Development

### Run Tests

```bash
cd forge-helpers/security-group-chainer
python -m pytest tests/
```

### Local Testing

```bash
# Create test config
cat > test-chains.yaml <<EOF
version: "1.0"
timeout_seconds: 300
chains:
  - name: test-chain
    master_tier: TestMaster
    slave_tier: TestSlave
    ports: [80]
    protocol: tcp
    bidirectional: true
EOF

# Run locally
python src/chainer.py \
  --mode=apply \
  --yaml-config test-chains.yaml \
  --vpc-id vpc-xxx \
  --region us-east-1
```

## License

MIT
