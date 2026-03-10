# UC-SECURITY-03: Falco Runtime Protection

## Overview

This Use Case validates the `common-security` chart's ability to deploy and configure **Falco** for runtime threat detection and anomaly detection in Kubernetes. Falco is a CNCF-incubated project that detects:

- **Suspicious syscall activity** (privilege escalation, shell spawning)
- **Anomalous network connections** (unexpected outbound connections)
- **File system tampering** (modifications to /etc, /bin, /usr)
- **Container escapes** (attempts to access host filesystem)
- **Crypto mining** (detection of mining processes)

## Test Objectives

1. **Falco Deployment**: Install Falco as DaemonSet via Helm chart
2. **Rule Loading**: Verify default security rules loaded
3. **Alert Generation**: Trigger suspicious activity and verify alerts
4. **Event Export**: Validate alerts exported to stdout/webhook
5. **Custom Rules**: Test custom rule definitions

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                Falco DaemonSet                          │   │
│  │  (One pod per node)                                     │   │
│  │                                                         │   │
│  │  ┌──────────────────┐         ┌──────────────────┐    │   │
│  │  │  Falco Driver    │────────▶│  Falco Engine    │    │   │
│  │  │  (kernel module  │         │  (rule matching) │    │   │
│  │  │   or eBPF)       │         └──────────────────┘    │   │
│  │  └──────────────────┘                │                │   │
│  │         │                             │                │   │
│  │         │ Syscall Events              │ Alerts         │   │
│  │         ▼                             ▼                │   │
│  │  ┌──────────────────────────────────────────────┐     │   │
│  │  │   Alert Outputs                              │     │   │
│  │  │   - stdout (logs)                            │     │   │
│  │  │   - webhook (Slack, PagerDuty)               │     │   │
│  │  │   - Falco Sidekick (routing)                 │     │   │
│  │  └──────────────────────────────────────────────┘     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │             Suspicious Pod                              │   │
│  │  - Spawns shell: /bin/bash                              │   │
│  │  - Writes to /etc: echo "test" > /etc/malicious         │   │
│  │  - Opens network: nc attacker.com 4444                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                       │                                         │
│                       ▼                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │   Falco Alert (Priority: WARNING)                       │   │
│  │   Rule: "Shell Spawned in Container"                    │   │
│  │   Output: "Shell spawned in suspicious-pod (bash)"      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (EKS 1.23+)
- `kubectl` and `helm` CLI tools
- **Kernel headers** installed on nodes (for kernel module driver)
- Nodes with compatible kernel (>= 4.14) OR eBPF support
- Privileged pod support (Falco needs host access)

## Test Environment

### Values File (`uc03-falco-runtime.yaml`)

