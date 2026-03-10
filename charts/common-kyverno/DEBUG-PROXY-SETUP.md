# Debug Proxy Setup Guide

Complete guide to set up controlled pod access via debug proxy mechanism.

## 📋 Overview

Instead of allowing users direct `kubectl exec` access, this solution:

1. **Blocks** all direct pod access (kubectl exec, attach, port-forward)
2. **Allows** access only via debug proxy jobs/pods
3. **Audits** all access attempts with user, reason, and timestamp
4. **Controls** who can create debug jobs via RBAC

## 🏗️ Architecture

```
┌─────────┐     kubectl exec    ┌──────────────┐
│  User   │ ───────X────────────│  Target Pod  │  BLOCKED ❌
└─────────┘                     └──────────────┘
     │
     │  create debug job
     ▼
┌─────────────────┐
│  Debug Job      │  ServiceAccount: debug-proxy
│  (Proxy Layer)  │  RBAC: pods/exec allowed
└─────────────────┘
     │
     │  kubectl exec (via ServiceAccount)
     ▼
┌──────────────┐
│  Target Pod  │  ALLOWED ✅
└──────────────┘
```

## 🚀 Quick Setup (5 minutes)

### Step 1: Install Kyverno Policies

```bash
# Add to your values.yaml
cat <<EOF > api-restrictions-values.yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
      excludeServiceAccounts:
        - system:serviceaccount:kube-system:debug-proxy
    blockAttach:
      enabled: true
      action: enforce
      excludeServiceAccounts:
        - system:serviceaccount:kube-system:debug-proxy
    blockPortForward:
      enabled: true
      action: enforce
      excludeServiceAccounts:
        - system:serviceaccount:kube-system:debug-proxy
EOF

# Apply policies
helm upgrade kyverno-policies . -f api-restrictions-values.yaml
```

### Step 2: Create Debug Proxy RBAC

```bash
kubectl apply -f - <<EOF
---
# ServiceAccount for debug proxy
apiVersion: v1
kind: ServiceAccount
metadata:
  name: debug-proxy
  namespace: kube-system

---
# ClusterRole: Allow pods/exec
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: debug-proxy-exec
rules:
  - apiGroups: [""]
    resources: ["pods/exec", "pods/log"]
    verbs: ["create", "get"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]

---
# Bind ClusterRole to ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: debug-proxy-exec
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: debug-proxy-exec
subjects:
  - kind: ServiceAccount
    name: debug-proxy
    namespace: kube-system

---
# ClusterRole: Who can create debug jobs
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: debug-job-creator
rules:
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get", "list", "delete"]
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list"]

---
# Grant to SRE team
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sre-debug-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: debug-job-creator
subjects:
  - kind: Group
    name: sre-team  # Your OIDC/LDAP group
    apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 3: Copy Helper Scripts

```bash
# Copy scripts to your PATH
cp examples/create-debug-job.sh /usr/local/bin/debug-pod
cp examples/create-debug-session.sh /usr/local/bin/debug-session
chmod +x /usr/local/bin/debug-pod /usr/local/bin/debug-session
```

## 📘 Usage

### Option 1: One-off Command (Quick Debug)

Execute a single command and exit:

```bash
# Basic usage
debug-pod production myapp-abc123 "ps aux"

# Multiple commands
debug-pod production myapp-abc123 "ps aux; df -h; netstat -tulpn"

# Get environment variables
debug-pod production myapp-abc123 "env | sort"

# Check filesystem
debug-pod production myapp-abc123 "ls -la /app"
```

The script will:
1. Prompt for reason and incident ticket
2. Create a Job with the debug-proxy ServiceAccount
3. Execute the command in the target pod
4. Stream logs to your terminal
5. Auto-delete after 1 hour

### Option 2: Interactive Session (Long Debug)

For debugging that requires multiple commands:

```bash
# Start interactive session
debug-session production

# Inside the session, you can:
kubectl get pods -n production
kubectl exec -n production myapp-abc123 -- /bin/sh
kubectl logs -n production myapp-abc123
kubectl describe pod -n production myapp-abc123

# Exit when done
exit
```

The session:
- Runs for 30 minutes (auto-terminates)
- Provides full kubectl access to target namespace
- All commands are audited via ServiceAccount

## 🔒 Security Features

### 1. Full Audit Trail

Every debug job records:
- **Who**: User email/username
- **When**: Timestamp
- **What**: Target pod and command
- **Why**: Required reason field
- **Incident**: Optional ticket number

View audit logs:
```bash
kubectl get jobs -n kube-system -l app.kubernetes.io/name=debug-proxy-job
kubectl describe job debug-myapp-20260221 -n kube-system
```

### 2. Time-Limited Access

- Jobs: Auto-delete after 1 hour (configurable)
- Sessions: Auto-terminate after 30 minutes
- ActiveDeadlineSeconds: Hard limit on execution time

### 3. RBAC-Controlled

Control who can create debug jobs:

```yaml
# Grant access to specific users
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: alice-debug-access
subjects:
  - kind: User
    name: alice@company.com
