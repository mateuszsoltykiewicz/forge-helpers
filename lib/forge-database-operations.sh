#!/usr/bin/env bash
# ==============================================================================
# Forge Database Operations Library
# ==============================================================================
# Description: PostgreSQL database operations for RDS with IAM authentication
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - IAM authentication token generation
# - Database connection testing with retry logic
# - SQL execution with multiple auth methods
# - Database and user creation (idempotent)
# - Privilege management
# - Schema operations
# - SSM parameter retrieval
#
# Dependencies:
# - forge-core.sh
# - forge-aws-discovery.sh
# - psql (PostgreSQL client)
# - aws CLI
#
# Usage:
#   source /path/to/forge-database-operations.sh
#   check_psql_installed || exit 1
#   token=$(get_rds_iam_auth_token "mydb.rds.amazonaws.com" "myuser")
#   test_database_connection "mydb.rds.amazonaws.com" "mydb" "myuser" "iam" "$token"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_DATABASE_OPERATIONS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_DATABASE_OPERATIONS_VERSION="1.0.0"
readonly FORGE_DATABASE_OPERATIONS_LOADED="true"

# ==============================================================================
# DEPENDENCIES
# ==============================================================================

# Get the directory of this script (only if not already set)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Load required libraries
if [[ "${FORGE_CORE_LOADED:-}" != "true" ]]; then
  if [[ -f "${SCRIPT_DIR}/forge-core.sh" ]]; then
    source "${SCRIPT_DIR}/forge-core.sh"
  else
    echo "ERROR: forge-core.sh not found in ${SCRIPT_DIR}" >&2
    exit 1
  fi
fi

if [[ "${FORGE_AWS_DISCOVERY_LOADED:-}" != "true" ]]; then
  if [[ -f "${SCRIPT_DIR}/forge-aws-discovery.sh" ]]; then
    source "${SCRIPT_DIR}/forge-aws-discovery.sh"
  else
    echo "ERROR: forge-aws-discovery.sh not found in ${SCRIPT_DIR}" >&2
    exit 1
  fi
fi

# ==============================================================================
# PREREQUISITE CHECKS
# ==============================================================================

# check_psql_installed
# Validates that psql (PostgreSQL client) is installed and accessible
#
# Returns:
#   0 - psql is available
#   1 - psql is not installed
#
# Example:
#   check_psql_installed || exit 1
#
check_psql_installed() {
  if ! command -v psql &> /dev/null; then
    log_error "psql (PostgreSQL client) is not installed"
    log_error "Please install PostgreSQL client: brew install postgresql@14"
    return 1
  fi
  
  log_debug "psql version: $(psql --version)"
  return 0
}

# check_aws_cli_installed
# Validates that AWS CLI is installed and accessible
#
# Returns:
#   0 - AWS CLI is available
#   1 - AWS CLI is not installed
#
# Example:
#   check_aws_cli_installed || exit 1
#
check_aws_cli_installed() {
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed"
    log_error "Please install AWS CLI: https://aws.amazon.com/cli/"
    return 1
  fi
  
  log_debug "AWS CLI version: $(aws --version)"
  return 0
}

# ==============================================================================
# IAM AUTHENTICATION
# ==============================================================================

# get_rds_iam_auth_token
# Generates an RDS IAM authentication token for PostgreSQL
# Token is valid for 15 minutes
#
# Arguments:
#   $1 - Database host (RDS endpoint)
#   $2 - Database user
#   $3 - (optional) Database port (default: 5432)
#   $4 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   IAM authentication token to stdout
#
# Returns:
#   0 - Success
#   1 - Failed to generate token
#
# Example:
#   token=$(get_rds_iam_auth_token "mydb.rds.amazonaws.com" "myuser")
#   token=$(get_rds_iam_auth_token "mydb.rds.amazonaws.com" "myuser" "5432" "eu-central-1")
#
get_rds_iam_auth_token() {
  local db_host="$1"
  local db_user="$2"
  local db_port="${3:-5432}"
  local aws_region="${4:-$(get_aws_region)}"
  
  log_debug "Generating IAM auth token for user $db_user at $db_host:$db_port"
  
  local token
  if ! token=$(aws rds generate-db-auth-token \
    --hostname "$db_host" \
    --port "$db_port" \
    --username "$db_user" \
    --region "$aws_region" 2>&1); then
    log_error "Failed to generate IAM auth token: $token"
    return 1
  fi
  
  echo "$token"
}