```yaml
# Enable Falco runtime protection
falco:
  enabled: true
  
  # Driver configuration (kernel module or eBPF)
  driver:
    kind: "ebpf"  # Use eBPF (modern, no kernel module needed)
    # kind: "module"  # Alternative: kernel module (requires headers)
    
  # DaemonSet configuration
  daemonset:
    updateStrategy:
      type: RollingUpdate
      
  # Resource limits
  resources:
    limits:
      cpu: "1000m"
      memory: "1Gi"
    requests:
      cpu: "200m"
      memory: "512Mi"
      
  # Rule files to load
  rules:
    - /etc/falco/falco_rules.yaml          # Default rules
    - /etc/falco/falco_rules.local.yaml    # Custom rules
    - /etc/falco/k8s_audit_rules.yaml      # Kubernetes audit rules
    
  # Custom rules
  customRules:
    suspicious-shell.yaml: |
      - rule: Shell Spawned in Container
        desc: Detect shell spawned inside container
        condition: >
          spawned_process and container and
          proc.name in (bash, sh, zsh, ksh, dash)
        output: >
          Shell spawned in %container.name (command=%proc.cmdline user=%user.name)
        priority: WARNING
        tags: [container, shell, mitre_execution]
        
      - rule: Write to Etc Directory
        desc: Detect writes to /etc directory
        condition: >
          open_write and container and
          fd.name startswith /etc/
        output: >
          File write to /etc in %container.name (file=%fd.name user=%user.name)
        priority: WARNING
        tags: [filesystem, container]
        
      - rule: Suspicious Network Connection
        desc: Detect outbound connection to non-standard port
        condition: >
          outbound and container and
          fd.sport > 32768 and
          not fd.dport in (80, 443, 8080, 8443)
        output: >
          Suspicious outbound connection from %container.name (dest=%fd.rip:%fd.rport)
        priority: WARNING
        tags: [network, container]
        
  # Alert outputs
  outputs:
    # stdout (logs)
    stdout:
      enabled: true
      
    # Webhook (optional)
    webhook:
      enabled: false
      # url: "https://hooks.slack.com/services/XXX/YYY/ZZZ"
      
    # File output
    file:
      enabled: true
      path: "/var/log/falco/alerts.log"
      
  # Alert settings
  alerts:
    priority: "WARNING"  # Minimum priority to alert
    rate: 1              # Max alerts per second
    
  # Performance tuning
  performance:
    buffered_outputs: true
    drop_failed_exit: false
    
# Falco Sidekick (alert routing)
falcoSidekick:
  enabled: false  # Optional: advanced alert routing
  # webui:
  #   enabled: true  # Web UI for alerts
```

### Suspicious Workload (`suspicious-pod.yaml`)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: suspicious-pod
  labels:
    app: security-test
    behavior: suspicious
spec:
  containers:
  - name: suspicious
    image: alpine:latest
    command: 
    - sh
    - -c
    - |
      echo "Starting suspicious activities..."
      sleep 5
      
      # Trigger: Shell spawned
      echo "1. Spawning shell..."
      /bin/sh -c "echo 'Shell spawned'"
      sleep 2
      
      # Trigger: Write to /etc
      echo "2. Writing to /etc..."
      touch /etc/test-file || true
      sleep 2
      
      # Trigger: Suspicious network connection
      echo "3. Attempting network connection..."
      nc -w 1 example.com 9999 || true
      sleep 2
      
      echo "Activities completed. Sleeping..."
      sleep 3600
    resources:
      limits:
        cpu: "100m"
        memory: "64Mi"
      requests:
        cpu: "50m"
        memory: "32Mi"
    securityContext:
      # Deliberately permissive for testing
      allowPrivilegeEscalation: true
      runAsNonRoot: false
```

## Test Steps

### Step 1: Install Falco

```bash
helm install falco-security charts/common-security \
  -f tests/unit/common-security/values/uc03-falco-runtime.yaml \
  -n falco-system \
  --create-namespace \
  --wait
```

### Step 2: Verify Falco DaemonSet

```bash
kubectl get daemonset -n falco-system

# Expected output:
# NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# falco   3         3         3       3            3
```

### Step 3: Check Falco Logs

```bash
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=50

# Expected: Falco startup logs with loaded rules
```

### Step 4: Deploy Suspicious Pod

```bash
kubectl create namespace test-security
kubectl apply -f tests/unit/common-security/workloads/suspicious-pod.yaml -n test-security
```

### Step 5: Monitor Falco Alerts

```bash
# Watch Falco logs for alerts
kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f | grep -i "warning\|shell\|etc"
```

**Expected Alerts**:
```
14:23:45.123456789: Warning Shell spawned in suspicious-pod (command=/bin/sh -c echo 'Shell spawned' user=root)
14:23:47.456789012: Warning File write to /etc in suspicious-pod (file=/etc/test-file user=root)
14:23:49.789012345: Warning Suspicious outbound connection from suspicious-pod (dest=93.184.216.34:9999)
```

### Step 6: Verify Alert Count

```bash
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep -c "Warning"

# Expected: >= 3 alerts
```

## Validation Criteria

### 1. Falco DaemonSet Running

```bash
READY=$(kubectl get daemonset -n falco-system -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].status.numberReady}')
DESIRED=$(kubectl get daemonset -n falco-system -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].status.desiredNumberScheduled}')

