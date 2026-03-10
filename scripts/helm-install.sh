#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Install/Upgrade Script
# ==============================================================================
# Description:
#   Idempotent Helm chart installation and upgrade with comprehensive features:
#   - Automatic namespace creation
#   - Multi-values file support with precedence
#   - Hybrid dependency auto-discovery
#   - Atomic operations with automatic rollback
#   - Health validation post-deployment
#   - Integration with SSM/Vault for secrets (when available)
#
# Usage:
#   helm-install.sh [options]
#
# Options:
#   -r, --release NAME          Release name (or use Forge pattern)
#   -n, --namespace NS          Kubernetes namespace
#   -c, --chart PATH/URL        Chart path or repository URL
#   -f, --values FILE           Values file (can be specified multiple times)
#       --set KEY=VALUE         Set individual value (can be specified multiple times)
#   -v, --version VERSION       Chart version
#       --create-namespace      Create namespace if it doesn't exist (default)
#       --no-create-namespace   Don't create namespace
#       --atomic                Atomic operation with auto-rollback (default)
#       --no-atomic             Disable atomic operation
#       --wait                  Wait for resources to be ready (default)
#       --no-wait               Don't wait for resources
#       --timeout DURATION      Timeout for operations (default: 300s)
#       --health-check          Perform health check after install (default)
#       --no-health-check       Skip health check
#       --update-deps           Update dependencies before install (default)
#       --no-update-deps        Skip dependency update
#       --dry-run               Simulate installation
#       --force                 Force resource updates
#       --debug                 Enable debug output
#   -h, --help                  Show help message
#
# Forge Pattern Options (instead of --release):
#   --customer NAME             Customer name
#   --project NAME              Project name
#   --environment ENV           Environment (dev, staging, prod)
#   --service NAME              Service name
#
# Examples:
#   # Simple install
#   helm-install.sh --release myapp --namespace default --chart ./mychart
#
#   # Install with Forge pattern
#   helm-install.sh --customer acme --project webapp --environment prod \
#                   --service api --namespace production --chart ./api-chart
#
#   # Install with multiple values files
#   helm-install.sh --release myapp --namespace default --chart ./mychart \
#                   -f values-base.yaml -f values-prod.yaml
#
#   # Install with version and custom values
#   helm-install.sh --release myapp --namespace default \
#                   --chart stable/nginx --version 1.2.3 \
#                   --set replicaCount=3 --set image.tag=v2.0.0
#
# Author: Forge Team
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SCRIPT METADATA
# ==============================================================================

readonly SCRIPT_NAME="helm-install.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

source "${LIB_DIR}/forge-core.sh" || {
    echo "ERROR: Failed to load forge-core.sh" >&2
    exit 1
}

source "${LIB_DIR}/forge-patterns.sh" || {
    log_error "Failed to load forge-patterns.sh"
    exit 1
}

source "${LIB_DIR}/forge-helm-operations.sh" || {
    log_error "Failed to load forge-helm-operations.sh"
    exit 1
}

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

RELEASE_NAME=""
NAMESPACE=""
CHART=""
VERSION=""
VALUES_FILES=()
SET_VALUES=()

# Forge pattern variables
CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""

# Options
CREATE_NAMESPACE=true
ATOMIC=true
WAIT=true
TIMEOUT="300s"
HEALTH_CHECK=true
UPDATE_DEPS=true
DRY_RUN=false
FORCE=false
DEBUG=false

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [options]

Required Options (one of):
  -r, --release NAME          Release name
  OR use Forge pattern:
    --customer NAME           Customer name
    --project NAME            Project name
    --environment ENV         Environment (dev, staging, prod)
    --service NAME            Service name

  -n, --namespace NS          Kubernetes namespace
  -c, --chart PATH/URL        Chart path or repository URL

Optional:
  -f, --values FILE           Values file (multiple allowed)
      --set KEY=VALUE         Set value (multiple allowed)
  -v, --version VERSION       Chart version
      --create-namespace      Create namespace (default: true)
      --no-create-namespace   Don't create namespace
      --atomic                Atomic operation (default: true)
      --no-atomic             Disable atomic
      --wait                  Wait for ready (default: true)
      --no-wait               Don't wait
      --timeout DURATION      Timeout (default: 300s)
      --health-check          Health check (default: true)
      --no-health-check       Skip health check
      --update-deps           Update deps (default: true)
      --no-update-deps        Skip deps update
      --dry-run               Simulate only
      --force                 Force updates
      --debug                 Debug output
  -h, --help                  Show help

Examples:
  ${SCRIPT_NAME} --release myapp --namespace default --chart ./mychart

  ${SCRIPT_NAME} --customer acme --project web --environment prod \\
                 --service api --namespace prod --chart ./api

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release)
                RELEASE_NAME="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -c|--chart)
                CHART="$2"
                shift 2
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -f|--values)
                VALUES_FILES+=("$2")
                shift 2
                ;;
            --set)
                SET_VALUES+=("$2")
                shift 2
                ;;
            --customer)
                CUSTOMER="$2"
                shift 2
                ;;
            --project)
                PROJECT="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --create-namespace)
                CREATE_NAMESPACE=true
                shift
                ;;
            --no-create-namespace)
                CREATE_NAMESPACE=false
                shift
                ;;
            --atomic)
                ATOMIC=true
                shift
                ;;
            --no-atomic)
                ATOMIC=false
                shift
                ;;
            --wait)
                WAIT=true
                shift
                ;;
            --no-wait)
                WAIT=false
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --health-check)
                HEALTH_CHECK=true
                shift
                ;;
            --no-health-check)
                HEALTH_CHECK=false
                shift
                ;;
            --update-deps)
                UPDATE_DEPS=true
                shift
                ;;
            --no-update-deps)
                UPDATE_DEPS=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --debug)
                DEBUG=true
                export LOG_LEVEL="debug"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

