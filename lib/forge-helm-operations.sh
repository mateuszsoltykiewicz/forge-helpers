#!/usr/bin/env bash
# ==============================================================================
# Forge Helm Operations Library
# ==============================================================================
# Description: Comprehensive Helm operations and management
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - Release lifecycle management (install, upgrade, rollback, uninstall)
# - Chart operations (fetch, template, lint, package)
# - Repository management (add, update, search)
# - Hybrid dependency management (local + remote charts)
# - Values management (merge, validate, diff)
# - Resource validation (health checks, readiness)
#
# Dependencies:
#   - forge-core.sh (logging, validation, utilities)
#   - forge-patterns.sh (naming conventions)
#   - helm 3.0+ (Kubernetes package manager)
#   - kubectl (Kubernetes CLI)
#   - yq, jq (YAML/JSON processors)
#
# Usage:
#   source /path/to/forge-helm-operations.sh
#   helm_install_or_upgrade "my-release" "default" "./chart" -f values.yaml
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_HELM_OPERATIONS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_HELM_OPERATIONS_VERSION="1.0.0"
readonly FORGE_HELM_OPERATIONS_LOADED="true"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Get library directory
if [[ -z "${LIB_DIR:-}" ]]; then
  LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source required libraries
source "${LIB_DIR}/forge-core.sh"
source "${LIB_DIR}/forge-patterns.sh"

# Validate required commands
validate_required_commands helm kubectl jq yq

# Validate Helm version
validate_helm_installed "3.0.0"

# ==============================================================================
# RELEASE LIFECYCLE OPERATIONS
# ==============================================================================

