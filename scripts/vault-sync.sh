#!/usr/bin/env bash
# ==============================================================================
# Vault Sync Script
# ==============================================================================
# Description: Syncs secrets from AWS SSM Parameter Store to Vault
# Version: 1.0.0
# Author: Moai Forge Team
#
# This script synchronizes secrets from AWS SSM to Vault:
# - Discovers SSM sections automatically
# - Syncs each section to corresponding Vault path
# - Detects and reports orphaned Vault secrets
# - Supports change detection (only updates when needed)
#
# Usage:
#   ./vault-sync.sh --customer sanofi --project cronus --environment dev --service video-calling
#   ./vault-sync.sh --customer sanofi --project cronus --environment dev --service video-calling --detect-orphans
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
source "${LIB_DIR}/forge-aws-discovery.sh"
source "${LIB_DIR}/forge-vault-discovery.sh"
source "${LIB_DIR}/forge-vault-operations.sh"

# ==============================================================================
# CONSTANTS
# ==============================================================================

readonly SCRIPT_NAME="vault-sync.sh"
readonly VERSION="1.0.0"

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""
DRY_RUN="false"
DETECT_ORPHANS="false"
SECTIONS=""  # Comma-separated list of specific sections to sync
FROM_YAML=""  # Path to YAML file for import instead of SSM sync

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_banner() {
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    VAULT SYNC (SSM → Vault)                      ║
║                  Moai Forge Platform v1.0.0                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

print_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Syncs secrets from AWS SSM Parameter Store to Vault.

Required Options:
  --customer CUSTOMER         Customer name (e.g., sanofi, indegene)
  --project PROJECT           Project name (e.g., cronus, platform)
  --environment ENV           Environment (e.g., dev, staging, prod)
  --service SERVICE           Service name (e.g., video-calling-agent)

Optional Flags:
  --sections SECTIONS         Comma-separated list of sections to sync (default: all)
                              Example: --sections app,livekit,database
  --from-yaml FILE            Import from YAML file instead of SSM
  --detect-orphans            Detect and report orphaned Vault secrets
  --dry-run                   Preview changes without executing them
  -h, --help                  Show this help message
  -v, --version               Show version information

Environment Variables:
  VAULT_ADDR                  Vault server address (auto-detected if not set)
  VAULT_TOKEN                 Vault authentication token (from SSM if not set)
  AWS_REGION                  AWS region (auto-detected if not set)

Examples:
  # Sync all sections from SSM to Vault
  ${SCRIPT_NAME} --customer sanofi --project cronus --environment dev --service video-calling

  # Import from YAML file
  ${SCRIPT_NAME} --customer sanofi --project cronus --environment dev --service test-1 --from-yaml vault.yaml

  # Sync only specific sections
  ${SCRIPT_NAME} --customer sanofi --project cronus --environment dev --service video-calling --sections app,livekit

  # Detect orphaned secrets (in Vault but not in SSM)
  ${SCRIPT_NAME} --customer sanofi --project cronus --environment dev --service video-calling --detect-orphans

  # Preview sync without making changes
  ${SCRIPT_NAME} --customer sanofi --project cronus --environment dev --service video-calling --dry-run

SSM Parameter Path Format:
  /{customer}/{project}/{environment}/{service}/{section}/{key}
  Example: /sanofi/cronus/dev/video-calling/app/PORT

Vault Secret Path Format:
  secret/{customer}/{project}/{environment}/{service}/{section}
  Example: secret/sanofi/cronus/dev/video-calling/app

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
      --sections)
        SECTIONS="$2"
        shift 2
        ;;
      --from-yaml)
        FROM_YAML="$2"
        shift 2
        ;;
      --detect-orphans)
        DETECT_ORPHANS="true"
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
  
  # Validate YAML file if provided
  if [[ -n "$FROM_YAML" ]] && [[ ! -f "$FROM_YAML" ]]; then
    log_error "YAML file not found: $FROM_YAML"
    exit 1
  fi
}

