#!/usr/bin/env bash
# ==============================================================================
# Forge Kubernetes Operations Library
# ==============================================================================
# Description: Kubernetes resource CRUD and management operations
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - Generic port-forward management (not service-specific)
# - ConfigMap CRUD operations (create, read, update, delete)
# - Secret CRUD operations (create, read, update, delete)
# - Label management with Forge patterns
# - Advanced kubectl operations (retry, wait for conditions)
# - Resource lifecycle management
#
# Dependencies:
#   - forge-core.sh (logging, validation, retry logic)
#   - forge-patterns.sh (naming conventions, label generation)
#   - forge-k8s-discovery.sh (context detection, kubectl wrapper)
#
# Usage:
#   source /path/to/forge-k8s-operations.sh
#   setup_port_forward_generic "vault" "vault" 8200 8200
#   create_configmap "my-config" "default" "key1=value1" "key2=value2"
#   apply_forge_labels_to_resource "deployment" "my-app" "default" "customer" "project" "dev" "app"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_K8S_OPERATIONS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_K8S_OPERATIONS_VERSION="1.0.0"
readonly FORGE_K8S_OPERATIONS_LOADED="true"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Get library directory
if [[ -z "${LIB_DIR:-}" ]]; then
  LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source required libraries (in order of dependencies)
source "${LIB_DIR}/forge-core.sh"
source "${LIB_DIR}/forge-patterns.sh"
source "${LIB_DIR}/forge-k8s-discovery.sh"

# Validate required commands
validate_required_commands kubectl jq

# ==============================================================================
# PORT FORWARD OPERATIONS
# ==============================================================================

# setup_port_forward_generic
# Sets up a generic kubectl port-forward to any service/pod
#
# This is a generic version (not Vault-specific) that can forward to any
# Kubernetes service or pod. Stores PID in a temp file for cleanup.
#
# Arguments:
#   $1 - resource_type: "service" or "pod" or "deployment"
#   $2 - resource_name: Name of the resource
#   $3 - namespace: Kubernetes namespace
#   $4 - local_port: Local port to forward to
#   $5 - remote_port: Remote port on the resource
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   PID file path to stdout
#
# Example:
#   pid_file=$(setup_port_forward_generic "service" "vault" "vault" "8200" "8200")
#   # Port-forward running, PID stored in $pid_file
#
#   # Later cleanup:
#   cleanup_port_forward_generic "$pid_file"
#
setup_port_forward_generic() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  local local_port="$4"
  local remote_port="$5"
  
  validate_not_empty resource_type "Resource type cannot be empty"
  validate_not_empty resource_name "Resource name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  validate_not_empty local_port "Local port cannot be empty"
  validate_not_empty remote_port "Remote port cannot be empty"
  
  # Validate port numbers
  if ! is_valid_port "$local_port"; then
    log_error "Invalid local port: $local_port"
    return 1
  fi
  
  if ! is_valid_port "$remote_port"; then
    log_error "Invalid remote port: $remote_port"
    return 1
  fi
  
  log_info "Setting up port-forward: ${resource_type}/${resource_name} in ${namespace}"
  log_debug "  Local port: $local_port -> Remote port: $remote_port"
  
  # Check if port is already in use
  if lsof -Pi ":${local_port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    log_warning "Port $local_port is already in use"
    
    # Check if it's our port-forward
    local existing_pid
    existing_pid=$(lsof -Pi ":${local_port}" -sTCP:LISTEN -t)
    if ps -p "$existing_pid" | grep -q "kubectl.*port-forward"; then
      log_info "Existing port-forward found (PID: $existing_pid), reusing"
      local pid_file="/tmp/kubectl-port-forward-${namespace}-${resource_name}-${local_port}.pid"
      echo "$existing_pid" > "$pid_file"
      echo "$pid_file"
      return 0
    else
      log_error "Port $local_port is in use by another process (PID: $existing_pid)"
      return 1
    fi
  fi
  
  # Create PID file path
  local pid_file="/tmp/kubectl-port-forward-${namespace}-${resource_name}-${local_port}.pid"
  
  # Start port-forward in background
  log_debug "Starting kubectl port-forward..."
  kubectl port-forward \
    -n "$namespace" \
    "${resource_type}/${resource_name}" \
    "${local_port}:${remote_port}" \
    >/dev/null 2>&1 &
  
  local pid=$!
  
  # Save PID to file
  echo "$pid" > "$pid_file"
  
  # Wait a moment and verify it's running
  sleep 2
  
  if ! kill -0 "$pid" 2>/dev/null; then
    log_error "Port-forward failed to start"
    rm -f "$pid_file"
    return 1
  fi
  
  # Verify port is listening
  if ! lsof -Pi ":${local_port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    log_error "Port-forward started but port $local_port is not listening"
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
    return 1
  fi
  
  log_success "Port-forward established (PID: $pid, port: $local_port)"
  
  # Return PID file path
  echo "$pid_file"
  return 0
}

