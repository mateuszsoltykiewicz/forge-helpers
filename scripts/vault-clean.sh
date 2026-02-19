#!/usr/bin/env bash
# ==============================================================================
# Vault Cleanup Script
# ==============================================================================
# Description: Cleans up Vault resources (policies, roles, secrets)
# Version: 1.0.0
# Author: Moai Forge Team
#
# This script removes Vault resources for a service:
# - Vault roles
# - Vault policies
# - Vault secrets (optional)
#
# Usage:
#   ./vault-clean.sh --customer customer --project project --environment dev --service application
#   ./vault-clean.sh --customer customer --project project --environment dev --service application --delete-secrets
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SCRIPT SETUP
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source libraries
source "${LIB_DIR}/forge-core.sh"
source "${LIB_DIR}/forge-patterns.sh"
source "${LIB_DIR}/forge-vault-discovery.sh"
source "${LIB_DIR}/forge-vault-operations.sh"

# ==============================================================================
# CONSTANTS
# ==============================================================================

readonly SCRIPT_NAME="vault-clean.sh"
readonly VERSION="1.0.0"

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""
DRY_RUN="false"
DELETE_SECRETS="false"
FORCE="false"
SKIP_CONFIRMATION="false"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_banner() {
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                      VAULT CLEANUP                               ║
║                  Moai Forge Platform v1.0.0                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

print_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Cleans up Vault resources for a service (roles, policies, secrets).

Required Options:
  --customer CUSTOMER         Customer name (e.g., customer, indegene)
  --project PROJECT           Project name (e.g., project, platform)
  --environment ENV           Environment (e.g., dev, staging, prod)
  --service SERVICE           Service name (e.g., application-agent)

Optional Flags:
  --delete-secrets            Also delete all secrets for this service
  --force                     Skip confirmation prompts
  --dry-run                   Preview changes without executing them
  -h, --help                  Show this help message
  -v, --version               Show version information

Environment Variables:
  VAULT_ADDR                  Vault server address (auto-detected if not set)
  VAULT_TOKEN                 Vault authentication token (from SSM if not set)

Examples:
  # Clean up policies and roles only
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application

  # Clean up everything including secrets
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application --delete-secrets

  # Preview what would be deleted
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application --delete-secrets --dry-run

  # Force deletion without confirmation
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application --delete-secrets --force

EOF
}

print_version() {
  echo "${SCRIPT_NAME} version ${VERSION}"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
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
      --delete-secrets)
        DELETE_SECRETS="true"
        shift
        ;;
      --force)
        FORCE="true"
        SKIP_CONFIRMATION="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        export DRY_RUN
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      -v|--version)
        print_version
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_usage
        exit 2
        ;;
    esac
  done

  # Validate required arguments
  validate_required_vars CUSTOMER PROJECT ENVIRONMENT SERVICE
  validate_forge_pattern_args "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE"
}

