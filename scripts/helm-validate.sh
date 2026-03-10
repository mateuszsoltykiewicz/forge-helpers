#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Validation Script
# ==============================================================================
# Description:
#   Multi-stage validation for Helm releases:
#   - Pre-installation: Chart lint, values schema, dependencies
#   - Post-installation: Resource status, health checks
#   - Runtime: Continuous monitoring and validation
#
# Usage:
#   helm-validate.sh <stage> [options]
#
# Stages:
#   pre              Pre-installation validation
#   post             Post-installation validation  
#   runtime          Runtime validation
#   all              All stages
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

STAGE=""
RELEASE_NAME=""
NAMESPACE=""
CHART=""
VALUES_FILES=()
TIMEOUT="300"
STRICT=false

# ==============================================================================
# FUNCTIONS
# ==============================================================================

show_usage() {
    cat << EOF
Usage: helm-validate.sh <stage> [options]

Stages:
  pre              Pre-installation validation
  post             Post-installation validation
  runtime          Runtime validation
  all              All applicable stages

Options:
  -r, --release NAME      Release name
  -n, --namespace NS      Namespace
  -c, --chart PATH        Chart path (for pre-validation)
  -f, --values FILE       Values file (multiple allowed)
      --timeout SECONDS   Timeout (default: 300)
      --strict            Strict mode (fail on warnings)
  -h, --help              Show help

Examples:
  # Pre-installation validation
  helm-validate.sh pre --chart ./mychart -f values.yaml

  # Post-installation validation
  helm-validate.sh post -r myapp -n default

  # Runtime monitoring
  helm-validate.sh runtime -r myapp -n default --timeout 60

EOF
}

parse_arguments() {
    STAGE="${1:-}"
    shift || true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release) RELEASE_NAME="$2"; shift 2 ;;
            -n|--namespace) NAMESPACE="$2"; shift 2 ;;
            -c|--chart) CHART="$2"; shift 2 ;;
            -f|--values) VALUES_FILES+=("$2"); shift 2 ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
            --strict) STRICT=true; shift ;;
            -h|--help) show_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done
}

# ==============================================================================
# VALIDATION STAGES
# ==============================================================================

