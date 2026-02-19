#!/usr/bin/env bash
# ==============================================================================
# Vault Provisioning Script
# ==============================================================================
# Description: Provisions complete Vault setup (policies, roles, auth backend)
# Version: 1.0.0
# Author: Moai Forge Team
#
# This script creates a complete Vault configuration for a service:
# - Kubernetes auth backend configuration
# - Vault policies with least-privilege access
# - Vault roles bound to Kubernetes ServiceAccounts
# - Secret path initialization
#
# Usage:
#   ./vault-provision.sh --customer customer --project project --environment dev --service application
#   ./vault-provision.sh --customer customer --project project --environment dev --service application --dry-run
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
source "${LIB_DIR}/forge-k8s-discovery.sh"

# ==============================================================================
# CONSTANTS
# ==============================================================================

readonly SCRIPT_NAME="vault-provision.sh"
readonly VERSION="1.0.0"

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""
DRY_RUN="false"
CONFIGURE_AUTH_BACKEND="false"
SKIP_POLICY="false"
SKIP_ROLE="false"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_banner() {
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    VAULT PROVISIONING                            ║
║                  Moai Forge Platform v1.0.0                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

print_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Provisions complete Vault setup for a service (policies, roles, auth backend).

Required Options:
  --customer CUSTOMER         Customer name (e.g., customer, indegene)
  --project PROJECT           Project name (e.g., project, platform)
  --environment ENV           Environment (e.g., dev, staging, prod)
  --service SERVICE           Service name (e.g., application-agent)

Optional Flags:
  --configure-auth-backend    Configure Kubernetes auth backend (requires root token)
  --skip-policy               Skip policy creation (use existing policy)
  --skip-role                 Skip role creation (use existing role)
  --dry-run                   Preview changes without executing them
  -h, --help                  Show this help message
  -v, --version               Show version information

Environment Variables:
  VAULT_ADDR                  Vault server address (auto-detected if not set)
  VAULT_TOKEN                 Vault authentication token (from SSM if not set)

Examples:
  # Provision complete setup
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application

  # Provision with auth backend configuration (first-time setup)
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application --configure-auth-backend

  # Preview changes without executing
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application --dry-run

  # Only create policy (skip role)
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service application --skip-role

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
      --configure-auth-backend)
        CONFIGURE_AUTH_BACKEND="true"
        shift
        ;;
      --skip-policy)
        SKIP_POLICY="true"
        shift
        ;;
      --skip-role)
        SKIP_ROLE="true"
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

# ==============================================================================
# PROVISIONING FUNCTIONS
# ==============================================================================

provision_auth_backend() {
  log_step "Configuring Kubernetes auth backend"
  
  if [[ "$CONFIGURE_AUTH_BACKEND" != "true" ]]; then
    log_info "Skipping auth backend configuration (use --configure-auth-backend to enable)"
    return 0
  fi
  
  if configure_k8s_auth_backend; then
    log_success "Kubernetes auth backend configured"
  else
    log_error "Failed to configure auth backend"
    return 1
  fi
}

provision_policy() {
  log_step "Creating Vault policy"
  
  if [[ "$SKIP_POLICY" == "true" ]]; then
    log_info "Skipping policy creation (--skip-policy flag set)"
    return 0
  fi
  
  # Generate policy name
  local policy_name
  policy_name=$(get_vault_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  # Generate secret path
  local secret_base_path
  secret_base_path=$(get_vault_secret_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "*")
  secret_base_path="${secret_base_path%/\*}"  # Remove trailing /*
  
  # Generate policy HCL
  log_info "Generating policy for path: secret/data/${secret_base_path#secret/}"
  
  local policy_hcl
  policy_hcl=$(cat <<EOF
# Policy for ${CUSTOMER}-${PROJECT}-${ENVIRONMENT}-${SERVICE}
# Allows full access to service secrets

# Read/write access to service secrets
path "secret/data/${secret_base_path#secret/}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# List capability on parent path
path "secret/data/${secret_base_path#secret/}" {
  capabilities = ["list"]
}

# Read metadata for service secrets
path "secret/metadata/${secret_base_path#secret/}/*" {
  capabilities = ["read", "list"]
}

# List metadata on parent path
path "secret/metadata/${secret_base_path#secret/}" {
  capabilities = ["list"]
}
EOF
)
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would create policy: $policy_name"
    log_dry_run "Policy content:"
    echo "$policy_hcl" | sed 's/^/  /' >&2
  else
    if create_vault_policy "$policy_name" "$policy_hcl"; then
      log_success "Policy created: $policy_name"
    else
      log_error "Failed to create policy: $policy_name"
      return 1
    fi
  fi
}

provision_role() {
  log_step "Creating Vault role"
  
  if [[ "$SKIP_ROLE" == "true" ]]; then
    log_info "Skipping role creation (--skip-role flag set)"
    return 0
  fi
  
  # Generate names
  local role_name
  role_name=$(get_vault_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  local namespace
  namespace=$(get_namespace_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  local sa_name
  sa_name=$(get_service_account_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  local policy_name
  policy_name=$(get_vault_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  log_info "Creating role: $role_name"
  log_debug "  Namespace: $namespace"
  log_debug "  ServiceAccount: $sa_name"
  log_debug "  Policy: $policy_name"
  
  if create_vault_role "$role_name" "$namespace" "$sa_name" "$policy_name" "24h"; then
    log_success "Role created: $role_name"
  else
    log_error "Failed to create role: $role_name"
    return 1
  fi
}

verify_provisioning() {
  log_step "Verifying provisioning"
  
  local policy_name
  policy_name=$(get_vault_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  local role_name
  role_name=$(get_vault_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run mode: skipping verification"
    return 0
  fi
  
  # Check policy exists
  if [[ "$SKIP_POLICY" != "true" ]]; then
    if list_vault_policies | grep -q "^${policy_name}$"; then
      log_success "✓ Policy exists: $policy_name"
    else
      log_warning "✗ Policy not found: $policy_name"
    fi
  fi
  
  # Check role exists
  if [[ "$SKIP_ROLE" != "true" ]]; then
    if list_vault_roles | grep -q "^${role_name}$"; then
      log_success "✓ Role exists: $role_name"
    else
      log_warning "✗ Role not found: $role_name"
    fi
  fi
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
  print_banner
  parse_arguments "$@"
  
  log_info "Starting Vault provisioning"
  log_info "Customer: $CUSTOMER"
  log_info "Project: $PROJECT"
  log_info "Environment: $ENVIRONMENT"
  log_info "Service: $SERVICE"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
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
  
  # Provision components
  provision_auth_backend
  provision_policy
  provision_role
  
  # Verify
  verify_provisioning
  
  log_success "Vault provisioning complete!"
  
  # Cleanup
  if [[ "$(get_vault_execution_mode)" == "local" ]]; then
    cleanup_vault_port_forward
  fi
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

main "$@"