# ==============================================================================
# CONNECTION TESTING
# ==============================================================================

# test_database_connection
# Tests database connection with retry logic
#
# Arguments:
#   $1 - Database host
#   $2 - Database name
#   $3 - Database user
#   $4 - Auth type: "password" or "iam"
#   $5 - Credential (password or IAM token)
#   $6 - (optional) Max retry attempts (default: 30)
#   $7 - (optional) Retry delay in seconds (default: 2)
#   $8 - (optional) Connection timeout in seconds (default: 5)
#
# Returns:
#   0 - Connection successful
#   1 - Connection failed after retries
#
# Example:
#   test_database_connection "mydb.rds.amazonaws.com" "mydb" "myuser" "password" "secret123"
#   test_database_connection "mydb.rds.amazonaws.com" "mydb" "myuser" "iam" "$token" 10 3 5
#
test_database_connection() {
  local db_host="$1"
  local db_name="$2"
  local db_user="$3"
  local auth_type="$4"
  local credential="$5"
  local max_attempts="${6:-30}"
  local retry_delay="${7:-2}"
  local timeout="${8:-5}"
  
  log_info "Testing database connection: $db_user@$db_host/$db_name (auth: $auth_type)"
  
  # Check for timeout command (GNU timeout or gtimeout on macOS)
  local timeout_cmd=""
  if command -v timeout &> /dev/null; then
    timeout_cmd="timeout $timeout"
  elif command -v gtimeout &> /dev/null; then
    timeout_cmd="gtimeout $timeout"
  fi
  
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    log_debug "Connection attempt $attempt/$max_attempts..."
    
    # Execute connection test with timeout
    local result
    if [[ "$auth_type" == "iam" ]]; then
      # IAM authentication requires SSL
      if [[ -n "$timeout_cmd" ]]; then
        result=$($timeout_cmd env PGPASSWORD="$credential" psql \
          -h "$db_host" \
          -U "$db_user" \
          -d "$db_name" \
          -p 5432 \
          --set=sslmode=require \
          --command='SELECT 1;' \
          --no-align \
          --tuples-only \
          --quiet 2>&1)
      else
        result=$(env PGPASSWORD="$credential" psql \
          -h "$db_host" \
          -U "$db_user" \
          -d "$db_name" \
          -p 5432 \
          --set=sslmode=require \
          --command='SELECT 1;' \
          --no-align \
          --tuples-only \
          --quiet 2>&1)
      fi
    else
      # Password authentication
      if [[ -n "$timeout_cmd" ]]; then
        result=$($timeout_cmd env PGPASSWORD="$credential" psql \
          -h "$db_host" \
          -U "$db_user" \
          -d "$db_name" \
          -p 5432 \
          --command='SELECT 1;' \
          --no-align \
          --tuples-only \
          --quiet 2>&1)
      else
        result=$(env PGPASSWORD="$credential" psql \
          -h "$db_host" \
          -U "$db_user" \
          -d "$db_name" \
          -p 5432 \
          --command='SELECT 1;' \
          --no-align \
          --tuples-only \
          --quiet 2>&1)
      fi
    fi
    
    if [[ $? -eq 0 ]] && [[ "$result" == "1" ]]; then
      log_success "Database connection successful on attempt $attempt"
      return 0
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      log_warning "Connection failed, retrying in ${retry_delay}s..."
      sleep "$retry_delay"
    fi
    
    attempt=$((attempt + 1))
  done
  
  log_error "Database connection failed after $max_attempts attempts"
  return 1
}

# ==============================================================================
# SQL EXECUTION
# ==============================================================================

