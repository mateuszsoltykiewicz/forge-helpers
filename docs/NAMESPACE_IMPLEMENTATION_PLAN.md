# Forge Namespace Operations - Implementation Plan

**Date:** 2026-02-12  
**Project:** forge-helpers  
**Epic:** Namespace Hardening V2 (Deploy → Measure → Harden)

---

## 📋 Executive Summary

**Goal:** Implement namespace hardening system based on V2 architecture (dynamic measurement vs static quotas)

**Deliverables:**
1. Core library: `lib/forge-namespace-operations.sh`
2. 5 operational scripts:
   - `scripts/namespace-create.sh`
   - `scripts/namespace-update.sh`
   - `scripts/namespace-hardening.sh`
   - `scripts/namespace-verify.sh`
   - `scripts/namespace-delete.sh`
3. Comprehensive testing (unit → integration → end-to-end)

**Timeline:** 5 phases with testing checkpoints

---

## 🏗️ Phase 1: Foundation - Core Library

### 1.1 Create `lib/forge-namespace-operations.sh`

**Dependencies:**
- `lib/forge-core.sh` (logging, validation, retry logic)
- `lib/forge-k8s-operations.sh` (kubectl wrappers, if exists)

**Functions to Implement:**

#### Namespace Management
```bash
create_namespace()              # Create namespace with labels
delete_namespace()              # Delete namespace with safety checks
namespace_exists()              # Check if namespace exists
get_namespace_type()            # Get namespace type from label
get_namespace_age()             # Calculate age since creation
is_namespace_hardened()         # Check hardening status
```

#### Label Management
```bash
apply_namespace_labels()        # Apply moai.forge.io/* labels
update_hardening_status()       # Update hardening labels
get_namespace_label()           # Read specific label
validate_namespace_type()       # Validate type against allowed list
```

#### Resource Measurement
```bash
measure_namespace_resources()   # Main measurement orchestrator
get_namespace_vpa_recommendations()     # VPA detection (namespace-wide)
get_namespace_hpa_max_pods()            # HPA max pods calculation
calculate_namespace_hpa_cpu_needs()     # HPA CPU with non-HPA workloads
calculate_non_hpa_cpu()                 # Non-HPA CPU calculation
count_non_hpa_pods()                    # Count non-HPA pods
sum_namespace_pod_cpu_limits()          # Fallback: sum pod CPU
sum_namespace_pod_memory_limits()       # Fallback: sum pod memory
```

#### Unit Conversion
```bash
convert_cpu_to_millicores()     # cores/m → millicores
convert_cpu_to_cores()          # millicores → cores
convert_memory_to_bytes()       # Ki/Mi/Gi/Ti → bytes
convert_bytes_to_human()        # bytes → 10Gi format
parse_k8s_quantity()            # Generic K8s quantity parser
```

#### DaemonSet Max Capacity
```bash
get_max_node_capacity()         # Detect max nodes (Karpenter/ASG/ConfigMap)
get_karpenter_max_nodes()       # Parse Karpenter NodePools
get_autoscaler_max_nodes()      # AWS/GCP/Azure autoscaler
get_max_gpu_nodes()             # GPU-specific max capacity
estimate_max_for_selector()     # Proportional estimation
```

#### ResourceQuota Operations
```bash
apply_resource_quota()          # Create/update ResourceQuota
remove_resource_quota()         # Delete quota
backup_resource_quota()         # Save quota to file
verify_resource_quota()         # Check quota exists and matches
get_quota_usage()               # Get current usage vs limits
```

#### NetworkPolicy Operations
```bash
apply_network_policy()          # Create default-deny policy
remove_network_policy()         # Delete network policy
get_namespace_network_policy()  # Get policy template by type
```

#### Vault Operations
```bash
create_vault_bundle()           # Create Vault secret bundle
verify_vault_bundle()           # Verify Vault secrets exist
delete_vault_bundle()           # Remove Vault bundle
```

#### Validation & Verification
```bash
verify_namespace_hardening()    # Complete compliance check
check_pss_labels()              # Pod Security Standards verification
check_quota_compliance()        # Verify quota not exceeded
detect_hardening_drift()        # Detect removed/modified resources
generate_compliance_report()    # Generate verification report
```

**Unit Tests for Phase 1:**
```bash
# tests/unit/test-namespace-operations-lib.sh

test_namespace_exists()
test_convert_cpu_to_millicores()
test_convert_memory_to_bytes()
test_validate_namespace_type()
test_get_namespace_age()
test_is_namespace_hardened()
test_parse_k8s_quantity()
```

**Success Criteria:**
- [ ] All 40+ functions implemented
- [ ] All functions have error handling
- [ ] All functions log appropriately (log_debug/info/warn/error)
- [ ] Unit tests pass (mocked kubectl calls)

---

## 🏗️ Phase 2: Script Implementation (Part 1)

