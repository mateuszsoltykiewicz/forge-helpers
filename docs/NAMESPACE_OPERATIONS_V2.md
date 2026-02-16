# Namespace Operations V2: Deploy → Measure → Harden

**Philosophy:** Dynamic security hardening based on actual workload requirements, not static configuration.

---

## 📋 Table of Contents

1. [Philosophy & Design Principles](#philosophy--design-principles)
2. [Architecture Overview](#architecture-overview)
3. [Script Reference](#script-reference)
   - [namespace-create.sh](#namespace-createsh)
   - [namespace-hardening.sh](#namespace-hardeningsh)
   - [namespace-delete.sh](#namespace-deletesh)
   - [namespace-verify.sh](#namespace-verifysh)
   - [namespace-update.sh](#namespace-updatesh)
4. [VPA/HPA/Goldilocks Integration](#vpahpagoldilocks-integration)
5. [Security Model](#security-model)
6. [Namespace Types](#namespace-types)
7. [Implementation Details](#implementation-details)
8. [Workflow Examples](#workflow-examples)

---

## Philosophy & Design Principles

### 🎯 Core Philosophy

**Problem with Static Quotas:**
- Arbitrary limits that don't match reality
- Either too restrictive (blocks legitimate workloads) or too permissive (security risk)
- Requires guessing resource needs upfront
- No adaptation to actual usage patterns

**Solution: Deploy → Measure → Harden**
```
Step 1: Create namespace (permissive, labeled)
        ↓
Step 2: Deploy application/infrastructure
        ↓
Step 3: Measure actual resource usage (VPA/HPA/Goldilocks)
        ↓
Step 4: Harden with calculated quotas (lock down)
        ↓
Step 5: Verify compliance (continuous monitoring)
```

### 🔐 Security Principles

1. **Least Privilege by Measurement** - Quotas match exact workload requirements + safety buffer
2. **Defense in Depth** - ResourceQuota + NetworkPolicy + PSS + Audit
3. **Immutable Post-Hardening** - Changes require explicit `namespace-update.sh` approval
4. **Zero-Trust Creation** - Namespaces start labeled but unprotected during deployment window
5. **Continuous Verification** - `namespace-verify.sh` monitors for unhardened namespaces

### 🎨 Design Principles

- **Reality-Based Security** - Measure first, restrict second
- **GitOps Compatible** - Works with ArgoCD/FluxCD deployment flows
- **VPA/HPA Aware** - Integrates with Kubernetes autoscaling recommendations
- **Audit Trail** - Clear state tracking via labels (`moai.forge.io/hardened=true`)
- **Fail-Safe Defaults** - Unhardened namespaces detected by monitoring

---

## Architecture Overview

### 🏗️ Script Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Namespace Lifecycle                          │
└─────────────────────────────────────────────────────────────────┘

CREATE PHASE                    HARDENING PHASE              OPERATIONS
─────────────────              ──────────────────            ────────────

namespace-create.sh            namespace-hardening.sh        namespace-verify.sh
     │                                │                            │
     ├─ Create namespace              ├─ Measure VPA/HPA          ├─ Check hardening status
     ├─ Apply labels                  ├─ Calculate quotas         ├─ Validate quotas
     ├─ Set type metadata             ├─ Apply ResourceQuota      ├─ Report violations
     └─ Mark unhardened               ├─ Apply NetworkPolicy      └─ Alert unhardened NS
                                      ├─ Apply PSS labels
                                      ├─ Create Vault bundle
                                      └─ Mark hardened

                                                              namespace-delete.sh
                                                                   │
                                                                   ├─ Verify no workloads
                                                                   ├─ Check dependencies
                                                                   ├─ Remove namespace
                                                                   └─ Audit log

                                                              namespace-update.sh
                                                                   │
                                                                   ├─ Temporarily expand
                                                                   ├─ Allow new workloads
                                                                   ├─ Re-measure resources
                                                                   └─ Re-harden with new limits
```

### 🔄 State Machine

```
┌───────────────┐
│   CREATED     │ ← namespace-create.sh
│ unhardened    │
└───────┬───────┘
        │
        │ Application deployed
        │ VPA/HPA data available
        ▼
┌───────────────┐
│  MEASURED     │ ← namespace-hardening.sh analyzes
│ calculating   │
└───────┬───────┘
        │
        │ Quotas applied
        │ Policies enforced
        ▼
┌───────────────┐
│   HARDENED    │ ← namespace-verify.sh monitors
│   locked      │
└───────┬───────┘
        │
        │ Need capacity increase
        ▼
┌───────────────┐
│  UPDATING     │ ← namespace-update.sh
│ expanding     │
└───────┬───────┘
        │
        │ Re-measure & re-harden
        ▼
┌───────────────┐
│   HARDENED    │
│   (new limit) │
└───────────────┘
```

### 🏷️ Namespace Labels

All namespaces managed by this system use these labels:

```yaml
metadata:
  labels:
    # Core management labels
    moai.forge.io/managed: "true"              # Managed by namespace-*.sh scripts
    moai.forge.io/type: "application"          # Namespace type (see Namespace Types)
    
    # Hardening state tracking
    moai.forge.io/hardened: "false"            # true after namespace-hardening.sh
    moai.forge.io/hardened-at: "2026-02-11T10:30:00Z"  # ISO8601 timestamp
    moai.forge.io/hardened-version: "v2.0"     # Script version for auditing
    
    # Resource tracking
    moai.forge.io/quota-cpu-limit: "8"         # Applied CPU limit (cores)
    moai.forge.io/quota-memory-limit: "16Gi"   # Applied memory limit
    moai.forge.io/quota-max-pods: "50"         # Max pods allowed
    
    # VPA/HPA metadata
    moai.forge.io/vpa-detected: "true"         # VPA recommendations found
    moai.forge.io/hpa-detected: "true"         # HPA configurations found
    moai.forge.io/goldilocks-detected: "false" # Goldilocks recommendations available
```

---

## Script Reference

### namespace-create.sh

**Purpose:** Create labeled namespace without security hardening (permissive initial state).

#### Usage

```bash
# Basic usage
./namespace-create.sh --name my-app --type application

# With custom metadata
./namespace-create.sh \
  --name analytics-pipeline \
  --type middleware \
  --owner team-data \
  --project metis \
  --environment production

# Infrastructure namespace
./namespace-create.sh --name keda --type keda
```

#### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--name` | Yes | - | Namespace name (DNS-1123 compliant) |
| `--type` | Yes | - | Namespace type (see Namespace Types) |
| `--owner` | No | - | Team/owner label |
| `--project` | No | - | Project/product label |
| `--environment` | No | production | Environment (dev/staging/production) |
| `--dry-run` | No | false | Show what would be created |

#### What It Does

1. **Validate inputs** - Check name format, type validity
2. **Create namespace** - `kubectl create namespace <name>`
3. **Apply labels** - Core management + metadata labels
4. **Mark unhardened** - Set `moai.forge.io/hardened=false`
5. **Audit log** - Record creation event

#### Example Output

```bash
$ ./namespace-create.sh --name payment-service --type application

✓ Validating namespace name: payment-service
✓ Checking namespace type: application
✓ Creating namespace: payment-service
✓ Applying management labels
✓ Setting hardening state: unhardened

Namespace 'payment-service' created successfully!

⚠️  SECURITY WARNING:
   This namespace is UNHARDENED and has no resource quotas or policies.
   
   Next steps:
   1. Deploy your application to this namespace
   2. Wait for VPA/HPA recommendations (30-60 minutes)
   3. Run: ./namespace-hardening.sh --name payment-service
   
   Unhardened namespaces older than 4 hours will trigger alerts!

Labels applied:
  moai.forge.io/managed: true
  moai.forge.io/type: application
  moai.forge.io/hardened: false
  moai.forge.io/created-at: 2026-02-11T10:15:00Z
```

#### Exit Codes

- `0` - Success
- `1` - Invalid arguments
- `2` - Namespace already exists
- `3` - Kubernetes API error

---

### namespace-hardening.sh

**Purpose:** Measure workload resources and apply security hardening with calculated quotas.

#### Usage

```bash
# Standard hardening (after deployment)
./namespace-hardening.sh --name my-app

# Force re-hardening (update existing quotas)
./namespace-hardening.sh --name my-app --force

# Custom safety buffer (default 20%)
./namespace-hardening.sh --name my-app --buffer-percent 30

# Dry-run to see what would be applied
./namespace-hardening.sh --name my-app --dry-run
```

#### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--name` | Yes | - | Namespace to harden |
| `--force` | No | false | Re-harden already hardened namespace |
| `--buffer-percent` | No | 20 | Safety buffer added to measured resources (%) |
| `--max-cpu-limit` | No | 64 | Maximum CPU limit allowed (sanity check) |
| `--max-memory-limit` | No | 128Gi | Maximum memory limit allowed (sanity check) |
| `--skip-vpa` | No | false | Skip VPA recommendation detection |
| `--skip-hpa` | No | false | Skip HPA max replica detection |
| `--skip-goldilocks` | No | false | Skip Goldilocks integration |
| `--dry-run` | No | false | Show what would be applied |

#### What It Does

**Phase 1: Measurement**
1. **Check namespace state** - Verify namespace exists and has workloads
2. **Detect VPA recommendations** - Parse VPA `upperBound` for CPU/memory
3. **Detect HPA configurations** - Calculate max pods from `maxReplicas`
4. **Parse Goldilocks data** - Use Goldilocks recommendations if available
5. **Fallback to pod limits** - If no autoscaler data, use container `resources.limits`

**Phase 2: Calculation**
1. **Aggregate CPU limits** - Sum all VPA/pod CPU recommendations
2. **Aggregate memory limits** - Sum all VPA/pod memory recommendations
3. **Calculate max pods** - HPA `maxReplicas` × number of deployments + buffer
4. **Apply safety buffer** - Add 20% (configurable) to prevent quota exhaustion
5. **Validate sanity checks** - Reject if exceeds `--max-cpu-limit` or `--max-memory-limit`

**Phase 3: Hardening**
1. **Apply ResourceQuota** - CPU, memory, pods, PVCs
2. **Apply NetworkPolicy** - Default deny ingress/egress based on namespace type
3. **Apply PSS labels** - Pod Security Standards enforcement
4. **Create Vault bundle** (application type only) - Certificate bundle secret
5. **Update namespace labels** - Mark as hardened with metadata

**Phase 4: Verification**
1. **Verify quota applied** - Check ResourceQuota exists and matches
2. **Verify policies** - Check NetworkPolicy and PSS labels
3. **Test quota enforcement** - Attempt to create over-quota pod (dry-run)

#### Example Output

```bash
$ ./namespace-hardening.sh --name payment-service

=== Namespace Hardening: payment-service ===

[1/4] MEASUREMENT PHASE
  ✓ Namespace exists: payment-service
  ✓ Workloads detected: 3 deployments, 8 pods
  ✓ VPA recommendations found:
      - payment-api: CPU 2 cores, Memory 4Gi
      - payment-worker: CPU 1 core, Memory 2Gi
      - payment-cache: CPU 0.5 cores, Memory 1Gi
  ✓ HPA configurations found:
      - payment-api: maxReplicas=10
      - payment-worker: maxReplicas=5
  ⚠ Goldilocks not detected (skipping)

[2/4] CALCULATION PHASE
  ✓ Total CPU limit (measured): 3.5 cores
  ✓ Total memory limit (measured): 7Gi
  ✓ Max pods (HPA-aware): 15 pods
  ✓ Safety buffer applied (20%): 
      - CPU: 3.5 → 4.2 cores (rounded to 5)
      - Memory: 7Gi → 8.4Gi (rounded to 9Gi)
      - Pods: 15 → 18 (rounded to 20)
  ✓ Sanity checks passed:
      - CPU 5 cores < max 64 cores ✓
      - Memory 9Gi < max 128Gi ✓

[3/4] HARDENING PHASE
  ✓ Applying ResourceQuota:
      requests.cpu: 5
      requests.memory: 9Gi
      limits.cpu: 5
      limits.memory: 9Gi
      pods: 20
      persistentvolumeclaims: 5
  ✓ Applying NetworkPolicy (default-deny-ingress)
  ✓ Applying PSS labels (pod-security.kubernetes.io/enforce=restricted)
  ✓ Creating Vault certificate bundle: payment-service-vault-bundle
  ✓ Updating namespace labels:
      moai.forge.io/hardened: true
      moai.forge.io/hardened-at: 2026-02-11T11:00:00Z
      moai.forge.io/quota-cpu-limit: 5
      moai.forge.io/quota-memory-limit: 9Gi
      moai.forge.io/quota-max-pods: 20

[4/4] VERIFICATION PHASE
  ✓ ResourceQuota exists and matches
  ✓ NetworkPolicy applied correctly
  ✓ PSS labels configured
  ✓ Quota enforcement test passed

=== Hardening Complete ===

Namespace 'payment-service' is now HARDENED and LOCKED.

Resources allowed:
  - CPU: 5 cores
  - Memory: 9Gi
  - Pods: 20
  - PVCs: 5

To increase quotas, use:
  ./namespace-update.sh --name payment-service

Audit log: /var/log/namespace-operations/payment-service-hardening.log
```

#### Exit Codes

- `0` - Success
- `1` - Invalid arguments
- `2` - Namespace not found or already hardened (without --force)
- `3` - No workloads detected (cannot measure)
- `4` - Measurement failed (VPA/HPA parsing errors)
- `5` - Sanity check failed (exceeds max limits)
- `6` - Hardening failed (quota/policy apply errors)
- `7` - Verification failed

---

### namespace-delete.sh

**Purpose:** Safely delete namespace after verifying no active workloads or dependencies.

#### Usage

```bash
# Standard deletion (with safety checks)
./namespace-delete.sh --name old-app

# Skip confirmation prompt
./namespace-delete.sh --name old-app --yes

# Force deletion (skip all checks - DANGEROUS)
./namespace-delete.sh --name old-app --force
```

#### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--name` | Yes | - | Namespace to delete |
| `--yes` | No | false | Skip confirmation prompt |
| `--force` | No | false | Skip safety checks (DANGEROUS) |
| `--dry-run` | No | false | Show what would be deleted |

#### What It Does

**Safety Checks (unless --force):**
1. **Verify namespace exists** - Check it's managed by moai.forge.io
2. **Check active workloads** - Block if pods/deployments/statefulsets exist
3. **Check PVCs** - Warn about data loss if PVCs exist
4. **Check dependencies** - Search for references in other namespaces
5. **User confirmation** - Require explicit "yes" unless --yes flag

**Deletion Process:**
1. **Remove Vault bundle** - Delete certificate bundle secret
2. **Remove policies** - Delete NetworkPolicy and ResourceQuota
3. **Delete namespace** - `kubectl delete namespace <name>`
4. **Audit log** - Record deletion event

#### Example Output

```bash
$ ./namespace-delete.sh --name old-service

=== Namespace Deletion: old-service ===

[1/3] SAFETY CHECKS
  ✓ Namespace exists: old-service
  ✓ Managed by moai.forge.io: true
  ⚠️  Active workloads detected:
      - 2 pods running
      - 1 deployment
  ⚠️  Persistent volumes detected:
      - 1 PVC (data-postgres-0) - 10Gi
      
  ❌ Cannot delete namespace with active workloads!
  
  To proceed:
  1. Scale down deployments: kubectl scale deployment --all --replicas=0 -n old-service
  2. Delete PVCs manually if data can be lost
  3. Re-run: ./namespace-delete.sh --name old-service
  
  Or use --force to override (NOT RECOMMENDED)

Exit code: 2
```

```bash
$ ./namespace-delete.sh --name old-service --yes

=== Namespace Deletion: old-service ===

[1/3] SAFETY CHECKS
  ✓ Namespace exists: old-service
  ✓ Managed by moai.forge.io: true
  ✓ No active workloads
  ✓ No PVCs
  ✓ No external dependencies

[2/3] RESOURCE CLEANUP
  ✓ Removed ResourceQuota
  ✓ Removed NetworkPolicy
  ✓ Removed PSS labels

[3/3] NAMESPACE DELETION
  ✓ Deleted namespace: old-service
  ✓ Audit log written

=== Deletion Complete ===

Namespace 'old-service' has been permanently deleted.
```

#### Exit Codes

- `0` - Success
- `1` - Invalid arguments
- `2` - Safety checks failed (active workloads)
- `3` - User cancelled deletion
- `4` - Deletion failed

---

### namespace-verify.sh

**Purpose:** Continuous compliance monitoring for namespace hardening state and quota violations.

#### Usage

```bash
# Verify single namespace
./namespace-verify.sh --name my-app

# Verify all managed namespaces
./namespace-verify.sh --all

# Check for unhardened namespaces (monitoring mode)
./namespace-verify.sh --check-unhardened

# Generate compliance report
./namespace-verify.sh --all --report compliance-report.json
```

#### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--name` | No | - | Single namespace to verify |
| `--all` | No | false | Verify all managed namespaces |
| `--check-unhardened` | No | false | Alert on unhardened namespaces >4 hours old |
| `--report` | No | - | Output JSON compliance report to file |
| `--max-age-hours` | No | 4 | Max hours allowed for unhardened namespace |

#### What It Does

**Verification Checks:**
1. **Hardening state** - Check `moai.forge.io/hardened=true`
2. **ResourceQuota exists** - Verify quota applied and matches labels
3. **NetworkPolicy exists** - Check policy enforcement
4. **PSS labels** - Verify Pod Security Standards configured
5. **Quota usage** - Compare current usage vs limits
6. **Label consistency** - Verify metadata labels match actual quotas
7. **Vault bundle** (application type) - Check certificate bundle exists

**Violation Detection:**
1. **Unhardened namespaces** - Older than `--max-age-hours`
2. **Quota drift** - Labels don't match actual ResourceQuota
3. **Policy missing** - NetworkPolicy deleted
4. **Near-quota exhaustion** - Usage >90% of limit
5. **Orphaned namespaces** - Managed label but no workloads for >30 days

#### Example Output

```bash
$ ./namespace-verify.sh --all

=== Namespace Verification Report ===
Generated: 2026-02-11T12:00:00Z

SUMMARY
  Total managed namespaces: 8
  Hardened: 6
  Unhardened: 2
  Violations: 1
  Warnings: 2

┌─────────────────────────────────────────────────────────────────┐
│ COMPLIANT NAMESPACES (6)                                        │
└─────────────────────────────────────────────────────────────────┘

✓ payment-service (application)
  - Hardened: 2026-02-11T11:00:00Z (1 hour ago)
  - Quota: 5 CPU, 9Gi memory, 20 pods
  - Usage: 3.2 CPU (64%), 5Gi memory (55%), 8 pods (40%)
  - Status: COMPLIANT

✓ analytics-pipeline (middleware)
  - Hardened: 2026-02-10T15:30:00Z (20 hours ago)
  - Quota: 16 CPU, 32Gi memory, 100 pods
  - Usage: 12 CPU (75%), 24Gi memory (75%), 42 pods (42%)
  - Status: COMPLIANT

... (4 more)

┌─────────────────────────────────────────────────────────────────┐
│ UNHARDENED NAMESPACES (2)                                       │
└─────────────────────────────────────────────────────────────────┘

⚠️  new-service (application)
  - Created: 2026-02-11T10:00:00Z (2 hours ago)
  - Hardened: false
  - Workloads: 2 deployments, 5 pods
  - Status: OK (within 4-hour grace period)
  - Action: Run namespace-hardening.sh before 14:00:00Z

❌ forgotten-app (application)
  - Created: 2026-02-10T08:00:00Z (28 hours ago)
  - Hardened: false
  - Workloads: 1 deployment, 3 pods
  - Status: VIOLATION (exceeds 4-hour grace period)
  - Action: URGENT - Harden immediately!
    ./namespace-hardening.sh --name forgotten-app

┌─────────────────────────────────────────────────────────────────┐
│ WARNINGS (2)                                                    │
└─────────────────────────────────────────────────────────────────┘

⚠️  user-service (application)
  - Quota usage near limit:
      CPU: 7.2/8 cores (90%)
      Memory: 14Gi/16Gi (87%)
  - Action: Consider increasing quota
    ./namespace-update.sh --name user-service

⚠️  old-cache (middleware)
  - No workloads detected for 35 days
  - Status: Orphaned namespace candidate
  - Action: Review if namespace still needed
    ./namespace-delete.sh --name old-cache

┌─────────────────────────────────────────────────────────────────┐
│ RECOMMENDATIONS                                                 │
└─────────────────────────────────────────────────────────────────┘

1. URGENT: Harden 'forgotten-app' (violation)
2. Review quota for 'user-service' (near limit)
3. Consider deleting 'old-cache' (orphaned)

Exit code: 1 (violations detected)
```

#### Exit Codes

- `0` - All namespaces compliant
- `1` - Violations detected
- `2` - Warnings only
- `3` - Verification failed (API errors)

---

### namespace-update.sh

**Purpose:** Safely expand namespace quotas by temporarily allowing growth, redeploying, and re-hardening.

#### Usage

```bash
# Interactive update (prompts for new limits)
./namespace-update.sh --name my-app

# Automated update (measure current + apply buffer)
./namespace-update.sh --name my-app --auto

# Manual quota increase
./namespace-update.sh --name my-app --cpu-limit 16 --memory-limit 32Gi --max-pods 50
```

#### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--name` | Yes | - | Namespace to update |
| `--auto` | No | false | Automatically measure and re-harden |
| `--cpu-limit` | No | - | New CPU limit (cores) |
| `--memory-limit` | No | - | New memory limit (e.g., 32Gi) |
| `--max-pods` | No | - | New max pods limit |
| `--buffer-percent` | No | 20 | Safety buffer for auto mode |
| `--dry-run` | No | false | Show what would be updated |

#### What It Does

**Two-Phase Update:**

**Phase 1: Expand (Temporary Permissive State)**
1. **Backup current quotas** - Save existing ResourceQuota
2. **Remove quota temporarily** - Allow workload scaling
3. **Mark as updating** - Set `moai.forge.io/hardened=updating`
4. **Wait for deployment** - User scales up workloads
5. **Monitor for stability** - Wait for VPA/HPA data

**Phase 2: Re-Harden (Lock New State)**
1. **Re-measure resources** - Call same logic as namespace-hardening.sh
2. **Calculate new quotas** - Include new workloads + buffer
3. **Apply new ResourceQuota** - Lock at new measured limits
4. **Update labels** - Mark as hardened with new values
5. **Verify compliance** - Check quota enforcement

#### Example Output

```bash
$ ./namespace-update.sh --name payment-service --auto

=== Namespace Update: payment-service ===

Current state:
  CPU limit: 5 cores
  Memory limit: 9Gi
  Max pods: 20
  Current usage: 4.8 cores (96%), 8.5Gi memory (94%), 18 pods (90%)

⚠️  WARNING: Namespace is near quota limits!

[1/2] EXPANSION PHASE
  ✓ Backed up current ResourceQuota to: /tmp/payment-service-quota-backup.yaml
  ✓ Removed ResourceQuota (temporary permissive state)
  ✓ Updated label: moai.forge.io/hardened=updating
  
  🚀 Namespace is now UNHARDENED
  
  You can now:
  - Scale up deployments
  - Deploy additional workloads
  - Increase HPA maxReplicas
  
  When ready, press ENTER to re-measure and re-harden...
  (Or Ctrl+C to cancel and manually re-harden later)

[User presses ENTER after scaling]

[2/2] RE-HARDENING PHASE
  ✓ Measuring current workloads...
  ✓ VPA recommendations:
      - payment-api: CPU 4 cores, Memory 8Gi (increased from 2/4Gi)
      - payment-worker: CPU 1 core, Memory 2Gi
      - payment-cache: CPU 0.5 cores, Memory 1Gi
  ✓ New totals (with 20% buffer):
      - CPU: 6.6 cores (rounded to 7)
      - Memory: 13.2Gi (rounded to 14Gi)
      - Pods: 20 → 25
  ✓ Applying new ResourceQuota
  ✓ Verifying quota enforcement
  ✓ Updated labels with new values

=== Update Complete ===

Namespace 'payment-service' re-hardened with new quotas:
  CPU: 5 cores → 7 cores (+40%)
  Memory: 9Gi → 14Gi (+55%)
  Pods: 20 → 25 (+25%)

Quota backup saved to: /tmp/payment-service-quota-backup.yaml
```

#### Exit Codes

- `0` - Success
- `1` - Invalid arguments
- `2` - Namespace not hardened (use namespace-hardening.sh first)
- `3` - Update failed (measurement or hardening errors)
- `4` - User cancelled

---

## VPA/HPA/Goldilocks Integration

### 🔍 Resource Measurement Strategy

The hardening script uses multiple data sources to accurately measure resource requirements:

```
Priority Order:
1. Goldilocks recommendations (if available) - Most accurate, observability-based
2. VPA upperBound (if available) - Historical usage + headroom
3. HPA maxReplicas × pod limits - Horizontal scaling aware
4. Pod resources.limits - Fallback to declared limits
```

### VPA Integration

**What We Use:**
- **`upperBound`** - Maximum recommended resources (P99 usage + buffer)
- Per-container recommendations aggregated to pod-level
- Historical data over 7-day window (VPA default)

**Example VPA Resource:**
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: payment-api-vpa
  namespace: payment-service
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-api
  updateMode: Auto
status:
  recommendation:
    containerRecommendations:
    - containerName: payment-api
      upperBound:
        cpu: 2000m      # ← We use this
        memory: 4Gi     # ← We use this
      target:
        cpu: 1500m
        memory: 3Gi
      lowerBound:
        cpu: 500m
        memory: 1Gi
```

**Parsing Logic:**
```bash
get_vpa_cpu_recommendation() {
  local namespace="$1"
  local deployment="$2"
  
  kubectl get vpa -n "$namespace" \
    -o json | \
    jq -r ".items[] | 
      select(.spec.targetRef.name == \"$deployment\") | 
      .status.recommendation.containerRecommendations[] | 
      .upperBound.cpu" | \
    convert_to_millicores | \
    awk '{sum+=$1} END {print sum}'
}
```

### HPA Integration

**What We Use:**
- **`maxReplicas`** - Maximum horizontal scale
- Multiply by pod resource limits to get worst-case quota needs

**Example HPA Resource:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: payment-api-hpa
  namespace: payment-service
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-api
  minReplicas: 3
  maxReplicas: 10    # ← We use this
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Pod Calculation:**
```bash
calculate_hpa_max_pods() {
  local namespace="$1"
  
  # Get all HPA maxReplicas, sum them
  kubectl get hpa -n "$namespace" -o json | \
    jq -r '.items[] | .spec.maxReplicas' | \
    awk '{sum+=$1} END {print sum}'
  
  # Add buffer for non-HPA workloads (daemonsets, static pods)
  # Example: +20% or +5 pods, whichever is larger
}
```

### Goldilocks Integration

**What We Use:**
- Goldilocks dashboard recommendations (if installed)
- Same VPA data but with UI-enhanced recommendations

**Checking for Goldilocks:**
```bash
has_goldilocks() {
  local namespace="$1"
  
  # Check if Goldilocks dashboard is installed
  kubectl get deployment -n goldilocks goldilocks-dashboard &>/dev/null || return 1
  
  # Check if namespace has Goldilocks label
  kubectl get namespace "$namespace" \
    -o jsonpath='{.metadata.labels.goldilocks\.fairwinds\.com/enabled}' | \
    grep -q "true"
}
```

### Measurement Workflow

```bash
# namespace-hardening.sh measurement logic

measure_namespace_resources() {
  local namespace="$1"
  local cpu_total=0
  local memory_total=0
  local pods_max=0
  
  # Try Goldilocks first
  if has_goldilocks "$namespace"; then
    log_info "Using Goldilocks recommendations"
    cpu_total=$(get_goldilocks_cpu "$namespace")
    memory_total=$(get_goldilocks_memory "$namespace")
  # Fallback to VPA
  elif has_vpa "$namespace"; then
    log_info "Using VPA upperBound recommendations"
    for deployment in $(get_deployments "$namespace"); do
      cpu=$(get_vpa_cpu_recommendation "$namespace" "$deployment")
      memory=$(get_vpa_memory_recommendation "$namespace" "$deployment")
      cpu_total=$((cpu_total + cpu))
      memory_total=$((memory_total + memory))
    done
  # Fallback to pod limits
  else
    log_warn "No VPA/Goldilocks found, using pod resource limits"
    cpu_total=$(calculate_namespace_cpu_limits "$namespace")
    memory_total=$(calculate_namespace_memory_limits "$namespace")
  fi
  
  # Calculate max pods from HPA
  if has_hpa "$namespace"; then
    pods_max=$(calculate_hpa_max_pods "$namespace")
  else
    # Fallback: count current pods + 50% buffer
    pods_current=$(count_namespace_pods "$namespace")
    pods_max=$(echo "$pods_current * 1.5" | bc | awk '{print int($1+0.5)}')
  fi
  
  # Apply safety buffer (default 20%)
  cpu_total=$(apply_buffer "$cpu_total" "$BUFFER_PERCENT")
  memory_total=$(apply_buffer "$memory_total" "$BUFFER_PERCENT")
  pods_max=$(apply_buffer "$pods_max" "$BUFFER_PERCENT")
  
  echo "$cpu_total $memory_total $pods_max"
}
```

---

## Security Model

### 🔐 Defense in Depth

**Layer 1: ResourceQuota (Resource Exhaustion Prevention)**
- Prevents CPU/memory bomb attacks
- Blocks pod sprawl
- Limits PVC storage usage

**Layer 2: NetworkPolicy (Network Isolation)**
- Default deny ingress/egress
- Explicit allow rules based on namespace type
- Prevents lateral movement

**Layer 3: Pod Security Standards (Container Hardening)**
- `restricted` - Application namespaces (strictest)
- `baseline` - Middleware/infrastructure (moderate)
- `privileged` - Vault/ArgoCD/kube-system (minimal restrictions)

**Layer 4: Vault Certificate Bundle (Application Only)**
- Pre-provisioned TLS certificates
- Automatic rotation
- Mutual TLS between services

**Layer 5: Continuous Monitoring**
- `namespace-verify.sh` alerts on policy drift
- Detects unhardened namespaces
- Quota exhaustion warnings

### 🛡️ Threat Mitigation

| Threat | Mitigation | Script Component |
|--------|------------|------------------|
| **Resource exhaustion attack** | Measured quotas + 20% buffer only | namespace-hardening.sh calculation |
| **Pod sprawl** | HPA-aware max pods limit | HPA integration logic |
| **Privilege escalation** | PSS enforcement (restricted for apps) | namespace-hardening.sh PSS labels |
| **Lateral movement** | Default deny NetworkPolicy | namespace-hardening.sh policies |
| **Quota bypass** | Immutable post-hardening (requires namespace-update.sh) | Label-based state tracking |
| **Configuration drift** | Continuous verification | namespace-verify.sh monitoring |
| **Unhardened namespaces** | Alert after 4-hour grace period | namespace-verify.sh --check-unhardened |
| **VPA/HPA manipulation** | Sanity checks (max 64 CPU, 128Gi memory) | namespace-hardening.sh validation |

### 🚨 Risk Mitigation Strategies

**1. Initial Deployment Window (Unhardened State)**

**Risk:** Namespace is permissive between create and hardening.

**Mitigations:**
- Grace period monitoring (4 hours max)
- `namespace-verify.sh` alerts on violations
- Admission webhooks (Kyverno/OPA) can enforce temp limits
- Label tracking (`moai.forge.io/hardened=false`)

**2. VPA/Goldilocks Manipulation**

**Risk:** Attacker inflates VPA recommendations before hardening.

**Mitigations:**
- Sanity checks (`--max-cpu-limit 64`, `--max-memory-limit 128Gi`)
- VPA recommendation age check (reject if <7 days of data)
- Manual override with `--cpu-limit` / `--memory-limit`
- Audit logs capture all measurements

**3. HPA Burst Attacks**

**Risk:** Malicious HPA requests 1000 replicas during deployment.

**Mitigations:**
- HPA `maxReplicas` sanity checks (reject if >100 without approval)
- Temporary HPA limits during deployment phase
- Buffer calculation prevents exact-fit quotas
- Cluster-level LimitRange as backstop

**4. Hardening Script Failure**

**Risk:** Namespace never gets hardened (step 3 skipped).

**Mitigations:**
- `namespace-verify.sh` continuous monitoring
- Alerts on unhardened namespaces >4 hours old
- Prometheus metrics: `moai_unhardened_namespaces_total`
- GitOps enforcement (ArgoCD sync hooks)

**5. Namespace Update Abuse**

**Risk:** `namespace-update.sh` used to bypass quotas.

**Mitigations:**
- Requires existing hardened namespace (not for initial bypass)
- Full audit trail (backup saved, logs recorded)
- Manual approval for large increases (>2x current quota)
- Rate limiting (max 1 update per 24 hours per namespace)

---

## Namespace Types

### 📦 Supported Types

| Type | PSS Enforce | Use Case | Default Network Policy | Vault Bundle |
|------|-------------|----------|------------------------|--------------|
| **application** | restricted | User applications | default-deny-ingress | ✓ Yes |
| **middleware** | baseline | Kafka, Redis, databases | default-deny-all | ✗ No |
| **forge-operator** | baseline | KOPF orchestrator pods | allow-api-server | ✗ No |
| **forge-jobs** | baseline | Bash worker jobs | default-deny-all | ✗ No |
| **vault** | privileged | HashiCorp Vault | allow-vault-clients | ✗ No |
| **argocd** | privileged | GitOps controller | allow-git-webhooks | ✗ No |
| **cert-manager** | baseline | Certificate automation | allow-acme-http01 | ✗ No |
| **privileged** | privileged | System workloads | none | ✗ No |
| **keda** | baseline | Event-driven autoscaler | default-deny-all | ✗ No |
| **kyverno** | baseline | Policy engine | default-deny-all | ✗ No |
| **monitoring** | baseline | Prometheus, Grafana | allow-scraping | ✗ No |
| **default** | baseline | Kubernetes default NS | none (locked) | ✗ No |
| **kube-system** | privileged | Kubernetes system | none (locked) | ✗ No |

### Type-Specific Behaviors

#### application
- **PSS:** `restricted` (no privileged containers, no host access)
- **NetworkPolicy:** Default deny ingress, allow egress to middleware/vault
- **Vault Bundle:** Automatic certificate provisioning
#### middleware
- **PSS:** `baseline` (allows some privileged ops for persistence)
- **NetworkPolicy:** Default deny all, explicit allow from applications
- **Use Cases:** Databases, caches, message queues
- **Typical Quota:** 16-32 CPU, 32-64Gi memory, 50-100 pods

#### forge-operator
- **PSS:** `baseline` (Python KOPF pods need Kubernetes API access)
- **NetworkPolicy:** Allow egress to Kubernetes API server, allow ingress on webhook ports (8443)
- **Use Cases:** Hybrid operator orchestrator (KOPF + Job pattern)
- **Naming Convention:**
  - Global: `forge-operator` (single operator for entire cluster)
  - Per-customer: `forge-operator-{customer}` (e.g., `forge-operator-acme`)
  - Per-project: `forge-operator-{project}` (e.g., `forge-operator-cronus`)
  - Per-service: `forge-operator-{service}` (e.g., `forge-operator-payment`)
- **Typical Quota:** 200m CPU, 256Mi memory, 5 pods (orchestrator HA + webhook)
- **Key Features:**
  - Always running (not job-based)
  - Small footprint (Python + KOPF framework)
  - Handles webhooks, timers, database connections
  - Creates Kubernetes Jobs for actual work

#### forge-jobs
- **PSS:** `baseline` (bash workers need cluster access via kubectl)
- **NetworkPolicy:** Default deny all (jobs run independently)
- **Use Cases:** Bash worker jobs spawned by forge-operator
- **Naming Convention:**
  - Global: `forge-jobs` (single namespace for all job execution)
  - Per-customer: `forge-jobs-{customer}` (isolate customer jobs)
  - Per-project: `forge-jobs-{project}` (isolate project jobs)
  - Per-service: `forge-jobs-{service}` (isolate service-specific jobs)
- **Typical Quota:** 2-4 CPU, 4-8Gi memory, 50-100 pods (for parallel job execution)
- **Key Features:**
  - Short-lived pods (jobs complete and terminate)
  - Bash scripts with kubectl/jq/bc
  - Fast startup (<1s)
  - TTL after completion (auto-cleanup)
  - High concurrency for bulk operations

**Multi-Tenancy Patterns:**

```bash
# Pattern 1: Single global operator + jobs namespace
./namespace-create.sh --name forge-operator --type forge-operator
./namespace-create.sh --name forge-jobs --type forge-jobs

# Pattern 2: Per-customer isolation
./namespace-create.sh --name forge-operator-acme --type forge-operator --project acme
./namespace-create.sh --name forge-jobs-acme --type forge-jobs --project acme

# Pattern 3: Per-project isolation (multi-project customers)
./namespace-create.sh --name forge-operator-cronus --type forge-operator --project cronus
./namespace-create.sh --name forge-jobs-cronus --type forge-jobs --project cronus

# Pattern 4: Per-service isolation (microservices architecture)
./namespace-create.sh --name forge-operator-payment --type forge-operator --project payment-service
./namespace-create.sh --name forge-jobs-payment --type forge-jobs --project payment-service
```

**Hardening Considerations:**

- **forge-operator:** Static resources (2 replicas, always running)
  - Hardening measurement: Based on pod limits (no VPA/HPA needed)
  - Quota: Conservative (200m CPU, 256Mi RAM per pod × 2 replicas + buffer)

- **forge-jobs:** Dynamic workload (jobs created on-demand)
  - Hardening measurement: Based on max concurrent jobs expected
  - Quota calculation:
    ```
    Max concurrent jobs: 50
    Per-job resources: 50m CPU, 64Mi RAM
    Total: 50 × 50m = 2500m (2.5 cores)
    With 20% buffer: 3 cores, 4Gi RAM
    ```
  - Pod quota: Allow burst capacity for bulk operations (100 pods)

#### keda / kyverno* 16-32 CPU, 32-64Gi memory, 50-100 pods

#### keda / kyverno
- **PSS:** `baseline` (needs cluster-scoped permissions)
- **NetworkPolicy:** Default deny all (except webhook traffic)
- **Pod Calculation:** Pre-sized for HA (9 pods for KEDA, 12 for Kyverno)
- **Use Cases:** Infrastructure controllers

#### default / kube-system
- **Mode:** Lock at current usage (post-Kubernetes install)
- **Purpose:** Prevent resource creep in system namespaces
- **Workflow:** Create after K8s install, measure existing pods, apply matching quota

---

## Implementation Details

### 📁 File Structure

```
forge-helpers/
├── scripts/
│   ├── namespace-create.sh          # Create unhardened namespace
│   ├── namespace-hardening.sh       # Measure + harden
│   ├── namespace-delete.sh          # Safe deletion
│   ├── namespace-verify.sh          # Compliance monitoring
│   ├── namespace-update.sh          # Quota expansion
│   └── namespace.sh                 # Legacy (deprecated)
│
├── lib/
│   ├── forge-namespace-core.sh      # Core functions (create, delete, labels)
│   ├── forge-namespace-hardening.sh # VPA/HPA measurement logic
│   ├── forge-namespace-quota.sh     # ResourceQuota generation
│   ├── forge-namespace-policy.sh    # NetworkPolicy templates
│   ├── forge-namespace-vault.sh     # Vault certificate bundle
│   └── forge-namespace-verify.sh    # Verification functions
│
├── config/
│   ├── network-policies/            # NetworkPolicy templates per type
│   │   ├── application.yaml
│   │   ├── middleware.yaml
│   │   └── ...
│   └── namespace-types.yaml         # Type definitions and defaults
│
├── docs/
│   ├── NAMESPACE_OPERATIONS_V2.md         # This document
│   ├── NAMESPACE_HARDENING_DETECTION.md   # VPA/HPA integration details
│   └── NAMESPACE_WORKFLOWS.md             # Usage examples
│
└── tests/
    ├── test-namespace-create.sh
    ├── test-namespace-hardening.sh
    └── ...
```

### 🔧 Library Functions

#### forge-namespace-core.sh
```bash
# Core namespace operations
create_namespace()              # Create namespace with labels
delete_namespace()              # Delete with safety checks
validate_namespace_name()       # DNS-1123 validation
apply_namespace_labels()        # Apply moai.forge.io labels
get_namespace_type()            # Read namespace type from label
namespace_exists()              # Check if namespace exists
```

#### forge-namespace-hardening.sh
```bash
# VPA/HPA/Goldilocks integration
has_vpa()                       # Check if VPA installed in namespace
has_hpa()                       # Check if HPA configured
has_goldilocks()                # Check if Goldilocks enabled
get_vpa_cpu_recommendation()    # Parse VPA upperBound CPU
get_vpa_memory_recommendation() # Parse VPA upperBound memory
calculate_hpa_max_pods()        # Sum HPA maxReplicas
apply_buffer()                  # Add safety buffer (default 20%)
validate_sanity_checks()        # Reject excessive quotas
```

#### forge-namespace-quota.sh
```bash
# ResourceQuota generation
generate_resource_quota()       # Create YAML from measurements
apply_resource_quota()          # Apply to namespace
remove_resource_quota()         # Delete (for namespace-update.sh)
backup_resource_quota()         # Save before update
verify_resource_quota()         # Check quota matches labels
```

#### forge-namespace-policy.sh
```bash
# NetworkPolicy management
get_network_policy_template()  # Load template for namespace type
apply_network_policy()         # Apply from template
verify_network_policy()        # Check policy exists
```

#### forge-namespace-vault.sh
```bash
# Vault certificate bundle (application type only)
create_vault_bundle()          # Provision certs from Vault
verify_vault_bundle()          # Check secret exists
delete_vault_bundle()          # Remove on namespace delete
```

#### forge-namespace-verify.sh
```bash
# Compliance verification
verify_namespace_hardened()     # Check hardened=true
verify_quota_labels_match()     # Labels match actual quota
check_unhardened_namespaces()   # Find old unhardened NS
check_quota_usage()             # Detect near-limit namespaces
check_orphaned_namespaces()     # Find empty namespaces >30 days
generate_compliance_report()    # JSON report output
```

### 🏷️ Label Schema

All labels follow the `moai.forge.io/*` convention:

```yaml
# Management labels
moai.forge.io/managed: "true"                    # Managed by namespace scripts
moai.forge.io/type: "application"                # Namespace type
moai.forge.io/created-by: "namespace-create.sh"  # Script that created
moai.forge.io/version: "v2.0.0"                  # Script version

# Hardening state
moai.forge.io/hardened: "true"                   # false/updating/true
moai.forge.io/hardened-at: "2026-02-11T10:30:00Z" # ISO8601 timestamp
moai.forge.io/hardened-version: "v2.0.0"         # Script version at hardening

# Applied quotas (for verification)
moai.forge.io/quota-cpu-requests: "5"
moai.forge.io/quota-cpu-limits: "5"
moai.forge.io/quota-memory-requests: "9Gi"
moai.forge.io/quota-memory-limits: "9Gi"
moai.forge.io/quota-max-pods: "20"
moai.forge.io/quota-pvc: "5"

# Measurement metadata
moai.forge.io/vpa-detected: "true"               # VPA found
moai.forge.io/hpa-detected: "true"               # HPA found
moai.forge.io/goldilocks-detected: "false"       # Goldilocks enabled
moai.forge.io/buffer-percent: "20"               # Safety buffer applied

# User metadata
moai.forge.io/owner: "team-platform"
moai.forge.io/project: "metis"
moai.forge.io/environment: "production"
moai.forge.io/cost-center: "engineering"
```

### 📊 ResourceQuota Template

Generated by `namespace-hardening.sh`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
  namespace: {{ namespace }}
  labels:
    moai.forge.io/managed: "true"
    moai.forge.io/type: {{ namespace_type }}
spec:
  hard:
    # CPU quotas (measured from VPA/HPA)
    requests.cpu: "{{ measured_cpu + buffer }}"
    limits.cpu: "{{ measured_cpu + buffer }}"
    
    # Memory quotas (measured from VPA/HPA)
    requests.memory: "{{ measured_memory + buffer }}"
    limits.memory: "{{ measured_memory + buffer }}"
    
    # Pod quotas (from HPA maxReplicas)
    pods: "{{ calculated_max_pods + buffer }}"
    
    # Storage quotas
    persistentvolumeclaims: "{{ type_default_pvcs }}"
    requests.storage: "{{ type_default_storage }}"
```

---

## Workflow Examples

### 🚀 Example 1: New Application Namespace

```bash
# Step 1: Create unhardened namespace
./namespace-create.sh \
  --name payment-service \
  --type application \
  --owner team-payments \
  --project metis

# Output:
# ✓ Namespace 'payment-service' created
# ⚠️  UNHARDENED - No quotas or policies applied
# Next: Deploy application, then run namespace-hardening.sh

# Step 2: Deploy application (using Helm, kubectl, ArgoCD, etc.)
helm install payment-api ./charts/payment-api \
  --namespace payment-service \
  --set replicas=3 \
  --set autoscaling.enabled=true \
  --set autoscaling.maxReplicas=10

# Step 3: Wait for VPA recommendations (30-60 minutes)
kubectl get vpa -n payment-service
# NAME              MODE   CPU    MEMORY   AGE
# payment-api-vpa   Auto   2000m  4Gi      45m

# Step 4: Harden the namespace
./namespace-hardening.sh --name payment-service

# Output:
# ✓ Measured: 3.5 cores, 7Gi memory, 15 max pods
# ✓ Applied quota: 5 cores, 9Gi, 20 pods (with 20% buffer)
# ✓ NetworkPolicy: default-deny-ingress
# ✓ PSS: restricted
# ✓ Vault bundle created

# Step 5: Verify compliance
./namespace-verify.sh --name payment-service
# ✓ COMPLIANT - All checks passed
```

### 📈 Example 2: Scale Existing Namespace

```bash
# Current state: 5 CPU, 9Gi memory, near quota limit
kubectl top pods -n payment-service
# NAME              CPU   MEMORY
# payment-api-1     1.8   3.1Gi
# payment-api-2     1.7   2.9Gi
# payment-api-3     1.5   2.8Gi
# Total: 5.0 cores (100%), 8.8Gi (97%)

# Need to scale to 10 replicas for Black Friday
./namespace-update.sh --name payment-service --auto

# Output:
# [1/2] EXPANSION PHASE
# ✓ Removed quota (temporary permissive state)
# 🚀 Deploy new workloads now...

# Scale up deployment
kubectl scale deployment payment-api -n payment-service --replicas=10

# Wait for VPA to adjust (press ENTER in script when ready)

# [2/2] RE-HARDENING PHASE
# ✓ Measured: 10 cores, 28Gi, 30 pods
# ✓ New quota: 12 cores, 32Gi, 35 pods
# ✓ Re-hardened successfully

# Verify new quota
kubectl get resourcequota -n payment-service -o yaml
```

### 🔒 Example 3: Lock System Namespaces (Post-K8s Install)

```bash
# After fresh Kubernetes installation
kubectl get pods -n kube-system
# NAME                              READY   STATUS
# coredns-1234                      1/1     Running
# kube-apiserver-node1              1/1     Running
# ... (standard K8s pods)

# Step 1: Create quota for kube-system (locks at current usage)
./namespace-create.sh --name kube-system --type kube-system

# Step 2: Immediately harden (prevents resource creep)
./namespace-hardening.sh --name kube-system

# Output:
# ✓ Measured: 12 pods, 4 cores, 8Gi memory
# ✓ Applied quota: 12 pods, 5 cores, 10Gi (with 20% buffer)
# 🔒 kube-system LOCKED - no new workloads allowed

# Step 3: Repeat for default namespace
./namespace-create.sh --name default --type default
./namespace-hardening.sh --name default

# Step 4: Verify system namespaces locked
./namespace-verify.sh --check-unhardened
# ✓ No unhardened system namespaces
```

### 🛠️ Example 4: Infrastructure Namespace (KEDA)

```bash
# Pre-sized for KEDA HA deployment (3 deployments × 3 replicas = 9 pods)
./namespace-create.sh --name keda --type keda

# Install KEDA via Helm
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda \
  --namespace keda \
  --set replicaCount=3

# Harden after installation
./namespace-hardening.sh --name keda

# Output:
# ✓ Detected: 9 pods (keda-operator, keda-metrics, keda-admission)
# ✓ Applied quota: 9 pods, 4 cores, 8Gi (matches HA config)
```

### 🚨 Example 5: Detect Unhardened Namespace (Monitoring)

```bash
# Run in monitoring system (cronjob every 15 minutes)
./namespace-verify.sh --check-unhardened --max-age-hours 4

# Output:
# ❌ VIOLATION: forgotten-app (unhardened for 28 hours)
# ⚠️  WARNING: new-service (unhardened for 2 hours, within grace period)

# Alert sent to Slack/PagerDuty:
# "URGENT: Namespace 'forgotten-app' unhardened for 28 hours
#  Action required: ./namespace-hardening.sh --name forgotten-app"
```

### 📊 Example 6: Compliance Report Generation

```bash
# Generate JSON report for all namespaces
./namespace-verify.sh --all --report /tmp/compliance-$(date +%Y%m%d).json

# Report structure:
{
  "generated_at": "2026-02-11T12:00:00Z",
  "summary": {
    "total_namespaces": 8,
    "hardened": 6,
    "unhardened": 2,
    "violations": 1,
    "warnings": 2
  },
  "namespaces": [
    {
      "name": "payment-service",
      "type": "application",
      "hardened": true,
      "hardened_at": "2026-02-11T11:00:00Z",
      "quota": {
        "cpu": "5",
        "memory": "9Gi",
        "pods": "20"
      },
      "usage": {
        "cpu": "3.2",
        "memory": "5Gi",
        "pods": "8"
      },
      "compliance": "COMPLIANT"
    },
    ...
  ]
}

# Use in dashboards or compliance audits
```

---

## Best Practices

### ✅ Do's

1. **Always measure before hardening** - Wait 30-60 minutes after deployment for VPA data
2. **Use --dry-run first** - Preview changes before applying
3. **Monitor unhardened namespaces** - Set up alerts for 4-hour threshold
4. **Regular verification** - Run `namespace-verify.sh --all` daily
5. **Document updates** - Add comments when using `namespace-update.sh`
6. **Backup before updates** - `namespace-update.sh` does this automatically
7. **Use automation** - Integrate with GitOps (ArgoCD sync hooks)
8. **Label everything** - Add owner/project labels for accountability

### ❌ Don'ts

1. **Don't skip hardening** - Every namespace must be hardened within 4 hours
2. **Don't use --force blindly** - Understand what you're overriding
3. **Don't delete namespaces with workloads** - Use safety checks
4. **Don't manually edit ResourceQuota** - Use `namespace-update.sh` for audit trail
5. **Don't ignore verification warnings** - Address quota exhaustion proactively
6. **Don't bypass VPA/HPA** - Trust measured data over guesses
7. **Don't harden too early** - Wait for representative workload data
8. **Don't ignore orphaned namespaces** - Clean up unused resources

### 🔐 Security Best Practices

1. **Enable VPA/HPA** - Ensures accurate quota calculations
2. **Set sanity check limits** - `--max-cpu-limit` and `--max-memory-limit`
3. **Use admission webhooks** - Kyverno/OPA for temporary limits during unhardened state
4. **Monitor quota bypass attempts** - Alert on manual ResourceQuota edits
5. **Audit all operations** - Log every create/harden/update/delete
6. **Restrict script access** - Only platform team runs namespace-*.sh
7. **Rotate Vault bundles** - Automatic certificate rotation
8. **Review compliance reports** - Weekly review of namespace-verify.sh output

---

## Troubleshooting

### ❓ Common Issues

**Q: Hardening fails with "No workloads detected"**

A: Deploy at least one workload before hardening. The script needs pods to measure.

```bash
# Check for pods
kubectl get pods -n my-app
# If empty, deploy application first
helm install my-app ./chart -n my-app
```

---

**Q: VPA recommendations not available**

A: VPA needs 7 days of data by default. Use `--skip-vpa` to fallback to pod limits.

```bash
# Check VPA age
kubectl get vpa -n my-app -o jsonpath='{.items[0].metadata.creationTimestamp}'

# If < 7 days old, use pod limits
./namespace-hardening.sh --name my-app --skip-vpa
```

---

**Q: Quota too restrictive after hardening**

A: VPA may have measured during low-traffic period. Use `namespace-update.sh` to expand.

```bash
# Check current usage vs quota
kubectl describe resourcequota -n my-app

# If near limit, update
./namespace-update.sh --name my-app --auto
```

---

**Q: Unhardened namespace alert but namespace is deleted**

A: Stale label detection. Verify namespace exists:

```bash
kubectl get namespace my-app
# If doesn't exist, ignore alert (will self-resolve)
```

---

**Q: HPA maxReplicas causes excessive pod quota**

A: HPA may be misconfigured with unrealistic maxReplicas. Review HPA config.

```bash
# Check HPA settings
kubectl get hpa -n my-app -o yaml

# If maxReplicas too high, adjust HPA
kubectl patch hpa my-hpa -n my-app -p '{"spec":{"maxReplicas":10}}'

# Re-harden
./namespace-hardening.sh --name my-app --force
```

---

**Q: namespace-update.sh failed during re-hardening**

A: Quota backup is saved. Restore manually if needed.

```bash
# Find backup
ls /tmp/*-quota-backup.yaml

# Restore
kubectl apply -f /tmp/my-app-quota-backup.yaml
```

---

## Migration from V1 (Legacy namespace.sh)

### 📦 Migration Path

**Old workflow (namespace.sh):**
```bash
# One-step creation with static quotas
./namespace.sh create --name my-app --type application --max-pods 50
```

**New workflow (V2):**
```bash
# Three-step: create → deploy → harden
./namespace-create.sh --name my-app --type application
# ... deploy application ...
./namespace-hardening.sh --name my-app
```

### 🔄 Converting Existing Namespaces

For namespaces created with old `namespace.sh`:

```bash
# Step 1: Add V2 labels (preserve existing quotas)
kubectl label namespace my-app \
  moai.forge.io/managed=true \
  moai.forge.io/hardened=true \
  moai.forge.io/hardened-at=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --overwrite

# Step 2: Verify compliance
./namespace-verify.sh --name my-app

# Step 3: Optionally re-harden with measured quotas
./namespace-hardening.sh --name my-app --force
```

---

## Monitoring & Metrics

### 📊 Prometheus Metrics

Expose these metrics for monitoring:

```prometheus
# Total managed namespaces
moai_managed_namespaces_total{type="application"} 12
moai_managed_namespaces_total{type="middleware"} 3

# Hardening state
moai_hardened_namespaces_total 14
moai_unhardened_namespaces_total 1

# Unhardened age (hours)
moai_unhardened_namespace_age_hours{namespace="new-app"} 2.5

# Quota usage percentage
moai_namespace_cpu_usage_percent{namespace="payment-service"} 64
moai_namespace_memory_usage_percent{namespace="payment-service"} 55
moai_namespace_pods_usage_percent{namespace="payment-service"} 40

# Violations
moai_namespace_violations_total 1
```

### 🚨 Alerting Rules

```yaml
# Alert on unhardened namespaces
- alert: NamespaceUnhardenedTooLong
  expr: moai_unhardened_namespace_age_hours > 4
  for: 15m
  labels:
    severity: critical
  annotations:
    summary: "Namespace {{ $labels.namespace }} unhardened for {{ $value }} hours"
    action: "./namespace-hardening.sh --name {{ $labels.namespace }}"

# Alert on quota exhaustion
- alert: NamespaceQuotaNearLimit
  expr: moai_namespace_cpu_usage_percent > 90 OR moai_namespace_memory_usage_percent > 90
  for: 30m
  labels:
    severity: warning
  annotations:
    summary: "Namespace {{ $labels.namespace }} near quota limit"
    action: "./namespace-update.sh --name {{ $labels.namespace }} --auto"

# Alert on orphaned namespaces
- alert: NamespaceOrphaned
  expr: moai_namespace_pods_count == 0 AND time() - moai_namespace_last_pod_timestamp > 2592000
  labels:
    severity: info
  annotations:
    summary: "Namespace {{ $labels.namespace }} empty for 30+ days"
    action: "Review: ./namespace-delete.sh --name {{ $labels.namespace }}"
```

---

## Future Enhancements

### 🚀 Roadmap

1. **GitOps Integration**
   - ArgoCD sync hooks for automatic hardening
   - FluxCD PostBuild notifications
   - Automated namespace-verify.sh on sync

2. **Cost Optimization**
   - FinOps metrics (CPU/memory cost per namespace)
   - Idle resource detection
   - Right-sizing recommendations beyond VPA

3. **Multi-Cluster Support**
   - Centralized namespace registry
   - Cross-cluster quota policies
   - Federated compliance reporting

4. **Advanced Autoscaling**
   - KEDA integration for pod count calculation
   - Cluster autoscaler coordination
   - Predictive quota scaling (time-series ML)

5. **Policy as Code**
   - OPA/Kyverno policy generation
   - Automated PSS escalation requests
   - Compliance-as-code (SOC2, PCI-DSS)

---

## References

- [Kubernetes ResourceQuota Documentation](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Goldilocks](https://github.com/FairwindsOps/goldilocks)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

**Document Version:** 2.0.0  
**Last Updated:** 2026-02-11  
**Author:** Forge Platform Team  
**Status:** Active
