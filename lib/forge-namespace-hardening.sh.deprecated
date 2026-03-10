#!/usr/bin/env bash

################################################################################
# forge-namespace-hardening.sh
#
# V2 implementation of namespace resource measurement using 4-phase algorithm.
# Uses utility functions from forge-namespace-operations.sh (convert_*, apply_buffer, etc.)
#
# Author: forge-helpers team
# Version: 2.0.0
# Date: 2026-02-12
################################################################################

set -euo pipefail

################################################################################
# Phase 1: Discovery - Build Namespace Workload Map
################################################################################

# Discovers all workloads in a namespace and collects their configurations
#
# Arguments:
#   $1 - Namespace name
#
# Outputs:
#   JSON array of workload objects with metadata
discover_namespace_workloads() {
    local namespace="${1:?Namespace name required}"
    
    log_debug "Phase 1: Discovering workloads in namespace '${namespace}'..."
    
    local workloads_json="[]"
    
    # Discover Deployments
    local deployments
    deployments=$(kubectl get deployment -n "${namespace}" -o json 2>/dev/null || echo '{"items":[]}')
    
    local deploy_count
    deploy_count=$(echo "${deployments}" | jq '.items | length')
    
    for ((i=0; i<deploy_count; i++)); do
        local deploy
        deploy=$(echo "${deployments}" | jq ".items[${i}]")
        
        local name replicas cpu_limit memory_limit
        name=$(echo "${deploy}" | jq -r '.metadata.name')
        replicas=$(echo "${deploy}" | jq -r '.spec.replicas // 1')
        cpu_limit=$(echo "${deploy}" | jq -r '.spec.template.spec.containers[0].resources.limits.cpu // "0"')
        memory_limit=$(echo "${deploy}" | jq -r '.spec.template.spec.containers[0].resources.limits.memory // "0"')
        
        # Check for HPA
        local has_hpa=false
        local hpa_max_replicas=0
        local hpa
        hpa=$(kubectl get hpa -n "${namespace}" -o json 2>/dev/null | \
              jq -r ".items[] | select(.spec.scaleTargetRef.kind == \"Deployment\" and .spec.scaleTargetRef.name == \"${name}\") | .spec.maxReplicas" 2>/dev/null || echo "")
        
        if [[ -n "${hpa}" && "${hpa}" != "null" ]]; then
            has_hpa=true
            hpa_max_replicas="${hpa}"
        fi
        
        # Check for KEDA
        local has_keda=false
        local keda_max_replicas=0
        local keda
        keda=$(kubectl get scaledobjects.keda.sh -n "${namespace}" -o json 2>/dev/null | \
               jq -r ".items[] | select(.spec.scaleTargetRef.kind == \"Deployment\" and .spec.scaleTargetRef.name == \"${name}\") | .spec.maxReplicaCount" 2>/dev/null || echo "")
        
        if [[ -n "${keda}" && "${keda}" != "null" ]]; then
            has_keda=true
            keda_max_replicas="${keda}"
        fi
        
        # Check for VPA
        local has_vpa=false
        local vpa_cpu_upper="0"
        local vpa_memory_upper="0"
        local vpa_age_days=0
        local vpa
        vpa=$(kubectl get vpa -n "${namespace}" -o json 2>/dev/null | \
              jq -r ".items[] | select(.spec.targetRef.kind == \"Deployment\" and .spec.targetRef.name == \"${name}\")" 2>/dev/null || echo "")
        
        if [[ -n "${vpa}" && "${vpa}" != "null" ]]; then
            local vpa_status
            vpa_status=$(echo "${vpa}" | jq -r '.status.recommendation.containerRecommendations[0].upperBound // empty')
            
            if [[ -n "${vpa_status}" ]]; then
                has_vpa=true
                vpa_cpu_upper=$(echo "${vpa}" | jq -r '.status.recommendation.containerRecommendations[0].upperBound.cpu // "0"')
                vpa_memory_upper=$(echo "${vpa}" | jq -r '.status.recommendation.containerRecommendations[0].upperBound.memory // "0"')
                
                # Calculate VPA age
                local vpa_time
                vpa_time=$(echo "${vpa}" | jq -r '.status.conditions[] | select(.type == "RecommendationProvided") | .lastTransitionTime // empty')
                if [[ -n "${vpa_time}" ]]; then
                    local vpa_timestamp current_timestamp
                    vpa_timestamp=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${vpa_time}" +%s 2>/dev/null || echo "0")
                    current_timestamp=$(date -u +%s)
                    vpa_age_days=$(( (current_timestamp - vpa_timestamp) / 86400 ))
                fi
            fi
        fi
        
        # Check for Goldilocks
        # TODO: Implement Goldilocks detection
        local has_goldilocks=false
        
        # Check for PDB
        local has_pdb=false
        local pdb_min_available=0
        local pdb
        pdb=$(kubectl get pdb -n "${namespace}" -o json 2>/dev/null | \
              jq -r ".items[] | select(.spec.selector.matchLabels.app == \"${name}\" or .spec.selector.matchLabels.\"app.kubernetes.io/name\" == \"${name}\") | .spec.minAvailable" 2>/dev/null || echo "")
        
        if [[ -n "${pdb}" && "${pdb}" != "null" && "${pdb}" =~ ^[0-9]+$ ]]; then
            has_pdb=true
            pdb_min_available="${pdb}"
        fi
        
        # Build workload object
        local workload_obj
        workload_obj=$(cat <<EOF
{
  "name": "${name}",
  "type": "Deployment",
  "replicas": ${replicas},
  "cpu_limit": "${cpu_limit}",
  "memory_limit": "${memory_limit}",
  "has_hpa": ${has_hpa},
  "hpa_max_replicas": ${hpa_max_replicas},
  "has_keda": ${has_keda},
  "keda_max_replicas": ${keda_max_replicas},
  "has_vpa": ${has_vpa},
  "vpa_cpu_upper": "${vpa_cpu_upper}",
  "vpa_memory_upper": "${vpa_memory_upper}",
  "vpa_age_days": ${vpa_age_days},
  "has_goldilocks": ${has_goldilocks},
  "has_pdb": ${has_pdb},
  "pdb_min_available": ${pdb_min_available},
  "pvc_count": 0
}
EOF
)
        
        workloads_json=$(echo "${workloads_json}" | jq ". + [${workload_obj}]")
    done
    
    # Discover StatefulSets
    local statefulsets
    statefulsets=$(kubectl get statefulset -n "${namespace}" -o json 2>/dev/null || echo '{"items":[]}')
    
    local sts_count
    sts_count=$(echo "${statefulsets}" | jq '.items | length')
    
    for ((i=0; i<sts_count; i++)); do
        local sts
        sts=$(echo "${statefulsets}" | jq ".items[${i}]")
        
        local name replicas cpu_limit memory_limit pvc_count
        name=$(echo "${sts}" | jq -r '.metadata.name')
        replicas=$(echo "${sts}" | jq -r '.spec.replicas // 1')
        cpu_limit=$(echo "${sts}" | jq -r '.spec.template.spec.containers[0].resources.limits.cpu // "0"')
        memory_limit=$(echo "${sts}" | jq -r '.spec.template.spec.containers[0].resources.limits.memory // "0"')
        
        # Count volumeClaimTemplates (each replica gets one PVC per template)
        pvc_count=$(echo "${sts}" | jq '.spec.volumeClaimTemplates | length')
        
        # Check for HPA (StatefulSets can have HPA)
        local has_hpa=false
        local hpa_max_replicas=0
        local hpa
        hpa=$(kubectl get hpa -n "${namespace}" -o json 2>/dev/null | \
              jq -r ".items[] | select(.spec.scaleTargetRef.kind == \"StatefulSet\" and .spec.scaleTargetRef.name == \"${name}\") | .spec.maxReplicas" 2>/dev/null || echo "")
        
        if [[ -n "${hpa}" && "${hpa}" != "null" ]]; then
            has_hpa=true
            hpa_max_replicas="${hpa}"
        fi
        
        # Check for KEDA
        local has_keda=false
        local keda_max_replicas=0
        local keda
        keda=$(kubectl get scaledobjects.keda.sh -n "${namespace}" -o json 2>/dev/null | \
               jq -r ".items[] | select(.spec.scaleTargetRef.kind == \"StatefulSet\" and .spec.scaleTargetRef.name == \"${name}\") | .spec.maxReplicaCount" 2>/dev/null || echo "")
        
        if [[ -n "${keda}" && "${keda}" != "null" ]]; then
            has_keda=true
            keda_max_replicas="${keda}"
        fi
        
        # Check for VPA
        local has_vpa=false
        local vpa_cpu_upper="0"
        local vpa_memory_upper="0"
        local vpa_age_days=0
        local vpa
        vpa=$(kubectl get vpa -n "${namespace}" -o json 2>/dev/null | \
              jq -r ".items[] | select(.spec.targetRef.kind == \"StatefulSet\" and .spec.targetRef.name == \"${name}\")" 2>/dev/null || echo "")
        
        if [[ -n "${vpa}" && "${vpa}" != "null" ]]; then
            local vpa_status
            vpa_status=$(echo "${vpa}" | jq -r '.status.recommendation.containerRecommendations[0].upperBound // empty')
            
            if [[ -n "${vpa_status}" ]]; then
                has_vpa=true
                vpa_cpu_upper=$(echo "${vpa}" | jq -r '.status.recommendation.containerRecommendations[0].upperBound.cpu // "0"')
                vpa_memory_upper=$(echo "${vpa}" | jq -r '.status.recommendation.containerRecommendations[0].upperBound.memory // "0"')
                
                # Calculate VPA age
                local vpa_time
                vpa_time=$(echo "${vpa}" | jq -r '.status.conditions[] | select(.type == "RecommendationProvided") | .lastTransitionTime // empty')
                if [[ -n "${vpa_time}" ]]; then
                    local vpa_timestamp current_timestamp
                    vpa_timestamp=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${vpa_time}" +%s 2>/dev/null || echo "0")
                    current_timestamp=$(date -u +%s)
                    vpa_age_days=$(( (current_timestamp - vpa_timestamp) / 86400 ))
                fi
            fi
        fi
        
        # Check for Goldilocks
        # TODO: Implement Goldilocks detection
        local has_goldilocks=false
        
        # Check for PDB
        local has_pdb=false
        local pdb_min_available=0
        local pdb
        pdb=$(kubectl get pdb -n "${namespace}" -o json 2>/dev/null | \
              jq -r ".items[] | select(.spec.selector.matchLabels.app == \"${name}\" or .spec.selector.matchLabels.\"app.kubernetes.io/name\" == \"${name}\") | .spec.minAvailable" 2>/dev/null || echo "")
        
        if [[ -n "${pdb}" && "${pdb}" != "null" && "${pdb}" =~ ^[0-9]+$ ]]; then
            has_pdb=true
            pdb_min_available="${pdb}"
        fi
        
        # Build workload object
        local workload_obj
        workload_obj=$(cat <<EOF
{
  "name": "${name}",
  "type": "StatefulSet",
  "replicas": ${replicas},
  "cpu_limit": "${cpu_limit}",
  "memory_limit": "${memory_limit}",
  "has_hpa": ${has_hpa},
  "hpa_max_replicas": ${hpa_max_replicas},
  "has_keda": ${has_keda},
  "keda_max_replicas": ${keda_max_replicas},
  "has_vpa": ${has_vpa},
  "vpa_cpu_upper": "${vpa_cpu_upper}",
  "vpa_memory_upper": "${vpa_memory_upper}",
  "vpa_age_days": ${vpa_age_days},
  "has_goldilocks": ${has_goldilocks},
  "has_pdb": ${has_pdb},
  "pdb_min_available": ${pdb_min_available},
  "pvc_count": ${pvc_count}
}
EOF
)
        
        workloads_json=$(echo "${workloads_json}" | jq ". + [${workload_obj}]")
    done
    
    # TODO: Add DaemonSets discovery
    
    echo "${workloads_json}"
}