### 2.1 `scripts/namespace-create.sh`

**Purpose:** Create namespace WITHOUT hardening (permissive state)

**Arguments:**
```bash
--name <namespace>          # Required: namespace name
--type <type>               # Required: application|middleware|forge-operator|forge-jobs|keda|vault|system...
--owner <team>              # Optional: owning team
--project <project>         # Optional: project name
--environment <env>         # Optional: dev|staging|production
--dry-run                   # Optional: preview without creating
```

**Workflow:**
1. Validate arguments (name, type)
2. Check namespace doesn't already exist
3. Create namespace with labels:
   - `moai.forge.io/managed: "true"`
   - `moai.forge.io/type: <type>`
   - `moai.forge.io/hardened: "false"`
   - `moai.forge.io/created-at: <timestamp>`
   - `moai.forge.io/owner: <team>`
   - `moai.forge.io/project: <project>`
4. Apply PSS labels (permissive initially):
   - `pod-security.kubernetes.io/enforce: baseline`
   - `pod-security.kubernetes.io/audit: restricted`
   - `pod-security.kubernetes.io/warn: restricted`
5. **DO NOT** apply ResourceQuota, NetworkPolicy, or Vault
6. Log success with next steps

**Output:**
```
[INFO] Creating namespace: my-app (type: application)
[INFO] Labels applied:
  moai.forge.io/managed: true
  moai.forge.io/type: application
  moai.forge.io/hardened: false
  moai.forge.io/owner: platform-team
[INFO] Pod Security Standards: baseline (enforce)
[SUCCESS] Namespace created successfully
[INFO] Next steps:
  1. Deploy your application: helm install my-app ./chart -n my-app
  2. Wait 4-7 days for VPA/HPA metrics to mature
  3. Run hardening: ./namespace-hardening.sh --name my-app
```

**Unit Tests:**
```bash
# tests/unit/test-namespace-create.sh

test_create_basic_namespace()
test_create_with_all_options()
test_create_duplicate_namespace_fails()
test_create_invalid_type_fails()
test_create_dry_run()
test_create_applies_correct_labels()
```

---

### 2.2 `scripts/namespace-update.sh`

**Purpose:** Update namespace labels/metadata (not hardening)

**Arguments:**
```bash
--name <namespace>          # Required
--owner <team>              # Optional: update owner
--project <project>         # Optional: update project
--add-label <key=value>     # Optional: add custom label
--remove-label <key>        # Optional: remove label
--dry-run                   # Optional
```

**Workflow:**
1. Validate namespace exists and is managed
2. Apply label updates
3. Log changes

**Unit Tests:**
```bash
test_update_owner()
test_update_project()
test_add_custom_label()
test_remove_label()
test_update_unmanaged_namespace_fails()
```

---

## 🏗️ Phase 3: Script Implementation (Part 2)

### 3.1 `scripts/namespace-hardening.sh` ⭐ **CORE SCRIPT**

**Purpose:** Measure resources and apply hardening (quota, policy, PSS, Vault)

**Arguments:**
```bash
--name <namespace>              # Required
--grace-period <duration>       # Optional: 4h (wait before hardening)
--buffer-percent <percent>      # Optional: 20 (safety buffer)
--min-vpa-age-days <days>       # Optional: 7 (minimum VPA data age)
--force                         # Optional: skip safety checks
--dry-run                       # Optional: show what would be applied
--skip-vault                    # Optional: skip Vault bundle creation
--skip-network-policy           # Optional: skip NetworkPolicy
```

**Workflow:**

1. **Pre-flight Checks:**
   ```bash
   - Namespace exists and is managed
   - If grace-period specified, check namespace age
   - Namespace not already hardened (unless --force)
   - At least one workload deployed (Deployment/StatefulSet/DaemonSet)
   ```

2. **Resource Measurement (Priority Waterfall):**
   ```bash
   # TIER 1: Goldilocks (if available)
   if has_goldilocks_recommendations; then
     cpu=$(get_goldilocks_cpu)
     memory=$(get_goldilocks_memory)
     source="goldilocks"
   
   # TIER 2: VPA upperBound
   elif has_vpa_resources; then
     validate_vpa_data_age >= 7 days
     cpu=$(get_namespace_vpa_recommendations | awk '{print $1}')
     memory=$(get_namespace_vpa_recommendations | awk '{print $2}')
     source="vpa"
   
   # TIER 3: HPA maxReplicas × pod limits
   elif has_hpa_resources; then
     cpu=$(calculate_namespace_hpa_cpu_needs)
     memory=$(calculate_namespace_hpa_memory_needs)
     pods=$(get_namespace_hpa_max_pods)
     source="hpa"
   
   # TIER 4: Pod resources.limits (fallback)
   else
     cpu=$(sum_namespace_pod_cpu_limits)
     memory=$(sum_namespace_pod_memory_limits)
     pods=$(count_namespace_pods)
     source="pod-limits"
   fi
   ```

