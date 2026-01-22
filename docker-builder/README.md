# Docker Builder - Production Grade Build System

Production-ready Docker image build and deployment system for Forge security automation tools.

## Features

- ✅ **Multi-Mode Support**: Local development and ECR production modes
- ✅ **Auto-Detection**: AWS account ID and region auto-detection
- ✅ **Repository Management**: Automatic ECR repository creation
- ✅ **Image Scanning**: Vulnerability scanning on push (ECR)
- ✅ **Build Caching**: Intelligent layer caching
- ✅ **Multi-Tagging**: Version tags + latest tag
- ✅ **Detailed Logging**: Timestamped logs with color output
- ✅ **Error Handling**: Comprehensive error checks and rollback
- ✅ **Metadata Injection**: Build date, version, VCS ref
- ✅ **Platform Support**: Multi-architecture builds

## Quick Start

### Build Locally

```bash
cd forge-helpers/docker-builder
./build.sh local
```

### Build and Push to ECR

```bash
./build.sh ecr --version=1.0.0
```

## Usage

```bash
./build.sh <mode> [options]
```

### Modes

| Mode | Description | Registry |
|------|-------------|----------|
| `local` | Build images locally only | `forge/` |
| `ecr` | Build and push to AWS ECR | `{account}.dkr.ecr.{region}.amazonaws.com/` |

### Options

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `--version=X.Y.Z` | Semantic version tag | `latest` | `--version=1.2.3` |
| `--region=REGION` | AWS region for ECR | `us-east-1` | `--region=eu-west-1` |
| `--account=ID` | AWS account ID | Auto-detected | `--account=123456789012` |
| `--no-cache` | Disable Docker build cache | Cache enabled | `--no-cache` |
| `--platform=ARCH` | Target platform | `linux/amd64` | `--platform=linux/arm64` |
| `--parallel` | Build in parallel (experimental) | Sequential | `--parallel` |
| `--help`, `-h` | Show help message | - | `--help` |

## Examples

### Development Workflow

```bash
# Build locally for testing
./build.sh local

# Test the images
docker run --rm forge/yaml-ssm-sync:latest --help
docker run --rm forge/security-group-chainer:latest --help

# Build and push to ECR with version
./build.sh ecr --version=1.0.0
```

### Production Release

```bash
# Build and push release version
./build.sh ecr --version=2.1.0 --region=us-east-1

# Verify in AWS
aws ecr describe-images \
  --repository-name yaml-ssm-sync \
  --region us-east-1
```

### Multi-Platform Build

```bash
# Build for ARM architecture
./build.sh local --platform=linux/arm64

# Build for AMD64 (default)
./build.sh local --platform=linux/amd64
```

### Clean Build (No Cache)

```bash
# Force rebuild without cache
./build.sh local --no-cache --version=1.0.1
```

### Multi-Region Deployment

```bash
# Deploy to multiple AWS regions
for region in us-east-1 eu-west-1 ap-southeast-1; do
  ./build.sh ecr \
    --version=1.0.0 \
    --region=$region
done
```

## Images Built

| Image Name | Source Directory | Description |
|------------|------------------|-------------|
| `yaml-ssm-sync` | `../yaml-sync-with-ssm/` | YAML-SSM synchronization tool |
| `security-group-chainer` | `../security-group-chainer/` | Security group automation |

## Output

### Console Output

```
===================================================
Docker Builder v1.0.0
===================================================

===================================================
Checking Prerequisites
===================================================

✅ Docker installed: Docker version 24.0.7
✅ Docker daemon running
✅ AWS CLI installed: aws-cli/2.13.25
✅ Found yaml-ssm-sync: /path/to/yaml-sync-with-ssm
✅ Found security-group-chainer: /path/to/security-group-chainer
✅ All prerequisites satisfied

===================================================
Authenticating with ECR
===================================================

ℹ️  Region: us-east-1
ℹ️  Account: 123456789012
✅ Successfully authenticated with ECR

===================================================
Building: yaml-ssm-sync
===================================================

ℹ️  Context: /path/to/yaml-sync-with-ssm
ℹ️  Image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0
ℹ️  Platform: linux/amd64
ℹ️  Cache: enabled
✅ Built: 123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0
✅ Tagged: 123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:latest
ℹ️  Image size: 145MB

===================================================
Build Summary
===================================================

Configuration:
  Mode:     ecr
  Version:  1.0.0
  Platform: linux/amd64
  Registry: 123456789012.dkr.ecr.us-east-1.amazonaws.com

Built Images:
  123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0     145MB
  123456789012.dkr.ecr.us-east-1.amazonaws.com/security-group-chainer:1.0.0   152MB

Terraform Integration:
  Update your Terraform variables:
    docker_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0"
    docker_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/security-group-chainer:1.0.0"

✅ Build process completed successfully
```

### Log Files

All build logs are saved to `logs/build-YYYYMMDD-HHMMSS.log`:

```
[2026-01-13 10:30:00] HEADER: Docker Builder v1.0.0
[2026-01-13 10:30:01] INFO: Mode: ecr, Version: 1.0.0, Platform: linux/amd64
[2026-01-13 10:30:02] SUCCESS: Docker installed: Docker version 24.0.7
[2026-01-13 10:30:15] SUCCESS: Built: 123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0
...
```

## Directory Structure

