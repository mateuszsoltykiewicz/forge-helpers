# Common-AWS Test Suite

Comprehensive test suite for the `common-aws` Helm chart, which provides AWS-specific integrations for Kubernetes workloads running on Amazon EKS.

## Overview

This test suite validates AWS-native Kubernetes features that enable seamless integration between EKS and AWS services. The two primary patterns tested are:
1. **IRSA** (IAM Roles for ServiceAccounts) - Secure AWS API access without static credentials
2. **ALB Ingress** - Application Load Balancer provisioning via Kubernetes Ingress

## Prerequisites

1. **AWS EKS cluster** (v1.23+)
2. **Helm** (v3.8+)
3. **kubectl** configured for EKS cluster
4. **AWS CLI** (v2.x) configured with appropriate credentials
5. **OIDC identity provider** associated with EKS cluster (for IRSA)
6. **AWS Load Balancer Controller** installed (for ALB Ingress)

## Test Cases

### UC01: IRSA (IAM Roles for ServiceAccounts)
**File**: `test-cases/UC01-irsa.md`

Tests IAM Roles for ServiceAccounts, which enables Kubernetes pods to assume AWS IAM roles using OpenID Connect (OIDC) federation. This eliminates the need for static AWS credentials in pods.

**Key Features**:
- OIDC-based IAM role assumption
- ServiceAccount annotation with IAM role ARN
- Automatic temporary credential injection
- AWS SDK auto-configuration
- Fine-grained IAM permissions per workload

**Use Cases**:
- S3 bucket access (read/write)
- DynamoDB operations
- Secrets Manager integration
- ECR image pulls
- CloudWatch logs/metrics
- SQS/SNS messaging

**Run**: `cd test-cases && ./run-uc01.sh`

**Prerequisites**:
- EKS cluster with OIDC provider
- IAM role with trust policy for ServiceAccount
- IAM policy attached to role (e.g., S3 read permissions)

---

### UC02: ALB Ingress with AWS Load Balancer Controller
**File**: `test-cases/UC02-alb-ingress.md`

Tests Application Load Balancer provisioning via Kubernetes Ingress resources using the AWS Load Balancer Controller. The controller automatically creates and configures ALBs based on Ingress annotations.

**Key Features**:
- Automatic ALB creation/deletion
- Path-based routing
- Host-based routing
- Health checks configuration
- Target group management (IP or instance mode)
- SSL/TLS termination (with ACM)
- WAF integration
- Resource tagging

**Use Cases**:
- Public HTTP/HTTPS APIs
- Microservices with path routing
- Multi-tenant applications (host-based routing)
- Cost optimization (single ALB for multiple services)
- AWS WAF protection
- SSL certificate management via ACM

**Run**: `cd test-cases && ./run-uc02.sh`

**Prerequisites**:
- AWS Load Balancer Controller installed
- VPC subnets tagged for ALB discovery
- IAM policy for Load Balancer Controller (via IRSA)

---

## Directory Structure

```
common-aws/
├── README.md                      # This file
├── run-all.sh                     # Run all test cases
├── test-cases/
│   ├── UC01-irsa.md              # UC01 documentation
│   ├── UC02-alb-ingress.md       # UC02 documentation
│   ├── run-uc01.sh               # UC01 test script
│   └── run-uc02.sh               # UC02 test script
└── values/
    ├── uc01-irsa.yaml            # IRSA configuration
    └── uc02-alb-ingress.yaml     # ALB Ingress configuration
```

## Quick Start

### Run All Tests
```bash
./run-all.sh
```

### Run Individual Tests
```bash
cd test-cases
./run-uc01.sh  # IRSA
./run-uc02.sh  # ALB Ingress
```

## Setup Instructions

### 1. Create EKS Cluster with OIDC Provider

```bash
# Create cluster
eksctl create cluster \
  --name test-cluster \
  --region us-east-1 \
  --with-oidc

# Verify OIDC provider
aws iam list-open-id-connect-providers | grep $(aws eks describe-cluster --name test-cluster --query "cluster.identity.oidc.issuer" --output text | cut -d'/' -f5)
```

### 2. Create IAM Role for IRSA (S3 Access Example)

```bash
# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name test-cluster --query "cluster.identity.oidc.issuer" --output text | sed 's/https:\/\///')
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:aws-test:s3-access-sa"
      }
    }
  }]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name eks-s3-read-role \
  --assume-role-policy-document file://trust-policy.json

# Attach S3 read policy
aws iam attach-role-policy \
  --role-name eks-s3-read-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

# Get role ARN (use in values file)
aws iam get-role --role-name eks-s3-read-role --query Role.Arn --output text
```