3. **Apply Safety Buffer:**
   ```bash
   cpu_with_buffer=$((cpu * (100 + buffer_percent) / 100))
   memory_with_buffer=$((memory * (100 + buffer_percent) / 100))
   pods_with_buffer=$((pods + 5))  # Fixed buffer for pods
   ```

4. **Sanity Checks:**
   ```bash
   if [[ $cpu_with_buffer -gt 64000 ]]; then  # 64 cores max
     log_error "Calculated CPU exceeds sanity limit: ${cpu_with_buffer}m (64 cores)"
     exit 1
   fi
   
   if [[ $memory_with_buffer -gt 137438953472 ]]; then  # 128Gi
     log_error "Calculated memory exceeds sanity limit"
     exit 1
   fi
   ```

5. **Apply Hardening:**
   ```bash
   # ResourceQuota
   apply_resource_quota "$namespace" "$cpu_with_buffer" "$memory_with_buffer" "$pods_with_buffer"
   
   # NetworkPolicy (default-deny)
   apply_network_policy "$namespace"
   
   # Pod Security Standards (enforce: restricted)
   kubectl label namespace "$namespace" \
     pod-security.kubernetes.io/enforce=restricted --overwrite
   
   # Vault bundle (application type only)
   if [[ "$type" == "application" ]] && [[ "$skip_vault" != "true" ]]; then
     create_vault_bundle "$namespace"
   fi
   ```

6. **Update Labels:**
   ```bash
   kubectl label namespace "$namespace" \
     moai.forge.io/hardened=true \
     moai.forge.io/hardened-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     moai.forge.io/hardening-source="$source" \
     moai.forge.io/quota-cpu-limit="${cpu_with_buffer}m" \
     moai.forge.io/quota-memory-limit="$(convert_bytes_to_human $memory_with_buffer)" \
     moai.forge.io/quota-pods-limit="$pods_with_buffer" \
     --overwrite
   ```

7. **Summary Output:**
   ```
   [SUCCESS] Namespace hardened: my-app
   
   Measurement Source: VPA (7 days of data)
   
   Resources Measured:
     CPU:     15000m (15 cores)
     Memory:  30Gi
     Pods:    25
   
   Safety Buffer: 20%
   
   Resources Applied (ResourceQuota):
     CPU:     18000m (18 cores)  [+20%]
     Memory:  36Gi               [+20%]
     Pods:    30                 [+5]
   
   Hardening Applied:
     ✓ ResourceQuota created
     ✓ NetworkPolicy (default-deny) created
     ✓ Pod Security Standards: restricted (enforced)
     ✓ Vault bundle created
   
   Labels Updated:
     moai.forge.io/hardened: true
     moai.forge.io/hardened-at: 2026-02-12T14:30:00Z
     moai.forge.io/hardening-source: vpa
     moai.forge.io/quota-cpu-limit: 18000m
   
   [INFO] Namespace is now locked. Monitor quota usage:
     kubectl describe resourcequota -n my-app
   ```

**Unit Tests:**
```bash
test_hardening_with_vpa()
test_hardening_with_hpa()
test_hardening_with_pod_limits_fallback()
test_hardening_dry_run()
test_hardening_already_hardened_fails()
test_hardening_force_overrides_existing()
test_hardening_grace_period_not_met_fails()
test_hardening_vpa_data_too_young_fails()
test_hardening_sanity_check_exceeds_max()
test_hardening_skip_vault()
```

---

### 3.2 `scripts/namespace-verify.sh`

**Purpose:** Verify namespace hardening compliance

**Arguments:**
```bash
--name <namespace>          # Required (or --all)
--all                       # Check all managed namespaces
--unhardened-only           # Only show unhardened namespaces
--drift-only                # Only show namespaces with drift
--report <file>             # Output report to file
```

**Workflow:**

1. **Hardening Status Check:**
   ```bash
   is_hardened=$(get_namespace_label "$namespace" "moai.forge.io/hardened")
   
   if [[ "$is_hardened" == "false" ]]; then
     age=$(get_namespace_age "$namespace")
     if [[ $age -gt $((4 * 3600)) ]]; then  # 4 hours
       log_warn "Namespace unhardened beyond grace period: ${namespace} (age: ${age}s)"
     fi
   fi
   ```

2. **Drift Detection:**
   ```bash
   # Check ResourceQuota exists
   if ! kubectl get resourcequota -n "$namespace" -l 'moai.forge.io/managed=true' > /dev/null 2>&1; then
     log_error "DRIFT: ResourceQuota missing in $namespace"
     drift_detected=true
   fi
   
   # Check NetworkPolicy exists
   if ! kubectl get networkpolicy -n "$namespace" -l 'moai.forge.io/managed=true' > /dev/null 2>&1; then
     log_error "DRIFT: NetworkPolicy missing in $namespace"
     drift_detected=true
   fi
   
   # Check PSS labels
   enforce_label=$(kubectl get namespace "$namespace" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
   if [[ "$enforce_label" != "restricted" ]]; then
     log_error "DRIFT: PSS enforce label incorrect: $enforce_label (expected: restricted)"
     drift_detected=true
   fi
   ```

