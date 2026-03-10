# Forge Helpers - Chart Dependencies Map

## Dependency Graph

```
                          ┌─────────────────┐
                          │  common-forge   │
                          │   (Base Layer)  │
                          └────────┬────────┘
                                   │
                   ┌───────────────┼───────────────┬─────────────┬──────────────┐
                   │               │               │             │              │
          ┌────────▼────────┐ ┌───▼───────────┐ ┌─▼──────────┐ ┌▼────────────┐ │
          │ common-kyverno  │ │common-monitor │ │common-sec  │ │common-hard  │ │
          │ (Policy/GitOps) │ │(Observability)│ │(Scanning)  │ │(Networking) │ │
          └─────────────────┘ └───────────────┘ └────────────┘ └─────────────┘ │
                   │                                                             │
          ┌────────▼────────┐ ┌─────────────┐   ┌─────────────┐  ┌────────────▼────────┐
          │ common-aws      │ │common-argocd│   │common-vault │  │ common-kubernetes   │
          │ (AWS Resources) │ │(GitOps Apps)│   │(Secrets)    │  │ (K8s Resources)     │
          └─────────────────┘ └─────────────┘   └──────┬──────┘  └──────────┬──────────┘
                                                        │                     │
                                                   ┌────▼─────┐              │
                                                   │common-   │◄─────────────┘
                                                   │keda      │
                                                   │(Scaling) │
                                                   └──────────┘

                          ┌─────────────────┐
                          │ common-library  │
                          │  (DEPRECATED)   │  ⚠️  NO DEPENDENCIES
                          └─────────────────┘
```

## Dependency Matrix

| Chart | Depends On | Used By | Layer |
|-------|-----------|---------|-------|
| **common-forge** | - (base) | ALL (9 charts) | Base |
| **common-kubernetes** | common-forge, common-vault | common-aws, common-argocd | Core |
| **common-vault** | common-forge | common-kubernetes, common-keda | Core |
| **common-kyverno** | common-forge | - | Security |
| **common-monitoring** | common-forge | - | Observability |
| **common-security** | common-forge | - | Security |
| **common-hardening** | common-forge | - | Security |
| **common-keda** | common-forge, common-vault | - | Autoscaling |
| **common-aws** | common-forge, common-kubernetes | - | Cloud Integration |
| **common-argocd** | common-forge, common-kubernetes | - | GitOps |
| **common-library** | - (DEPRECATED) | - (NONE) | Deprecated |

## Layer Architecture

### Layer 1: Base (common-forge)
**Purpose**: Core helpers and naming conventions

**Provides**:
- `forge.labels` - Standard Kubernetes + Forge labels
- `forge.resourceName` - Consistent resource naming
- `forge.namespace` - Namespace naming with tenant/customer/cluster patterns
- `forge.name`, `forge.fullname` - Chart name helpers
- `forge.selectorLabels` - Pod selector labels

**Used by**: All 9 active charts

---

### Layer 2: Core Infrastructure

#### common-kubernetes
**Purpose**: Standard Kubernetes resource templates

**Provides**:
- Deployment, StatefulSet, DaemonSet, Job, CronJob
- Service, Ingress, NetworkPolicy
- ConfigMap, Secret, ServiceAccount
- PVC, HPA, VPA, PodDisruptionBudget
- RBAC (Role, RoleBinding, ClusterRole, ClusterRoleBinding)

**Dependencies**: common-forge, common-vault

#### common-vault
**Purpose**: HashiCorp Vault integration

**Provides**:
- Vault secret injection
- ServiceAccount annotations for Vault auth
- Secret synchronization templates

**Dependencies**: common-forge

---

### Layer 3: Security & Governance

#### common-kyverno (7,698 lines) ⭐
**Purpose**: Policy governance and GitOps enforcement

**Provides**:
- **API Restrictions** (5 policies):
  * Block kubectl exec/port-forward
  * Block kubectl proxy
  * Block ephemeral containers
  * Block kubectl attach
  * Block kubectl cp
