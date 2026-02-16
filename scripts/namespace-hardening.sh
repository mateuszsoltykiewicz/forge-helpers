#!/usr/bin/env bash

################################################################################
# namespace-hardening.sh
#
# Purpose:
#   Harden a Kubernetes namespace by applying resource quotas, network policies,
#   and security constraints based on MEASURED MAXIMUM CAPACITY (not current usage).
#
# Philosophy:
#   We measure CAPACITY (what COULD be used at peak), not USAGE (what IS used now).
#   This means hardening can be done IMMEDIATELY after deployment - no waiting needed!
#
# Measurement Sources (in priority order):
#   1. Goldilocks VPA recommendations (historical, pre-calculated)
#   2. VPA upperBound (P99 + headroom, 7+ days data)
#   3. HPA maxReplicas (declared maximum scale)
#   4. Pod limits (static manifest declarations)
#
# DaemonSets:
#   Max capacity calculated from maximum node count (Karpenter/ASG limits),
#   NOT current running pods.
#
# Why No Waiting?
#   - HPA maxReplicas: Declared in manifest (static config)
#   - VPA upperBound: Already calculated from 7+ days historical data
#   - Max nodes: Defined in Karpenter/ASG configuration
#   - Pod limits: Static values in deployment manifests
#   
#   None of these values change based on current runtime metrics!
#   See docs/WHY_NO_WAITING.md for comprehensive explanation.
#
# Usage:
#   ./namespace-hardening.sh --name <namespace> [options]
#
# Examples:
#   # Basic hardening (immediate after deployment!)
#   ./namespace-hardening.sh --name my-app
#
#   # Custom buffer and minimum VPA age
#   ./namespace-hardening.sh --name my-app --buffer-percent 30 --min-vpa-age-days 14
#
#   # Dry-run to preview changes
#   ./namespace-hardening.sh --name my-app --dry-run
#
#   # Force re-hardening (ignore "already hardened" status)
#   ./namespace-hardening.sh --name my-app --force
#
#   # Skip Vault bundle creation
#   ./namespace-hardening.sh --name my-app --skip-vault
#
# Author: forge-helpers team
# Version: 2.0.0
# Date: 2026-02-12
################################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source dependencies
# shellcheck source=../lib/forge-core.sh
source "${REPO_ROOT}/lib/forge-core.sh"
# shellcheck source=../lib/forge-namespace-operations.sh
source "${REPO_ROOT}/lib/forge-namespace-operations.sh"
# shellcheck source=../lib/forge-namespace-hardening.sh
source "${REPO_ROOT}/lib/forge-namespace-hardening.sh"

# Alias for compatibility (forge-core uses log_warning, but we prefer log_warn)
log_warn() { log_warning "$@"; }

################################################################################
# Default Configuration
################################################################################

HARDENING_DEFAULT_BUFFER_PERCENT=20          # 20% buffer above measured capacity
HARDENING_DEFAULT_MIN_VPA_AGE_DAYS=7         # VPA must have 7+ days of data
HARDENING_DEFAULT_GRACE_PERIOD=0             # No grace period needed (immediate hardening!)
# Note: No minimum pod quota - we use ACTUAL measured capacity
# - No HPA, 2 replicas → pods = 2
# - HPA maxReplicas=10 → pods = 10
# - HPA maxReplicas=10 + PDB minAvailable=10 → pods = 11 (extra for disruption)
# - DaemonSet + max_nodes=100 → pods = 100
# - Mixed workloads → pods = sum(all above)
HARDENING_MIN_CPU_MILLICORES=100             # Minimum CPU quota (100m)
HARDENING_MIN_MEMORY_BYTES=$((128 * 1024 * 1024))  # Minimum memory quota (128Mi)

################################################################################
# Global Variables
################################################################################

