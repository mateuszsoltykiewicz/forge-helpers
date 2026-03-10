# Common AWS - AWS Integration Library

**Forge Common Library** for AWS-specific Kubernetes resource configurations.

This library provides reusable Helm templates for integrating Kubernetes workloads with AWS services:
- **ALB Ingress Controller** annotations for Application Load Balancers
- **IRSA** (IAM Roles for Service Accounts) helpers
- **ECR** (Elastic Container Registry) integration

---

## 🚀 Features

- **AWS Load Balancer Controller** annotations (modular and composable)
- **IRSA** automatic role ARN generation and ServiceAccount annotations
- **ECR** registry URL helpers for image references
- **SSL/TLS** configuration with ACM certificates
- **Authentication** with Cognito or generic OIDC
- **WAF** and **Shield** integration for security
- **Access logs** to S3 for auditing
- **Target group** attributes (stickiness, deregistration delay)
- **Custom tags** for cost allocation and organization

---

## 📦 Installation

Add as a dependency to your Helm chart:

```yaml
# Chart.yaml
dependencies:
  - name: common-aws
    version: ~0.1.0
    repository: file://../common-aws
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
  - name: common-kubernetes
    version: ~0.1.0
    repository: file://../common-kubernetes
```

Update dependencies:
```bash
helm dependency update
```

---

## 📖 Usage

### Basic ALB Ingress

```yaml
# values.yaml
aws:
  accountId: "123456789012"
  region: "us-east-1"
  alb:
    enabled: true
    scheme: "internet-facing"
    targetType: "ip"
    healthcheck:
      enabled: true
      path: "/health"
      intervalSeconds: 30

# templates/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "ingress") }}
  annotations:
    {{- include "aws.alb.annotations" . | nindent 4 }}
spec:
  ingressClassName: alb
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "forge.resourceName" (dict "context" . "type" "service") }}
                port:
                  number: 80
```

### ALB with SSL/TLS

```yaml
aws:
  alb:
    enabled: true
    scheme: "internet-facing"
    ssl:
      enabled: true
      certificateArn: "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
      sslPolicy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
      redirectHttp: true
    healthcheck:
      protocol: "HTTPS"
      path: "/health"
```

### ALB with Cognito Authentication

```yaml
aws:
  alb:
    enabled: true
    ssl:
      enabled: true
      certificateArn: "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
    auth:
      cognito:
        enabled: true
        userPoolArn: "arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_ABC123"
        userPoolClientId: "abc123def456"
        userPoolDomain: "my-app.auth.us-east-1.amazoncognito.com"
        scope: "openid email profile"
        sessionTimeout: 3600
```

### ALB with WAF and Shield

```yaml
aws:
  alb:
    enabled: true
    waf:
      enabled: true
      webAclArn: "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/my-waf/abc123"
    shield:
      enabled: true
    accessLogs:
      enabled: true
      s3Bucket: "my-alb-logs"
      s3Prefix: "production"
```

### IRSA (IAM Roles for Service Accounts)

**Option 1: Full Role ARN**
```yaml
# values.yaml
aws:
  accountId: "123456789012"
  irsa:
    enabled: true
    roleArn: "arn:aws:iam::123456789012:role/my-app-role"

# templates/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "serviceaccount") }}
  annotations:
    {{- include "aws.irsa.serviceAccountAnnotation" . | nindent 4 }}
```

**Option 2: Auto-generated Role ARN**
```yaml
aws:
  accountId: "123456789012"
  irsa:
    enabled: true
    roleNamePrefix: "my-app-role"  # Will generate: arn:aws:iam::123456789012:role/my-app-role-{release-name}
```

**Result:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role-production
    eks.amazonaws.com/token-expiration: "86400"
```

### ECR Image Reference

**Option 1: Full Image URL Helper**
```yaml
# values.yaml
aws:
  accountId: "123456789012"
  region: "us-east-1"
  ecr:
    repository: "my-app"
image:
  tag: "v1.0.0"

# templates/deployment.yaml
spec:
  containers:
    - name: app
      image: {{ include "aws.ecr.imageUrl" . }}
```

**Result:**
```yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.0.0
```

**Option 2: ECR Public Gallery**
```yaml
aws:
  ecr:
    publicAlias: "my-org"
    repository: "my-app"
image:
  tag: "v1.0.0"
```

```yaml
image: {{ include "aws.ecr.publicImageUrl" . }}
# Result: public.ecr.aws/my-org/my-app:v1.0.0
```

**Option 3: Cross-Account ECR**
```yaml
aws:
  ecr:
    sourceAccountId: "987654321098"
    sourceRegion: "us-west-2"
    repository: "shared-repo"
image:
  tag: "v1.0.0"