### 3. Install AWS Load Balancer Controller

```bash
# Add EKS Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Create IAM policy for Load Balancer Controller
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json

# Create IRSA for Load Balancer Controller
eksctl create iamserviceaccount \
  --cluster=test-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=test-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 4. Tag VPC Subnets for ALB Discovery

```bash
# Public subnets (for internet-facing ALB)
aws ec2 create-tags \
  --resources subnet-xxxxxx \
  --tags Key=kubernetes.io/role/elb,Value=1

# Private subnets (for internal ALB)
aws ec2 create-tags \
  --resources subnet-yyyyyy \
  --tags Key=kubernetes.io/role/internal-elb,Value=1
```

## IRSA (IAM Roles for ServiceAccounts)

### How It Works
1. ServiceAccount annotated with `eks.amazonaws.com/role-arn`
2. Pod uses ServiceAccount and mounts OIDC token at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
3. AWS SDK detects environment variables and OIDC token
4. SDK calls `sts:AssumeRoleWithWebIdentity` to exchange token for temporary credentials
5. Temporary credentials refreshed automatically before expiration

### Environment Variables Injected
```bash
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/eks-s3-read-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

### Testing IRSA
```bash
# Exec into pod
kubectl exec -it <pod-name> -n aws-test -- bash

# AWS CLI will automatically use IRSA credentials
aws s3 ls
aws dynamodb list-tables
aws secretsmanager list-secrets
```

## ALB Ingress Annotations

### Common Annotations

```yaml
# Scheme (internet-facing or internal)
alb.ingress.kubernetes.io/scheme: internet-facing

# Target type (ip or instance)
alb.ingress.kubernetes.io/target-type: ip

# Listeners
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'

# SSL/TLS
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/id
alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
alb.ingress.kubernetes.io/ssl-redirect: "443"

# Health checks
alb.ingress.kubernetes.io/healthcheck-path: /health
alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
alb.ingress.kubernetes.io/success-codes: "200"

# WAF
alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:region:account:regional/webacl/name/id

# Tags
alb.ingress.kubernetes.io/tags: Environment=prod,Team=platform
```

### Example: HTTPS with ACM Certificate

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: https-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789012:certificate/abcd1234
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  ingressClassName: alb
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80
```

## Troubleshooting

### IRSA Not Working
```bash
# Check ServiceAccount annotation
kubectl get sa <service-account> -n <namespace> -o yaml | grep role-arn

# Verify OIDC provider
aws eks describe-cluster --name <cluster> --query "cluster.identity.oidc.issuer"

# Check pod environment variables
kubectl exec <pod> -n <namespace> -- env | grep AWS

# Verify OIDC token mounted
kubectl exec <pod> -n <namespace> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# Test IAM role assumption
aws sts assume-role-with-web-identity \
  --role-arn <role-arn> \
  --role-session-name test \
  --web-identity-token file://<token-file>
```

### ALB Not Created
```bash
# Check Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=100

# Verify Ingress resource
kubectl describe ingress <ingress-name> -n <namespace>

# Check subnet tags
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[*].Tags'

# Verify IAM permissions
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml
```

### ALB Health Checks Failing
```bash
# Check target group in AWS console
aws elbv2 describe-target-groups --names <target-group-name>

# Verify pod health
kubectl get pods -n <namespace>
kubectl logs <pod> -n <namespace>

# Test health endpoint
kubectl port-forward <pod> 8080:8080 -n <namespace>
curl http://localhost:8080/health
```

## Best Practices

### IRSA
1. **Least Privilege**: Grant minimal IAM permissions required
2. **Namespace Isolation**: Use namespace-specific IAM roles
3. **Role Per Service**: Create dedicated IAM role for each application
4. **Audit Logging**: Enable CloudTrail for IAM role assumption tracking
5. **Condition Keys**: Use OIDC condition keys to restrict role assumption

### ALB Ingress
1. **Target Type**: Use `ip` mode for better pod distribution
2. **Health Checks**: Configure appropriate intervals and timeouts
3. **Resource Tags**: Tag ALBs for cost allocation and management
4. **SSL/TLS**: Always use HTTPS in production with ACM certificates
5. **WAF**: Enable AWS WAF for public-facing ALBs
6. **Cost Optimization**: Use single ALB for multiple services (path/host routing)

## Resources

- [EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ALB Ingress Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

## Support

For issues or questions:
1. Check EKS cluster OIDC provider configuration
2. Verify IAM trust policies and permissions
3. Review Load Balancer Controller logs
4. Consult AWS EKS troubleshooting documentation