# ==============================================================================
# YAML IMPORT FUNCTIONS
# ==============================================================================

parse_yaml_sections() {
  local yaml_file="$1"
  
  log_debug "Parsing YAML file: $yaml_file"
  
  # Get top-level keys (sections)
  local sections
  sections=$(yq eval 'keys | .[]' "$yaml_file" 2>/dev/null)
  
  if [[ -z "$sections" ]]; then
    log_error "No sections found in YAML file"
    return 1
  fi
  
  echo "$sections"
}

import_yaml_section() {
  local section="$1"
  local yaml_file="$2"
  local vault_base_path="$3"
  
  log_info "Importing section: $section"
  
  # Get Vault path for this section
  local vault_path="${vault_base_path}/${section}"
  
  log_debug "Vault path: $vault_path"
  
  # Extract section data as JSON
  local section_data
  section_data=$(yq eval ".${section}" "$yaml_file" -o=json 2>/dev/null)
  
  if [[ -z "$section_data" || "$section_data" == "null" ]]; then
    log_warning "Section '$section' is empty, skipping"
    return 0
  fi
  
  # Count keys in section
  local key_count
  key_count=$(echo "$section_data" | jq 'length' 2>/dev/null || echo "0")
  
  log_debug "Found $key_count keys in section '$section'"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would write to Vault: $vault_path"
    echo "$section_data" | jq '.' | while IFS= read -r line; do
      log_debug "[DRY-RUN]   $line"
    done
    return 0
  fi
  
  # Write to Vault
  if ! echo "$section_data" | vault kv put "$vault_path" - >/dev/null 2>&1; then
    log_error "Failed to write section '$section' to Vault"
    return 1
  fi
  
  log_success "✓ Section '$section' imported ($key_count keys)"
}

sync_from_yaml() {
  log_step "Importing from YAML file: $FROM_YAML"
  
  local vault_base_path
  vault_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
  
  log_info "Vault base path: $vault_base_path"
  
  # Parse sections
  local sections_to_import
  if [[ -n "$SECTIONS" ]]; then
    # Use specified sections
    sections_to_import=$(echo "$SECTIONS" | tr ',' '\n')
    log_info "Importing specified sections: $SECTIONS"
  else
    # Parse all sections from YAML
    sections_to_import=$(parse_yaml_sections "$FROM_YAML")
    if [[ -z "$sections_to_import" ]]; then
      log_error "No sections found in YAML"
      return 1
    fi
    local section_count
    section_count=$(echo "$sections_to_import" | wc -l | tr -d ' ')
    log_info "Found $section_count sections in YAML"
  fi
  
  # Import each section
  local imported=0
  local failed=0
  
  while IFS= read -r section; do
    [[ -z "$section" ]] && continue
    
    if import_yaml_section "$section" "$FROM_YAML" "$vault_base_path"; then
      ((imported++))
    else
      ((failed++))
    fi
  done <<< "$sections_to_import"
  
  log_success "YAML import complete: $imported sections imported"
  if [[ $failed -gt 0 ]]; then
    log_warning "Failed: $failed sections"
    return 1
  fi
  
  return 0
}

# ==============================================================================
# SYNC FUNCTIONS
# ==============================================================================

discover_sections() {
  log_step "Discovering SSM sections"
  
  local ssm_prefix
  ssm_prefix=$(get_ssm_parameter_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "")
  ssm_prefix="${ssm_prefix%/}"  # Remove trailing slash
  
  log_info "SSM prefix: $ssm_prefix"
  
  local discovered_sections
  discovered_sections=$(discover_ssm_sections "$ssm_prefix")
  
  if [[ -z "$discovered_sections" ]]; then
    log_warning "No sections found in SSM"
    return 1
  fi
  
  local section_count
  section_count=$(echo "$discovered_sections" | wc -l | tr -d ' ')
  
  log_success "Discovered $section_count sections:"
  echo "$discovered_sections" | sed 's/^/  - /' >&2
  
  echo "$discovered_sections"
}