confirm_deletion() {
  if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  
  echo ""
  log_warning "⚠️  WARNING: This will delete Vault resources!"
  echo ""
  echo "  Customer:    $CUSTOMER"
  echo "  Project:     $PROJECT"
  echo "  Environment: $ENVIRONMENT"
  echo "  Service:     $SERVICE"
  echo ""
  
  if [[ "$DELETE_SECRETS" == "true" ]]; then
    log_warning "  Secrets will also be DELETED!"
  fi
  
  echo ""
  read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
  echo ""
  
  if [[ "$REPLY" != "yes" ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
  fi
}

# ==============================================================================
# CLEANUP FUNCTIONS
# ==============================================================================

cleanup_role() {
  log_step "Deleting Vault role"
  
  local role_name
  role_name=$(get_vault_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  # Check if role exists
  if ! list_vault_roles 2>/dev/null | grep -q "^${role_name}$"; then
    log_info "Role does not exist: $role_name"
    return 0
  fi
  
  if delete_vault_role "$role_name"; then
    log_success "Role deleted: $role_name"
  else
    log_error "Failed to delete role: $role_name"
    return 1
  fi
}

cleanup_policy() {
  log_step "Deleting Vault policy"
  
  local policy_name
  policy_name=$(get_vault_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  # Check if policy exists
  if ! list_vault_policies | grep -q "^${policy_name}$"; then
    log_info "Policy does not exist: $policy_name"
    return 0
  fi
  
  if delete_vault_policy "$policy_name"; then
    log_success "Policy deleted: $policy_name"
  else
    log_error "Failed to delete policy: $policy_name"
    return 1
  fi
}

cleanup_secrets() {
  if [[ "$DELETE_SECRETS" != "true" ]]; then
    log_info "Skipping secret deletion (use --delete-secrets to enable)"
    return 0
  fi
  
  log_step "Deleting Vault secrets"
  
  local secret_base_path
  secret_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
  
  log_info "Listing secrets under: $secret_base_path"
  
  # List all secrets
  local secrets
  secrets=$(list_vault_secrets "$secret_base_path" "true" 2>/dev/null || echo "")
  
  if [[ -z "$secrets" ]]; then
    log_info "No secrets found to delete"
    return 0
  fi
  
  # Count secrets
  local secret_count
  secret_count=$(echo "$secrets" | wc -l | tr -d ' ')
  
  log_warning "Found $secret_count secrets to delete"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would delete the following secrets:"
    echo "$secrets" | sed 's/^/  /' >&2
    return 0
  fi
  
  # Delete each secret
  local deleted=0
  local failed=0
  
  while IFS= read -r secret_path; do
    [[ -z "$secret_path" ]] && continue
    
    if delete_vault_secret "$secret_path"; then
      ((deleted++))
    else
      ((failed++))
    fi
  done <<< "$secrets"
  
  log_info "Secrets deleted: $deleted, failed: $failed"
  
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
}

verify_cleanup() {
  log_step "Verifying cleanup"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run mode: skipping verification"
    return 0
  fi
  
  local policy_name
  policy_name=$(get_vault_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  local role_name
  role_name=$(get_vault_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  # Check policy deleted
  if list_vault_policies | grep -q "^${policy_name}$"; then
    log_warning "✗ Policy still exists: $policy_name"
  else
    log_success "✓ Policy removed: $policy_name"
  fi
  
  # Check role deleted
  if list_vault_roles 2>/dev/null | grep -q "^${role_name}$"; then
    log_warning "✗ Role still exists: $role_name"
  else
    log_success "✓ Role removed: $role_name"
  fi
  
  # Check secrets deleted
  if [[ "$DELETE_SECRETS" == "true" ]]; then
    local secret_base_path
    secret_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
    
    local remaining_secrets
    remaining_secrets=$(list_vault_secrets "$secret_base_path" "true" 2>/dev/null | wc -l | tr -d ' ')
    
    if [[ "$remaining_secrets" -eq 0 ]]; then
      log_success "✓ All secrets removed"
    else
      log_warning "✗ $remaining_secrets secrets still exist"
    fi
  fi
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
  print_banner
  parse_arguments "$@"
  
  log_info "Starting Vault cleanup"
  log_info "Customer: $CUSTOMER"
  log_info "Project: $PROJECT"
  log_info "Environment: $ENVIRONMENT"
  log_info "Service: $SERVICE"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Confirm deletion
  confirm_deletion
  
  # Validate required commands
  validate_required_commands vault kubectl aws jq
  
  # Setup Vault connection
  log_step "Setting up Vault connection"
  if ! setup_vault_connection; then
    log_error "Failed to setup Vault connection"
    exit 1
  fi
  log_success "Connected to Vault: ${VAULT_ADDR}"
  
  # Authenticate to Vault
  log_step "Authenticating to Vault"
  if ! authenticate_vault_token; then
    log_error "Failed to authenticate to Vault"
    exit 1
  fi
  log_success "Authenticated to Vault"
  
  # Cleanup components (order matters: role before policy)
  cleanup_role
  cleanup_policy
  cleanup_secrets
  
  # Verify
  verify_cleanup
  
  log_success "Vault cleanup complete!"
  
  # Cleanup
  if [[ "$(get_vault_execution_mode)" == "local" ]]; then
    cleanup_vault_port_forward
  fi
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

main "$@"
