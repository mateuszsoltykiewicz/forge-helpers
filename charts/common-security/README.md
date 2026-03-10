# Forge Common Library - Security

Library chart for security scanning and runtime protection.

## Overview

This Helm library provides reusable templates for **Trivy vulnerability scanning** and **Falco runtime security**, enabling comprehensive security monitoring for Kubernetes applications.

**Features**:
- **Trivy**: Container image vulnerability scanning, CVE detection
- **Configuration Audit**: Kubernetes misconf iguration detection
- **Secret Scanning**: Leaked credentials detection
- **Falco**: Runtime threat detection and behavioral monitoring
- **Compliance Rules**: Pod Security Standards, CIS benchmarks
- **Automated Scanning**: Scheduled CronJob scans

**Integrations**:
- **common-forge**: Naming conventions, labels
- **Trivy Operator**: Automated vulnerability scanning
- **Falco**: Runtime security event monitoring

## Installation

Add as a dependency in your `Chart.yaml`:

```yaml
dependencies:
  - name: common-security
    version: ~0.1.0
    repository: file://../common-security
```

## Usage Examples

### Example 1: Trivy Vulnerability Scanning Policy

Enable vulnerability scanning for container images:

```yaml
# values.yaml
security:
  trivy:
    vulnerabilityReport:
      enabled: true
      
      # Report CRITICAL and HIGH severities
      severities:
        - CRITICAL
        - HIGH
      
      # Ignore vulnerabilities without fixes
      ignoreUnfixed: true
      
      # Ignore specific CVEs (false positives)
      ignoreVulnerabilities:
        - CVE-2021-44228  # Log4j (already patched in our image)
      
      # Skip scanning certain directories
      skipDirs:
        - /tmp
        - /var/cache
      
      # Scan timeout
      timeout: "5m"
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.trivy.vulnerabilityReport" . }}
```

This creates a ConfigMap that Trivy Operator uses to scan your images.

### Example 2: Configuration Audit (Misconfiguration Detection)

Scan Kubernetes resources for misconfigurations:

```yaml
# values.yaml
security:
  trivy:
    configAuditReport:
      enabled: true
      
      # Severities to report
      severities:
        - CRITICAL
        - HIGH
        - MEDIUM
      
      # Compliance standards
      compliance:
        - k8s-pss-baseline    # Pod Security Standards Baseline
        - k8s-pss-restricted  # Pod Security Standards Restricted
        - k8s-nsa             # NSA/CISA Kubernetes Hardening
      
      # Scanners
      scanners:
        - config-audit  # Kubernetes configuration
        - secret        # Secret detection
        - rbac          # RBAC misconfigurations
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.trivy.configAuditReport" . }}
```

This detects issues like:
- Containers running as root
- Missing resource limits
- Privileged containers
- Insecure capabilities

### Example 3: Secret Scanning

Detect leaked credentials in container images:

```yaml
# values.yaml
security:
  trivy:
    secretScan:
      enabled: true
      
      # Secret types to detect
      secretTypes:
        - aws-access-key-id
        - aws-secret-access-key
        - github-token
        - gitlab-token
        - slack-webhook-url
        - private-key
        - generic-api-key
      
      # Exclude paths
      excludePaths:
        - "**/test/**"
        - "**/vendor/**"
        - "**/node_modules/**"
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.trivy.secretScan" . }}
```

### Example 4: Scheduled Trivy Scan Job

Run automated vulnerability scans on a schedule:

```yaml
# values.yaml
security:
  trivy:
    scanJob:
      enabled: true
      
      # Daily at 2 AM
      schedule: "0 2 * * *"
      
      # Image to scan
      imageRef: "myregistry.io/myapp:latest"
      
      # Trivy scanner image
      image: "aquasec/trivy:0.48.0"
      
      # Report CRITICAL and HIGH only
      severity:
        - CRITICAL
        - HIGH
      
      # Ignore unfixed vulnerabilities
      ignoreUnfixed: true
      
      # Service account with pull permissions
      serviceAccountName: "trivy-operator"
      
      # Resources
      resources:
        limits:
          cpu: 500m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 128Mi
      
      # Job history
      successfulJobsHistoryLimit: 3
      failedJobsHistoryLimit: 1
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.trivy.scanJob" . }}
```

### Example 5: Trivy Scan with Node Scheduling

Run scans only on specific nodes using tolerations, nodeAffinity, and podAntiAffinity:

