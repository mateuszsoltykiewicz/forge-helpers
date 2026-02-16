#!/usr/bin/env bash
# ==============================================================================
# SSM Push Script
# ==============================================================================
# Pushes YAML configuration to AWS SSM Parameter Store
#
# Usage:
#   ./ssm-push.sh --customer <name> --project <name> --environment <env> \
#                 --service <name> --file <yaml-file> [--dry-run] [--type <String|SecureString>]
#
# Example:
#   ./ssm-push.sh --customer sanofi --project cronus --environment dev \
#                 --service test-1 --file /tmp/sanofi-cronus-dev-test-1.yaml
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
DRY_RUN="false"
PARAMETER_TYPE="SecureString"

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║                  SSM PUSH - Push YAML to SSM                    ║
║                  Moai Forge Platform v${VERSION}                      ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
  $(basename "$0") --customer <name> --project <name> --environment <env> \\
                   --service <name> --file <yaml-file> [OPTIONS]

Required Arguments:
  --customer <name>        Customer name (e.g., sanofi)
  --project <name>         Project name (e.g., cronus)
  --environment <env>      Environment (dev, staging, prod)
  --service <name>         Service name (e.g., test-1)
  --file <yaml-file>       Path to YAML configuration file

Optional Arguments:
  --type <type>            Parameter type: String or SecureString (default: SecureString)
  --dry-run                Preview changes without pushing to SSM
  --debug                  Enable debug output
  --help                   Show this help message

Examples:
  # Push configuration to SSM
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service test-1 --file /tmp/sanofi-cronus-dev-test-1.yaml

  # Dry-run mode
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service test-1 --file config.yaml --dry-run

  # Use String type instead of SecureString
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service test-1 --file config.yaml --type String

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
      --type)
        PARAMETER_TYPE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
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
  
  # Validate parameter type
  if [[ "$PARAMETER_TYPE" != "String" ]] && [[ "$PARAMETER_TYPE" != "SecureString" ]]; then
    log_error "Parameter type must be 'String' or 'SecureString', got: $PARAMETER_TYPE"
    exit 1
  fi
  
  log_success "Input validation complete"
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
║                     SSM PUSH                                     ║
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
  log_info "  YAML file: $YAML_FILE"
  log_info "  Parameter type: $PARAMETER_TYPE"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Validate required commands
  log_step "Checking required commands"
  validate_required_commands aws jq yq
  log_success "All required commands available"
  
  # Get SSM base path
  local base_path
  base_path=$(get_ssm_base_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  log_info "SSM base path: $base_path"
  
  # Push YAML to SSM
  if ! push_yaml_to_ssm "$YAML_FILE" "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$DRY_RUN" "$PARAMETER_TYPE"; then
    log_error "Failed to push YAML to SSM"
    exit 1
  fi
  
  log_success "SSM push complete!"
  
  if [[ "$DRY_RUN" != "true" ]]; then
    echo ""
    log_info "To verify the pushed parameters, run:"
    log_info "  ./ssm-pull.sh --customer $CUSTOMER --project $PROJECT --environment $ENVIRONMENT --service $SERVICE"
  fi
}

# Run main
main "$@"
