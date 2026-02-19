#!/usr/bin/env bash
# ==============================================================================
# Forge KMS Operations Library
# ==============================================================================
# Description: AWS KMS key management operations
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - KMS key creation with automatic alias assignment
# - KMS key deletion (schedule deletion with waiting period)
# - KMS key listing and discovery
# - Key policy management
# - Automatic IRSA/local AWS credential detection
# - Dry-run support for safe operations
#
# Key Naming Convention:
#   alias/{customer}/{project}/{environment}/{service}/{purpose}
#
# Example:
#   alias/customer/project/dev/application/encryption
#
# Usage:
#   source /path/to/forge-kms-operations.sh
#   create_kms_key "customer" "project" "dev" "test-service" "encryption" "false"
#   delete_kms_key "customer" "project" "dev" "test-service" "encryption" "7" "false"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_KMS_OPERATIONS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_KMS_OPERATIONS_VERSION="1.0.0"
readonly FORGE_KMS_OPERATIONS_LOADED="true"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Get script directory
FORGE_KMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -f "${FORGE_KMS_DIR}/forge-core.sh" ]]; then
  source "${FORGE_KMS_DIR}/forge-core.sh"
else
  echo "ERROR: forge-core.sh not found. Cannot continue." >&2
  exit 1
fi

if [[ -f "${FORGE_KMS_DIR}/forge-patterns.sh" ]]; then
  source "${FORGE_KMS_DIR}/forge-patterns.sh"
else
  log_error "forge-patterns.sh not found. Cannot continue."
  exit 1
fi

if [[ -f "${FORGE_KMS_DIR}/forge-aws-discovery.sh" ]]; then
  source "${FORGE_KMS_DIR}/forge-aws-discovery.sh"
else
  log_error "forge-aws-discovery.sh not found. Cannot continue."
  exit 1
fi

# Validate required commands
validate_required_commands aws jq

# ==============================================================================
# KMS KEY OPERATIONS
# ==============================================================================

# create_kms_key
# Creates a KMS key with alias following Forge naming convention
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose (e.g., "encryption", "signing", "data", "secrets")
#   $6 - Dry run (true/false)
#
# Output:
#   Key ID to stdout on success
#   Error message to stderr on failure
#
# Returns:
#   0 on success, 1 on failure
#
# Example:
#   key_id=$(create_kms_key "customer" "project" "dev" "application" "encryption" "false")
#
create_kms_key() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  local dry_run="${6:-false}"
  
  log_step "Creating KMS key"
  
  # Validate required parameters
  validate_required_vars customer project environment service_name purpose
  
  # Build alias and description
  local alias_name
  alias_name=$(get_kms_key_alias_path "$customer" "$project" "$environment" "$service_name" "$purpose")
  
  local description
  description=$(get_kms_key_description "$customer" "$project" "$environment" "$service_name" "$purpose")
  
  local tags
  tags=$(get_kms_key_tags "$customer" "$project" "$environment" "$service_name" "$purpose")
  
  log_info "Key alias: $alias_name"
  log_info "Description: $description"
  
  # Check if key already exists
  if key_exists "$customer" "$project" "$environment" "$service_name" "$purpose"; then
    log_warning "KMS key already exists with alias: $alias_name"
    
    # Get existing key ID
    local existing_key_id
    existing_key_id=$(get_key_id_by_alias "$alias_name")
    
    if [[ -n "$existing_key_id" ]]; then
      log_info "Existing key ID: $existing_key_id"
      echo "$existing_key_id"
      return 0
    else
      log_error "Failed to retrieve existing key ID"
      return 1
    fi
  fi
  
  if [[ "$dry_run" == "true" ]]; then
    log_warning "DRY-RUN: Would create KMS key with alias: $alias_name"
    echo "dry-run-key-id-placeholder"
    return 0
  fi
  
  # Get AWS region and account ID
  # Get AWS region and account ID
  local region
  region=$(get_aws_region)
  
  local account_id
  account_id=$(get_aws_account_id)
  
  local irsa_role_name
  irsa_role_name=$(get_irsa_role_name "$customer" "$project" "$environment" "$service_name")
  
  log_info "Creating KMS key in region: $region"
  log_debug "IRSA role: $irsa_role_name"
  
  # Convert tags to AWS KMS CLI format (uses TagKey/TagValue, not Key/Value)
  local tag_args=()
  for tag in $tags; do
    local key="${tag%%=*}"
    local value="${tag#*=}"
    tag_args+=("TagKey=${key},TagValue=${value}")
  done
  
  # Generate KMS key policy (always enabled)
  local policy_json
  policy_json=$(get_kms_key_policy "$account_id" "$customer" "$project" "$environment" "$service_name" "$region")
  
  log_debug "Generated KMS key policy with root and IRSA access"
  
  # Create KMS key with policy
  local key_id
  if ! key_id=$(aws kms create-key \
    --description "$description" \
    --key-usage ENCRYPT_DECRYPT \
    --origin AWS_KMS \
    --policy "$policy_json" \
    --tags "${tag_args[@]}" \
    --region "$region" \
    --query 'KeyMetadata.KeyId' \
    --output text 2>&1); then
    log_error "Failed to create KMS key: $key_id"
    return 1
  fi
  log_success "Created KMS key: $key_id"
  
  # Create alias
  log_info "Creating alias: $alias_name"
  
  if ! aws kms create-alias \
    --alias-name "$alias_name" \
    --target-key-id "$key_id" \
    --region "$region" 2>&1; then
    log_error "Failed to create alias for key: $key_id"
    log_warning "Key created but alias assignment failed. You may need to manually create the alias."
    echo "$key_id"
    return 1
  fi
  
  log_success "Created alias: $alias_name → $key_id"
  
  echo "$key_id"
  return 0
}

