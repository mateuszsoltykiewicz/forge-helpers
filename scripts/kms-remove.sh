#!/usr/bin/env bash
# ==============================================================================
# KMS Remove Script
# ==============================================================================
# Schedules AWS KMS key for deletion (7-30 day waiting period)
#
# Usage:
#   ./kms-remove.sh --customer <name> --project <name> --environment <env> \
#                   --service <name> --purpose <purpose> [--pending-days <7-30>] \
#                   [--force] [--dry-run]
#
# Example:
#   ./kms-remove.sh --customer sanofi --project cronus --environment dev \
#                   --service video-calling --purpose encryption --pending-days 7
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
PENDING_DAYS="30"  # AWS default
FORCE="false"
DRY_RUN="false"

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║              KMS REMOVE - Delete AWS KMS Key                    ║
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
  --pending-days <7-30>    Days before deletion (default: 30)
  --force                  Skip confirmation prompt
  --dry-run                Preview changes without deleting
  --debug                  Enable debug output
  --help                   Show this help message

Key Naming Convention:
  alias/{customer}/{project}/{environment}/{service}/{purpose}

Examples:
  # Schedule deletion with 7-day waiting period
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service video-calling --purpose encryption --pending-days 7

  # Force deletion without confirmation
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service video-calling --purpose data --force

  # Dry-run mode
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service video-calling --purpose encryption --dry-run

⚠️  WARNING: KMS key deletion is DESTRUCTIVE!
   - Keys are scheduled for deletion (7-30 day waiting period)
   - Data encrypted with this key will become INACCESSIBLE
   - Deletion can be cancelled during waiting period with:
     aws kms cancel-key-deletion --key-id <key-id>

Exit Codes:
  0 - Key scheduled for deletion successfully
  1 - Key deletion failed or user cancelled

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
      --pending-days)
        PENDING_DAYS="$2"
        shift 2
        ;;
      --force)
        FORCE="true"
        shift
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
  
  # Validate pending days
  if [[ ! "$PENDING_DAYS" =~ ^[0-9]+$ ]] || [[ "$PENDING_DAYS" -lt 7 ]] || [[ "$PENDING_DAYS" -gt 30 ]]; then
    log_error "Invalid pending days: $PENDING_DAYS (must be 7-30)"
    exit 1
  fi
  
  log_success "Input validation complete"
}

# ==============================================================================
# CONFIRMATION
# ==============================================================================

confirm_deletion() {
  if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  
  echo ""
  log_warning "⚠️  WARNING: You are about to SCHEDULE KMS KEY DELETION!"
  echo ""
  echo "  Customer:      $CUSTOMER"
  echo "  Project:       $PROJECT"
  echo "  Environment:   $ENVIRONMENT"
  echo "  Service:       $SERVICE"
  echo "  Purpose:       $PURPOSE"
  echo "  Pending days:  $PENDING_DAYS"
  echo ""
  log_warning "This operation will:"
  echo "  1. Delete the key alias"
  echo "  2. Schedule the KMS key for deletion after $PENDING_DAYS days"
  echo "  3. Make ALL data encrypted with this key INACCESSIBLE"
  echo ""
  log_info "You can cancel deletion during the waiting period with:"
  echo "  aws kms cancel-key-deletion --key-id <key-id>"
  echo ""
  
  read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
  echo
  
  if [[ "$REPLY" != "yes" ]]; then
    log_info "Deletion cancelled by user"
    exit 0
  fi
  
  log_info "Proceeding with deletion..."
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
║                    KMS REMOVE                                    ║
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
  log_info "  Pending days: $PENDING_DAYS"
  
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
  
  # Build alias
  local alias_name
  alias_name=$(get_kms_key_alias_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$PURPOSE")
  log_info "Key alias: $alias_name"
  
  # Check if key exists
  if ! key_exists "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$PURPOSE"; then
    log_error "KMS key does not exist with alias: $alias_name"
    exit 1
  fi
  
  # Get key ID
  local key_id
  key_id=$(get_key_id_by_alias "$alias_name")
  log_info "Key ID: $key_id"
  
  # Confirm deletion
  confirm_deletion
  
  # Delete KMS key
  local deletion_date
  if deletion_date=$(delete_kms_key "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$PURPOSE" "$PENDING_DAYS" "$DRY_RUN"); then
    log_success "KMS key deletion scheduled!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
      echo ""
      log_info "Deletion Details:"
      log_info "  Key ID: $key_id"
      log_info "  Alias: $alias_name (deleted)"
      log_info "  Deletion date: $deletion_date"
      log_info "  Pending days: $PENDING_DAYS"
      
      echo ""
      log_warning "To cancel deletion before $deletion_date, run:"
      log_info "  aws kms cancel-key-deletion --key-id '$key_id' --region '$region'"
    fi
    
    exit 0
  else
    log_error "KMS key deletion failed"
    exit 1
  fi
}

# Run main
main "$@"