if [ "$READY" -eq "$DESIRED" ]; then
  echo "✅ Falco running on all nodes ($READY/$DESIRED)"
else
  echo "❌ Falco not fully deployed ($READY/$DESIRED)"
fi
```

### 2. Shell Spawn Detection

```bash
if kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep -q "Shell spawned"; then
  echo "✅ Detected shell spawn in container"
else
  echo "❌ Shell spawn not detected"
fi
```

### 3. File System Tampering Detection

```bash
if kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep -q "Write to Etc\|/etc"; then
  echo "✅ Detected write to /etc"
else
  echo "❌ Write to /etc not detected"
fi
```

### 4. Network Activity Detection

```bash
if kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep -qi "network\|connection"; then
  echo "✅ Detected suspicious network activity"
else
  echo "❌ Network activity not detected"
fi
```

## Real-World Scenarios

### Scenario 1: Crypto Mining Detection

**Context**: Detect unauthorized crypto mining in cluster

```yaml
# Custom Falco rule
- rule: Detect Crypto Mining
  desc: Detect processes associated with crypto mining
  condition: >
    spawned_process and container and
    proc.name in (xmrig, minerd, cgminer, ethminer)
  output: >
    Crypto mining detected in %container.name (process=%proc.name)
  priority: CRITICAL
  tags: [process, crypto, mining]
```

**Test**:
```bash
# Deploy pod that runs mining-like process
kubectl run crypto-test --image=alpine -- sh -c "while true; do echo 'xmrig'; sleep 1; done"

# Falco alert:
# CRITICAL Crypto mining detected in crypto-test (process=xmrig)
```

### Scenario 2: Container Escape Attempt

**Context**: Detect attempts to access host filesystem

```yaml
- rule: Container Escape Attempt
  desc: Detect container trying to access host paths
  condition: >
    open_read and container and
    (fd.name startswith /host/ or
     fd.name startswith /proc/1/root/)
  output: >
    Container escape attempt in %container.name (file=%fd.name)
  priority: CRITICAL
  tags: [container, escape, privilege]
```

### Scenario 3: Privilege Escalation

**Context**: Detect setuid/setgid attempts

```yaml
- rule: Privilege Escalation
  desc: Detect privilege escalation via setuid
  condition: >
    evt.type=setuid and container and
    evt.arg.uid=0
  output: >
    Privilege escalation in %container.name (user=%user.name target_uid=0)
  priority: CRITICAL
  tags: [privilege, escalation]
```

## Advanced Configuration

### 1. Kubernetes Audit Logging

```yaml
falco:
  # Enable Kubernetes audit log monitoring
  kubernetesAudit:
    enabled: true
    webhook:
      enabled: true
      url: "http://falco:8765/k8s-audit"
      
  # Kubernetes audit rules
  k8sAuditRules:
    - rule: K8s Secret Access
      desc: Detect access to Kubernetes secrets
      condition: >
        k8s_audit and ka.verb=get and
        ka.target.resource=secrets
      output: >
        Secret accessed (user=%ka.user.name secret=%ka.target.name)
      priority: WARNING
```

### 2. Alert Routing with Falco Sidekick

```yaml
falcoSidekick:
  enabled: true
  
  # Slack integration
  slack:
    webhookurl: "https://hooks.slack.com/services/XXX"
    minimumpriority: "warning"
    
  # PagerDuty integration
  pagerduty:
    integrationkey: "YOUR_KEY"
    minimumpriority: "critical"
    
  # Web UI
  webui:
    enabled: true
    redis:
      storageEnabled: true
```

### 3. Performance Tuning

```yaml
falco:
  # Reduce syscall monitoring overhead
  syscall:
    drop_failed_exit: true  # Ignore failed syscalls
    
  # Buffer settings
  buffered_outputs: true
  outputs_queue:
    capacity: 10000
    
  # Rate limiting
  throttling:
    enabled: true
    rate: 1              # 1 alert/second per rule
    max_burst: 1000