validate_inputs() {
    # Build release name from Forge pattern if needed
    if [[ -z "${RELEASE_NAME}" ]]; then
        if [[ -n "${CUSTOMER}" ]] && [[ -n "${PROJECT}" ]] && \
           [[ -n "${ENVIRONMENT}" ]] && [[ -n "${SERVICE}" ]]; then
            RELEASE_NAME=$(get_helm_release_name "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${SERVICE}")
            log_info "Using Forge pattern release name: ${RELEASE_NAME}"
        else
            log_error "Either --release or full Forge pattern (--customer, --project, --environment, --service) is required"
            return 1
        fi
    fi
    
    # Validate release name
    if ! validate_helm_release_name "${RELEASE_NAME}"; then
        return 1
    fi
    
    # Validate required fields
    if [[ -z "${NAMESPACE}" ]]; then
        log_error "Namespace is required (--namespace)"
        return 1
    fi
    
    if [[ -z "${CHART}" ]]; then
        log_error "Chart is required (--chart)"
        return 1
    fi
    
    # Validate values files exist
    for values_file in "${VALUES_FILES[@]}"; do
        if [[ ! -f "${values_file}" ]]; then
            log_error "Values file not found: ${values_file}"
            return 1
        fi
    done
    
    return 0
}

# ==============================================================================
# MAIN FUNCTIONS
# ==============================================================================

perform_install() {
    log_info "==> Installing Helm release: ${RELEASE_NAME}"
    
    # Build Helm arguments
    local helm_args=()
    
    # Add namespace
    helm_args+=(--namespace "${NAMESPACE}")
    
    # Create namespace
    if [[ "${CREATE_NAMESPACE}" == "true" ]]; then
        helm_args+=(--create-namespace)
    fi
    
    # Add version
    if [[ -n "${VERSION}" ]]; then
        helm_args+=(--version "${VERSION}")
    fi
    
    # Add values files
    for values_file in "${VALUES_FILES[@]}"; do
        helm_args+=(--values "${values_file}")
    done
    
    # Add set values
    for set_value in "${SET_VALUES[@]}"; do
        helm_args+=(--set "${set_value}")
    done
    
    # Add flags
    if [[ "${ATOMIC}" == "true" ]]; then
        helm_args+=(--atomic)
    fi
    
    if [[ "${WAIT}" == "true" ]]; then
        helm_args+=(--wait --timeout "${TIMEOUT}")
    fi
    
    if [[ "${FORCE}" == "true" ]]; then
        helm_args+=(--force)
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        helm_args+=(--dry-run)
        log_warn "DRY RUN MODE - No actual changes will be made"
    fi
    
    if [[ "${DEBUG}" == "true" ]]; then
        helm_args+=(--debug)
    fi
    
    # Update dependencies if needed
    if [[ "${UPDATE_DEPS}" == "true" ]] && [[ -d "${CHART}" ]]; then
        log_info "==> Updating chart dependencies..."
        
        if ! helm_dependency_update_hybrid "${CHART}" false; then
            log_warn "Dependency update had issues, continuing anyway..."
        fi
    fi
    
    # Perform install or upgrade
    log_info "==> Performing install/upgrade..."
    if helm_install_or_upgrade "${RELEASE_NAME}" "${NAMESPACE}" "${CHART}" "${helm_args[@]}"; then
        log_success "Release installed/upgraded successfully"
    else
        log_error "Failed to install/upgrade release"
        return 1
    fi
    
    # Skip remaining steps in dry-run mode
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    # Get release status
    log_info "==> Getting release status..."
    helm_get_release_status "${RELEASE_NAME}" "${NAMESPACE}" table
    
    # Perform health check
    if [[ "${HEALTH_CHECK}" == "true" ]]; then
        log_info "==> Performing health check..."
        
        # Extract timeout value (remove 's' suffix)
        local timeout_seconds="${TIMEOUT%s}"
        
        if helm_check_resource_health "${RELEASE_NAME}" "${NAMESPACE}" "${timeout_seconds}" false; then
            log_success "All health checks passed"
        else
            log_warn "Some health checks failed, but release is installed"
            log_info "Check logs with: kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/instance=${RELEASE_NAME}"
        fi
    fi
    
    return 0
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    log_info "Forge Helm Install v${SCRIPT_VERSION}"
    echo ""
    
    # Validate Helm
    if ! validate_helm_installed "3.0.0"; then
        log_error "Helm 3.0.0 or higher is required"
        exit 1
    fi
    
    # Parse arguments
    parse_arguments "$@"
    
    # Validate inputs
    if ! validate_inputs; then
        show_usage
        exit 1
    fi
    
    # Show configuration
    log_info "Configuration:"
    log_info "  Release:    ${RELEASE_NAME}"
    log_info "  Namespace:  ${NAMESPACE}"
    log_info "  Chart:      ${CHART}"
    [[ -n "${VERSION}" ]] && log_info "  Version:    ${VERSION}"
    [[ ${#VALUES_FILES[@]} -gt 0 ]] && log_info "  Values:     ${VALUES_FILES[*]}"
    [[ ${#SET_VALUES[@]} -gt 0 ]] && log_info "  Set:        ${SET_VALUES[*]}"
    echo ""
    
    # Perform installation
    if perform_install; then
        echo ""
        log_success "✓ Installation completed successfully"
        log_info "Release: ${RELEASE_NAME} in namespace: ${NAMESPACE}"
        exit 0
    else
        echo ""
        log_error "✗ Installation failed"
        exit 1
    fi
}

main "$@"