```yaml
# values.yaml
security:
  trivy:
    scanJob:
      enabled: true
      schedule: "0 2 * * *"
      imageRef: "myregistry.io/myapp:latest"
      
      # Tolerations - allow scheduling on tainted nodes
      tolerations:
        - key: "security-scanning"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/batch"
          operator: "Exists"
          effect: "NoSchedule"
      
      # Node selector - simple node selection
      nodeSelector:
        nodeType: "security-scanner"
        diskType: "ssd"
      
      # Node affinity - prefer nodes with specific labels
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: "node-role.kubernetes.io/security"
                  operator: In
                  values:
                    - "scanner"
                    - "batch"
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
                - key: "diskType"
                  operator: In
                  values:
                    - "ssd"
      
      # Pod anti-affinity - avoid running multiple scans on same node
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                  - key: "moai.forge.io/security-tool"
                    operator: In
                    values:
                      - "trivy"
              topologyKey: "kubernetes.io/hostname"
      
      # Resources
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 200m
          memory: 256Mi
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.trivy.scanJob" . }}
```

**Benefits**:
- **Tolerations**: Allow scans to run on dedicated security nodes with taints
- **Node Selector**: Simple key-value node selection
- **Node Affinity**: Advanced node selection with required/preferred rules
- **Pod Anti-Affinity**: Distribute scan jobs across nodes to avoid resource contention

### Example 6: Falco Application Security Rules

Monitor runtime behavior for suspicious activity:

```yaml
# values.yaml
security:
  falco:
    applicationRules:
      enabled: true
      
      # Allowed application processes
      allowedProcesses:
        - java
        - node
        - python
        - ruby
      
      # Known malicious IPs to alert on
      suspiciousIPs:
        - 192.0.2.1
        - 198.51.100.1
      
      # Alert priority
      priority: "WARNING"
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.falco.applicationRules" . }}
```

This creates Falco rules that detect:
- **Unexpected processes** in containers (e.g., shells, curl, wget)
- **Writes to sensitive directories** (/etc, /usr/bin)
- **Outbound connections to suspicious IPs**
- **Shell spawned in container** (potential compromise)
- **Privilege escalation attempts** (sudo, su, setuid)

### Example 7: Falco Compliance Rules

Enforce Pod Security Standards and compliance policies:

```yaml
# values.yaml
security:
  falco:
    complianceRules:
      enabled: true
      
      # Alert priority
      priority: "WARNING"
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.falco.complianceRules" . }}
```

This creates Falco rules that detect:
- **Containers running as root** (PSS violation)
- **Privileged containers** (critical security risk)
- **Sensitive host mounts** (/proc, /sys, /dev, docker.sock)
- **Package management in running containers** (immutability violation)

### Example 8: Custom Falco Rules

Define your own security rules:

```yaml
# values.yaml
security:
  falco:
    rules:
      enabled: true
      
      # Custom macros
      macros:
        - name: database_process
          condition: proc.name in (postgres, mysqld, mongod)
      
      # Custom lists
      lists:
        - name: sensitive_files
          items:
            - /etc/passwd
            - /etc/shadow
            - /root/.ssh/id_rsa
      
      # Raw custom rules (YAML)
      customRules: |
        - rule: Database Direct File Access
          desc: Detect direct file access by database processes
          condition: >
            open_read or open_write
            and database_process
            and fd.name in (sensitive_files)
          output: >
            Database process accessing sensitive file
            (user=%user.name process=%proc.name file=%fd.name)
          priority: CRITICAL
          tags: [database, filesystem, security]
        
        - rule: Cryptocurrency Mining Detected
          desc: Detect cryptocurrency mining activity
          condition: >
            spawned_process
            and proc.name in (xmrig, ethminer, cgminer, bfgminer)
          output: >
            Cryptocurrency mining process detected
            (user=%user.name process=%proc.name parent=%proc.pname)
          priority: CRITICAL
          tags: [mining, security, threat]
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.falco.rules" . }}
```

### Example 9: Complete Production Security Setup

Full security stack with Trivy and Falco:

```yaml
# values.yaml
security:
  # Trivy configuration
  trivy:
    namespace: "trivy-system"
    
    # Vulnerability scanning
    vulnerabilityReport:
      enabled: true
      severities:
        - CRITICAL
        - HIGH
      ignoreUnfixed: true
      timeout: "10m"
    
    # Configuration audit
    configAuditReport:
      enabled: true
      severities:
        - CRITICAL
        - HIGH
      compliance:
        - k8s-pss-restricted
        - k8s-nsa
      scanners:
        - config-audit
        - secret
        - rbac
    
    # Secret scanning
    secretScan:
      enabled: true
      secretTypes:
        - aws-access-key-id
        - aws-secret-access-key
        - github-token
        - private-key
      excludePaths:
        - "**/test/**"
        - "**/vendor/**"
    
    # Scheduled scan
    scanJob:
      enabled: true
      schedule: "0 2 * * *"
      imageRef: "myregistry.io/myapp:latest"
      severity:
        - CRITICAL
        - HIGH
      ignoreUnfixed: true
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 200m
          memory: 256Mi
  
  # Falco configuration
  falco:
    namespace: "falco"
    
    # Application security rules
    applicationRules:
      enabled: true
      allowedProcesses:
        - java
        - node
      priority: "WARNING"
    
    # Compliance rules
    complianceRules:
      enabled: true
      priority: "WARNING"
```

