# Namespace Hardening Detection: VPA/HPA/Goldilocks Integration

**Technical implementation guide for measuring workload resources and calculating security quotas.**

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Detection Strategy](#detection-strategy)
3. [VPA Integration](#vpa-integration)
4. [HPA Integration](#hpa-integration)
5. [Goldilocks Integration](#goldilocks-integration)
6. [Pod Resource Fallback](#pod-resource-fallback)
7. [Safety Buffers & Validation](#safety-buffers--validation)
8. [Implementation Functions](#implementation-functions)
9. [Testing & Validation](#testing--validation)

---

## Overview

### 🎯 Purpose

The hardening detection system **measures actual workload resource usage** to calculate appropriate ResourceQuota limits, avoiding the problems of static configuration:

**Problems with Static Quotas:**
- ❌ Arbitrary guesses (e.g., "give it 8 CPU")
- ❌ Either too restrictive or too permissive
- ❌ No adaptation to actual workload patterns
- ❌ Ignores autoscaling configurations (VPA/HPA)

**Solution: Dynamic Measurement**
- ✅ Use VPA recommendations (P99 usage + headroom)
- ✅ Account for HPA horizontal scaling (maxReplicas)
- ✅ Integrate Goldilocks observability
- ✅ Fallback to pod resource limits when autoscalers unavailable
- ✅ Apply safety buffer (default 20%) to prevent quota exhaustion

### 📊 Measurement Priority

The system uses a **waterfall detection strategy**:

```
1. Goldilocks recommendations (HIGHEST PRIORITY)
   ↓ (if not available)
2. VPA upperBound
   ↓ (if not available)
3. HPA maxReplicas × Pod limits
   ↓ (if not available)
4. Pod resources.limits (FALLBACK)
```

---

## Detection Strategy

### 🔍 Overall Workflow

```bash
measure_namespace_resources() {
  local namespace="$1"
  
  # 1. Detect what's available
  local has_goldilocks=$(check_goldilocks_enabled "$namespace")
  local has_vpa=$(check_vpa_exists "$namespace")
  local has_hpa=$(check_hpa_exists "$namespace")
  
  # 2. Choose measurement strategy
  if [[ "$has_goldilocks" == "true" ]]; then
    cpu=$(get_goldilocks_cpu_recommendation "$namespace")
    memory=$(get_goldilocks_memory_recommendation "$namespace")
    pods=$(get_goldilocks_pod_count "$namespace")
  elif [[ "$has_vpa" == "true" ]]; then
    cpu=$(get_vpa_total_cpu "$namespace")
    memory=$(get_vpa_total_memory "$namespace")
    pods=$(get_hpa_max_pods "$namespace" || fallback_pod_count "$namespace")
  elif [[ "$has_hpa" == "true" ]]; then
    cpu=$(calculate_hpa_cpu_needs "$namespace")
    memory=$(calculate_hpa_memory_needs "$namespace")
    pods=$(get_hpa_max_pods "$namespace")
  else
    # Fallback: current pod limits
    cpu=$(sum_pod_cpu_limits "$namespace")
    memory=$(sum_pod_memory_limits "$namespace")
    pods=$(count_current_pods "$namespace")
  fi
  
  # 3. Apply safety buffer
  cpu=$(apply_buffer "$cpu" "${BUFFER_PERCENT:-20}")
  memory=$(apply_buffer "$memory" "${BUFFER_PERCENT:-20}")
  pods=$(apply_buffer "$pods" "${BUFFER_PERCENT:-20}")
  
  # 4. Validate sanity checks
  validate_quota_limits "$cpu" "$memory" "$pods"
  
  echo "$cpu $memory $pods"
}
```

### 🛡️ Safety Principles

1. **Over-provision slightly** - 20% buffer prevents quota exhaustion
2. **Round up always** - Ensures quota covers measured usage
3. **Sanity check maximums** - Reject if exceeds cluster limits
4. **Prefer autoscaler data** - VPA/HPA more accurate than static limits
5. **Account for burstiness** - HPA maxReplicas prevents scale-up failures

---

## VPA Integration

### 📐 Vertical Pod Autoscaler Basics

**What VPA Provides:**
- **lowerBound** - Minimum safe resources (P1 usage)
- **target** - Recommended resources (P50 usage)
- **upperBound** - Maximum safe resources (P99 usage + headroom) ← **We use this**

**Why upperBound?**
- Covers 99th percentile usage spikes
- Includes built-in safety margin
- Prevents pod OOM kills and CPU throttling
- Accounts for historical traffic patterns (7-day default window)

### 🔍 Detecting VPA

```bash
check_vpa_exists() {
  local namespace="$1"
  
  # Check if any VPA resources exist in namespace
  local vpa_count=$(kubectl get vpa -n "$namespace" --no-headers 2>/dev/null | wc -l)
  
  if [[ "$vpa_count" -gt 0 ]]; then
    log_info "VPA detected: $vpa_count resources in namespace $namespace"
    echo "true"
    return 0
  else
    log_debug "No VPA resources found in namespace $namespace"
    echo "false"
    return 1
  fi
}

check_vpa_data_age() {
  local namespace="$1"
  local vpa_name="$2"
  local min_age_seconds="${3:-604800}"  # Default: 7 days
  
  # Get VPA creation timestamp
  local created_at=$(kubectl get vpa "$vpa_name" -n "$namespace" \
    -o jsonpath='{.metadata.creationTimestamp}')
  
  local created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null)
  local now_epoch=$(date +%s)
  local age_seconds=$((now_epoch - created_epoch))
  
  if [[ "$age_seconds" -lt "$min_age_seconds" ]]; then
    log_warn "VPA $vpa_name only $((age_seconds / 3600)) hours old (need $((min_age_seconds / 3600)) hours)"
    echo "false"
    return 1
  fi
  
  echo "true"
  return 0
}
```

### 📊 Parsing VPA Recommendations (Namespace-Wide)

**VPA Resource Structure:**
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
  updateMode: Auto  # or "Off" for recommendation-only
status:
  recommendation:
    containerRecommendations:
    - containerName: payment-api
      lowerBound:
        cpu: 500m
        memory: 1Gi
      target:
        cpu: 1500m
        memory: 3Gi
      upperBound:          # ← WE USE THIS
        cpu: 2000m         # ← Maximum safe CPU
        memory: 4Gi        # ← Maximum safe memory
    - containerName: sidecar-proxy
      upperBound:
        cpu: 100m
        memory: 256Mi
```

**Namespace-Wide VPA Aggregation:**

```bash
get_namespace_vpa_recommendations() {
  local namespace="$1"
  local total_cpu_millicores=0
  local total_memory_bytes=0
  
  log_info "Scanning all VPA resources in namespace $namespace..."
  
  # Get ALL VPA resources in namespace (regardless of target)
  local vpa_list=$(kubectl get vpa -n "$namespace" -o json)
  local vpa_count=$(echo "$vpa_list" | jq -r '.items | length')
  
  if [[ "$vpa_count" -eq 0 ]]; then
    log_warn "No VPA resources found in namespace $namespace"
    echo "0 0"
    return 1
  fi
  
  log_info "Found $vpa_count VPA resources in namespace $namespace"
  
  # Iterate through all VPAs in namespace
  for vpa_index in $(seq 0 $((vpa_count - 1))); do
    local vpa_name=$(echo "$vpa_list" | jq -r ".items[$vpa_index].metadata.name")
    local target_kind=$(echo "$vpa_list" | jq -r ".items[$vpa_index].spec.targetRef.kind")
    local target_name=$(echo "$vpa_list" | jq -r ".items[$vpa_index].spec.targetRef.name")
    
    log_debug "Processing VPA: $vpa_name (target: $target_kind/$target_name)"
    
    # Check VPA data age (require at least 7 days)
    if [[ "$(check_vpa_data_age "$namespace" "$vpa_name" 604800)" == "false" ]]; then
      log_warn "VPA $vpa_name recommendations not mature (<7 days), skipping"
      continue
    fi
    
    # Get target workload replica count
    local replica_count=1
    case "$target_kind" in
      "Deployment")
        replica_count=$(kubectl get deployment "$target_name" -n "$namespace" \
          -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        ;;
      "StatefulSet")
        replica_count=$(kubectl get statefulset "$target_name" -n "$namespace" \
          -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        ;;
      "DaemonSet")
        # DaemonSets run one pod per node
        replica_count=$(kubectl get daemonset "$target_name" -n "$namespace" \
          -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "1")
        ;;
    esac
    
    log_debug "$target_kind/$target_name has $replica_count replicas"
    
    # Extract CPU recommendations for all containers in this VPA
    local vpa_cpu_per_pod=0
    local container_cpus=$(echo "$vpa_list" | \
      jq -r ".items[$vpa_index].status.recommendation.containerRecommendations[]? | 
        .upperBound.cpu // \"0m\"")
    
    for cpu_value in $container_cpus; do
      local millicores=$(convert_cpu_to_millicores "$cpu_value")
      vpa_cpu_per_pod=$((vpa_cpu_per_pod + millicores))
    done
    
    # Multiply by replica count
    local vpa_total_cpu=$((vpa_cpu_per_pod * replica_count))
    total_cpu_millicores=$((total_cpu_millicores + vpa_total_cpu))
    
    log_info "  VPA $vpa_name: ${vpa_cpu_per_pod}m CPU per pod × $replica_count replicas = ${vpa_total_cpu}m total"
    
    # Extract memory recommendations for all containers in this VPA
    local vpa_memory_per_pod=0
    local container_memories=$(echo "$vpa_list" | \
      jq -r ".items[$vpa_index].status.recommendation.containerRecommendations[]? | 
        .upperBound.memory // \"0\"")
    
    for memory_value in $container_memories; do
      local bytes=$(convert_memory_to_bytes "$memory_value")
      vpa_memory_per_pod=$((vpa_memory_per_pod + bytes))
    done
    
    # Multiply by replica count
    local vpa_total_memory=$((vpa_memory_per_pod * replica_count))
    total_memory_bytes=$((total_memory_bytes + vpa_total_memory))
    
    local memory_gi_per_pod=$(convert_bytes_to_gi "$vpa_memory_per_pod")
    local memory_gi_total=$(convert_bytes_to_gi "$vpa_total_memory")
    log_info "  VPA $vpa_name: $memory_gi_per_pod memory per pod × $replica_count replicas = $memory_gi_total total"
  done
  
  # Convert to final units
  local total_cpu_cores=$(echo "scale=2; $total_cpu_millicores / 1000" | bc)
  local total_memory_gi=$(convert_bytes_to_gi "$total_memory_bytes")
  
  log_info "=== VPA Summary for namespace $namespace ==="
  log_info "Total CPU (all workloads): $total_cpu_cores cores"
  log_info "Total Memory (all workloads): $total_memory_gi"
  
  # Return space-separated values
  echo "$total_cpu_cores $total_memory_gi"
}

get_vpa_total_cpu() {
  local namespace="$1"
  local result=$(get_namespace_vpa_recommendations "$namespace")
  echo "$result" | awk '{print $1}'
}

get_vpa_total_memory() {
  local namespace="$1"
  local result=$(get_namespace_vpa_recommendations "$namespace")
  echo "$result" | awk '{print $2}'
}
```

### 🔄 CPU/Memory Unit Conversion

```bash
convert_cpu_to_millicores() {
  local cpu_value="$1"
  
  # Handle different CPU formats:
  # - "2" or "2.0" = 2 cores = 2000 millicores
  # - "500m" = 500 millicores
  # - "0.5" = 0.5 cores = 500 millicores
  
  if [[ "$cpu_value" =~ ^([0-9]+)m$ ]]; then
    # Already in millicores (e.g., "500m")
    echo "${BASH_REMATCH[1]}"
  elif [[ "$cpu_value" =~ ^([0-9]+\.?[0-9]*)$ ]]; then
    # Cores (e.g., "2" or "0.5")
    local cores="${BASH_REMATCH[1]}"
    local millicores=$(echo "$cores * 1000" | bc | awk '{print int($1+0.5)}')
    echo "$millicores"
  else
    log_error "Invalid CPU value: $cpu_value"
    echo "0"
    return 1
  fi
}

convert_memory_to_bytes() {
  local memory_value="$1"
  
  # Handle different memory formats:
  # - "1024" = 1024 bytes
  # - "4Ki" = 4 * 1024 bytes
  # - "512Mi" = 512 * 1024^2 bytes
  # - "8Gi" = 8 * 1024^3 bytes
  # - "2Ti" = 2 * 1024^4 bytes
  
  local number=$(echo "$memory_value" | sed -E 's/([0-9]+\.?[0-9]*).*/\1/')
  local unit=$(echo "$memory_value" | sed -E 's/[0-9]+\.?[0-9]*(.*)/\1/')
  
  case "$unit" in
    "Ki"|"K")
      echo "$number * 1024" | bc | awk '{print int($1)}'
      ;;
    "Mi"|"M")
      echo "$number * 1048576" | bc | awk '{print int($1)}'
      ;;
    "Gi"|"G")
      echo "$number * 1073741824" | bc | awk '{print int($1)}'
      ;;
    "Ti"|"T")
      echo "$number * 1099511627776" | bc | awk '{print int($1)}'
      ;;
    "")
      # No unit = bytes
      echo "$number" | awk '{print int($1)}'
      ;;
    *)
      log_error "Unknown memory unit: $unit in $memory_value"
      echo "0"
      return 1
      ;;
  esac
}

convert_bytes_to_gi() {
  local bytes="$1"
  
  # Convert bytes to Gi, round up
  local gi=$(echo "scale=0; ($bytes / 1073741824 + 0.5) / 1" | bc)
  
  # Ensure minimum 1Gi
  if [[ "$gi" -lt 1 ]]; then
    gi=1
  fi
  
  echo "${gi}Gi"
}
```

---

## HPA Integration

### 📈 Horizontal Pod Autoscaler Basics

**What HPA Provides:**
- `minReplicas` - Minimum pod count
- `maxReplicas` - Maximum pod count ← **We use this**
- `metrics` - Target CPU/memory utilization

**Why maxReplicas?**
- Defines worst-case horizontal scale
- ResourceQuota must accommodate full scale-out
- Prevents HPA from being blocked by quota

**Namespace-Wide HPA Calculation:**
The quota must account for **all HPAs scaling to max simultaneously**.

### 🔍 Detecting HPA

```bash
check_hpa_exists() {
  local namespace="$1"
  
  # Check if any HPA resources exist
  local hpa_count=$(kubectl get hpa -n "$namespace" --no-headers 2>/dev/null | wc -l)
  
  if [[ "$hpa_count" -gt 0 ]]; then
    log_info "HPA detected: $hpa_count resources in namespace $namespace"
    echo "true"
    return 0
  else
    log_debug "No HPA resources found in namespace $namespace"
    echo "false"
    return 1
  fi
}
```

### 📊 Calculating Max Pods from HPA (Namespace-Wide)

```bash
get_namespace_hpa_max_pods() {
  local namespace="$1"
  local buffer_pods="${2:-5}"  # Add buffer for non-HPA pods (daemonsets, etc.)
  
  log_info "Scanning all HPA resources in namespace $namespace..."
  
  # Get ALL HPAs in namespace
  local hpa_list=$(kubectl get hpa -n "$namespace" -o json)
  local hpa_count=$(echo "$hpa_list" | jq -r '.items | length')
  
  if [[ "$hpa_count" -eq 0 ]]; then
    log_warn "No HPA resources found in namespace $namespace"
    echo "0"
    return 1
  fi
  
  log_info "Found $hpa_count HPA resources in namespace $namespace"
  
  # Sum all maxReplicas across all HPAs
  local total_max_replicas=0
  
  for hpa_index in $(seq 0 $((hpa_count - 1))); do
    local hpa_name=$(echo "$hpa_list" | jq -r ".items[$hpa_index].metadata.name")
    local target_kind=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.scaleTargetRef.kind")
    local target_name=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.scaleTargetRef.name")
    local max_replicas=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.maxReplicas")
    
    log_info "  HPA $hpa_name: $target_kind/$target_name maxReplicas=$max_replicas"
    total_max_replicas=$((total_max_replicas + max_replicas))
  done
  
  # Count non-HPA workloads (StatefulSets without HPA, DaemonSets, standalone pods)
  local non_hpa_pods=$(count_non_hpa_pods "$namespace")
  
  # Total = HPA max replicas + non-HPA pods + buffer
  local total_pods=$((total_max_replicas + non_hpa_pods + buffer_pods))
  
  log_info "=== HPA Summary for namespace $namespace ==="
  log_info "Total HPA max replicas: $total_max_replicas"
  log_info "Non-HPA pods: $non_hpa_pods"
  log_info "Buffer: $buffer_pods"
  log_info "Total max pods: $total_pods"
  
  echo "$total_pods"
}

count_non_hpa_pods() {
  local namespace="$1"
  local non_hpa_count=0
  
  # Get all HPA target references
  local hpa_targets=$(kubectl get hpa -n "$namespace" -o json | \
    jq -r '.items[] | "\(.spec.scaleTargetRef.kind)/\(.spec.scaleTargetRef.name)"')
  
  # Count StatefulSets not managed by HPA
  local statefulsets=$(kubectl get statefulsets -n "$namespace" -o json | \
    jq -r '.items[] | "\(.kind)/\(.metadata.name)"')
  
  for ss in $statefulsets; do
    if ! echo "$hpa_targets" | grep -q "$ss"; then
      local replicas=$(kubectl get statefulset $(echo "$ss" | cut -d'/' -f2) -n "$namespace" \
        -o jsonpath='{.spec.replicas}')
      non_hpa_count=$((non_hpa_count + replicas))
      log_debug "  Non-HPA StatefulSet $ss: $replicas replicas"
    fi
  done
  
  # Count DaemonSets (always run one per node)
  local daemonsets=$(kubectl get daemonsets -n "$namespace" --no-headers 2>/dev/null | wc -l)
  if [[ "$daemonsets" -gt 0 ]]; then
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    local ds_pods=$((daemonsets * node_count))
    non_hpa_count=$((non_hpa_count + ds_pods))
    log_debug "  DaemonSets: $daemonsets × $node_count nodes = $ds_pods pods"
  fi
  
  # Count standalone deployments without HPA
  local deployments=$(kubectl get deployments -n "$namespace" -o json | \
    jq -r '.items[] | "\(.kind)/\(.metadata.name)"')
  
  for deploy in $deployments; do
    if ! echo "$hpa_targets" | grep -q "$deploy"; then
      local replicas=$(kubectl get deployment $(echo "$deploy" | cut -d'/' -f2) -n "$namespace" \
        -o jsonpath='{.spec.replicas}')
      non_hpa_count=$((non_hpa_count + replicas))
      log_debug "  Non-HPA Deployment $deploy: $replicas replicas"
    fi
  done
  
  echo "$non_hpa_count"
}

get_hpa_max_pods() {
  # Wrapper for backward compatibility
  get_namespace_hpa_max_pods "$@"
}
```

### 🧮 Calculating CPU/Memory Needs with HPA (Namespace-Wide)

When VPA is not available but HPA is, calculate based on all workloads at max scale:

```bash
calculate_namespace_hpa_cpu_needs() {
  local namespace="$1"
  local total_cpu_millicores=0
  
  log_info "Calculating HPA-based CPU needs for namespace $namespace..."
  
  # Get ALL workloads (Deployments, StatefulSets, DaemonSets)
  local hpa_list=$(kubectl get hpa -n "$namespace" -o json)
  local hpa_count=$(echo "$hpa_list" | jq -r '.items | length')
  
  # Process HPA-managed workloads
  if [[ "$hpa_count" -gt 0 ]]; then
    for hpa_index in $(seq 0 $((hpa_count - 1))); do
      local hpa_name=$(echo "$hpa_list" | jq -r ".items[$hpa_index].metadata.name")
      local target_kind=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.scaleTargetRef.kind")
      local target_name=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.scaleTargetRef.name")
      local max_replicas=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.maxReplicas")
      
      # Get pod CPU from target workload
      local pod_cpu=""
      case "$target_kind" in
        "Deployment")
          pod_cpu=$(kubectl get deployment "$target_name" -n "$namespace" -o json | \
            jq -r '.spec.template.spec.containers[] | 
              .resources.limits.cpu // .resources.requests.cpu // "0m"' 2>/dev/null)
          ;;
        "StatefulSet")
          pod_cpu=$(kubectl get statefulset "$target_name" -n "$namespace" -o json | \
            jq -r '.spec.template.spec.containers[] | 
              .resources.limits.cpu // .resources.requests.cpu // "0m"' 2>/dev/null)
          ;;
      esac
      
      # Sum CPU for all containers in pod
      local pod_cpu_total=0
      for cpu_value in $pod_cpu; do
        local millicores=$(convert_cpu_to_millicores "$cpu_value")
        pod_cpu_total=$((pod_cpu_total + millicores))
      done
      
      # Total = maxReplicas × pod CPU
      local workload_total=$((max_replicas * pod_cpu_total))
      total_cpu_millicores=$((total_cpu_millicores + workload_total))
      
      log_info "  HPA $hpa_name ($target_kind/$target_name): ${pod_cpu_total}m per pod × $max_replicas max replicas = ${workload_total}m"
    done
  fi
  
  # Process non-HPA workloads
  local non_hpa_cpu=$(calculate_non_hpa_cpu "$namespace")
  total_cpu_millicores=$((total_cpu_millicores + non_hpa_cpu))
  
  # Convert to cores
  local total_cores=$(echo "scale=2; $total_cpu_millicores / 1000" | bc)
  
  log_info "=== CPU Summary for namespace $namespace ==="
  log_info "Total CPU (HPA + non-HPA workloads): $total_cores cores"
  
  echo "$total_cores"
}

calculate_non_hpa_cpu() {
  local namespace="$1"
  local total_cpu_millicores=0
  
  # Get all HPA targets
  local hpa_targets=$(kubectl get hpa -n "$namespace" -o json 2>/dev/null | \
    jq -r '.items[] | "\(.spec.scaleTargetRef.kind)/\(.spec.scaleTargetRef.name)"')
  
  # Process Deployments without HPA
  local deployments=$(kubectl get deployments -n "$namespace" -o json)
  local deploy_count=$(echo "$deployments" | jq -r '.items | length')
  
  for deploy_index in $(seq 0 $((deploy_count - 1))); do
    local deploy_name=$(echo "$deployments" | jq -r ".items[$deploy_index].metadata.name")
    
    # Skip if managed by HPA
    if echo "$hpa_targets" | grep -q "Deployment/$deploy_name"; then
      continue
    fi
    
    local replicas=$(echo "$deployments" | jq -r ".items[$deploy_index].spec.replicas")
    local pod_cpus=$(echo "$deployments" | jq -r ".items[$deploy_index].spec.template.spec.containers[] | 
      .resources.limits.cpu // .resources.requests.cpu // \"0m\"")
    
    local pod_cpu_total=0
    for cpu_value in $pod_cpus; do
      local millicores=$(convert_cpu_to_millicores "$cpu_value")
      pod_cpu_total=$((pod_cpu_total + millicores))
    done
    
    local deploy_total=$((replicas * pod_cpu_total))
    total_cpu_millicores=$((total_cpu_millicores + deploy_total))
    log_debug "  Non-HPA Deployment $deploy_name: ${pod_cpu_total}m × $replicas = ${deploy_total}m"
  done
  
  # Process StatefulSets without HPA
  local statefulsets=$(kubectl get statefulsets -n "$namespace" -o json)
  local ss_count=$(echo "$statefulsets" | jq -r '.items | length')
  
  for ss_index in $(seq 0 $((ss_count - 1))); do
    local ss_name=$(echo "$statefulsets" | jq -r ".items[$ss_index].metadata.name")
    
    # Skip if managed by HPA
    if echo "$hpa_targets" | grep -q "StatefulSet/$ss_name"; then
      continue
    fi
    
    local replicas=$(echo "$statefulsets" | jq -r ".items[$ss_index].spec.replicas")
    local pod_cpus=$(echo "$statefulsets" | jq -r ".items[$ss_index].spec.template.spec.containers[] | 
      .resources.limits.cpu // .resources.requests.cpu // \"0m\"")
    
    local pod_cpu_total=0
    for cpu_value in $pod_cpus; do
      local millicores=$(convert_cpu_to_millicores "$cpu_value")
      pod_cpu_total=$((pod_cpu_total + millicores))
    done
    
    local ss_total=$((replicas * pod_cpu_total))
    total_cpu_millicores=$((total_cpu_millicores + ss_total))
    log_debug "  Non-HPA StatefulSet $ss_name: ${pod_cpu_total}m × $replicas = ${ss_total}m"
  done
  
  # Process DaemonSets
  local daemonsets=$(kubectl get daemonsets -n "$namespace" -o json)
  local ds_count=$(echo "$daemonsets" | jq -r '.items | length')
  
  if [[ "$ds_count" -gt 0 ]]; then
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    
    for ds_index in $(seq 0 $((ds_count - 1))); do
      local ds_name=$(echo "$daemonsets" | jq -r ".items[$ds_index].metadata.name")
      local pod_cpus=$(echo "$daemonsets" | jq -r ".items[$ds_index].spec.template.spec.containers[] | 
        .resources.limits.cpu // .resources.requests.cpu // \"0m\"")
      
      local pod_cpu_total=0
      for cpu_value in $pod_cpus; do
        local millicores=$(convert_cpu_to_millicores "$cpu_value")
        pod_cpu_total=$((pod_cpu_total + millicores))
      done
      
      local ds_total=$((node_count * pod_cpu_total))
      total_cpu_millicores=$((total_cpu_millicores + ds_total))
      log_debug "  DaemonSet $ds_name: ${pod_cpu_total}m × $node_count nodes = ${ds_total}m"
    done
  fi
  
  log_info "  Non-HPA workloads total: ${total_cpu_millicores}m"
  echo "$total_cpu_millicores"
}

calculate_namespace_hpa_memory_needs() {
  local namespace="$1"
  local total_memory_bytes=0
  
  log_info "Calculating HPA-based memory needs for namespace $namespace..."
  
  # Get ALL workloads
  local hpa_list=$(kubectl get hpa -n "$namespace" -o json)
  local hpa_count=$(echo "$hpa_list" | jq -r '.items | length')
  
  # Process HPA-managed workloads
  if [[ "$hpa_count" -gt 0 ]]; then
    for hpa_index in $(seq 0 $((hpa_count - 1))); do
      local hpa_name=$(echo "$hpa_list" | jq -r ".items[$hpa_index].metadata.name")
      local target_kind=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.scaleTargetRef.kind")
      local target_name=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.scaleTargetRef.name")
      local max_replicas=$(echo "$hpa_list" | jq -r ".items[$hpa_index].spec.maxReplicas")
      
      # Get pod memory from target workload
      local pod_memory=""
      case "$target_kind" in
        "Deployment")
          pod_memory=$(kubectl get deployment "$target_name" -n "$namespace" -o json | \
            jq -r '.spec.template.spec.containers[] | 
              .resources.limits.memory // .resources.requests.memory // "0"' 2>/dev/null)
          ;;
        "StatefulSet")
          pod_memory=$(kubectl get statefulset "$target_name" -n "$namespace" -o json | \
            jq -r '.spec.template.spec.containers[] | 
              .resources.limits.memory // .resources.requests.memory // "0"' 2>/dev/null)
          ;;
      esac
      
      # Sum memory for all containers in pod
      local pod_memory_total=0
      for memory_value in $pod_memory; do
        local bytes=$(convert_memory_to_bytes "$memory_value")
        pod_memory_total=$((pod_memory_total + bytes))
      done
      
      # Total = maxReplicas × pod memory
      local workload_total=$((max_replicas * pod_memory_total))
      total_memory_bytes=$((total_memory_bytes + workload_total))
      
      local pod_mem_gi=$(convert_bytes_to_gi "$pod_memory_total")
      local workload_mem_gi=$(convert_bytes_to_gi "$workload_total")
      log_info "  HPA $hpa_name ($target_kind/$target_name): $pod_mem_gi per pod × $max_replicas max replicas = $workload_mem_gi"
    done
  fi
  
  # Process non-HPA workloads
  local non_hpa_memory=$(calculate_non_hpa_memory "$namespace")
  total_memory_bytes=$((total_memory_bytes + non_hpa_memory))
  
  # Convert to Gi
  local total_gi=$(convert_bytes_to_gi "$total_memory_bytes")
  
  log_info "=== Memory Summary for namespace $namespace ==="
  log_info "Total Memory (HPA + non-HPA workloads): $total_gi"
  
  echo "$total_gi"
}

calculate_non_hpa_memory() {
  local namespace="$1"
  local total_memory_bytes=0
  
  # Get all HPA targets
  local hpa_targets=$(kubectl get hpa -n "$namespace" -o json 2>/dev/null | \
    jq -r '.items[] | "\(.spec.scaleTargetRef.kind)/\(.spec.scaleTargetRef.name)"')
  
  # Process Deployments without HPA
  local deployments=$(kubectl get deployments -n "$namespace" -o json)
  local deploy_count=$(echo "$deployments" | jq -r '.items | length')
  
  for deploy_index in $(seq 0 $((deploy_count - 1))); do
    local deploy_name=$(echo "$deployments" | jq -r ".items[$deploy_index].metadata.name")
    
    if echo "$hpa_targets" | grep -q "Deployment/$deploy_name"; then
      continue
    fi
    
    local replicas=$(echo "$deployments" | jq -r ".items[$deploy_index].spec.replicas")
    local pod_memories=$(echo "$deployments" | jq -r ".items[$deploy_index].spec.template.spec.containers[] | 
      .resources.limits.memory // .resources.requests.memory // \"0\"")
    
    local pod_memory_total=0
    for memory_value in $pod_memories; do
      local bytes=$(convert_memory_to_bytes "$memory_value")
      pod_memory_total=$((pod_memory_total + bytes))
    done
    
    local deploy_total=$((replicas * pod_memory_total))
    total_memory_bytes=$((total_memory_bytes + deploy_total))
  done
  
  # Process StatefulSets without HPA
  local statefulsets=$(kubectl get statefulsets -n "$namespace" -o json)
  local ss_count=$(echo "$statefulsets" | jq -r '.items | length')
  
  for ss_index in $(seq 0 $((ss_count - 1))); do
    local ss_name=$(echo "$statefulsets" | jq -r ".items[$ss_index].metadata.name")
    
    if echo "$hpa_targets" | grep -q "StatefulSet/$ss_name"; then
      continue
    fi
    
    local replicas=$(echo "$statefulsets" | jq -r ".items[$ss_index].spec.replicas")
    local pod_memories=$(echo "$statefulsets" | jq -r ".items[$ss_index].spec.template.spec.containers[] | 
      .resources.limits.memory // .resources.requests.memory // \"0\"")
    
    local pod_memory_total=0
    for memory_value in $pod_memories; do
      local bytes=$(convert_memory_to_bytes "$memory_value")
      pod_memory_total=$((pod_memory_total + bytes))
    done
    
    local ss_total=$((replicas * pod_memory_total))
    total_memory_bytes=$((total_memory_bytes + ss_total))
  done
  
  # Process DaemonSets
  local daemonsets=$(kubectl get daemonsets -n "$namespace" -o json)
  local ds_count=$(echo "$daemonsets" | jq -r '.items | length')
  
  if [[ "$ds_count" -gt 0 ]]; then
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    
    for ds_index in $(seq 0 $((ds_count - 1))); do
      local ds_name=$(echo "$daemonsets" | jq -r ".items[$ds_index].metadata.name")
      local pod_memories=$(echo "$daemonsets" | jq -r ".items[$ds_index].spec.template.spec.containers[] | 
        .resources.limits.memory // .resources.requests.memory // \"0\"")
      
      local pod_memory_total=0
      for memory_value in $pod_memories; do
        local bytes=$(convert_memory_to_bytes "$memory_value")
        pod_memory_total=$((pod_memory_total + bytes))
      done
      
      local ds_total=$((node_count * pod_memory_total))
      total_memory_bytes=$((total_memory_bytes + ds_total))
    done
  fi
  
  echo "$total_memory_bytes"
}

# Wrapper functions for backward compatibility
calculate_hpa_cpu_needs() {
  calculate_namespace_hpa_cpu_needs "$@"
}

calculate_hpa_memory_needs() {
  calculate_namespace_hpa_memory_needs "$@"
}
```

---

## Goldilocks Integration

### 🎯 Goldilocks Basics

**What Goldilocks Provides:**
- UI dashboard for VPA recommendations
- Namespace-wide recommendation aggregation
- Quality of Service (QoS) aware recommendations

**How It Works:**
- Goldilocks creates VPA resources in "Off" mode
- Collects recommendations without auto-scaling
- Presents data in user-friendly dashboard

### 🔍 Detecting Goldilocks

```bash
check_goldilocks_enabled() {
  local namespace="$1"
  
  # Check if Goldilocks is installed in cluster
  if ! kubectl get deployment -n goldilocks goldilocks-dashboard &>/dev/null; then
    log_debug "Goldilocks not installed in cluster"
    echo "false"
    return 1
  fi
  
  # Check if namespace has Goldilocks label
  local label=$(kubectl get namespace "$namespace" \
    -o jsonpath='{.metadata.labels.goldilocks\.fairwinds\.com/enabled}' 2>/dev/null)
  
  if [[ "$label" == "true" ]]; then
    log_info "Goldilocks enabled for namespace $namespace"
    echo "true"
    return 0
  else
    log_debug "Goldilocks not enabled for namespace $namespace"
    echo "false"
    return 1
  fi
}

enable_goldilocks_for_namespace() {
  local namespace="$1"
  
  # Add Goldilocks label to namespace
  kubectl label namespace "$namespace" \
    goldilocks.fairwinds.com/enabled=true \
    --overwrite
  
  log_info "Enabled Goldilocks for namespace $namespace"
  
  # Wait for VPA resources to be created
  sleep 5
  
  # Verify VPAs created
  local vpa_count=$(kubectl get vpa -n "$namespace" --no-headers 2>/dev/null | wc -l)
  log_info "Goldilocks created $vpa_count VPA resources"
}
```

### 📊 Extracting Goldilocks Recommendations

Goldilocks uses standard VPA resources, so we reuse VPA extraction functions:

```bash
get_goldilocks_cpu_recommendation() {
  local namespace="$1"
  
  # Goldilocks creates VPAs with specific labels
  # Use same VPA extraction logic
  get_vpa_total_cpu "$namespace"
}

get_goldilocks_memory_recommendation() {
  local namespace="$1"
  
  get_vpa_total_memory "$namespace"
}

get_goldilocks_pod_count() {
  local namespace="$1"
  
  # Goldilocks doesn't provide pod count recommendations
  # Fallback to HPA or current pod count
  if [[ "$(check_hpa_exists "$namespace")" == "true" ]]; then
    get_hpa_max_pods "$namespace"
  else
    fallback_pod_count "$namespace"
  fi
}
```

### 📈 Goldilocks Dashboard API (Optional)

For advanced integration, query Goldilocks dashboard API:

```bash
get_goldilocks_dashboard_data() {
  local namespace="$1"
  local goldilocks_url="${GOLDILOCKS_DASHBOARD_URL:-http://goldilocks-dashboard.goldilocks.svc.cluster.local}"
  
  # Query Goldilocks API
  curl -s "$goldilocks_url/v1/namespaces/$namespace" | \
    jq -r '.recommendations'
  
  # Example response:
  # {
  #   "deployments": [
  #     {
  #       "name": "payment-api",
  #       "containers": [
  #         {
  #           "name": "payment-api",
  #           "upperBound": {
  #             "cpu": "2000m",
  #             "memory": "4Gi"
  #           }
  #         }
  #       ]
  #     }
  #   ]
  # }
}
```

---

## Pod Resource Fallback

When VPA/HPA/Goldilocks are not available, fallback to declared pod resources **across the entire namespace**.

### 📊 Summing Pod Resources (Namespace-Wide)

```bash
sum_namespace_pod_cpu_limits() {
  local namespace="$1"
  local total_cpu_millicores=0
  
  log_info "Summing CPU limits for all pods in namespace $namespace..."
  
  # Get all running pods
  local pods=$(kubectl get pods -n "$namespace" -o json)
  local pod_count=$(echo "$pods" | jq -r '.items | length')
  
  if [[ "$pod_count" -eq 0 ]]; then
    log_warn "No pods found in namespace $namespace"
    echo "0"
    return 1
  fi
  
  log_info "Found $pod_count pods in namespace $namespace"
  
  # Iterate through all pods
  for pod_index in $(seq 0 $((pod_count - 1))); do
    local pod_name=$(echo "$pods" | jq -r ".items[$pod_index].metadata.name")
    
    # Get CPU limits for all containers in this pod
    local container_cpus=$(echo "$pods" | \
      jq -r ".items[$pod_index].spec.containers[] | 
        .resources.limits.cpu // .resources.requests.cpu // \"0m\"")
    
    local pod_cpu_total=0
    for cpu_value in $container_cpus; do
      local millicores=$(convert_cpu_to_millicores "$cpu_value")
      pod_cpu_total=$((pod_cpu_total + millicores))
    done
    
    total_cpu_millicores=$((total_cpu_millicores + pod_cpu_total))
    log_debug "  Pod $pod_name: ${pod_cpu_total}m"
  done
  
  # Convert to cores, round up
  local cores=$(echo "scale=0; ($total_cpu_millicores / 1000 + 0.5) / 1" | bc)
  
  # Ensure minimum 1 core
  if [[ "$cores" -lt 1 ]]; then
    cores=1
  fi
  
  log_info "Total pod CPU limits: $cores cores (${total_cpu_millicores}m)"
  echo "$cores"
}

sum_namespace_pod_memory_limits() {
  local namespace="$1"
  local total_memory_bytes=0
  
  log_info "Summing memory limits for all pods in namespace $namespace..."
  
  # Get all running pods
  local pods=$(kubectl get pods -n "$namespace" -o json)
  local pod_count=$(echo "$pods" | jq -r '.items | length')
  
  if [[ "$pod_count" -eq 0 ]]; then
    log_warn "No pods found in namespace $namespace"
    echo "0"
    return 1
  fi
  
  log_info "Found $pod_count pods in namespace $namespace"
  
  # Iterate through all pods
  for pod_index in $(seq 0 $((pod_count - 1))); do
    local pod_name=$(echo "$pods" | jq -r ".items[$pod_index].metadata.name")
    
    # Get memory limits for all containers in this pod
    local container_memories=$(echo "$pods" | \
      jq -r ".items[$pod_index].spec.containers[] | 
        .resources.limits.memory // .resources.requests.memory // \"0\"")
    
    local pod_memory_total=0
    for memory_value in $container_memories; do
      local bytes=$(convert_memory_to_bytes "$memory_value")
      pod_memory_total=$((pod_memory_total + bytes))
    done
    
    total_memory_bytes=$((total_memory_bytes + pod_memory_total))
    
    local pod_mem_gi=$(convert_bytes_to_gi "$pod_memory_total")
    log_debug "  Pod $pod_name: $pod_mem_gi"
  done
  
  # Convert to Gi
  local memory_gi=$(convert_bytes_to_gi "$total_memory_bytes")
  
  log_info "Total pod memory limits: $memory_gi"
  echo "$memory_gi"
}

fallback_pod_count() {
  local namespace="$1"
  local buffer_percent="${2:-50}"  # Add 50% buffer by default
  
  # Count current pods
  local current_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
  
  # Add buffer to allow for scaling
  local buffered_pods=$(echo "scale=0; ($current_pods * (100 + $buffer_percent) / 100 + 0.5) / 1" | bc)
  
  # Ensure minimum 3 pods
  if [[ "$buffered_pods" -lt 3 ]]; then
    buffered_pods=3
  fi
  
  log_info "Fallback pod count: $current_pods current + $buffer_percent% buffer = $buffered_pods"
  echo "$buffered_pods"
}

# Wrapper functions for backward compatibility
sum_pod_cpu_limits() {
  sum_namespace_pod_cpu_limits "$@"
}

sum_pod_memory_limits() {
  sum_namespace_pod_memory_limits "$@"
}
```

---

## Safety Buffers & Validation

### 🛡️ Applying Safety Buffers

**Why buffers?**
- Prevents quota exhaustion during traffic spikes
- Accounts for measurement inaccuracies
- Allows temporary overhead (init containers, job pods)

```bash
apply_buffer() {
  local value="$1"
  local buffer_percent="${2:-20}"  # Default 20%
  
  # Remove unit suffix if present (e.g., "8Gi" -> "8")
  local numeric_value=$(echo "$value" | sed -E 's/([0-9]+\.?[0-9]*).*/\1/')
  local unit=$(echo "$value" | sed -E 's/[0-9]+\.?[0-9]*(.*)/\1/')
  
  # Calculate buffered value
  local buffered=$(echo "scale=2; $numeric_value * (100 + $buffer_percent) / 100" | bc)
  
  # Round up to nearest integer
  buffered=$(echo "scale=0; ($buffered + 0.5) / 1" | bc)
  
  log_debug "Applied $buffer_percent% buffer: $value -> $buffered$unit"
  echo "$buffered$unit"
}
```

### ✅ Sanity Check Validation

**Prevent misconfiguration:**
- Reject quotas exceeding cluster capacity
- Block suspicious VPA/HPA values (potential manipulation)
- Enforce organizational limits

```bash
validate_quota_limits() {
  local cpu="$1"
  local memory="$2"
  local pods="$3"
  local max_cpu="${MAX_CPU_LIMIT:-64}"          # Default: 64 cores max
  local max_memory="${MAX_MEMORY_LIMIT:-128}"   # Default: 128Gi max
  local max_pods="${MAX_PODS_LIMIT:-500}"       # Default: 500 pods max
  
  # Remove unit suffixes for comparison
  cpu=$(echo "$cpu" | sed 's/[^0-9.]//g')
  memory=$(echo "$memory" | sed 's/[^0-9.]//g')
  pods=$(echo "$pods" | sed 's/[^0-9.]//g')
  
  # Validate CPU
  if (( $(echo "$cpu > $max_cpu" | bc -l) )); then
    log_error "CPU quota $cpu exceeds maximum $max_cpu cores"
    log_error "Review VPA recommendations or increase --max-cpu-limit"
    return 1
  fi
  
  # Validate memory
  if (( $(echo "$memory > $max_memory" | bc -l) )); then
    log_error "Memory quota ${memory}Gi exceeds maximum ${max_memory}Gi"
    log_error "Review VPA recommendations or increase --max-memory-limit"
    return 1
  fi
  
  # Validate pods
  if (( $(echo "$pods > $max_pods" | bc -l) )); then
    log_error "Pod quota $pods exceeds maximum $max_pods"
    log_error "Review HPA maxReplicas or increase --max-pods-limit"
    return 1
  fi
  
  log_info "Quota validation passed: ${cpu} CPU, ${memory}Gi memory, $pods pods"
  return 0
}

validate_vpa_recommendation_age() {
  local namespace="$1"
  local min_age_days="${2:-7}"  # Require at least 7 days of data
  local min_age_seconds=$((min_age_days * 86400))
  
  # Check all VPAs in namespace
  local vpas=$(kubectl get vpa -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  for vpa in $vpas; do
    local age_valid=$(check_vpa_data_age "$namespace" "$vpa" "$min_age_seconds")
    if [[ "$age_valid" == "false" ]]; then
      log_warn "VPA $vpa has insufficient data age (<$min_age_days days)"
      log_warn "Recommendations may not be accurate yet"
      return 1
    fi
  done
  
  log_info "All VPA recommendations have sufficient data age (>$min_age_days days)"
  return 0
}

validate_hpa_max_replicas() {
  local namespace="$1"
  local max_allowed_replicas="${2:-100}"  # Default: 100 replicas max per HPA
  
  # Check all HPAs
  local excessive_hpas=$(kubectl get hpa -n "$namespace" -o json | \
    jq -r ".items[] | 
      select(.spec.maxReplicas > $max_allowed_replicas) | 
      .metadata.name")
  
  if [[ -n "$excessive_hpas" ]]; then
    log_error "HPAs with excessive maxReplicas (>$max_allowed_replicas):"
    echo "$excessive_hpas" | while read hpa; do
      local max_replicas=$(kubectl get hpa "$hpa" -n "$namespace" \
        -o jsonpath='{.spec.maxReplicas}')
      log_error "  - $hpa: maxReplicas=$max_replicas"
    done
    log_error "Review HPA configurations before hardening"
    return 1
  fi
  
  log_info "HPA maxReplicas validation passed"
  return 0
}
```

### 📊 Rounding Strategies

```bash
round_up_cpu() {
  local cpu_cores="$1"
  
  # Round up to nearest integer core
  local rounded=$(echo "scale=0; ($cpu_cores + 0.5) / 1" | bc)
  
  # Ensure minimum 1 core
  if [[ "$rounded" -lt 1 ]]; then
    rounded=1
  fi
  
  echo "$rounded"
}

round_up_memory() {
  local memory_gi="$1"
  
  # Remove 'Gi' suffix if present
  memory_gi=$(echo "$memory_gi" | sed 's/Gi//g')
  
  # Round up to nearest Gi
  local rounded=$(echo "scale=0; ($memory_gi + 0.5) / 1" | bc)
  
  # Ensure minimum 1Gi
  if [[ "$rounded" -lt 1 ]]; then
    rounded=1
  fi
  
  echo "${rounded}Gi"
}

round_up_pods() {
  local pods="$1"
  
  # Round up to nearest integer
  local rounded=$(echo "scale=0; ($pods + 0.5) / 1" | bc)
  
  # Ensure minimum 3 pods (for basic HA)
  if [[ "$rounded" -lt 3 ]]; then
    rounded=3
  fi
  
  echo "$rounded"
}
```

---

## Implementation Functions

### 🔧 Complete Measurement Function

Combining all detection methods:

```bash
measure_namespace_resources() {
  local namespace="$1"
  local buffer_percent="${2:-20}"
  local skip_vpa="${3:-false}"
  local skip_hpa="${4:-false}"
  local skip_goldilocks="${5:-false}"
  
  log_info "=== Measuring namespace resources: $namespace ==="
  
  # Initialize variables
  local cpu_cores=0
  local memory_gi=0
  local max_pods=0
  local measurement_source="unknown"
  
  # Detection flags
  local has_goldilocks="false"
  local has_vpa="false"
  local has_hpa="false"
  
  # Step 1: Detect available autoscalers
  if [[ "$skip_goldilocks" == "false" ]]; then
    has_goldilocks=$(check_goldilocks_enabled "$namespace")
  fi
  
  if [[ "$skip_vpa" == "false" ]]; then
    has_vpa=$(check_vpa_exists "$namespace")
  fi
  
  if [[ "$skip_hpa" == "false" ]]; then
    has_hpa=$(check_hpa_exists "$namespace")
  fi
  
  # Step 2: Choose measurement strategy (priority order)
  if [[ "$has_goldilocks" == "true" ]]; then
    log_info "Using Goldilocks recommendations (highest priority)"
    measurement_source="goldilocks"
    cpu_cores=$(get_goldilocks_cpu_recommendation "$namespace" | sed 's/[^0-9.]//g')
    memory_gi=$(get_goldilocks_memory_recommendation "$namespace" | sed 's/[^0-9.]//g')
    max_pods=$(get_goldilocks_pod_count "$namespace")
    
  elif [[ "$has_vpa" == "true" ]]; then
    log_info "Using VPA upperBound recommendations"
    measurement_source="vpa"
    
    # Validate VPA data age
    if ! validate_vpa_recommendation_age "$namespace" 7; then
      log_warn "VPA data immature, falling back to pod limits"
      measurement_source="vpa-immature-fallback"
      cpu_cores=$(sum_pod_cpu_limits "$namespace")
      memory_gi=$(sum_pod_memory_limits "$namespace" | sed 's/[^0-9.]//g')
    else
      cpu_cores=$(get_vpa_total_cpu "$namespace")
      memory_gi=$(get_vpa_total_memory "$namespace" | sed 's/[^0-9.]//g')
    fi
    
    # Get pod count from HPA or fallback
    if [[ "$has_hpa" == "true" ]]; then
      max_pods=$(get_hpa_max_pods "$namespace")
    else
      max_pods=$(fallback_pod_count "$namespace")
    fi
    
  elif [[ "$has_hpa" == "true" ]]; then
    log_info "Using HPA maxReplicas with pod resource limits"
    measurement_source="hpa"
    
    # Validate HPA configurations
    if ! validate_hpa_max_replicas "$namespace" 100; then
      log_error "HPA validation failed, aborting measurement"
      return 1
    fi
    
    cpu_cores=$(calculate_hpa_cpu_needs "$namespace")
    memory_gi=$(calculate_hpa_memory_needs "$namespace" | sed 's/[^0-9.]//g')
    max_pods=$(get_hpa_max_pods "$namespace")
    
  else
    log_warn "No autoscalers detected, using current pod resource limits"
    measurement_source="pod-limits-fallback"
    cpu_cores=$(sum_pod_cpu_limits "$namespace")
    memory_gi=$(sum_pod_memory_limits "$namespace" | sed 's/[^0-9.]//g')
    max_pods=$(fallback_pod_count "$namespace")
  fi
  
  # Step 3: Apply safety buffer
  log_info "Applying $buffer_percent% safety buffer"
  cpu_cores=$(apply_buffer "$cpu_cores" "$buffer_percent" | sed 's/[^0-9.]//g')
  memory_gi=$(apply_buffer "$memory_gi" "$buffer_percent" | sed 's/[^0-9.]//g')
  max_pods=$(apply_buffer "$max_pods" "$buffer_percent" | sed 's/[^0-9.]//g')
  
  # Step 4: Round up
  cpu_cores=$(round_up_cpu "$cpu_cores")
  memory_gi=$(round_up_memory "$memory_gi")
  max_pods=$(round_up_pods "$max_pods")
  
  # Step 5: Validate sanity checks
  if ! validate_quota_limits "$cpu_cores" "$memory_gi" "$max_pods"; then
    log_error "Quota validation failed, measurement aborted"
    return 1
  fi
  
  # Step 6: Return results
  log_info "=== Measurement complete ==="
  log_info "Source: $measurement_source"
  log_info "CPU: $cpu_cores cores"
  log_info "Memory: $memory_gi"
  log_info "Max pods: $max_pods"
  
  # Return as space-separated values
  echo "$cpu_cores $memory_gi $max_pods $measurement_source"
}
```

### 📝 Usage Example

```bash
# Measure namespace resources
result=$(measure_namespace_resources "payment-service" 20)

# Parse results
cpu=$(echo "$result" | awk '{print $1}')
memory=$(echo "$result" | awk '{print $2}')
pods=$(echo "$result" | awk '{print $3}')
source=$(echo "$result" | awk '{print $4}')

# Generate ResourceQuota
generate_resource_quota \
  "payment-service" \
  "$cpu" \
  "$memory" \
  "$pods" \
  "5"  # PVC count
```

---

## Testing & Validation

### 🧪 Test Scenarios

#### Test 1: VPA Detection and Parsing

```bash
# Create test namespace with VPA
kubectl create namespace test-vpa
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: test-vpa
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: test-app-vpa
  namespace: test-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: test-app
  updateMode: "Off"
EOF

# Wait for VPA to generate recommendations (may take 24-48 hours in production)
# For testing, simulate VPA recommendations:
kubectl patch vpa test-app-vpa -n test-vpa --type=json -p='[
  {
    "op": "add",
    "path": "/status",
    "value": {
      "recommendation": {
        "containerRecommendations": [
          {
            "containerName": "app",
            "lowerBound": {"cpu": "100m", "memory": "128Mi"},
            "target": {"cpu": "200m", "memory": "256Mi"},
            "upperBound": {"cpu": "500m", "memory": "512Mi"}
          }
        ]
      }
    }
  }
]'

# Test VPA detection
check_vpa_exists "test-vpa"
# Expected: "true"

# Test VPA CPU recommendation
get_vpa_cpu_recommendation "test-vpa" "test-app"
# Expected: "0.5" (500m = 0.5 cores)

# Test VPA memory recommendation
get_vpa_memory_recommendation "test-vpa" "test-app"
# Expected: "1Gi" (512Mi rounded up)
```

#### Test 2: HPA Detection and Max Pods

```bash
# Create test namespace with HPA
kubectl create namespace test-hpa
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: test-hpa
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: test-app-hpa
  namespace: test-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: test-app
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

# Test HPA detection
check_hpa_exists "test-hpa"
# Expected: "true"

# Test max pods calculation
get_hpa_max_pods "test-hpa" 5
# Expected: "15" (10 maxReplicas + 5 buffer)

# Test HPA CPU needs
calculate_hpa_cpu_needs "test-hpa"
# Expected: "2" (10 replicas × 200m = 2000m = 2 cores)
```

#### Test 3: Full Measurement Workflow

```bash
# Measure namespace with VPA and HPA
result=$(measure_namespace_resources "test-vpa" 20)
echo "$result"
# Expected: "1 1Gi 18 vpa" (0.5 cores × 3 replicas + 20% = 1 core rounded)

# Measure namespace with HPA only
result=$(measure_namespace_resources "test-hpa" 20)
echo "$result"
# Expected: "3 4Gi 18 hpa" (10 max replicas × 200m × 1.2 buffer)
```

#### Test 4: Unit Conversion

```bash
# Test CPU conversion
convert_cpu_to_millicores "2"
# Expected: "2000"

convert_cpu_to_millicores "500m"
# Expected: "500"

convert_cpu_to_millicores "0.5"
# Expected: "500"

# Test memory conversion
convert_memory_to_bytes "4Gi"
# Expected: "4294967296"

convert_memory_to_bytes "512Mi"
# Expected: "536870912"

convert_bytes_to_gi "5368709120"
# Expected: "5Gi"
```

#### Test 5: Safety Buffer Application

```bash
# Test buffer application
apply_buffer "8" 20
# Expected: "10" (8 × 1.2 = 9.6 rounded to 10)

apply_buffer "5Gi" 20
# Expected: "6Gi" (5 × 1.2 = 6)

apply_buffer "15" 50
# Expected: "23" (15 × 1.5 = 22.5 rounded to 23)
```

#### Test 6: Validation Functions

```bash
# Test quota validation (should pass)
validate_quota_limits "8" "16" "20"
# Expected: return 0 (success)

# Test quota validation (should fail - excessive CPU)
validate_quota_limits "128" "16" "20"
# Expected: return 1 (failure), log error about exceeding max CPU

# Test VPA age validation (mock old VPA)
# Would need actual VPA with >7 day age or mock the timestamp
```

### 🔍 Debugging Tips

**Enable debug logging:**
```bash
export LOG_LEVEL=debug
measure_namespace_resources "my-namespace"
```

**Check VPA/HPA configurations:**
```bash
# View VPA status
kubectl get vpa -n my-namespace -o yaml

# View HPA status
kubectl get hpa -n my-namespace -o yaml

# Check for VPA/HPA events
kubectl get events -n my-namespace --field-selector involvedObject.kind=VerticalPodAutoscaler
kubectl get events -n my-namespace --field-selector involvedObject.kind=HorizontalPodAutoscaler
```

**Manual calculation verification:**
```bash
# Manually sum pod CPU limits
kubectl get pods -n my-namespace -o json | \
  jq -r '.items[].spec.containers[].resources.limits.cpu' | \
  awk '{sum+=$1} END {print sum}'

# Compare with function output
sum_pod_cpu_limits "my-namespace"
```

---

## Summary

### ✅ Key Takeaways

1. **Priority Order**: Goldilocks → VPA → HPA → Pod Limits
2. **VPA upperBound**: Use for CPU/memory (P99 + headroom)
3. **HPA maxReplicas**: Use for max pods calculation
4. **Safety Buffer**: Always add 20% to prevent quota exhaustion
5. **Validation**: Sanity check all measurements (max 64 CPU, 128Gi)
6. **VPA Age**: Require at least 7 days of data for accurate recommendations
7. **Rounding**: Always round UP to ensure quota covers usage

### 🛡️ Security Considerations

1. **Prevent VPA/HPA manipulation**: Validate against cluster maximums
2. **Immature VPA data**: Fallback to pod limits if <7 days old
3. **Excessive HPA maxReplicas**: Alert on >100 replicas per HPA
4. **Audit trail**: Log measurement source and values
5. **Graceful degradation**: Fallback strategy if autoscalers unavailable

---

**Document Version:** 2.0.0  
**Last Updated:** 2026-02-11  
**Author:** Forge Platform Team  
**Status:** Active