# cleanup_port_forward_generic
# Cleans up a port-forward process
#
# Arguments:
#   $1 - pid_file: Path to PID file (from setup_port_forward_generic)
#
# Returns:
#   0 - Success (or already cleaned up)
#   1 - Error
#
# Example:
#   cleanup_port_forward_generic "$pid_file"
#
cleanup_port_forward_generic() {
  local pid_file="$1"
  
  validate_not_empty pid_file "PID file path cannot be empty"
  
  if [[ ! -f "$pid_file" ]]; then
    log_debug "PID file not found, port-forward may already be cleaned up: $pid_file"
    return 0
  fi
  
  local pid
  pid=$(cat "$pid_file")
  
  if [[ -z "$pid" ]]; then
    log_warning "Empty PID in file: $pid_file"
    rm -f "$pid_file"
    return 0
  fi
  
  log_info "Cleaning up port-forward (PID: $pid)"
  
  # Kill the process if it's still running
  if kill -0 "$pid" 2>/dev/null; then
    log_debug "Killing process $pid"
    kill "$pid" 2>/dev/null || true
    
    # Wait for process to die
    for i in {1..5}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    
    # Force kill if still alive
    if kill -0 "$pid" 2>/dev/null; then
      log_warning "Process $pid did not terminate, force killing"
      kill -9 "$pid" 2>/dev/null || true
    fi
  else
    log_debug "Process $pid is not running"
  fi
  
  # Remove PID file
  rm -f "$pid_file"
  
  log_success "Port-forward cleaned up"
  return 0
}

