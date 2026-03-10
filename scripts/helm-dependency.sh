#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Dependency Management Script
# ==============================================================================
# Description:
#   Comprehensive Helm chart dependency management with hybrid local/remote
#   repository support. Handles discovery, validation, updating, and health
#   checks for both file:// local dependencies and https://, oci:// remote deps.
#
# Usage:
#   helm-dependency.sh <command> [options]
#
# Commands:
#   update           Update all dependencies (hybrid local + remote)
#   discover         Discover and analyze all dependencies
#   validate-local   Validate local chart dependencies
#   build            Build/rebuild dependencies
#   list             List all dependencies
#   verify           Verify all dependencies are satisfied
#   clean            Clean dependency cache
#   health-check     Check repository health
#   help             Show this help message
#
# Options:
#   -c, --chart PATH        Chart directory (required for most commands)
#   -f, --format FORMAT     Output format: table, json, yaml (default: table)
#   -s, --skip-refresh      Skip repository refresh during update
#   -v, --verbose           Enable verbose output
#   -h, --help              Show help message
#
# Examples:
#   # Update all dependencies (local + remote)
#   helm-dependency.sh update --chart ./my-chart
#
#   # Discover dependencies with JSON output
#   helm-dependency.sh discover --chart ./my-chart --format json
#
#   # Validate local dependencies
#   helm-dependency.sh validate-local --chart ./my-chart
#
#   # Clean and rebuild
#   helm-dependency.sh clean --chart ./my-chart
#   helm-dependency.sh build --chart ./my-chart
#
# Author: Forge Team
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SCRIPT METADATA
# ==============================================================================

readonly SCRIPT_NAME="helm-dependency.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Load forge libraries
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

CHART_PATH=""
OUTPUT_FORMAT="table"
SKIP_REFRESH=false
VERBOSE=false

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Display usage information
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} <command> [options]

Commands:
  update           Update all dependencies (hybrid local + remote)
  discover         Discover and analyze all dependencies
  validate-local   Validate local chart dependencies
  build            Build/rebuild dependencies
  list             List all dependencies
  verify           Verify all dependencies are satisfied
  clean            Clean dependency cache
  health-check     Check repository health
  help             Show this help message

Options:
  -c, --chart PATH        Chart directory (required for most commands)
  -f, --format FORMAT     Output format: table, json, yaml (default: table)
  -s, --skip-refresh      Skip repository refresh during update
  -v, --verbose           Enable verbose output
  -h, --help              Show help message

Examples:
  # Update all dependencies
  ${SCRIPT_NAME} update --chart ./my-chart

  # Discover dependencies with JSON output
  ${SCRIPT_NAME} discover --chart ./my-chart --format json

  # Validate local dependencies
  ${SCRIPT_NAME} validate-local --chart ./my-chart

  # Health check repositories
  ${SCRIPT_NAME} health-check --chart ./my-chart

EOF
}

# Parse command line arguments
parse_arguments() {
    local command="${1:-}"
    shift || true
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--chart)
                CHART_PATH="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -s|--skip-refresh)
                SKIP_REFRESH=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
    
    # Validate command
    if [[ -z "${command}" ]]; then
        log_error "No command specified"
        show_usage
        exit 1
    fi
    
    echo "${command}"
}

# Validate chart path
validate_chart_path() {
    if [[ -z "${CHART_PATH}" ]]; then
        log_error "Chart path is required. Use --chart option"
        return 1
    fi
    
    if [[ ! -d "${CHART_PATH}" ]]; then
        log_error "Chart directory not found: ${CHART_PATH}"
        return 1
    fi
    
    if [[ ! -f "${CHART_PATH}/Chart.yaml" ]]; then
        log_error "Chart.yaml not found in: ${CHART_PATH}"
        return 1
    fi
    
    # Convert to absolute path
    CHART_PATH="$(cd "${CHART_PATH}" && pwd)"
    log_debug "Using chart: ${CHART_PATH}"
    
    return 0
}

# ==============================================================================
# COMMAND IMPLEMENTATIONS
# ==============================================================================

# Update command - hybrid local + remote dependencies
cmd_update() {
    log_info "==> Updating dependencies for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    # Use hybrid update function
    if helm_dependency_update_hybrid "${CHART_PATH}" "${SKIP_REFRESH}"; then
        log_success "Dependencies updated successfully"
        
        # Show summary
        echo ""
        log_info "==> Dependency Summary:"
        helm_dependency_list "${CHART_PATH}"
        
        return 0
    else
        log_error "Failed to update dependencies"
        return 1
    fi
}

# Discover command - analyze dependencies
cmd_discover() {
    log_info "==> Discovering dependencies for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    # Get all dependencies
    local deps
    deps=$(helm_dependency_discover_all "${CHART_PATH}" "${OUTPUT_FORMAT}") || {
        log_error "Failed to discover dependencies"
        return 1
    }
    
    # Display dependencies
    echo "${deps}"
    
    # Show repository summary
    if [[ "${OUTPUT_FORMAT}" == "table" ]]; then
        echo ""
        log_info "==> Required Repositories:"
        helm_dependency_discover_repositories "${CHART_PATH}" || true
    fi
    
    return 0
}

