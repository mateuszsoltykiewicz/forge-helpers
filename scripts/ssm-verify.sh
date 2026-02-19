#!/usr/bin/env bash
# ==============================================================================
# SSM Verify Script
# ==============================================================================
# Verifies AWS SSM parameters against a reference YAML file
#
# Usage:
#   ./ssm-verify.sh --customer <name> --project <name> --environment <env> \
#                   --service <name> --file <yaml-file> [--verbose]
#
# Example:
#   ./ssm-verify.sh --customer customer --project project --environment dev \
#                   --service test-1 --file /tmp/customer-project-dev-test-1.yaml
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SCRIPT DIRECTORY AND LIBRARY LOADING
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Source libraries
source "$LIB_DIR/forge-core.sh"
source "$LIB_DIR/forge-patterns.sh"
source "$LIB_DIR/forge-aws-discovery.sh"
source "$LIB_DIR/forge-ssm-operations.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

VERSION="1.0.0"

# Required parameters
CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""
YAML_FILE=""

# Optional parameters
VERBOSE="false"

# Counters
TOTAL_PARAMS=0
VERIFIED_PARAMS=0
MISSING_PARAMS=0
MISMATCHED_PARAMS=0
EXTRA_PARAMS=0

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║              SSM VERIFY - Verify SSM Parameters                 ║
║                  Moai Forge Platform v${VERSION}                      ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
  $(basename "$0") --customer <name> --project <name> --environment <env> \\
                   --service <name> --file <yaml-file> [OPTIONS]

Required Arguments:
  --customer <name>        Customer name (e.g., customer)
  --project <name>         Project name (e.g., project)
  --environment <env>      Environment (dev, staging, prod)
  --service <name>         Service name (e.g., test-1)
  --file <yaml-file>       Reference YAML file to verify against

Optional Arguments:
  --verbose                Show detailed comparison for each parameter
  --debug                  Enable debug output
  --help                   Show this help message

Examples:
  # Verify SSM parameters
  $(basename "$0") --customer customer --project project --environment dev \\
                   --service test-1 --file /tmp/customer-project-dev-test-1.yaml

  # Verbose mode (show all comparisons)
  $(basename "$0") --customer customer --project project --environment dev \\
                   --service test-1 --file config.yaml --verbose

Exit Codes:
  0 - All parameters match
  1 - Verification failed (missing, mismatched, or extra parameters)

EOF
  exit 0
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

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
      --file)
        YAML_FILE="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE="true"
        shift
        ;;
      --debug)
        DEBUG="true"
        shift
        ;;
      --help)
        usage
        ;;
      *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
}

# ==============================================================================
# VALIDATION
# ==============================================================================

validate_inputs() {
  log_step "Validating inputs"
  
  validate_required_vars CUSTOMER PROJECT ENVIRONMENT SERVICE YAML_FILE
  validate_file_exists "$YAML_FILE" "YAML file"
  
  log_success "Input validation complete"
}

# ==============================================================================
# VERIFICATION
# ==============================================================================