- **Resource Management** (5 policies):
  * Block workload modifications (Deployments, StatefulSets)
  * Block networking modifications (Services, Ingresses)
  * Block config modifications (ConfigMaps, Secrets)
  * Block storage modifications (PVCs, PVs)
  * Block RBAC modifications
- **Debug Proxy**: Controlled access via ServiceAccount
- **Custom Policies**: Extensible policy templates

**Dependencies**: common-forge

**Key Features**:
- GitOps-only enforcement (block direct kubectl)
- Break-glass procedures
- Audit/Enforce modes
- Exclusion lists (namespaces, ServiceAccounts, users)

#### common-security (1,651 lines)
**Purpose**: Vulnerability scanning and runtime protection

**Provides**:
- **Trivy Scanning**:
  * Vulnerability scanning
  * Configuration scanning (IaC)
  * Secret scanning
  * Scheduled CronJob scans
- **Falco Runtime Security**:
  * 9 pre-configured rules
  * Custom rule templates
  * Alert integration

**Dependencies**: common-forge

#### common-hardening
**Purpose**: Network segmentation and resource quotas

**Provides**:
- NetworkPolicies (deny-all, allow-dns, allow-internet, etc.)
- ResourceQuotas
- LimitRanges
- PodSecurityPolicies (deprecated, migrating to PSS)

**Dependencies**: common-forge

---

### Layer 4: Observability

#### common-monitoring (1,707 lines)
**Purpose**: Prometheus and Grafana integration

**Provides**:
- **PrometheusRule** templates:
  * Availability alerts (5xx errors, pod crashes)
  * Resource alerts (CPU, memory, disk)
  * SLO alerts (latency, error rate, saturation)
  * Custom alert templates
- **Grafana Dashboards**:
  * Application dashboard (golden signals)
  * Infrastructure dashboard (node/pod metrics)
  * Custom dashboard support

**Dependencies**: common-forge

**Key Features**:
- Golden signals (latency, traffic, errors, saturation)
- Multi-environment support (prod, staging, dev)
- Sidecar discovery (Grafana sidecar pattern)

---

### Layer 5: Autoscaling

#### common-keda
**Purpose**: Event-driven autoscaling with KEDA

**Provides**:
- ScaledObject templates (HPA-like)
- ScaledJob templates (event-driven jobs)
- Vault secret integration for scalers
- Support for 50+ KEDA scalers

**Dependencies**: common-forge, common-vault

---

### Layer 6: Cloud & GitOps Integration

#### common-aws
**Purpose**: AWS-specific resource templates

**Provides**:
- IAM Roles for Service Accounts (IRSA)
- AWS ALB Ingress annotations
- EBS/EFS PVC templates
- AWS-specific labels and annotations

**Dependencies**: common-forge, common-kubernetes

#### common-argocd
**Purpose**: ArgoCD Application/ApplicationSet templates

**Provides**:
- ArgoCD Application CRDs
- ArgoCD ApplicationSet CRDs
- Multi-cluster deployment patterns
- GitOps repository configurations

**Dependencies**: common-forge, common-kubernetes

---

## Deprecated Charts

### common-library ⚠️
**Status**: DEPRECATED - No charts depend on this

**Issues**:
1. Uses `common-library.labels` (non-standard)
2. Uses `common-library.fullname` (non-standard)
3. No Forge naming convention support
4. No `moai.forge.io/*` labels

**Recommendation**: Archive or delete

---

## Dependency Resolution Order

When using multiple charts together, Helm resolves dependencies in this order:

```yaml
# Example Chart.yaml for an application
dependencies:
  # 1. Base layer (always first)
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
  
  # 2. Core infrastructure (if needed)
  - name: common-kubernetes
    version: ~0.1.0
    repository: file://../common-kubernetes
  
  # 3. Security & governance (if needed)
  - name: common-kyverno
    version: ~0.1.0
    repository: file://../common-kyverno
    condition: kyverno.enabled
  
  - name: common-security
    version: ~0.1.0
    repository: file://../common-security
    condition: security.scanning.enabled
  
  # 4. Observability (if needed)
  - name: common-monitoring
    version: ~0.1.0
    repository: file://../common-monitoring
    condition: monitoring.enabled
  
  # 5. Autoscaling (if needed)
  - name: common-keda
    version: ~0.1.0
    repository: file://../common-keda
    condition: keda.enabled
```