# execute_sql
# Executes SQL statement on PostgreSQL database
#
# Arguments:
#   $1 - SQL statement
#   $2 - Database host
#   $3 - Database name
#   $4 - Database user
#   $5 - Auth type: "password" or "iam"
#   $6 - Credential (password or IAM token)
#
# Returns:
#   0 - Success
#   1 - Failed to execute SQL
#
# Example:
#   execute_sql "CREATE DATABASE mydb;" "localhost" "postgres" "postgres" "password" "secret"
#
execute_sql() {
  local sql="$1"
  local db_host="$2"
  local db_name="$3"
  local db_user="$4"
  local auth_type="$5"
  local credential="$6"
  
  log_debug "Executing SQL on $db_host/$db_name as $db_user"
  
  # Execute SQL based on auth type
  local output
  if [[ "$auth_type" == "iam" ]]; then
    output=$(env PGPASSWORD="$credential" psql \
      -h "$db_host" \
      -U "$db_user" \
      -d "$db_name" \
      -p 5432 \
      --set=sslmode=require \
      --command="$sql" 2>&1)
  else
    output=$(env PGPASSWORD="$credential" psql \
      -h "$db_host" \
      -U "$db_user" \
      -d "$db_name" \
      -p 5432 \
      --command="$sql" 2>&1)
  fi
  
  # Check execution status
  if [[ $? -ne 0 ]]; then
    log_error "SQL execution failed: $output"
    return 1
  fi
  
  log_debug "SQL executed successfully"
  return 0
}

# ==============================================================================
# SSM PARAMETER RETRIEVAL
# ==============================================================================

# get_database_password_from_ssm
# Retrieves database password from SSM Parameter Store
#
# Arguments:
#   $1 - SSM parameter path
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   Password value to stdout
#
# Returns:
#   0 - Success
#   1 - Failed to retrieve password
#
# Example:
#   password=$(get_database_password_from_ssm "/rds/sanofi/cronus/prod/db/password")
#
get_database_password_from_ssm() {
  local ssm_path="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Retrieving password from SSM: $ssm_path"
  
  local password
  if ! password=$(aws ssm get-parameter \
    --name "$ssm_path" \
    --with-decryption \
    --region "$aws_region" \
    --query 'Parameter.Value' \
    --output text 2>&1); then
    log_error "Failed to retrieve SSM parameter: $password"
    return 1
  fi
  
  if [[ -z "$password" ]] || [[ "$password" == "None" ]]; then
    log_error "SSM parameter is empty or not found: $ssm_path"
    return 1
  fi
  
  echo "$password"
}

# ==============================================================================
# DATABASE OPERATIONS
# ==============================================================================

# create_database_if_not_exists
# Creates PostgreSQL database if it doesn't exist
# Idempotent operation - safe to run multiple times
#
# Arguments:
#   $1 - Database name
#   $2 - Database host
#   $3 - Admin user (e.g., postgres)
#   $4 - Admin password
#   $5 - (optional) Database owner (defaults to admin user)
#
# Returns:
#   0 - Success (created or already exists)
#   1 - Failed to create database
#
# Example:
#   create_database_if_not_exists "mydb" "localhost" "postgres" "secret" "myuser"
#
create_database_if_not_exists() {
  local db_name="$1"
  local db_host="$2"
  local admin_user="$3"
  local admin_password="$4"
  local owner="${5:-$admin_user}"
  
  log_info "Checking if database exists: $db_name"
  
  # Check if database exists
  local check_sql="SELECT 1 FROM pg_database WHERE datname = '$db_name';"
  local result
  
  result=$(PGPASSWORD="$admin_password" psql \
    -h "$db_host" \
    -U "$admin_user" \
    -d postgres \
    -p 5432 \
    --tuples-only \
    --no-align \
    --command="$check_sql" 2>&1)
  
  if [[ "$result" == "1" ]]; then
    log_success "Database already exists: $db_name"
    return 0
  fi
  
  # Create database (first as admin, then transfer ownership)
  log_info "Creating database: $db_name (owner: $owner)"
  
  # Step 1: Create database with admin as owner
  local create_sql="CREATE DATABASE \"$db_name\" WITH ENCODING = 'UTF8';"
  
  if ! execute_sql "$create_sql" "$db_host" "postgres" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to create database: $db_name"
    return 1
  fi
  
  # Step 2: Transfer ownership to target user (if different from admin)
  if [[ "$owner" != "$admin_user" ]]; then
    log_debug "Transferring database ownership to: $owner"
    local alter_sql="ALTER DATABASE \"$db_name\" OWNER TO \"$owner\";"
    
    if ! execute_sql "$alter_sql" "$db_host" "postgres" "$admin_user" "password" "$admin_password"; then
      log_error "Failed to transfer database ownership to: $owner"
      return 1
    fi
  fi
  
  log_success "Database created: $db_name (owner: $owner)"
  return 0
}

