# DaemonSet Maximum Capacity Handling

**Critical Design Decision for Namespace Hardening**

---

## 🎯 Problem Statement

**DaemonSets scale with cluster node count**, not workload demand. When calculating namespace ResourceQuotas, we must account for **maximum cluster capacity**, not current node count.

### ❌ The Problem

```bash
# Current state
Current nodes: 10
DaemonSet (monitoring-agent): 100m CPU per pod
Calculated quota: 10 nodes × 100m = 1 core

# Future state (autoscaling)
Cluster scales to: 80 nodes (Karpenter limit: 100)
DaemonSet needs: 80 nodes × 100m = 8 cores
Result: QUOTA EXCEEDED - Pods fail to schedule!
```

### ✅ The Solution

```bash
# Use maximum capacity
Max nodes (Karpenter): 100
DaemonSet: 100m CPU per pod
Calculated quota: 100 nodes × 100m = 10 cores

# Future state (autoscaling)
Cluster scales to: 80 nodes
DaemonSet needs: 80 nodes × 100m = 8 cores
Result: ✅ Within quota - Pods schedule successfully
```

---

## 🏗️ Architecture

### Detection Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│          DaemonSet Max Capacity Detection                  │
└─────────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
    ┌───▼───┐          ┌─────▼──────┐     ┌──────▼───────┐
    │ TIER 1│          │   TIER 2   │     │   TIER 3     │
    │Karpenter│        │Autoscaler  │     │  ConfigMap   │
    └───┬───┘          └─────┬──────┘     └──────┬───────┘
        │                    │                    │
        │ NodePool.spec      │ ASG maxSize       │ Manual
        │ .limits.resources  │ MIG targetSize    │ Override
        │ .nodes             │ VMSS capacity     │
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                       ┌─────▼──────┐
                       │  TIER 4    │
                       │  Fallback  │
                       │Current × 2 │
                       └────────────┘
```

---

## 📚 Implementation

### Core Function: `get_max_node_capacity()`

```bash
#!/bin/bash

# Get maximum node capacity for DaemonSet calculations
# Returns: Integer (max node count)
# Fallback: Current node count × 2

