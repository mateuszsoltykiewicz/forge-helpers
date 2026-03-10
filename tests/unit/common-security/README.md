# common-security Test Suite

Comprehensive test coverage for the `common-security` Helm chart, validating security scanning, secret detection, and runtime protection capabilities.

## 📋 Overview

This test suite provides **Type 1 (Isolated Chart Testing)** for common-security, covering:

- **UC01**: Trivy Operator - Vulnerability scanning for container images
- **UC02**: Secret Detection - Identifying hardcoded secrets in manifests
- **UC03**: Falco Runtime Protection - Real-time threat detection
- **UC04**: Scheduled Security Scans - Automated periodic security audits

## 🎯 Use Cases

### UC01: Trivy Vulnerability Scanning

**Purpose**: Validate Trivy Operator's ability to detect CVEs in container images

**Key Features**:
- VulnerabilityReport CRD validation
- Severity-based filtering (CRITICAL/HIGH/MEDIUM/LOW)
- ConfigAuditReport generation
- ExposedSecretReport creation
- Metrics and ServiceMonitor integration

**Test Workload**: 
- `vulnerable-app.yaml` - nginx:1.14.0 with known CVEs
  - CVE-2018-16843 (CRITICAL) - Memory corruption
  - CVE-2018-16844 (HIGH) - Write out-of-bounds

**Expected Outcomes**:
- VulnerabilityReports generated automatically
- Critical/High severity vulnerabilities detected
- Reports accessible via kubectl/API

**Run Test**:
```bash
cd test-cases
./run-uc01.sh
```

**Real-World Scenarios**:
1. Production audit before deployment
2. CI/CD pipeline integration
3. Compliance reporting (PCI-DSS, HIPAA)

---

### UC02: Secret Detection

**Purpose**: Identify hardcoded secrets in Kubernetes configurations

**Key Features**:
- ConfigAuditReport with secret findings
- Pattern matching for common secret types
- Severity classification (CRITICAL for secrets)
- Remediation guidance in reports

**Detected Secret Patterns**:
- AWS Access Keys (AKIA*)
- GitHub Personal Access Tokens (ghp_*)
- Passwords in environment variables
- JWT tokens
- Slack webhook URLs
- Database connection strings

**Test Workload**:
- `app-with-secrets.yaml` - Pod with hardcoded secrets
  - AWS credentials
  - Database passwords
  - GitHub tokens
  - Slack webhooks

**Expected Outcomes**:
- ConfigAuditReports with secret detections
- CRITICAL severity for exposed credentials
- Recommendations for Kubernetes Secrets/Vault

**Run Test**:
```bash
cd test-cases
./run-uc02.sh
```

**Real-World Scenarios**:
1. Pre-commit hooks to prevent secret leaks
2. Audit existing deployments for secrets
3. Compliance scanning (SOC 2, ISO 27001)

---

### UC03: Falco Runtime Protection

**Purpose**: Real-time threat detection during container runtime

**Key Features**:
- eBPF-based system call monitoring
- Custom Falco rules
- Alert generation and routing
- DaemonSet deployment across nodes
- Integration with SIEM systems

**Custom Rules Implemented**:
1. **Shell Spawned in Container** (WARNING)
   - Detects: bash, sh, zsh, ksh execution
   - Purpose: Identify interactive shell access

2. **Write to Etc Directory** (WARNING)
   - Detects: Modifications to /etc/
   - Purpose: Configuration tampering detection

3. **Suspicious Outbound Connection** (WARNING)
   - Detects: High ports not matching standard services
   - Purpose: Data exfiltration, C2 communication

4. **Privilege Escalation Attempt** (CRITICAL)
   - Detects: setuid operations to root (uid=0)
   - Purpose: Unauthorized privilege gain

5. **Crypto Mining Activity** (CRITICAL)
   - Detects: xmrig, minerd, cgminer processes
   - Purpose: Resource abuse prevention

**Test Workload**:
- `suspicious-pod.yaml` - Triggers multiple Falco alerts
  - Shell execution
  - /etc/ file creation
  - Network connection attempts

**Expected Outcomes**:
- Falco DaemonSet running on all nodes
- Alerts generated for suspicious activities
- Logs available via kubectl logs/files

**Run Test**:
```bash
cd test-cases
./run-uc03.sh
```

**Real-World Scenarios**:
1. Detect container breakout attempts
2. Identify compromised containers
3. Compliance monitoring (PCI-DSS Req 10)

---

### UC04: Scheduled Security Scans

**Purpose**: Automate periodic security scanning with Kubernetes CronJobs

**Key Features**:
- CronJob-based scheduling (configurable intervals)
- Trivy-based scanning across multiple namespaces
- Report storage (ConfigMap, PVC, S3)
- RBAC for cross-namespace access
- Job history and retention policies

