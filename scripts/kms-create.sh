#!/usr/bin/env bash
# ==============================================================================
# KMS Create Script
# ==============================================================================
# Creates AWS KMS key with Forge naming convention
#
# Usage:
#   ./kms-create.sh --customer <name> --project <name> --environment <env> \
#                   --service <name> --purpose <purpose> [--dry-run]
#
# Example:
#   ./kms-create.sh --customer sanofi --project cronus --environment dev \
#                   --service video-calling --purpose encryption
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
source "$LIB_DIR/forge-kms-operations.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

VERSION="1.0.0"

# Required parameters
CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""
PURPOSE=""

# Optional parameters
DRY_RUN="false"

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║              KMS CREATE - Create AWS KMS Key                    ║
║                  Moai Forge Platform v${VERSION}                      ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
  $(basename "$0") --customer <name> --project <name> --environment <env> \\
                   --service <name> --purpose <purpose> [OPTIONS]

Required Arguments:
  --customer <name>        Customer name (e.g., sanofi)
  --project <name>         Project name (e.g., cronus)
  --environment <env>      Environment (dev, staging, prod)
  --service <name>         Service name (e.g., video-calling)
  --purpose <purpose>      Key purpose (e.g., encryption, signing, data, secrets)

Optional Arguments:
Optional Arguments:
  --dry-run                Preview changes without creating
  --debug                  Enable debug output
  --help                   Show this help message

Key Policy:
  All keys are created with a policy that grants:
  - Full access to AWS account root user
  - Encrypt/Decrypt access to IRSA role: {Customer}{Project}{Env}{Service}Irsa
Key Naming Convention:
  alias/{customer}/{project}/{environment}/{service}/{purpose}

Examples:
  # Create encryption key for video-calling service
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service video-calling --purpose encryption

  # Dry-run mode
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service video-calling --purpose data --dry-run

Key Purposes:
  - encryption:  General data encryption (ENCRYPT_DECRYPT)
  - signing:     Digital signatures
  - data:        Database/storage encryption
  - secrets:     Secrets management encryption
  - custom:      Custom purpose defined by service

Exit Codes:
  0 - Key created successfully (or already exists)
  1 - Key creation failed

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
      --purpose)
        PURPOSE="$2"
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
  
  validate_required_vars CUSTOMER PROJECT ENVIRONMENT SERVICE PURPOSE
  
  # Validate naming conventions
  validate_customer_name "$CUSTOMER"
  validate_project_name "$PROJECT"
  validate_environment_name "$ENVIRONMENT"
  validate_service_name "$SERVICE"
  
  # Validate purpose (alphanumeric, hyphens allowed)
  if [[ ! "$PURPOSE" =~ ^[a-z0-9-]+$ ]]; then
    log_error "Invalid purpose: $PURPOSE (must be lowercase alphanumeric with hyphens)"
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
║                    KMS CREATE                                    ║
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
  log_info "  Purpose: $PURPOSE"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Validate required commands
  log_step "Checking required commands"
  validate_required_commands aws jq
  log_success "All required commands available"
  
  # Get AWS info
  local region
  region=$(get_aws_region)
  log_info "AWS Region: $region"
  
  local execution_mode
  execution_mode=$(detect_aws_execution_mode)
  log_info "Execution mode: $execution_mode"
  
  # Build alias
  local alias_name
  alias_name=$(get_kms_key_alias_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$PURPOSE")
  log_info "Key alias: $alias_name"
  
  # Build alias
  local alias_name
  alias_name=$(get_kms_key_alias_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$PURPOSE")
  log_info "Key alias: $alias_name"
  
  # Show IRSA role that will have access
  local irsa_role
  irsa_role=$(get_irsa_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  log_info "IRSA role with access: $irsa_role"
  
  # Create KMS key
  local key_id
  if key_id=$(create_kms_key "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$PURPOSE" "$DRY_RUN"); then
    log_success "KMS key ready!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
      echo ""
      log_info "Key Details:"
      log_info "  Key ID: $key_id"
      log_info "  Alias: $alias_name"
      log_info "  Region: $region"
      
      echo ""
      log_info "To use this key in your application:"
      log_info "  export KMS_KEY_ID='$key_id'"
      log_info "  export KMS_KEY_ALIAS='$alias_name'"
      
      echo ""
      log_info "To encrypt data with this key:"
      log_info "  aws kms encrypt --key-id '$key_id' --plaintext 'your-data' --query CiphertextBlob --output text"
      
      echo ""
      log_info "To delete this key, run:"
      log_info "  ./kms-remove.sh --customer $CUSTOMER --project $PROJECT --environment $ENVIRONMENT --service $SERVICE --purpose $PURPOSE"
    fi
    
    exit 0
  else
    log_error "KMS key creation failed"
    exit 1
  fi
}

# Run main
main "$@"
