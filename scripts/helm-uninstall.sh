#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Uninstall Script
# ==============================================================================
# Description:
#   Safe Helm release uninstallation with backup and cleanup verification
#
# Usage:
#   helm-uninstall.sh [options]
#
# Author: Forge Team
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/forge-core.sh" || exit 1
source "${LIB_DIR}/forge-patterns.sh" || exit 1
source "${LIB_DIR}/forge-helm-operations.sh" || exit 1

# ==============================================================================
# VARIABLES
# ==============================================================================

RELEASE_NAME=""
NAMESPACE=""
BACKUP=true
FORCE=false
KEEP_HISTORY=false
WAIT=true
TIMEOUT="300s"
VERIFY_CLEANUP=true

# ==============================================================================
# FUNCTIONS
# ==============================================================================

show_usage() {
    cat << EOF
Usage: helm-uninstall.sh [options]

Options:
  -r, --release NAME      Release name (required)
  -n, --namespace NS      Namespace (required)
      --backup            Create backup before uninstall (default)
      --no-backup         Skip backup
      --force             Force deletion
      --keep-history      Keep release history
      --no-wait           Don't wait for deletion
      --timeout DURATION  Timeout (default: 300s)
      --no-verify         Skip cleanup verification
  -h, --help              Show help

Examples:
  helm-uninstall.sh --release myapp --namespace default
  helm-uninstall.sh -r myapp -n default --force --no-backup

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release) RELEASE_NAME="$2"; shift 2 ;;
            -n|--namespace) NAMESPACE="$2"; shift 2 ;;
            --backup) BACKUP=true; shift ;;
            --no-backup) BACKUP=false; shift ;;
            --force) FORCE=true; shift ;;
            --keep-history) KEEP_HISTORY=true; shift ;;
            --no-wait) WAIT=false; shift ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
            --no-verify) VERIFY_CLEANUP=false; shift ;;
            -h|--help) show_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done
}

validate_inputs() {
    if [[ -z "${RELEASE_NAME}" ]] || [[ -z "${NAMESPACE}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    return 0
}

create_backup() {
    local backup_dir
    backup_dir=$(get_helm_backup_path "${RELEASE_NAME}" "$(date +%Y%m%d_%H%M%S)")
    
    log_info "Creating backup: ${backup_dir}"
    mkdir -p "${backup_dir}"
    
    # Save release manifest
    log_info "Backing up release manifest..."
    if kubectl get all,ingress,configmap,secret,pvc -n "${NAMESPACE}" \
        -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
        -o yaml > "${backup_dir}/manifest.yaml" 2>/dev/null; then
        log_success "Manifest backed up"
    else
        log_warn "Failed to backup manifest"
    fi
    
    # Save release values
    log_info "Backing up release values..."
    if helm_get_release_values "${RELEASE_NAME}" "${NAMESPACE}" yaml true \
        > "${backup_dir}/values.yaml" 2>/dev/null; then
        log_success "Values backed up"
    else
        log_warn "Failed to backup values"
    fi
    
    # Save release info
    log_info "Backing up release info..."
    if helm_get_release_status "${RELEASE_NAME}" "${NAMESPACE}" yaml \
        > "${backup_dir}/release-info.yaml" 2>/dev/null; then
        log_success "Release info backed up"
    else
        log_warn "Failed to backup release info"
    fi
    
    log_success "Backup completed: ${backup_dir}"
}

perform_uninstall() {
    log_info "==> Uninstalling release: ${RELEASE_NAME}"
    
    # Build arguments
    local args=()
    
    if [[ "${KEEP_HISTORY}" == "true" ]]; then
        args+=(--keep-history)
    fi
    
    if [[ "${WAIT}" == "true" ]]; then
        args+=(--wait --timeout "${TIMEOUT}")
    fi
    
    # Uninstall
    if helm_uninstall_release "${RELEASE_NAME}" "${NAMESPACE}" "${args[@]}"; then
        log_success "Release uninstalled successfully"
    else
        log_error "Failed to uninstall release"
        return 1
    fi
    
    # Verify cleanup
    if [[ "${VERIFY_CLEANUP}" == "true" ]]; then
        log_info "==> Verifying cleanup..."
        sleep 2
        
        local remaining
        remaining=$(kubectl get all -n "${NAMESPACE}" \
            -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
            --no-headers 2>/dev/null | wc -l)
        
        if [[ ${remaining} -eq 0 ]]; then
            log_success "All resources cleaned up"
        else
            log_warn "Some resources remain (${remaining}), may need manual cleanup"
            
            if [[ "${FORCE}" == "true" ]]; then
                log_info "Force deleting remaining resources..."
                kubectl delete all -n "${NAMESPACE}" \
                    -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
                    --force --grace-period=0 2>/dev/null || true
            fi
        fi
    fi
    
    return 0
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    log_info "Forge Helm Uninstall v${SCRIPT_VERSION}"
    echo ""
    
    validate_helm_installed "3.0.0" || exit 1
    
    parse_arguments "$@"
    validate_inputs || exit 1
    
    log_info "Configuration:"
    log_info "  Release:   ${RELEASE_NAME}"
    log_info "  Namespace: ${NAMESPACE}"
    echo ""
    
    # Confirm
    if [[ "${FORCE}" != "true" ]]; then
        log_warn "This will delete release: ${RELEASE_NAME} from namespace: ${NAMESPACE}"
        read -p "Continue? (yes/no): " -r
        if [[ ! "${REPLY}" =~ ^[Yy]es$ ]]; then
            log_info "Uninstall cancelled"
            exit 0
        fi
    fi
    
    # Backup
    if [[ "${BACKUP}" == "true" ]]; then
        create_backup
        echo ""
    fi
    
    # Uninstall
    if perform_uninstall; then
        echo ""
        log_success "✓ Uninstall completed successfully"
        exit 0
    else
        echo ""
        log_error "✗ Uninstall failed"
        exit 1
    fi
}

main "$@"
