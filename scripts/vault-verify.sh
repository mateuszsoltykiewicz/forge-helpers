#!/usr/bin/env bash
# ==============================================================================
# Vault Verify Script
# ==============================================================================
# Description: Verifies secrets in Vault against reference YAML file
# Version: 1.0.0
# Author: Moai Forge Team
#
# This script verifies that secrets in Vault match the reference YAML:
# - Checks if all sections from YAML exist in Vault
# - Verifies all keys are present in each section
# - Compares values between YAML and Vault
# - Reports missing, extra, or mismatched secrets
#
# Usage:
#   ./vault-verify.sh --customer customer --project project --environment dev --service test-1 --file vault.yaml
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

# ==============================================================================
# CONSTANTS
# ==============================================================================

readonly SCRIPT_NAME="vault-verify.sh"
readonly VERSION="1.0.0"

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""
YAML_FILE=""
VERBOSE="false"

# Counters
TOTAL_SECTIONS=0
VERIFIED_SECTIONS=0
FAILED_SECTIONS=0
TOTAL_KEYS=0
VERIFIED_KEYS=0
MISSING_KEYS=0
MISMATCHED_KEYS=0
EXTRA_KEYS=0

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_banner() {
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    VAULT VERIFICATION                            ║
║                  Moai Forge Platform v1.0.0                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

print_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Verifies secrets in Vault against reference YAML file.

Required Options:
  --customer CUSTOMER         Customer name (e.g., customer, indegene)
  --project PROJECT           Project name (e.g., project, platform)
  --environment ENV           Environment (e.g., dev, staging, prod)
  --service SERVICE           Service name (e.g., application-agent)
  --file FILE                 Path to reference YAML file

Optional Flags:
  --verbose                   Show detailed comparison for all keys
  -h, --help                  Show this help message
  -v, --version               Show version information

YAML File Format:
  The YAML file should have sections as top-level keys:
  
  app:
    KEY1: value1
    KEY2: value2
  livekit:
    API_KEY: xxx
    API_SECRET: yyy

Verification Checks:
  1. All sections from YAML exist in Vault
  2. All keys in each section are present in Vault
  3. Values match between YAML and Vault
  4. Reports any extra keys in Vault not in YAML

Exit Codes:
  0 - All secrets verified successfully
  1 - Verification failed (missing/mismatched secrets)
  2 - Invalid arguments or setup error

Examples:
  # Verify all secrets
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service test-1 --file vault.yaml

  # Verbose mode (show all comparisons)
  ${SCRIPT_NAME} --customer customer --project project --environment dev --service test-1 --file vault.yaml --verbose

EOF
}

print_version() {
  echo "${SCRIPT_NAME} version ${VERSION}"
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --file)
        YAML_FILE="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE="true"
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
  validate_required_vars CUSTOMER PROJECT ENVIRONMENT SERVICE YAML_FILE
  validate_forge_pattern_args "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE"
  
  # Validate file exists
  if [[ ! -f "$YAML_FILE" ]]; then
    log_error "YAML file not found: $YAML_FILE"
    exit 1
  fi
}

# ==============================================================================
# VERIFICATION FUNCTIONS
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