3. **Quota Usage Check:**
   ```bash
   quota_usage=$(kubectl get resourcequota -n "$namespace" -o json | jq -r '.items[0].status')
   
   cpu_used=$(echo "$quota_usage" | jq -r '.used."limits.cpu"')
   cpu_limit=$(echo "$quota_usage" | jq -r '.hard."limits.cpu"')
   
   cpu_percent=$((cpu_used * 100 / cpu_limit))
   
   if [[ $cpu_percent -gt 80 ]]; then
     log_warn "Quota usage high: CPU ${cpu_percent}% (${cpu_used}/${cpu_limit})"
   fi
   ```

4. **Generate Report:**
   ```json
   {
     "namespace": "my-app",
     "managed": true,
     "hardened": true,
     "hardened_at": "2026-02-12T14:30:00Z",
     "age_hours": 48,
     "drift_detected": false,
     "quota_usage": {
       "cpu": {"used": "12000m", "limit": "18000m", "percent": 66},
       "memory": {"used": "24Gi", "limit": "36Gi", "percent": 66},
       "pods": {"used": 22, "limit": 30, "percent": 73}
     },
     "compliance": "PASS"
   }
   ```

**Unit Tests:**
```bash
test_verify_hardened_namespace()
test_verify_unhardened_namespace()
test_verify_detect_quota_drift()
test_verify_detect_networkpolicy_drift()
test_verify_detect_pss_drift()
test_verify_quota_usage_warning()
test_verify_all_namespaces()
test_verify_report_generation()
```

---

### 3.3 `scripts/namespace-delete.sh`

**Purpose:** Safely delete namespace

**Arguments:**
```bash
--name <namespace>          # Required
--force                     # Skip safety checks
--keep-resources            # Remove hardening but keep namespace
--dry-run                   # Preview deletion
```

**Workflow:**

1. **Safety Checks:**
   ```bash
   # Check namespace is managed
   if ! is_namespace_managed "$namespace"; then
     log_error "Refusing to delete unmanaged namespace: $namespace"
     exit 1
   fi
   
   # Check for running workloads
   workload_count=$(kubectl get deploy,sts,ds -n "$namespace" --no-headers 2>/dev/null | wc -l)
   if [[ $workload_count -gt 0 ]] && [[ "$force" != "true" ]]; then
     log_error "Namespace has $workload_count workloads. Use --force to override"
     exit 1
   fi
   ```

2. **Remove Hardening (if --keep-resources):**
   ```bash
   kubectl delete resourcequota -n "$namespace" -l 'moai.forge.io/managed=true'
   kubectl delete networkpolicy -n "$namespace" -l 'moai.forge.io/managed=true'
   kubectl label namespace "$namespace" moai.forge.io/hardened=false --overwrite
   ```

3. **Delete Namespace:**
   ```bash
   kubectl delete namespace "$namespace"
   ```

4. **Cleanup Vault (if exists):**
   ```bash
   delete_vault_bundle "$namespace"
   ```

**Unit Tests:**
```bash
test_delete_empty_namespace()
test_delete_with_workloads_fails()
test_delete_force_with_workloads()
test_delete_keep_resources()
test_delete_unmanaged_namespace_fails()
test_delete_dry_run()
```

---

## 🏗️ Phase 4: Integration Testing

### 4.1 Test Environment Setup

**Prerequisites:**
```bash
# Kubernetes cluster (kind/minikube/EKS dev cluster)
kubectl cluster-info

# Karpenter (for max node detection) - optional
kubectl get crd nodepools.karpenter.sh

# VPA operator (for VPA testing)
kubectl get crd verticalpodautoscalers.autoscaling.k8s.io

# Metrics server (for HPA)
kubectl get deployment metrics-server -n kube-system

# Goldilocks (optional)
kubectl get deployment goldilocks-controller -n goldilocks
```

**Test Namespace Sandbox:**
```bash
# Create test sandbox directory
mkdir -p ~/forge-test-sandbox
cd ~/forge-test-sandbox

# Copy helm chart for testing
cp -r /Users/mateuszsoltykiewicz/Documents/application-service/deployment/helm/service-chart ./test-app-chart

# Modify values for test-1, test-2
cat > test-1-values.yaml <<EOF
global:
  environment: dev
  serviceName: test-1

image:
  repository: nginx
  tag: "1.25"

replicaCount: 3

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

goldilocks:
  enabled: true

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
EOF

cat > test-2-values.yaml <<EOF
global:
  environment: dev
  serviceName: test-2

image:
  repository: nginx
  tag: "1.25"

replicaCount: 2

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

goldilocks:
  enabled: false

autoscaling:
  enabled: false
EOF
```