In your templates:

```yaml
# templates/security.yaml
{{- include "security.trivy.vulnerabilityReport" . }}
{{- include "security.trivy.configAuditReport" . }}
{{- include "security.trivy.secretScan" . }}
{{- include "security.trivy.scanJob" . }}
{{- include "security.falco.applicationRules" . }}
{{- include "security.falco.complianceRules" . }}
```

## Templates Reference

### Trivy Templates

**Vulnerability Report Policy**:
```yaml
{{- include "security.trivy.vulnerabilityReport" . }}
```

**Configuration Audit Policy**:
```yaml
{{- include "security.trivy.configAuditReport" . }}
```

**Secret Scan Policy**:
```yaml
{{- include "security.trivy.secretScan" . }}
```

**Scheduled Scan Job**:
```yaml
{{- include "security.trivy.scanJob" . }}
```

### Falco Templates

**Custom Rules**:
```yaml
{{- include "security.falco.rules" . }}
```

**Application Security Rules**:
```yaml
{{- include "security.falco.applicationRules" . }}
```

**Compliance Rules**:
```yaml
{{- include "security.falco.complianceRules" . }}
```

## Vulnerability Severity Levels

### Trivy Severities
- **CRITICAL**: Immediate patching required (CVSS 9.0-10.0)
- **HIGH**: Patch within days (CVSS 7.0-8.9)
- **MEDIUM**: Patch within weeks (CVSS 4.0-6.9)
- **LOW**: Patch when convenient (CVSS 0.1-3.9)
- **UNKNOWN**: Severity not assigned

### Falco Priorities
- **EMERGENCY**: System unusable
- **ALERT**: Action must be taken immediately
- **CRITICAL**: Critical security event
- **ERROR**: Error conditions
- **WARNING**: Warning conditions
- **NOTICE**: Normal but significant
- **INFO**: Informational
- **DEBUG**: Debug-level messages

## Compliance Standards

### Pod Security Standards (PSS)
- **Privileged**: Unrestricted (no restrictions)
- **Baseline**: Minimally restrictive (blocks known privilege escalations)
- **Restricted**: Heavily restricted (hardened, production-ready)

### Supported Compliance Checks
- `k8s-pss-baseline` - Pod Security Standards Baseline
- `k8s-pss-restricted` - Pod Security Standards Restricted
- `k8s-nsa` - NSA/CISA Kubernetes Hardening Guide
- `k8s-cis` - CIS Kubernetes Benchmark

## Best Practices

### Trivy Scanning

**Development**:
```yaml
severities: [CRITICAL, HIGH, MEDIUM, LOW]
ignoreUnfixed: false  # Report all vulnerabilities
```

**Production**:
```yaml
severities: [CRITICAL, HIGH]
ignoreUnfixed: true  # Only report patchable issues
```

### Falco Alert Priorities

**Critical Events** (CRITICAL):
- Shell spawned in container
- Privilege escalation
- Cryptocurrency mining
- Known malicious IPs

**Important Events** (WARNING):
- Unexpected processes
- Writes to sensitive directories
- Compliance violations

**Informational** (INFO):
- Allowed but unusual behavior
- Debugging information

### False Positive Management

**Trivy**:
```yaml
ignoreVulnerabilities:
  - CVE-2021-44228  # Already patched
```

**Falco**:
```yaml
allowedProcesses:
  - legitimate-tool  # Expected in this app
```

## Integration with Monitoring

Forward Falco alerts to Prometheus/Alertmanager:

```yaml
# Falco Helm chart values
falco:
  falco:
    json_output: true
    json_include_output_property: true
    
  falcosidekick:
    enabled: true
    config:
      alertmanager:
        hostport: "http://alertmanager:9093"
```

## Requirements

- **Helm**: 3.0+
- **Trivy Operator**: 0.16+ (for vulnerability scanning)
- **Falco**: 0.36+ (for runtime security)
- **Kubernetes**: 1.23-1.29

## License

Part of the Moai Forge platform.
