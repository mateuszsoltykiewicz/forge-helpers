# UC-SECURITY-01: Trivy Vulnerability Scanning

## Overview

This Use Case validates the `common-security` chart's ability to enable and configure **Trivy Operator** for automated vulnerability scanning of container images in Kubernetes. Trivy is a comprehensive security scanner that detects:

- **OS package vulnerabilities** (Alpine, Debian, Ubuntu, RHEL, etc.)
- **Application dependency vulnerabilities** (npm, pip, gem, Maven, etc.)
- **Misconfigurations** (CIS benchmarks, best practices)
- **Secrets in container images** (API keys, passwords, tokens)

## Test Objectives

1. **Trivy Operator Deployment**: Install Trivy Operator via chart dependencies
2. **VulnerabilityReport Generation**: Deploy vulnerable app and verify scan
3. **Severity Detection**: Validate HIGH, CRITICAL vulnerability identification
4. **Report Accessibility**: Query VulnerabilityReport CRD via kubectl
5. **Automated Scanning**: Verify scans trigger automatically on pod creation

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │               Trivy Operator Namespace                  │   │
│  │                                                         │   │
│  │  ┌──────────────────┐         ┌──────────────────┐    │   │
│  │  │ Trivy Operator   │────────▶│  Scanner Pods    │    │   │
│  │  │   Controller     │         │ (Job per image)  │    │   │
│  │  └──────────────────┘         └──────────────────┘    │   │
│  │         │                             │                │   │
│  │         │ Watch Pods                  │ Scan Results   │   │
│  │         ▼                             ▼                │   │
│  │  ┌──────────────────────────────────────────────┐     │   │
│  │  │   VulnerabilityReport CRD                    │     │   │
│  │  │   - CVE-2023-12345 (CRITICAL)                │     │   │
│  │  │   - CVE-2023-67890 (HIGH)                    │     │   │
│  │  └──────────────────────────────────────────────┘     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │             Application Namespace                       │   │
│  │                                                         │   │
│  │  ┌──────────────────┐                                  │   │
│  │  │ Vulnerable App   │◀─── Trivy scans image            │   │
│  │  │ nginx:1.14.0     │     (old version with CVEs)      │   │
│  │  └──────────────────┘                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (EKS 1.23+)
- `kubectl` and `helm` CLI tools
- Trivy Operator Helm chart (installed via chart dependencies)
- Internet access for Trivy vulnerability database updates

## Test Environment

### Values File (`uc01-trivy-vuln.yaml`)

```yaml
# Enable Trivy Operator
trivy:
  enabled: true
  
  operator:
    # Automatic scanning on pod creation
    scanJobsInNamespace: "*"  # Scan all namespaces
    
    # Vulnerability scanner settings
    vulnerabilityReports:
      enabled: true
      scanner:
        reportType: "summary"
        skipUpdate: false       # Update vulnerability DB
    
    # Severity thresholds
    severity:
      - CRITICAL
      - HIGH
      - MEDIUM
      
    # Resource limits for scanner jobs
    resources:
      scanner:
        limits:
          cpu: "1000m"
          memory: "1Gi"
        requests:
          cpu: "500m"
          memory: "512Mi"
          
  # Trivy configuration
  trivyConfig:
    db:
      repository: "ghcr.io/aquasecurity/trivy-db"
    vulnerability:
      type: "os,library"  # Scan OS packages and libraries
```

### Vulnerable Application (`vulnerable-app.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vulnerable-nginx
  labels:
    app: vulnerable-nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vulnerable-nginx
  template:
    metadata:
      labels:
        app: vulnerable-nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.0  # Old version with known CVEs
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: "100m"
            memory: "128Mi"
          requests:
            cpu: "50m"
            memory: "64Mi"