NAMESPACE=""
BUFFER_PERCENT="${HARDENING_DEFAULT_BUFFER_PERCENT}"
MIN_VPA_AGE_DAYS="${HARDENING_DEFAULT_MIN_VPA_AGE_DAYS}"
GRACE_PERIOD="${HARDENING_DEFAULT_GRACE_PERIOD}"
DRY_RUN=false
FORCE=false
SKIP_VAULT=false
SKIP_NETWORK_POLICY=false
VERBOSE=false

################################################################################
# Functions
################################################################################

show_help() {
    cat <<EOF
Usage: $(basename "$0") --name <namespace> [options]

Harden a Kubernetes namespace by applying resource quotas, network policies,
and security constraints based on measured maximum capacity.

💡 Key Principle: Hardening can be done IMMEDIATELY after deployment!
   We measure DECLARED MAXIMUMS (HPA maxReplicas, VPA upperBound, max nodes),
   not current runtime usage. No waiting period needed!

Required Arguments:
  --name <namespace>              Name of the namespace to harden

Optional Arguments:
  --buffer-percent <percent>      Buffer percentage above measured capacity
                                  (default: ${HARDENING_DEFAULT_BUFFER_PERCENT}%)
  --min-vpa-age-days <days>       Minimum VPA recommendation age in days
                                  (default: ${HARDENING_DEFAULT_MIN_VPA_AGE_DAYS} days)
  --grace-period <seconds>        Grace period before hardening (deprecated, always 0)
                                  (default: ${HARDENING_DEFAULT_GRACE_PERIOD}s)
  --force                         Force re-hardening even if already hardened
  --dry-run                       Show what would be done without making changes
  --skip-vault                    Skip Vault bundle creation
  --skip-network-policy           Skip NetworkPolicy creation
  --verbose                       Enable verbose output
  --help                          Show this help message

Measurement Sources (priority order):
  1. Goldilocks VPA recommendations (historical, pre-calculated)
  2. VPA upperBound (P99 + headroom, 7+ days of data)
  3. HPA maxReplicas (declared maximum scale, NOT current replicas)
  4. Pod limits (static manifest values)

DaemonSets:
  Max capacity = max nodes × pod limits × buffer
  Max nodes from: Karpenter → Cloud provider API → ConfigMap → Fallback (100)

Examples:
  # Basic hardening (run IMMEDIATELY after helm install!)
  $(basename "$0") --name my-app

  # Custom buffer for high-variability workloads
  $(basename "$0") --name my-app --buffer-percent 50

  # Require 14 days of VPA data (more conservative)
  $(basename "$0") --name my-app --min-vpa-age-days 14

  # Preview changes without applying
  $(basename "$0") --name my-app --dry-run

  # Force re-hardening after config changes
  $(basename "$0") --name my-app --force

  # Harden without Vault integration
  $(basename "$0") --name my-app --skip-vault

Workflow:
  1. Deploy application:    helm install my-app ./chart -n my-app
  2. Harden IMMEDIATELY:    ./namespace-hardening.sh --name my-app
  3. Verify compliance:     ./namespace-verify.sh --name my-app

Why No Waiting?
  - HPA maxReplicas=10 is declared in manifest (doesn't change with traffic)
  - VPA upperBound=600m is already calculated from 7+ days historical data
  - Max nodes=100 is defined in Karpenter/ASG config (infrastructure limit)
  - Pod limits=500m are static values in deployment manifests
  
  Current usage (3 replicas, 200m CPU, 6 nodes) is IGNORED.
  We measure what COULD happen at peak, not what IS happening now.

Exit Codes:
  0  - Success
  1  - Invalid arguments or validation failure
  2  - Hardening failed
  3  - Namespace not found or not managed

See Also:
  - docs/WHY_NO_WAITING.md - Comprehensive explanation of measurement philosophy
  - docs/NAMESPACE_OPERATIONS_V2.md - Architecture and design decisions
  - docs/RESOURCE_MEASUREMENT.md - Detailed measurement algorithms

EOF
}

parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                NAMESPACE="$2"
                shift 2
                ;;
            --buffer-percent)
                BUFFER_PERCENT="$2"
                shift 2
                ;;
            --min-vpa-age-days)
                MIN_VPA_AGE_DAYS="$2"
                shift 2
                ;;
            --grace-period)
                GRACE_PERIOD="$2"
                if [[ "${GRACE_PERIOD}" -ne 0 ]]; then
                    log_warn "Grace period is deprecated and ignored (always 0). Hardening can be done immediately!"
                    GRACE_PERIOD=0
                fi
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-vault)
                SKIP_VAULT=true
                shift
                ;;
            --skip-network-policy)
                SKIP_NETWORK_POLICY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${NAMESPACE}" ]]; then
        log_error "Namespace name is required (--name)"
        show_help
        exit 1
    fi

    # Validate numeric arguments
    if ! [[ "${BUFFER_PERCENT}" =~ ^[0-9]+$ ]] || [[ "${BUFFER_PERCENT}" -lt 0 ]] || [[ "${BUFFER_PERCENT}" -gt 1000 ]]; then
        log_error "Buffer percent must be a number between 0 and 1000"
        exit 1
    fi

    if ! [[ "${MIN_VPA_AGE_DAYS}" =~ ^[0-9]+$ ]] || [[ "${MIN_VPA_AGE_DAYS}" -lt 0 ]]; then
        log_error "Minimum VPA age must be a non-negative number"
        exit 1
    fi
}

preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check if namespace exists
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_error "Namespace '${NAMESPACE}' does not exist"
        log_info "Create it first with: ./namespace-create.sh --name ${NAMESPACE} --type <type>"
        exit 3
    fi

    # Check if namespace is managed
    local managed
    managed=$(kubectl get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels.moai\.forge\.io/managed}' 2>/dev/null || echo "")
    if [[ "${managed}" != "true" ]]; then
        log_error "Namespace '${NAMESPACE}' is not managed by forge-helpers"
        log_info "Only namespaces created with namespace-create.sh can be hardened"
        exit 3
    fi

    # Check if already hardened
    local already_hardened
    already_hardened=$(kubectl get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels.moai\.forge\.io/hardened}' 2>/dev/null || echo "false")
    if [[ "${already_hardened}" == "true" ]] && [[ "${FORCE}" != "true" ]]; then
        log_warn "Namespace '${NAMESPACE}' is already hardened"
        log_info "Use --force to re-harden (e.g., after config changes or new workloads)"
        log_info ""
        log_info "When to re-harden:"
        log_info "  ✅ HPA maxReplicas changed (10 → 20)"
        log_info "  ✅ New workloads added to namespace"
        log_info "  ✅ VPA recommendations matured (now 14+ days old)"
        log_info "  ✅ DaemonSet added or max nodes increased"
        log_info ""
        log_info "When NOT to re-harden:"
        log_info "  ❌ Current replica count changed (3 → 8, still under maxReplicas=10)"
        log_info "  ❌ Current CPU usage increased (200m → 400m, still under VPA upperBound=600m)"
        log_info "  ❌ Current node count increased (6 → 12, still under max nodes=100)"
        exit 0
    fi

    # Check if namespace has workloads
    local workload_count
    workload_count=$(kubectl get deployments,statefulsets,daemonsets,replicasets -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${workload_count}" -eq 0 ]]; then
        log_warn "Namespace '${NAMESPACE}' has no workloads (Deployments, StatefulSets, DaemonSets, or ReplicaSets)"
        log_info "Deploy workloads first, then run hardening"
        log_info ""
        log_info "Example workflow:"
        log_info "  1. Create namespace:  ./namespace-create.sh --name ${NAMESPACE} --type application"
        log_info "  2. Deploy app:        helm install my-app ./chart -n ${NAMESPACE}"
        log_info "  3. Harden IMMEDIATE:  ./namespace-hardening.sh --name ${NAMESPACE}"
        exit 1
    fi

    log_success "Pre-flight checks passed"
}

