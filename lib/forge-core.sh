#!/usr/bin/env bash
# ==============================================================================
# Forge Core Library
# ==============================================================================
# Description: Core utilities for all Forge scripts
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - Unified logging system with 7 severity levels
# - Color-coded output with terminal detection
# - Validation utilities (commands, variables, files, directories)
# - String manipulation (case conversion, formatting)
# - Retry logic with exponential backoff
# - Standardized exit codes
# - Error handling utilities
#
# Usage:
#   source /path/to/forge-core.sh
#   log_info "Starting process..."
#   validate_required_commands kubectl aws docker
#   retry_command 3 2 aws s3 ls s3://my-bucket
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_CORE_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_CORE_VERSION="1.0.0"
readonly FORGE_CORE_LOADED="true"

# ==============================================================================
# EXIT CODES
# ==============================================================================

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR_GENERAL=1
readonly EXIT_ERROR_ARGS=2
readonly EXIT_ERROR_AWS=3
readonly EXIT_ERROR_GIT=4
readonly EXIT_ERROR_DOCKER=5
readonly EXIT_ERROR_VALIDATION=6
readonly EXIT_ERROR_K8S=7
readonly EXIT_ERROR_VAULT=8
readonly EXIT_ERROR_DATABASE=9
readonly EXIT_ERROR_CONNECTION=10
readonly EXIT_ERROR_SQS=11
readonly EXIT_ERROR_QUEUE_NOT_FOUND=12
readonly EXIT_ERROR_QUEUE_ACCESS_DENIED=13
readonly EXIT_ERROR_KMS=14
readonly EXIT_ERROR_POLICY=15

# ==============================================================================
# COLOR DEFINITIONS
# ==============================================================================
# Auto-detects terminal capability and sets color codes accordingly
# Use COLOR_RESET to return to normal after colored output

if [ -t 1 ]; then
  # Terminal supports colors
  readonly COLOR_RED='\033[0;31m'
  readonly COLOR_GREEN='\033[0;32m'
  readonly COLOR_YELLOW='\033[1;33m'
  readonly COLOR_BLUE='\033[0;34m'
  readonly COLOR_CYAN='\033[0;36m'
  readonly COLOR_MAGENTA='\033[0;35m'
  readonly COLOR_WHITE='\033[1;37m'
  readonly COLOR_BOLD='\033[1m'
  readonly COLOR_DIM='\033[2m'
  readonly COLOR_RESET='\033[0m'
else
  # No color support (non-TTY)
  readonly COLOR_RED=''
  readonly COLOR_GREEN=''
  readonly COLOR_YELLOW=''
  readonly COLOR_BLUE=''
  readonly COLOR_CYAN=''
  readonly COLOR_MAGENTA=''
  readonly COLOR_WHITE=''
  readonly COLOR_BOLD=''
  readonly COLOR_DIM=''
  readonly COLOR_RESET=''
fi

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================
# All logging functions write to stderr to keep stdout clean for data output

# log_info
# Logs informational messages
#
# Arguments:
#   $@ - Message to log
#
# Output:
#   Blue [INFO] prefix with message to stderr
#
log_info() {
  echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}  $*" >&2
}

# log_success
# Logs success messages with checkmark
#
# Arguments:
#   $@ - Message to log
#
# Output:
#   Green [✓] prefix with message to stderr
#
log_success() {
  echo -e "${COLOR_GREEN}[✓]${COLOR_RESET}    $*" >&2
}

# log_warning
# Logs warning messages
#
# Arguments:
#   $@ - Message to log
#
# Output:
#   Yellow [WARN] prefix with message to stderr
#
log_warning() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}  $*" >&2
}

# log_error
# Logs error messages
#
# Arguments:
#   $@ - Message to log
#
# Output:
#   Red [ERROR] prefix with message to stderr
#
log_error() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