# create_iam_database_user
# Creates PostgreSQL user for IAM authentication
# NO PASSWORD - user authenticates via IAM tokens
# Grants rds_iam role required for IAM authentication
# Idempotent operation - safe to run multiple times
#
# Arguments:
#   $1 - Username
#   $2 - Database host
#   $3 - Admin user (e.g., postgres)
#   $4 - Admin password
#
# Returns:
#   0 - Success (created or already exists)
#   1 - Failed to create user
#
# Example:
#   create_iam_database_user "myuser" "localhost" "postgres" "secret"
#
create_iam_database_user() {
  local username="$1"
  local db_host="$2"
  local admin_user="$3"
  local admin_password="$4"
  
  log_info "Checking if IAM user exists: $username"
  
  # Check if user exists
  local check_sql="SELECT 1 FROM pg_roles WHERE rolname = '$username';"
  local result
  
  result=$(PGPASSWORD="$admin_password" psql \
    -h "$db_host" \
    -U "$admin_user" \
    -d postgres \
    -p 5432 \
    --tuples-only \
    --no-align \
    --command="$check_sql" 2>&1)
  
  if [[ "$result" == "1" ]]; then
    log_success "IAM user already exists: $username"
    
    # Ensure rds_iam role is granted
    log_info "Ensuring rds_iam role is granted to: $username"
    local grant_sql="GRANT rds_iam TO \"$username\";"
    
    if ! execute_sql "$grant_sql" "$db_host" "postgres" "$admin_user" "password" "$admin_password"; then
      log_warning "Failed to grant rds_iam role (may already be granted)"
    fi
    
    return 0
  fi
  
  # Create IAM user WITHOUT password
  log_info "Creating IAM user: $username (NO PASSWORD)"
  
  local create_sql="CREATE USER \"$username\" WITH LOGIN;"
  
  if ! execute_sql "$create_sql" "$db_host" "postgres" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to create IAM user: $username"
    return 1
  fi
  
  # Grant rds_iam role
  log_info "Granting rds_iam role to: $username"
  
  local grant_sql="GRANT rds_iam TO \"$username\";"
  
  if ! execute_sql "$grant_sql" "$db_host" "postgres" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to grant rds_iam role to: $username"
    return 1
  fi
  
  log_success "IAM user created: $username"
  return 0
}

# grant_database_privileges
# Grants privileges to user on database
# Default privileges: ALL PRIVILEGES
#
# Arguments:
#   $1 - Database name
#   $2 - Username
#   $3 - Database host
#   $4 - Admin user (e.g., postgres)
#   $5 - Admin password
#   $6 - (optional) Privileges (default: "ALL PRIVILEGES")
#
# Returns:
#   0 - Success
#   1 - Failed to grant privileges
#
# Example:
#   grant_database_privileges "mydb" "myuser" "localhost" "postgres" "secret"
#   grant_database_privileges "mydb" "myuser" "localhost" "postgres" "secret" "SELECT, INSERT"
#
grant_database_privileges() {
  local db_name="$1"
  local username="$2"
  local db_host="$3"
  local admin_user="$4"
  local admin_password="$5"
  local privileges="${6:-ALL PRIVILEGES}"
  
  log_info "Granting privileges on database $db_name to $username: $privileges"
  
  local grant_sql="GRANT $privileges ON DATABASE \"$db_name\" TO \"$username\";"
  
  if ! execute_sql "$grant_sql" "$db_host" "postgres" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to grant privileges to $username on $db_name"
    return 1
  fi
  
  log_success "Privileges granted: $username on $db_name"
  return 0
}