```

**Why nginx:1.14.0?**
- Released in 2018
- Contains **CVE-2018-16843** (CRITICAL): CPU exhaustion DoS
- Contains **CVE-2018-16844** (HIGH): Buffer overflow
- Contains **CVE-2018-16845** (HIGH): Memory corruption
- Multiple outdated Debian packages with CVEs

## Test Steps

### Step 1: Install Trivy Operator

```bash
helm install trivy-security charts/common-security \
  -f tests/unit/common-security/values/uc01-trivy-vuln.yaml \
  -n trivy-system \
  --create-namespace \
  --wait
```

### Step 2: Verify Trivy Operator Deployment

```bash
# Check operator pod
kubectl get pods -n trivy-system

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# trivy-operator-7d8f9c5b6d-abc12         1/1     Running   0          30s
```

### Step 3: Verify CRDs Installed

```bash
kubectl get crd | grep trivy

# Expected CRDs:
# vulnerabilityreports.aquasecurity.github.io
# configauditreports.aquasecurity.github.io
# exposedsecretreports.aquasecurity.github.io
# rbacassessmentreports.aquasecurity.github.io
```

### Step 4: Deploy Vulnerable Application

```bash
kubectl create namespace test-security
kubectl apply -f tests/unit/common-security/workloads/vulnerable-app.yaml -n test-security
```

### Step 5: Wait for Scan Completion

```bash
# Trivy Operator automatically creates a scan job
kubectl get jobs -n trivy-system -w

# Wait for scan job to complete (~60-120 seconds)
# Job name pattern: scan-vulnerabilityreport-<pod-uid>
```

### Step 6: Check VulnerabilityReport

```bash
# List vulnerability reports
kubectl get vulnerabilityreports -n test-security

# Expected output:
# NAME                                   REPOSITORY   TAG      CRITICAL   HIGH   MEDIUM   LOW
# replicaset-vulnerable-nginx-abc123-nginx   nginx    1.14.0   3          12     45       67
```

### Step 7: Inspect Report Details

```bash
kubectl get vulnerabilityreport -n test-security -o yaml | head -50
```

**Expected Output**:
```yaml
apiVersion: aquasecurity.github.io/v1alpha1
kind: VulnerabilityReport
metadata:
  name: replicaset-vulnerable-nginx-abc123-nginx
  namespace: test-security
  labels:
    resource-spec-hash: "7d8f9c5b6d"
    trivy-operator.resource.kind: ReplicaSet
    trivy-operator.resource.name: vulnerable-nginx-abc123
spec:
  artifact:
    repository: nginx
    tag: "1.14.0"
  scanner:
    name: Trivy
    vendor: Aqua Security
    version: "0.48.0"
  registry:
    server: index.docker.io
report:
  summary:
    criticalCount: 3
    highCount: 12
    mediumCount: 45
    lowCount: 67
  vulnerabilities:
  - vulnerabilityID: CVE-2018-16843
    resource: nginx
    installedVersion: 1.14.0
    fixedVersion: 1.15.6
    severity: CRITICAL
    title: "nginx: CPU exhaustion DoS via excessive HTTP/2 requests"
    primaryLink: https://avd.aquasec.com/nvd/cve-2018-16843
    
  - vulnerabilityID: CVE-2018-16844
    resource: libc-bin
    installedVersion: 2.24-11+deb9u3
    fixedVersion: 2.24-11+deb9u4
    severity: HIGH
    title: "glibc: Buffer overflow in memcpy"
    primaryLink: https://avd.aquasec.com/nvd/cve-2018-16844
```

## Validation Criteria

### 1. Trivy Operator Running

```bash
kubectl get deploy -n trivy-system | grep trivy-operator

# Expected: 1/1 READY
```

### 2. VulnerabilityReport Exists

```bash
if kubectl get vulnerabilityreport -n test-security | grep -q "vulnerable-nginx"; then
  echo "✅ VulnerabilityReport created"
else
  echo "❌ VulnerabilityReport not found"
fi
```

### 3. Critical Vulnerabilities Detected

```bash
CRITICAL_COUNT=$(kubectl get vulnerabilityreport -n test-security -o json | jq '.items[0].report.summary.criticalCount')

