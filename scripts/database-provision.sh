#!/usr/bin/env bash
# ==============================================================================
# Database Provisioning Script
# ==============================================================================
# Description: Provisions PostgreSQL database on RDS with IAM authentication
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Execution Mode: PROVISIONING (ONE-TIME before deployment)
# Authentication: Password-based (PostgreSQL admin from SSM)
#
# Operations:
#   1. Retrieve admin credentials from SSM
#   2. Discover RDS instance endpoint
#   3. Test admin connection
#   4. Create IAM user (conditional - only if main DB or --create-user flag)
#   5. Create database
#   6. Grant ALL PRIVILEGES to user on database
#   7. Create schema
#   8. Grant schema ownership to user
#
# Features:
#   - Multi-database support (--db-custom-suffix)
#   - User reuse (skip user creation for additional databases)
#   - Dry-run mode (--dry-run)
#   - Verbose logging (--verbose)
#   - Idempotent operations (safe to re-run)
#
# Usage:
#   ./database-provision.sh --customer customer --project project --environment prod --service videocalling
#   ./database-provision.sh --customer customer --project project --environment prod --service videocalling --db-custom-suffix recordings
#   ./database-provision.sh --customer customer --project project --environment prod --service videocalling --dry-run
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

DRY_RUN=false
VERBOSE=false
CREATE_USER=false
DB_CUSTOM_SUFFIX=""
ADMIN_USERNAME_SSM=""
ADMIN_PASSWORD_SSM=""
DB_HOST=""
DB_PORT="5432"
AWS_REGION=""
RDS_INSTANCE_ID=""