# Validate local command - check local dependencies
cmd_validate_local() {
    log_info "==> Validating local dependencies for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    if helm_validate_local_dependency "${CHART_PATH}"; then
        log_success "All local dependencies are valid"
        return 0
    else
        log_error "Local dependency validation failed"
        return 1
    fi
}

# Build command - build/rebuild dependencies
cmd_build() {
    log_info "==> Building dependencies for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    # Check if we should rebuild local dependencies
    local has_local=false
    local deps
    deps=$(helm_dependency_discover_all "${CHART_PATH}" json) || {
        log_error "Failed to discover dependencies"
        return 1
    }
    
    # Check for local dependencies
    if echo "${deps}" | jq -e '.[] | select(.repository | test("^(file://|\\.\\.?/)"))' >/dev/null 2>&1; then
        has_local=true
        log_info "Found local dependencies - rebuilding..."
        
        if ! helm_rebuild_local_dependencies "${CHART_PATH}"; then
            log_error "Failed to rebuild local dependencies"
            return 1
        fi
    fi
    
    # Run helm dependency build
    log_info "Building Helm dependencies..."
    if helm_dependency_build "${CHART_PATH}"; then
        log_success "Dependencies built successfully"
        return 0
    else
        log_error "Failed to build dependencies"
        return 1
    fi
}

# List command - list all dependencies
cmd_list() {
    log_info "==> Listing dependencies for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    # Use helm dependency list
    helm_dependency_list "${CHART_PATH}"
}

# Verify command - verify dependencies are satisfied
cmd_verify() {
    log_info "==> Verifying dependencies for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    if helm_dependency_verify "${CHART_PATH}"; then
        log_success "All dependencies are satisfied"
        return 0
    else
        log_error "Dependency verification failed"
        log_info "Run '${SCRIPT_NAME} update --chart ${CHART_PATH}' to resolve"
        return 1
    fi
}

# Clean command - clean dependency cache
cmd_clean() {
    log_info "==> Cleaning dependency cache for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    if helm_dependency_clean "${CHART_PATH}"; then
        log_success "Dependency cache cleaned"
        return 0
    else
        log_error "Failed to clean dependency cache"
        return 1
    fi
}

# Health check command - check repository health
cmd_health_check() {
    log_info "==> Checking repository health for: ${CHART_PATH}"
    
    validate_chart_path || return 1
    
    # Get repository list
    local repos
    repos=$(helm_dependency_discover_repositories "${CHART_PATH}") || {
        log_warn "No remote repositories found"
        return 0
    }
    
    if [[ -z "${repos}" ]]; then
        log_info "No remote repositories to check"
        return 0
    fi
    
    # Check each repository
    local all_healthy=true
    local repo_count=0
    
    while IFS= read -r repo_url; do
        [[ -z "${repo_url}" ]] && continue
        
        # Skip local repositories
        if [[ "${repo_url}" =~ ^(file://|\.\.?/) ]]; then
            continue
        fi
        
        repo_count=$((repo_count + 1))
        
        # Generate repository name
        local repo_name
        repo_name=$(helm_generate_repo_name_from_url "${repo_url}")
        
        log_info "Checking: ${repo_name} (${repo_url})"
        
        # Check if repository is added
        local repo_list
        repo_list=$(helm_list_repositories json 2>/dev/null) || repo_list="[]"
        
        local is_added
        is_added=$(echo "${repo_list}" | jq -r ".[] | select(.name == \"${repo_name}\") | .name" 2>/dev/null)
        
        if [[ -z "${is_added}" ]]; then
            log_warn "  Repository not added: ${repo_name}"
            all_healthy=false
            continue
        fi
        
        # Check health
        if helm_repository_health_check "${repo_name}" >/dev/null 2>&1; then
            log_success "  ✓ Healthy"
        else
            log_error "  ✗ Unhealthy"
            all_healthy=false
        fi
    done <<< "${repos}"
    
    # Summary
    echo ""
    if [[ "${all_healthy}" == "true" ]]; then
        log_success "All ${repo_count} repositories are healthy"
        return 0
    else
        log_warn "Some repositories have health issues"
        return 1
    fi
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
    # Show banner
    log_info "Forge Helm Dependency Manager v${SCRIPT_VERSION}"
    echo ""
    
    # Validate Helm installation
    if ! validate_helm_installed "3.0.0"; then
        log_error "Helm 3.0.0 or higher is required"
        exit 1
    fi
    
    # Parse command
    local command
    command=$(parse_arguments "$@")
    
    # Execute command
    case "${command}" in
        update)
            cmd_update
            ;;
        discover)
            cmd_discover
            ;;
        validate-local)
            cmd_validate_local
            ;;
        build)
            cmd_build
            ;;
        list)
            cmd_list
            ;;
        verify)
            cmd_verify
            ;;
        clean)
            cmd_clean
            ;;
        health-check)
            cmd_health_check
            ;;
        help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: ${command}"
            show_usage
            exit 1
            ;;
    esac
    
    exit $?
}

# Run main function
main "$@"