**Scan Configuration**:
- **Default Schedule**: Daily at 2 AM UTC (`0 2 * * *`)
- **Target Namespaces**: default, production, staging
- **Severities**: CRITICAL, HIGH, MEDIUM
- **Output Formats**: JSON, HTML, SARIF

**Report Storage Options**:
1. **ConfigMap** (enabled by default)
   - Quick access via kubectl
   - Limited size (1MB etcd limit)

2. **Persistent Volume** (optional)
   - Long-term storage
   - 10Gi default size

3. **S3 Bucket** (optional)
   - External storage
   - Integration with analytics tools

**Expected Outcomes**:
- CronJob created with specified schedule
- Jobs execute on schedule
- Reports stored in configured location
- Job history retained per policy

**Run Test**:
```bash
cd test-cases
./run-uc04.sh
```

**Real-World Scenarios**:
1. Weekly production vulnerability audits
2. Daily pre-deployment scans in staging
3. Monthly compliance reports for security teams

---

## 🚀 Quick Start

### Prerequisites

```bash
# Verify tools
kubectl version --client
helm version

# Check cluster access
kubectl cluster-info
kubectl get nodes

# Verify common-security chart exists
ls -la ../../charts/common-security/
```

### Run All Tests

```bash
# From common-security directory
./run-all.sh
```

### Run Individual Tests

```bash
cd test-cases

# UC01: Trivy vulnerability scanning
./run-uc01.sh

# UC02: Secret detection
./run-uc02.sh

# UC03: Falco runtime protection
./run-uc03.sh

# UC04: Scheduled scans
./run-uc04.sh
```

## 📁 Directory Structure

```
common-security/
├── README.md                    # This file
├── run-all.sh                   # Execute all UCs sequentially
├── test-cases/
│   ├── run-uc01.sh             # Trivy scanning tests
│   ├── run-uc02.sh             # Secret detection tests
│   ├── run-uc03.sh             # Falco runtime tests
│   ├── run-uc04.sh             # Scheduled scan tests
│   ├── UC01-trivy-vuln.md      # UC01 documentation
│   ├── UC02-secret-detection.md
│   ├── UC03-falco-runtime.md
│   └── UC04-scheduled-scans.md
├── values/
│   ├── uc01-trivy-vuln.yaml    # Trivy configuration
│   ├── uc02-secret-scan.yaml   # Secret detection config
│   ├── uc03-falco-runtime.yaml # Falco configuration
│   └── uc04-scheduled-scan.yaml # CronJob configuration
└── workloads/
    ├── vulnerable-app.yaml      # nginx:1.14.0 with CVEs
    ├── app-with-secrets.yaml    # Hardcoded secrets
    └── suspicious-pod.yaml      # Triggers Falco alerts
```

## 🔧 Configuration

### Trivy Operator (UC01, UC02)

```yaml
# values/uc01-trivy-vuln.yaml
trivy:
  enabled: true
  operator:
    scanJobTimeout: "10m"
    vulnerabilityScannerScanOnlyCurrentRevisions: true
  
  trivy:
    severity: "CRITICAL,HIGH,MEDIUM,LOW"
  
  resources:
    limits:
      memory: 1Gi
      cpu: 1000m
```

### Falco (UC03)

```yaml
# values/uc03-falco-runtime.yaml
falco:
  enabled: true
  driver:
    kind: ebpf  # or 'module' for kernel module
  
  customRules:
    shell-spawn.yaml: |
      - rule: Shell Spawned in Container
        priority: WARNING
        condition: >
          spawned_process and container and
          proc.name in (bash, sh, zsh, ksh)
```

### Scheduled Scans (UC04)

```yaml
# values/uc04-scheduled-scan.yaml
scheduledScans:
  cronjob:
    enabled: true
    schedule: "0 2 * * *"  # Daily at 2 AM
    
  scanner:
    image: aquasec/trivy:0.48.0
    namespaces:
      - default
      - production
      - staging
    
  reports:
    configmap:
      enabled: true
      name: security-scan-report
```

## 📊 Expected Test Results

### Passing Test Output

```
=================================================================
  common-security Test Suite - All Use Cases
=================================================================

╔════════════════════════════════════════════════════════════════╗
║  UC01: Trivy Vulnerability Scanning
╚════════════════════════════════════════════════════════════════╝

✅ PASS: kubectl installed
✅ PASS: helm installed
✅ PASS: Chart installed
✅ PASS: Trivy Operator deployed
✅ PASS: VulnerabilityReport CRDs present
✅ PASS: Vulnerable app deployed
✅ PASS: VulnerabilityReport created
✅ PASS: CVE-2018-16843 detected
✅ PASS: CVE-2018-16844 detected
✅ PASS: Critical vulnerabilities found

Total Tests:   10
Passed:        10
Failed:        0

✅ UC01 PASSED

[... similar output for UC02, UC03, UC04 ...]

=================================================================
  Final Summary
=================================================================

Total Use Cases:   4
Passed:            4
Failed:            0
Duration:          420s

✅ All common-security use cases passed!
```

