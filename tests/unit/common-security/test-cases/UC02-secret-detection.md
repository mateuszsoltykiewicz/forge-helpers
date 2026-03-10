# UC-SECURITY-02: Secret Detection and Hardcoded Credentials

## Overview

This Use Case validates the `common-security` chart's ability to detect **hardcoded secrets, passwords, API keys, and sensitive data** in Kubernetes workloads using Trivy's ConfigAuditReport functionality. This prevents:

- **Credential exposure** in container images and configuration
- **Compliance violations** (PCI-DSS, HIPAA, SOC 2)
- **Security incidents** from leaked API keys and tokens
- **Supply chain attacks** via compromised credentials

## Test Objectives

1. **Secret Scanning**: Detect hardcoded passwords, API keys, tokens in deployments
2. **ConfigAuditReport Generation**: Validate automatic report creation
3. **Secret Pattern Detection**: Verify detection of common secret patterns (AWS keys, GitHub tokens, etc.)
4. **Severity Classification**: Confirm HIGH/CRITICAL severity for exposed secrets
5. **Remediation Guidance**: Verify report includes fix recommendations

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Trivy Operator                             │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          ConfigAuditReport Scanner                       │  │
│  │                                                          │  │
│  │  Scans for:                                             │  │
│  │  - Hardcoded passwords (PASSWORD=secret123)             │  │
│  │  - API keys (AWS_ACCESS_KEY_ID=AKIA...)                │  │
│  │  - GitHub tokens (ghp_xxxxxxxxxxxx)                     │  │
│  │  - Private keys (-----BEGIN PRIVATE KEY-----)           │  │
│  │  - Database connection strings                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                       │                                         │
│                       ▼                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │   ConfigAuditReport CRD                                  │  │
│  │   - ID: AVD-KSV-0104                                     │  │
│  │   - Severity: CRITICAL                                   │  │
│  │   - Title: "Environment variable contains secret"        │  │
│  │   - Resource: deployment/app-with-secrets                │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (EKS 1.23+)
- Trivy Operator installed (from UC-SECURITY-01 or standalone)
- `kubectl` and `helm` CLI tools
- `jq` for JSON parsing

## Test Environment

### Values File (`uc02-secret-scan.yaml`)

```yaml
# Enable Trivy Operator with secret scanning
trivy:
  enabled: true
  
  operator:
    # Configuration audit scanning
    configAuditReports:
      enabled: true
      scanWorkloads: true
      
    # Exposed secret scanning
    exposedsecretReports:
      enabled: true
      
    # Scan all namespaces
    scanJobsInNamespace: "*"
    
    # Severity levels
    severity:
      - CRITICAL
      - HIGH
      - MEDIUM
      
  # Trivy secret scanning configuration
  trivyConfig:
    # Enable secret detection
    secret:
      enabled: true
      
    # Secret patterns to detect
    secretPatterns:
      - aws-access-key
      - aws-secret-key
      - github-token
      - generic-api-key
      - password
      - private-key
      - slack-webhook
      - jwt-token
      
    # Maximum file size to scan
    maxFileSize: "1MB"
```

### Vulnerable Application (`app-with-secrets.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-secrets
  labels:
    app: secret-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secret-test
  template:
    metadata:
      labels:
        app: secret-test
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["sh", "-c", "sleep 3600"]
        env:
        # CRITICAL: Hardcoded AWS credentials
        - name: AWS_ACCESS_KEY_ID
          value: "AKIAIOSFODNN7EXAMPLE"
        - name: AWS_SECRET_ACCESS_KEY
          value: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
          
        # HIGH: Database password in plaintext
        - name: DB_PASSWORD
          value: "super_secret_password_123"
          
        # HIGH: GitHub token
        - name: GITHUB_TOKEN
          value: "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
          
        # HIGH: API key
        - name: API_KEY
          value: "sk-1234567890abcdefghijklmnopqrstuvwxyz"
          
        resources:
          limits:
            cpu: "100m"
            memory: "64Mi"
          requests:
            cpu: "50m"
            memory: "32Mi"
```

**Why these secrets?**
- **AWS keys**: Match official AWS key format (AKIA prefix)
- **GitHub token**: Matches `ghp_` prefix pattern
- **Passwords**: Common plaintext password patterns
- **API keys**: Generic `sk-` prefix used by many services

## Test Steps

### Step 1: Install Trivy Operator

```bash
helm install trivy-security charts/common-security \
  -f tests/unit/common-security/values/uc02-secret-scan.yaml \
  -n trivy-system \
  --create-namespace \
  --wait
```

### Step 2: Verify Secret Scanning Enabled

```bash
kubectl get deployment trivy-operator -n trivy-system -o yaml | grep -A 5 "secret"
```

### Step 3: Deploy Application with Secrets

```bash
kubectl create namespace test-security
kubectl apply -f tests/unit/common-security/workloads/app-with-secrets.yaml -n test-security
```

### Step 4: Wait for Scan Completion

```bash
# Wait for ConfigAuditReport
sleep 60

