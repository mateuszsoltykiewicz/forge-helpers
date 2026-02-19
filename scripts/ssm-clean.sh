#!/usr/bin/env bash
# ==============================================================================
# SSM Clean Script
# ==============================================================================
# Deletes parameters from AWS SSM Parameter Store
#
# Usage:
#   ./ssm-clean.sh --customer <name> --project <name> --environment <env> \
#                  --service <name> [--section <name>] [--dry-run] [--force]
#
# Example:
#   ./ssm-clean.sh --customer customer --project project --environment dev \
#                  --service test-1 --section database --dry-run
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

# Optional parameters
SECTION=""
DRY_RUN="false"
FORCE="false"

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║              SSM CLEAN - Delete SSM Parameters                  ║
║                  Moai Forge Platform v${VERSION}                      ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
  $(basename "$0") --customer <name> --project <name> --environment <env> \\
                   --service <name> [OPTIONS]

Required Arguments:
  --customer <name>        Customer name (e.g., customer)
  --project <name>         Project name (e.g., project)
  --environment <env>      Environment (dev, staging, prod)
  --service <name>         Service name (e.g., test-1)

Optional Arguments:
  --section <name>         Delete only specific section (e.g., database, app)
                           If omitted, deletes ALL parameters for the service
  --force                  Skip confirmation prompt
  --dry-run                Preview changes without deleting
  --debug                  Enable debug output
  --help                   Show this help message

Examples:
  # Delete all parameters (with confirmation)
  $(basename "$0") --customer customer --project project --environment dev \\
                   --service test-1

  # Delete specific section
  $(basename "$0") --customer customer --project project --environment dev \\
                   --service test-1 --section database

  # Dry-run mode
  $(basename "$0") --customer customer --project project --environment dev \\
                   --service test-1 --dry-run

  # Force deletion without confirmation
  $(basename "$0") --customer customer --project project --environment dev \\
                   --service test-1 --force

Exit Codes:
  0 - Cleanup completed successfully
  1 - Cleanup failed or user cancelled

⚠️  WARNING: This operation is DESTRUCTIVE and cannot be undone!
   Always use --dry-run first to preview what will be deleted.

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
      --section)
        SECTION="$2"
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
  
  validate_required_vars CUSTOMER PROJECT ENVIRONMENT SERVICE
  
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
  log_warning "⚠️  WARNING: You are about to DELETE parameters from SSM!"
  echo ""
  echo "  Customer:    $CUSTOMER"
  echo "  Project:     $PROJECT"
  echo "  Environment: $ENVIRONMENT"
  echo "  Service:     $SERVICE"
  
  if [[ -n "$SECTION" ]]; then
    echo "  Section:     $SECTION"
  else
    echo "  Scope:       ALL SECTIONS"
  fi
  
  echo ""
  log_warning "This operation CANNOT be undone!"
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
# CLEANUP
# ==============================================================================

cleanup_parameters() {
  log_step "Cleaning up SSM parameters"
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  if [[ -n "$SECTION" ]]; then
    # Delete specific section
    log_info "Target: $base_path/$SECTION"
    
    if ! delete_ssm_section "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$SECTION" "$DRY_RUN"; then
      log_error "Failed to delete section: $SECTION"
      return 1
    fi
  else
    # Delete all sections
    log_info "Target: $base_path (ALL sections)"
    
    # List all sections
    local sections
    sections=$(list_ssm_sections "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
    
    if [[ -z "$sections" ]]; then
      log_warning "No sections found to delete"
      return 0
    fi
    
    local section_count
    section_count=$(echo "$sections" | wc -l | tr -d ' ')
    log_info "Found $section_count sections to delete"
    
    # Delete each section
    local deleted=0
    local failed=0
    
    while IFS= read -r section; do
      [[ -z "$section" ]] && continue
      
      log_info "Deleting section: $section"
      
      if delete_ssm_section "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$section" "$DRY_RUN"; then
        ((deleted++))
      else
        ((failed++))
      fi
    done <<< "$sections"
    
    log_info "Sections deleted: $deleted, failed: $failed"
    
    if [[ $failed -gt 0 ]]; then
      return 1
    fi
  fi
  
  return 0
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
║                    SSM CLEAN                                     ║
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
  
  if [[ -n "$SECTION" ]]; then
    log_info "  Section: $SECTION"
  else
    log_warning "  Scope: ALL SECTIONS"
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Validate required commands
  log_step "Checking required commands"
  validate_required_commands aws jq
  log_success "All required commands available"
  
  # Confirm deletion
  confirm_deletion
  
  # Cleanup parameters
  if cleanup_parameters; then
    log_success "SSM cleanup complete!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
      echo ""
      log_info "To verify deletion, run:"
      log_info "  ./ssm-pull.sh --customer $CUSTOMER --project $PROJECT --environment $ENVIRONMENT --service $SERVICE"
    fi
    
    exit 0
  else
    log_error "SSM cleanup failed"
    exit 1
  fi
}

# Run main
main "$@"