## 🛠️ Troubleshooting

### Trivy Operator Issues (UC01, UC02)

**Problem**: VulnerabilityReports not generated

```bash
# Check operator logs
kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator

# Verify CRDs
kubectl get crd | grep aquasecurity

# Check scan jobs
kubectl get jobs -n trivy-system
```

**Problem**: Scans timing out

```bash
# Increase timeout in values
helm upgrade trivy-release --set trivy.operator.scanJobTimeout=15m

# Check node resources
kubectl top nodes
```

### Falco Issues (UC03)

**Problem**: Driver not loading

```bash
# Check driver status
kubectl exec -n falco-system daemonset/falco -- falco-driver-loader status

# View driver logs
kubectl logs -n falco-system -l app=falco -c falco-driver-loader

# Try switching driver type
helm upgrade falco-release --set falco.driver.kind=module
```

**Problem**: No alerts generated

```bash
# Check Falco logs
kubectl logs -n falco-system -l app=falco -c falco

# Verify rules loaded
kubectl exec -n falco-system daemonset/falco -- falco --list

# Test with suspicious activity
kubectl exec suspicious-pod -- sh -c "touch /etc/test-file"
```

### Scheduled Scans Issues (UC04)

**Problem**: CronJob not executing

```bash
# Check CronJob status
kubectl get cronjob -n security-system

# View CronJob details
kubectl describe cronjob security-scan -n security-system

# Check job history
kubectl get jobs -n security-system

# Manually trigger job
kubectl create job test-scan --from=cronjob/security-scan -n security-system
```

**Problem**: Reports not stored

```bash
# Check ConfigMap
kubectl get configmap security-scan-report -n security-system -o yaml

# Verify RBAC permissions
kubectl auth can-i list pods --as=system:serviceaccount:security-system:security-scanner

# Check job logs
kubectl logs -n security-system -l job-name=<job-name>
```

### General Issues

**Problem**: Namespace conflicts

```bash
# Clean up previous test runs
kubectl delete namespace trivy-system falco-system security-system --wait=false
helm uninstall trivy-release falco-release security-scans
```

**Problem**: Resource constraints

```bash
# Check cluster resources
kubectl top nodes
kubectl describe nodes

# Reduce resource requests
helm upgrade --set resources.limits.memory=512Mi
```

## 🎓 Best Practices

### Security Scanning

1. **Regular Scans**: Schedule daily/weekly scans for production
2. **Severity Thresholds**: Block deployments with CRITICAL/HIGH CVEs
3. **Report Storage**: Use S3 for long-term retention
4. **CI/CD Integration**: Scan images before deployment

### Secret Management

1. **Prevention**: Use pre-commit hooks with Trivy
2. **Detection**: Enable ExposedSecretReports
3. **Remediation**: Rotate exposed credentials immediately
4. **Alternatives**: Use Kubernetes Secrets, Vault, or AWS Secrets Manager

### Runtime Protection

1. **Driver Selection**: Use eBPF for modern kernels (no kernel headers needed)
2. **Rule Tuning**: Customize rules to reduce false positives
3. **Alert Routing**: Integrate with PagerDuty, Slack, SIEM
4. **Performance**: Monitor Falco resource usage on nodes

### Scheduled Scans

1. **Timing**: Run during low-traffic periods (e.g., 2-4 AM)
2. **Concurrency**: Use `Forbid` policy to prevent overlap
3. **Retention**: Keep 3-5 successful jobs for history
4. **Notifications**: Alert on scan failures

## 📚 References

### Trivy Operator
- [Official Documentation](https://aquasecurity.github.io/trivy-operator/)
- [Trivy CLI](https://github.com/aquasecurity/trivy)
- [CRD Reference](https://aquasecurity.github.io/trivy-operator/latest/docs/crds/)

### Falco
- [Official Documentation](https://falco.org/docs/)
- [Rules Guide](https://falco.org/docs/rules/)
- [eBPF vs Kernel Module](https://falco.org/docs/event-sources/drivers/)

### Kubernetes Security
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Benchmarks](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST SP 800-190](https://csrc.nist.gov/publications/detail/sp/800-190/final)

## 📝 License

Part of the forge-helpers common charts testing framework.

## 🤝 Contributing

When adding new test cases:

1. Create values file: `values/ucXX-name.yaml`
2. Write documentation: `test-cases/UCXX-name.md`
3. Add test workload: `workloads/name.yaml` (if needed)
4. Implement test script: `test-cases/run-ucXX.sh`
5. Update `run-all.sh` to include new UC
6. Update this README with UC description
7. Test locally before committing

**Test Script Template**:
```bash
#!/bin/bash
set -e

# UC-SECURITY-XX: Description

# Color codes, functions (pass, fail, info, warn)
# Prerequisites check
# Cleanup trap
# Test steps (7-12 tests recommended)
# Summary with pass/fail counts
```