kubectl get configauditreport -n test-security
```

### Step 5: Inspect ConfigAuditReport

```bash
kubectl get configauditreport -n test-security -o yaml | grep -A 20 "secret\|password\|key"
```

**Expected Findings**:
```yaml
checks:
  - checkID: "AVD-KSV-0104"
    title: "Environment variable contains AWS credentials"
    severity: CRITICAL
    category: "Secret"
    description: "Environment variable AWS_ACCESS_KEY_ID contains hardcoded AWS credentials"
    remediation: "Use Kubernetes Secrets or external secret management (Vault, AWS Secrets Manager)"
    
  - checkID: "AVD-KSV-0105"
    title: "Environment variable contains password"
    severity: HIGH
    category: "Secret"
    description: "Environment variable DB_PASSWORD contains hardcoded password"
    
  - checkID: "AVD-KSV-0106"
    title: "Environment variable contains GitHub token"
    severity: HIGH
    category: "Secret"
    description: "Environment variable GITHUB_TOKEN contains GitHub personal access token"
```

### Step 6: Count Secret Findings

```bash
kubectl get configauditreport -n test-security -o json | \
  jq '.items[0].report.summary | {critical: .criticalCount, high: .highCount}'
```

### Step 7: Verify ExposedSecretReport (Bonus)

```bash
# Check if ExposedSecretReport also created
kubectl get exposedsecretreport -n test-security
```

## Validation Criteria

### 1. ConfigAuditReport Created

```bash
if kubectl get configauditreport -n test-security | grep -q "app-with-secrets"; then
  echo "✅ ConfigAuditReport created"
else
  echo "❌ ConfigAuditReport not found"
fi
```

### 2. AWS Credential Detection

```bash
if kubectl get configauditreport -n test-security -o yaml | grep -q "AWS_ACCESS_KEY\|AKIA"; then
  echo "✅ Detected AWS credentials"
else
  echo "❌ AWS credentials not detected"
fi
```

### 3. Password Detection

```bash
if kubectl get configauditreport -n test-security -o yaml | grep -qi "password"; then
  echo "✅ Detected password in environment"
else
  echo "❌ Password not detected"
fi
```

### 4. GitHub Token Detection

```bash
if kubectl get configauditreport -n test-security -o yaml | grep -q "ghp_\|GITHUB_TOKEN"; then
  echo "✅ Detected GitHub token"
else
  echo "❌ GitHub token not detected"
fi
```

## Real-World Scenarios

### Scenario 1: Pre-Deployment Secret Audit

**Context**: CI/CD pipeline checks for secrets before deployment

```bash
#!/bin/bash
# pre-deploy-secret-check.sh

NAMESPACE="staging"
DEPLOYMENT="my-app"

# Deploy to temporary namespace
kubectl create ns temp-secret-scan
kubectl apply -f deploy/$DEPLOYMENT.yaml -n temp-secret-scan

# Wait for scan
sleep 90

# Check for critical secret findings
CRITICAL=$(kubectl get configauditreport -n temp-secret-scan -o json | \
  jq '[.items[].report.checks[] | select(.category == "Secret" and .severity == "CRITICAL")] | length')

if [ "$CRITICAL" -gt 0 ]; then
  echo "❌ Deployment blocked: $CRITICAL critical secrets found"
  kubectl get configauditreport -n temp-secret-scan -o yaml
  kubectl delete ns temp-secret-scan
  exit 1
else
  echo "✅ No critical secrets found"
  kubectl delete ns temp-secret-scan
  exit 0
fi
```

### Scenario 2: Secret Remediation Workflow

**Context**: Migrate hardcoded secrets to Kubernetes Secrets

**Before** (insecure):
```yaml
env:
- name: DB_PASSWORD
  value: "hardcoded_password_123"
```

**After** (secure):
```yaml
# 1. Create Kubernetes Secret
kubectl create secret generic db-credentials \
  --from-literal=password='actual_password_123' \
  -n production

# 2. Reference secret in deployment
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: password
```

**Verify fix**:
```bash
# Redeploy app
kubectl apply -f deploy/app-fixed.yaml -n production

# Wait for rescan
sleep 90

# Check for secrets
kubectl get configauditreport -n production -o json | \
  jq '.items[0].report.checks[] | select(.category == "Secret")'
# Expected: Empty array (no secrets)
```

### Scenario 3: Compliance Audit

**Context**: Generate report of all exposed secrets for audit

```bash
# Export all secret findings across all namespaces
kubectl get configauditreport -A -o json | \
  jq '[.items[] | {
    namespace: .metadata.namespace,
    resource: .metadata.name,
    secrets: [.report.checks[] | select(.category == "Secret") | {
      title: .title,
      severity: .severity,
      description: .description
    }]
  }] | map(select(.secrets | length > 0))' > secret-audit-$(date +%Y-%m).json