measure_resources() {
    log_info "Measuring namespace resources..."
    log_info "Sources: Goldilocks → VPA (${MIN_VPA_AGE_DAYS}+ days) → HPA (maxReplicas) → Pod limits"
    log_info "Buffer: ${BUFFER_PERCENT}%"

    # Call library function to measure resources
    local measurement_json
    measurement_json=$(measure_namespace_resources "${NAMESPACE}" "${BUFFER_PERCENT}" "${MIN_VPA_AGE_DAYS}")

    if [[ -z "${measurement_json}" ]] || [[ "${measurement_json}" == "null" ]]; then
        log_error "Failed to measure namespace resources"
        exit 2
    fi

    # Extract values
    CPU_MILLICORES=$(echo "${measurement_json}" | jq -r '.cpu_millicores')
    MEMORY_BYTES=$(echo "${measurement_json}" | jq -r '.memory_bytes')
    PODS=$(echo "${measurement_json}" | jq -r '.pods')
    PVCS=$(echo "${measurement_json}" | jq -r '.pvcs // 0')
    SOURCE=$(echo "${measurement_json}" | jq -r '.source')

    # Apply minimums (CPU and memory only, NOT pods)
    if [[ "${CPU_MILLICORES}" -lt "${HARDENING_MIN_CPU_MILLICORES}" ]]; then
        log_warn "Measured CPU (${CPU_MILLICORES}m) below minimum, using ${HARDENING_MIN_CPU_MILLICORES}m"
        CPU_MILLICORES="${HARDENING_MIN_CPU_MILLICORES}"
    fi

    if [[ "${MEMORY_BYTES}" -lt "${HARDENING_MIN_MEMORY_BYTES}" ]]; then
        local min_memory_human
        min_memory_human=$(convert_bytes_to_human "${HARDENING_MIN_MEMORY_BYTES}")
        log_warn "Measured memory below minimum, using ${min_memory_human}"
        MEMORY_BYTES="${HARDENING_MIN_MEMORY_BYTES}"
    fi

    # NO minimum for pods - use actual measured capacity!
    # - No HPA, 2 replicas → pods = 2
    # - HPA maxReplicas=10 → pods = 10  
    # - HPA + PDB → pods = maxReplicas + PDB overhead
    # - DaemonSet → pods = max_nodes
    # - Mixed → pods = sum(all workloads)

    # Display measurement results
    local cpu_human="${CPU_MILLICORES}m"
    if [[ "${CPU_MILLICORES}" -ge 1000 ]]; then
        cpu_human="$((CPU_MILLICORES / 1000)) cores (${CPU_MILLICORES}m)"
    fi
    local memory_human
    memory_human=$(convert_bytes_to_human "${MEMORY_BYTES}")

    log_success "Resource measurement complete"
    log_info ""
    log_info "📊 Measured Capacity (with ${BUFFER_PERCENT}% buffer):"
    log_info "  Source:  ${SOURCE}"
    log_info "  CPU:     ${cpu_human}"
    log_info "  Memory:  ${memory_human}"
    log_info "  Pods:    ${PODS}"
    log_info ""

    if [[ "${VERBOSE}" == "true" ]]; then
        log_info "💡 Why these values?"
        case "${SOURCE}" in
            goldilocks)
                log_info "  Using Goldilocks VPA recommendations (historical, pre-calculated)"
                ;;
            vpa)
                log_info "  Using VPA upperBound (P99 + headroom from ${MIN_VPA_AGE_DAYS}+ days data)"
                ;;
            hpa)
                log_info "  Using HPA maxReplicas (DECLARED maximum, not current replica count)"
                ;;
            pod-limits)
                log_info "  Using pod limits (static manifest values, fallback method)"
                ;;
        esac
        log_info "  These are MAXIMUM CAPACITY values, not current usage!"
        log_info "  See docs/WHY_NO_WAITING.md for detailed explanation"
        log_info ""
    fi
}

