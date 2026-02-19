#!/usr/bin/env bash
# ==============================================================================
# Forge Vault Operations Library
# ==============================================================================
# Description: Vault policy, role, and secret management operations
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - Extended secret operations (delete, list, exists, bulk)
# - Policy management (CRUD operations)
# - Role management (CRUD operations with policy binding)
# - Kubernetes auth backend configuration
# - Path and permission management
# - Bulk sync operations (SSM→Vault, YAML→Vault)
# - Orphan detection and cleanup
# - Dual execution mode support (in-cluster / local)
#
# Dependencies:
#   - forge-core.sh (logging, validation, execution mode)
#   - forge-patterns.sh (naming conventions)
#   - forge-aws-discovery.sh (SSM operations)
#   - forge-vault-discovery.sh (connection, auth, basic CRUD)
#
# Usage:
#   source /path/to/forge-vault-operations.sh
#   delete_vault_secret "secret/data/customer/project/dev/service/app"
#   create_vault_policy "my-policy" "path \"secret/data/*\" { capabilities = [\"read\"] }"
#   create_vault_role "my-role" "my-namespace" "my-service-account" "my-policy" "24h"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_VAULT_OPERATIONS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_VAULT_OPERATIONS_VERSION="1.0.0"
readonly FORGE_VAULT_OPERATIONS_LOADED="true"

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
source "${LIB_DIR}/forge-aws-discovery.sh"
source "${LIB_DIR}/forge-vault-discovery.sh"

# Validate required commands
validate_required_commands vault jq

# ==============================================================================
# EXTENDED SECRET OPERATIONS
# ==============================================================================

# delete_vault_secret
# Deletes a secret from Vault KV v2 storage
#
# This function removes both the secret data and its metadata. For KV v2,
# this performs a soft delete - versions can still be recovered unless
# you also call destroy_vault_secret_versions.
#
# Arguments:
#   $1 - secret_path: Full path to secret (can be metadata or data path)
#        Examples: 
#          - secret/data/customer/project/dev/application/app
#          - secret/customer/project/dev/application/app (will be converted)
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Validation error
#   2 - Vault API error
#
# Output:
#   Logs deletion status to stderr
#
# Example:
#   delete_vault_secret "secret/data/customer/project/dev/application/app"
#   delete_vault_secret "secret/customer/project/dev/application/app"
#
delete_vault_secret() {
  local secret_path="$1"
  
  # Validate inputs
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty secret_path "Secret path cannot be empty"
  
  # Convert to metadata path (KV v2 delete uses metadata endpoint)
  local metadata_path
  if [[ "$secret_path" =~ ^secret/data/ ]]; then
    metadata_path="${secret_path/\/data\//\/metadata\/}"
  elif [[ "$secret_path" =~ ^secret/metadata/ ]]; then
    metadata_path="$secret_path"
  else
    # Assume it's a base path without /data/ or /metadata/
    metadata_path="secret/metadata/${secret_path#secret/}"
  fi
  
  log_info "Deleting secret: $metadata_path"
  
  # Delete the secret (soft delete in KV v2)
  if ! vault kv metadata delete "$metadata_path" 2>&1 | grep -q "Success"; then
    log_error "Failed to delete secret: $metadata_path"
    return 2
  fi
  
  log_success "Secret deleted: $metadata_path"
  return 0
}