if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "✅ Detected $CRITICAL_COUNT critical vulnerabilities"
else
  echo "❌ No critical vulnerabilities found (unexpected)"
fi
```

### 4. CVE-2018-16843 Found

```bash
if kubectl get vulnerabilityreport -n test-security -o yaml | grep -q "CVE-2018-16843"; then
  echo "✅ Known CVE-2018-16843 detected"
else
  echo "⚠️  CVE-2018-16843 not found (may be false negative)"
fi
```

## Real-World Scenarios

### Scenario 1: Production Image Audit

**Context**: Security team requests audit of all production images

```bash
# Trivy automatically scans all pods in production namespace
kubectl get vulnerabilityreports -n production -o wide

# Generate CSV report
kubectl get vulnerabilityreport -n production -o json | \
  jq -r '.items[] | [.metadata.name, .report.summary.criticalCount, .report.summary.highCount] | @csv'
```

**Output**:
```
"replicaset-api-server-xyz-api",5,12
"replicaset-database-abc-postgres",0,3
"replicaset-frontend-def-nginx",2,8
```

### Scenario 2: CI/CD Gate

**Context**: Block deployment if critical vulnerabilities detected

```bash
#!/bin/bash
# pre-deploy-scan.sh

NAMESPACE="staging"
IMAGE="myapp:v1.2.3"

# Deploy test pod
kubectl run scan-test --image=$IMAGE -n $NAMESPACE

# Wait for scan
sleep 120

# Check critical count
CRITICAL=$(kubectl get vulnerabilityreport -n $NAMESPACE -l app=scan-test -o json | \
  jq '.items[0].report.summary.criticalCount')

if [ "$CRITICAL" -gt 0 ]; then
  echo "❌ Deployment blocked: $CRITICAL critical vulnerabilities"
  kubectl delete pod scan-test -n $NAMESPACE
  exit 1
else
  echo "✅ Deployment approved: No critical vulnerabilities"
  kubectl delete pod scan-test -n $NAMESPACE
  exit 0
fi
```

### Scenario 3: Compliance Reporting

**Context**: Generate monthly compliance report for audit

```bash
# Export all vulnerability reports
kubectl get vulnerabilityreport -A -o json > /tmp/vuln-report-$(date +%Y-%m).json

# Generate summary
jq '.items | group_by(.metadata.namespace) | 
  map({namespace: .[0].metadata.namespace, 
       critical: map(.report.summary.criticalCount) | add,
       high: map(.report.summary.highCount) | add})' /tmp/vuln-report-*.json
```

**Output**:
```json
[
  {
    "namespace": "production",
    "critical": 12,
    "high": 45
  },
  {
    "namespace": "staging",
    "critical": 0,
    "high": 8
  }
]
```

## Advanced Configuration

### 1. Namespace-Specific Scanning

```yaml
trivy:
  operator:
    # Only scan specific namespaces
    scanJobsInNamespace: "production,staging"
    
    # Exclude namespaces
    excludeNamespaces:
      - "kube-system"
      - "kube-public"
```

### 2. Custom Severity Policies

```yaml
trivy:
  policies:
    # Fail on HIGH severity in production
    production:
      severity: ["CRITICAL", "HIGH"]
      action: "fail"
      
    # Warn on HIGH severity in staging
    staging:
      severity: ["CRITICAL", "HIGH"]
      action: "warn"
```

### 3. Scheduled Rescans

```yaml
trivy:
  schedule:
    enabled: true
    cron: "0 2 * * *"  # Rescan daily at 2 AM
```

## Troubleshooting

### Issue: VulnerabilityReport Not Created

**Symptoms**: Report missing after 5 minutes

**Solution**:
```bash
# Check Trivy Operator logs
kubectl logs -n trivy-system deployment/trivy-operator

