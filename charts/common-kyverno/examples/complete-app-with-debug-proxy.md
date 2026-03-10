# Complete Application Chart with Debug Proxy

This example shows how to integrate debug proxy into your application chart.

## Directory Structure

```
myapp/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
    security-policies.yaml  # <- Add this
    debug-proxy.yaml        # <- Add this
```

---

## Chart.yaml

```yaml
apiVersion: v2
name: myapp
description: My Application with Debug Proxy
version: 1.0.0
appVersion: "1.0.0"

dependencies:
  # Common Kyverno library (provides API restrictions + debug proxy)
  - name: common-kyverno
    version: ~0.1.0
    repository: file://../common-kyverno
  
  # Common Forge library (provides naming helpers)
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
```

---

## values.yaml

```yaml
# Application configuration
app:
  name: myapp
  replicas: 3

# Kyverno API Restrictions
kyverno:
  apiRestrictions:
    # Block kubectl exec for all users
    blockExec:
      enabled: true
      action: enforce  # enforce in production, audit in dev
      severity: high
      
      # IMPORTANT: Exclude debug-proxy ServiceAccount
      excludeServiceAccounts:
        - system:serviceaccount:default:myapp-debug-proxy
      
      # Exclude cluster admins (break-glass)
      excludeUsers:
        - cluster-admin
      
      # Custom message for users
      message: |
        ⛔ Direct kubectl exec is not allowed.
        
        Use the debug proxy instead:
          debug-pod default myapp-pod-name "command"
        
        Or for interactive session:
          debug-session default
        
        Documentation: https://wiki.company.com/debug-proxy
    
    # Block kubectl attach
    blockAttach:
      enabled: true
      action: enforce
      excludeServiceAccounts:
        - system:serviceaccount:default:myapp-debug-proxy
    
    # Block kubectl port-forward
    blockPortForward:
      enabled: true
      action: enforce
      excludeServiceAccounts:
        - system:serviceaccount:default:myapp-debug-proxy
    
    # Block kubectl debug (ephemeral containers)
    blockEphemeralContainers:
      enabled: true
      action: enforce
      excludeServiceAccounts:
        - system:serviceaccount:default:myapp-debug-proxy
  
  # Debug Proxy configuration
  debugProxy:
  # Debug Proxy configuration
  debugProxy:
    # Enable debug proxy for this app
    enabled: true
    
    # ServiceAccount name (namespaced to this app)
    serviceAccountName: "myapp-debug-proxy"
    
    # Allow users to create debug jobs
    allowJobCreation: true
    
    # Who can create debug jobs for this app
    allowedGroups:
      - sre-team
      - myapp-developers
    
    allowedUsers:
      - oncall-engineer@company.com
    
    # Optional: Allow specific operations
    allowAttach: false
    allowPortForward: false
```

---

## templates/security-policies.yaml

This file applies Kyverno API restrictions.

```yaml
---
# Include all API restriction policies
{{- include "kyverno.apiRestrictions.blockAll" . }}
```

---

## templates/debug-proxy.yaml

This file deploys the debug proxy infrastructure.

```yaml
---
# Include all debug proxy resources
{{- include "debugProxy.all" . }}
```

---

## Deployment Instructions

### 1. Add dependencies

```bash
helm dependency update
```

### 2. Deploy with debug proxy enabled (production)

```bash
helm upgrade myapp . --install \
  --namespace production \
  --set kyverno.apiRestrictions.blockExec.action=enforce \
  --set kyverno.debugProxy.enabled=true
```

### 3. Deploy with audit mode (staging)

```bash
helm upgrade myapp . --install \
  --namespace staging \
  --set kyverno.apiRestrictions.blockExec.action=audit \
  --set kyverno.debugProxy.enabled=true
```

### 4. Test blocking

```bash
kubectl exec -it myapp-pod-abc123 -n production -- /bin/sh
# Expected: Error from server: admission webhook denied
```

### 5. Test debug proxy

```bash
debug-pod production myapp-pod-abc123 "/bin/sh"
# Expected: Interactive shell via proxy job
```

---

## Per-Environment Configuration

### Development (values-dev.yaml)

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      action: audit  # Log only, don't block
  debugProxy:
    enabled: false  # Not needed in dev
```

### Staging (values-staging.yaml)

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      action: audit  # Monitor before enforcing
  debugProxy:
    enabled: true
    allowedGroups:
      - developers
```

### Production (values-production.yaml)

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      action: enforce  # Strict enforcement
  debugProxy:
    enabled: true
    allowedGroups:
      - sre-team
    allowedUsers:
    allowedUsers:
      - oncall-engineer@company.com