# log_debug
# Logs debug messages (only if DEBUG or VERBOSE is true)
#
# Arguments:
#   $@ - Message to log
#
# Output:
#   Cyan [DEBUG] prefix with message to stderr (if debug enabled)
#
log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]] || [[ "${VERBOSE:-false}" == "true" ]]; then
    echo -e "${COLOR_CYAN}[DEBUG]${COLOR_RESET} $*" >&2
  fi
}

# log_dry_run
# Logs dry-run messages (preview of actions)
#
# Arguments:
#   $@ - Message to log
#
# Output:
#   Cyan [DRY-RUN] prefix with message to stderr
#
log_dry_run() {
  echo -e "${COLOR_CYAN}[DRY-RUN]${COLOR_RESET} $*" >&2
}

# log_step
# Logs major step/section headers with emphasis
#
# Arguments:
#   $@ - Step title to log
#
# Output:
#   Bold magenta arrow with title to stderr, surrounded by blank lines
#
log_step() {
  echo "" >&2
  echo -e "${COLOR_BOLD}${COLOR_MAGENTA}==>${COLOR_RESET} ${COLOR_BOLD}$*${COLOR_RESET}" >&2
  echo "" >&2
}

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

# validate_required_commands
# Checks if required commands are available in PATH
#
# Arguments:
#   $@ - List of command names to check
#
# Returns:
#   0 - All commands available
#   1 - One or more commands missing
#
# Example:
#   validate_required_commands kubectl aws docker || exit $EXIT_ERROR_VALIDATION
#
validate_required_commands() {
  local missing_commands=()
  
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_commands+=("$cmd")
    fi
  done
  
  if [ ${#missing_commands[@]} -gt 0 ]; then
    log_error "Missing required commands: ${missing_commands[*]}"
    log_error "Please install missing dependencies and try again"
    return 1
  fi
  
  log_debug "All required commands available: $*"
  return 0
}

# validate_required_vars
# Checks if required environment variables are set and non-empty
#
# Arguments:
#   $@ - List of variable names to check (not values!)
#
# Returns:
#   0 - All variables set and non-empty
#   1 - One or more variables missing or empty
#
# Example:
#   validate_required_vars AWS_REGION CUSTOMER PROJECT || exit $EXIT_ERROR_VALIDATION
#
validate_required_vars() {
  local missing_vars=()
  
  for var_name in "$@"; do
    # Use indirect expansion to check if variable is set and non-empty
    if [[ -z "${!var_name:-}" ]]; then
      missing_vars+=("$var_name")
    fi
  done
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    log_error "Missing required variables: ${missing_vars[*]}"
    log_error "Please set these environment variables and try again"
    return 1
  fi
  
  log_debug "All required variables set: $*"
  return 0
}

# validate_file_exists
# Checks if file exists and is readable
#
# Arguments:
#   $1 - File path
#   $2 - (optional) File description for error message
#
# Returns:
#   0 - File exists and is readable
#   1 - File not found or not readable
#
# Example:
#   validate_file_exists "./Dockerfile" "Dockerfile" || exit $EXIT_ERROR_VALIDATION
#
validate_file_exists() {
  local file_path="$1"
  local description="${2:-File}"
  
  if [[ ! -f "$file_path" ]]; then
    log_error "$description not found: $file_path"
    return 1
  fi
  
  if [[ ! -r "$file_path" ]]; then
    log_error "$description not readable: $file_path"
    log_error "Please check file permissions"
    return 1
  fi
  
  log_debug "$description exists and is readable: $file_path"
  return 0
}

# validate_directory_exists
# Checks if directory exists and is accessible
#
# Arguments:
#   $1 - Directory path
#   $2 - (optional) Directory description for error message
#
# Returns:
#   0 - Directory exists and is accessible
#   1 - Directory not found or not accessible
#
# Example:
#   validate_directory_exists "./build" "Build context" || exit $EXIT_ERROR_VALIDATION
#
validate_directory_exists() {
  local dir_path="$1"
  local description="${2:-Directory}"
  
  if [[ ! -d "$dir_path" ]]; then
    log_error "$description not found: $dir_path"
    return 1
  fi
  
  log_debug "$description exists: $dir_path"
  return 0
}

# validate_not_empty
# Checks if string is not empty
#
# Arguments:
#   $1 - String to check
#   $2 - (optional) Variable name for error message
#
# Returns:
#   0 - String is not empty
#   1 - String is empty
#
# Example:
#   validate_not_empty "$CUSTOMER" "CUSTOMER" || exit $EXIT_ERROR_VALIDATION
#
validate_not_empty() {
  local value="$1"
  local name="${2:-Value}"
  
  if [[ -z "$value" ]]; then
    log_error "$name cannot be empty"
    return 1
  fi
  
  log_debug "$name is set: $value"
  return 0
}

# validate_in_list
# Checks if value is in allowed list
#
# Arguments:
#   $1 - Value to check
#   $2 - Comma-separated list of allowed values
#   $3 - (optional) Variable name for error message
#
# Returns:
#   0 - Value is in list
#   1 - Value not in list
#
# Example:
#   validate_in_list "$ENVIRONMENT" "dev,staging,prod" "ENVIRONMENT" || exit $EXIT_ERROR_VALIDATION
#
validate_in_list() {
  local value="$1"
  local allowed_list="$2"
  local name="${3:-Value}"
  
  # Convert comma-separated list to array
  IFS=',' read -ra allowed_array <<< "$allowed_list"
  
  for allowed_value in "${allowed_array[@]}"; do
    if [[ "$value" == "$allowed_value" ]]; then
      log_debug "$name is valid: $value"
      return 0
    fi
  done
  
  log_error "$name must be one of: $allowed_list (got: $value)"
  return 1
}

# ==============================================================================
# STRING UTILITIES
# ==============================================================================

# to_lowercase
# Converts string to lowercase
#
# Arguments:
#   $1 - Input string
#
# Output:
#   Lowercase string to stdout
#
# Example:
#   env=$(to_lowercase "DEV")  # env="dev"
#
to_lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# to_uppercase
# Converts string to uppercase
#
# Arguments:
#   $1 - Input string
#
# Output:
#   Uppercase string to stdout
#
# Example:
#   region=$(to_uppercase "eu-central-1")  # region="EU-CENTRAL-1"
#
to_uppercase() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# to_pascal_case
# Converts hyphen/space/underscore-separated string to PascalCase
#
# Arguments:
#   $1 - Input string (hyphen, space, or underscore separated)
#
# Output:
#   PascalCase string to stdout
#
# Example:
#   to_pascal_case "video-calling-agent"  # VideoCallingAgent
#   to_pascal_case "video calling agent"  # VideoCallingAgent
#   to_pascal_case "video_calling_agent"  # VideoCallingAgent
#
to_pascal_case() {
  echo "$1" | awk -F'[-_ ]' '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1)) tolower(substr($i,2))}'
}

# to_snake_case
# Converts hyphen-separated string to snake_case (underscores)
#
# Arguments:
#   $1 - Input string
#
# Output:
#   snake_case string to stdout
#
# Example:
#   to_snake_case "video-calling-agent"  # video_calling_agent
#
to_snake_case() {
  echo "$1" | tr '-' '_'
}

# replace_hyphens_with_underscores
# Alias for to_snake_case (for backward compatibility)
#
# Arguments:
#   $1 - Input string
#
# Output:
#   String with underscores to stdout
#
replace_hyphens_with_underscores() {
  to_snake_case "$1"
}

# trim_whitespace
# Removes leading and trailing whitespace
#
# Arguments:
#   $1 - Input string
#
# Output:
#   Trimmed string to stdout
#
# Example:
#   trim_whitespace "  hello world  "  # "hello world"
#
trim_whitespace() {
  echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# ==============================================================================
# RETRY LOGIC
# ==============================================================================

# retry_command
# Retries a command with exponential backoff
#
# Arguments:
#   $1 - Max attempts (default: 3)
#   $2 - Initial delay in seconds (default: 2)
#   $@ - Command to execute (all remaining arguments)
#
# Returns:
#   0 - Command succeeded within max attempts
#   1 - Command failed after max attempts
#
# Example:
#   retry_command 3 2 aws s3 ls s3://my-bucket
#   retry_command 5 1 kubectl get pods
#
retry_command() {
  local max_attempts="${1:-3}"
  local delay="${2:-2}"
  shift 2
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    log_debug "Attempt $attempt/$max_attempts: $*"
    
    if "$@"; then
      log_debug "Command succeeded on attempt $attempt"
      return 0
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      log_warning "Command failed, retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))  # Exponential backoff
    fi
    
    ((attempt++))
  done
  
  log_error "Command failed after $max_attempts attempts: $*"
  return 1
}

# retry_with_timeout
# Retries a command with timeout per attempt
#
# Arguments:
#   $1 - Max attempts
#   $2 - Timeout per attempt in seconds
#   $3 - Delay between attempts in seconds
#   $@ - Command to execute
#
# Returns:
#   0 - Command succeeded within max attempts
#   1 - Command failed/timed out after max attempts
#
# Example:
#   retry_with_timeout 3 10 2 curl https://api.example.com/health
#
retry_with_timeout() {
  local max_attempts="$1"
  local timeout="$2"
  local delay="$3"
  shift 3
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    log_debug "Attempt $attempt/$max_attempts (timeout: ${timeout}s): $*"
    
    if timeout "$timeout" "$@"; then
      log_debug "Command succeeded on attempt $attempt"
      return 0
    fi
    
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
      log_warning "Command timed out after ${timeout}s"
    else
      log_warning "Command failed with exit code $exit_code"
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      log_warning "Retrying in ${delay}s..."
      sleep "$delay"
    fi
    
    ((attempt++))
  done
  
  log_error "Command failed after $max_attempts attempts: $*"
  return 1
}

# ==============================================================================
# ERROR HANDLING UTILITIES
# ==============================================================================

# die
# Prints error message and exits with specified code
#
# Arguments:
#   $1 - Exit code (default: EXIT_ERROR_GENERAL)
#   $@ - Error message
#
# Example:
#   die $EXIT_ERROR_VALIDATION "Missing required argument: --customer"
#   die "Something went wrong"  # Uses EXIT_ERROR_GENERAL
#
die() {
  local exit_code="${EXIT_ERROR_GENERAL}"
  
  # Check if first arg is a number (exit code)
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    exit_code="$1"
    shift
  fi
  
  log_error "$@"
  exit "$exit_code"
}

# assert_command_exists
# Checks if command exists, exits if not
#
# Arguments:
#   $1 - Command name
#   $2 - (optional) Installation hint message
#
# Example:
#   assert_command_exists kubectl "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
#
assert_command_exists() {
  local cmd="$1"
  local hint="${2:-}"
  
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    if [[ -n "$hint" ]]; then
      log_error "$hint"
    fi
    exit "$EXIT_ERROR_VALIDATION"
  fi
}

# ==============================================================================
# ARRAY UTILITIES
# ==============================================================================

# join_array
# Joins array elements with delimiter
#
# Arguments:
#   $1 - Delimiter
#   $@ - Array elements
#
# Output:
#   Joined string to stdout
#
# Example:
#   envs=(dev staging prod)
#   join_array "," "${envs[@]}"  # "dev,staging,prod"
#
join_array() {
  local delimiter="$1"
  shift
  local first="$1"
  shift
  printf "%s" "$first" "${@/#/$delimiter}"
}

# split_string
# Splits string into array by delimiter
#
# Arguments:
#   $1 - String to split
#   $2 - Delimiter (default: comma)
#
# Output:
#   Array elements to stdout (one per line)
#
# Example:
#   split_string "dev,staging,prod" ","
#
split_string() {
  local string="$1"
  local delimiter="${2:-,}"
  
  IFS="$delimiter" read -ra parts <<< "$string"
  printf "%s\n" "${parts[@]}"
}

# array_contains
# Checks if array contains specific value
#
# Arguments:
#   $1 - Value to search for
#   $@ - Array elements
#
# Returns:
#   0 - Value found in array
#   1 - Value not found
#
# Example:
#   envs=(dev staging prod)
#   array_contains "dev" "${envs[@]}" && echo "Found!"
#
array_contains() {
  local value="$1"
  shift
  
  for item in "$@"; do
    if [[ "$item" == "$value" ]]; then
      return 0
    fi
  done
  
  return 1
}

# ==============================================================================
# TIMING UTILITIES
# ==============================================================================

# get_timestamp
# Returns current Unix timestamp
#
# Output:
#   Unix timestamp to stdout
#
# Example:
#   start_time=$(get_timestamp)
#
get_timestamp() {
  date +%s
}

# get_iso_timestamp
# Returns current ISO 8601 timestamp
#
# Output:
#   ISO 8601 timestamp to stdout
#
# Example:
#   log_file="build-$(get_iso_timestamp).log"
#
get_iso_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# calculate_duration
# Calculates duration between two timestamps
#
# Arguments:
#   $1 - Start timestamp (seconds)
#   $2 - End timestamp (seconds)
#
# Output:
#   Duration in human-readable format to stdout
#
# Example:
#   start=$(get_timestamp)
#   # ... do work ...
#   end=$(get_timestamp)
#   calculate_duration $start $end  # "2m 35s"
#
calculate_duration() {
  local start="$1"
  local end="$2"
  local duration=$((end - start))
  
  local hours=$((duration / 3600))
  local minutes=$(((duration % 3600) / 60))
  local seconds=$((duration % 60))
  
  if [ $hours -gt 0 ]; then
    echo "${hours}h ${minutes}m ${seconds}s"
  elif [ $minutes -gt 0 ]; then
    echo "${minutes}m ${seconds}s"
  else
    echo "${seconds}s"
  fi
}

# ==============================================================================
# EXPORTS
# ==============================================================================
# Export all functions for use in scripts that source this library

# Logging functions
export -f log_info log_success log_warning log_error log_debug log_dry_run log_step

# Validation functions
export -f validate_required_commands validate_required_vars validate_file_exists
export -f validate_directory_exists validate_not_empty validate_in_list

# String utilities
export -f to_lowercase to_uppercase to_pascal_case to_snake_case
export -f replace_hyphens_with_underscores trim_whitespace

# Retry logic
export -f retry_command retry_with_timeout

# Error handling
export -f die assert_command_exists

# Array utilities
export -f join_array split_string array_contains

# Timing utilities
export -f get_timestamp get_iso_timestamp calculate_duration

# ==============================================================================
# DATABASE UTILITIES
# ==============================================================================

# print_banner
# Displays a formatted banner with title and optional mode
#
# Arguments:
#   $1 - Title
#   $2 - (optional) Mode or subtitle
#
# Output:
#   Formatted banner to stdout
#
# Example:
#   print_banner "Database Provisioning" "PRODUCTION"
#
print_banner() {
  local title="$1"
  local mode="${2:-}"
  
  echo ""
  echo "================================================================================"
  echo "  ${title}"
  if [[ -n "${mode}" ]]; then
    echo "  Mode: ${mode}"
  fi
  echo "================================================================================"
  echo ""
}

# is_valid_identifier
# Validates if string is a valid PostgreSQL identifier (alphanumeric + underscores)
#
# Arguments:
#   $1 - String to validate
#
# Returns:
#   0 if valid, 1 if invalid
#
# Example:
#   if is_valid_identifier "my_database_123"; then
#     echo "Valid"
#   fi
#
is_valid_identifier() {
  local str="$1"
  [[ "$str" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]
}

# is_valid_port
# Validates if string is a valid port number (1-65535)
#
# Arguments:
#   $1 - Port number to validate
#
# Returns:
#   0 if valid, 1 if invalid
#
# Example:
#   if is_valid_port "5432"; then
#     echo "Valid"
#   fi
#
is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# is_valid_aws_region
# Validates if string is a valid AWS region format
#
# Arguments:
#   $1 - AWS region to validate
#
# Returns:
#   0 if valid, 1 if invalid
#
# Example:
#   if is_valid_aws_region "eu-central-1"; then
#     echo "Valid"
#   fi
#
is_valid_aws_region() {
  local region="$1"
  [[ "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]{1}$ ]]
}

# sanitize_database_identifier
# Sanitizes string to be a valid database identifier
# Converts to lowercase, replaces hyphens with underscores, removes invalid chars
#
# Arguments:
#   $1 - String to sanitize
#
# Output:
#   Sanitized identifier to stdout
#
# Example:
#   db_name=$(sanitize_database_identifier "My-Database-123")
#   # Output: my_database_123
#
sanitize_database_identifier() {
  local str="$1"
  echo "$str" | tr '[:upper:]' '[:lower:]' | tr '-' '_' | sed 's/[^a-z0-9_]//g'
}

# ==============================================================================
# SQS VALIDATION FUNCTIONS
# ==============================================================================

# is_valid_queue_name
# Validates SQS queue name according to AWS rules
#
# SQS Queue Naming Rules:
#   - 1-80 characters
#   - Alphanumeric, hyphens, underscores only
#   - FIFO queues must end with .fifo
#
# Arguments:
#   $1 - queue_name (e.g., "my-queue.fifo")
#   $2 - is_fifo ("true" or "false", default: "false")
#
# Returns:
#   0 - Valid queue name
#   1 - Invalid queue name
#
# Example:
#   is_valid_queue_name "sanofi-cronus-prod-events.fifo" "true"
#
is_valid_queue_name() {
  local queue_name="$1"
  local is_fifo="${2:-false}"
  
  # Length check (1-80 characters)
  if [[ ${#queue_name} -lt 1 ]] || [[ ${#queue_name} -gt 80 ]]; then
    log_debug "Invalid queue name length: ${#queue_name} (must be 1-80)"
    return 1
  fi
  
  # FIFO suffix check
  if [[ "$is_fifo" == "true" ]]; then
    if [[ ! "$queue_name" =~ \.fifo$ ]]; then
      log_debug "FIFO queue must end with .fifo: $queue_name"
      return 1
    fi
  fi
  
  # Character check (alphanumeric, hyphen, underscore, period)
  if [[ ! "$queue_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    log_debug "Invalid characters in queue name: $queue_name"
    return 1
  fi
  
  return 0
}

# is_valid_message_retention
# Validates message retention period (60s - 1209600s = 14 days)
#
# Arguments:
#   $1 - retention_period (in seconds)
#
# Returns:
#   0 - Valid retention period
#   1 - Invalid retention period
#
# Example:
#   is_valid_message_retention "345600"  # 4 days
#
is_valid_message_retention() {
  local retention="$1"
  
  # Must be numeric
  if ! [[ "$retention" =~ ^[0-9]+$ ]]; then
    log_debug "Retention period must be numeric: $retention"
    return 1
  fi
  
  # Range check: 60s - 1209600s (14 days)
  if [[ "$retention" -lt 60 ]] || [[ "$retention" -gt 1209600 ]]; then
    log_debug "Retention period out of range: $retention (must be 60-1209600)"
    return 1
  fi
  
  return 0
}

# is_valid_visibility_timeout
# Validates visibility timeout (0s - 43200s = 12 hours)
#
# Arguments:
#   $1 - visibility_timeout (in seconds)
#
# Returns:
#   0 - Valid timeout
#   1 - Invalid timeout
#
# Example:
#   is_valid_visibility_timeout "30"
#
is_valid_visibility_timeout() {
  local timeout="$1"
  
  # Must be numeric
  if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
    log_debug "Visibility timeout must be numeric: $timeout"
    return 1
  fi
  
  # Range check: 0s - 43200s (12 hours)
  if [[ "$timeout" -lt 0 ]] || [[ "$timeout" -gt 43200 ]]; then
    log_debug "Visibility timeout out of range: $timeout (must be 0-43200)"
    return 1
  fi
  
  return 0
}

# parse_queue_arn
# Extracts components from SQS queue ARN
#
# ARN format: arn:aws:sqs:REGION:ACCOUNT:QUEUE_NAME
#
# Arguments:
#   $1 - arn (e.g., "arn:aws:sqs:eu-central-1:123456789012:my-queue")
#
# Returns:
#   0 - Success
#   1 - Invalid ARN
#
# Output:
#   JSON: {"region": "...", "account": "...", "queue_name": "..."}
#
# Example:
#   parse_queue_arn "arn:aws:sqs:eu-central-1:123456789012:my-queue"
#
parse_queue_arn() {
  local arn="$1"
  
  # Validate ARN format
  if [[ ! "$arn" =~ ^arn:aws:sqs: ]]; then
    log_error "Invalid SQS ARN format: $arn"
    return 1
  fi
  
  # Extract components
  local region
  local account
  local queue_name
  
  region=$(echo "$arn" | cut -d':' -f4)
  account=$(echo "$arn" | cut -d':' -f5)
  queue_name=$(echo "$arn" | cut -d':' -f6)
  
  # Validate extracted values
  if [[ -z "$region" ]] || [[ -z "$account" ]] || [[ -z "$queue_name" ]]; then
    log_error "Failed to parse ARN: $arn"
    return 1
  fi
  
  # Return as JSON
  jq -n \
    --arg region "$region" \
    --arg account "$account" \
    --arg queue "$queue_name" \
    '{region: $region, account: $account, queue_name: $queue}'
}

# is_running_in_kubernetes
# Detects if script is running inside Kubernetes pod
#
# Returns:
#   0 - Running in Kubernetes
#   1 - Not running in Kubernetes
#
# Example:
#   if is_running_in_kubernetes; then
#     log_info "Running in-cluster"
#   fi
#
is_running_in_kubernetes() {
  # Check for Kubernetes service host environment variable
  if [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
    return 0
  fi
  
  # Check for service account token
  if [[ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]]; then
    return 0
  fi
  
  return 1
}

# get_execution_mode
# Returns execution mode: "in-cluster" or "local"
#
# Returns:
#   String: "in-cluster" or "local"
#
# Example:
#   mode=$(get_execution_mode)
#   log_info "Execution mode: $mode"
#
get_execution_mode() {
  if is_running_in_kubernetes; then
    echo "in-cluster"
  else
    echo "local"
  fi
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Logging functions
export -f log_info log_success log_warning log_error log_debug log_dry_run log_step

# Validation functions
export -f validate_required_commands validate_required_vars validate_file_exists
export -f validate_directory_exists validate_not_empty validate_in_list
export -f is_valid_identifier is_valid_port is_valid_aws_region

# SQS validation functions
export -f is_valid_queue_name is_valid_message_retention is_valid_visibility_timeout
export -f parse_queue_arn is_running_in_kubernetes get_execution_mode

# String utilities
export -f to_lowercase to_uppercase to_pascal_case to_snake_case
export -f replace_hyphens_with_underscores trim_whitespace sanitize_database_identifier

# Retry logic
export -f retry_command retry_with_timeout

# Error handling
export -f die assert_command_exists

# Array utilities
export -f join_array split_string array_contains

# Timing utilities
export -f get_timestamp get_iso_timestamp calculate_duration

# Database utilities
export -f print_banner

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-core.sh v${FORGE_CORE_VERSION}"