################################################################################
# Phase 2: Resolution - Apply Precedence Rules Per Workload
################################################################################

# Resolves CPU limit for a workload using precedence rules
# Precedence: Goldilocks → VPA (if age >= min_days) → Pod manifest limits
#
# Arguments:
#   $1 - Workload JSON object
#   $2 - Minimum VPA age in days (default: 7)
#
# Outputs:
#   CPU in millicores (integer)
resolve_workload_cpu_limit() {
    local workload="${1:?Workload JSON required}"
    local min_vpa_age_days="${2:-7}"
    
    # TODO: Check Goldilocks first (when implemented)
    
    # Check VPA (if age is sufficient)
    local has_vpa vpa_age_days vpa_cpu_upper
    has_vpa=$(echo "${workload}" | jq -r '.has_vpa')
    vpa_age_days=$(echo "${workload}" | jq -r '.vpa_age_days')
    vpa_cpu_upper=$(echo "${workload}" | jq -r '.vpa_cpu_upper // "0"')
    
    if [[ "${has_vpa}" == "true" && ${vpa_age_days} -ge ${min_vpa_age_days} && "${vpa_cpu_upper}" != "0" ]]; then
        convert_cpu_to_millicores "${vpa_cpu_upper}"
        return 0
    fi
    
    # Fallback to Pod manifest limits
    local cpu_limit
    cpu_limit=$(echo "${workload}" | jq -r '.cpu_limit // "0"')
    convert_cpu_to_millicores "${cpu_limit}"
}