```

---

## Testing the Setup

### Test 1: Verify policies are active

```bash
kubectl get clusterpolicy
# Should see: block-pod-exec, block-pod-attach, etc.
```

### Test 2: Verify debug proxy RBAC

```bash
kubectl get sa myapp-debug-proxy -n production
kubectl get clusterrole myapp-debug-proxy
kubectl get clusterrolebinding myapp-debug-proxy
```

### Test 3: Try direct exec (should fail)

```bash
kubectl exec -it $(kubectl get pod -n production -l app=myapp -o name | head -1) -n production -- /bin/sh
# Expected: Error from server: admission webhook "validate.kyverno.svc" denied
```

### Test 4: Try debug proxy (should work)

```bash
POD_NAME=$(kubectl get pod -n production -l app=myapp -o jsonpath='{.items[0].metadata.name}')
debug-pod production $POD_NAME "hostname; whoami; ps aux"
# Expected: Output from commands
```

### Test 5: Verify audit trail

```bash
kubectl get jobs -n production -l app.kubernetes.io/name=debug-proxy-job
kubectl describe job debug-myapp-xyz -n production
# Should see: user, reason, target pod annotations
```

---

## Monitoring and Alerts

### Prometheus Alerts (alerts.yaml)

```yaml
groups:
  - name: debug-proxy
    rules:
      # Alert on blocked exec attempts
      - alert: BlockedKubectlExec
        expr: |
          increase(kyverno_policy_results_total{
            policy_name="block-pod-exec",
            status="fail"
          }[5m]) > 5
        for: 5m
        annotations:
          summary: "Multiple kubectl exec attempts blocked"
          description: "{{ $value }} blocked attempts in 5 minutes"
      
      # Alert on high debug job usage
      - alert: HighDebugJobUsage
        expr: |
          count(kube_job_info{
            job_name=~"debug-.*"
          }) > 10
        annotations:
          summary: "High number of debug jobs"
          description: "{{ $value }} active debug jobs"
```

### Grafana Dashboard Queries

**Panel 1: Blocked Exec Attempts**

```promql
sum(rate(kyverno_policy_results_total{policy_name="block-pod-exec",status="fail"}[5m]))
```

**Panel 2: Debug Jobs Created**

```promql
sum(kube_job_created{job=~"debug-.*"})
```

**Panel 3: Active Debug Sessions**

```promql
count(kube_pod_info{pod=~"debug-session-.*",phase="Running"})
```

---

## Compliance Reports

### Generate monthly report of debug access (JSON)

```bash
kubectl get jobs -n production \
  -l app.kubernetes.io/name=debug-proxy-job \
  -o json | jq -r '
    .items[] | {
      date: .metadata.creationTimestamp,
      user: .metadata.labels["debug.forge.io/created-by"],
      target: .metadata.labels["debug.forge.io/target-pod"],
      reason: .metadata.annotations["debug.forge.io/reason"],
      incident: .metadata.annotations["debug.forge.io/incident"]
    }
  ' | jq -s '.' > debug-access-report-$(date +%Y-%m).json
```

### Export to CSV for audit

```bash
kubectl get jobs -n production \
  -l app.kubernetes.io/name=debug-proxy-job \
  -o custom-columns=\
DATE:.metadata.creationTimestamp,\
USER:.metadata.labels.debug\.forge\.io/created-by,\
TARGET:.metadata.labels.debug\.forge\.io/target-pod,\
REASON:.metadata.annotations.debug\.forge\.io/reason,\
INCIDENT:.metadata.annotations.debug\.forge\.io/incident \
  --no-headers > debug-access-report.csv
```

---

## Best Practices

### 1. Start with audit mode

- Deploy with `action: audit`
- Monitor for 2-4 weeks
- Identify patterns and legitimate use cases

### 2. Educate users

- Provide debug-pod and debug-session scripts
- Document alternatives (logs, Telepresence)
- Share success stories

### 3. Gradual enforcement

- Enforce in staging first
- Monitor for issues
- Then enforce in production

### 4. Regular reviews

- Review debug job usage monthly
- Adjust allowed users/groups
- Update documentation

### 5. Incident response

- Document break-glass procedure
- Test emergency access quarterly
- Keep audit trail

---

## Troubleshooting

### Problem: Policy not working

```bash
kubectl get clusterpolicy block-pod-exec -o yaml
kubectl describe clusterpolicy block-pod-exec
```

### Problem: Debug proxy not working

```bash
kubectl get sa myapp-debug-proxy -n production
kubectl auth can-i create pods/exec --as=system:serviceaccount:production:myapp-debug-proxy
```

### Problem: Users can't create debug jobs

```bash
kubectl auth can-i create jobs --as=user@company.com -n production
```

### Problem: Debug job fails

```bash
kubectl logs job/debug-myapp-xyz -n production
kubectl describe job debug-myapp-xyz -n production
```