### 4.2 Integration Test Scenarios

#### Scenario 1: Basic Workflow (No VPA/HPA)
```bash
# Test: namespace-create.sh + namespace-hardening.sh + namespace-verify.sh

# Step 1: Create namespace
./scripts/namespace-create.sh \
  --name test-basic \
  --type application \
  --owner platform-team \
  --project forge-test

# Verify: Labels applied correctly
kubectl get namespace test-basic -o yaml | grep 'moai.forge.io'

# Step 2: Deploy simple workload (no HPA/VPA)
kubectl create deployment nginx --image=nginx:1.25 -n test-basic
kubectl set resources deployment nginx -n test-basic \
  --limits=cpu=200m,memory=256Mi \
  --requests=cpu=100m,memory=128Mi

# Step 3: Harden (should use pod limits fallback)
./scripts/namespace-hardening.sh \
  --name test-basic \
  --buffer-percent 20

# Verify: ResourceQuota created
kubectl describe resourcequota -n test-basic

# Expected quota:
# CPU: 240m (200m + 20%)
# Memory: 307Mi (256Mi + 20%)

# Step 4: Verify compliance
./scripts/namespace-verify.sh --name test-basic

# Expected: PASS, no drift

# Cleanup
./scripts/namespace-delete.sh --name test-basic --force
```

#### Scenario 2: HPA-Based Hardening
```bash
# Test: Hardening with HPA maxReplicas

# Step 1: Create namespace
./scripts/namespace-create.sh \
  --name test-hpa \
  --type application

# Step 2: Deploy with HPA
helm install test-hpa ./test-app-chart -n test-hpa -f test-1-values.yaml

# Verify HPA created
kubectl get hpa -n test-hpa

# Expected: minReplicas=3, maxReplicas=10

# Step 3: Wait 10 seconds for HPA to stabilize
sleep 10

# Step 4: Harden (should detect HPA)
./scripts/namespace-hardening.sh --name test-hpa

# Expected calculation:
# - HPA maxReplicas: 10
# - Pod CPU limit: 500m
# - Total: 10 × 500m = 5000m (5 cores)
# - With 20% buffer: 6000m (6 cores)

# Verify quota
kubectl get resourcequota -n test-hpa -o yaml | grep 'limits.cpu'

# Expected: "6" or "6000m"

# Step 5: Scale up and verify quota prevents over-scaling
kubectl scale deployment test-hpa -n test-hpa --replicas=12

# Expected: Some pods should be Pending due to quota

# Step 6: Verify
./scripts/namespace-verify.sh --name test-hpa

# Cleanup
./scripts/namespace-delete.sh --name test-hpa --force
```

#### Scenario 3: VPA-Based Hardening
```bash
# Test: Hardening with VPA recommendations

# Step 1: Create namespace
./scripts/namespace-create.sh --name test-vpa --type application

# Step 2: Deploy workload
helm install test-vpa ./test-app-chart -n test-vpa -f test-2-values.yaml

# Step 3: Create VPA manually (simulate 7 days of data)
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: test-vpa
  namespace: test-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: test-vpa
  updatePolicy:
    updateMode: "Off"  # Recommendations only
status:
  recommendation:
    containerRecommendations:
    - containerName: service
      upperBound:
        cpu: 800m
        memory: 1Gi
      target:
        cpu: 600m
        memory: 768Mi
  conditions:
  - type: RecommendationProvided
    status: "True"
    lastTransitionTime: "2026-02-05T00:00:00Z"  # 7 days ago
EOF

# Step 4: Harden (should use VPA upperBound)
./scripts/namespace-hardening.sh --name test-vpa

# Expected calculation:
# - VPA upperBound CPU: 800m per pod
# - Replicas: 2
# - Total: 2 × 800m = 1600m
# - With 20% buffer: 1920m (~2 cores)

# Verify
kubectl describe resourcequota -n test-vpa

# Cleanup
./scripts/namespace-delete.sh --name test-vpa --force
```

#### Scenario 4: Drift Detection & Remediation
```bash
# Test: Verify detects deleted quota

# Step 1: Create and harden
./scripts/namespace-create.sh --name test-drift --type application
kubectl create deployment nginx --image=nginx -n test-drift
./scripts/namespace-hardening.sh --name test-drift

# Step 2: Verify initially compliant
./scripts/namespace-verify.sh --name test-drift
# Expected: PASS

# Step 3: Delete ResourceQuota (simulate drift)
kubectl delete resourcequota -n test-drift --all

# Step 4: Verify detects drift
./scripts/namespace-verify.sh --name test-drift
# Expected: FAIL, drift detected

# Step 5: Re-harden (remediation)
./scripts/namespace-hardening.sh --name test-drift --force

# Step 6: Verify fixed
./scripts/namespace-verify.sh --name test-drift
# Expected: PASS

# Cleanup
./scripts/namespace-delete.sh --name test-drift --force
```