# check_port_forward_running
# Checks if a port-forward is still running
#
# Arguments:
#   $1 - pid_file: Path to PID file
#
# Returns:
#   0 - Port-forward is running
#   1 - Port-forward is not running
#
# Example:
#   if check_port_forward_running "$pid_file"; then
#     echo "Port-forward is active"
#   fi
#
check_port_forward_running() {
  local pid_file="$1"
  
  validate_not_empty pid_file "PID file path cannot be empty"
  
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi
  
  local pid
  pid=$(cat "$pid_file")
  
  if [[ -z "$pid" ]]; then
    return 1
  fi
  
  # Check if process is running
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# ==============================================================================
# CONFIGMAP OPERATIONS
# ==============================================================================

# create_configmap
# Creates a Kubernetes ConfigMap
#
# Arguments:
#   $1 - configmap_name: Name of the ConfigMap
#   $2 - namespace: Kubernetes namespace
#   $@ - data entries in "key=value" format
#
# Environment Variables:
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   create_configmap "my-config" "default" \
#     "database.host=localhost" \
#     "database.port=5432" \
#     "app.name=myapp"
#
#   # Using forge-patterns:
#   cm_name=$(get_configmap_name "customer" "project" "dev" "application" "app")
#   namespace=$(get_namespace_name "customer" "project" "dev" "application")
#   create_configmap "$cm_name" "$namespace" "KEY=value"
#
create_configmap() {
  local configmap_name="$1"
  local namespace="$2"
  shift 2
  
  validate_not_empty configmap_name "ConfigMap name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  if [[ $# -eq 0 ]]; then
    log_error "No data entries provided"
    return 1
  fi
  
  local dry_run="${DRY_RUN:-false}"
  
  log_info "Creating ConfigMap: $configmap_name in namespace $namespace"
  
  # Build kubectl command
  local kubectl_args=(
    "create" "configmap" "$configmap_name"
    "-n" "$namespace"
  )
  
  # Add data entries
  for entry in "$@"; do
    if [[ ! "$entry" =~ ^[^=]+= ]]; then
      log_warning "Invalid data format (expected key=value): $entry"
      continue
    fi
    kubectl_args+=("--from-literal=$entry")
  done
  
  if [[ "$dry_run" == "true" ]]; then
    kubectl_args+=("--dry-run=client" "-o" "yaml")
    log_dry_run "Would create ConfigMap:"
    execute_kubectl "${kubectl_args[@]}"
    return 0
  fi
  
  # Create ConfigMap
  if ! execute_kubectl "${kubectl_args[@]}" >/dev/null; then
    log_error "Failed to create ConfigMap: $configmap_name"
    return 1
  fi
  
  log_success "ConfigMap created: $configmap_name"
  return 0
}

# update_configmap
# Updates a Kubernetes ConfigMap
#
# This replaces the entire ConfigMap. For partial updates, read the existing
# ConfigMap, modify it, and then update.
#
# Arguments:
#   $1 - configmap_name: Name of the ConfigMap
#   $2 - namespace: Kubernetes namespace
#   $@ - data entries in "key=value" format
#
# Environment Variables:
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   update_configmap "my-config" "default" "database.host=newhost"
#
update_configmap() {
  local configmap_name="$1"
  local namespace="$2"
  shift 2
  
  validate_not_empty configmap_name "ConfigMap name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  # Check if ConfigMap exists
  if ! check_configmap_exists "$configmap_name" "$namespace"; then
    log_error "ConfigMap does not exist: $configmap_name"
    return 1
  fi
  
  local dry_run="${DRY_RUN:-false}"
  
  log_info "Updating ConfigMap: $configmap_name in namespace $namespace"
  
  # Delete and recreate (kubectl doesn't have a direct update for configmaps with --from-literal)
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would delete ConfigMap: $configmap_name"
    log_dry_run "Would recreate ConfigMap with new data"
    return 0
  fi
  
  # Delete existing
  execute_kubectl delete configmap "$configmap_name" -n "$namespace" >/dev/null
  
  # Recreate with new data
  create_configmap "$configmap_name" "$namespace" "$@"
}

# delete_configmap
# Deletes a Kubernetes ConfigMap
#
# Arguments:
#   $1 - configmap_name: Name of the ConfigMap
#   $2 - namespace: Kubernetes namespace
#
# Environment Variables:
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   delete_configmap "my-config" "default"
#
delete_configmap() {
  local configmap_name="$1"
  local namespace="$2"
  
  validate_not_empty configmap_name "ConfigMap name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would delete ConfigMap: $configmap_name"
    return 0
  fi
  
  log_info "Deleting ConfigMap: $configmap_name in namespace $namespace"
  
  if ! execute_kubectl delete configmap "$configmap_name" -n "$namespace" >/dev/null; then
    log_error "Failed to delete ConfigMap: $configmap_name"
    return 1
  fi
  
  log_success "ConfigMap deleted: $configmap_name"
  return 0
}

# get_configmap_data
# Gets all data from a ConfigMap as JSON
#
# This returns the entire data section, not just one value.
#
# Arguments:
#   $1 - configmap_name: Name of the ConfigMap
#   $2 - namespace: Kubernetes namespace
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   JSON object with all ConfigMap data to stdout
#
# Example:
#   data=$(get_configmap_data "my-config" "default")
#   echo "$data" | jq -r '.["database.host"]'
#
get_configmap_data() {
  local configmap_name="$1"
  local namespace="$2"
  
  validate_not_empty configmap_name "ConfigMap name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  execute_kubectl get configmap "$configmap_name" -n "$namespace" -o json | jq -r '.data'
}

# ==============================================================================
# LABEL MANAGEMENT
# ==============================================================================

# apply_forge_labels_to_resource
# Applies Forge labels to a Kubernetes resource
#
# This function generates standard Forge labels and applies them to a resource.
# Uses forge-patterns.sh get_forge_labels() for label generation.
#
# Arguments:
#   $1 - resource_type: Type of resource (e.g., "deployment", "service", "pod")
#   $2 - resource_name: Name of the resource
#   $3 - namespace: Kubernetes namespace
#   $4 - customer: Customer name (for labels)
#   $5 - project: Project name (for labels)
#   $6 - environment: Environment (for labels)
#   $7 - service_name: Service name (for labels)
#
# Environment Variables:
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   apply_forge_labels_to_resource \
#     "deployment" \
#     "application-agent" \
#     "customer-project-dev-application-agent" \
#     "customer" \
#     "project" \
#     "dev" \
#     "application-agent"
#
apply_forge_labels_to_resource() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  local customer="$4"
  local project="$5"
  local environment="$6"
  local service_name="$7"
  
  validate_not_empty resource_type "Resource type cannot be empty"
  validate_not_empty resource_name "Resource name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  # Validate forge pattern args
  validate_forge_pattern_args "$customer" "$project" "$environment" "$service_name"
  
  local dry_run="${DRY_RUN:-false}"
  
  log_info "Applying Forge labels to ${resource_type}/${resource_name}"
  
  # Generate Forge labels
  local labels
  labels=$(get_forge_labels "$customer" "$project" "$environment" "$service_name")
  
  # Build kubectl label command
  local label_args=()
  while IFS='=' read -r key value; do
    [[ -z "$key" ]] && continue
    label_args+=("${key}=${value}")
  done <<< "$labels"
  
  if [[ ${#label_args[@]} -eq 0 ]]; then
    log_error "No labels generated"
    return 1
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would apply labels to ${resource_type}/${resource_name}:"
    for label in "${label_args[@]}"; do
      log_dry_run "  $label"
    done
    return 0
  fi
  
  # Apply labels
  if ! execute_kubectl label "$resource_type" "$resource_name" -n "$namespace" "${label_args[@]}" --overwrite >/dev/null; then
    log_error "Failed to apply labels to ${resource_type}/${resource_name}"
    return 1
  fi
  
  log_success "Labels applied to ${resource_type}/${resource_name}"
  return 0
}

# get_resource_labels
# Gets all labels from a Kubernetes resource
#
# Arguments:
#   $1 - resource_type: Type of resource
#   $2 - resource_name: Name of the resource
#   $3 - namespace: Kubernetes namespace
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   JSON object with all labels to stdout
#
# Example:
#   labels=$(get_resource_labels "deployment" "my-app" "default")
#   echo "$labels" | jq -r '.["moai.forge.io/customer"]'
#
get_resource_labels() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  
  validate_not_empty resource_type "Resource type cannot be empty"
  validate_not_empty resource_name "Resource name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  execute_kubectl get "$resource_type" "$resource_name" -n "$namespace" -o json | jq -r '.metadata.labels'
}

# update_resource_labels
# Updates labels on a Kubernetes resource
#
# Arguments:
#   $1 - resource_type: Type of resource
#   $2 - resource_name: Name of the resource
#   $3 - namespace: Kubernetes namespace
#   $@ - Label entries in "key=value" format
#
# Environment Variables:
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   update_resource_labels "deployment" "my-app" "default" \
#     "app.kubernetes.io/version=1.2.3" \
#     "custom-label=value"
#
update_resource_labels() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  shift 3
  
  validate_not_empty resource_type "Resource type cannot be empty"
  validate_not_empty resource_name "Resource name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  if [[ $# -eq 0 ]]; then
    log_error "No labels provided"
    return 1
  fi
  
  local dry_run="${DRY_RUN:-false}"
  
  log_info "Updating labels on ${resource_type}/${resource_name}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would update labels:"
    for label in "$@"; do
      log_dry_run "  $label"
    done
    return 0
  fi
  
  # Apply labels
  if ! execute_kubectl label "$resource_type" "$resource_name" -n "$namespace" "$@" --overwrite >/dev/null; then
    log_error "Failed to update labels on ${resource_type}/${resource_name}"
    return 1
  fi
  
  log_success "Labels updated on ${resource_type}/${resource_name}"
  return 0
}

# ==============================================================================
# ADVANCED KUBECTL OPERATIONS
# ==============================================================================

# execute_kubectl_with_retry
# Executes a kubectl command with retry logic
#
# This wraps execute_kubectl with retry_command from forge-core.sh
#
# Arguments:
#   $1 - max_attempts: Maximum number of retry attempts
#   $2 - delay_seconds: Delay between retries (in seconds)
#   $@ - kubectl command arguments
#
# Returns:
#   0 - Success
#   1 - All retries failed
#
# Example:
#   execute_kubectl_with_retry 3 5 get pods -n default
#
execute_kubectl_with_retry() {
  local max_attempts="$1"
  local delay_seconds="$2"
  shift 2
  
  validate_not_empty max_attempts "Max attempts cannot be empty"
  validate_not_empty delay_seconds "Delay seconds cannot be empty"
  
  log_debug "Executing kubectl with retry (max: $max_attempts, delay: ${delay_seconds}s)"
  
  retry_command "$max_attempts" "$delay_seconds" execute_kubectl "$@"
}

# wait_for_resource_condition
# Waits for a Kubernetes resource to reach a specific condition
#
# This is a generic version of wait_for_pod_ready that works with any resource.
#
# Arguments:
#   $1 - resource_type: Type of resource (e.g., "pod", "deployment")
#   $2 - resource_name: Name of the resource
#   $3 - namespace: Kubernetes namespace
#   $4 - condition: Condition to wait for (e.g., "Ready", "Available")
#   $5 - timeout_seconds: Timeout in seconds (default: 300)
#
# Returns:
#   0 - Condition met
#   1 - Timeout or error
#
# Example:
#   wait_for_resource_condition "deployment" "my-app" "default" "Available" 300
#   wait_for_resource_condition "pod" "my-pod" "default" "Ready" 60
#
wait_for_resource_condition() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  local condition="$4"
  local timeout_seconds="${5:-300}"
  
  validate_not_empty resource_type "Resource type cannot be empty"
  validate_not_empty resource_name "Resource name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  validate_not_empty condition "Condition cannot be empty"
  
  log_info "Waiting for ${resource_type}/${resource_name} to be ${condition} (timeout: ${timeout_seconds}s)"
  
  local start_time
  start_time=$(get_timestamp)
  
  while true; do
    # Check if condition is met
    if execute_kubectl wait --for=condition="${condition}" \
      "${resource_type}/${resource_name}" \
      -n "$namespace" \
      --timeout=10s &>/dev/null; then
      log_success "${resource_type}/${resource_name} is ${condition}"
      return 0
    fi
    
    # Check timeout
    local current_time
    current_time=$(get_timestamp)
    local elapsed=$((current_time - start_time))
    
    if [[ $elapsed -ge $timeout_seconds ]]; then
      log_error "Timeout waiting for ${resource_type}/${resource_name} to be ${condition}"
      return 1
    fi
    
    log_debug "Still waiting... (${elapsed}s elapsed)"
    sleep 5
  done
}