# Generate CSV report
jq -r '.[] | [.namespace, .resource, (.secrets | length)] | @csv' secret-audit-*.json
```

**Output**:
```csv
"production","deployment-api-server",3
"staging","deployment-worker",1
"development","deployment-test-app",5
```

## Advanced Configuration

### 1. Custom Secret Patterns

```yaml
trivy:
  trivyConfig:
    secret:
      customPatterns:
        - name: "Internal API Key"
          pattern: "INTERNAL_API_KEY_[A-Z0-9]{32}"
          severity: CRITICAL
          
        - name: "Legacy Database Password"
          pattern: "LEGACY_DB_PASS=.*"
          severity: HIGH
```

### 2. Allowlist for False Positives

```yaml
trivy:
  trivyConfig:
    secret:
      allowlist:
        # Example: Placeholder values in documentation
        - "AWS_ACCESS_KEY_ID=YOUR_KEY_HERE"
        - "PASSWORD=changeme"
```

### 3. Webhook Notifications

```yaml
trivy:
  webhook:
    enabled: true
    url: "https://security-alerts.example.com/trivy"
    events:
      - secret-detected
      - critical-finding
```

## Troubleshooting

### Issue: Secrets Not Detected

**Symptoms**: Known secrets not appearing in ConfigAuditReport

**Solution**:
```bash
# Check if secret scanning enabled
kubectl get deployment trivy-operator -n trivy-system -o yaml | \
  grep -A 5 "TRIVY_SECRET"

# If missing, update config:
helm upgrade trivy-security charts/common-security \
  --set trivy.trivyConfig.secret.enabled=true \
  -n trivy-system \
  --reuse-values
```

### Issue: Too Many False Positives

**Symptoms**: Test data flagged as secrets

**Solution**:
```yaml
# Add to values file
trivy:
  trivyConfig:
    secret:
      # Exclude test namespaces
      excludeNamespaces:
        - "test-*"
        - "sandbox"
        
      # Ignore test secrets
      allowlist:
        - "TEST_API_KEY=test_key_123"
```

### Issue: ConfigAuditReport Not Created

**Symptoms**: No report after 5 minutes

**Solution**:
```bash
# Check Trivy Operator logs
kubectl logs -n trivy-system deployment/trivy-operator

# Force rescan by deleting pod
kubectl delete pod -n test-security -l app=secret-test

# Check for errors in events
kubectl get events -n test-security --sort-by='.lastTimestamp'
```

## Performance Considerations

### 1. Scan Frequency

```yaml
# Avoid continuous rescanning
trivy:
  operator:
    # Scan on pod creation only
    scanJobsInNamespace: "production,staging"
    
    # Disable scheduled rescans for secrets
    configAuditReports:
      scanInterval: "24h"  # Once daily
```

### 2. Resource Limits

```yaml
trivy:
  operator:
    resources:
      scanner:
        limits:
          cpu: "500m"
          memory: "512Mi"
```

### 3. Parallel Scans

```yaml
trivy:
  operator:
    # Limit concurrent secret scans
    concurrentScanJobsLimit: 2
```

## Best Practices

1. **Never Commit Secrets**: Use `.gitignore` for secrets, scan PRs before merge
2. **Use Secret Managers**: Vault, AWS Secrets Manager, Azure Key Vault
3. **Rotate Credentials**: Regular rotation for exposed secrets
4. **Kubernetes Secrets**: Minimum viable solution, encrypt at rest
5. **Service Accounts**: Use IRSA (AWS) or Workload Identity (GCP) instead of keys
6. **CI/CD Integration**: Block builds with exposed secrets
7. **Audit Logs**: Track who deployed workloads with secrets

## Success Metrics

- **Secret Detection Rate**: >95% of hardcoded secrets detected
- **False Positive Rate**: <5% of flagged items are false positives
- **MTTR for Exposed Secrets**: <4 hours to rotate and redeploy
- **Compliance**: Zero production workloads with hardcoded secrets

## Integration with Secret Management

### AWS Secrets Manager

```yaml
# Before: Hardcoded secret
env:
- name: DB_PASSWORD
  value: "hardcoded_password"  # ❌

# After: Secrets Manager via External Secrets Operator
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials  # ✅
      key: password

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  secretStoreRef:
    name: aws-secrets-manager
  target:
    name: db-credentials
  data:
  - secretKey: password
    remoteRef:
      key: /production/database/password
```

### HashiCorp Vault

```yaml
# Vault injection via annotations
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/agent-inject-secret-database: "secret/data/database/config"
    vault.hashicorp.com/role: "myapp"
```

## Related Use Cases

- **UC-SECURITY-01**: Trivy Vulnerability Scanning (image CVEs)
- **UC-SECURITY-03**: Falco Runtime Protection (runtime detection)
- **UC-VAULT-01**: Vault Secret Injection (proper secret management)

## References

- [Trivy Secret Scanning](https://aquasecurity.github.io/trivy/latest/docs/secret/)
- [OWASP Secret Management](https://owasp.org/www-project-secure-coding-practices/)
- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)
- [HashiCorp Vault](https://www.vaultproject.io/)
