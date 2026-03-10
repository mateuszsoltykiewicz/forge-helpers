# UC01: IRSA (IAM Roles for ServiceAccounts)

## Overview
Tests IAM Roles for ServiceAccounts (IRSA), an AWS EKS feature that enables Kubernetes pods to assume IAM roles without static credentials. This provides secure, fine-grained AWS API access using temporary credentials.

## IRSA Architecture
IRSA leverages AWS STS (Security Token Service) and OIDC (OpenID Connect) identity provider:
1. EKS cluster has an OIDC identity provider in AWS IAM
2. ServiceAccount is annotated with IAM role ARN
3. Pod uses ServiceAccount and mounts OIDC token
4. AWS SDK automatically exchanges token for temporary IAM credentials
5. Pod can make AWS API calls with IAM role permissions

## Use Cases
- **S3 Access**: Read/write S3 buckets without access keys
- **DynamoDB**: Database operations with scoped permissions
- **Secrets Manager**: Retrieve application secrets
- **ECR**: Pull container images from private registries
- **CloudWatch**: Send logs and metrics
- **SQS/SNS**: Message queue operations

## Prerequisites
- AWS EKS cluster (v1.23+)
- OIDC identity provider associated with cluster
- IAM role created with trust policy for ServiceAccount
- AWS Load Balancer Controller (if using ALB/NLB)

## Test Objectives
1. Create ServiceAccount with IAM role annotation
2. Deploy pod using the ServiceAccount
3. Verify AWS credentials automatically injected
4. Test AWS API access (e.g., list S3 buckets)
5. Confirm temporary credentials auto-refresh

## IAM Trust Policy Example
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT"
      }
    }
  }]
}
```

## References
- [EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [EKS OIDC Provider Setup](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)