# list_vault_secrets
# Lists all secrets under a given path, optionally recursively
#
# For KV v2, this uses the metadata endpoint to list all secrets.
# Can list recursively to get all nested paths.
#
# Arguments:
#   $1 - base_path: Base path to list from
#        Example: secret/customer/project/dev
#   $2 - recursive: "true" or "false" (default: "false")
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Validation error
#   2 - Vault API error
#
# Output:
#   List of secret paths to stdout (one per line)
#
# Example:
#   list_vault_secrets "secret/customer/project/dev" "false"
#   # Output:
#   # secret/customer/project/dev/application/app
#   # secret/customer/project/dev/application/livekit
#
#   list_vault_secrets "secret/customer/project" "true"
#   # Recursively lists all secrets under customer/project/*
#
list_vault_secrets() {
  local base_path="$1"
  local recursive="${2:-false}"
  
  # Validate inputs
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty base_path "Base path cannot be empty"
  
  # vault kv list automatically handles the metadata path conversion
  # Just strip 'secret/data/' or 'secret/metadata/' prefix if present and use clean path
  local clean_path="$base_path"
  if [[ "$base_path" =~ ^secret/data/ ]]; then
    clean_path="${base_path#secret/data/}"
    clean_path="secret/${clean_path}"
  elif [[ "$base_path" =~ ^secret/metadata/ ]]; then
    clean_path="${base_path#secret/metadata/}"
    clean_path="secret/${clean_path}"
  fi
  
  log_debug "Listing secrets at: $clean_path (recursive: $recursive)"
  
  # List secrets using vault kv list
  local secrets_json
  if ! secrets_json=$(vault kv list -format=json "$clean_path" 2>/dev/null); then
    # Path might not exist or no secrets
    log_debug "No secrets found at: $clean_path"
    return 0
  fi
  
  # Parse JSON array and output paths
  local secrets
  secrets=$(echo "$secrets_json" | jq -r '.[]')
  
  while IFS= read -r secret; do
    [[ -z "$secret" ]] && continue
    
    local full_path="${base_path}/${secret}"
    
    # If it's a folder (ends with /) and recursive is enabled, recurse
    if [[ "$secret" =~ /$ ]] && [[ "$recursive" == "true" ]]; then
      list_vault_secrets "${full_path%/}" "true"
    else
      # It's a secret file, output it
      echo "${full_path%/}"  # Remove trailing slash if present
    fi
  done <<< "$secrets"
  
  return 0
}