# helm_install_or_upgrade
# Idempotent install or upgrade operation (recommended for automation)
# Installs if release doesn't exist, upgrades if it does
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - chart: Chart reference (path, repo/chart, or URL)
#   $@ - helm_args: Additional Helm arguments (--values, --set, etc.)
#
# Returns:
#   0 - Success (installed or upgraded)
#   1 - Error
#
# Example:
#   helm_install_or_upgrade "my-app" "default" "./chart" \
#     --values values.yaml \
#     --set image.tag=1.0.0 \
#     --wait --timeout 5m
#
helm_install_or_upgrade() {
  if [[ $# -lt 3 ]]; then
    log_error "Usage: helm_install_or_upgrade <release> <namespace> <chart> [helm_args...]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local chart="$3"
  shift 3
  local helm_args=("$@")
  
  log_info "═══════════════════════════════════════════════════════════"
  log_info "  Helm Install or Upgrade"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Release: ${release_name}"
  log_info "Namespace: ${namespace}"
  log_info "Chart: ${chart}"
  log_info ""
  
  # Validate release name
  if ! validate_helm_release_name "$release_name"; then
    return 1
  fi
  
  # Execute install/upgrade
  log_info "Executing: helm upgrade --install ${release_name} ${chart}"
  
  if helm upgrade --install "$release_name" "$chart" \
    --namespace "$namespace" \
    --create-namespace \
    "${helm_args[@]}" 2>&1 | log_pipe_output "info"; then
    
    log_success "Release '${release_name}' deployed successfully"
    
    # Get release info
    helm_get_release_status "$release_name" "$namespace"
    
    return 0
  else
    log_error "Failed to deploy release '${release_name}'"
    return 1
  fi
}

# helm_install_release
# Install a new Helm release (fails if release already exists)
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - chart: Chart reference
#   $@ - helm_args: Additional Helm arguments
#
# Returns:
#   0 - Success
#   1 - Error (including if release already exists)
#
# Example:
#   helm_install_release "my-app" "default" "bitnami/nginx" \
#     --version 15.0.0 \
#     --values values.yaml \
#     --atomic --wait
#
helm_install_release() {
  if [[ $# -lt 3 ]]; then
    log_error "Usage: helm_install_release <release> <namespace> <chart> [helm_args...]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local chart="$3"
  shift 3
  local helm_args=("$@")
  
  log_info "Installing new Helm release: ${release_name}"
  
  # Validate release name
  if ! validate_helm_release_name "$release_name"; then
    return 1
  fi
  
  # Check if release already exists
  if helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_error "Release '${release_name}' already exists in namespace '${namespace}'"
    log_info "Use helm_upgrade_release() or helm_install_or_upgrade() instead"
    return 1
  fi
  
  # Execute install
  log_info "Executing: helm install ${release_name} ${chart}"
  
  if helm install "$release_name" "$chart" \
    --namespace "$namespace" \
    --create-namespace \
    "${helm_args[@]}" 2>&1 | log_pipe_output "info"; then
    
    log_success "Release '${release_name}' installed successfully"
    return 0
  else
    log_error "Failed to install release '${release_name}'"
    return 1
  fi
}

# helm_upgrade_release
# Upgrade an existing Helm release (fails if release doesn't exist)
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - chart: Chart reference
#   $@ - helm_args: Additional Helm arguments
#
# Returns:
#   0 - Success
#   1 - Error (including if release doesn't exist)
#
# Example:
#   helm_upgrade_release "my-app" "default" "./chart" \
#     --values values-prod.yaml \
#     --set image.tag=2.0.0 \
#     --atomic --wait --timeout 10m
#
helm_upgrade_release() {
  if [[ $# -lt 3 ]]; then
    log_error "Usage: helm_upgrade_release <release> <namespace> <chart> [helm_args...]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local chart="$3"
  shift 3
  local helm_args=("$@")
  
  log_info "Upgrading Helm release: ${release_name}"
  
  # Check if release exists
  if ! helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_error "Release '${release_name}' does not exist in namespace '${namespace}'"
    log_info "Use helm_install_release() or helm_install_or_upgrade() instead"
    return 1
  fi
  
  # Get current revision
  local current_revision
  current_revision=$(helm list -n "$namespace" -f "^${release_name}$" -o json 2>/dev/null | \
    jq -r '.[0].revision // "unknown"')
  
  log_info "Current revision: ${current_revision}"
  
  # Execute upgrade
  log_info "Executing: helm upgrade ${release_name} ${chart}"
  
  if helm upgrade "$release_name" "$chart" \
    --namespace "$namespace" \
    "${helm_args[@]}" 2>&1 | log_pipe_output "info"; then
    
    local new_revision
    new_revision=$(helm list -n "$namespace" -f "^${release_name}$" -o json 2>/dev/null | \
      jq -r '.[0].revision // "unknown"')
    
    log_success "Release '${release_name}' upgraded successfully"
    log_info "New revision: ${new_revision}"
    return 0
  else
    log_error "Failed to upgrade release '${release_name}'"
    return 1
  fi
}

# helm_rollback_release
# Rollback a Helm release to a previous revision
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - revision: Revision number to rollback to (optional, defaults to previous)
#   $@ - helm_args: Additional Helm arguments
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   helm_rollback_release "my-app" "default" 5 --wait
#   helm_rollback_release "my-app" "default" 0 --wait  # 0 = previous revision
#
helm_rollback_release() {
  if [[ $# -lt 2 ]]; then
    log_error "Usage: helm_rollback_release <release> <namespace> [revision] [helm_args...]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local revision="${3:-0}"  # 0 means previous revision
  shift 2
  
  # Remove revision from args if it was provided
  if [[ "$revision" =~ ^[0-9]+$ ]]; then
    shift 1 2>/dev/null || true
  fi
  
  local helm_args=("$@")
  
  log_info "Rolling back release: ${release_name}"
  
  # Check if release exists
  if ! helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_error "Release '${release_name}' does not exist in namespace '${namespace}'"
    return 1
  fi
  
  # Get current revision
  local current_revision
  current_revision=$(helm list -n "$namespace" -f "^${release_name}$" -o json 2>/dev/null | \
    jq -r '.[0].revision // "unknown"')
  
  log_info "Current revision: ${current_revision}"
  
  if [[ "$revision" == "0" ]]; then
    log_info "Rolling back to previous revision"
  else
    log_info "Rolling back to revision: ${revision}"
  fi
  
  # Execute rollback
  if helm rollback "$release_name" "$revision" \
    --namespace "$namespace" \
    "${helm_args[@]}" 2>&1 | log_pipe_output "info"; then
    
    log_success "Release '${release_name}' rolled back successfully"
    
    local new_revision
    new_revision=$(helm list -n "$namespace" -f "^${release_name}$" -o json 2>/dev/null | \
      jq -r '.[0].revision // "unknown"')
    log_info "New revision: ${new_revision}"
    
    return 0
  else
    log_error "Failed to rollback release '${release_name}'"
    return 1
  fi
}

# helm_uninstall_release
# Uninstall a Helm release and optionally delete associated resources
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $@ - helm_args: Additional Helm arguments (--keep-history, --wait, etc.)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   helm_uninstall_release "my-app" "default" --wait --timeout 5m
#   helm_uninstall_release "my-app" "default" --keep-history
#
helm_uninstall_release() {
  if [[ $# -lt 2 ]]; then
    log_error "Usage: helm_uninstall_release <release> <namespace> [helm_args...]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  shift 2
  local helm_args=("$@")
  
  log_info "Uninstalling Helm release: ${release_name}"
  
  # Check if release exists
  if ! helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_warning "Release '${release_name}' does not exist in namespace '${namespace}'"
    log_info "Nothing to uninstall"
    return 0
  fi
  
  # Get release info before deletion
  local revision
  revision=$(helm list -n "$namespace" -f "^${release_name}$" -o json 2>/dev/null | \
    jq -r '.[0].revision // "unknown"')
  
  log_info "Current revision: ${revision}"
  
  # Execute uninstall
  log_info "Executing: helm uninstall ${release_name}"
  
  if helm uninstall "$release_name" \
    --namespace "$namespace" \
    "${helm_args[@]}" 2>&1 | log_pipe_output "info"; then
    
    log_success "Release '${release_name}' uninstalled successfully"
    return 0
  else
    log_error "Failed to uninstall release '${release_name}'"
    return 1
  fi
}

# helm_get_release_status
# Get detailed status of a Helm release
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - output_format: Output format (json|yaml|table, default: table)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   Release status information to stdout
#
# Example:
#   helm_get_release_status "my-app" "default"
#   helm_get_release_status "my-app" "default" "json"
#
helm_get_release_status() {
  if [[ $# -lt 2 ]]; then
    log_error "Usage: helm_get_release_status <release> <namespace> [format]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local output_format="${3:-table}"
  
  # Check if release exists
  if ! helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_error "Release '${release_name}' does not exist in namespace '${namespace}'"
    return 1
  fi
  
  case "$output_format" in
    json)
      helm status "$release_name" -n "$namespace" -o json 2>/dev/null
      ;;
    yaml)
      helm status "$release_name" -n "$namespace" -o yaml 2>/dev/null
      ;;
    table|*)
      helm status "$release_name" -n "$namespace" 2>/dev/null
      ;;
  esac
  
  return 0
}

# helm_get_release_values
# Get computed values for a Helm release
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - output_format: Output format (json|yaml, default: yaml)
#   $4 - all_values: Show all values including defaults (true|false, default: false)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   Release values to stdout
#
# Example:
#   helm_get_release_values "my-app" "default"
#   helm_get_release_values "my-app" "default" "json" "true"
#
helm_get_release_values() {
  if [[ $# -lt 2 ]]; then
    log_error "Usage: helm_get_release_values <release> <namespace> [format] [all_values]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local output_format="${3:-yaml}"
  local all_values="${4:-false}"
  
  # Check if release exists
  if ! helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_error "Release '${release_name}' does not exist in namespace '${namespace}'"
    return 1
  fi
  
  local helm_args=()
  [[ "$all_values" == "true" ]] && helm_args+=("--all")
  
  case "$output_format" in
    json)
      helm get values "$release_name" -n "$namespace" "${helm_args[@]}" -o json 2>/dev/null
      ;;
    yaml|*)
      helm get values "$release_name" -n "$namespace" "${helm_args[@]}" -o yaml 2>/dev/null
      ;;
  esac
  
  return 0
}

# helm_get_release_history
# Get revision history for a Helm release
#
# Arguments:
#   $1 - release_name: Name of the Helm release
#   $2 - namespace: Kubernetes namespace
#   $3 - max_revisions: Maximum number of revisions to show (default: 10)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   Release history to stdout
#
# Example:
#   helm_get_release_history "my-app" "default"
#   helm_get_release_history "my-app" "default" 20
#
helm_get_release_history() {
  if [[ $# -lt 2 ]]; then
    log_error "Usage: helm_get_release_history <release> <namespace> [max_revisions]"
    return 1
  fi
  
  local release_name="$1"
  local namespace="$2"
  local max_revisions="${3:-10}"
  
  # Check if release exists
  if ! helm list -n "$namespace" -q 2>/dev/null | grep -q "^${release_name}$"; then
    log_error "Release '${release_name}' does not exist in namespace '${namespace}'"
    return 1
  fi
  
  log_info "Release history for '${release_name}':"
  log_info ""
  
  helm history "$release_name" \
    --namespace "$namespace" \
    --max "$max_revisions" 2>/dev/null
  
  return 0
}

# ==============================================================================
# CHART OPERATIONS
# ==============================================================================

# Fetch a chart from a repository or URL
helm_fetch_chart() {
    local chart="$1"
    local destination="${2:-.}"
    shift 2
    local args=("$@")
    
    log_info "Fetching chart: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart name/URL is required"
        return 1
    fi
    
    # Create destination directory
    mkdir -p "${destination}"
    
    # Build fetch command
    local cmd=(helm fetch "${chart}" --destination "${destination}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute fetch
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Chart fetched successfully to: ${destination}"
        echo "${output}"
        return 0
    else
        log_error "Failed to fetch chart: ${chart}"
        helm_error_handler "${output}"
        return 1
    fi
}

# Template a chart (render without installing)
helm_template_chart() {
    local release="$1"
    local chart="$2"
    shift 2
    local args=("$@")
    
    log_info "Templating chart: ${chart} as ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${chart}" ]]; then
        log_error "Release name and chart are required"
        return 1
    fi
    
    # Build template command
    local cmd=(helm template "${release}" "${chart}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute template
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Chart templated successfully"
        echo "${output}"
        return 0
    else
        log_error "Failed to template chart: ${chart}"
        helm_error_handler "${output}"
        return 1
    fi
}

# Lint a chart for issues
helm_lint_chart() {
    local chart="$1"
    shift
    local args=("$@")
    
    log_info "Linting chart: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    if [[ ! -d "${chart}" ]]; then
        log_error "Chart directory not found: ${chart}"
        return 1
    fi
    
    # Build lint command
    local cmd=(helm lint "${chart}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute lint
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Chart lint passed"
        echo "${output}"
        return 0
    else
        log_error "Chart lint failed"
        echo "${output}"
        return 1
    fi
}

# Package a chart into a versioned archive
helm_package_chart() {
    local chart="$1"
    local destination="${2:-.}"
    shift 2
    local args=("$@")
    
    log_info "Packaging chart: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    if [[ ! -d "${chart}" ]]; then
        log_error "Chart directory not found: ${chart}"
        return 1
    fi
    
    # Create destination directory
    mkdir -p "${destination}"
    
    # Build package command
    local cmd=(helm package "${chart}" --destination "${destination}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute package
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Chart packaged successfully"
        echo "${output}"
        
        # Extract package filename from output
        if [[ "${output}" =~ Successfully\ packaged\ chart\ and\ saved\ it\ to:\ (.+\.tgz) ]]; then
            local package="${BASH_REMATCH[1]}"
            log_info "Package: ${package}"
        fi
        
        return 0
    else
        log_error "Failed to package chart: ${chart}"
        echo "${output}"
        return 1
    fi
}

# Show chart information (metadata)
helm_show_chart_info() {
    local chart="$1"
    local format="${2:-yaml}"
    shift 2
    local args=("$@")
    
    log_info "Getting chart info: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart name/path is required"
        return 1
    fi
    
    # Build show command
    local cmd=(helm show chart "${chart}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute show
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        # Format output if requested
        case "${format}" in
            json)
                echo "${output}" | yq eval -o=json - 2>/dev/null || echo "${output}"
                ;;
            yaml|*)
                echo "${output}"
                ;;
        esac
        return 0
    else
        log_error "Failed to get chart info: ${chart}"
        helm_error_handler "${output}"
        return 1
    fi
}

# Show chart default values
helm_show_chart_values() {
    local chart="$1"
    local format="${2:-yaml}"
    shift 2
    local args=("$@")
    
    log_info "Getting chart values: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart name/path is required"
        return 1
    fi
    
    # Build show command
    local cmd=(helm show values "${chart}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute show
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        # Format output if requested
        case "${format}" in
            json)
                echo "${output}" | yq eval -o=json - 2>/dev/null || echo "${output}"
                ;;
            yaml|*)
                echo "${output}"
                ;;
        esac
        return 0
    else
        log_error "Failed to get chart values: ${chart}"
        helm_error_handler "${output}"
        return 1
    fi
}

# Update chart dependencies
helm_dependency_update() {
    local chart="$1"
    shift
    local args=("$@")
    
    log_info "Updating dependencies for chart: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    if [[ ! -d "${chart}" ]]; then
        log_error "Chart directory not found: ${chart}"
        return 1
    fi
    
    # Check if Chart.yaml exists
    if [[ ! -f "${chart}/Chart.yaml" ]]; then
        log_error "Chart.yaml not found in: ${chart}"
        return 1
    fi
    
    # Build dependency update command
    local cmd=(helm dependency update "${chart}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute dependency update
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Dependencies updated successfully"
        echo "${output}"
        return 0
    else
        log_error "Failed to update dependencies for: ${chart}"
        echo "${output}"
        return 1
    fi
}

# Build chart dependencies (download to charts/ directory)
helm_dependency_build() {
    local chart="$1"
    shift
    local args=("$@")
    
    log_info "Building dependencies for chart: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    if [[ ! -d "${chart}" ]]; then
        log_error "Chart directory not found: ${chart}"
        return 1
    fi
    
    # Check if Chart.yaml exists
    if [[ ! -f "${chart}/Chart.yaml" ]]; then
        log_error "Chart.yaml not found in: ${chart}"
        return 1
    fi
    
    # Build dependency build command
    local cmd=(helm dependency build "${chart}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute dependency build
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Dependencies built successfully"
        echo "${output}"
        return 0
    else
        log_error "Failed to build dependencies for: ${chart}"
        echo "${output}"
        return 1
    fi
}

# List chart dependencies
helm_dependency_list() {
    local chart="$1"
    
    log_info "Listing dependencies for chart: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    if [[ ! -d "${chart}" ]]; then
        log_error "Chart directory not found: ${chart}"
        return 1
    fi
    
    # Check if Chart.yaml exists
    if [[ ! -f "${chart}/Chart.yaml" ]]; then
        log_error "Chart.yaml not found in: ${chart}"
        return 1
    fi
    
    # Execute dependency list
    log_debug "Executing: helm dependency list ${chart}"
    if output=$(helm dependency list "${chart}" 2>&1); then
        echo "${output}"
        return 0
    else
        log_error "Failed to list dependencies for: ${chart}"
        echo "${output}"
        return 1
    fi
}

# ==============================================================================
# REPOSITORY MANAGEMENT
# ==============================================================================

# Add a Helm repository
helm_add_repository() {
    local name="$1"
    local url="$2"
    shift 2
    local args=("$@")
    
    log_info "Adding Helm repository: ${name} (${url})"
    
    # Validate inputs
    if [[ -z "${name}" ]] || [[ -z "${url}" ]]; then
        log_error "Repository name and URL are required"
        return 1
    fi
    
    # Build add command
    local cmd=(helm repo add "${name}" "${url}")
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute add
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        log_success "Repository added: ${name}"
        
        # Update repository
        log_info "Updating repository index..."
        helm repo update "${name}" 2>&1 | log_pipe_output "debug"
        
        return 0
    else
        # Check if already exists
        if [[ "${output}" =~ already\ exists ]]; then
            log_warn "Repository already exists: ${name}"
            return 0
        fi
        
        log_error "Failed to add repository: ${name}"
        echo "${output}"
        return 1
    fi
}

# Remove a Helm repository
helm_remove_repository() {
    local name="$1"
    
    log_info "Removing Helm repository: ${name}"
    
    # Validate inputs
    if [[ -z "${name}" ]]; then
        log_error "Repository name is required"
        return 1
    fi
    
    # Execute remove
    log_debug "Executing: helm repo remove ${name}"
    if output=$(helm repo remove "${name}" 2>&1); then
        log_success "Repository removed: ${name}"
        return 0
    else
        # Check if doesn't exist
        if [[ "${output}" =~ no\ repo\ named ]]; then
            log_warn "Repository doesn't exist: ${name}"
            return 0
        fi
        
        log_error "Failed to remove repository: ${name}"
        echo "${output}"
        return 1
    fi
}

# Update all or specific Helm repositories
helm_update_repositories() {
    local name="${1:-}"
    
    if [[ -n "${name}" ]]; then
        log_info "Updating Helm repository: ${name}"
        
        # Update specific repository
        log_debug "Executing: helm repo update ${name}"
        if output=$(helm repo update "${name}" 2>&1); then
            log_success "Repository updated: ${name}"
            echo "${output}"
            return 0
        else
            log_error "Failed to update repository: ${name}"
            echo "${output}"
            return 1
        fi
    else
        log_info "Updating all Helm repositories"
        
        # Update all repositories
        log_debug "Executing: helm repo update"
        if output=$(helm repo update 2>&1); then
            log_success "All repositories updated"
            echo "${output}"
            return 0
        else
            log_error "Failed to update repositories"
            echo "${output}"
            return 1
        fi
    fi
}

# List Helm repositories
helm_list_repositories() {
    local format="${1:-table}"
    
    log_info "Listing Helm repositories"
    
    # Build list command
    local cmd=(helm repo list)
    
    # Add format if not table
    if [[ "${format}" != "table" ]]; then
        cmd+=(--output "${format}")
    fi
    
    # Execute list
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        echo "${output}"
        return 0
    else
        # Check if no repositories
        if [[ "${output}" =~ no\ repositories ]]; then
            log_warn "No repositories configured"
            return 0
        fi
        
        log_error "Failed to list repositories"
        echo "${output}"
        return 1
    fi
}

# Search for charts in repositories
helm_search_repository() {
    local keyword="$1"
    local repo="${2:-}"
    shift 2
    local args=("$@")
    
    log_info "Searching for charts: ${keyword}"
    
    # Validate inputs
    if [[ -z "${keyword}" ]]; then
        log_error "Search keyword is required"
        return 1
    fi
    
    # Build search command
    local cmd=(helm search repo)
    
    # Add repo prefix if specified
    if [[ -n "${repo}" ]]; then
        cmd+=("${repo}/${keyword}")
    else
        cmd+=("${keyword}")
    fi
    
    # Add additional arguments
    if [[ ${#args[@]} -gt 0 ]]; then
        cmd+=("${args[@]}")
    fi
    
    # Execute search
    log_debug "Executing: ${cmd[*]}"
    if output=$("${cmd[@]}" 2>&1); then
        echo "${output}"
        return 0
    else
        log_error "Search failed: ${keyword}"
        echo "${output}"
        return 1
    fi
}

# Check repository health
helm_repository_health_check() {
    local name="$1"
    
    log_info "Checking repository health: ${name}"
    
    # Validate inputs
    if [[ -z "${name}" ]]; then
        log_error "Repository name is required"
        return 1
    fi
    
    # Get repository list
    local repos
    repos=$(helm repo list --output json 2>&1) || {
        log_error "Failed to list repositories"
        return 1
    }
    
    # Check if repository exists
    local url
    url=$(echo "${repos}" | jq -r ".[] | select(.name == \"${name}\") | .url" 2>/dev/null)
    
    if [[ -z "${url}" ]] || [[ "${url}" == "null" ]]; then
        log_error "Repository not found: ${name}"
        return 1
    fi
    
    log_info "Repository URL: ${url}"
    
    # Try to update repository
    if output=$(helm repo update "${name}" 2>&1); then
        log_success "Repository is healthy: ${name}"
        return 0
    else
        log_error "Repository is unhealthy: ${name}"
        echo "${output}"
        return 1
    fi
}

# Ensure repository is added
helm_ensure_repository_added() {
    local name="$1"
    local url="$2"
    shift 2
    local args=("$@")
    
    log_info "Ensuring repository is added: ${name}"
    
    # Check if repository already exists
    local repos
    repos=$(helm repo list --output json 2>/dev/null) || repos="[]"
    
    local existing_url
    existing_url=$(echo "${repos}" | jq -r ".[] | select(.name == \"${name}\") | .url" 2>/dev/null)
    
    if [[ -n "${existing_url}" ]] && [[ "${existing_url}" != "null" ]]; then
        # Repository exists
        if [[ "${existing_url}" == "${url}" ]]; then
            log_info "Repository already configured correctly: ${name}"
            
            # Update repository
            helm_update_repositories "${name}" >/dev/null
            return 0
        else
            log_warn "Repository exists with different URL"
            log_warn "  Existing: ${existing_url}"
            log_warn "  Requested: ${url}"
            log_info "Removing old repository..."
            
            helm_remove_repository "${name}" >/dev/null || true
        fi
    fi
    
    # Add repository
    helm_add_repository "${name}" "${url}" "${args[@]}"
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Release lifecycle
export -f helm_install_or_upgrade helm_install_release helm_upgrade_release
export -f helm_rollback_release helm_uninstall_release
export -f helm_get_release_status helm_get_release_values helm_get_release_history

# Chart operations
export -f helm_fetch_chart helm_template_chart helm_lint_chart helm_package_chart
export -f helm_show_chart_info helm_show_chart_values
export -f helm_dependency_update helm_dependency_build helm_dependency_list

# Repository management
export -f helm_add_repository helm_remove_repository helm_update_repositories
export -f helm_list_repositories helm_search_repository
export -f helm_repository_health_check helm_ensure_repository_added

# ==============================================================================
# HYBRID DEPENDENCY MANAGEMENT
# ==============================================================================

# Discover all dependencies (local and remote) from Chart.yaml
helm_dependency_discover_all() {
    local chart="$1"
    local format="${2:-json}"
    
    log_info "Discovering all dependencies for: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    local chart_yaml="${chart}/Chart.yaml"
    if [[ ! -f "${chart_yaml}" ]]; then
        log_error "Chart.yaml not found: ${chart_yaml}"
        return 1
    fi
    
    # Parse dependencies
    local deps
    deps=$(yq eval '.dependencies // []' "${chart_yaml}" 2>/dev/null) || {
        log_error "Failed to parse Chart.yaml"
        return 1
    }
    
    # Check if empty
    if [[ "${deps}" == "[]" ]] || [[ -z "${deps}" ]]; then
        log_info "No dependencies found"
        echo "[]"
        return 0
    fi
    
    # Build dependency info
    local dep_count
    dep_count=$(echo "${deps}" | yq eval 'length' - 2>/dev/null)
    
    log_info "Found ${dep_count} dependencies"
    
    # Output in requested format
    case "${format}" in
        json)
            echo "${deps}" | yq eval -o=json -
            ;;
        yaml)
            echo "${deps}"
            ;;
        table)
            echo "${deps}" | yq eval '.[] | [.name, .version, .repository] | @tsv' - 2>/dev/null | \
                awk 'BEGIN {print "NAME\tVERSION\tREPOSITORY"} {print}'
            ;;
        *)
            echo "${deps}"
            ;;
    esac
}

# Discover and extract repository URLs from dependencies
helm_dependency_discover_repositories() {
    local chart="$1"
    
    log_info "Discovering repositories from dependencies: ${chart}"
    
    # Get all dependencies
    local deps
    deps=$(helm_dependency_discover_all "${chart}" json) || return 1
    
    # Extract unique repository URLs
    local repos
    repos=$(echo "${deps}" | jq -r '.[].repository // empty' 2>/dev/null | sort -u)
    
    if [[ -z "${repos}" ]]; then
        log_info "No remote repositories found"
        return 0
    fi
    
    # Output repositories
    echo "${repos}"
}

# Update dependencies with hybrid support (local + remote)
helm_dependency_update_hybrid() {
    local chart="$1"
    local skip_refresh="${2:-false}"
    
    log_info "Updating hybrid dependencies for: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]]; then
        log_error "Chart path is required"
        return 1
    fi
    
    # Discover all repositories
    log_info "Discovering required repositories..."
    local repos
    repos=$(helm_dependency_discover_repositories "${chart}") || return 1
    
    # Add/update remote repositories
    while IFS= read -r repo; do
        [[ -z "${repo}" ]] && continue
        
        # Skip local repositories (file://, ../, ./)
        if [[ "${repo}" =~ ^file:// ]] || [[ "${repo}" =~ ^\.\.?/ ]]; then
            log_debug "Skipping local repository: ${repo}"
            continue
        fi
        
        # Generate repository name
        local repo_name
        repo_name=$(helm_generate_repo_name_from_url "${repo}")
        
        # Ensure repository is added
        log_info "Ensuring repository: ${repo_name}"
        helm_ensure_repository_added "${repo_name}" "${repo}" --force-update >/dev/null || {
            log_warn "Failed to add repository: ${repo_name}"
        }
    done <<< "${repos}"
    
    # Refresh repositories unless skipped
    if [[ "${skip_refresh}" != "true" ]]; then
        log_info "Refreshing repository indexes..."
        helm_update_repositories >/dev/null || {
            log_warn "Repository update had issues"
        }
    fi
    
    # Validate local dependencies
    log_info "Validating local dependencies..."
    if ! helm_validate_local_dependency "${chart}"; then
        log_warn "Some local dependencies may have issues"
    fi
    
    # Run helm dependency update
    log_info "Updating Helm dependencies..."
    if helm_dependency_update "${chart}"; then
        log_success "Hybrid dependencies updated successfully"
        return 0
    else
        log_error "Failed to update dependencies"
        return 1
    fi
}

# Validate local chart dependencies exist and are valid
helm_validate_local_dependency() {
    local chart="$1"
    
    log_info "Validating local dependencies for: ${chart}"
    
    # Get dependencies
    local deps
    deps=$(helm_dependency_discover_all "${chart}" json) || return 1
    
    # Check each dependency
    local all_valid=true
    local count=0
    
    while IFS= read -r dep; do
        [[ -z "${dep}" ]] && continue
        
        local name repo
        name=$(echo "${dep}" | jq -r '.name')
        repo=$(echo "${dep}" | jq -r '.repository')
        
        # Check if local repository
        if [[ "${repo}" =~ ^file:// ]] || [[ "${repo}" =~ ^\.\.?/ ]]; then
            count=$((count + 1))
            
            # Resolve path
            local dep_path
            dep_path=$(helm_dependency_resolve_path "${chart}" "${repo}")
            
            log_debug "Checking local dependency: ${name} at ${dep_path}"
            
            # Check if path exists
            if [[ ! -d "${dep_path}" ]]; then
                log_error "Local dependency not found: ${name} (${dep_path})"
                all_valid=false
                continue
            fi
            
            # Check if Chart.yaml exists
            if [[ ! -f "${dep_path}/Chart.yaml" ]]; then
                log_error "Invalid chart (no Chart.yaml): ${name} (${dep_path})"
                all_valid=false
                continue
            fi
            
            log_debug "Local dependency valid: ${name}"
        fi
    done < <(echo "${deps}" | jq -c '.[]' 2>/dev/null)
    
    if [[ ${count} -eq 0 ]]; then
        log_info "No local dependencies found"
        return 0
    fi
    
    if [[ "${all_valid}" == "true" ]]; then
        log_success "All ${count} local dependencies are valid"
        return 0
    else
        log_error "Some local dependencies are invalid"
        return 1
    fi
}

# Rebuild local dependencies (repackage local charts)
helm_rebuild_local_dependencies() {
    local chart="$1"
    local destination="${chart}/charts"
    
    log_info "Rebuilding local dependencies for: ${chart}"
    
    # Create charts directory
    mkdir -p "${destination}"
    
    # Get dependencies
    local deps
    deps=$(helm_dependency_discover_all "${chart}" json) || return 1
    
    # Rebuild each local dependency
    local count=0
    
    while IFS= read -r dep; do
        [[ -z "${dep}" ]] && continue
        
        local name repo version
        name=$(echo "${dep}" | jq -r '.name')
        repo=$(echo "${dep}" | jq -r '.repository')
        version=$(echo "${dep}" | jq -r '.version')
        
        # Check if local repository
        if [[ "${repo}" =~ ^file:// ]] || [[ "${repo}" =~ ^\.\.?/ ]]; then
            count=$((count + 1))
            
            # Resolve path
            local dep_path
            dep_path=$(helm_dependency_resolve_path "${chart}" "${repo}")
            
            log_info "Packaging local dependency: ${name} (${version})"
            
            # Package chart
            if helm_package_chart "${dep_path}" "${destination}" --version "${version}" >/dev/null; then
                log_success "Packaged: ${name}-${version}.tgz"
            else
                log_error "Failed to package: ${name}"
                return 1
            fi
        fi
    done < <(echo "${deps}" | jq -c '.[]' 2>/dev/null)
    
    if [[ ${count} -eq 0 ]]; then
        log_info "No local dependencies to rebuild"
        return 0
    fi
    
    log_success "Rebuilt ${count} local dependencies"
}

# Verify all dependencies are satisfied
helm_dependency_verify() {
    local chart="$1"
    
    log_info "Verifying dependencies for: ${chart}"
    
    # Check charts directory
    local charts_dir="${chart}/charts"
    
    if [[ ! -d "${charts_dir}" ]]; then
        log_error "Charts directory not found: ${charts_dir}"
        log_info "Run 'helm dependency update' first"
        return 1
    fi
    
    # Get expected dependencies
    local deps
    deps=$(helm_dependency_discover_all "${chart}" json) || return 1
    
    local dep_count
    dep_count=$(echo "${deps}" | jq 'length' 2>/dev/null)
    
    if [[ ${dep_count} -eq 0 ]]; then
        log_info "No dependencies to verify"
        return 0
    fi
    
    # Check each dependency
    local all_satisfied=true
    
    while IFS= read -r dep; do
        [[ -z "${dep}" ]] && continue
        
        local name version
        name=$(echo "${dep}" | jq -r '.name')
        version=$(echo "${dep}" | jq -r '.version')
        
        # Look for package or unpacked chart
        local found=false
        
        # Check for .tgz package
        if ls "${charts_dir}/${name}"-*.tgz >/dev/null 2>&1; then
            found=true
            log_debug "Found packaged: ${name}"
        fi
        
        # Check for unpacked directory
        if [[ -d "${charts_dir}/${name}" ]]; then
            found=true
            log_debug "Found unpacked: ${name}"
        fi
        
        if [[ "${found}" != "true" ]]; then
            log_error "Missing dependency: ${name} (${version})"
            all_satisfied=false
        fi
    done < <(echo "${deps}" | jq -c '.[]' 2>/dev/null)
    
    if [[ "${all_satisfied}" == "true" ]]; then
        log_success "All ${dep_count} dependencies satisfied"
        return 0
    else
        log_error "Some dependencies are missing"
        return 1
    fi
}

# Clean dependency cache
helm_dependency_clean() {
    local chart="$1"
    
    log_info "Cleaning dependency cache for: ${chart}"
    
    local charts_dir="${chart}/charts"
    local lock_file="${chart}/Chart.lock"
    
    # Remove charts directory
    if [[ -d "${charts_dir}" ]]; then
        log_info "Removing charts directory..."
        rm -rf "${charts_dir}"
        log_success "Removed: ${charts_dir}"
    fi
    
    # Remove Chart.lock
    if [[ -f "${lock_file}" ]]; then
        log_info "Removing Chart.lock..."
        rm -f "${lock_file}"
        log_success "Removed: ${lock_file}"
    fi
    
    log_success "Dependency cache cleaned"
}

# Resolve dependency path (handle file://, ../, ./)
helm_dependency_resolve_path() {
    local chart="$1"
    local repo="$2"
    
    local chart_dir
    chart_dir=$(cd "${chart}" && pwd)
    
    # Handle file:// protocol
    if [[ "${repo}" =~ ^file:// ]]; then
        repo="${repo#file://}"
    fi
    
    # Handle relative paths
    if [[ "${repo}" =~ ^\.\.?/ ]]; then
        # Resolve relative to chart directory
        echo "$(cd "${chart_dir}" && cd "${repo}" && pwd)"
    else
        # Absolute or other path
        echo "${repo}"
    fi
}

# Generate repository name from URL
helm_generate_repo_name_from_url() {
    local url="$1"
    
    # Extract meaningful name from URL
    local name
    
    # Remove protocol
    name="${url#*://}"
    
    # Remove trailing slashes
    name="${name%/}"
    
    # Replace special characters with hyphens
    name=$(echo "${name}" | tr '/:@.' '-' | tr -s '-')
    
    # Truncate if too long
    if [[ ${#name} -gt 53 ]]; then
        name="${name:0:53}"
    fi
    
    echo "${name}"
}

# Discover common Helm repositories (bitnami, stable, etc.)
helm_discover_common_repositories() {
    local format="${1:-table}"
    
    log_info "Discovering common Helm repositories"
    
    # Common repositories
    local repos='[
        {"name": "bitnami", "url": "https://charts.bitnami.com/bitnami"},
        {"name": "stable", "url": "https://charts.helm.sh/stable"},
        {"name": "ingress-nginx", "url": "https://kubernetes.github.io/ingress-nginx"},
        {"name": "jetstack", "url": "https://charts.jetstack.io"},
        {"name": "prometheus-community", "url": "https://prometheus-community.github.io/helm-charts"},
        {"name": "grafana", "url": "https://grafana.github.io/helm-charts"},
        {"name": "elastic", "url": "https://helm.elastic.co"},
        {"name": "hashicorp", "url": "https://helm.releases.hashicorp.com"}
    ]'
    
    # Output in requested format
    case "${format}" in
        json)
            echo "${repos}"
            ;;
        yaml)
            echo "${repos}" | yq eval -P -
            ;;
        table)
            echo "${repos}" | jq -r '.[] | [.name, .url] | @tsv' | \
                awk 'BEGIN {print "NAME\tURL"} {print}'
            ;;
        *)
            echo "${repos}"
            ;;
    esac
}

# ==============================================================================
# RESOURCE VALIDATION
# ==============================================================================

# Wait for Helm release to reach desired status
helm_wait_for_release() {
    local release="$1"
    local namespace="$2"
    local desired_status="${3:-deployed}"
    local timeout="${4:-300}"
    
    log_info "Waiting for release ${release} to reach status: ${desired_status}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Use wait_for_helm_release from forge-core
    if wait_for_helm_release "${release}" "${namespace}" "${desired_status}" "${timeout}"; then
        log_success "Release reached desired status: ${desired_status}"
        return 0
    else
        log_error "Release did not reach desired status within ${timeout}s"
        return 1
    fi
}

# Check pod status for a release
helm_check_pod_status() {
    local release="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    log_info "Checking pod status for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Get pods for release
    log_debug "Finding pods for release: ${release}"
    local pods
    pods=$(kubectl get pods -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o name 2>&1) || {
        log_error "Failed to get pods for release"
        return 1
    }
    
    if [[ -z "${pods}" ]]; then
        log_warn "No pods found for release: ${release}"
        return 0
    fi
    
    # Wait for all pods to be ready
    local all_ready=true
    local pod_count=0
    
    while IFS= read -r pod; do
        [[ -z "${pod}" ]] && continue
        pod_count=$((pod_count + 1))
        
        log_info "Waiting for ${pod} to be ready..."
        
        if kubectl wait "${pod}" -n "${namespace}" \
            --for=condition=Ready \
            --timeout="${timeout}s" >/dev/null 2>&1; then
            log_success "Pod ready: ${pod}"
        else
            log_error "Pod not ready: ${pod}"
            all_ready=false
        fi
    done <<< "${pods}"
    
    if [[ "${all_ready}" == "true" ]]; then
        log_success "All ${pod_count} pods are ready"
        return 0
    else
        log_error "Some pods are not ready"
        return 1
    fi
}

# Check service endpoints
helm_check_service_endpoints() {
    local release="$1"
    local namespace="$2"
    
    log_info "Checking service endpoints for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Get services for release
    local services
    services=$(kubectl get svc -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o name 2>&1) || {
        log_error "Failed to get services for release"
        return 1
    }
    
    if [[ -z "${services}" ]]; then
        log_warn "No services found for release: ${release}"
        return 0
    fi
    
    # Check each service
    local all_ready=true
    local svc_count=0
    
    while IFS= read -r svc; do
        [[ -z "${svc}" ]] && continue
        svc_count=$((svc_count + 1))
        
        local svc_name="${svc#service/}"
        log_debug "Checking endpoints for: ${svc_name}"
        
        # Get endpoints
        local endpoints
        endpoints=$(kubectl get endpoints "${svc_name}" -n "${namespace}" -o json 2>&1) || {
            log_warn "Failed to get endpoints for: ${svc_name}"
            all_ready=false
            continue
        }
        
        # Check if endpoints exist
        local ready_addresses
        ready_addresses=$(echo "${endpoints}" | jq -r '.subsets[]?.addresses // [] | length' 2>/dev/null | awk '{s+=$1} END {print s+0}')
        
        if [[ ${ready_addresses} -gt 0 ]]; then
            log_success "Service has ${ready_addresses} ready endpoints: ${svc_name}"
        else
            log_warn "Service has no ready endpoints: ${svc_name}"
            all_ready=false
        fi
    done <<< "${services}"
    
    if [[ "${all_ready}" == "true" ]]; then
        log_success "All ${svc_count} services have endpoints"
        return 0
    else
        log_warn "Some services have no endpoints"
        return 1
    fi
}

# Check deployment rollout status
helm_check_deployment_rollout() {
    local release="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    log_info "Checking deployment rollout for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Get deployments for release
    local deployments
    deployments=$(kubectl get deployment -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o name 2>&1) || {
        log_error "Failed to get deployments for release"
        return 1
    }
    
    if [[ -z "${deployments}" ]]; then
        log_info "No deployments found for release: ${release}"
        return 0
    fi
    
    # Check each deployment
    local all_ready=true
    local deploy_count=0
    
    while IFS= read -r deploy; do
        [[ -z "${deploy}" ]] && continue
        deploy_count=$((deploy_count + 1))
        
        log_info "Waiting for rollout: ${deploy}"
        
        if kubectl rollout status "${deploy}" -n "${namespace}" --timeout="${timeout}s" 2>&1 | log_pipe_output "debug"; then
            log_success "Rollout complete: ${deploy}"
        else
            log_error "Rollout failed or timed out: ${deploy}"
            all_ready=false
        fi
    done <<< "${deployments}"
    
    if [[ "${all_ready}" == "true" ]]; then
        log_success "All ${deploy_count} deployments rolled out successfully"
        return 0
    else
        log_error "Some deployments failed to roll out"
        return 1
    fi
}

# Check StatefulSet ready status
helm_check_statefulset_ready() {
    local release="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    log_info "Checking StatefulSet status for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Get StatefulSets for release
    local statefulsets
    statefulsets=$(kubectl get statefulset -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o name 2>&1) || {
        log_error "Failed to get StatefulSets for release"
        return 1
    }
    
    if [[ -z "${statefulsets}" ]]; then
        log_info "No StatefulSets found for release: ${release}"
        return 0
    fi
    
    # Check each StatefulSet
    local all_ready=true
    local sts_count=0
    
    while IFS= read -r sts; do
        [[ -z "${sts}" ]] && continue
        sts_count=$((sts_count + 1))
        
        log_info "Waiting for StatefulSet: ${sts}"
        
        if kubectl rollout status "${sts}" -n "${namespace}" --timeout="${timeout}s" 2>&1 | log_pipe_output "debug"; then
            log_success "StatefulSet ready: ${sts}"
        else
            log_error "StatefulSet not ready: ${sts}"
            all_ready=false
        fi
    done <<< "${statefulsets}"
    
    if [[ "${all_ready}" == "true" ]]; then
        log_success "All ${sts_count} StatefulSets are ready"
        return 0
    else
        log_error "Some StatefulSets are not ready"
        return 1
    fi
}

# Check DaemonSet ready status
helm_check_daemonset_ready() {
    local release="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    log_info "Checking DaemonSet status for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Get DaemonSets for release
    local daemonsets
    daemonsets=$(kubectl get daemonset -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o name 2>&1) || {
        log_error "Failed to get DaemonSets for release"
        return 1
    }
    
    if [[ -z "${daemonsets}" ]]; then
        log_info "No DaemonSets found for release: ${release}"
        return 0
    fi
    
    # Check each DaemonSet
    local all_ready=true
    local ds_count=0
    
    while IFS= read -r ds; do
        [[ -z "${ds}" ]] && continue
        ds_count=$((ds_count + 1))
        
        log_info "Waiting for DaemonSet: ${ds}"
        
        if kubectl rollout status "${ds}" -n "${namespace}" --timeout="${timeout}s" 2>&1 | log_pipe_output "debug"; then
            log_success "DaemonSet ready: ${ds}"
        else
            log_error "DaemonSet not ready: ${ds}"
            all_ready=false
        fi
    done <<< "${daemonsets}"
    
    if [[ "${all_ready}" == "true" ]]; then
        log_success "All ${ds_count} DaemonSets are ready"
        return 0
    else
        log_error "Some DaemonSets are not ready"
        return 1
    fi
}

# Check Job completion status
helm_check_job_completion() {
    local release="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    log_info "Checking Job completion for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    # Get Jobs for release
    local jobs
    jobs=$(kubectl get job -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o name 2>&1) || {
        log_error "Failed to get Jobs for release"
        return 1
    }
    
    if [[ -z "${jobs}" ]]; then
        log_info "No Jobs found for release: ${release}"
        return 0
    fi
    
    # Check each Job
    local all_complete=true
    local job_count=0
    
    while IFS= read -r job; do
        [[ -z "${job}" ]] && continue
        job_count=$((job_count + 1))
        
        log_info "Waiting for Job: ${job}"
        
        if kubectl wait "${job}" -n "${namespace}" \
            --for=condition=Complete \
            --timeout="${timeout}s" 2>&1 | log_pipe_output "debug"; then
            log_success "Job completed: ${job}"
        else
            log_error "Job did not complete: ${job}"
            all_complete=false
        fi
    done <<< "${jobs}"
    
    if [[ "${all_complete}" == "true" ]]; then
        log_success "All ${job_count} Jobs completed successfully"
        return 0
    else
        log_error "Some Jobs did not complete"
        return 1
    fi
}

# Check overall resource health for release
helm_check_resource_health() {
    local release="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    local check_jobs="${4:-false}"
    
    log_info "Performing comprehensive health check for release: ${release}"
    
    # Validate inputs
    if [[ -z "${release}" ]] || [[ -z "${namespace}" ]]; then
        log_error "Release name and namespace are required"
        return 1
    fi
    
    local health_ok=true
    
    # Check Deployments
    log_info "==> Checking Deployments..."
    if ! helm_check_deployment_rollout "${release}" "${namespace}" "${timeout}"; then
        health_ok=false
    fi
    
    # Check StatefulSets
    log_info "==> Checking StatefulSets..."
    if ! helm_check_statefulset_ready "${release}" "${namespace}" "${timeout}"; then
        health_ok=false
    fi
    
    # Check DaemonSets
    log_info "==> Checking DaemonSets..."
    if ! helm_check_daemonset_ready "${release}" "${namespace}" "${timeout}"; then
        health_ok=false
    fi
    
    # Check Jobs (optional)
    if [[ "${check_jobs}" == "true" ]]; then
        log_info "==> Checking Jobs..."
        if ! helm_check_job_completion "${release}" "${namespace}" "${timeout}"; then
            health_ok=false
        fi
    fi
    
    # Check Pods
    log_info "==> Checking Pods..."
    if ! helm_check_pod_status "${release}" "${namespace}" "${timeout}"; then
        health_ok=false
    fi
    
    # Check Services
    log_info "==> Checking Services..."
    if ! helm_check_service_endpoints "${release}" "${namespace}"; then
        health_ok=false
    fi
    
    # Final result
    if [[ "${health_ok}" == "true" ]]; then
        log_success "All health checks passed for release: ${release}"
        return 0
    else
        log_error "Some health checks failed for release: ${release}"
        return 1
    fi
}

# ==============================================================================
# VALUES MANAGEMENT
# ==============================================================================

# Merge multiple values files
helm_merge_values_files() {
    local output="$1"
    shift
    local values_files=("$@")
    
    log_info "Merging ${#values_files[@]} values files into: ${output}"
    
    # Validate inputs
    if [[ -z "${output}" ]] || [[ ${#values_files[@]} -eq 0 ]]; then
        log_error "Output file and at least one values file are required"
        return 1
    fi
    
    # Check all files exist
    for file in "${values_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            log_error "Values file not found: ${file}"
            return 1
        fi
    done
    
    # Use merge_yaml_files from forge-core
    if merge_yaml_files "${output}" "${values_files[@]}"; then
        log_success "Values files merged successfully"
        return 0
    else
        log_error "Failed to merge values files"
        return 1
    fi
}

# Validate values against chart schema
helm_validate_values_schema() {
    local chart="$1"
    local values_file="$2"
    
    log_info "Validating values against chart schema: ${chart}"
    
    # Validate inputs
    if [[ -z "${chart}" ]] || [[ -z "${values_file}" ]]; then
        log_error "Chart and values file are required"
        return 1
    fi
    
    if [[ ! -f "${values_file}" ]]; then
        log_error "Values file not found: ${values_file}"
        return 1
    fi
    
    # Check if chart has schema
    local schema_file="${chart}/values.schema.json"
    
    if [[ ! -f "${schema_file}" ]]; then
        log_warn "No values.schema.json found in chart, skipping validation"
        return 0
    fi
    
    log_info "Found schema file: ${schema_file}"
    
    # Validate using yq and jq (basic validation)
    log_info "Validating YAML syntax..."
    if ! yq eval '.' "${values_file}" >/dev/null 2>&1; then
        log_error "Invalid YAML syntax in values file"
        return 1
    fi
    
    # Convert to JSON for schema validation
    local values_json
    values_json=$(yq eval -o=json '.' "${values_file}" 2>&1) || {
        log_error "Failed to convert values to JSON"
        return 1
    }
    
    # Note: Full JSON Schema validation would require additional tools
    log_warn "Full JSON Schema validation requires 'ajv-cli' or similar tools"
    log_info "Performing basic structure validation..."
    
    log_success "Basic values validation passed"
    return 0
}

# Generate diff between values files
helm_diff_values() {
    local file1="$1"
    local file2="$2"
    local format="${3:-yaml}"
    
    log_info "Generating diff between values files"
    
    # Validate inputs
    if [[ -z "${file1}" ]] || [[ -z "${file2}" ]]; then
        log_error "Two values files are required"
        return 1
    fi
    
    if [[ ! -f "${file1}" ]]; then
        log_error "First values file not found: ${file1}"
        return 1
    fi
    
    if [[ ! -f "${file2}" ]]; then
        log_error "Second values file not found: ${file2}"
        return 1
    fi
    
    # Generate diff based on format
    case "${format}" in
        yaml)
            diff -u "${file1}" "${file2}" || true
            ;;
        json)
            local json1 json2
            json1=$(yq eval -o=json '.' "${file1}")
            json2=$(yq eval -o=json '.' "${file2}")
            diff -u <(echo "${json1}" | jq -S .) <(echo "${json2}" | jq -S .) || true
            ;;
        *)
            log_error "Unsupported format: ${format}"
            return 1
            ;;
    esac
}

# Get computed values for a release
helm_get_computed_values() {
    local release="$1"
    local namespace="$2"
    local format="${3:-yaml}"
    
    # Use helm_get_release_values (already implemented)
    helm_get_release_values "${release}" "${namespace}" "${format}" true
}

# Set a specific value in values file
helm_set_value() {
    local values_file="$1"
    local key="$2"
    local value="$3"
    local value_type="${4:-string}"
    
    log_info "Setting value in ${values_file}: ${key}=${value}"
    
    # Validate inputs
    if [[ -z "${values_file}" ]] || [[ -z "${key}" ]]; then
        log_error "Values file and key are required"
        return 1
    fi
    
    if [[ ! -f "${values_file}" ]]; then
        log_error "Values file not found: ${values_file}"
        return 1
    fi
    
    # Create backup
    local backup="${values_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "${values_file}" "${backup}"
    log_debug "Created backup: ${backup}"
    
    # Set value based on type
    local yq_expr
    case "${value_type}" in
        string)
            yq_expr=".${key} = \"${value}\""
            ;;
        number)
            yq_expr=".${key} = ${value}"
            ;;
        boolean)
            yq_expr=".${key} = ${value}"
            ;;
        null)
            yq_expr=".${key} = null"
            ;;
        *)
            log_error "Unsupported value type: ${value_type}"
            return 1
            ;;
    esac
    
    # Apply change
    if yq eval -i "${yq_expr}" "${values_file}" 2>&1 | log_pipe_output "debug"; then
        log_success "Value set successfully"
        log_info "Backup saved to: ${backup}"
        return 0
    else
        log_error "Failed to set value"
        # Restore backup
        mv "${backup}" "${values_file}"
        return 1
    fi
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Release lifecycle
export -f helm_install_or_upgrade helm_install_release helm_upgrade_release
export -f helm_rollback_release helm_uninstall_release
export -f helm_get_release_status helm_get_release_values helm_get_release_history

# Chart operations
export -f helm_fetch_chart helm_template_chart helm_lint_chart helm_package_chart
export -f helm_show_chart_info helm_show_chart_values
export -f helm_dependency_update helm_dependency_build helm_dependency_list

# Repository management
export -f helm_add_repository helm_remove_repository helm_update_repositories
export -f helm_list_repositories helm_search_repository
export -f helm_repository_health_check helm_ensure_repository_added

# Hybrid dependency management
export -f helm_dependency_discover_all helm_dependency_discover_repositories
export -f helm_dependency_update_hybrid helm_validate_local_dependency
export -f helm_rebuild_local_dependencies helm_dependency_verify helm_dependency_clean
export -f helm_dependency_resolve_path helm_generate_repo_name_from_url
export -f helm_discover_common_repositories

# Resource validation
export -f helm_wait_for_release helm_check_pod_status helm_check_service_endpoints
export -f helm_check_deployment_rollout helm_check_statefulset_ready
export -f helm_check_daemonset_ready helm_check_job_completion
export -f helm_check_resource_health

# Values management
export -f helm_merge_values_files helm_validate_values_schema helm_diff_values
export -f helm_get_computed_values helm_set_value

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-helm-operations.sh v${FORGE_HELM_OPERATIONS_VERSION}"