validate_pre() {
    log_info "==> Pre-Installation Validation"
    echo ""
    
    local has_errors=false
    
    # Validate chart path
    if [[ -z "${CHART}" ]]; then
        log_error "Chart path required for pre-validation (--chart)"
        return 1
    fi
    
    if [[ ! -d "${CHART}" ]]; then
        log_error "Chart directory not found: ${CHART}"
        return 1
    fi
    
    # 1. Lint chart
    log_info "[1/4] Linting chart..."
    if helm_lint_chart "${CHART}"; then
        log_success "✓ Chart lint passed"
    else
        log_error "✗ Chart lint failed"
        has_errors=true
    fi
    echo ""
    
    # 2. Validate values schema
    log_info "[2/4] Validating values schema..."
    local validation_ok=true
    
    for values_file in "${VALUES_FILES[@]}"; do
        log_info "Checking: ${values_file}"
        if helm_validate_values_schema "${CHART}" "${values_file}"; then
            log_success "✓ Valid"
        else
            log_error "✗ Invalid"
            has_errors=true
            validation_ok=false
        fi
    done
    
    if [[ "${validation_ok}" == "true" ]] || [[ ${#VALUES_FILES[@]} -eq 0 ]]; then
        log_success "✓ Values validation passed"
    fi
    echo ""
    
    # 3. Check dependencies
    log_info "[3/4] Checking dependencies..."
    if helm_dependency_verify "${CHART}"; then
        log_success "✓ Dependencies satisfied"
    else
        log_warn "⚠ Dependencies not satisfied"
        log_info "Run: helm-dependency.sh update --chart ${CHART}"
        
        if [[ "${STRICT}" == "true" ]]; then
            has_errors=true
        fi
    fi
    echo ""
    
    # 4. Template rendering test
    log_info "[4/4] Testing template rendering..."
    if helm_template_chart "test-release" "${CHART}" \
        $(printf -- "-f %s " "${VALUES_FILES[@]}") \
        >/dev/null 2>&1; then
        log_success "✓ Templates render successfully"
    else
        log_error "✗ Template rendering failed"
        has_errors=true
    fi
    echo ""
    
    if [[ "${has_errors}" == "true" ]]; then
        log_error "Pre-validation failed"
        return 1
    else
        log_success "✓ All pre-validation checks passed"
        return 0
    fi
}

validate_post() {
    log_info "==> Post-Installation Validation"
    echo ""
    
    # Validate inputs
    if [[ -z "${RELEASE_NAME}" ]] || [[ -z "${NAMESPACE}" ]]; then
        log_error "Release name and namespace required (--release, --namespace)"
        return 1
    fi
    
    local has_errors=false
    
    # 1. Release status
    log_info "[1/5] Checking release status..."
    local status
    status=$(helm list -n "${NAMESPACE}" -o json | \
        jq -r ".[] | select(.name == \"${RELEASE_NAME}\") | .status" 2>/dev/null || echo "not-found")
    
    if [[ "${status}" == "deployed" ]]; then
        log_success "✓ Release is deployed"
    else
        log_error "✗ Release status: ${status}"
        has_errors=true
    fi
    echo ""
    
    # 2. Pod status
    log_info "[2/5] Checking pod status..."
    if helm_check_pod_status "${RELEASE_NAME}" "${NAMESPACE}" "${TIMEOUT}"; then
        log_success "✓ All pods ready"
    else
        log_error "✗ Some pods not ready"
        has_errors=true
    fi
    echo ""
    
    # 3. Service endpoints
    log_info "[3/5] Checking service endpoints..."
    if helm_check_service_endpoints "${RELEASE_NAME}" "${NAMESPACE}"; then
        log_success "✓ Services have endpoints"
    else
        log_warn "⚠ Some services have no endpoints"
        if [[ "${STRICT}" == "true" ]]; then
            has_errors=true
        fi
    fi
    echo ""
    
    # 4. Deployment rollout
    log_info "[4/5] Checking deployments..."
    if helm_check_deployment_rollout "${RELEASE_NAME}" "${NAMESPACE}" "${TIMEOUT}"; then
        log_success "✓ Deployments rolled out"
    else
        log_error "✗ Deployment rollout issues"
        has_errors=true
    fi
    echo ""
    
    # 5. Overall health
    log_info "[5/5] Performing comprehensive health check..."
    if helm_check_resource_health "${RELEASE_NAME}" "${NAMESPACE}" "${TIMEOUT}" false; then
        log_success "✓ All health checks passed"
    else
        log_error "✗ Health check failed"
        has_errors=true
    fi
    echo ""
    
    if [[ "${has_errors}" == "true" ]]; then
        log_error "Post-validation failed"
        return 1
    else
        log_success "✓ All post-validation checks passed"
        return 0
    fi
}

validate_runtime() {
    log_info "==> Runtime Validation"
    echo ""
    
    if [[ -z "${RELEASE_NAME}" ]] || [[ -z "${NAMESPACE}" ]]; then
        log_error "Release name and namespace required"
        return 1
    fi
    
    log_info "Monitoring release: ${RELEASE_NAME} for ${TIMEOUT}s"
    echo ""
    
    local start_time=$(date +%s)
    local check_interval=10
    local checks=0
    local failures=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ ${elapsed} -ge ${TIMEOUT} ]]; then
            break
        fi
        
        checks=$((checks + 1))
        log_info "[Check ${checks}] Elapsed: ${elapsed}s / ${TIMEOUT}s"
        
        # Check pod status
        if ! helm_check_pod_status "${RELEASE_NAME}" "${NAMESPACE}" 30 >/dev/null 2>&1; then
            failures=$((failures + 1))
            log_warn "⚠ Pod check failed (${failures} failures)"
        else
            log_success "✓ Pods healthy"
        fi
        
        # Check service endpoints
        if ! helm_check_service_endpoints "${RELEASE_NAME}" "${NAMESPACE}" >/dev/null 2>&1; then
            log_warn "⚠ Service endpoints check failed"
        else
            log_debug "✓ Services healthy"
        fi
        
        # Sleep between checks
        if [[ ${elapsed} -lt ${TIMEOUT} ]]; then
            sleep ${check_interval}
        fi
        
        echo ""
    done
    
    log_info "Runtime validation completed"
    log_info "Total checks: ${checks}"
    log_info "Failures: ${failures}"
    
    if [[ ${failures} -gt 0 ]]; then
        log_warn "Some runtime checks failed"
        return 1
    else
        log_success "✓ All runtime checks passed"
        return 0
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    log_info "Forge Helm Validate v${SCRIPT_VERSION}"
    echo ""
    
    validate_helm_installed "3.0.0" || exit 1
    
    parse_arguments "$@"
    
    if [[ -z "${STAGE}" ]]; then
        log_error "Stage required (pre, post, runtime, all)"
        show_usage
        exit 1
    fi
    
    local result=0
    
    case "${STAGE}" in
        pre)
            validate_pre || result=$?
            ;;
        post)
            validate_post || result=$?
            ;;
        runtime)
            validate_runtime || result=$?
            ;;
        all)
            if [[ -n "${CHART}" ]]; then
                validate_pre || result=$?
                echo ""
            fi
            
            if [[ -n "${RELEASE_NAME}" ]] && [[ -n "${NAMESPACE}" ]]; then
                validate_post || result=$?
            fi
            ;;
        *)
            log_error "Unknown stage: ${STAGE}"
            show_usage
            exit 1
            ;;
    esac
    
    exit ${result}
}

main "$@"
