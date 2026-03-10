# Forge Common Library - common-hardening

Capacity-based namespace hardening library for ResourceQuotas and NetworkPolicies. Enables **IMMEDIATE** hardening after deployment by measuring declared maximums instead of runtime usage.

## Overview

`common-hardening` provides production-ready templates for namespace security hardening, following the philosophy from `namespace-hardening.sh`: measure **CAPACITY** (what COULD be used), not **USAGE** (what IS used now).

### Key Philosophy

**Why No Waiting Period?**

Traditional resource quota approaches wait for workloads to "settle" and then measure usage. This library takes a different approach:

- **HPA maxReplicas=10** is declared in manifest (static config, doesn't change with traffic)
- **VPA upperBound=600m** is already calculated from 7+ days historical data (pre-existing)
- **Max nodes=100** is defined in Karpenter/ASG config (infrastructure limit, not runtime metric)
- **Pod limits=500m** are static values in deployment manifests

**None of these values change based on current runtime!** Current usage (3 replicas, 200m CPU, 6 nodes) is **IGNORED**.

### Key Features

- **Capacity-Based ResourceQuotas**: Measure declared maximums, not current usage
- **NetworkPolicy by Namespace Type**: 6 pre-configured policy sets
- **Automatic Calculation**: From workload configurations (HPA, VPA, PDB, DaemonSets)
- **Immediate Hardening**: Run right after `helm install` (no grace period)
- **Buffer Configuration**: Configurable headroom (default: 20%)
- **VPA Integration**: Use upperBound recommendations (with minimum age requirement)
- **PDB Awareness**: Extra pod capacity for disruption budgets

## Installation

### As Dependency

Add to your `Chart.yaml`:

```yaml
dependencies:
  - name: common-hardening
    version: ~0.1.0
    repository: file://../common-hardening
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
```

Then run:

```bash
helm dependency update
```

## Usage

### Basic ResourceQuota (Manual Values)

```yaml
# values.yaml
resourceQuota:
  enabled: true
  bufferPercent: 20
  
  cpu:
    limits: "5000m"    # Measured from: 10 pods × 500m per pod
  memory:
    limits: "16Gi"     # Measured from: 10 pods × 1.6Gi per pod
  pods: 12             # Measured from: HPA maxReplicas=10 + PDB minAvailable=2

networkPolicy:
  enabled: true
  namespaceType: "application"
```

```helm
{{/* templates/hardening.yaml */}}
{{- include "hardening.resourcequota" . }}
{{- include "hardening.networkpolicy" . }}
```

### Automatic Calculation from Workloads

```yaml
# values.yaml
resourceQuota:
  enabled: true
  bufferPercent: 20
  minVpaAgeDays: 7

workloads:
  # API Deployment with HPA and VPA
  - name: api
    type: Deployment
    replicas: 3
    cpuLimit: "500m"
    memoryLimit: "512Mi"
    hpa:
      enabled: true
      maxReplicas: 10
    vpa:
      enabled: true
      upperBound: "600m"
      memoryUpperBound: "600Mi"
      ageDays: 14
    pdb:
      enabled: true
      minAvailable: 2
  
  # Worker with KEDA
  - name: worker
    type: Deployment
    replicas: 2
    cpuLimit: "1000m"
    memoryLimit: "1Gi"
    keda:
      enabled: true
      maxReplicas: 20
  
  # Database StatefulSet
  - name: database
    type: StatefulSet
    replicas: 3
    cpuLimit: "2000m"
    memoryLimit: "4Gi"
    pvcCount: 1
  
  # Logger DaemonSet
  - name: logger
    type: DaemonSet
    cpuLimit: "100m"
    memoryLimit: "128Mi"

maxNodes: 100  # For DaemonSet capacity calculation

networkPolicy:
  enabled: true
  namespaceType: "application"
```

```helm
{{/* templates/hardening.yaml */}}
{{- $cpu := include "hardening.calculateCpuQuota" (dict "context" . "workloads" .Values.workloads "bufferPercent" .Values.resourceQuota.bufferPercent "minVpaAgeDays" .Values.resourceQuota.minVpaAgeDays) }}
{{- $memory := include "hardening.calculateMemoryQuota" (dict "context" . "workloads" .Values.workloads "bufferPercent" .Values.resourceQuota.bufferPercent "minVpaAgeDays" .Values.resourceQuota.minVpaAgeDays) }}
{{- $pods := include "hardening.calculatePodQuota" (dict "workloads" .Values.workloads "maxNodes" .Values.maxNodes) }}

{{- $_ := set .Values.resourceQuota.cpu "limits" $cpu }}
{{- $_ := set .Values.resourceQuota.memory "limits" $memory }}
{{- $_ := set .Values "resourceQuota" (merge .Values.resourceQuota (dict "pods" ($pods | int))) }}

{{- include "hardening.resourcequota" . }}
{{- include "hardening.networkpolicy" . }}
```

**Calculation Example (API workload)**:
1. VPA upperBound=600m (14 days old, meets minimum) → Use VPA
2. HPA maxReplicas=10 → Pod count = 10
3. PDB minAvailable=2 (not >= 10) → No extra pod
4. Total: 10 pods × 600m = 6000m
5. Buffer 20%: 6000m × 1.20 = 7200m

**Final Quota** (all workloads):
- API: 7200m
- Worker: 20 × 1000m × 1.20 = 24000m
- Database: 3 × 2000m × 1.20 = 7200m
- Logger: 100 nodes × 100m × 1.20 = 12000m
- **Total CPU**: 50400m (50.4 cores)

### NetworkPolicy by Namespace Type

#### Application Namespace (Default)

```yaml
networkPolicy:
  enabled: true
  namespaceType: "application"
  allowInternalTraffic: true
```

Policies:
- ❌ Deny all ingress (must be explicitly allowed via Ingress)
- ✅ Allow egress to DNS (kube-system)
- ✅ Allow egress to HTTPS (port 443, all namespaces)
- ✅ Allow internal traffic (pod-to-pod in same namespace)

#### Middleware Namespace

```yaml
networkPolicy:
  enabled: true
  namespaceType: "middleware"
```

Policies:
- ❌ Deny all ingress by default
- ✅ Allow ingress from application namespaces (labeled `moai.forge.io/type=application`)
- ✅ Allow ingress from forge-jobs namespaces
- ✅ Allow egress to DNS
- ✅ Allow internal traffic (for clustering)

#### Forge Operator Namespace

```yaml
networkPolicy:
  enabled: true
  namespaceType: "forge-operator"
```

Policies:
- ❌ Deny all ingress
- ✅ Allow egress to Kubernetes API server (port 443)
- ✅ Allow egress to DNS
- ✅ Allow egress to all namespaces (for resource management)

#### Admin Namespace

```yaml
networkPolicy:
  enabled: true
  namespaceType: "admin"
```

Policies:
- ❌ Deny ingress from non-admin namespaces
- ✅ Allow internal traffic (for dashboards)
- ✅ Allow all egress (admin tools need full access)

#### Platform Namespace

```yaml
networkPolicy:
  enabled: true
  namespaceType: "platform"
```

Policies:
- ✅ Allow ingress from all namespaces (for metrics, logs collection)
- ✅ Allow egress to DNS
- ✅ Allow egress to HTTPS (for external alerting, storage)

## Templates Reference

### `hardening.resourcequota`

Main ResourceQuota template with capacity-based limits.

**Configuration**:
```yaml
resourceQuota:
  enabled: true
  bufferPercent: 20
  minVpaAgeDays: 7
  cpu:
    limits: "10000m"
  memory:
    limits: "32Gi"
  pods: 50
  persistentvolumeclaims: 10
```

### `hardening.networkpolicy`

NetworkPolicy template with type-specific policy sets.

**Supported Types**:
- `application` - User applications (default)
- `middleware` - Databases, message queues, caches
- `forge-jobs` - Batch jobs (same as application)
- `forge-operator` - Kubernetes operators/controllers
- `admin` - Administrative tools
- `platform` - Monitoring, logging, service mesh

### Calculation Helpers

#### `hardening.calculateCpuQuota`

Calculates CPU quota from workload configurations.

**Precedence** (per workload):
1. Goldilocks VPA recommendation (if available)
2. VPA upperBound (if age >= minVpaAgeDays)
3. HPA maxReplicas × pod limits
4. Static replicas × pod limits

**PDB Handling**: Adds 1 extra pod if `pdb.minAvailable >= podCount`

#### `hardening.calculateMemoryQuota`

Calculates memory quota from workload configurations. Same precedence as CPU.

#### `hardening.calculatePodQuota`

Calculates maximum pod count:
- **Deployments/StatefulSets**: HPA maxReplicas (or static replicas)
- **DaemonSets**: maxNodes (from Karpenter/ASG/ConfigMap)
- **PDB**: +1 pod if minAvailable >= current pod count

### Conversion Helpers

- `hardening.cpuToMillicores` - Convert CPU to millicores ("500m" → 500, "2" → 2000)
- `hardening.memoryToBytes` - Convert memory to bytes ("512Mi" → 536870912)
- `hardening.bytesToHumanMemory` - Convert bytes to human format (536870912 → "512Mi")

## Measurement Sources

### Priority Order (per workload)

1. **Goldilocks VPA** (TODO: Not yet implemented)
   - Historical recommendations from Goldilocks dashboard
   - Pre-calculated, requires Goldilocks operator

2. **VPA upperBound**
   - P99 + headroom from 7+ days of historical data
   - Requires VPA age >= `minVpaAgeDays` (default: 7)
   - Already calculated, no waiting needed

3. **HPA maxReplicas**
   - Declared maximum scale in HPA manifest
   - Static configuration value
   - Takes precedence over static replicas

4. **Pod Limits**
   - From deployment/statefulset manifest
   - Fallback if no VPA/HPA

### DaemonSet Capacity

```
DaemonSet capacity = max_nodes × pod_limits × buffer
```

**Max nodes from**:
1. Karpenter NodePool (`.spec.limits.nodes`)
2. Cloud provider API (ASG max size)
3. ConfigMap (`karpenter-config`, `cluster-config`)
4. Fallback: 100 nodes

## Workflow

### Standard Deployment with Immediate Hardening

```bash
# 1. Deploy application
helm install my-app ./chart -n my-app --create-namespace

# 2. Harden IMMEDIATELY (no waiting!)
./scripts/namespace-hardening.sh --name my-app

# 3. Verify compliance
kubectl get resourcequota -n my-app
kubectl get networkpolicy -n my-app
```

### Using Helm Chart Directly

```yaml
# Chart.yaml
dependencies:
  - name: common-hardening
    version: ~0.1.0

# values.yaml
resourceQuota:
  enabled: true
  cpu:
    limits: "10000m"
  memory:
    limits: "32Gi"
  pods: 50

networkPolicy:
  enabled: true
  namespaceType: "application"
```

### With Automatic Calculation

```yaml
# values.yaml
workloads:
  - name: api
    type: Deployment
    replicas: 3
    cpuLimit: "500m"
    memoryLimit: "512Mi"
    hpa:
      enabled: true
      maxReplicas: 10

# templates/hardening.yaml
{{- $cpu := include "hardening.calculateCpuQuota" (dict "context" . "workloads" .Values.workloads "bufferPercent" 20) }}
{{- $_ := set .Values.resourceQuota.cpu "limits" $cpu }}
{{- include "hardening.resourcequota" . }}
```

## Best Practices

### Buffer Configuration

- **Production**: 20-30% (default: 20%)
- **High variability workloads**: 40-50%
- **Stable workloads**: 15-20%
- **Cost-sensitive environments**: 10-15% (monitor closely)

### VPA Age Requirements

- **Standard**: 7 days (default)
- **Conservative**: 14 days (more stable, less responsive)
- **Aggressive**: 3 days (faster response, less reliable)

### Namespace Type Selection

| Type | Use Case | Ingress | Egress |
|------|----------|---------|--------|
| application | User apps, APIs | Deny all | DNS, HTTPS |
| middleware | Databases, caches | From apps only | DNS, internal |
| forge-jobs | Batch processing | Deny all | DNS, HTTPS, apps |
| forge-operator | Controllers | Deny all | API server, all NS |
| admin | Admin tools | Internal only | All |
| platform | Monitoring, logging | From all | DNS, HTTPS |

### Manual vs Automatic Calculation

**Manual** (simple, predictable):
```yaml
resourceQuota:
  cpu:
    limits: "10000m"
```

**Automatic** (dynamic, follows workloads):
```yaml
workloads:
  - name: api
    hpa:
      maxReplicas: 10
```

Use **manual** for:
- Simple applications (1-2 workloads)
- Known, fixed requirements
- CI/CD pipelines (predictable)

Use **automatic** for:
- Complex applications (3+ workloads)
- Dynamic scaling (HPA, KEDA, VPA)
- Mixed workload types (Deployment + StatefulSet + DaemonSet)

## Integration with namespace-hardening.sh

This library implements the same philosophy as `scripts/namespace-hardening.sh`:

```bash
# Shell script (full automation)
./namespace-hardening.sh --name my-app --buffer-percent 20

# Helm library (declarative)
{{- include "hardening.resourcequota" . }}
```

Both approaches:
- Measure **CAPACITY**, not usage
- Support immediate hardening
- Use same precedence rules (VPA → HPA → limits)
- Apply same buffer calculation
- Generate same ResourceQuota format

## See Also

- **scripts/namespace-hardening.sh** - Full implementation with automatic measurement
- **lib/forge-namespace-hardening.sh** - Core measurement algorithms
- **docs/WHY_NO_WAITING.md** - Philosophy explanation
- **docs/NAMESPACE_OPERATIONS_V2.md** - Architecture decisions

## License

Copyright © 2024 MOAI Forge Platform. All rights reserved.

## Version

- **Chart Version**: 0.1.0
- **App Version**: 1.0

## Dependencies

- `common-forge` ~0.1.0 (naming, validation, labels)