#### Scenario 5: Update Labels
```bash
# Test: namespace-update.sh

# Step 1: Create namespace
./scripts/namespace-create.sh --name test-update --type application --owner team-a

# Step 2: Verify initial labels
kubectl get namespace test-update -o jsonpath='{.metadata.labels.moai\.forge\.io/owner}'
# Expected: team-a

# Step 3: Update owner
./scripts/namespace-update.sh --name test-update --owner team-b

# Step 4: Verify updated
kubectl get namespace test-update -o jsonpath='{.metadata.labels.moai\.forge\.io/owner}'
# Expected: team-b

# Step 5: Add custom label
./scripts/namespace-update.sh --name test-update --add-label 'custom.io/foo=bar'

# Verify
kubectl get namespace test-update -o jsonpath='{.metadata.labels.custom\.io/foo}'
# Expected: bar

# Cleanup
./scripts/namespace-delete.sh --name test-update --force
```

### 4.3 Integration Test Summary

**Create test runner:**
```bash
#!/bin/bash
# tests/integration/run-all-integration-tests.sh

set -euo pipefail

source lib/forge-core.sh

log_info "Running integration tests..."

# Run all scenarios
./tests/integration/scenario-1-basic.sh
./tests/integration/scenario-2-hpa.sh
./tests/integration/scenario-3-vpa.sh
./tests/integration/scenario-4-drift.sh
./tests/integration/scenario-5-update.sh

log_info "All integration tests passed!"
```

---

## 🏗️ Phase 5: End-to-End Testing

### 5.1 E2E Scenario: Complete Lifecycle

**Scenario:** Production-like workflow with VPA → Hardening → Monitoring → Scaling → Verification