verify_section() {
  local section="$1"
  local yaml_file="$2"
  local vault_base_path="$3"
  
  log_step "Verifying section: $section"
  ((TOTAL_SECTIONS++))
  
  local vault_path="${vault_base_path}/${section}"
  
  # Get expected data from YAML
  local expected_data
  expected_data=$(yq eval ".${section}" "$yaml_file" -o=json 2>/dev/null)
  
  if [[ -z "$expected_data" || "$expected_data" == "null" ]]; then
    log_warning "Section '$section' is empty in YAML, skipping"
    return 0
  fi
  
  # Get actual data from Vault
  local actual_data
  if ! actual_data=$(vault kv get -format=json "$vault_path" 2>/dev/null); then
    log_error "✗ Section '$section' not found in Vault"
    ((FAILED_SECTIONS++))
    return 1
  fi
  
  # Extract the data field from Vault response
  actual_data=$(echo "$actual_data" | jq -r '.data.data' 2>/dev/null)
  
  if [[ -z "$actual_data" || "$actual_data" == "null" ]]; then
    log_error "✗ Section '$section' exists but has no data in Vault"
    ((FAILED_SECTIONS++))
    return 1
  fi
  
  # Compare keys and values
  local section_failed=false
  
  # Get all keys from YAML
  local expected_keys
  expected_keys=$(echo "$expected_data" | jq -r 'keys[]' 2>/dev/null | sort)
  
  # Get all keys from Vault
  local actual_keys
  actual_keys=$(echo "$actual_data" | jq -r 'keys[]' 2>/dev/null | sort)
  
  # Check each expected key
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    ((TOTAL_KEYS++))
    
    local expected_value
    expected_value=$(echo "$expected_data" | jq -r --arg k "$key" '.[$k]' 2>/dev/null)
    
    local actual_value
    actual_value=$(echo "$actual_data" | jq -r --arg k "$key" '.[$k]' 2>/dev/null)
    
    if [[ "$actual_value" == "null" ]]; then
      log_error "  ✗ Key '$key' missing in Vault"
      ((MISSING_KEYS++))
      section_failed=true
    elif [[ "$expected_value" != "$actual_value" ]]; then
      log_error "  ✗ Key '$key' value mismatch"
      if [[ "$VERBOSE" == "true" ]]; then
        log_error "    Expected: $expected_value"
        log_error "    Actual:   $actual_value"
      fi
      ((MISMATCHED_KEYS++))
      section_failed=true
    else
      if [[ "$VERBOSE" == "true" ]]; then
        log_success "  ✓ Key '$key' matches"
      fi
      ((VERIFIED_KEYS++))
    fi
  done <<< "$expected_keys"
  
  # Check for extra keys in Vault
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    
    if ! echo "$expected_keys" | grep -q "^${key}$"; then
      log_warning "  ! Key '$key' exists in Vault but not in YAML"
      ((EXTRA_KEYS++))
    fi
  done <<< "$actual_keys"
  
  if [[ "$section_failed" == "true" ]]; then
    log_error "✗ Section '$section' verification failed"
    ((FAILED_SECTIONS++))
    return 1
  else
    log_success "✓ Section '$section' verified successfully"
    ((VERIFIED_SECTIONS++))
    return 0
  fi
}

print_summary() {
  log_step "Verification Summary"
  
  echo ""
  echo "Sections:"
  echo "  Total:    $TOTAL_SECTIONS"
  echo "  Verified: $VERIFIED_SECTIONS"
  echo "  Failed:   $FAILED_SECTIONS"
  echo ""
  echo "Keys:"
  echo "  Total:      $TOTAL_KEYS"
  echo "  Verified:   $VERIFIED_KEYS"
  echo "  Missing:    $MISSING_KEYS"
  echo "  Mismatched: $MISMATCHED_KEYS"
  echo "  Extra:      $EXTRA_KEYS"
  echo ""
  
  if [[ $FAILED_SECTIONS -eq 0 && $MISSING_KEYS -eq 0 && $MISMATCHED_KEYS -eq 0 ]]; then
    log_success "All secrets verified successfully! ✓"
    if [[ $EXTRA_KEYS -gt 0 ]]; then
      log_warning "Note: $EXTRA_KEYS extra key(s) found in Vault (not in YAML)"
    fi
    return 0
  else
    log_error "Verification failed!"
    return 1
  fi
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
  print_banner
  parse_arguments "$@"
  
  log_info "Starting Vault verification"
  log_info "Customer: $CUSTOMER"
  log_info "Project: $PROJECT"
  log_info "Environment: $ENVIRONMENT"
  log_info "Service: $SERVICE"
  log_info "Reference file: $YAML_FILE"
  
  # Validate required commands
  validate_required_commands vault yq jq
  
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
  
  # Parse sections from YAML
  log_step "Parsing reference YAML"
  local sections
  if ! sections=$(parse_yaml_sections "$YAML_FILE"); then
    exit 1
  fi
  
  local section_count
  section_count=$(echo "$sections" | wc -l | tr -d ' ')
  log_info "Found $section_count sections to verify"
  
  # Verify each section
  local vault_base_path
  vault_base_path="secret/${CUSTOMER}/${PROJECT}/${ENVIRONMENT}/${SERVICE}"
  
  log_info "Vault base path: $vault_base_path"
  echo ""
  
  local verification_failed=false
  
  while IFS= read -r section; do
    [[ -z "$section" ]] && continue
    
    if ! verify_section "$section" "$YAML_FILE" "$vault_base_path"; then
      verification_failed=true
    fi
  done <<< "$sections"
  
  echo ""
  
  # Print summary
  if ! print_summary; then
    verification_failed=true
  fi
  
  # Cleanup
  if [[ "$(detect_vault_execution_mode)" == "LOCAL" ]]; then
    cleanup_vault_port_forward
  fi
  
  # Exit with appropriate code
  if [[ "$verification_failed" == "true" ]]; then
    exit 1
  else
    exit 0
  fi
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

main "$@"