apply_hardening() {
    local ns_type
    ns_type=$(get_namespace_type "${NAMESPACE}")

    log_info "Applying hardening to namespace '${NAMESPACE}' (type: ${ns_type})..."

    # Apply ResourceQuota
    log_info "Creating ResourceQuota..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create ResourceQuota with:"
        log_info "  limits.cpu: ${CPU_MILLICORES}m"
        log_info "  limits.memory: $(convert_bytes_to_human "${MEMORY_BYTES}")"
        log_info "  pods: ${PODS}"
        if [[ ${PVCS} -gt 0 ]]; then
            log_info "  persistentvolumeclaims: ${PVCS}"
        fi
    else
        apply_resource_quota "${NAMESPACE}" "${CPU_MILLICORES}" "${MEMORY_BYTES}" "${PODS}" "${PVCS}"
        log_success "ResourceQuota created"
    fi

    # Apply NetworkPolicy (for specific namespace types)
    if [[ "${SKIP_NETWORK_POLICY}" != "true" ]]; then
        case "${ns_type}" in
            application|middleware|forge-jobs)
                log_info "Creating NetworkPolicy (type: ${ns_type})..."
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY-RUN] Would create NetworkPolicy for ${ns_type} namespace"
                else
                    apply_network_policy "${NAMESPACE}" "${ns_type}"
                    log_success "NetworkPolicy created"
                fi
                ;;
            forge-operator)
                log_info "Creating NetworkPolicy with API server access (type: ${ns_type})..."
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY-RUN] Would create NetworkPolicy allowing API server access"
                else
                    apply_network_policy "${NAMESPACE}" "${ns_type}"
                    log_success "NetworkPolicy created"
                fi
                ;;
            *)
                log_info "Skipping NetworkPolicy (not applicable for type: ${ns_type})"
                ;;
        esac
    else
        log_info "Skipping NetworkPolicy (--skip-network-policy)"
    fi

    # Upgrade to restricted PSS for application namespaces
    if [[ "${ns_type}" == "application" ]]; then
        log_info "Upgrading to restricted Pod Security Standard..."
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would set pod-security.kubernetes.io/enforce=restricted"
        else
            kubectl label namespace "${NAMESPACE}" \
                pod-security.kubernetes.io/enforce=restricted \
                pod-security.kubernetes.io/audit=restricted \
                pod-security.kubernetes.io/warn=restricted \
                --overwrite
            log_success "Pod Security Standard upgraded to restricted"
        fi
    fi

    # Create Vault bundle (for application namespaces only)
    if [[ "${SKIP_VAULT}" != "true" ]] && [[ "${ns_type}" == "application" ]]; then
        log_info "Creating Vault bundle (ServiceAccount, SecretStore, ExternalSecret)..."
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would create Vault bundle for secrets management"
        else
            if command -v create_vault_bundle &>/dev/null; then
                create_vault_bundle "${NAMESPACE}"
                log_success "Vault bundle created"
            else
                log_warn "create_vault_bundle function not available, skipping Vault setup"
            fi
        fi
    else
        if [[ "${SKIP_VAULT}" == "true" ]]; then
            log_info "Skipping Vault bundle (--skip-vault)"
        else
            log_info "Skipping Vault bundle (not applicable for type: ${ns_type})"
        fi
    fi

    # Update hardening status labels
    log_info "Updating hardening status labels..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would update labels:"
        log_info "  moai.forge.io/hardened: true"
        log_info "  moai.forge.io/hardened-at: $(date -u +%Y%m%d-%H%M%S)"
        log_info "  moai.forge.io/hardening-source: ${SOURCE}"
        log_info "  moai.forge.io/quota-cpu: ${CPU_MILLICORES}m"
        log_info "  moai.forge.io/quota-memory: $(convert_bytes_to_human "${MEMORY_BYTES}")"
        log_info "  moai.forge.io/quota-pods: ${PODS}"
    else
        update_hardening_status "${NAMESPACE}" "${SOURCE}" "${CPU_MILLICORES}m" \
            "$(convert_bytes_to_human "${MEMORY_BYTES}")" "${PODS}"
        log_success "Hardening status updated"
    fi

    log_success "Hardening complete!"
}

