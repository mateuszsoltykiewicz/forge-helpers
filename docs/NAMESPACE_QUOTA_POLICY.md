# Namespace Resource Quota Policy

## Quick Reference

### ⭐ Most Common Usage: Override Max Pods

```bash
# 90% of use cases: Just change max pods limit
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment dev \
  --service my-app \
  --max-pods 150  # ⭐ MOST IMPORTANT ARG - always supported
```

### 🎯 All Quota Override Flags

```bash
--max-pods <number>              # ⭐ CRITICAL: Pod limit (most frequently used)
--quota-cpu-request <cores>      # CPU request (e.g., "4", "8")
--quota-cpu-limit <cores>        # CPU limit (e.g., "8", "16")
--quota-memory-request <size>    # Memory request (e.g., "8Gi", "16Gi")
--quota-memory-limit <size>      # Memory limit (e.g., "16Gi", "32Gi")
--quota-pvc <number>             # PVC limit (e.g., "5", "10")
```

---

## Security-First Resource Allocation

### 📊 Resource Quotas by Namespace Type

#### Application & Custom Namespaces

| Namespace Type | PSS Enforce | CPU Req | Memory Req | CPU Limit | Memory Limit | PVCs | Max Pods | Priority |
|----------------|-------------|---------|------------|-----------|--------------|------|----------|----------|
| Application    | restricted  | 4       | 8Gi        | 8         | 16Gi         | **3** | **3**   | 🟢 **Start Small** |
| Middleware     | baseline    | 8       | 16Gi       | 16        | 32Gi         | 10   | 100      | 🔵 High |
| Vault          | privileged  | 4       | 8Gi        | 8         | 16Gi         | 5    | 20       | 🟢 Standard |
| **Privileged** | privileged  | **1**   | **2Gi**    | **2**     | **4Gi**      | **1** | **10**   | 🔴 **MINIMAL** |

#### Infrastructure Namespaces (Kubernetes System)

| Namespace Type | PSS Enforce | CPU Req | Memory Req | CPU Limit | Memory Limit | PVCs | Max Pods | Mode |
|----------------|-------------|---------|------------|-----------|--------------|------|----------|------|
| **default**    | baseline    | **auto** | **auto**   | **auto**  | **auto**     | **0** | **auto** | 🔒 **Lock After Install** |
| **kube-system** | privileged | **auto** | **auto**   | **auto**  | **auto**     | **5** | **auto** | 🔒 **Lock After Install** |

**Legend:**
- **auto** = Calculated from existing workloads after Kubernetes installation
- **Lock After Install** = Quota set to match current usage, preventing additional resources

#### Infrastructure Namespaces (Add-ons)

| Namespace Type | PSS Enforce | CPU Req | Memory Req | CPU Limit | Memory Limit | PVCs | Max Pods | Purpose |
|----------------|-------------|---------|------------|-----------|--------------|------|----------|---------|
| ArgoCD         | privileged  | 2       | 4Gi        | 4         | 8Gi          | 3    | 30       | GitOps controller |
| cert-manager   | baseline    | 2       | 4Gi        | 4         | 8Gi          | 2    | 20       | Certificate mgmt |
| **KEDA**       | baseline    | 2       | 4Gi        | 4         | 8Gi          | 1    | **9**    | **3 deployments × 3 replicas** |
| **Kyverno**    | baseline    | 3       | 6Gi        | 6         | 12Gi         | 1    | **12**   | **4 deployments × 3 replicas** |
| **Monitoring** | baseline    | 8       | 16Gi       | 16        | 32Gi         | 10   | 50       | Prometheus, Grafana stack |

---

## � Why Application Namespaces Start with 3 Pods/PVCs

### The Conservative Default Philosophy

**Traditional thinking:**
> "Give generous defaults so users don't hit limits"

**Resource-conscious thinking (CORRECT):**
> "Start small, scale on demand. Unused quota is wasted cluster capacity."

### Real-World Scenarios

**Scenario 1: Development Namespace (Initial Creation)**
```bash
# Developer creates namespace for new microservice
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment dev \
  --service payment-api

# Result: 3 pods, 3 PVCs
# Reality: Initial deployment = 1 pod, 0 PVCs (just testing)
# Outcome: ✅ No wasted quota, room to grow
```

**Scenario 2: Development Namespace (Scale Up)**
```bash
# Later: Need to run integration tests with multiple replicas
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment dev \
  --service payment-api \
  --max-pods 20  # Easy override when needed

# Result: 20 pods, 3 PVCs
# Reality: Testing with 15 pod replicas
# Outcome: ✅ Scaled on demand, simple CLI override
```

**Scenario 3: Production Namespace**
```bash
# Production: Known requirements
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment prod \
  --service payment-api \
  --max-pods 50 \
  --quota-pvc 10

# Result: 50 pods, 10 PVCs
# Reality: HA deployment = 30 pods, 5 PVCs
# Outcome: ✅ Appropriate headroom
```

### Benefits of Starting Small