# Resolves memory limit for a workload using precedence rules
# Precedence: Goldilocks → VPA (if age >= min_days) → Pod manifest limits
#
# Arguments:
#   $1 - Workload JSON object
#   $2 - Minimum VPA age in days (default: 7)
#
# Outputs:
#   Memory in bytes (integer)
resolve_workload_memory_limit() {
    local workload="${1:?Workload JSON required}"
    local min_vpa_age_days="${2:-7}"
    
    # TODO: Check Goldilocks first (when implemented)
    
    # Check VPA (if age is sufficient)
    local has_vpa vpa_age_days vpa_memory_upper
    has_vpa=$(echo "${workload}" | jq -r '.has_vpa')
    vpa_age_days=$(echo "${workload}" | jq -r '.vpa_age_days')
    vpa_memory_upper=$(echo "${workload}" | jq -r '.vpa_memory_upper // "0"')
    
    if [[ "${has_vpa}" == "true" && ${vpa_age_days} -ge ${min_vpa_age_days} && "${vpa_memory_upper}" != "0" ]]; then
        convert_memory_to_bytes "${vpa_memory_upper}"
        return 0
    fi
    
    # Fallback to Pod manifest limits
    local memory_limit
    memory_limit=$(echo "${workload}" | jq -r '.memory_limit // "0"')
    convert_memory_to_bytes "${memory_limit}"
}