# check_vault_secret_exists
# Checks if a secret exists in Vault
#
# This function checks the metadata endpoint to verify secret existence
# without reading the actual secret data.
#
# Arguments:
#   $1 - secret_path: Path to check
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Secret exists
#   1 - Secret does not exist or error
#
# Output:
#   None (silent check)
#
# Example:
#   if check_vault_secret_exists "secret/customer/project/dev/application/app"; then
#     echo "Secret exists"
#   fi
#
check_vault_secret_exists() {
  local secret_path="$1"
  
  # Validate inputs
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty secret_path "Secret path cannot be empty"
  
  # Convert to metadata path
  local metadata_path
  if [[ "$secret_path" =~ ^secret/data/ ]]; then
    metadata_path="${secret_path/\/data\//\/metadata\/}"
  elif [[ "$secret_path" =~ ^secret/metadata/ ]]; then
    metadata_path="$secret_path"
  else
    metadata_path="secret/metadata/${secret_path#secret/}"
  fi
  
  # Check if secret exists
  if vault kv metadata get "$metadata_path" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

# get_vault_secret_metadata
# Retrieves metadata for a secret (version info, created time, etc.)
#
# Arguments:
#   $1 - secret_path: Path to secret
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   JSON metadata to stdout
#
# Example:
#   metadata=$(get_vault_secret_metadata "secret/customer/project/dev/application/app")
#   echo "$metadata" | jq '.current_version'
#
get_vault_secret_metadata() {
  local secret_path="$1"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty secret_path "Secret path cannot be empty"
  
  # Convert to metadata path
  local metadata_path
  if [[ "$secret_path" =~ ^secret/data/ ]]; then
    metadata_path="${secret_path/\/data\//\/metadata\/}"
  elif [[ "$secret_path" =~ ^secret/metadata/ ]]; then
    metadata_path="$secret_path"
  else
    metadata_path="secret/metadata/${secret_path#secret/}"
  fi
  
  vault kv metadata get -format=json "$metadata_path"
}

# bulk_write_vault_secrets
# Writes multiple secrets to Vault from a key=value array
#
# Arguments:
#   $1 - base_path: Base path for all secrets
#   $@ - key=value pairs (format: "section/key=value")
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   bulk_write_vault_secrets "secret/customer/project/dev/application" \
#     "app/PORT=3000" \
#     "app/HOST=0.0.0.0" \
#     "livekit/API_KEY=abc123"
#
bulk_write_vault_secrets() {
  local base_path="$1"
  shift
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty base_path "Base path cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  local success_count=0
  local error_count=0
  
  # Group secrets by section
  declare -A secrets_by_section
  
  for kv_pair in "$@"; do
    if [[ ! "$kv_pair" =~ ^([^/]+)/([^=]+)=(.*)$ ]]; then
      log_warning "Invalid format (expected section/key=value): $kv_pair"
      ((error_count++))
      continue
    fi
    
    local section="${BASH_REMATCH[1]}"
    local key="${BASH_REMATCH[2]}"
    local value="${BASH_REMATCH[3]}"
    
    # Append to section's secrets
    if [[ -z "${secrets_by_section[$section]:-}" ]]; then
      secrets_by_section[$section]="$key=$value"
    else
      secrets_by_section[$section]="${secrets_by_section[$section]} $key=$value"
    fi
  done
  
  # Write each section
  for section in "${!secrets_by_section[@]}"; do
    local secret_path="${base_path}/${section}"
    local kv_args="${secrets_by_section[$section]}"
    
    if [[ "$dry_run" == "true" ]]; then
      log_dry_run "Would write to $secret_path: $kv_args"
      ((success_count++))
    else
      log_info "Writing to $secret_path"
      # shellcheck disable=SC2086
      if write_vault_secret "$secret_path" $kv_args; then
        ((success_count++))
      else
        ((error_count++))
      fi
    fi
  done
  
  log_info "Bulk write complete: $success_count succeeded, $error_count failed"
  
  [[ $error_count -eq 0 ]] && return 0 || return 1
}

# bulk_delete_vault_secrets
# Deletes multiple secrets from Vault
#
# Arguments:
#   $@ - Array of secret paths to delete
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - All deletions successful
#   1 - One or more deletions failed
#
# Example:
#   bulk_delete_vault_secrets \
#     "secret/customer/project/dev/application/app" \
#     "secret/customer/project/dev/application/livekit"
#
bulk_delete_vault_secrets() {
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  
  local dry_run="${DRY_RUN:-false}"
  local success_count=0
  local error_count=0
  
  for secret_path in "$@"; do
    if [[ "$dry_run" == "true" ]]; then
      log_dry_run "Would delete: $secret_path"
      ((success_count++))
    else
      if delete_vault_secret "$secret_path"; then
        ((success_count++))
      else
        ((error_count++))
      fi
    fi
  done
  
  log_info "Bulk delete complete: $success_count succeeded, $error_count failed"
  
  [[ $error_count -eq 0 ]] && return 0 || return 1
}

# ==============================================================================
# POLICY OPERATIONS
# ==============================================================================

# create_vault_policy
# Creates or updates a Vault policy
#
# Arguments:
#   $1 - policy_name: Name of the policy
#   $2 - policy_hcl: Policy content in HCL format
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required with sufficient permissions)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Validation error
#   2 - Vault API error
#
# Example:
#   policy_hcl='path "secret/data/customer/project/dev/*" {
#     capabilities = ["create", "read", "update", "delete", "list"]
#   }'
#   create_vault_policy "customer-project-dev-application-policy" "$policy_hcl"
#
#   # Or using forge-patterns naming:
#   policy_name=$(get_vault_policy_name "customer" "project" "dev" "application")
#   create_vault_policy "$policy_name" "$policy_hcl"
#
create_vault_policy() {
  local policy_name="$1"
  local policy_hcl="$2"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty policy_name "Policy name cannot be empty"
  validate_not_empty policy_hcl "Policy HCL cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would create policy: $policy_name"
    log_dry_run "Policy content:"
    echo "$policy_hcl" | sed 's/^/  /' >&2
    return 0
  fi
  
  log_info "Creating Vault policy: $policy_name"
  
  # Write policy using vault CLI
  if ! echo "$policy_hcl" | vault policy write "$policy_name" - &>/dev/null; then
    log_error "Failed to create policy: $policy_name"
    return 2
  fi
  
  log_success "Policy created: $policy_name"
  return 0
}

# update_vault_policy
# Updates an existing Vault policy (alias for create_vault_policy)
#
# In Vault, creating and updating policies use the same endpoint.
# This is just an alias for clarity.
#
# Arguments:
#   $1 - policy_name: Name of the policy
#   $2 - policy_hcl: New policy content in HCL format
#
# Returns:
#   Same as create_vault_policy
#
update_vault_policy() {
  create_vault_policy "$@"
}