1. **Resource Efficiency**: Don't reserve unused cluster capacity
2. **Cost Awareness**: Forces consideration of actual needs
3. **Easy Scaling**: `--max-pods` flag makes growth trivial
4. **Prevents Sprawl**: Discourages "just in case" over-provisioning
5. **Cluster Health**: More namespaces can fit on cluster

### When 3 is Enough

- ✅ Initial development/testing
- ✅ Simple microservices (1 pod deployment)
- ✅ Stateless applications (no PVCs needed)
- ✅ Proof-of-concept projects

### When to Override

- 🔧 Multi-replica deployments (`--max-pods 10+`)
- 🔧 Stateful applications with databases (`--quota-pvc 5+`)
- 🔧 High-availability setups (`--max-pods 20+`)
- 🔧 Horizontal Pod Autoscaler (HPA) enabled (`--max-pods 50+`)

---

## �🔐 Why Privileged Namespaces Get LESS Resources

### The Counter-Intuitive Security Model

**Traditional thinking (WRONG):**
> "Privileged containers need more power, so give them higher resource limits"

**Security-first thinking (CORRECT):**
> "Privileged containers are the highest risk, so minimize their blast radius with strict limits"

### Attack Scenario: Compromised Privileged Container

**Without strict quotas (BAD):**
```
1. Attacker compromises privileged DaemonSet
2. Container has root + host access + 32GB memory limit
3. Attacker spawns cryptominers using all 32 cores
4. Entire cluster becomes unresponsive
5. Production workloads crash due to resource starvation
```

**With strict quotas (GOOD):**
```
1. Attacker compromises privileged DaemonSet  
2. Container has root + host access BUT only 2GB memory limit
3. Attacker tries to spawn cryptominers
4. ResourceQuota blocks additional pods (max 10)
5. Memory limit prevents resource exhaustion
6. Damage contained to single node
7. Alerts fire, incident response begins
```

---

## 🎯 Defense-in-Depth Layers

### Layer 1: Pod Security Standards
- **Privileged PSS** allows dangerous operations (root, host access)
- ❌ Cannot prevent if workload legitimately needs privileges

### Layer 2: Resource Quotas ✅
- **Strict quotas** limit blast radius even with root access
- ✅ Prevents cluster-wide resource exhaustion
- ✅ Contains damage to namespace boundary

### Layer 3: Network Policies ✅
- **Default-deny** prevents lateral movement
- ✅ Blocks exfiltration even from compromised privileged pod

### Layer 4: Audit & Monitoring ✅
- **PSS audit mode** tracks all privileged operations
- ✅ Detects anomalous behavior (spike in CPU, new pods)

---

## 📝 Privileged Namespace Use Cases

### ✅ VALID Use Cases (minimal quotas sufficient)
- **Fluentd/Fluent Bit**: Log collection from host (needs host mount)
- **Node Exporter**: Metrics from host (needs host PID namespace)
- **Falco**: Kernel security monitoring (needs privileged + host)
- **CNI Plugins**: Network setup (Cilium, Calico - needs NET_ADMIN)
- **CSI Drivers**: Storage provisioning (needs privileged mounts)

**Why minimal quotas work:**
- DaemonSets: 1 pod per node (controlled count)
- System agents: lightweight, minimal memory (<500Mi typical)
- No user traffic: just metrics/logs/monitoring

### ❌ INVALID Use Cases (don't use privileged)
- **Databases**: Use application namespace with security contexts
- **Web servers**: Use restricted PSS
- **User applications**: Never needs true privileged mode
- **CI/CD runners**: Use Docker-in-Docker alternatives (Kaniko, Buildah)

---

## 🛠️ Implementation Examples

### Creating Privileged Namespace (Future API)

```bash
./scripts/namespace-create.sh \
  --type privileged \
  --customer sanofi \
  --project infrastructure \
  --environment prod \
  --service node-monitoring \
  --max-pods 15  # ⭐ CRITICAL: Most frequently used override
```

### Common Usage Patterns

```bash
# Pattern 1: Override just max pods (90% of use cases)
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment dev \
  --service my-app \
  --max-pods 100  # Quick pod limit override

# Pattern 2: Privileged namespace with custom pod limit
./scripts/namespace-create.sh \
  --type privileged \
  --customer sanofi \
  --project infrastructure \
  --environment prod \
  --service monitoring \
  --max-pods 20  # Still strict, but slightly higher

# Pattern 3: Full quota override via CLI (no config file needed)
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment prod \
  --service critical \
  --max-pods 200 \
  --quota-cpu-limit 32 \
  --quota-memory-limit 64Gi \
  --quota-pvc 15

# Pattern 4: Config file + max-pods override
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment staging \
  --service test \
  --config-path ./configs/base.yaml \
  --max-pods 75  # Override just pods, keep other config values
```

### CLI Arguments Priority

**Priority Order (highest to lowest):**
1. **CLI arguments** (`--max-pods`, `--quota-*`) ⭐ **HIGHEST**
2. **Config file** (`--config-path`)
3. **Namespace type defaults** (application, middleware, privileged)