```

## Troubleshooting

### Issue: Falco Pods in CrashLoopBackOff

**Symptoms**: `driver: unable to load kernel module`

**Solution**:
```bash
# Check kernel version
uname -r

# Option 1: Install kernel headers (for module driver)
sudo apt-get install linux-headers-$(uname -r)

# Option 2: Switch to eBPF driver (no headers needed)
helm upgrade falco-security charts/common-security \
  --set falco.driver.kind=ebpf \
  -n falco-system \
  --reuse-values
```

### Issue: No Alerts Generated

**Symptoms**: Falco running but no alerts in logs

**Solution**:
```bash
# Check Falco rule loading
kubectl exec -n falco-system daemonset/falco -- falco --list-rules

# Verify rule syntax
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep -i "error\|warning"

# Test with simple rule
kubectl exec -n falco-system daemonset/falco -- \
  falco -r /etc/falco/falco_rules.yaml --validate
```

### Issue: Too Many False Positives

**Symptoms**: Excessive alerts for normal activity

**Solution**:
```yaml
# Add exceptions to rules
falco:
  customRules:
    exceptions.yaml: |
      - rule: Shell Spawned in Container
        exceptions:
          # Allow shells in debug pods
          - name: debug_pods
            fields: [container.name]
            comps: [=]
            values: [debug, troubleshoot]
```

## Performance Considerations

### 1. Resource Usage per Node

| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| Falco (idle) | 50m | 256Mi | Minimal load |
| Falco (active) | 500m | 512Mi | During alert bursts |
| eBPF driver | 20m | 50Mi | Lower overhead than module |

### 2. Syscall Overhead

```yaml
# Minimize performance impact
falco:
  syscall:
    # Only monitor specific syscalls
    filter:
      - open
      - execve
      - connect
      - write
    
    # Skip monitoring of system namespaces
    exclude_namespaces:
      - kube-system
      - kube-public
```

### 3. Alert Batching

```yaml
falco:
  # Batch alerts to reduce I/O
  outputs:
    stdout:
      enabled: true
      batch:
        enabled: true
        size: 100
        timeout: "5s"
```

## Best Practices

1. **eBPF over Kernel Module**: Use eBPF driver for better compatibility
2. **Start with Default Rules**: Don't over-customize initially
3. **Tune Alert Priority**: Set appropriate priority thresholds
4. **Exception Management**: Maintain allowlist for known-good behavior
5. **Alert Routing**: Use Falco Sidekick for centralized alert management
6. **Regular Updates**: Keep Falco and rule sets updated
7. **Testing**: Test rules in staging before production

## Success Metrics

- **Detection Rate**: >90% of malicious activity detected
- **False Positive Rate**: <5% of alerts are false positives
- **MTTD (Mean Time to Detect)**: <30 seconds from activity to alert
- **Resource Overhead**: <5% node CPU/memory overhead
- **Rule Coverage**: 50+ security rules loaded

## Integration with Incident Response

### SIEM Integration

```yaml
falcoSidekick:
  enabled: true
  
  # Splunk
  splunk:
    hec:
      url: "https://splunk.example.com:8088/services/collector"
      token: "YOUR_TOKEN"
      
  # Elasticsearch
  elasticsearch:
    hostport: "https://elasticsearch:9200"
    index: "falco-alerts"
```

### Automated Response

```yaml
# Example: Delete pod on critical alert
falcoSidekick:
  kubeless:
    enabled: true
    function: "delete-suspicious-pod"
    namespace: "falco-system"
```

## Related Use Cases

- **UC-SECURITY-01**: Trivy Vulnerability Scanning (image CVEs)
- **UC-SECURITY-02**: Secret Detection (static analysis)
- **UC-HARDENING-01**: Network Policies (prevent lateral movement)

## References

- [Falco Documentation](https://falco.org/docs/)
- [Falco Rules](https://github.com/falcosecurity/rules)
- [Falco Sidekick](https://github.com/falcosecurity/falco-sidekick)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)