```bash
#!/bin/bash
# tests/e2e/test-complete-lifecycle.sh

set -euo pipefail

E2E_NAMESPACE="e2e-test-$(date +%s)"
HELM_RELEASE="e2e-app"

log_info "=== E2E Test: Complete Namespace Lifecycle ==="

# ============================================================================
# PHASE 1: NAMESPACE CREATION
# ============================================================================

log_info "PHASE 1: Creating namespace..."

./scripts/namespace-create.sh \
  --name "$E2E_NAMESPACE" \
  --type application \
  --owner e2e-test-team \
  --project forge-validation \
  --environment dev

# Verify namespace exists
if ! kubectl get namespace "$E2E_NAMESPACE" > /dev/null 2>&1; then
  log_error "Namespace creation failed"
  exit 1
fi

# Verify labels
hardened=$(kubectl get namespace "$E2E_NAMESPACE" -o jsonpath='{.metadata.labels.moai\.forge\.io/hardened}')
if [[ "$hardened" != "false" ]]; then
  log_error "Expected hardened=false, got: $hardened"
  exit 1
fi

log_info "✓ Namespace created successfully (unhardened)"

# ============================================================================
# PHASE 2: APPLICATION DEPLOYMENT
# ============================================================================

log_info "PHASE 2: Deploying application with VPA and HPA..."

helm install "$HELM_RELEASE" ./test-app-chart \
  -n "$E2E_NAMESPACE" \
  -f test-1-values.yaml \
  --wait --timeout 5m

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l "app.kubernetes.io/name=$HELM_RELEASE" \
  -n "$E2E_NAMESPACE" \
  --timeout=300s

# Verify HPA created
if ! kubectl get hpa -n "$E2E_NAMESPACE" > /dev/null 2>&1; then
  log_error "HPA not created"
  exit 1
fi

log_info "✓ Application deployed (3 replicas, HPA enabled)"

# ============================================================================
# PHASE 3: VPA SETUP (Simulate 7 days of data)
# ============================================================================

log_info "PHASE 3: Creating VPA with historical recommendations..."

cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: $HELM_RELEASE
  namespace: $E2E_NAMESPACE
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $HELM_RELEASE
  updatePolicy:
    updateMode: "Off"
status:
  recommendation:
    containerRecommendations:
    - containerName: service
      upperBound:
        cpu: 600m
        memory: 768Mi
      target:
        cpu: 400m
        memory: 512Mi
  conditions:
  - type: RecommendationProvided
    status: "True"
    lastTransitionTime: "$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)"
EOF

log_info "✓ VPA created with 8 days of historical data"

# ============================================================================
# PHASE 4: NAMESPACE HARDENING
# ============================================================================

log_info "PHASE 4: Hardening namespace..."

./scripts/namespace-hardening.sh \
  --name "$E2E_NAMESPACE" \
  --buffer-percent 25 \
  --min-vpa-age-days 7

# Verify hardening labels updated
hardened=$(kubectl get namespace "$E2E_NAMESPACE" -o jsonpath='{.metadata.labels.moai\.forge\.io/hardened}')
if [[ "$hardened" != "true" ]]; then
  log_error "Expected hardened=true, got: $hardened"
  exit 1
fi

# Verify ResourceQuota created
if ! kubectl get resourcequota -n "$E2E_NAMESPACE" -l 'moai.forge.io/managed=true' > /dev/null 2>&1; then
  log_error "ResourceQuota not created"
  exit 1
fi

# Verify NetworkPolicy created
if ! kubectl get networkpolicy -n "$E2E_NAMESPACE" -l 'moai.forge.io/managed=true' > /dev/null 2>&1; then
  log_error "NetworkPolicy not created"
  exit 1
fi

log_info "✓ Namespace hardened successfully"

# Show quota
kubectl describe resourcequota -n "$E2E_NAMESPACE"

# ============================================================================
# PHASE 5: VERIFICATION
# ============================================================================

log_info "PHASE 5: Verifying compliance..."

./scripts/namespace-verify.sh --name "$E2E_NAMESPACE" --report /tmp/e2e-report.json

# Check report
compliance=$(jq -r '.compliance' /tmp/e2e-report.json)
if [[ "$compliance" != "PASS" ]]; then
  log_error "Compliance check failed: $compliance"
  cat /tmp/e2e-report.json
  exit 1
fi

log_info "✓ Compliance verification passed"

# ============================================================================
# PHASE 6: DRIFT SIMULATION & DETECTION
# ============================================================================

log_info "PHASE 6: Testing drift detection..."

# Delete ResourceQuota
kubectl delete resourcequota -n "$E2E_NAMESPACE" --all

# Verify detects drift
./scripts/namespace-verify.sh --name "$E2E_NAMESPACE" --report /tmp/e2e-drift-report.json

drift=$(jq -r '.drift_detected' /tmp/e2e-drift-report.json)
if [[ "$drift" != "true" ]]; then
  log_error "Drift not detected"
  exit 1
fi

log_info "✓ Drift detected correctly"

# Remediate
./scripts/namespace-hardening.sh --name "$E2E_NAMESPACE" --force

# Verify fixed
./scripts/namespace-verify.sh --name "$E2E_NAMESPACE" --report /tmp/e2e-remediated-report.json

compliance=$(jq -r '.compliance' /tmp/e2e-remediated-report.json)
if [[ "$compliance" != "PASS" ]]; then
  log_error "Remediation failed"
  exit 1
fi

log_info "✓ Drift remediated successfully"

# ============================================================================
# PHASE 7: SCALING TEST
# ============================================================================

log_info "PHASE 7: Testing quota enforcement during scaling..."

# Try to scale beyond HPA max
kubectl scale deployment "$HELM_RELEASE" -n "$E2E_NAMESPACE" --replicas=15

# Wait 30 seconds
sleep 30

# Check how many pods actually running
running_pods=$(kubectl get pods -n "$E2E_NAMESPACE" --field-selector=status.phase=Running --no-headers | wc -l)
pending_pods=$(kubectl get pods -n "$E2E_NAMESPACE" --field-selector=status.phase=Pending --no-headers | wc -l)

log_info "Running pods: $running_pods, Pending pods: $pending_pods"

if [[ $pending_pods -eq 0 ]]; then
  log_warn "Expected some pods to be pending due to quota, but all are running"
  log_warn "This may indicate quota is too generous or pods are very small"
fi

log_info "✓ Scaling test completed"

# ============================================================================
# PHASE 8: LABEL UPDATE TEST
# ============================================================================

log_info "PHASE 8: Testing label updates..."

./scripts/namespace-update.sh \
  --name "$E2E_NAMESPACE" \
  --owner updated-team \
  --project updated-project

owner=$(kubectl get namespace "$E2E_NAMESPACE" -o jsonpath='{.metadata.labels.moai\.forge\.io/owner}')
if [[ "$owner" != "updated-team" ]]; then
  log_error "Label update failed: expected 'updated-team', got '$owner'"
  exit 1
fi

log_info "✓ Labels updated successfully"

# ============================================================================
# PHASE 9: CLEANUP
# ============================================================================

log_info "PHASE 9: Cleaning up..."

./scripts/namespace-delete.sh --name "$E2E_NAMESPACE" --force

# Verify deleted
if kubectl get namespace "$E2E_NAMESPACE" > /dev/null 2>&1; then
  log_error "Namespace deletion failed"
  exit 1
fi

log_info "✓ Namespace deleted successfully"

# ============================================================================
# SUMMARY
# ============================================================================

log_info "=== E2E Test Summary ==="
log_info "✓ PHASE 1: Namespace creation"
log_info "✓ PHASE 2: Application deployment"
log_info "✓ PHASE 3: VPA setup"
log_info "✓ PHASE 4: Namespace hardening"
log_info "✓ PHASE 5: Compliance verification"
log_info "✓ PHASE 6: Drift detection & remediation"
log_info "✓ PHASE 7: Quota enforcement during scaling"
log_info "✓ PHASE 8: Label updates"
log_info "✓ PHASE 9: Cleanup"
log_info ""
log_info "🎉 E2E TEST PASSED!"
```