roleRef:
  kind: ClusterRole
  name: debug-job-creator
```

### 4. Non-Privileged Containers

Debug containers run with:
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- Dropped capabilities

## 📊 Monitoring

### Prometheus Metrics

```promql
# Count of debug jobs created
sum(kube_job_created{job=~"debug-.*"})

# Debug job creation rate
rate(kube_job_created{job=~"debug-.*"}[1h])

# Failed debug jobs
kube_job_failed{job=~"debug-.*"}
```

### Alerts

```yaml
groups:
  - name: debug-proxy
    rules:
      - alert: HighDebugJobUsage
        expr: rate(kube_job_created{job=~"debug-.*"}[1h]) > 10
        for: 5m
        annotations:
          summary: High number of debug jobs created
          description: "{{ $value }} jobs/hour"
      
      - alert: DebugJobStuck
        expr: |
          time() - kube_job_status_start_time{job=~"debug-.*"}
          > 600
        annotations:
          summary: Debug job running longer than 10 minutes
```

### Audit Log Export

Export to SIEM:

```bash
# Get all debug jobs with metadata
kubectl get jobs -n kube-system \
  -l app.kubernetes.io/name=debug-proxy-job \
  -o json | jq -r '.items[] | {
    name: .metadata.name,
    user: .metadata.labels["debug.forge.io/created-by"],
    target: .metadata.labels["debug.forge.io/target-pod"],
    reason: .metadata.annotations["debug.forge.io/reason"],
    incident: .metadata.annotations["debug.forge.io/incident"],
    time: .metadata.creationTimestamp
  }'
```

## 🔧 Advanced Configuration

### Custom Timeout

```bash
# 5-minute timeout
DEBUG_TIMEOUT=300 debug-session production

# 10-minute job timeout
DEBUG_TTL=600 debug-pod production myapp-abc123 "sleep 300"
```

### Custom Debug Image

```bash
# Use custom image with tools
DEBUG_IMAGE=myregistry.io/debug-tools:latest \
  debug-pod production myapp-abc123 "custom-tool"
```

### Namespace-Specific Access

Grant access only to specific namespaces:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-team-debug-access
  namespace: production
subjects:
  - kind: Group
    name: dev-team
roleRef:
  kind: ClusterRole
  name: debug-job-creator
```

## 🚨 Break-Glass Procedure

In emergencies, temporarily allow direct access:

```bash
# Disable enforcement (switch to audit mode)
kubectl patch clusterpolicy block-pod-exec \
  -p '{"spec":{"validationFailureAction":"audit"}}'

# Perform emergency maintenance
kubectl exec -it emergency-pod -- /bin/sh

# Re-enable enforcement
kubectl patch clusterpolicy block-pod-exec \
  -p '{"spec":{"validationFailureAction":"enforce"}}'

# Document in incident report
```

## 📝 Compliance

This solution helps with:

- **SOC2 CC6.1**: Audit trail of all pod access
- **ISO 27001 A.9.2**: Access control and authentication
- **PCI-DSS 10.2**: Automated audit trails
- **HIPAA 164.308(a)(4)**: Access management

All access is logged with:
- User identity
- Timestamp
- Target resource
- Business justification

## 🔍 Troubleshooting

### "admission webhook denied the request"

**Problem**: Kyverno policy is blocking you

**Solution**: Check if you're using the debug proxy:
```bash
# ❌ This is blocked
kubectl exec -it myapp-pod -- /bin/sh

# ✅ This works
debug-pod default myapp-pod "/bin/sh"
```

### "serviceaccount debug-proxy not found"

**Problem**: RBAC not set up

**Solution**: Run Step 2 again

### "Error from server (Forbidden)"

**Problem**: Your user can't create debug jobs

**Solution**: Ask admin to grant you the debug-job-creator role

## 🎓 Training Users

Share this quick reference with your team:

```bash
# OLD WAY (blocked):
kubectl exec -it myapp-pod -- /bin/sh

# NEW WAY:
debug-pod production myapp-pod "/bin/sh"

# Interactive session:
debug-session production
```

## 📚 Additional Resources

- Kyverno API Restrictions: `../README.md#api-restrictions`
- Full architecture: `debug-proxy-architecture.yaml`
- Script source: `create-debug-job.sh`, `create-debug-session.sh`

---

**Questions?** Contact Platform Engineering team