# delete_vault_policy
# Deletes a Vault policy
#
# Arguments:
#   $1 - policy_name: Name of the policy to delete
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Validation error
#   2 - Vault API error
#
# Example:
#   delete_vault_policy "customer-project-dev-application-policy"
#
delete_vault_policy() {
  local policy_name="$1"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty policy_name "Policy name cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would delete policy: $policy_name"
    return 0
  fi
  
  log_info "Deleting Vault policy: $policy_name"
  
  if ! vault policy delete "$policy_name" &>/dev/null; then
    log_error "Failed to delete policy: $policy_name"
    return 2
  fi
  
  log_success "Policy deleted: $policy_name"
  return 0
}

# list_vault_policies
# Lists all Vault policies
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   List of policy names to stdout (one per line)
#
# Example:
#   list_vault_policies
#   # Output:
#   # default
#   # root
#   # customer-project-dev-application-policy
#
list_vault_policies() {
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  
  vault policy list -format=json | jq -r '.[]'
}

# get_vault_policy
# Retrieves the content of a Vault policy
#
# Arguments:
#   $1 - policy_name: Name of the policy
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   Policy content in HCL format to stdout
#
# Example:
#   get_vault_policy "customer-project-dev-application-policy"
#
get_vault_policy() {
  local policy_name="$1"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty policy_name "Policy name cannot be empty"
  
  vault policy read "$policy_name"
}

# generate_vault_policy_hcl
# Generates Vault policy HCL from path and capabilities
#
# This is a helper function to generate policy HCL programmatically.
#
# Arguments:
#   $1 - base_path: Base path for the policy (e.g., "secret/data/customer/project/dev/application")
#   $2 - capabilities: Comma-separated capabilities (e.g., "create,read,update,delete,list")
#
# Returns:
#   0 - Success
#
# Output:
#   Policy HCL to stdout
#
# Example:
#   policy_hcl=$(generate_vault_policy_hcl "secret/data/customer/project/dev/application" "read,list")
#   create_vault_policy "my-policy" "$policy_hcl"
#
generate_vault_policy_hcl() {
  local base_path="$1"
  local capabilities="$2"
  
  validate_not_empty base_path "Base path cannot be empty"
  validate_not_empty capabilities "Capabilities cannot be empty"
  
  # Convert comma-separated to JSON array
  local caps_array
  caps_array=$(echo "$capabilities" | tr ',' '\n' | jq -R . | jq -s .)
  
  cat <<EOF
path "${base_path}/*" {
  capabilities = ${caps_array}
}

path "${base_path}" {
  capabilities = ["list"]
}
EOF
}

# ==============================================================================
# ROLE OPERATIONS
# ==============================================================================

# create_vault_role
# Creates a Vault Kubernetes auth role
#
# Arguments:
#   $1 - role_name: Name of the role
#   $2 - bound_service_account_namespaces: Comma-separated K8s namespaces
#   $3 - bound_service_account_names: Comma-separated K8s ServiceAccount names
#   $4 - policies: Comma-separated Vault policy names
#   $5 - ttl: Token TTL (default: "24h")
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Validation error
#   2 - Vault API error
#
# Example:
#   create_vault_role \
#     "customer-project-dev-application-role" \
#     "customer-project-dev-application-agent" \
#     "customer-project-dev-application-agent-sa" \
#     "customer-project-dev-application-policy" \
#     "24h"
#
#   # Or using forge-patterns:
#   role_name=$(get_vault_role_name "customer" "project" "dev" "application")
#   namespace=$(get_namespace_name "customer" "project" "dev" "application")
#   sa_name=$(get_service_account_name "customer" "project" "dev" "application")
#   policy_name=$(get_vault_policy_name "customer" "project" "dev" "application")
#   create_vault_role "$role_name" "$namespace" "$sa_name" "$policy_name" "24h"
#
create_vault_role() {
  local role_name="$1"
  local bound_sa_namespaces="$2"
  local bound_sa_names="$3"
  local policies="$4"
  local ttl="${5:-24h}"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty role_name "Role name cannot be empty"
  validate_not_empty bound_sa_namespaces "Service account namespaces cannot be empty"
  validate_not_empty bound_sa_names "Service account names cannot be empty"
  validate_not_empty policies "Policies cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would create role: $role_name"
    log_dry_run "  Bound SA Namespaces: $bound_sa_namespaces"
    log_dry_run "  Bound SA Names: $bound_sa_names"
    log_dry_run "  Policies: $policies"
    log_dry_run "  TTL: $ttl"
    return 0
  fi
  
  log_info "Creating Vault role: $role_name"
  
  # Create role using vault CLI
  if ! vault write "auth/kubernetes/role/${role_name}" \
    bound_service_account_names="$bound_sa_names" \
    bound_service_account_namespaces="$bound_sa_namespaces" \
    policies="$policies" \
    ttl="$ttl" &>/dev/null; then
    log_error "Failed to create role: $role_name"
    return 2
  fi
  
  log_success "Role created: $role_name"
  return 0
}