```
docker-builder/
├── build.sh              # Main build script
├── README.md             # This file
└── logs/                 # Build logs (created automatically)
    └── build-YYYYMMDD-HHMMSS.log
```

## Prerequisites

### Local Mode

- **Docker** (version 20.10+)
  ```bash
  docker --version
  ```

### ECR Mode

All of local mode plus:

- **AWS CLI** (version 2.x)
  ```bash
  aws --version
  ```

- **AWS Credentials** configured
  ```bash
  aws configure
  # OR
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
  ```

- **IAM Permissions**:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecr:GetAuthorizationToken",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImageScanningConfiguration"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": "sts:GetCallerIdentity",
        "Resource": "*"
      }
    ]
  }
  ```

## ECR Configuration

Repositories are created with:

- **Image Scanning**: Enabled (scans on push)
- **Encryption**: AES256
- **Tags**:
  - `ManagedBy=docker-builder`
  - `Project=forge`

### Lifecycle Policy (Optional)

```bash
aws ecr put-lifecycle-policy \
  --repository-name yaml-ssm-sync \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }]
  }'
```

## Terraform Integration

After building and pushing to ECR, update your Terraform configuration:

### Using Variables

```hcl
# forge-infrastructure/aws/variables.tf
variable "ecr_registry" {
  description = "ECR registry URL"
  default     = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
}

variable "image_version" {
  description = "Docker image version"
  default     = "1.0.0"
}

# forge-infrastructure/aws/main.tf
module "yaml_ssm_sync_chains" {
  source = "./security/yaml-sync-with-ssm"
  
  docker_image = "${var.ecr_registry}/yaml-ssm-sync:${var.image_version}"
  # ...
}

module "security_group_chainer" {
  source = "./security/security-group-chainer"
  
  docker_image = "${var.ecr_registry}/security-group-chainer:${var.image_version}"
  # ...
}
```

### Direct Configuration

```hcl
module "yaml_ssm_sync_chains" {
  source = "./security/yaml-sync-with-ssm"
  
  docker_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0"
  # ...
}
```

## Troubleshooting

### Docker Daemon Not Running

**Error:**
```
❌ Docker daemon not running
```

**Solution:**
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
```

### AWS CLI Not Found

**Error:**
```
❌ AWS CLI not installed (required for ECR mode)
```

**Solution:**
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Failed to Auto-Detect AWS Account

**Error:**
```
❌ Failed to auto-detect AWS account ID
```

**Solution:**
```bash
# Configure AWS credentials
aws configure

# Or specify manually
./build.sh ecr --account=123456789012
```

### ECR Authentication Failed

**Error:**
```
❌ Failed to authenticate with ECR
```

**Solution:**
```bash
# Check credentials
aws sts get-caller-identity

# Check region
aws configure get region

# Manual login test
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com
```

### Build Failed

**Error:**
```
❌ Failed to build: forge/yaml-ssm-sync:latest
```

**Solution:**
```bash
# Check logs
tail logs/build-*.log

# Try clean build
./build.sh local --no-cache

# Check Dockerfile
cat ../yaml-sync-with-ssm/Dockerfile
```

### Push Failed

**Error:**
```
❌ Failed to push: 123456789012.dkr.ecr.us-east-1.amazonaws.com/yaml-ssm-sync:1.0.0
```

**Solution:**
```bash
# Check repository exists
aws ecr describe-repositories --repository-names yaml-ssm-sync

# Check IAM permissions
aws ecr get-authorization-token

# Check image size limits (max 10GB)
docker images | grep yaml-ssm-sync
```

## Performance

### Build Times (Approximate)

| Operation | Time | Notes |
|-----------|------|-------|
| Local build (cached) | 30s | Using layer cache |
| Local build (no cache) | 2-3min | Full rebuild |
| ECR push | 1-2min | Depends on network |
| Total (local) | 1min | Cached build |
| Total (ECR) | 4-5min | Full workflow |

### Optimization Tips

1. **Use build cache**: Don't use `--no-cache` unless necessary
2. **Optimize Dockerfiles**: Order commands from least to most frequently changed
3. **Multi-stage builds**: Already implemented in Dockerfiles
4. **Parallel builds**: Use `--parallel` for faster builds (experimental)

## Cost Considerations

| Item | Cost |
|------|------|
| ECR Storage | $0.10/GB/month |
| ECR Data Transfer (in) | FREE |
| ECR Data Transfer (out to internet) | $0.09/GB |
| Image Scanning (first scan) | FREE |
| Image Scanning (subsequent) | $0.09/image scan |

**Typical monthly cost:**
- 2 images × 150MB = 300MB storage = **$0.03/month**
- 10 versions × 300MB = 3GB storage = **$0.30/month**

## CI/CD Integration

### GitHub Actions

```yaml
name: Build and Push to ECR

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Build and push to ECR
        run: |
          cd forge-helpers/docker-builder
          ./build.sh ecr --version=${GITHUB_REF#refs/tags/v}
```

### GitLab CI

```yaml
build-ecr:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - apk add --no-cache aws-cli
    - cd forge-helpers/docker-builder
    - ./build.sh ecr --version=$CI_COMMIT_TAG
  only:
    - tags
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-13 | Initial production release |

## License

MIT

## Support

For issues or questions:
- Check logs in `logs/`
- Review Dockerfile in source directories
- Verify AWS credentials and permissions
- Check Docker daemon status
