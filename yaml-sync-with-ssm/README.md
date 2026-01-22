# YAML-SSM Sync

Bidirectional synchronization tool for YAML files and AWS SSM Parameter Store.

## Features

- ✅ **Upload**: YAML file → SSM Parameter Store
- ✅ **Download**: SSM Parameter Store → YAML file
- ✅ **Compare**: Detect differences between local and SSM
- ✅ **Validate**: Schema validation with Pydantic
- ✅ **Smart Sync**: Skip updates if content is identical
- ✅ **Force Mode**: Override smart sync

## Architecture

```
┌──────────────┐         ┌─────────────────────────┐
│  Local YAML  │ ←──────→│  AWS SSM Parameter      │
│    File      │  Sync   │  Store                  │
└──────────────┘         └─────────────────────────┘
       │                          │
       │                          │
       ▼                          ▼
  Validation              Version Control
  (Pydantic)              (SSM Versions)
```

## Build Docker Image

```bash
cd forge-helpers/yaml-sync-with-ssm
docker build -t ghcr.io/forge/yaml-ssm-sync:latest .
docker push ghcr.io/forge/yaml-ssm-sync:latest
```

## Usage

### Upload YAML to SSM

```bash
# From Docker
docker run --rm \
  -v $(pwd):/data \
  -v ~/.aws:/root/.aws:ro \
  ghcr.io/forge/yaml-ssm-sync:latest \
  upload /data/chains.yaml \
  --parameter /forge/security-group-chains \
  --region us-east-1 \
  --validate

# From Python
python src/sync.py upload chains.yaml \
  --parameter /forge/security-group-chains \
  --region us-east-1 \
  --validate \
  --description "Security Group Chains Configuration"
```

### Download YAML from SSM

```bash
# From Docker
docker run --rm \
  -v $(pwd):/data \
  -v ~/.aws:/root/.aws:ro \
  ghcr.io/forge/yaml-ssm-sync:latest \
  download /data/chains.yaml \
  --parameter /forge/security-group-chains \
  --region us-east-1

# From Python
python src/sync.py download chains.yaml \
  --parameter /forge/security-group-chains \
  --region us-east-1
```

### Compare Local and SSM

```bash
# From Docker
docker run --rm \
  -v $(pwd):/data \
  -v ~/.aws:/root/.aws:ro \
  ghcr.io/forge/yaml-ssm-sync:latest \
  compare /data/chains.yaml \
  --parameter /forge/security-group-chains \
  --region us-east-1

# From Python
python src/sync.py compare chains.yaml \
  --parameter /forge/security-group-chains \
  --region us-east-1
```

### Validate YAML

```bash
# From Docker
docker run --rm \
  -v $(pwd):/data \
  ghcr.io/forge/yaml-ssm-sync:latest \
  validate /data/chains.yaml

# From Python
python src/sync.py validate chains.yaml
```

## Commands

### `upload`

Upload YAML file to SSM Parameter Store.

**Arguments:**
- `yaml_file`: Path to YAML file
- `--parameter`: SSM parameter name (required)
- `--region`: AWS region (default: us-east-1)
- `--description`: Parameter description
- `--validate`: Validate YAML schema before upload
- `--force`: Force upload even if identical

**Example:**
```bash
python src/sync.py upload chains.yaml \
  --parameter /forge/chains \
  --validate \
  --force
```

### `download`

Download YAML from SSM Parameter Store to file.

**Arguments:**
- `yaml_file`: Path to save YAML file
- `--parameter`: SSM parameter name (required)
- `--region`: AWS region (default: us-east-1)
- `--force`: Force download even if identical

**Example:**
```bash
python src/sync.py download chains.yaml \
  --parameter /forge/chains
```

### `compare`

Compare local YAML with SSM parameter.

**Arguments:**
- `yaml_file`: Path to YAML file
- `--parameter`: SSM parameter name (required)
- `--region`: AWS region (default: us-east-1)

**Returns:**
- Exit code 0: Files are identical
- Exit code 1: Files differ

**Example:**
```bash
python src/sync.py compare chains.yaml \
  --parameter /forge/chains
```

### `validate`

Validate YAML file structure.

**Arguments:**
- `yaml_file`: Path to YAML file

**Example:**
```bash
python src/sync.py validate chains.yaml
```

## YAML Schema

The tool validates against the following schema for security group chains:

```yaml
version: "1.0"                    # Required
timeout_seconds: 1800             # 60-3600
polling_interval_seconds: 10      # 5-60
circuit_breaker_threshold: 5      # 3-20

chains:                           # At least one required
  - name: string                  # Required
    master_tier: string           # Required
    slave_tier: string            # Required
    ports: [int, ...]             # Required (0-65535)
    protocol: tcp|udp|icmp|-1     # Default: tcp
    bidirectional: bool           # Default: true
```

## Integration with Terraform

### Example: Sync before Terraform Apply

```bash
# 1. Validate local config
python src/sync.py validate chains.yaml

# 2. Upload to SSM
python src/sync.py upload chains.yaml \
  --parameter /forge/security-group-chains \
  --validate

# 3. Run Terraform (chainer will read from SSM)
terraform apply
```

### Example: Download after Manual SSM Update

```bash
# Someone updated SSM manually, download to local
python src/sync.py download chains.yaml \
  --parameter /forge/security-group-chains
```

## Development

### Install Dependencies

```bash
cd forge-helpers/yaml-sync-with-ssm
pip install -r requirements.txt
```

### Run Tests

```bash
python -m pytest tests/
```

### Example YAML File

```yaml
version: "1.0"
timeout_seconds: 1800
polling_interval_seconds: 10
circuit_breaker_threshold: 5

chains:
  - name: alb-to-eks
    master_tier: ALB
    slave_tier: EKSNodes
    ports: [80, 443]
    protocol: tcp
    bidirectional: true
    
  - name: eks-to-rds
    master_tier: EKSNodes
    slave_tier: RDS
    ports: [5432]
    protocol: tcp
    bidirectional: true
```

## AWS Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:PutParameter",
        "ssm:DeleteParameter"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/forge/*"
    }
  ]
}
```

## License

MIT