```

```yaml
image: {{ include "aws.ecr.crossAccountImageUrl" . }}
# Result: 987654321098.dkr.ecr.us-west-2.amazonaws.com/shared-repo:v1.0.0
```

---

## 📚 Templates Reference

### ALB Annotations

#### Base Annotations
```yaml
{{- include "aws.alb.annotations.base" . }}
```
Generates: scheme, target-type, IP address type, subnets, security groups

#### Health Check
```yaml
{{- include "aws.alb.annotations.healthcheck" . }}
```
Generates: healthcheck-path, healthcheck-interval-seconds, success-codes, etc.

#### SSL/TLS
```yaml
{{- include "aws.alb.annotations.ssl" . }}
```
Generates: certificate-arn, ssl-policy, ssl-redirect, listen-ports

#### Authentication (Cognito)
```yaml
{{- include "aws.alb.annotations.auth.cognito" . }}
```
Generates: auth-type, auth-idp-cognito, auth-scope, auth-session-cookie

#### Authentication (OIDC)
```yaml
{{- include "aws.alb.annotations.auth.oidc" . }}
```
Generates: auth-type, auth-idp-oidc, authorization-endpoint, token-endpoint

#### Target Group
```yaml
{{- include "aws.alb.annotations.targetGroup" . }}
```
Generates: stickiness, deregistration-delay, slow-start-duration

#### WAF
```yaml
{{- include "aws.alb.annotations.waf" . }}
```
Generates: wafv2-acl-arn

#### Shield
```yaml
{{- include "aws.alb.annotations.shield" . }}
```
Generates: shield-advanced-protection

#### Access Logs
```yaml
{{- include "aws.alb.annotations.accessLogs" . }}
```
Generates: load-balancer-attributes (access_logs.s3.enabled, bucket, prefix)

#### Tags
```yaml
{{- include "aws.alb.annotations.tags" . }}
```
Generates: tags (key=value pairs for AWS resource tagging)

#### Combined (All)
```yaml
{{- include "aws.alb.annotations" . }}
```
Includes all enabled ALB annotations in one template.

---

### IRSA Helpers

#### ServiceAccount Annotation
```yaml
{{- include "aws.irsa.serviceAccountAnnotation" . }}
```
Generates: `eks.amazonaws.com/role-arn`

#### Role ARN
```yaml
{{ include "aws.irsa.roleArn" . }}
```
Generates: `arn:aws:iam::{accountId}:role/{roleNamePrefix}-{release}`

#### Complete ServiceAccount (with IRSA)
```yaml
{{- include "aws.irsa.serviceAccount" . }}
```
Extends `kubernetes.serviceaccount` from common-kubernetes with IRSA annotations.

---

### ECR Helpers

#### Registry URL
```yaml
{{ include "aws.ecr.registryUrl" . }}
```
Generates: `{accountId}.dkr.ecr.{region}.amazonaws.com`

#### Full Image URL
```yaml
{{ include "aws.ecr.imageUrl" . }}
```
Generates: `{accountId}.dkr.ecr.{region}.amazonaws.com/{repository}:{tag}`

#### Public Gallery Image URL
```yaml
{{ include "aws.ecr.publicImageUrl" . }}
```
Generates: `public.ecr.aws/{publicAlias}/{repository}:{tag}`

#### Cross-Account Image URL
```yaml
{{ include "aws.ecr.crossAccountImageUrl" . }}
```
Generates: `{sourceAccountId}.dkr.ecr.{sourceRegion}.amazonaws.com/{repository}:{tag}`

#### Image with Digest
```yaml
{{ include "aws.ecr.imageWithDigest" . }}
```
Generates: `{accountId}.dkr.ecr.{region}.amazonaws.com/{repository}@sha256:{digest}`

#### Image Pull Secret Name
```yaml
{{ include "aws.ecr.imagePullSecretName" . }}
```
Generates standardized name for ECR credentials secret.

#### Repository Policy ARN
```yaml
{{ include "aws.ecr.repositoryPolicyArn" . }}
```
Generates: `arn:aws:ecr:{region}:{accountId}:repository/{repository}`

---

## 🔧 Configuration

See [`values.yaml`](./values.yaml) for all configuration options.

### Key Configuration Sections

- **aws.accountId**: AWS account ID (12 digits)
- **aws.region**: AWS region (e.g., us-east-1)
- **aws.alb**: ALB Ingress Controller configuration
  - scheme, targetType, subnets, security groups
  - healthcheck, ssl, auth, targetGroup, waf, shield, accessLogs, tags
- **aws.irsa**: IRSA configuration (roleArn or roleNamePrefix)
- **aws.ecr**: ECR repository and image pull secrets

---

## 🧪 Examples

### Complete Production ALB Setup

```yaml
aws:
  accountId: "123456789012"
  region: "us-east-1"
  alb:
    enabled: true
    name: "production-alb"
    scheme: "internet-facing"
    targetType: "ip"
    ipAddressType: "ipv4"
    subnets:
      - "subnet-abc123"
      - "subnet-def456"
    securityGroups:
      - "sg-abc123"
    healthcheck:
      enabled: true
      path: "/health"
      protocol: "HTTPS"
      port: "traffic-port"
      intervalSeconds: 30
      timeoutSeconds: 5
      healthyThresholdCount: 2
      unhealthyThresholdCount: 2
      successCodes: "200,204"
    ssl:
      enabled: true
      certificateArn: "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
      sslPolicy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
      redirectHttp: true
    targetGroup:
      stickinessEnabled: true
      stickinessDurationSeconds: 86400
      deregistrationDelaySeconds: 30
      slowStartDurationSeconds: 60
      loadBalancingAlgorithm: "least_outstanding_requests"
    waf:
      enabled: true
      webAclArn: "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/production-waf/abc123"
    shield:
      enabled: true
    accessLogs:
      enabled: true
      s3Bucket: "production-alb-logs"
      s3Prefix: "alb"
    tags:
      Environment: "production"
      Team: "platform"
      CostCenter: "engineering"
```

---

## 🔗 Integration with Other Libraries

This library is designed to work seamlessly with:

- **common-forge**: Provides naming conventions and labels
- **common-kubernetes**: Provides base Kubernetes resource templates
- **common-vault**: Optional integration for secret management

---

## 🛠️ Dependencies

- **common-forge** (~0.1.0): Naming and validation helpers
- **common-kubernetes** (~0.1.0): Base Kubernetes resource templates

---

## 📝 License

Part of the Forge Platform - Internal Use Only

---

## 🤝 Contributing

See main repository contributing guidelines.

---

## 📞 Support

For issues or questions, contact the Platform Engineering team.
