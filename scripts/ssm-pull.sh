#!/usr/bin/env bash
# ==============================================================================
# SSM Pull Script
# ==============================================================================
# Pulls parameters from AWS SSM Parameter Store and generates YAML file
#
# Usage:
#   ./ssm-pull.sh --customer <name> --project <name> --environment <env> \
#                 --service <name> [--output <file>]
#
# Example:
#   ./ssm-pull.sh --customer sanofi --project cronus --environment dev \
#                 --service test-1 --output /tmp/pulled-config.yaml
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
OUTPUT_FILE=""

# ==============================================================================
# USAGE
# ==============================================================================

usage() {
  cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║                  SSM PULL - Pull SSM to YAML                    ║
║                  Moai Forge Platform v${VERSION}                      ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
  $(basename "$0") --customer <name> --project <name> --environment <env> \\
                   --service <name> [OPTIONS]

Required Arguments:
  --customer <name>        Customer name (e.g., sanofi)
  --project <name>         Project name (e.g., cronus)
  --environment <env>      Environment (dev, staging, prod)
  --service <name>         Service name (e.g., test-1)

Optional Arguments:
  --output <file>          Output YAML file path (default: /tmp/{naming-convention}.yaml)
  --debug                  Enable debug output
  --help                   Show this help message

Default Output Path:
  /tmp/{customer}-{project}-{environment}-{service}.yaml

Examples:
  # Pull to default location
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service test-1

  # Pull to custom location
  $(basename "$0") --customer sanofi --project cronus --environment dev \\
                   --service test-1 --output ./my-config.yaml

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
      --output)
        OUTPUT_FILE="$2"
        shift 2
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
  
  # Set default output file if not provided
  if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="/tmp/${CUSTOMER}-${PROJECT}-${ENVIRONMENT}-${SERVICE}.yaml"
    log_info "Using default output file: $OUTPUT_FILE"
  fi
  
  # Check if output directory exists
  local output_dir
  output_dir=$(dirname "$OUTPUT_FILE")
  if [[ ! -d "$output_dir" ]]; then
    log_error "Output directory does not exist: $output_dir"
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
║                     SSM PULL                                     ║
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
  log_info "  Output file: $OUTPUT_FILE"
  
  # Validate required commands
  log_step "Checking required commands"
  validate_required_commands aws jq
  log_success "All required commands available"
  
  # Get SSM base path
  local base_path
  base_path=$(get_ssm_base_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  log_info "SSM base path: $base_path"
  
  # Pull SSM to YAML
  if ! pull_ssm_to_yaml "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$OUTPUT_FILE"; then
    log_error "Failed to pull SSM to YAML"
    exit 1
  fi
  
  log_success "SSM pull complete!"
  echo ""
  log_info "Configuration saved to: $OUTPUT_FILE"
  
  # Show file stats
  if [[ -f "$OUTPUT_FILE" ]]; then
    local line_count
    line_count=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
    log_info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    log_info "Lines: $line_count"
    
    # Show sections
    local sections
    sections=$(grep -E '^[a-z_-]+:$' "$OUTPUT_FILE" | sed 's/:$//' | tr '\n' ', ' | sed 's/,$//')
    if [[ -n "$sections" ]]; then
      log_info "Sections: $sections"
    fi
  fi
}

# Run main
main "$@"