```bash
# Example: All three levels
./scripts/namespace-create.sh \
  --type application \              # Default: pods=50
  --config-path ./config.yaml \     # Override: pods=80 (from YAML)
  --max-pods 120                    # Final value: 120 (CLI wins)
```

### Configuration: `privileged-strict.yaml`

```yaml
namespace:
  type: privileged
  
# CRITICAL: Strict quotas for privileged namespaces
resourceQuota:
  hard:
    requests.cpu: "1"          # Minimal CPU request
    requests.memory: "2Gi"     # Minimal memory request
    limits.cpu: "2"            # 2x request (tight ratio)
    limits.memory: "4Gi"       # 2x request (tight ratio)
    persistentvolumeclaims: "1"  # Minimize storage attack surface
    pods: "10"                 # Limit pod count (typically DaemonSets)

limitRange:
  limits:
    - max:
        cpu: "500m"            # Per-container max
        memory: "1Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
      default:
        cpu: "200m"
        memory: "256Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      maxLimitRequestRatio:
        cpu: 2                 # Limit can only be 2x request
        memory: 2
      type: Container

# Still enforce network isolation despite privileged mode
networkPolicies:
  defaultDeny: true
  allowDns: true
  allowSameNamespace: true

# Audit all privileged operations
podSecurity:
  enforce: privileged          # Allow privileged (required)
  audit: privileged            # Track all privileged ops
  warn: privileged             # Warn on violations
```

---

## 📈 Comparison: Application vs Privileged

### Application Namespace (Standard Workload)
```yaml
PSS: restricted               # No root, no host access
CPU Limit: 8 cores            # Can scale up with --quota-cpu-limit
Memory Limit: 16Gi            # Can scale up with --quota-memory-limit
PVCs: 3                       # ⭐ DEFAULT: Start small, use --quota-pvc to increase
Pods: 3                       # ⭐ DEFAULT: Start small, use --max-pods to increase
```

**Philosophy:**
- **Start small**: Conservative defaults prevent resource waste
- **Scale on demand**: Use `--max-pods` and `--quota-pvc` when needed
- **Lower risk**: No host access, no root privileges
- **Flexibility**: Easy to override via CLI arguments

**Common Override:**
```bash
# Most applications need more than 3 pods
./scripts/namespace-create.sh \
  --customer sanofi \
  --project cronus \
  --environment dev \
  --service my-app \
  --max-pods 50 \      # Scale to 50 pods
  --quota-pvc 10       # Allow 10 PVCs
```

### Privileged Namespace (System Agents)
```yaml
PSS: privileged               # ⚠️ ROOT + HOST ACCESS + CAPABILITIES
CPU Limit: 2 cores            # ⚠️ STRICT LIMIT
Memory Limit: 4Gi             # ⚠️ STRICT LIMIT  
PVCs: 1                       # ⚠️ MINIMAL STORAGE
Pods: 10                      # ⚠️ CONTROLLED COUNT
```

**Threat Model:**
- Higher risk: Full host compromise possible
- Lower capacity: Just enough for system tasks
- No scaling: DaemonSets don't scale horizontally

---

## 🚨 Alert Thresholds

### Privileged Namespace Alerts

```yaml
# Alert if privileged namespace approaches quota
- alert: PrivilegedNamespaceHighCPU
  expr: |
    namespace:container_cpu_usage:sum{namespace=~".*-privileged.*"} 
    / 
    kube_resourcequota{resource="limits.cpu", namespace=~".*-privileged.*"}
    > 0.8
  labels:
    severity: warning
  annotations:
    summary: "Privileged namespace {{ $labels.namespace }} using 80% of CPU quota"

- alert: PrivilegedNamespaceHighMemory
  expr: |
    namespace:container_memory_usage:sum{namespace=~".*-privileged.*"}
    /
    kube_resourcequota{resource="limits.memory", namespace=~".*-privileged.*"}
    > 0.8
  labels:
    severity: warning

- alert: PrivilegedNamespaceUnexpectedPods
  expr: |
    count(kube_pod_info{namespace=~".*-privileged.*"}) > 10
  labels:
    severity: critical
  annotations:
    summary: "Privileged namespace has more than 10 pods (potential compromise)"
```

---

## ✅ Policy Summary

### Golden Rules for Privileged Namespaces

1. **Minimize Resources** - Give only what's needed for system tasks
2. **Maximize Auditing** - Log every privileged operation
3. **Isolate Network** - Default-deny policies still apply
4. **Limit Scope** - Only for DaemonSets and system agents
5. **Monitor Strictly** - Alert on unusual resource usage
6. **Manual Approval** - Require review before creation

### Resource Allocation Philosophy

```
Security Risk ∝ Resource Limits (INVERSE)

High Privileges = Low Resource Quotas
Low Privileges  = High Resource Quotas
```

**The more dangerous the workload, the more we constrain its resources.**

---

**Last Updated**: 2026-02-11  
**Status**: Policy Active  
**Review Cycle**: Quarterly