# delete_kms_key
# Schedules a KMS key for deletion (AWS requires waiting period)
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose
#   $6 - Pending window in days (7-30, default: 30)
#   $7 - Dry run (true/false)
#
# Output:
#   Deletion date to stdout on success
#   Error message to stderr on failure
#
# Returns:
#   0 on success, 1 on failure
#
# Example:
#   delete_kms_key "customer" "project" "dev" "application" "encryption" "7" "false"
#
delete_kms_key() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  local pending_window_days="${6:-30}"
  local dry_run="${7:-false}"
  
  log_step "Scheduling KMS key deletion"
  
  # Validate required parameters
  validate_required_vars customer project environment service_name purpose
  
  # Validate pending window
  if [[ "$pending_window_days" -lt 7 ]] || [[ "$pending_window_days" -gt 30 ]]; then
    log_error "Pending window must be between 7 and 30 days (got: $pending_window_days)"
    return 1
  fi
  
  # Build alias
  local alias_name
  alias_name=$(get_kms_key_alias_path "$customer" "$project" "$environment" "$service_name" "$purpose")
  
  log_info "Key alias: $alias_name"
  
  # Check if key exists
  if ! key_exists "$customer" "$project" "$environment" "$service_name" "$purpose"; then
    log_error "KMS key does not exist with alias: $alias_name"
    return 1
  fi
  
  # Get key ID
  local key_id
  key_id=$(get_key_id_by_alias "$alias_name")
  
  if [[ -z "$key_id" ]]; then
    log_error "Failed to retrieve key ID for alias: $alias_name"
    return 1
  fi
  
  log_info "Key ID: $key_id"
  
  if [[ "$dry_run" == "true" ]]; then
    log_warning "DRY-RUN: Would schedule key $key_id for deletion (pending window: $pending_window_days days)"
    echo "dry-run-deletion-scheduled"
    return 0
  fi
  
  # Get AWS region
  local region
  region=$(get_aws_region)
  
  # Delete alias first
  log_info "Deleting alias: $alias_name"
  
  if ! aws kms delete-alias \
    --alias-name "$alias_name" \
    --region "$region" 2>&1; then
    log_warning "Failed to delete alias (may not exist or already deleted)"
  else
    log_success "Deleted alias: $alias_name"
  fi
  
  # Schedule key deletion
  log_info "Scheduling key deletion (pending window: $pending_window_days days)"
  
  local deletion_date
  if ! deletion_date=$(aws kms schedule-key-deletion \
    --key-id "$key_id" \
    --pending-window-in-days "$pending_window_days" \
    --region "$region" \
    --query 'DeletionDate' \
    --output text 2>&1); then
    log_error "Failed to schedule key deletion: $deletion_date"
    return 1
  fi
  
  log_success "Scheduled key deletion: $key_id"
  log_info "Deletion date: $deletion_date"
  log_warning "Key will be permanently deleted after $pending_window_days days"
  log_info "You can cancel deletion with: aws kms cancel-key-deletion --key-id $key_id"
  
  echo "$deletion_date"
  return 0
}

# key_exists
# Checks if a KMS key exists with the given alias
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose
#
# Returns:
#   0 if exists, 1 if not
#
# Example:
#   if key_exists "customer" "project" "dev" "application" "encryption"; then
#     echo "Key exists"
#   fi
#
key_exists() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  
  local alias_name
  alias_name=$(get_kms_key_alias_path "$customer" "$project" "$environment" "$service_name" "$purpose")
  
  # Use discovery function from forge-aws-discovery.sh
  kms_key_exists "$alias_name"
}

# get_key_id_by_alias
# Retrieves KMS key ID for a given alias
#
# Arguments:
#   $1 - Alias name (e.g., alias/customer/project/dev/application/encryption)
#
# Output:
#   Key ID to stdout
#
# Returns:
#   0 on success, 1 on failure
#
# Example:
#   key_id=$(get_key_id_by_alias "alias/customer/project/dev/application/encryption")
#
get_key_id_by_alias() {
  local alias_name="$1"
  
  # Use discovery function from forge-aws-discovery.sh
  discover_kms_key_by_alias "$alias_name"
}

# list_kms_keys
# Lists all KMS keys for a service
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   JSON array of key information
#
# Example:
#   list_kms_keys "customer" "project" "dev" "application"
#
list_kms_keys() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  # Use discovery function from forge-aws-discovery.sh
  list_kms_keys_by_service "$customer" "$project" "$environment" "$service_name"
}

# get_key_info
# Retrieves detailed information about a KMS key
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose
#
# Output:
#   JSON object with key metadata
#
# Example:
#   get_key_info "customer" "project" "dev" "application" "encryption"
#
get_key_info() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  
  local alias_name
  alias_name=$(get_kms_key_alias_path "$customer" "$project" "$environment" "$service_name" "$purpose")
  
  # Use discovery function from forge-aws-discovery.sh
  get_kms_key_metadata "$alias_name"
}

# ==============================================================================
# EXPORTS
# ==============================================================================

export -f create_kms_key delete_kms_key key_exists get_key_id_by_alias
export -f list_kms_keys get_key_info

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "forge-kms-operations.sh loaded (v${FORGE_KMS_OPERATIONS_VERSION})"