show_summary() {
    local ns_type
    ns_type=$(get_namespace_type "${NAMESPACE}")

    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "✅ Namespace Hardening Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""
    log_info "Namespace:          ${NAMESPACE}"
    log_info "Type:               ${ns_type}"
    log_info "Hardening Source:   ${SOURCE}"
    log_info "Buffer:             ${BUFFER_PERCENT}%"
    log_info ""
    log_info "📊 Applied Resource Quotas:"
    log_info "  CPU:              ${CPU_MILLICORES}m"
    log_info "  Memory:           $(convert_bytes_to_human "${MEMORY_BYTES}")"
    log_info "  Pods:             ${PODS}"
    log_info ""

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "🔍 DRY-RUN MODE - No changes were made"
        log_info ""
    else
        log_info "🔒 Security Applied:"
        log_info "  ✓ ResourceQuota created"
        
        case "${ns_type}" in
            application|middleware|forge-jobs|forge-operator)
                log_info "  ✓ NetworkPolicy created"
                ;;
            *)
                log_info "  - NetworkPolicy (not applicable)"
                ;;
        esac
        
        if [[ "${ns_type}" == "application" ]]; then
            log_info "  ✓ Pod Security Standard: restricted"
            if [[ "${SKIP_VAULT}" != "true" ]]; then
                log_info "  ✓ Vault bundle created"
            else
                log_info "  - Vault bundle (skipped)"
            fi
        else
            log_info "  - Pod Security Standard: baseline"
            log_info "  - Vault bundle (not applicable)"
        fi
        log_info ""
    fi

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "📋 Next Steps:"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""
    log_info "  1. Verify compliance:"
    log_info "     ./namespace-verify.sh --name ${NAMESPACE}"
    log_info ""
    log_info "  2. Check ResourceQuota usage:"
    log_info "     kubectl describe resourcequota -n ${NAMESPACE}"
    log_info ""
    log_info "  3. Test workload deployment:"
    log_info "     kubectl get pods -n ${NAMESPACE}"
    log_info ""
    log_info "  4. When to re-harden (use --force):"
    log_info "     ✅ HPA maxReplicas changed (scale limit increased)"
    log_info "     ✅ New workloads added to namespace"
    log_info "     ✅ VPA recommendations matured (more historical data)"
    log_info "     ✅ DaemonSet added or max nodes increased"
    log_info ""
    log_info "  5. When NOT to re-harden:"
    log_info "     ❌ Current replica count fluctuated (still under maxReplicas)"
    log_info "     ❌ Current CPU/memory usage changed (still under quota)"
    log_info "     ❌ Current node count changed (still under max nodes)"
    log_info ""
    log_info "💡 Remember: Quotas are based on MAXIMUM CAPACITY, not current usage!"
    log_info "   See docs/WHY_NO_WAITING.md for detailed explanation."
    log_info ""
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting namespace hardening..."
    log_info ""

    # Parse arguments
    parse_arguments "$@"

    # Pre-flight checks
    preflight_checks

    # Measure resources (IMMEDIATE - no waiting!)
    measure_resources

    # Apply hardening
    apply_hardening

    # Show summary
    show_summary

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry-run complete. Run without --dry-run to apply changes."
        exit 0
    else
        log_success "Namespace '${NAMESPACE}' hardened successfully!"
        exit 0
    fi
}

# Run main function
main "$@"