get_max_node_capacity() {
  local node_selector="${1:-}"  # Optional: nodeSelector filter
  
  log_debug "Detecting maximum node capacity..."
  
  # TIER 1: Karpenter NodePool
  if command -v kubectl > /dev/null 2>&1 && \
     kubectl get crd nodepools.karpenter.sh > /dev/null 2>&1; then
    
    local max_nodes=$(get_karpenter_max_nodes "$node_selector")
    if [[ -n "$max_nodes" && "$max_nodes" -gt 0 ]]; then
      log_info "Max nodes from Karpenter: $max_nodes"
      echo "$max_nodes"
      return 0
    fi
  fi
  
  # TIER 2: Cluster Autoscaler (Cloud Provider APIs)
  local max_nodes=$(get_autoscaler_max_nodes "$node_selector")
  if [[ -n "$max_nodes" && "$max_nodes" -gt 0 ]]; then
    log_info "Max nodes from autoscaler: $max_nodes"
    echo "$max_nodes"
    return 0
  fi
  
  # TIER 3: ConfigMap Override
  max_nodes=$(kubectl get configmap forge-cluster-config -n forge-system \
    -o jsonpath='{.data.max-nodes}' 2>/dev/null)
  
  if [[ -n "$max_nodes" && "$max_nodes" -gt 0 ]]; then
    log_info "Max nodes from ConfigMap: $max_nodes"
    echo "$max_nodes"
    return 0
  fi
  
  # TIER 4: Fallback - Current × 2
  local current_nodes
  if [[ -n "$node_selector" ]]; then
    current_nodes=$(kubectl get nodes -l "$node_selector" --no-headers 2>/dev/null | wc -l)
  else
    current_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  fi
  
  if [[ "$current_nodes" -eq 0 ]]; then
    current_nodes=1  # At least 1 node
  fi
  
  local fallback_max=$((current_nodes * 2))
  log_warn "Using fallback max nodes: current ($current_nodes) × 2 = $fallback_max"
  echo "$fallback_max"
}
```

### Tier 1: Karpenter Detection

```bash
get_karpenter_max_nodes() {
  local node_selector="$1"
  
  # Get all NodePools
  local nodepools=$(kubectl get nodepool -A -o json 2>/dev/null)
  [[ -z "$nodepools" || "$nodepools" == "null" ]] && return 1
  
  local total_max=0
  local pool_count=0
  
  # Parse each NodePool
  while IFS= read -r nodepool; do
    local pool_name=$(echo "$nodepool" | jq -r '.metadata.name')
    
    # Check for explicit node limit
    local max_nodes=$(echo "$nodepool" | jq -r '.spec.limits.resources.nodes // empty')
    
    if [[ -z "$max_nodes" ]]; then
      # No node limit, try to estimate from CPU/memory
      local max_cpu=$(echo "$nodepool" | jq -r '.spec.limits.resources.cpu // empty')
      
      if [[ -n "$max_cpu" ]]; then
        # Get typical node size from instance types
        local instance_types=$(echo "$nodepool" | jq -r '.spec.template.spec.requirements[] | 
          select(.key == "node.kubernetes.io/instance-type") | .values[]' 2>/dev/null)
        
        # Estimate vCPUs per node (AWS example: m5.xlarge = 4 vCPUs)
        local vcpus_per_node=4  # Default conservative estimate
        
        if echo "$instance_types" | grep -q "xlarge"; then
          vcpus_per_node=4
        elif echo "$instance_types" | grep -q "2xlarge"; then
          vcpus_per_node=8
        elif echo "$instance_types" | grep -q "4xlarge"; then
          vcpus_per_node=16
        fi
        
        # Convert max_cpu to cores
        local max_cores=$(convert_cpu_to_cores "$max_cpu")
        max_nodes=$((max_cores / vcpus_per_node))
        
        log_debug "Karpenter NodePool $pool_name: estimated $max_nodes nodes from ${max_cpu} CPU"
      fi
    else
      log_debug "Karpenter NodePool $pool_name: explicit limit $max_nodes nodes"
    fi
    
    if [[ -n "$max_nodes" && "$max_nodes" -gt 0 ]]; then
      total_max=$((total_max + max_nodes))
      pool_count=$((pool_count + 1))
    fi
    
  done < <(echo "$nodepools" | jq -c '.items[]')
  
  if [[ "$total_max" -gt 0 ]]; then
    log_info "Karpenter: $pool_count NodePools, total max $total_max nodes"
    echo "$total_max"
    return 0
  fi
  
  return 1
}
```

### Tier 2: Cloud Provider Autoscaler

```bash
get_autoscaler_max_nodes() {
  local node_selector="$1"
  
  # Try each cloud provider
  get_aws_autoscaler_max "$node_selector" && return 0
  get_gcp_autoscaler_max "$node_selector" && return 0
  get_azure_autoscaler_max "$node_selector" && return 0
  
  return 1
}

get_aws_autoscaler_max() {
  local node_selector="$1"
  
  # Requires AWS CLI
  command -v aws > /dev/null 2>&1 || return 1
  
  # Get cluster name from kubeconfig
  local cluster_name=$(kubectl config current-context | grep -oP '(?<=/).*$' || echo "")
  [[ -z "$cluster_name" ]] && return 1
  
  log_debug "Detecting AWS AutoScalingGroups for cluster: $cluster_name"
  
  local total_max=0
  
  # Find ASGs tagged with this cluster
  while IFS= read -r asg_name; do
    [[ -z "$asg_name" ]] && continue
    
    local max_size=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$asg_name" \
      --query 'AutoScalingGroups[0].MaxSize' \
      --output text 2>/dev/null)
    
    if [[ -n "$max_size" && "$max_size" != "None" ]]; then
      log_debug "AWS ASG $asg_name: maxSize=$max_size"
      total_max=$((total_max + max_size))
    fi
    
  done < <(aws autoscaling describe-auto-scaling-groups \
    --query "AutoScalingGroups[?Tags[?Key=='kubernetes.io/cluster/${cluster_name}']].AutoScalingGroupName" \
    --output text 2>/dev/null | tr '\t' '\n')
  
  if [[ "$total_max" -gt 0 ]]; then
    log_info "AWS Autoscaler: total max $total_max nodes"
    echo "$total_max"
    return 0
  fi
  
  return 1
}

get_gcp_autoscaler_max() {
  local node_selector="$1"
  
  # Requires gcloud CLI
  command -v gcloud > /dev/null 2>&1 || return 1
  
  log_debug "Detecting GCP ManagedInstanceGroups"
  
  local total_max=0
  local project=$(gcloud config get-value project 2>/dev/null)
  
  # Get all MIGs in project
  while IFS= read -r mig_name; do
    [[ -z "$mig_name" ]] && continue
    
    local target_size=$(gcloud compute instance-groups managed describe "$mig_name" \
      --format='value(targetSize)' 2>/dev/null)
    
    if [[ -n "$target_size" ]]; then
      log_debug "GCP MIG $mig_name: targetSize=$target_size"
      total_max=$((total_max + target_size))
    fi
    
  done < <(gcloud compute instance-groups managed list \
    --filter="name~'gke-.*'" \
    --format='value(name)' 2>/dev/null)
  
  if [[ "$total_max" -gt 0 ]]; then
    log_info "GCP Autoscaler: total max $total_max nodes"
    echo "$total_max"
    return 0
  fi
  
  return 1
}

get_azure_autoscaler_max() {
  local node_selector="$1"
  
  # Requires az CLI
  command -v az > /dev/null 2>&1 || return 1
  
  log_debug "Detecting Azure VMSS"
  
  local total_max=0
  
  # Get all VMSSs
  while IFS= read -r vmss_name; do
    [[ -z "$vmss_name" ]] && continue
    
    local capacity=$(az vmss show --name "$vmss_name" \
      --query 'sku.capacity' -o tsv 2>/dev/null)
    
    if [[ -n "$capacity" ]]; then
      log_debug "Azure VMSS $vmss_name: capacity=$capacity"
      total_max=$((total_max + capacity))
    fi
    
  done < <(az vmss list --query '[].name' -o tsv 2>/dev/null)
  
  if [[ "$total_max" -gt 0 ]]; then
    log_info "Azure Autoscaler: total max $total_max nodes"
    echo "$total_max"
    return 0
  fi
  
  return 1
}
```

### Tier 3: ConfigMap Override

```yaml
# Manual cluster configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: forge-cluster-config
  namespace: forge-system
data:
  # Total maximum nodes
  max-nodes: "200"
  
  # Maximum GPU nodes (for DaemonSets with nodeSelector: node-type=gpu)
  max-gpu-nodes: "50"
  
  # Maximum spot nodes
  max-spot-nodes: "150"
  
  # Cloud provider hint
  cloud-provider: "aws"
  
  # Autoscaler type
  autoscaler: "karpenter"
```

**Reading ConfigMap:**

```bash
get_configmap_max_nodes() {
  local node_type="${1:-max-nodes}"  # Default: total max-nodes
  
  kubectl get configmap forge-cluster-config -n forge-system \
    -o jsonpath="{.data.${node_type}}" 2>/dev/null
}
```

---

## 🎯 Node Selector Handling

### Problem: DaemonSets with NodeSelector

Some DaemonSets only run on specific node types:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin
  namespace: gpu-workloads
spec:
  template:
    spec:
      nodeSelector:
        node-type: gpu  # Only GPU nodes
```

**We must calculate max GPU nodes, not total nodes!**

### Solution: Type-Specific Limits

```bash
get_max_gpu_nodes() {
  # 1. Try ConfigMap first
  local max_gpu=$(get_configmap_max_nodes "max-gpu-nodes")
  if [[ -n "$max_gpu" && "$max_gpu" -gt 0 ]]; then
    echo "$max_gpu"
    return 0
  fi
  
  # 2. Try Karpenter (filter by instance type)
  if kubectl get crd nodepools.karpenter.sh > /dev/null 2>&1; then
    local karpenter_gpu=$(kubectl get nodepool -A -o json | jq '
      [.items[] | 
       select(.spec.template.spec.requirements[]? | 
              select(.key == "node.kubernetes.io/instance-type") | 
              .values[]? | 
              test("p3|p4|g4|g5"))
       | .spec.limits.resources.nodes // 0] | add')
    
    if [[ -n "$karpenter_gpu" && "$karpenter_gpu" != "null" && "$karpenter_gpu" -gt 0 ]]; then
      echo "$karpenter_gpu"
      return 0
    fi
  fi
  
  # 3. Fallback: current GPU nodes × 2
  local current_gpu=$(kubectl get nodes -l 'node-type=gpu' --no-headers 2>/dev/null | wc -l)
  if [[ "$current_gpu" -eq 0 ]]; then
    echo "0"  # No GPU nodes
  else
    echo $((current_gpu * 2))
  fi
}

get_max_spot_nodes() {
  # Similar logic for spot instances
  local max_spot=$(get_configmap_max_nodes "max-spot-nodes")
  [[ -n "$max_spot" ]] && echo "$max_spot" && return 0
  
  # Karpenter: filter by capacity-type=spot
  local karpenter_spot=$(kubectl get nodepool -A -o json | jq '
    [.items[] | 
     select(.spec.template.spec.requirements[]? | 
            select(.key == "karpenter.sh/capacity-type") | 
            .values[]? == "spot")
     | .spec.limits.resources.nodes // 0] | add')
  
  [[ -n "$karpenter_spot" && "$karpenter_spot" != "null" ]] && echo "$karpenter_spot" && return 0
  
  # Fallback
  local current_spot=$(kubectl get nodes -l 'karpenter.sh/capacity-type=spot' --no-headers 2>/dev/null | wc -l)
  echo $((current_spot * 2))
}
```

### Proportional Estimation

For unknown node selectors, estimate proportion:

```bash
estimate_max_for_selector() {
  local node_selector="$1"
  
  # Get current counts
  local current_matching=$(kubectl get nodes -l "$node_selector" --no-headers 2>/dev/null | wc -l)
  local current_total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  
  if [[ "$current_total" -eq 0 ]]; then
    echo "0"
    return 0
  fi
  
  # Calculate ratio
  local ratio=$(echo "scale=2; $current_matching / $current_total" | bc)
  
  # Apply ratio to total max capacity
  local total_max=$(get_max_node_capacity)
  local estimated_max=$(echo "$total_max * $ratio" | bc | cut -d'.' -f1)
  
  log_debug "Estimated max nodes for selector '$node_selector': ${estimated_max} (${ratio}x of $total_max)"
  echo "$estimated_max"
}
```

---

## 🔧 Integration with Hardening

### Updated `calculate_non_hpa_cpu()`

```bash
calculate_non_hpa_cpu() {
  local namespace="$1"
  
  local hpa_targets=$(kubectl get hpa -n "$namespace" \
    -o jsonpath='{.items[*].spec.scaleTargetRef.name}' 2>/dev/null)
  
  local total_millicores=0
  
  # ... Deployments and StatefulSets (unchanged) ...
  
  # Process DaemonSets - USE MAXIMUM NODE CAPACITY
  while read -r ds; do
    [[ -z "$ds" ]] && continue
    
    # Get pod CPU
    local pod_cpu=$(kubectl get daemonset "$ds" -n "$namespace" \
      -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')
    
    [[ -z "$pod_cpu" ]] && continue
    
    local pod_millicores=$(convert_cpu_to_millicores "$pod_cpu")
    
    # Get nodeSelector (if any)
    local node_selector=$(kubectl get daemonset "$ds" -n "$namespace" \
      -o jsonpath='{.spec.template.spec.nodeSelector}' | \
      jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
    
    # Determine max nodes
    local ds_max_nodes
    if [[ -z "$node_selector" ]]; then
      # No selector: use total cluster max
      ds_max_nodes=$(get_max_node_capacity)
      log_debug "DaemonSet $ds: ${pod_millicores}m × $ds_max_nodes max nodes = $((pod_millicores * ds_max_nodes))m"
    else
      # Has selector: estimate based on current ratio or specific type
      if [[ "$node_selector" == *"node-type=gpu"* ]]; then
        ds_max_nodes=$(get_max_gpu_nodes)
        log_debug "DaemonSet $ds (GPU): ${pod_millicores}m × $ds_max_nodes max GPU nodes = $((pod_millicores * ds_max_nodes))m"
      else
        ds_max_nodes=$(estimate_max_for_selector "$node_selector")
        log_debug "DaemonSet $ds (selector: $node_selector): ${pod_millicores}m × $ds_max_nodes estimated nodes = $((pod_millicores * ds_max_nodes))m"
      fi
    fi
    
    local ds_millicores=$((pod_millicores * ds_max_nodes))
    total_millicores=$((total_millicores + ds_millicores))
    
  done < <(kubectl get daemonset -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
  
  echo "$total_millicores"
}
```

---

## 📊 Real-World Examples

### Example 1: AWS EKS with Karpenter

**Cluster Setup:**
- Karpenter NodePool with `max-nodes: 200`
- Current nodes: 45
- DaemonSet: `aws-node` (VPC CNI plugin, 100m CPU per pod)

**Detection:**
```bash
$ get_max_node_capacity
# Output: 200 (from Karpenter NodePool)

$ calculate_daemonset_cpu "kube-system" "aws-node"
# DaemonSet aws-node: 100m × 200 max nodes = 20000m (20 cores)
```

**Quota Applied:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: kube-system-quota
  namespace: kube-system
spec:
  hard:
    limits.cpu: "25"  # 20 cores + 20% buffer = 24 → round up to 25
```

**Result:**
- ✅ Cluster scales to 180 nodes → DaemonSet uses 18 cores → within quota
- ✅ Safe capacity for growth to 200 nodes

### Example 2: GPU DaemonSet with NodeSelector

**Cluster Setup:**
- Total max nodes: 500 (Karpenter)
- GPU NodePool: max 50 nodes (p3.2xlarge instances)
- DaemonSet: `nvidia-device-plugin` (50m CPU per pod, nodeSelector: node-type=gpu)

**Detection:**
```bash
$ get_max_gpu_nodes
# Output: 50 (from Karpenter NodePool filtering p3 instances)

$ calculate_daemonset_cpu "gpu-workloads" "nvidia-device-plugin"
# DaemonSet nvidia-device-plugin (GPU): 50m × 50 max GPU nodes = 2500m (2.5 cores)
```

**Quota Applied:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-workloads-quota
  namespace: gpu-workloads
spec:
  hard:
    limits.cpu: "3"  # 2.5 cores + buffer = 3 cores
```

**Result:**
- ✅ Only GPU nodes counted (not all 500 nodes!)
- ✅ Accurate quota prevents over-provisioning

### Example 3: Fallback Mode (No Autoscaler Detected)

**Cluster Setup:**
- No Karpenter
- No AWS CLI available
- No ConfigMap
- Current nodes: 20

**Detection:**
```bash
$ get_max_node_capacity
# WARN: Using fallback max nodes: current (20) × 2 = 40

$ calculate_daemonset_cpu "default" "logging-agent"
# DaemonSet logging-agent: 100m × 40 max nodes = 4000m (4 cores)
```

**Quota Applied:**
```yaml
spec:
  hard:
    limits.cpu: "5"  # 4 cores + buffer
```

**Result:**
- ⚠️ Conservative estimate (2× current)
- ✅ Better than using current count (20 nodes)
- 📝 Administrator should create ConfigMap for accuracy

---

## ⚙️ Configuration Guide

### Option 1: Karpenter (Recommended)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general-purpose
spec:
  limits:
    resources:
      nodes: "200"  # ← CRITICAL: Explicit node limit
      cpu: "800"    # Alternative: 200 nodes × 4 vCPUs
```

**Why preferred:**
- Auto-detected (no manual config)
- Single source of truth
- Enforced by Karpenter

### Option 2: ConfigMap Override

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: forge-cluster-config
  namespace: forge-system
  annotations:
    forge.io/description: "Cluster capacity limits for DaemonSet quota calculations"
data:
  max-nodes: "200"           # Total max nodes
  max-gpu-nodes: "50"        # Max GPU nodes (node-type=gpu)
  max-spot-nodes: "150"      # Max spot nodes (capacity-type=spot)
  cloud-provider: "aws"      # Optional: aws, gcp, azure, on-prem
  autoscaler: "karpenter"    # Optional: karpenter, cluster-autoscaler, manual
```

**Create:**
```bash
kubectl create namespace forge-system 2>/dev/null || true

kubectl create configmap forge-cluster-config -n forge-system \
  --from-literal=max-nodes=200 \
  --from-literal=max-gpu-nodes=50 \
  --from-literal=cloud-provider=aws \
  --from-literal=autoscaler=karpenter
```

### Option 3: ASG Tags (AWS)

Tag your AutoScalingGroups:

```bash
aws autoscaling create-or-update-tags \
  --tags \
    ResourceId=eks-worker-asg-1,ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/my-cluster,Value=owned,PropagateAtLaunch=false \
    ResourceId=eks-worker-asg-1,ResourceType=auto-scaling-group,Key=forge.io/max-size,Value=100,PropagateAtLaunch=false
```

---

## 🧪 Testing

### Test Script

```bash
#!/bin/bash
# test-daemonset-max-capacity.sh

set -euo pipefail

source lib/forge-namespace-hardening.sh

echo "Testing DaemonSet max capacity detection..."
echo

# Test 1: Karpenter detection
echo "Test 1: Karpenter NodePool detection"
if kubectl get crd nodepools.karpenter.sh > /dev/null 2>&1; then
  MAX_NODES=$(get_karpenter_max_nodes)
  echo "  ✓ Karpenter max nodes: $MAX_NODES"
else
  echo "  ⊘ Karpenter not installed"
fi
echo

# Test 2: ConfigMap detection
echo "Test 2: ConfigMap override"
if kubectl get configmap forge-cluster-config -n forge-system > /dev/null 2>&1; then
  MAX_NODES=$(kubectl get configmap forge-cluster-config -n forge-system \
    -o jsonpath='{.data.max-nodes}')
  echo "  ✓ ConfigMap max-nodes: $MAX_NODES"
else
  echo "  ⊘ ConfigMap not found"
fi
echo

# Test 3: Fallback
echo "Test 3: Fallback calculation"
CURRENT_NODES=$(kubectl get nodes --no-headers | wc -l)
FALLBACK=$((CURRENT_NODES * 2))
echo "  Current nodes: $CURRENT_NODES"
echo "  Fallback max: $FALLBACK"
echo

# Test 4: GPU nodes
echo "Test 4: GPU node detection"
GPU_NODES=$(get_max_gpu_nodes 2>/dev/null || echo "0")
echo "  Max GPU nodes: $GPU_NODES"
echo

# Test 5: DaemonSet calculation
echo "Test 5: DaemonSet CPU calculation"
if kubectl get ds -n kube-system > /dev/null 2>&1; then
  DS_COUNT=$(kubectl get ds -n kube-system --no-headers 2>/dev/null | wc -l)
  echo "  DaemonSets in kube-system: $DS_COUNT"
  
  if [[ "$DS_COUNT" -gt 0 ]]; then
    TOTAL_CPU=$(calculate_non_hpa_cpu "kube-system")
    echo "  Total DaemonSet CPU (millicores): $TOTAL_CPU"
    echo "  Total DaemonSet CPU (cores): $((TOTAL_CPU / 1000))"
  fi
fi
echo

echo "✅ All tests complete"
```

### Expected Output

```
Testing DaemonSet max capacity detection...

Test 1: Karpenter NodePool detection
  ✓ Karpenter max nodes: 200

Test 2: ConfigMap override
  ✓ ConfigMap max-nodes: 200

Test 3: Fallback calculation
  Current nodes: 45
  Fallback max: 90

Test 4: GPU node detection
  Max GPU nodes: 50

Test 5: DaemonSet CPU calculation
  DaemonSets in kube-system: 3
  Total DaemonSet CPU (millicores): 60000
  Total DaemonSet CPU (cores): 60

✅ All tests complete
```

---

## 🚨 Edge Cases

### 1. Zero Current Nodes

```bash
# If cluster is brand new or nodes are drained
current_nodes=$(kubectl get nodes --no-headers | wc -l)
# current_nodes = 0

# Solution: Default to 1
[[ "$current_nodes" -eq 0 ]] && current_nodes=1
```

### 2. DaemonSet with Taints/Tolerations

```yaml
spec:
  template:
    spec:
      tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "monitoring"
        effect: "NoSchedule"
```

**Impact:** DaemonSet may run on ALL nodes despite taints.

**Solution:** Assume max capacity unless nodeSelector explicitly filters.

### 3. Multiple NodePools

```yaml
# NodePool 1: general-purpose (max 150 nodes)
# NodePool 2: gpu (max 50 nodes)
# NodePool 3: spot (max 100 nodes)

# Total max = 150 + 50 + 100 = 300 nodes
```

**Solution:** Sum all NodePools.

### 4. Cluster Autoscaler Min/Max

```bash
--min-size=10 --max-size=100
```

**Use max-size (100), not min-size (10)!**

---

## 📈 Monitoring

### Prometheus Metrics

```bash
# Export metric for current vs. max nodes
cat <<EOF | curl --data-binary @- http://localhost:9091/metrics/job/forge-operator
# HELP forge_cluster_max_nodes Maximum node capacity
# TYPE forge_cluster_max_nodes gauge
forge_cluster_max_nodes{source="karpenter"} $MAX_NODES

# HELP forge_cluster_current_nodes Current node count
# TYPE forge_cluster_current_nodes gauge
forge_cluster_current_nodes $CURRENT_NODES

# HELP forge_daemonset_quota_cpu_cores DaemonSet CPU quota (cores)
# TYPE forge_daemonset_quota_cpu_cores gauge
forge_daemonset_quota_cpu_cores{namespace="kube-system"} $DAEMONSET_CORES
EOF
```

### Alert on Drift

```yaml
# Prometheus alert
alert: DaemonSetQuotaNearMax
expr: |
  (forge_daemonset_quota_cpu_cores / forge_cluster_max_nodes) > 0.9
for: 5m
labels:
  severity: warning
annotations:
  summary: "DaemonSet quota approaching max capacity"
  description: "DaemonSet CPU quota is 90%+ of max cluster capacity"
```

---

## ✅ Checklist

**Before implementing namespace hardening:**

- [ ] Determine autoscaler: Karpenter, Cluster Autoscaler, or Manual
- [ ] Configure max node capacity (NodePool, ConfigMap, or ASG tags)
- [ ] Document GPU/Spot node limits (if applicable)
- [ ] Test DaemonSet detection in each namespace
- [ ] Validate quota calculations with `--dry-run`
- [ ] Set up monitoring for max_nodes vs current_nodes
- [ ] Create alerts for quota exhaustion warnings

---

## 📚 References

- [Karpenter NodePool Limits](https://karpenter.sh/docs/concepts/nodepools/)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
- [DaemonSet Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [ResourceQuota Best Practices](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

---

**Document Version:** 1.0.0  
**Last Updated:** 2026-02-11  
**Status:** Production Architecture