# update_vault_role
# Updates an existing Vault role (alias for create_vault_role)
#
update_vault_role() {
  create_vault_role "$@"
}

# delete_vault_role
# Deletes a Vault role
#
# Arguments:
#   $1 - role_name: Name of the role to delete
#   $2 - auth_backend: Auth backend path (default: "kubernetes")
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   delete_vault_role "customer-project-dev-application-role"
#
delete_vault_role() {
  local role_name="$1"
  local auth_backend="${2:-kubernetes}"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty role_name "Role name cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would delete role: $role_name"
    return 0
  fi
  
  log_info "Deleting Vault role: $role_name"
  
  if ! vault delete "auth/${auth_backend}/role/${role_name}" &>/dev/null; then
    log_error "Failed to delete role: $role_name"
    return 2
  fi
  
  log_success "Role deleted: $role_name"
  return 0
}

# list_vault_roles
# Lists all roles for a given auth backend
#
# Arguments:
#   $1 - auth_backend: Auth backend path (default: "kubernetes")
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   List of role names to stdout (one per line)
#
# Example:
#   list_vault_roles "kubernetes"
#
list_vault_roles() {
  local auth_backend="${1:-kubernetes}"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  
  vault list -format=json "auth/${auth_backend}/role" | jq -r '.[]'
}

# get_vault_role
# Retrieves configuration of a Vault role
#
# Arguments:
#   $1 - role_name: Name of the role
#   $2 - auth_backend: Auth backend path (default: "kubernetes")
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   Role configuration in JSON format to stdout
#
# Example:
#   get_vault_role "customer-project-dev-application-role"
#
get_vault_role() {
  local role_name="$1"
  local auth_backend="${2:-kubernetes}"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty role_name "Role name cannot be empty"
  
  vault read -format=json "auth/${auth_backend}/role/${role_name}"
}

# ==============================================================================
# KUBERNETES AUTH BACKEND CONFIGURATION
# ==============================================================================

# configure_k8s_auth_backend
# Configures Vault Kubernetes auth backend
#
# This function configures the Kubernetes auth backend with cluster information.
# It auto-detects execution mode and uses appropriate configuration.
#
# Arguments:
#   None (auto-detects configuration from environment)
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   KUBERNETES_SERVICE_HOST - K8s API host (auto-detected in-cluster)
#   KUBERNETES_SERVICE_PORT - K8s API port (auto-detected in-cluster)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   configure_k8s_auth_backend
#
configure_k8s_auth_backend() {
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  
  local dry_run="${DRY_RUN:-false}"
  local execution_mode
  execution_mode=$(get_execution_mode)
  
  log_info "Configuring Kubernetes auth backend (mode: $execution_mode)"
  
  local k8s_host
  local k8s_ca_cert
  local token_reviewer_jwt
  
  if [[ "$execution_mode" == "in-cluster" ]]; then
    # In-cluster: use service account token
    k8s_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
    k8s_ca_cert=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
    token_reviewer_jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  else
    # Local: use kubeconfig
    k8s_host=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    k8s_ca_cert=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)
    
    # Create a service account token for token review
    # Note: This requires a SA with proper RBAC
    local sa_token
    sa_token=$(kubectl create token vault-auth-delegator --duration=8760h 2>/dev/null || \
               kubectl get secret vault-auth-delegator-token -o jsonpath='{.data.token}' | base64 -d)
    token_reviewer_jwt="$sa_token"
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would configure K8s auth backend:"
    log_dry_run "  K8s Host: $k8s_host"
    log_dry_run "  CA Cert: [${#k8s_ca_cert} bytes]"
    log_dry_run "  Token: [${#token_reviewer_jwt} bytes]"
    return 0
  fi
  
  # Enable auth backend if not already enabled
  if ! vault auth list | grep -q "^kubernetes/"; then
    log_info "Enabling Kubernetes auth backend"
    vault auth enable kubernetes
  fi
  
  # Configure the backend
  if ! vault write auth/kubernetes/config \
    kubernetes_host="$k8s_host" \
    kubernetes_ca_cert="$k8s_ca_cert" \
    token_reviewer_jwt="$token_reviewer_jwt" &>/dev/null; then
    log_error "Failed to configure Kubernetes auth backend"
    return 2
  fi
  
  log_success "Kubernetes auth backend configured"
  return 0
}