# ==============================================================================
# SECRET OPERATIONS (CRUD)
# ==============================================================================

# create_k8s_secret
# Creates a Kubernetes Secret
#
# Arguments:
#   $1 - secret_name: Name of the Secret
#   $2 - namespace: Kubernetes namespace
#   $3 - secret_type: Secret type (default: "Opaque")
#   $@ - data entries in "key=value" format
#
# Environment Variables:
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   create_k8s_secret "my-secret" "default" "Opaque" \
#     "username=admin" \
#     "password=secretpass"
#
create_k8s_secret() {
  local secret_name="$1"
  local namespace="$2"
  local secret_type="${3:-Opaque}"
  shift 3
  
  validate_not_empty secret_name "Secret name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  if [[ $# -eq 0 ]]; then
    log_error "No data entries provided"
    return 1
  fi
  
  local dry_run="${DRY_RUN:-false}"
  
  log_info "Creating Secret: $secret_name in namespace $namespace"
  
  # Build kubectl command
  local kubectl_args=(
    "create" "secret" "generic" "$secret_name"
    "-n" "$namespace"
    "--type=$secret_type"
  )
  
  # Add data entries
  for entry in "$@"; do
    if [[ ! "$entry" =~ ^[^=]+= ]]; then
      log_warning "Invalid data format (expected key=value): $entry"
      continue
    fi
    kubectl_args+=("--from-literal=$entry")
  done
  
  if [[ "$dry_run" == "true" ]]; then
    kubectl_args+=("--dry-run=client" "-o" "yaml")
    log_dry_run "Would create Secret:"
    execute_kubectl "${kubectl_args[@]}"
    return 0
  fi
  
  # Create Secret
  if ! execute_kubectl "${kubectl_args[@]}" >/dev/null; then
    log_error "Failed to create Secret: $secret_name"
    return 1
  fi
  
  log_success "Secret created: $secret_name"
  return 0
}