# Resolves max replicas for a workload using precedence rules
# Precedence: KEDA → HPA → Deployment/StatefulSet.spec.replicas
#
# Arguments:
#   $1 - Workload JSON object
#
# Outputs:
#   Max replicas (integer)
resolve_workload_max_replicas() {
    local workload="${1:?Workload JSON required}"
    
    # Check KEDA first
    local has_keda keda_max_replicas
    has_keda=$(echo "${workload}" | jq -r '.has_keda')
    keda_max_replicas=$(echo "${workload}" | jq -r '.keda_max_replicas // 0')
    
    if [[ "${has_keda}" == "true" && ${keda_max_replicas} -gt 0 ]]; then
        echo "${keda_max_replicas}"
        return 0
    fi
    
    # Check HPA
    local has_hpa hpa_max_replicas
    has_hpa=$(echo "${workload}" | jq -r '.has_hpa')
    hpa_max_replicas=$(echo "${workload}" | jq -r '.hpa_max_replicas // 0')
    
    if [[ "${has_hpa}" == "true" && ${hpa_max_replicas} -gt 0 ]]; then
        echo "${hpa_max_replicas}"
        return 0
    fi
    
    # Fallback to spec.replicas
    local replicas
    replicas=$(echo "${workload}" | jq -r '.replicas // 1')
    echo "${replicas}"
}