# enable_k8s_auth_backend
# Enables the Kubernetes auth backend
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
enable_k8s_auth_backend() {
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  
  log_info "Enabling Kubernetes auth backend"
  
  if vault auth list | grep -q "^kubernetes/"; then
    log_warning "Kubernetes auth backend already enabled"
    return 0
  fi
  
  if ! vault auth enable kubernetes; then
    log_error "Failed to enable Kubernetes auth backend"
    return 2
  fi
  
  log_success "Kubernetes auth backend enabled"
  return 0
}

# ==============================================================================
# BULK SYNC OPERATIONS
# ==============================================================================

# discover_ssm_sections
# Discovers all unique sections in AWS SSM Parameter Store
#
# Arguments:
#   $1 - ssm_prefix: SSM parameter path prefix
#        Example: /customer/project/dev/application
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   List of section names to stdout (one per line)
#
# Example:
#   discover_ssm_sections "/customer/project/dev/application"
#   # Output:
#   # app
#   # livekit
#   # database
#
discover_ssm_sections() {
  local ssm_prefix="$1"
  
  validate_not_empty ssm_prefix "SSM prefix cannot be empty"
  validate_required_commands aws
  
  log_debug "Discovering SSM sections under: $ssm_prefix"
  
  # List all parameters under prefix
  local parameters
  parameters=$(aws ssm get-parameters-by-path \
    --path "$ssm_prefix" \
    --recursive \
    --query 'Parameters[].Name' \
    --output text)
  
  # Extract unique sections (part after prefix, before last /)
  echo "$parameters" | tr '\t' '\n' | while read -r param; do
    # Remove prefix
    local relative_path="${param#$ssm_prefix/}"
    # Extract section (everything before last /)
    local section="${relative_path%/*}"
    echo "$section"
  done | sort -u
}