# Common issues:
# 1. Image pull failures
# 2. Resource limits too low (increase memory)
# 3. Network timeout fetching vulnerability DB

# Force rescan by deleting pod
kubectl delete pod -n test-security -l app=vulnerable-nginx
```

### Issue: Database Update Failures

**Symptoms**: `error downloading vulnerability database`

**Solution**:
```bash
# Check network connectivity from operator
kubectl exec -n trivy-system deployment/trivy-operator -- \
  wget -qO- https://ghcr.io/aquasecurity/trivy-db

# If behind proxy, configure:
trivy:
  proxy:
    httpProxy: http://proxy.example.com:8080
    httpsProxy: http://proxy.example.com:8080
    noProxy: ".svc,.cluster.local"
```

### Issue: Too Many Scanner Jobs

**Symptoms**: Excessive resource usage from scan jobs

**Solution**:
```yaml
trivy:
  operator:
    # Limit concurrent scans
    concurrentScanJobsLimit: 3
    
    # Increase scan timeout
    scanJobTimeout: "10m"
    
    # Set resource limits
    resources:
      scanner:
        limits:
          cpu: "500m"
          memory: "500Mi"
```

## Performance Considerations

### 1. Scan Duration

| Image Size | Layers | Scan Time | Memory Usage |
|------------|--------|-----------|--------------|
| Alpine (5MB) | 1 | ~15s | 50MB |
| Debian (100MB) | 3 | ~45s | 150MB |
| Ubuntu (200MB) | 5 | ~90s | 300MB |
| Large App (1GB) | 15 | ~5min | 800MB |

### 2. Database Size

- **Vulnerability DB**: ~200MB compressed
- **Update frequency**: Daily
- **Storage requirement**: 500MB per namespace

### 3. Resource Planning

```yaml
# For 100 pods across 10 namespaces:
trivy:
  operator:
    resources:
      limits:
        cpu: "2000m"
        memory: "4Gi"
      requests:
        cpu: "1000m"
        memory: "2Gi"
        
    scanner:
      resources:
        limits:
          cpu: "1000m"    # Per scan job
          memory: "1Gi"   # Per scan job
```

## Best Practices

1. **Image Scanning in CI**: Scan images before deployment, not just in cluster
2. **Policy Enforcement**: Use admission controllers to block vulnerable images
3. **Regular Rescans**: Schedule daily rescans to catch newly disclosed CVEs
4. **Database Caching**: Use shared PVC for vulnerability database across clusters
5. **Namespace Isolation**: Limit scanning to production namespaces for performance
6. **Alert Integration**: Forward CRITICAL findings to incident management systems
7. **Exemptions**: Maintain allowlist for accepted risks with justification

## Success Metrics

- **Scan Coverage**: >95% of production pods scanned
- **Critical CVE MTTR**: <24 hours to patch or mitigate
- **False Positive Rate**: <10% of CRITICAL findings
- **Scan Completion Time**: <2 minutes for 90th percentile
- **Database Freshness**: Updated daily (max 24h age)

## Integration with CI/CD

### GitHub Actions

```yaml
name: Trivy Scan
on: [push]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'myapp:${{ github.sha }}'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'  # Fail build on findings
```

### Jenkins Pipeline

```groovy
pipeline {
  agent any
  stages {
    stage('Trivy Scan') {
      steps {
        sh '''
          trivy image --severity CRITICAL,HIGH myapp:${BUILD_NUMBER}
        '''
      }
    }
  }
}
```

## Related Use Cases

- **UC-SECURITY-02**: Secret Detection (exposed credentials)
- **UC-SECURITY-03**: Falco Runtime Protection (runtime threats)
- **UC-SECURITY-04**: Scheduled Security Scans (periodic audits)

## References

- [Trivy Operator Documentation](https://aquasecurity.github.io/trivy-operator/)
- [Trivy Scanner](https://trivy.dev/)
- [CVE Database](https://cve.mitre.org/)
- [NIST NVD](https://nvd.nist.gov/)