# create_database_schema
# Creates PostgreSQL schema in database
# Idempotent operation - safe to run multiple times
#
# Arguments:
#   $1 - Schema name
#   $2 - Database name
#   $3 - Database host
#   $4 - Admin user (e.g., postgres)
#   $5 - Admin password
#
# Returns:
#   0 - Success (created or already exists)
#   1 - Failed to create schema
#
# Example:
#   create_database_schema "public" "mydb" "localhost" "postgres" "secret"
#
create_database_schema() {
  local schema_name="$1"
  local db_name="$2"
  local db_host="$3"
  local admin_user="$4"
  local admin_password="$5"
  
  log_info "Checking if schema exists: $schema_name in database $db_name"
  
  # Check if schema exists
  local check_sql="SELECT 1 FROM information_schema.schemata WHERE schema_name = '$schema_name';"
  local result
  
  result=$(PGPASSWORD="$admin_password" psql \
    -h "$db_host" \
    -U "$admin_user" \
    -d "$db_name" \
    -p 5432 \
    --tuples-only \
    --no-align \
    --command="$check_sql" 2>&1)
  
  if [[ "$result" == "1" ]]; then
    log_success "Schema already exists: $schema_name"
    return 0
  fi
  
  # Create schema
  log_info "Creating schema: $schema_name in database $db_name"
  
  local create_sql="CREATE SCHEMA IF NOT EXISTS \"$schema_name\";"
  
  if ! execute_sql "$create_sql" "$db_host" "$db_name" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to create schema: $schema_name"
    return 1
  fi
  
  log_success "Schema created: $schema_name"
  return 0
}

# grant_schema_ownership
# Grants ownership of schema to user
# Also grants all privileges on schema
#
# Arguments:
#   $1 - Schema name
#   $2 - Username (new owner)
#   $3 - Database name
#   $4 - Database host
#   $5 - Admin user (e.g., postgres)
#   $6 - Admin password
#
# Returns:
#   0 - Success
#   1 - Failed to grant ownership
#
# Example:
#   grant_schema_ownership "public" "myuser" "mydb" "localhost" "postgres" "secret"
#
grant_schema_ownership() {
  local schema_name="$1"
  local username="$2"
  local db_name="$3"
  local db_host="$4"
  local admin_user="$5"
  local admin_password="$6"
  
  log_info "Granting schema ownership: $schema_name to $username in $db_name"
  
  # Change schema owner
  local alter_sql="ALTER SCHEMA \"$schema_name\" OWNER TO \"$username\";"
  
  if ! execute_sql "$alter_sql" "$db_host" "$db_name" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to change schema owner: $schema_name"
    return 1
  fi
  
  # Grant all privileges on schema
  local grant_sql="GRANT ALL ON SCHEMA \"$schema_name\" TO \"$username\";"
  
  if ! execute_sql "$grant_sql" "$db_host" "$db_name" "$admin_user" "password" "$admin_password"; then
    log_error "Failed to grant schema privileges: $schema_name"
    return 1
  fi
  
  log_success "Schema ownership granted: $schema_name to $username"
  return 0
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Prerequisites
export -f check_psql_installed check_aws_cli_installed

# IAM authentication
export -f get_rds_iam_auth_token

# Connection testing
export -f test_database_connection

# SQL execution
export -f execute_sql

# SSM
export -f get_database_password_from_ssm

# Database operations
export -f create_database_if_not_exists create_iam_database_user
export -f grant_database_privileges create_database_schema grant_schema_ownership

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-database-operations.sh v${FORGE_DATABASE_OPERATIONS_VERSION}"
