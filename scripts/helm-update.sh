#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Update Script  
# ==============================================================================
# Description:
#   Intelligent Helm release upgrades with diff preview, version comparison,
#   and automatic rollback on failure
#
# Usage:
#   helm-update.sh [options]
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
CHART=""
VERSION=""
VALUES_FILES=()
SET_VALUES=()
SHOW_DIFF=true
ATOMIC=true
WAIT=true
TIMEOUT="300s"
FORCE=false
DRY_RUN=false
AUTO_ROLLBACK=true
REUSE_VALUES=false

# ==============================================================================
# FUNCTIONS
# ==============================================================================

show_usage() {
    cat << EOF
Usage: helm-update.sh [options]

Options:
  -r, --release NAME      Release name (required)
  -n, --namespace NS      Namespace (required)
  -c, --chart PATH/URL    Chart path or URL
  -v, --version VERSION   Chart version
  -f, --values FILE       Values file (multiple allowed)
      --set KEY=VALUE     Set value (multiple allowed)
      --show-diff         Show diff before upgrade (default)
      --no-diff           Skip diff
      --atomic            Atomic operation (default)
      --no-atomic         Disable atomic
      --reuse-values      Reuse existing values
      --force             Force upgrade
      --dry-run           Simulate only
      --timeout DURATION  Timeout (default: 300s)
  -h, --help              Show help

Examples:
  helm-update.sh -r myapp -n default -c ./mychart
  helm-update.sh -r myapp -n default --version 2.0.0 -f new-values.yaml

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release) RELEASE_NAME="$2"; shift 2 ;;
            -n|--namespace) NAMESPACE="$2"; shift 2 ;;
            -c|--chart) CHART="$2"; shift 2 ;;
            -v|--version) VERSION="$2"; shift 2 ;;
            -f|--values) VALUES_FILES+=("$2"); shift 2 ;;
            --set) SET_VALUES+=("$2"); shift 2 ;;
            --show-diff) SHOW_DIFF=true; shift ;;
            --no-diff) SHOW_DIFF=false; shift ;;
            --atomic) ATOMIC=true; shift ;;
            --no-atomic) ATOMIC=false; shift ;;
            --reuse-values) REUSE_VALUES=true; shift ;;
            --force) FORCE=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
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
    
    # Check if release exists
    if ! helm list -n "${NAMESPACE}" -q | grep -q "^${RELEASE_NAME}$"; then
        log_error "Release not found: ${RELEASE_NAME} in namespace: ${NAMESPACE}"
        log_info "Use helm-install.sh to create the release first"
        return 1
    fi
    
    return 0
}

show_diff() {
    log_info "==> Generating upgrade diff..."
    
    # Build args for diff
    local args=()
    
    if [[ -n "${CHART}" ]]; then
        args+=("${CHART}")
    fi
    
    if [[ -n "${VERSION}" ]]; then
        args+=(--version "${VERSION}")
    fi
    
    for values_file in "${VALUES_FILES[@]}"; do
        args+=(--values "${values_file}")
    done
    
    for set_value in "${SET_VALUES[@]}"; do
        args+=(--set "${set_value}")
    done
    
    if [[ "${REUSE_VALUES}" == "true" ]]; then
        args+=(--reuse-values)
    fi
    
    # Check if helm-diff plugin is available
    if validate_helm_plugin "diff"; then
        log_info "Using helm-diff plugin..."
        
        if generate_helm_diff "${RELEASE_NAME}" "${NAMESPACE}" "" "${args[@]}"; then
            echo ""
            read -p "Continue with upgrade? (yes/no): " -r
            if [[ ! "${REPLY}" =~ ^[Yy]es$ ]]; then
                log_info "Upgrade cancelled"
                exit 0
            fi
        else
            log_warn "Diff generation failed, continuing anyway..."
        fi
    else
        log_warn "helm-diff plugin not available, skipping diff"
        log_info "Install with: helm plugin install https://github.com/databus23/helm-diff"
    fi
}

perform_upgrade() {
    log_info "==> Upgrading release: ${RELEASE_NAME}"
    
    # Get current revision for potential rollback
    local current_revision
    current_revision=$(helm list -n "${NAMESPACE}" -o json | \
        jq -r ".[] | select(.name == \"${RELEASE_NAME}\") | .revision" 2>/dev/null || echo "0")
    
    log_info "Current revision: ${current_revision}"
    
    # Build arguments
    local args=()
    
    if [[ -n "${VERSION}" ]]; then
        args+=(--version "${VERSION}")
    fi
    
    for values_file in "${VALUES_FILES[@]}"; do
        args+=(--values "${values_file}")
    done
    
    for set_value in "${SET_VALUES[@]}"; do
        args+=(--set "${set_value}")
    done
    
    if [[ "${ATOMIC}" == "true" ]]; then
        args+=(--atomic)
    fi
    
    if [[ "${WAIT}" == "true" ]]; then
        args+=(--wait --timeout "${TIMEOUT}")
    fi
    
    if [[ "${FORCE}" == "true" ]]; then
        args+=(--force)
    fi
    
    if [[ "${REUSE_VALUES}" == "true" ]]; then
        args+=(--reuse-values)
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        args+=(--dry-run)
    fi
    
    # Perform upgrade
    local upgrade_chart="${CHART:-${RELEASE_NAME}}"
    
    if helm_upgrade_release "${RELEASE_NAME}" "${NAMESPACE}" "${upgrade_chart}" "${args[@]}"; then
        log_success "Release upgraded successfully"
        
        # Get new revision
        local new_revision
        new_revision=$(helm list -n "${NAMESPACE}" -o json | \
            jq -r ".[] | select(.name == \"${RELEASE_NAME}\") | .revision" 2>/dev/null || echo "0")
        
        log_info "New revision: ${new_revision}"
        
        return 0
    else
        log_error "Upgrade failed"
        
        if [[ "${AUTO_ROLLBACK}" == "true" ]] && [[ "${ATOMIC}" != "true" ]]; then
            log_warn "Attempting automatic rollback to revision ${current_revision}..."
            
            if helm_rollback_release "${RELEASE_NAME}" "${NAMESPACE}" "${current_revision}" --wait; then
                log_success "Rolled back successfully"
            else
                log_error "Rollback also failed"
            fi
        fi
        
        return 1
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    log_info "Forge Helm Update v${SCRIPT_VERSION}"
    echo ""
    
    validate_helm_installed "3.0.0" || exit 1
    
    parse_arguments "$@"
    validate_inputs || exit 1
    
    log_info "Configuration:"
    log_info "  Release:   ${RELEASE_NAME}"
    log_info "  Namespace: ${NAMESPACE}"
    [[ -n "${CHART}" ]] && log_info "  Chart:     ${CHART}"
    [[ -n "${VERSION}" ]] && log_info "  Version:   ${VERSION}"
    echo ""
    
    # Show current status
    log_info "==> Current release status:"
    helm_get_release_status "${RELEASE_NAME}" "${NAMESPACE}" table
    echo ""
    
    # Show diff if requested
    if [[ "${SHOW_DIFF}" == "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        show_diff
        echo ""
    fi
    
    # Perform upgrade
    if perform_upgrade; then
        echo ""
        log_success "✓ Upgrade completed successfully"
        exit 0
    else
        echo ""
        log_error "✗ Upgrade failed"
        exit 1
    fi
}

main "$@"