verify_parameters() {
  log_step "Verifying SSM parameters"
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  log_info "SSM base path: $base_path"
  
  # Parse YAML to get expected parameters
  local yaml_params
  yaml_params=$(parse_yaml_to_ssm_format "$YAML_FILE" "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  TOTAL_PARAMS=$(echo "$yaml_params" | jq 'length')
  log_info "Reference YAML contains $TOTAL_PARAMS parameters"
  
  # Get current SSM parameters
  local ssm_params
  ssm_params=$(list_ssm_parameters_by_path "$base_path" "true" "true")
  
  local ssm_count
  ssm_count=$(echo "$ssm_params" | jq 'length')
  log_info "SSM contains $ssm_count parameters"
  
  echo ""
  log_step "Comparing parameters"
  
  # Check each YAML parameter against SSM
  while IFS= read -r yaml_param; do
    local path
    local yaml_value
    
    path=$(echo "$yaml_param" | jq -r '.path')
    yaml_value=$(echo "$yaml_param" | jq -r '.value')
    
    # Find matching SSM parameter
    local ssm_value
    ssm_value=$(echo "$ssm_params" | jq -r ".[] | select(.Name == \"$path\") | .Value // empty")
    
    if [[ -z "$ssm_value" ]]; then
      # Parameter missing in SSM
      log_error "[MISSING] $path"
      ((MISSING_PARAMS++))
    elif [[ "$ssm_value" != "$yaml_value" ]]; then
      # Parameter exists but value differs
      log_warning "[MISMATCH] $path"
      if [[ "$VERBOSE" == "true" ]]; then
        log_info "  Expected: $yaml_value"
        log_info "  Actual:   $ssm_value"
      fi
      ((MISMATCHED_PARAMS++))
    else
      # Parameter matches
      if [[ "$VERBOSE" == "true" ]]; then
        log_success "[OK] $path"
      fi
      ((VERIFIED_PARAMS++))
    fi
  done < <(echo "$yaml_params" | jq -c '.[]')
  
  # Check for extra parameters in SSM (not in YAML)
  while IFS= read -r ssm_param; do
    local ssm_path
    ssm_path=$(echo "$ssm_param" | jq -r '.Name')
    
    # Check if this path exists in YAML
    local in_yaml
    in_yaml=$(echo "$yaml_params" | jq -r ".[] | select(.path == \"$ssm_path\") | .path // empty")
    
    if [[ -z "$in_yaml" ]]; then
      log_warning "[EXTRA] $ssm_path (in SSM but not in YAML)"
      ((EXTRA_PARAMS++))
    fi
  done < <(echo "$ssm_params" | jq -c '.[]')
}

# ==============================================================================
# SUMMARY
# ==============================================================================

print_summary() {
  echo ""
  log_step "Verification Summary"
  
  echo ""
  echo "  Total parameters:      $TOTAL_PARAMS"
  echo "  ✓ Verified (match):    $VERIFIED_PARAMS"
  echo "  ✗ Missing in SSM:      $MISSING_PARAMS"
  echo "  ⚠ Mismatched values:   $MISMATCHED_PARAMS"
  echo "  ⚠ Extra in SSM:        $EXTRA_PARAMS"
  echo ""
  
  if [[ $MISSING_PARAMS -eq 0 ]] && [[ $MISMATCHED_PARAMS -eq 0 ]] && [[ $EXTRA_PARAMS -eq 0 ]]; then
    log_success "✅ All parameters verified successfully!"
    return 0
  else
    log_error "❌ Verification failed"
    
    if [[ $MISSING_PARAMS -gt 0 ]]; then
      echo ""
      log_error "Action required: Push missing parameters to SSM"
      log_info "  ./ssm-push.sh --customer $CUSTOMER --project $PROJECT --environment $ENVIRONMENT --service $SERVICE --file $YAML_FILE"
    fi
    
    if [[ $EXTRA_PARAMS -gt 0 ]]; then
      echo ""
      log_warning "Warning: Extra parameters found in SSM"
      log_info "  These parameters exist in SSM but not in your YAML file"
      log_info "  Run ssm-pull.sh to see all current parameters"
    fi
    
    return 1
  fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
  # Parse arguments
  parse_arguments "$@"
  
  # Print banner
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║                    SSM VERIFY                                    ║
║                  Moai Forge Platform v${VERSION}                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
  
  # Validate inputs
  validate_inputs
  
  # Show configuration
  log_info "Configuration:"
  log_info "  Customer: $CUSTOMER"
  log_info "  Project: $PROJECT"
  log_info "  Environment: $ENVIRONMENT"
  log_info "  Service: $SERVICE"
  log_info "  Reference file: $YAML_FILE"
  
  # Validate required commands
  log_step "Checking required commands"
  validate_required_commands aws jq yq
  log_success "All required commands available"
  
  # Verify parameters
  verify_parameters
  
  # Print summary
  if print_summary; then
    exit 0
  else
    exit 1
  fi
}

# Run main
main "$@"