# Resolves max replicas with PDB overhead
# If PDB minAvailable >= max_replicas, add +1 for disruption handling
#
# Arguments:
#   $1 - Workload JSON object
#
# Outputs:
#   Max replicas with PDB overhead (integer)
resolve_workload_max_replicas_with_pdb() {
    local workload="${1:?Workload JSON required}"
    
    local max_replicas
    max_replicas=$(resolve_workload_max_replicas "${workload}")
    
    # Check PDB
    local has_pdb pdb_min_available
    has_pdb=$(echo "${workload}" | jq -r '.has_pdb')
    pdb_min_available=$(echo "${workload}" | jq -r '.pdb_min_available // 0')
    
    # If PDB minAvailable >= max_replicas, need +1 pod for disruptions
    if [[ "${has_pdb}" == "true" && ${pdb_min_available} -ge ${max_replicas} ]]; then
        echo $((max_replicas + 1))
        return 0
    fi
    
    echo "${max_replicas}"
}

################################################################################
# Phase 3: Calculation - Calculate Max Resources Per Workload
################################################################################

# Calculates max CPU resources for a single workload
# Formula: per-pod-cpu × max-replicas
#
# Arguments:
#   $1 - Workload JSON object
#   $2 - Minimum VPA age in days
#
# Outputs:
#   Max CPU in millicores
calculate_workload_max_cpu() {
    local workload="${1:?Workload JSON required}"
    local min_vpa_age_days="${2:-7}"
    
    local per_pod_cpu max_replicas
    per_pod_cpu=$(resolve_workload_cpu_limit "${workload}" "${min_vpa_age_days}")
    max_replicas=$(resolve_workload_max_replicas "${workload}")
    
    echo $((per_pod_cpu * max_replicas))
}

# Calculates max memory resources for a single workload
# Formula: per-pod-memory × max-replicas
#
# Arguments:
#   $1 - Workload JSON object
#   $2 - Minimum VPA age in days
#
# Outputs:
#   Max memory in bytes
calculate_workload_max_memory() {
    local workload="${1:?Workload JSON required}"
    local min_vpa_age_days="${2:-7}"
    
    local per_pod_memory max_replicas
    per_pod_memory=$(resolve_workload_memory_limit "${workload}" "${min_vpa_age_days}")
    max_replicas=$(resolve_workload_max_replicas "${workload}")
    
    echo $((per_pod_memory * max_replicas))
}

# Calculates max PVCs for a single workload (StatefulSets only)
# Formula: pvc-count-per-replica × max-replicas
#
# Arguments:
#   $1 - Workload JSON object
#
# Outputs:
#   Max PVC count (0 for non-StatefulSets)
calculate_workload_max_pvcs() {
    local workload="${1:?Workload JSON required}"
    
    local workload_type pvc_count max_replicas
    workload_type=$(echo "${workload}" | jq -r '.type')
    
    # Only StatefulSets have PVCs
    if [[ "${workload_type}" != "StatefulSet" ]]; then
        echo "0"
        return 0
    fi
    
    pvc_count=$(echo "${workload}" | jq -r '.pvc_count // 0')
    max_replicas=$(resolve_workload_max_replicas "${workload}")
    
    # Each replica gets pvc_count PVCs
    echo $((pvc_count * max_replicas))
}

################################################################################
# Phase 4: Aggregation - Sum All Workloads
################################################################################

# NOTE: measure_namespace_resources() function is defined in forge-namespace-operations.sh
# This file used to have a duplicate, but it's been removed to avoid conflicts.
# The canonical implementation with VPA/HPA/KEDA detection and multi-container support
# is in lib/forge-namespace-operations.sh