---

## 📋 Implementation Checklist

### Phase 1: Foundation ✅
- [ ] Create `lib/forge-namespace-operations.sh`
- [ ] Implement namespace management functions (10 functions)
- [ ] Implement resource measurement functions (15 functions)
- [ ] Implement unit conversion functions (5 functions)
- [ ] Implement DaemonSet max capacity functions (5 functions)
- [ ] Implement quota/policy/vault functions (10 functions)
- [ ] Implement verification functions (5 functions)
- [ ] Write unit tests for library
- [ ] All unit tests pass

### Phase 2: Scripts (Part 1) ✅
- [ ] Implement `namespace-create.sh`
- [ ] Write unit tests for create script
- [ ] Implement `namespace-update.sh`
- [ ] Write unit tests for update script

### Phase 3: Scripts (Part 2) ✅
- [ ] Implement `namespace-hardening.sh` (CORE)
- [ ] Write unit tests for hardening script
- [ ] Implement `namespace-verify.sh`
- [ ] Write unit tests for verify script
- [ ] Implement `namespace-delete.sh`
- [ ] Write unit tests for delete script

### Phase 4: Integration Testing ✅
- [ ] Set up test environment (sandbox)
- [ ] Prepare test helm charts (test-1, test-2)
- [ ] Run Scenario 1: Basic workflow
- [ ] Run Scenario 2: HPA-based hardening
- [ ] Run Scenario 3: VPA-based hardening
- [ ] Run Scenario 4: Drift detection
- [ ] Run Scenario 5: Label updates
- [ ] All integration tests pass

### Phase 5: E2E Testing ✅
- [ ] Run complete lifecycle test
- [ ] Verify all 9 phases pass
- [ ] Document any issues found
- [ ] Fix issues and re-run
- [ ] E2E test passes consistently (3 runs)

---

## 📊 Success Criteria

### Library (`forge-namespace-operations.sh`)
- ✅ 50+ functions implemented
- ✅ All functions have error handling (`set -euo pipefail`)
- ✅ All functions log appropriately (debug/info/warn/error)
- ✅ All functions validated with unit tests
- ✅ Documentation comments for each function

### Scripts
- ✅ All 5 scripts executable and functional
- ✅ Proper argument parsing (getopts or manual)
- ✅ Help text (`--help` flag)
- ✅ Dry-run support (`--dry-run` flag)
- ✅ Exit codes follow standards (0=success, >0=error)

### Testing
- ✅ Unit tests: 30+ test cases
- ✅ Integration tests: 5 scenarios
- ✅ E2E test: 9 phases
- ✅ All tests pass on fresh cluster
- ✅ Tests cleanup after themselves

### Documentation
- ✅ README for each script (usage examples)
- ✅ Architecture docs updated
- ✅ Testing guide created
- ✅ Troubleshooting section added

---

## 🚀 Getting Started

### Immediate Next Steps

1. **Review this plan** - confirm approach
2. **Set up test environment** - Kubernetes cluster with VPA/HPA/Karpenter
3. **Start Phase 1** - implement `lib/forge-namespace-operations.sh`
4. **Incremental testing** - test each function as implemented
5. **Iterate through phases** - complete testing at each checkpoint

### Estimated Timeline

| Phase | Estimated Time | Testing Time | Total |
|-------|----------------|--------------|-------|
| Phase 1: Foundation | 4-6 hours | 2 hours | **6-8 hours** |
| Phase 2: Scripts (Part 1) | 2-3 hours | 1 hour | **3-4 hours** |
| Phase 3: Scripts (Part 2) | 4-6 hours | 2 hours | **6-8 hours** |
| Phase 4: Integration Tests | 2 hours | 3 hours | **5 hours** |
| Phase 5: E2E Tests | 1 hour | 2 hours | **3 hours** |
| **TOTAL** | **13-18 hours** | **10 hours** | **23-28 hours** |

**Recommendation:** Spread over 3-4 days with testing checkpoints

---

## ❓ Questions Before Starting

1. **Kubernetes Cluster:**
   - Do you have a dev/test cluster ready?
   - VPA operator installed?
   - Karpenter or Cluster Autoscaler?
   - Goldilocks installed?

2. **Test Data:**
   - Should we use the existing helm chart as-is or create simplified test charts?
   - Do you want to test with real VPA data (wait 7 days) or mock it?

3. **Implementation Preferences:**
   - Start with library then scripts? (recommended)
   - Or implement one script end-to-end then iterate?

4. **Testing Approach:**
   - Manual testing (you run commands)?
   - Automated test scripts (bash test runner)?
   - Or both?

---

**Ready to proceed? Confirm plan and I'll start with Phase 1!**
