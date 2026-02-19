#!/usr/bin/env bash
# ==============================================================================
# Database Verification Script
# ==============================================================================
# Description: Verifies PostgreSQL database connection with IAM authentication
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Execution Mode: VERIFICATION (init container in Kubernetes)
# Authentication: IAM-based (IRSA - ServiceAccount)
#
# Operations:
#   1. Auto-discover RDS instance endpoint
#   2. Auto-detect AWS region
#   3. Generate IAM authentication token
#   4. Test database connection with retry logic
#
# Features:
#   - IAM token auto-generation
#   - Retry logic (30 attempts, 2s delay, 5s timeout)
#   - Init container ready
#   - Troubleshooting output
#   - Exit codes: 0=success, 3=connection failed
#
# Usage (Kubernetes init container):
#   ./database-verify.sh --customer customer --project project --environment prod --service videocalling --db-name mydb
#
# Usage (manual testing):
#   ./database-verify.sh --customer customer --project project --environment prod --service videocalling --db-name mydb --verbose
# ==============================================================================

set -euo pipefail

# ==============================================================================
# SCRIPT METADATA
# ==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# LOAD LIBRARIES
# ==============================================================================

LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ -f "${LIB_DIR}/forge-core.sh" ]]; then
  source "${LIB_DIR}/forge-core.sh"
else
  echo "ERROR: forge-core.sh not found in ${LIB_DIR}" >&2
  exit 1
fi

if [[ -f "${LIB_DIR}/forge-patterns.sh" ]]; then
  source "${LIB_DIR}/forge-patterns.sh"
else
  log_error "forge-patterns.sh not found in ${LIB_DIR}"
  exit 1
fi

if [[ -f "${LIB_DIR}/forge-aws-discovery.sh" ]]; then
  source "${LIB_DIR}/forge-aws-discovery.sh"
else
  log_error "forge-aws-discovery.sh not found in ${LIB_DIR}"
  exit 1
fi

if [[ -f "${LIB_DIR}/forge-database-operations.sh" ]]; then
  source "${LIB_DIR}/forge-database-operations.sh"
else
  log_error "forge-database-operations.sh not found in ${LIB_DIR}"
  exit 1
fi

# ==============================================================================
# DEFAULT CONFIGURATION
# ==============================================================================

VERBOSE=false
MAX_ATTEMPTS=30
RETRY_DELAY=2
CONNECTION_TIMEOUT=5

# Required parameters (set via CLI or environment)
CUSTOMER="${CUSTOMER:-}"
PROJECT="${PROJECT:-}"
ENVIRONMENT="${ENVIRONMENT:-}"
SERVICE="${SERVICE:-}"
DB_NAME="${DB_NAME:-}"

# Optional parameters
RDS_INSTANCE_ID="${RDS_INSTANCE_ID:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-}"
AWS_REGION="${AWS_REGION:-}"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# show_usage
# Displays script usage information
#
show_usage() {
  cat << EOF
Database Verification Script v${SCRIPT_VERSION}

Verifies PostgreSQL database connection with IAM authentication.
Designed for Kubernetes init containers with IRSA.

USAGE:
  ${SCRIPT_NAME} [OPTIONS]

REQUIRED OPTIONS:
  --customer CUSTOMER         Customer name (e.g., customer)
  --project PROJECT           Project name (e.g., project)
  --environment ENVIRONMENT   Environment (e.g., prod, dev)
  --service SERVICE           Service name (e.g., videocalling)
  --db-name DB_NAME           Database name to connect to

OPTIONAL OPTIONS:
  --rds-instance-id ID        RDS instance identifier (default: auto-generated from naming convention)
                              Use this to override auto-discovery with a specific RDS instance
                              Example: --rds-instance-id indegene
  
  --db-host HOST              Database host (default: auto-discover from RDS)
  --db-port PORT              Database port (default: 5432)
  --db-user USER              Database user (default: auto-generate from naming convention)
  
  --aws-region REGION         AWS region (default: auto-detect)
  
  --max-attempts COUNT        Maximum retry attempts (default: 30)
  --retry-delay SECONDS       Delay between retries (default: 2)
  --timeout SECONDS           Connection timeout (default: 5)
  
  --verbose                   Enable verbose debug logging
  --help                      Show this help message

ENVIRONMENT VARIABLES:
  CUSTOMER                    Alternative to --customer
  PROJECT                     Alternative to --project
  ENVIRONMENT                 Alternative to --environment
  SERVICE                     Alternative to --service
  DB_NAME                     Alternative to --db-name
  DB_HOST                     Alternative to --db-host
  DB_PORT                     Alternative to --db-port
  DB_USER                     Alternative to --db-user
  AWS_REGION                  Alternative to --aws-region

EXIT CODES:
  0                           Connection successful
  3                           Connection failed after retries

EXAMPLES:
  # Basic usage (Kubernetes init container)
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --db-name customer_project_prod_videocalling_db

  # With environment variables (Kubernetes ConfigMap)
  export CUSTOMER=customer PROJECT=project ENVIRONMENT=prod SERVICE=videocalling
  export DB_NAME=customer_project_prod_videocalling_db
  ${SCRIPT_NAME}

  # Manual testing with verbose output
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --db-name mydb --verbose

  # Custom retry parameters
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --db-name mydb --max-attempts 10 --retry-delay 5

NOTES:
  - Requires IRSA (IAM Roles for Service Accounts) in Kubernetes
  - Auto-generates IAM authentication token
  - Safe for init containers (proper exit codes)
  - Logs to stderr for Kubernetes log aggregation

EOF
}