## Integration Patterns

### Pattern 1: Full Stack Application

```yaml
# Complete application with all features
dependencies:
  - common-forge          # Base helpers
  - common-kubernetes     # K8s resources
  - common-monitoring     # Prometheus/Grafana
  - common-security       # Trivy/Falco scanning
  - common-keda          # Autoscaling
  - common-aws           # AWS integration
```

**Use Cases**:
- Production microservices
- Multi-environment deployments
- Fully governed applications

---

### Pattern 2: GitOps-Enforced Environment

```yaml
# Cluster-wide GitOps enforcement
dependencies:
  - common-forge          # Base helpers
  - common-kyverno        # Policy enforcement
  - common-monitoring     # Observability
  - common-security       # Security scanning
```

**Use Cases**:
- Platform team managing cluster
- Production environments
- Compliance-heavy industries

**Features**:
- Block direct kubectl access
- Enforce GitOps workflows
- Audit all changes
- Runtime security monitoring

---

### Pattern 3: Development Environment

```yaml
# Minimal dependencies for dev
dependencies:
  - common-forge          # Base helpers
  - common-kubernetes     # K8s resources
  - common-monitoring     # Basic monitoring
```

**Use Cases**:
- Local development clusters
- Testing environments
- Developer sandboxes

---

### Pattern 4: Multi-Cloud Platform

```yaml
# Cloud-agnostic with provider-specific integration
dependencies:
  - common-forge          # Base helpers
  - common-kubernetes     # K8s resources
  - common-aws           # AWS-specific (conditionally)
  # Add common-azure, common-gcp in future
```

**Use Cases**:
- Multi-cloud deployments
- Cloud migration projects
- Hybrid cloud architectures

---

## Testing Dependency Chain

```bash
# Test dependency resolution
cd /path/to/forge-helpers/charts

# 1. Build base layer
cd common-forge && helm dependency update && cd ..

# 2. Build core layer
cd common-kubernetes && helm dependency update && cd ..
cd common-vault && helm dependency update && cd ..

# 3. Build security layer
cd common-kyverno && helm dependency update && cd ..
cd common-security && helm dependency update && cd ..
cd common-hardening && helm dependency update && cd ..

# 4. Build observability layer
cd common-monitoring && helm dependency update && cd ..

# 5. Build autoscaling layer
cd common-keda && helm dependency update && cd ..

# 6. Build integration layer
cd common-aws && helm dependency update && cd ..
cd common-argocd && helm dependency update && cd ..

# Verify all charts lint successfully
for chart in common-*/; do
  echo "=== Linting $chart ==="
  helm lint "$chart"
done
```

## Version Compatibility

All charts use **~0.1.0** semantic versioning:

- `~0.1.0` = `>=0.1.0 <0.2.0` (patch updates only)
- Breaking changes = bump minor version (0.2.0)
- New features (backwards compatible) = bump patch version (0.1.1)

**Current versions**: All charts are on 0.1.0

---

## Future Dependencies

### Planned Charts

1. **common-azure** - Azure-specific integrations
2. **common-gcp** - Google Cloud integrations
3. **common-istio** - Istio service mesh
4. **common-cert-manager** - Certificate management
5. **common-external-secrets** - External Secrets Operator

### Dependency Predictions

```
common-istio → common-forge, common-kubernetes
common-cert-manager → common-forge, common-kubernetes
common-external-secrets → common-forge, common-vault
common-azure → common-forge, common-kubernetes
common-gcp → common-forge, common-kubernetes
```

---

## Summary

- **11 charts total**: 10 active + 1 deprecated
- **9 charts depend on common-forge**: 100% adoption ✅
- **2 charts depend on common-kubernetes**: AWS, ArgoCD
- **2 charts depend on common-vault**: Kubernetes, KEDA
- **0 charts depend on common-library**: Safe to deprecate ✅

**Dependency health**: ✅ EXCELLENT - Clean, hierarchical, no circular dependencies