# update_k8s_secret
# Updates a Kubernetes Secret (replaces entirely)
#
# Arguments:
#   $1 - secret_name: Name of the Secret
#   $2 - namespace: Kubernetes namespace
#   $3 - secret_type: Secret type
#   $@ - data entries in "key=value" format
#
# Returns:
#   0 - Success
#   1 - Error
#
update_k8s_secret() {
  local secret_name="$1"
  local namespace="$2"
  local secret_type="${3:-Opaque}"
  shift 3
  
  validate_not_empty secret_name "Secret name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  # Check if Secret exists
  if ! check_secret_exists "$secret_name" "$namespace"; then
    log_error "Secret does not exist: $secret_name"
    return 1
  fi
  
  local dry_run="${DRY_RUN:-false}"
  
  log_info "Updating Secret: $secret_name in namespace $namespace"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would delete Secret: $secret_name"
    log_dry_run "Would recreate Secret with new data"
    return 0
  fi
  
  # Delete existing
  execute_kubectl delete secret "$secret_name" -n "$namespace" >/dev/null
  
  # Recreate with new data
  create_k8s_secret "$secret_name" "$namespace" "$secret_type" "$@"
}

# delete_k8s_secret
# Deletes a Kubernetes Secret
#
# Arguments:
#   $1 - secret_name: Name of the Secret
#   $2 - namespace: Kubernetes namespace
#
# Returns:
#   0 - Success
#   1 - Error
#
delete_k8s_secret() {
  local secret_name="$1"
  local namespace="$2"
  
  validate_not_empty secret_name "Secret name cannot be empty"
  validate_not_empty namespace "Namespace cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would delete Secret: $secret_name"
    return 0
  fi
  
  log_info "Deleting Secret: $secret_name in namespace $namespace"
  
  if ! execute_kubectl delete secret "$secret_name" -n "$namespace" >/dev/null; then
    log_error "Failed to delete Secret: $secret_name"
    return 1
  fi
  
  log_success "Secret deleted: $secret_name"
  return 0
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

# Port Forward Operations
export -f setup_port_forward_generic
export -f cleanup_port_forward_generic
export -f check_port_forward_running

# ConfigMap Operations
export -f create_configmap
export -f update_configmap
export -f delete_configmap
export -f get_configmap_data

# Label Management
export -f apply_forge_labels_to_resource
export -f get_resource_labels
export -f update_resource_labels

# Advanced kubectl Operations
export -f execute_kubectl_with_retry
export -f wait_for_resource_condition

# Secret Operations
export -f create_k8s_secret
export -f update_k8s_secret
export -f delete_k8s_secret

log_debug "forge-k8s-operations.sh loaded (v${FORGE_K8S_OPERATIONS_VERSION})"