# sync_ssm_section_to_vault
# Syncs one section from AWS SSM to Vault
#
# Arguments:
#   $1 - ssm_prefix: SSM parameter path prefix
#   $2 - vault_path: Vault secret base path
#   $3 - section: Section name to sync
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#   DRY_RUN - If "true", only preview changes (default: "false")
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   sync_ssm_section_to_vault \
#     "/customer/project/dev/application" \
#     "secret/customer/project/dev/application" \
#     "app"
#
sync_ssm_section_to_vault() {
  local ssm_prefix="$1"
  local vault_path="$2"
  local section="$3"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty ssm_prefix "SSM prefix cannot be empty"
  validate_not_empty vault_path "Vault path cannot be empty"
  validate_not_empty section "Section cannot be empty"
  
  local dry_run="${DRY_RUN:-false}"
  local section_ssm_path="${ssm_prefix}/${section}"
  local section_vault_path="${vault_path}/${section}"
  
  log_info "Syncing section '$section' from SSM to Vault"
  log_debug "  SSM path: $section_ssm_path"
  log_debug "  Vault path: $section_vault_path"
  
  # Get all parameters for this section
  local parameters
  parameters=$(aws ssm get-parameters-by-path \
    --path "$section_ssm_path" \
    --with-decryption \
    --query 'Parameters[].[Name,Value]' \
    --output json)
  
  # Build key=value pairs
  local kv_args=()
  while IFS= read -r param; do
    local name value
    name=$(echo "$param" | jq -r '.[0]')
    value=$(echo "$param" | jq -r '.[1]')
    
    # Extract key (last part of SSM path)
    local key="${name##*/}"
    
    kv_args+=("${key}=${value}")
  done < <(echo "$parameters" | jq -c '.[]')
  
  if [[ ${#kv_args[@]} -eq 0 ]]; then
    log_warning "No parameters found in section: $section"
    return 0
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    log_dry_run "Would sync ${#kv_args[@]} parameters to $section_vault_path"
    for kv in "${kv_args[@]}"; do
      log_dry_run "  $kv"
    done
    return 0
  fi
  
  # Write to Vault
  log_info "Writing ${#kv_args[@]} parameters to Vault"
  write_vault_secret "$section_vault_path" "${kv_args[@]}"
}

# detect_orphaned_vault_secrets
# Detects Vault secrets that don't exist in SSM
#
# Arguments:
#   $1 - vault_base_path: Base Vault path to check
#   $2 - ssm_prefix: SSM parameter path prefix
#
# Environment Variables:
#   VAULT_ADDR - Vault server address (required)
#   VAULT_TOKEN - Vault authentication token (required)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   List of orphaned secret paths to stdout
#
# Example:
#   orphans=$(detect_orphaned_vault_secrets \
#     "secret/customer/project/dev/application" \
#     "/customer/project/dev/application")
#
detect_orphaned_vault_secrets() {
  local vault_base_path="$1"
  local ssm_prefix="$2"
  
  validate_required_vars VAULT_ADDR VAULT_TOKEN
  validate_not_empty vault_base_path "Vault base path cannot be empty"
  validate_not_empty ssm_prefix "SSM prefix cannot be empty"
  
  log_info "Detecting orphaned secrets"
  log_debug "  Vault path: $vault_base_path"
  log_debug "  SSM prefix: $ssm_prefix"
  
  # Get all Vault secrets
  local vault_secrets
  vault_secrets=$(list_vault_secrets "$vault_base_path" "true")
  
  # Get all SSM parameters
  local ssm_params
  ssm_params=$(aws ssm get-parameters-by-path \
    --path "$ssm_prefix" \
    --recursive \
    --query 'Parameters[].Name' \
    --output text | tr '\t' '\n')
  
  # Compare and find orphans
  local orphans=()
  while IFS= read -r vault_secret; do
    [[ -z "$vault_secret" ]] && continue
    
    # Convert Vault path to expected SSM path
    local relative_path="${vault_secret#$vault_base_path/}"
    local expected_ssm_path="${ssm_prefix}/${relative_path}"
    
    # Check if SSM parameter exists
    if ! echo "$ssm_params" | grep -q "^${expected_ssm_path}$"; then
      orphans+=("$vault_secret")
      echo "$vault_secret"
    fi
  done <<< "$vault_secrets"
  
  log_info "Found ${#orphans[@]} orphaned secrets"
  return 0
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

# Extended Secret Operations
export -f delete_vault_secret
export -f list_vault_secrets
export -f check_vault_secret_exists
export -f get_vault_secret_metadata
export -f bulk_write_vault_secrets
export -f bulk_delete_vault_secrets

# Policy Operations
export -f create_vault_policy
export -f update_vault_policy
export -f delete_vault_policy
export -f list_vault_policies
export -f get_vault_policy
export -f generate_vault_policy_hcl

# Role Operations
export -f create_vault_role
export -f update_vault_role
export -f delete_vault_role
export -f list_vault_roles
export -f get_vault_role

# Kubernetes Auth Backend
export -f configure_k8s_auth_backend
export -f enable_k8s_auth_backend

# Bulk Sync Operations
export -f discover_ssm_sections
export -f sync_ssm_section_to_vault
export -f detect_orphaned_vault_secrets

log_debug "forge-vault-operations.sh loaded (v${FORGE_VAULT_OPERATIONS_VERSION})"