# Required parameters (set via CLI)
CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
SERVICE=""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# show_usage
# Displays script usage information
#
show_usage() {
  cat << EOF
Database Provisioning Script v${SCRIPT_VERSION}

Provisions PostgreSQL database on RDS with IAM authentication.

USAGE:
  ${SCRIPT_NAME} [OPTIONS]

REQUIRED OPTIONS:
  --customer CUSTOMER         Customer name (e.g., customer)
  --project PROJECT           Project name (e.g., project)
  --environment ENVIRONMENT   Environment (e.g., prod, dev)
  --service SERVICE           Service name (e.g., videocalling)

OPTIONAL OPTIONS:
  --db-custom-suffix SUFFIX   Custom database suffix (e.g., recordings)
                              Creates: customer_project_env_service_SUFFIX_db
                              Reuses existing IAM user (no new user created)
  
  --create-user               Force IAM user creation (even with custom suffix)
                              Use when creating first database with custom suffix
  
  --admin-username-ssm PATH   SSM path for admin username (default: auto-generated)
  --admin-password-ssm PATH   SSM path for admin password (default: auto-generated)
  
  --rds-instance-id ID        RDS instance identifier (default: auto-generated from naming convention)
                              Use this to override auto-discovery with a specific RDS instance
                              Example: --rds-instance-id indegene
  
  --db-host HOST              Database host (default: auto-discover from RDS)
  --db-port PORT              Database port (default: 5432)
  
  --aws-region REGION         AWS region (default: auto-detect)
  
  --dry-run                   Show what would be done without executing
  --verbose                   Enable verbose debug logging
  --help                      Show this help message

EXAMPLES:
  # Provision main database with IAM user
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling

  # Provision additional database (reuses existing IAM user)
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --db-custom-suffix recordings

  # Dry-run mode
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --dry-run

  # Verbose logging
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --verbose

  # Override RDS instance discovery (use specific RDS instance)
  ${SCRIPT_NAME} --customer customer --project project --environment prod --service videocalling --rds-instance-id indegene

NOTES:
  - Idempotent: Safe to run multiple times
  - Multi-database: Use --db-custom-suffix for additional databases
  - User reuse: IAM user is created once and reused for all service databases
  - SSM paths: Uses /rds/{customer}/{project}/{environment}/db/* convention
  - IAM users: Created WITHOUT password (use IAM tokens)
  - RDS Discovery: Uses naming convention by default, or specify --rds-instance-id to override

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
    log_error "Missing required parameter: --customer"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$PROJECT" ]]; then
    log_error "Missing required parameter: --project"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Missing required parameter: --environment"
    errors=$((errors + 1))
  fi
  
  if [[ -z "$SERVICE" ]]; then
    log_error "Missing required parameter: --service"
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
  
  return $errors
}

# ==============================================================================
# MAIN PROVISIONING LOGIC
# ==============================================================================

# provision_database
# Main provisioning workflow
#
# Workflow:
#   1. Retrieve admin credentials from SSM
#   2. Discover RDS instance endpoint
#   3. Test admin connection
#   4. Create IAM user (conditional)
#   5. Create database
#   6. Grant ALL PRIVILEGES
#   7. Create schema
#   8. Grant schema ownership
#
provision_database() {
  print_banner "Database Provisioning" "PRODUCTION"
  
  # Step 0: Show configuration
  log_info "Configuration:"
  log_info "  Customer: $CUSTOMER"
  log_info "  Project: $PROJECT"
  log_info "  Environment: $ENVIRONMENT"
  log_info "  Service: $SERVICE"
  if [[ -n "$DB_CUSTOM_SUFFIX" ]]; then
    log_info "  Custom Suffix: $DB_CUSTOM_SUFFIX"
  fi
  log_info "  Dry-run: $DRY_RUN"
  log_info "  Create User: $CREATE_USER"
  echo ""
  
  # Generate naming
  local db_name
  local db_user
  local rds_instance_id
  local schema_name
  
  db_name=$(get_database_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$DB_CUSTOM_SUFFIX")
  db_name=$(get_database_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE" "$DB_CUSTOM_SUFFIX")
  db_user=$(get_database_user "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE")
  
  # Use provided RDS instance ID or generate from naming convention
  if [[ -n "$RDS_INSTANCE_ID" ]]; then
    rds_instance_id="$RDS_INSTANCE_ID"
  else
    rds_instance_id=$(get_rds_instance_identifier "$CUSTOMER" "$PROJECT" "$ENVIRONMENT")
  fi
  
  schema_name=$(get_default_schema_name)
  
  log_info "Generated naming:"
  log_info "  Database: $db_name"
  log_info "  User: $db_user"
  log_info "  RDS Instance: $rds_instance_id"
  log_info "  Schema: $schema_name"
  echo ""
  
  # Step 1: Retrieve admin credentials from SSM
  log_step "Step 1/8: Retrieving admin credentials from SSM"
  
  local admin_username="postgres"  # Default PostgreSQL admin user
  local admin_password
  
  # Admin username (optional - fallback to "postgres") - with fallback to "shared"
  if [[ -z "$ADMIN_USERNAME_SSM" ]]; then
    ADMIN_USERNAME_SSM=$(get_rds_admin_username_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT")
  fi
  
  log_info "Admin username SSM path: $ADMIN_USERNAME_SSM"
  
  # Try environment-specific path first
  if admin_username_from_ssm=$(get_ssm_parameter "$ADMIN_USERNAME_SSM" 2>/dev/null); then
    admin_username="$admin_username_from_ssm"
    log_success "Admin username retrieved from SSM: $admin_username"
  else
    # Try fallback to "shared" environment
    local shared_username_path
    shared_username_path=$(get_rds_admin_username_path "$CUSTOMER" "$PROJECT" "shared")
    
    if admin_username_from_ssm=$(get_ssm_parameter "$shared_username_path" 2>/dev/null); then
      admin_username="$admin_username_from_ssm"
      log_success "Admin username retrieved from shared SSM path: $admin_username"
    else
      log_warning "Admin username not found in SSM (environment or shared), using default: $admin_username"
    fi
  fi
  
  # Admin password (required) - with fallback to "shared" environment
  if [[ -z "$ADMIN_PASSWORD_SSM" ]]; then
    ADMIN_PASSWORD_SSM=$(get_rds_admin_password_path "$CUSTOMER" "$PROJECT" "$ENVIRONMENT")
  fi
  
  log_info "Admin password SSM path: $ADMIN_PASSWORD_SSM"
  
  # Try environment-specific path first
  if ! admin_password=$(get_database_password_from_ssm "$ADMIN_PASSWORD_SSM" 2>/dev/null); then
    log_warning "Admin password not found for environment: $ENVIRONMENT"
    
    # Fallback to "shared" environment
    local shared_password_path
    shared_password_path=$(get_rds_admin_password_path "$CUSTOMER" "$PROJECT" "shared")
    log_info "Trying fallback SSM path: $shared_password_path"
    
    if ! admin_password=$(get_database_password_from_ssm "$shared_password_path"); then
      log_error "Failed to retrieve admin password from SSM"
      log_error "  Environment-specific: $ADMIN_PASSWORD_SSM"
      log_error "  Shared fallback:      $shared_password_path"
      exit "$EXIT_ERROR_AWS"
    fi
    
    log_success "Admin password retrieved from shared SSM path"
  else
    log_success "Admin password retrieved from SSM"
  fi
  echo ""
  
  # Step 2: Discover RDS instance endpoint
  log_step "Step 2/8: Discovering RDS instance endpoint"
  
  if [[ -z "$DB_HOST" ]]; then
    log_info "Auto-discovering RDS endpoint for: $rds_instance_id"
    
    local rds_info
    if ! rds_info=$(discover_rds_instance "$rds_instance_id" "${AWS_REGION}"); then
      log_error "Failed to discover RDS instance: $rds_instance_id"
      exit "$EXIT_ERROR_AWS"
    fi
    
    DB_HOST=$(echo "$rds_info" | jq -r '.endpoint')
    DB_PORT=$(echo "$rds_info" | jq -r '.port')
    
    log_success "RDS endpoint discovered: $DB_HOST:$DB_PORT"
  else
    log_info "Using provided database host: $DB_HOST:$DB_PORT"
  fi
  echo ""
  
  # Step 3: Test admin connection
  log_step "Step 3/8: Testing admin database connection"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would test connection: $admin_username@$DB_HOST:$DB_PORT/postgres"
  else
    if ! test_database_connection "$DB_HOST" "postgres" "$admin_username" "password" "$admin_password" 5 2 5; then
      log_error "Admin connection test failed"
      exit "$EXIT_ERROR_CONNECTION"
    fi
  fi
  echo ""
  
  # Step 4: Create IAM user (conditional)
  log_step "Step 4/8: Creating IAM user (conditional)"
  
  local should_create_user=false
  
  # Logic: Create user if:
  # 1. Main database (no custom suffix), OR
  # 2. --create-user flag is set
  if [[ -z "$DB_CUSTOM_SUFFIX" ]] || [[ "$CREATE_USER" == "true" ]]; then
    should_create_user=true
  fi
  
  if [[ "$should_create_user" == "true" ]]; then
    log_info "Creating IAM user: $db_user (NO PASSWORD)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would create IAM user: $db_user"
    else
      if ! create_iam_database_user "$db_user" "$DB_HOST" "$admin_username" "$admin_password"; then
        log_error "Failed to create IAM user: $db_user"
        exit "$EXIT_ERROR_DATABASE"
      fi
    fi
  else
    log_info "Skipping user creation (reusing existing IAM user: $db_user)"
  fi
  echo ""
  
  # Step 5: Create database
  log_step "Step 5/8: Creating database: $db_name"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would create database: $db_name (owner: $db_user)"
  else
    if ! create_database_if_not_exists "$db_name" "$DB_HOST" "$admin_username" "$admin_password" "$db_user"; then
      log_error "Failed to create database: $db_name"
      exit "$EXIT_ERROR_DATABASE"
    fi
  fi
  echo ""
  
  # Step 6: Grant ALL PRIVILEGES
  log_step "Step 6/8: Granting privileges to user"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would grant ALL PRIVILEGES on $db_name to $db_user"
  else
    if ! grant_database_privileges "$db_name" "$db_user" "$DB_HOST" "$admin_username" "$admin_password"; then
      log_error "Failed to grant privileges"
      exit "$EXIT_ERROR_DATABASE"
    fi
  fi
  echo ""
  
  # Step 7: Create schema
  log_step "Step 7/8: Creating schema: $schema_name"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would create schema: $schema_name in $db_name"
  else
    if ! create_database_schema "$schema_name" "$db_name" "$DB_HOST" "$admin_username" "$admin_password"; then
      log_error "Failed to create schema: $schema_name"
      exit "$EXIT_ERROR_DATABASE"
    fi
  fi
  echo ""
  
  # Step 8: Grant schema ownership
  log_step "Step 8/8: Granting schema ownership to user"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would grant ownership of $schema_name to $db_user"
  else
    if ! grant_schema_ownership "$schema_name" "$db_user" "$db_name" "$DB_HOST" "$admin_username" "$admin_password"; then
      log_error "Failed to grant schema ownership"
      exit "$EXIT_ERROR_DATABASE"
    fi
  fi
  echo ""
  
  # Summary
  print_banner "Provisioning Complete" "SUCCESS"
  
  log_success "Database provisioning completed successfully!"
  echo ""
  log_info "Summary:"
  log_info "  Database: $db_name"
  log_info "  User: $db_user (IAM authentication)"
  log_info "  Schema: $schema_name"
  log_info "  Endpoint: $DB_HOST:$DB_PORT"
  echo ""
  log_info "Next steps:"
  log_info "  1. Update vault.yaml with connection details"
  log_info "  2. Ensure IAM role has rds-db:connect permission"
  log_info "  3. Test connection with database-verify.sh"
  echo ""
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
    --db-custom-suffix)
      DB_CUSTOM_SUFFIX="$2"
      shift 2
      ;;
    --create-user)
      CREATE_USER=true
      shift
      ;;
    --admin-username-ssm)
      ADMIN_USERNAME_SSM="$2"
      shift 2
      ;;
    --admin-password-ssm)
      ADMIN_PASSWORD_SSM="$2"
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
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
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
  
  # Auto-detect AWS region if not provided
  if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION=$(get_aws_region)
    log_info "Auto-detected AWS region: $AWS_REGION"
  fi
  
  # Run provisioning
  provision_database
  
  exit "$EXIT_SUCCESS"
}

main "$@"