# validate_arguments
# Validates all required and optional arguments
#
# Returns:
#   0 - All arguments valid
#   1 - Validation failed
#
validate_arguments() {
  local errors=0
  
  # Required parameters
  if [[ -z "$CUSTOMER" ]]; then
    log_error "Missing required parameter: --customer (or CUSTOMER env var)"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$PROJECT" ]]; then
    log_error "Missing required parameter: --project (or PROJECT env var)"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Missing required parameter: --environment (or ENVIRONMENT env var)"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$SERVICE" ]]; then
    log_error "Missing required parameter: --service (or SERVICE env var)"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$DB_NAME" ]]; then
    log_error "Missing required parameter: --db-name (or DB_NAME env var)"
    errors=$((errors + 1))
  fi
  
  # Validate port if provided
  if [[ -n "$DB_PORT" ]] && ! is_valid_port "$DB_PORT"; then
    log_error "Invalid database port: $DB_PORT"
    errors=$((errors + 1))
  fi
  
  # Validate region if provided
  if [[ -n "$AWS_REGION" ]] && ! is_valid_aws_region "$AWS_REGION"; then
    log_error "Invalid AWS region: $AWS_REGION"
    errors=$((errors + 1))
  fi
  
  # Validate numeric parameters
  if ! [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$MAX_ATTEMPTS" -lt 1 ]; then
    log_error "Invalid max attempts: $MAX_ATTEMPTS (must be positive integer)"
    errors=$((errors + 1))
  fi
  
  if ! [[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || [ "$RETRY_DELAY" -lt 1 ]; then
    log_error "Invalid retry delay: $RETRY_DELAY (must be positive integer)"
    errors=$((errors + 1))
  fi
  
  if ! [[ "$CONNECTION_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$CONNECTION_TIMEOUT" -lt 1 ]; then
    log_error "Invalid connection timeout: $CONNECTION_TIMEOUT (must be positive integer)"
    errors=$((errors + 1))
  fi
  
  return $errors
}

# ==============================================================================
# MAIN VERIFICATION LOGIC
# ==============================================================================

# verify_database_connection
# Main verification workflow
#
# Workflow:
#   1. Auto-discover RDS instance endpoint (if needed)
#   2. Auto-detect AWS region (if needed)
#   3. Generate database user name (if needed)
#   4. Generate IAM authentication token
#   5. Test database connection with retry logic
#
verify_database_connection() {
  print_banner "Database Connection Verification" "IAM AUTHENTICATION"
  
  # Show configuration
  log_info "Configuration:"
  log_info "  Customer: $CUSTOMER"
  log_info "  Project: $PROJECT"
  log_info "  Environment: $ENVIRONMENT"
  log_info "  Service: $SERVICE"
  log_info "  Database: $DB_NAME"
  log_info "  Max Attempts: $MAX_ATTEMPTS"
  log_info "  Retry Delay: ${RETRY_DELAY}s"
  log_info "  Connection Timeout: ${CONNECTION_TIMEOUT}s"
  echo ""
  
  # Step 1: Auto-discover RDS instance endpoint (if needed)
  if [[ -z "$DB_HOST" ]]; then
    log_step "Step 1/4: Auto-discovering RDS instance endpoint"
    
    local rds_instance_id
    
    # Use provided RDS instance ID or generate from naming convention
    if [[ -n "$RDS_INSTANCE_ID" ]]; then
      rds_instance_id="$RDS_INSTANCE_ID"
    else
      rds_instance_id=$(get_rds_instance_identifier "$CUSTOMER" "$PROJECT" "$ENVIRONMENT")
    fi
    
    log_info "RDS instance identifier: $rds_instance_id"
    
    local rds_info
    if ! rds_info=$(discover_rds_instance "$rds_instance_id" "${AWS_REGION}"); then
      log_error "Failed to discover RDS instance: $rds_instance_id"
      log_error "Ensure RDS instance exists and AWS credentials are configured"
      exit "$EXIT_ERROR_AWS"
    fi
    
    DB_HOST=$(echo "$rds_info" | jq -r '.endpoint')
    DB_PORT=$(echo "$rds_info" | jq -r '.port')
    
    log_success "RDS endpoint discovered: $DB_HOST:$DB_PORT"
    echo ""
  else
    log_info "Using provided database host: $DB_HOST:$DB_PORT"
    echo ""
  fi
  
  # Step 2: Auto-detect AWS region (if needed)
  if [[ -z "$AWS_REGION" ]]; then
    log_step "Step 2/4: Auto-detecting AWS region"
    
    AWS_REGION=$(get_aws_region)
    log_success "AWS region detected: $AWS_REGION"
    echo ""
  else
    log_info "Using provided AWS region: $AWS_REGION"
    echo ""
  fi
  
  # Step 3: Generate database user name (if needed)
  if [[ -z "$DB_USER" ]]; then
    log_step "Step 3/4: Generating database user name"
    
    DB_USER=$(get_database_user "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
    log_success "Database user: $DB_USER"
    echo ""
  else
    log_info "Using provided database user: $DB_USER"
    echo ""
  fi
  
  # Step 4: Generate IAM authentication token
  log_step "Step 4/4: Generating IAM authentication token"
  
  local iam_token
  if ! iam_token=$(get_rds_iam_auth_token "$DB_HOST" "$DB_USER" "$DB_PORT" "$AWS_REGION"); then
    log_error "Failed to generate IAM authentication token"
    log_error "Ensure IAM role has rds-db:connect permission and IRSA is configured"
    exit "$EXIT_ERROR_AWS"
  fi
  
  log_success "IAM token generated (valid for 15 minutes)"
  echo ""
  
  # Step 5: Test database connection
  print_banner "Connection Test" "RETRY LOGIC ENABLED"
  
  log_info "Connecting to database..."
  log_info "  Host: $DB_HOST:$DB_PORT"
  log_info "  Database: $DB_NAME"
  log_info "  User: $DB_USER"
  log_info "  Auth: IAM (token-based)"
  echo ""
  
  if ! test_database_connection "$DB_HOST" "$DB_NAME" "$DB_USER" "iam" "$iam_token" "$MAX_ATTEMPTS" "$RETRY_DELAY" "$CONNECTION_TIMEOUT"; then
    log_error "Database connection verification failed"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  1. Verify database exists: $DB_NAME"
    log_error "  2. Verify IAM user exists: $DB_USER"
    log_error "  3. Check IAM role has rds-db:connect permission"
    log_error "  4. Check RDS security group allows connection from pod"
    log_error "  5. Verify IRSA is configured correctly"
    log_error "  6. Check RDS instance is available"
    log_error ""
    exit "$EXIT_ERROR_CONNECTION"
  fi
  
  # Success
  print_banner "Verification Complete" "SUCCESS"
  
  log_success "Database connection verified successfully!"
  log_success "Database is ready for application use"
  echo ""
  
  exit "$EXIT_SUCCESS"
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

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
    --db-name)
      DB_NAME="$2"
      shift 2
      ;;
    --rds-instance-id)
      RDS_INSTANCE_ID="$2"
      shift 2
      ;;
    --db-host)
      DB_HOST="$2"
      shift 2
      ;;
    --db-port)
      DB_PORT="$2"
      shift 2
      ;;
    --db-user)
      DB_USER="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --max-attempts)
      MAX_ATTEMPTS="$2"
      shift 2
      ;;
    --retry-delay)
      RETRY_DELAY="$2"
      shift 2
      ;;
    --timeout)
      CONNECTION_TIMEOUT="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit "$EXIT_ERROR_ARGS"
      ;;
  esac
done

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  # Validate arguments
  if ! validate_arguments; then
    log_error "Argument validation failed"
    show_usage
    exit "$EXIT_ERROR_ARGS"
  fi
  
  # Enable verbose logging if requested
  if [[ "$VERBOSE" == "true" ]]; then
    export DEBUG=true
  fi
  
  # Check prerequisites
  check_psql_installed || exit "$EXIT_ERROR_VALIDATION"
  check_aws_cli_installed || exit "$EXIT_ERROR_VALIDATION"
  
  # Run verification
  verify_database_connection
}

main "$@"