sync_sections() {
  log_step "Syncing sections from SSM to Vault"
  
  local ssm_prefix
  ssm_prefix=$(get_ssm_parameter_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "")
  ssm_prefix="${ssm_prefix%/}"
  
  local vault_base_path
  vault_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
  
  local sections_to_sync
  if [[ -n "$SECTIONS" ]]; then
    # Use specified sections
    sections_to_sync=$(echo "$SECTIONS" | tr ',' '\n')
    log_info "Syncing specified sections: $SECTIONS"
  else
    # Discover all sections
    sections_to_sync=$(discover_sections)
    if [[ -z "$sections_to_sync" ]]; then
      log_error "No sections to sync"
      return 1
    fi
  fi
  
  local synced=0
  local failed=0
  
  while IFS= read -r section; do
    [[ -z "$section" ]] && continue
    
    log_info "Syncing section: $section"
    
    if sync_ssm_section_to_vault "$ssm_prefix" "$vault_base_path" "$section"; then
      ((synced++))
    else
      ((failed++))
      log_error "Failed to sync section: $section"
    fi
  done <<< "$sections_to_sync"
  
  log_info "Sync complete: $synced succeeded, $failed failed"
  
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
}

detect_orphans_func() {
  if [[ "$DETECT_ORPHANS" != "true" ]]; then
    return 0
  fi
  
  log_step "Detecting orphaned Vault secrets"
  
  local ssm_prefix
  ssm_prefix=$(get_ssm_parameter_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "")
  ssm_prefix="${ssm_prefix%/}"
  
  local vault_base_path
  vault_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
  
  local orphans
  orphans=$(detect_orphaned_vault_secrets "$vault_base_path" "$ssm_prefix" 2>/dev/null || echo "")
  
  if [[ -z "$orphans" ]]; then
    log_success "No orphaned secrets found"
    return 0
  fi
  
  local orphan_count
  orphan_count=$(echo "$orphans" | wc -l | tr -d ' ')
  
  log_warning "Found $orphan_count orphaned secrets (in Vault but not in SSM):"
  echo "$orphans" | sed 's/^/  - /' >&2
  
  echo ""
  log_info "To delete orphaned secrets, use: vault-clean.sh --delete-secrets"
}

verify_sync() {
  log_step "Verifying sync"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run mode: skipping verification"
    return 0
  fi
  
  local vault_base_path
  vault_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
  
  # List Vault secrets
  local vault_secrets
  vault_secrets=$(list_vault_secrets "$vault_base_path" "true" 2>/dev/null || echo "")
  
  if [[ -z "$vault_secrets" ]]; then
    log_warning "No secrets found in Vault after sync"
    return 0
  fi
  
  local secret_count
  secret_count=$(echo "$vault_secrets" | wc -l | tr -d ' ')
  
  log_success "Verified: $secret_count secrets in Vault"
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
  print_banner
  parse_arguments "$@"
  
  if [[ -n "$FROM_YAML" ]]; then
    log_info "Starting Vault import from YAML"
    log_info "YAML file: $FROM_YAML"
  else
    log_info "Starting Vault sync (SSM → Vault)"
  fi
  
  log_info "Customer: $CUSTOMER"
  log_info "Project: $PROJECT"
  log_info "Environment: $ENVIRONMENT"
  log_info "Service: $SERVICE"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Validate required commands
  if [[ -n "$FROM_YAML" ]]; then
    validate_required_commands vault yq jq
  else
    validate_required_commands vault aws jq
  fi
  
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
  
  # Sync or import
  if [[ -n "$FROM_YAML" ]]; then
    # Import from YAML
    sync_from_yaml
  else
    # Sync from SSM
    sync_sections
    detect_orphans_func
  fi
  
  # Verify
  verify_sync
  
  log_success "Vault sync complete!"
  
  # Cleanup
  if [[ "$(detect_vault_execution_mode)" == "LOCAL" ]]; then
    cleanup_vault_port_forward
  fi
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

main "$@"
