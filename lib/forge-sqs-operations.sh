#!/usr/bin/env bash
# ==============================================================================
# Forge SQS Operations Library
# ==============================================================================
# Description: AWS SQS queue management utilities
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - FIFO queue creation and deletion
# - KMS encryption key management
# - Queue policy generation (producer/consumer)
# - IRSA role integration (multi-role support)
# - Testing utilities (send/receive messages)
# - SSM Parameter Store integration
#
# Usage:
#   source /path/to/forge-sqs-operations.sh
#   create_kms_key_for_sqs "customer" "project" "prod"
#   create_fifo_queue "my-queue.fifo" "$kms_key_id"
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_SQS_OPERATIONS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_SQS_OPERATIONS_VERSION="1.0.0"
readonly FORGE_SQS_OPERATIONS_LOADED="true"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Get script directory
FORGE_SQS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source forge-core (required)
if [[ -f "${FORGE_SQS_DIR}/forge-core.sh" ]]; then
  source "${FORGE_SQS_DIR}/forge-core.sh"
else
  echo "ERROR: forge-core.sh not found in ${FORGE_SQS_DIR}" >&2
  exit 1
fi

# Source forge-patterns (required)
if [[ -f "${FORGE_SQS_DIR}/forge-patterns.sh" ]]; then
  source "${FORGE_SQS_DIR}/forge-patterns.sh"
else
  log_error "forge-patterns.sh not found in ${FORGE_SQS_DIR}"
  exit 1
fi

# Source forge-aws-discovery (required)
if [[ -f "${FORGE_SQS_DIR}/forge-aws-discovery.sh" ]]; then
  source "${FORGE_SQS_DIR}/forge-aws-discovery.sh"
else
  log_error "forge-aws-discovery.sh not found in ${FORGE_SQS_DIR}"
  exit 1
fi

# ==============================================================================
# PREREQUISITES
# ==============================================================================

# check_aws_sqs_permissions
# Checks if user has necessary SQS permissions
#
# Returns:
#   0 - Has permissions
#   1 - Missing permissions
#
check_aws_sqs_permissions() {
  log_debug "Checking AWS SQS permissions..."
  
  # Try to list queues (minimal permission check)
  if aws sqs list-queues --max-results 1 &>/dev/null; then
    log_debug "AWS SQS permissions OK"
    return 0
  else
    log_error "Missing AWS SQS permissions"
    log_error "Required permissions: sqs:ListQueues, sqs:CreateQueue, sqs:GetQueueUrl"
    return 1
  fi
}

# check_jq_installed
# Checks if jq is installed
#
# Returns:
#   0 - jq installed
#   1 - jq not installed
#
check_jq_installed() {
  if command -v jq &>/dev/null; then
    log_debug "jq is installed"
    return 0
  else
    log_error "jq is not installed. Please install jq: brew install jq"
    return 1
  fi
}

# ==============================================================================
# KMS KEY OPERATIONS
# ==============================================================================

# create_kms_key_for_sqs
# Creates KMS key for SQS queue encryption
#
# Arguments:
#   $1 - customer
#   $2 - project
#   $3 - environment
#   $4 - aws_region (optional, auto-detect if not provided)
#
# Returns:
#   0 - Success
#   1 - Failed to create key
#
# Output:
#   KMS Key ID (stdout)
#
# Example:
#   key_id=$(create_kms_key_for_sqs "customer" "project" "prod")
#
create_kms_key_for_sqs() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local aws_region="${4:-$(get_aws_region)}"
  
  local key_alias
  key_alias=$(get_kms_key_alias "$customer" "$project" "$environment")
  
  local description
  description=$(get_kms_key_description "$customer" "$project" "$environment")
  
  # Check if key already exists
  if kms_key_exists "$key_alias" "$aws_region"; then
    log_warning "KMS key already exists: $key_alias"
    get_kms_key_id "$key_alias" "$aws_region"
    return 0
  fi
  
  log_info "Creating KMS key: $key_alias"
  
  # Create key
  local key_id
  key_id=$(aws kms create-key \
    --description "$description" \
    --key-usage ENCRYPT_DECRYPT \
    --origin AWS_KMS \
    --region "$aws_region" \
    --tags \
      TagKey=forge.moai.io/customer,TagValue="$customer" \
      TagKey=forge.moai.io/project,TagValue="$project" \
      TagKey=forge.moai.io/environment,TagValue="$environment" \
      TagKey=forge.moai.io/managed-by,TagValue="forge-helpers" \
      TagKey=forge.moai.io/purpose,TagValue="sqs-encryption" \
    --query 'KeyMetadata.KeyId' \
    --output text 2>&1) || {
    log_error "Failed to create KMS key: $key_id"
    return 1
  }
  
  log_debug "KMS key created: $key_id"
  
  # Create alias
  log_debug "Creating KMS key alias: $key_alias"
  
  aws kms create-alias \
    --alias-name "$key_alias" \
    --target-key-id "$key_id" \
    --region "$aws_region" || {
    log_error "Failed to create KMS key alias"
    return 1
  }
  
  log_success "KMS key created: $key_id (alias: $key_alias)"
  echo "$key_id"
}

# get_kms_key_id
# Gets KMS key ID from alias
#
# Arguments:
#   $1 - key_alias (e.g., "alias/customer-project-prod-sqs-key")
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Key not found
#
# Output:
#   KMS Key ID
#
# Example:
#   key_id=$(get_kms_key_id "alias/customer-project-prod-sqs-key")
#
get_kms_key_id() {
  local key_alias="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Getting KMS key ID for alias: $key_alias"
  
  local key_id
  key_id=$(aws kms describe-key \
    --key-id "$key_alias" \
    --region "$aws_region" \
    --query 'KeyMetadata.KeyId' \
    --output text 2>&1) || {
    log_debug "KMS key not found: $key_alias"
    return 1
  }
  
  echo "$key_id"
}

# kms_key_exists
# Checks if KMS key exists by alias
#
# Arguments:
#   $1 - key_alias
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Key exists
#   1 - Key does not exist
#
# Example:
#   if kms_key_exists "alias/customer-project-prod-sqs-key"; then
#     echo "Key exists"
#   fi
#
kms_key_exists() {
  local key_alias="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  aws kms describe-key \
    --key-id "$key_alias" \
    --region "$aws_region" \
    --output text &>/dev/null
}

# delete_kms_key
# Schedules KMS key deletion
#
# Arguments:
#   $1 - key_id
#   $2 - pending_days (default: 30, minimum: 7)
#   $3 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to schedule deletion
#
# Example:
#   delete_kms_key "$key_id" 30
#
delete_kms_key() {
  local key_id="$1"
  local pending_days="${2:-30}"
  local aws_region="${3:-$(get_aws_region)}"
  
  log_warning "Scheduling KMS key deletion (${pending_days} days): $key_id"
  
  aws kms schedule-key-deletion \
    --key-id "$key_id" \
    --pending-window-in-days "$pending_days" \
    --region "$aws_region" || {
    log_error "Failed to schedule KMS key deletion"
    return 1
  }
  
  log_success "KMS key deletion scheduled (${pending_days} days)"
}

# ==============================================================================
# QUEUE OPERATIONS
# ==============================================================================

# create_fifo_queue
# Creates FIFO SQS queue with KMS encryption
#
# Arguments:
#   $1 - queue_name (must end with .fifo)
#   $2 - kms_key_id
#   $3 - aws_region (optional)
#   $4 - retention_period (default: 345600 = 4 days)
#   $5 - visibility_timeout (default: 30 seconds)
#   $6 - content_based_dedup (default: "true")
#
# Returns:
#   0 - Success
#   1 - Failed to create queue
#
# Output:
#   Queue URL (stdout)
#
# Example:
#   queue_url=$(create_fifo_queue "my-queue.fifo" "$kms_key_id")
#
create_fifo_queue() {
  local queue_name="$1"
  local kms_key_id="$2"
  local aws_region="${3:-$(get_aws_region)}"
  local retention="${4:-345600}"      # 4 days
  local visibility="${5:-30}"         # 30 seconds
  local dedup="${6:-true}"            # content-based deduplication
  
  # Validate queue name
  if ! is_valid_queue_name "$queue_name" "true"; then
    log_error "Invalid FIFO queue name: $queue_name"
    return 1
  fi
  
  log_info "Creating FIFO queue: $queue_name"
  
  # Build attributes JSON
  local attributes
  attributes=$(jq -n \
    --arg retention "$retention" \
    --arg visibility "$visibility" \
    --arg dedup "$dedup" \
    --arg kms "$kms_key_id" \
    '{
      FifoQueue: "true",
      ContentBasedDeduplication: $dedup,
      MessageRetentionPeriod: $retention,
      VisibilityTimeout: $visibility,
      KmsMasterKeyId: $kms,
      KmsDataKeyReusePeriodSeconds: "300"
    }')
  
  # Create queue
  local queue_url
  queue_url=$(aws sqs create-queue \
    --queue-name "$queue_name" \
    --attributes "$attributes" \
    --region "$aws_region" \
    --output text 2>&1) || {
    log_error "Failed to create queue: $queue_url"
    return 1
  }
  
  log_success "FIFO queue created: $queue_url"
  echo "$queue_url"
}

# delete_queue
# Deletes SQS queue
#
# Arguments:
#   $1 - queue_url
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to delete queue
#
# Example:
#   delete_queue "$queue_url"
#
delete_queue() {
  local queue_url="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_info "Deleting queue: $queue_url"
  
  aws sqs delete-queue \
    --queue-url "$queue_url" \
    --region "$aws_region" || {
    log_error "Failed to delete queue"
    return 1
  }
  
  log_success "Queue deleted"
}

# purge_queue
# Purges all messages from queue
#
# Arguments:
#   $1 - queue_url
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to purge queue
#
# Example:
#   purge_queue "$queue_url"
#
purge_queue() {
  local queue_url="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_warning "Purging all messages from queue: $queue_url"
  
  aws sqs purge-queue \
    --queue-url "$queue_url" \
    --region "$aws_region" || {
    log_error "Failed to purge queue"
    return 1
  }
  
  log_success "Queue purged"
}

# get_queue_url
# Gets queue URL by name
#
# Arguments:
#   $1 - queue_name
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Queue not found
#
# Output:
#   Queue URL
#
# Example:
#   queue_url=$(get_queue_url "my-queue.fifo")
#
get_queue_url() {
  local queue_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  aws sqs get-queue-url \
    --queue-name "$queue_name" \
    --region "$aws_region" \
    --query 'QueueUrl' \
    --output text 2>&1
}

# get_queue_arn
# Gets queue ARN from URL
#
# Arguments:
#   $1 - queue_url
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to get ARN
#
# Output:
#   Queue ARN
#
# Example:
#   queue_arn=$(get_queue_arn "$queue_url")
#
get_queue_arn() {
  local queue_url="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  aws sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --attribute-names QueueArn \
    --region "$aws_region" \
    --query 'Attributes.QueueArn' \
    --output text 2>&1
}

# get_queue_attributes
# Gets all queue attributes
#
# Arguments:
#   $1 - queue_url
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to get attributes
#
# Output:
#   JSON with all attributes
#
# Example:
#   attributes=$(get_queue_attributes "$queue_url")
#
get_queue_attributes() {
  local queue_url="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  aws sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --attribute-names All \
    --region "$aws_region" \
    --output json 2>&1
}

# ==============================================================================
# POLICY OPERATIONS
# ==============================================================================

# generate_merged_queue_policy
# Generates SQS queue policy with separate statements for different access types
# Groups services by access type (producer/consumer) and creates appropriate statements
#
# Arguments:
#   $1 - queue_arn
#   $2...$N - service specifications in format "service-name:access-type:irsa-role-arn"
#
# Returns:
#   0 - Success
#   1 - Failed to generate policy
#
# Output:
#   JSON policy document (stdout)
#
# Example:
#   policy=$(generate_merged_queue_policy "$queue_arn" \
#     "application:consumer:arn:aws:iam::123:role/Role1" \
#     "agent:producer:arn:aws:iam::123:role/Role2")
#
generate_merged_queue_policy() {
  local queue_arn="$1"
  shift
  
  # Arrays to group services by access type
  local producer_arns=()
  local consumer_arns=()
  
  # Parse service specifications
  for service_spec in "$@"; do
    IFS=':' read -r service_name access_type irsa_arn <<< "$service_spec"
    
    if [[ "$access_type" == "producer" ]]; then
      producer_arns+=("$irsa_arn")
    elif [[ "$access_type" == "consumer" ]]; then
      consumer_arns+=("$irsa_arn")
    else
      log_error "Invalid access type for $service_name: $access_type"
      return 1
    fi
  done
  
  # Start building policy
  local policy='{"Version":"2012-10-17","Statement":[]}'
  
  # Add producer statement if there are any producers
  if [[ ${#producer_arns[@]} -gt 0 ]]; then
    local producer_principals='[]'
    for arn in "${producer_arns[@]}"; do
      producer_principals=$(echo "$producer_principals" | jq --arg arn "$arn" '. += [$arn]')
    done
    
    local producer_statement
    producer_statement=$(jq -n \
      --arg queue_arn "$queue_arn" \
      --argjson principals "$producer_principals" \
      '{
        Sid: "AllowProducerAccess",
        Effect: "Allow",
        Principal: {
          AWS: $principals
        },
        Action: [
          "SQS:SendMessage",
          "SQS:GetQueueUrl",
          "SQS:GetQueueAttributes"
        ],
        Resource: $queue_arn
      }')
    
    policy=$(echo "$policy" | jq --argjson stmt "$producer_statement" '.Statement += [$stmt]')
  fi
  
  # Add consumer statement if there are any consumers
  if [[ ${#consumer_arns[@]} -gt 0 ]]; then
    local consumer_principals='[]'
    for arn in "${consumer_arns[@]}"; do
      consumer_principals=$(echo "$consumer_principals" | jq --arg arn "$arn" '. += [$arn]')
    done
    
    local consumer_statement
    consumer_statement=$(jq -n \
      --arg queue_arn "$queue_arn" \
      --argjson principals "$consumer_principals" \
      '{
        Sid: "AllowConsumerAccess",
        Effect: "Allow",
        Principal: {
          AWS: $principals
        },
        Action: [
          "SQS:ReceiveMessage",
          "SQS:DeleteMessage",
          "SQS:GetQueueUrl",
          "SQS:GetQueueAttributes",
          "SQS:ChangeMessageVisibility"
        ],
        Resource: $queue_arn
      }')
    
    policy=$(echo "$policy" | jq --argjson stmt "$consumer_statement" '.Statement += [$stmt]')
  fi
  
  echo "$policy"
}

# generate_queue_policy_document
# Generates SQS queue policy for IRSA roles (LEGACY - use generate_merged_queue_policy)
#
# Arguments:
#   $1 - queue_arn
#   $2 - access_type ("producer" or "consumer")
#   $3 - irsa_role_arns (comma-separated)
#   $4 - aws_account_id
#
# Returns:
#   0 - Success
#   1 - Failed to generate policy
#
# Output:
#   JSON policy document (stdout)
#
# Example:
#   policy=$(generate_queue_policy_document "$queue_arn" "consumer" "$irsa_arns" "$account_id")
#
generate_queue_policy_document() {
  local queue_arn="$1"
  local access_type="$2"
  local irsa_roles="$3"
  local aws_account_id="$4"
  
  log_debug "Generating $access_type policy for queue: $queue_arn"
  
  # Split IRSA roles by comma and build JSON array
  IFS=',' read -ra ROLES <<< "$irsa_roles"
  
  local principals='[]'
  for role_arn in "${ROLES[@]}"; do
    principals=$(echo "$principals" | jq --arg arn "$role_arn" '. += [$arn]')
  done
  
  # Define actions based on access type
  local actions
  if [[ "$access_type" == "producer" ]]; then
    actions='["SQS:SendMessage","SQS:GetQueueUrl","SQS:GetQueueAttributes"]'
  elif [[ "$access_type" == "consumer" ]]; then
    actions='["SQS:ReceiveMessage","SQS:DeleteMessage","SQS:GetQueueUrl","SQS:GetQueueAttributes","SQS:ChangeMessageVisibility"]'
  else
    log_error "Invalid access type: $access_type (must be producer or consumer)"
    return 1
  fi
  
  # Build policy document
  jq -n \
    --arg queue_arn "$queue_arn" \
    --argjson principals "$principals" \
    --argjson actions "$actions" \
    '{
      Version: "2012-10-17",
      Statement: [
        {
          Sid: "AllowIRSAAccess",
          Effect: "Allow",
          Principal: {
            AWS: $principals
          },
          Action: $actions,
          Resource: $queue_arn
        }
      ]
    }'
}

# attach_queue_policy
# Attaches policy to SQS queue
#
# Arguments:
#   $1 - queue_url
#   $2 - policy_document (JSON string)
#   $3 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to attach policy
#
# Example:
#   attach_queue_policy "$queue_url" "$policy_doc"
#
attach_queue_policy() {
  local queue_url="$1"
  local policy_document="$2"
  local aws_region="${3:-$(get_aws_region)}"
  
  log_info "Attaching policy to queue..."
  
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_dry_run "Would attach policy to queue: $queue_url"
    log_debug "Policy document:"
    echo "$policy_document" | jq '.' >&2
    return 0
  fi
  
  # Use temporary file to avoid shell quoting issues with complex JSON
  local tmp_attributes_file="/tmp/sqs-attributes-$$.json"
  
  # Compact the policy JSON first, then create attributes JSON
  # AWS CLI expects attributes to be a JSON map where Policy value is a compact JSON string
  local compact_policy
  compact_policy=$(echo "$policy_document" | jq -c '.')
  
  log_debug "Policy document length: ${#policy_document}"
  log_debug "Compact policy length: ${#compact_policy}"
  
  jq -n --arg policy "$compact_policy" '{Policy: $policy}' > "$tmp_attributes_file" || {
    log_error "Failed to create attributes document"
    rm -f "$tmp_attributes_file"
    return 1
  }
  
  log_debug "Attributes file: $tmp_attributes_file"
  log_debug "Attributes content:"
  cat "$tmp_attributes_file" >&2
  
  # Pass attributes as JSON file using file:// protocol
  log_debug "Running: aws sqs set-queue-attributes --queue-url $queue_url --attributes file://$tmp_attributes_file --region $aws_region"
  log_debug "File exists check: $(test -f "$tmp_attributes_file" && echo YES || echo NO)"
  log_debug "File size: $(wc -c < "$tmp_attributes_file" 2>/dev/null || echo 0)"
  
  aws sqs set-queue-attributes \
    --queue-url "$queue_url" \
    --attributes "file://$tmp_attributes_file" \
    --region "$aws_region"
  
  local exit_code=$?
  
  # Cleanup temp file
  rm -f "$tmp_attributes_file"
  
  if [[ $exit_code -ne 0 ]]; then
    log_error "Failed to attach policy"
    return 1
  fi
  
  log_success "Policy attached to queue"
}

# get_current_policy
# Gets current queue policy
#
# Arguments:
#   $1 - queue_url
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - No policy or error
#
# Output:
#   JSON policy document
#
# Example:
#   current_policy=$(get_current_policy "$queue_url")
#
get_current_policy() {
  local queue_url="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  local policy
  policy=$(aws sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --attribute-names Policy \
    --region "$aws_region" \
    --query 'Attributes.Policy' \
    --output text 2>&1)
  
  if [[ "$policy" == "None" ]] || [[ -z "$policy" ]]; then
    echo '{}'
    return 1
  fi
  
  echo "$policy"
}

# add_irsa_to_policy
# Adds IRSA role to existing queue policy
#
# Arguments:
#   $1 - queue_url
#   $2 - new_irsa_arn
#   $3 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to update policy
#
# Example:
#   add_irsa_to_policy "$queue_url" "arn:aws:iam::123456:role/my-role"
#
add_irsa_to_policy() {
  local queue_url="$1"
  local new_irsa_arn="$2"
  local aws_region="${3:-$(get_aws_region)}"
  
  log_info "Adding IRSA role to queue policy: $new_irsa_arn"
  
  # Get current policy
  local current_policy
  current_policy=$(get_current_policy "$queue_url" "$aws_region")
  
  # Add new principal (deduplicate)
  local updated_policy
  updated_policy=$(echo "$current_policy" | jq \
    --arg arn "$new_irsa_arn" \
    '.Statement[0].Principal.AWS += [$arn] | .Statement[0].Principal.AWS |= unique')
  
  # Attach updated policy
  attach_queue_policy "$queue_url" "$updated_policy" "$aws_region"
}

# remove_irsa_from_policy
# Removes IRSA role from queue policy
#
# Arguments:
#   $1 - queue_url
#   $2 - irsa_arn_to_remove
#   $3 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to update policy
#
# Example:
#   remove_irsa_from_policy "$queue_url" "arn:aws:iam::123456:role/my-role"
#
remove_irsa_from_policy() {
  local queue_url="$1"
  local irsa_arn="$2"
  local aws_region="${3:-$(get_aws_region)}"
  
  log_info "Removing IRSA role from queue policy: $irsa_arn"
  
  # Get current policy
  local current_policy
  current_policy=$(get_current_policy "$queue_url" "$aws_region")
  
  # Remove principal
  local updated_policy
  updated_policy=$(echo "$current_policy" | jq \
    --arg arn "$irsa_arn" \
    '.Statement[0].Principal.AWS -= [$arn]')
  
  # Attach updated policy
  attach_queue_policy "$queue_url" "$updated_policy" "$aws_region"
}

# ==============================================================================
# TESTING OPERATIONS
# ==============================================================================

# send_test_message
# Sends test message to FIFO queue
#
# Arguments:
#   $1 - queue_url
#   $2 - message_body
#   $3 - message_group_id (default: "test-group")
#   $4 - message_deduplication_id (optional, for FIFO queues)
#   $5 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to send message
#
# Output:
#   Message ID (stdout)
#
# Example:
#   msg_id=$(send_test_message "$queue_url" '{"test":true}' "group-1" "dedup-123")
#
send_test_message() {
  local queue_url="$1"
  local message_body="$2"
  local message_group_id="${3:-test-group}"
  local message_deduplication_id="$4"
  local aws_region="${5:-$(get_aws_region)}"
  
  log_info "Sending test message to queue..."
  
  local message_id
  local cmd="aws sqs send-message \
    --queue-url \"$queue_url\" \
    --message-body \"$message_body\" \
    --message-group-id \"$message_group_id\""
  
  # Add deduplication ID if provided (for FIFO queues)
  if [[ -n "$message_deduplication_id" ]]; then
    cmd="$cmd --message-deduplication-id \"$message_deduplication_id\""
  fi
  
  cmd="$cmd --region \"$aws_region\" --query 'MessageId' --output text"
  
  message_id=$(eval $cmd 2>&1) || {
    log_error "Failed to send message: $message_id"
    return 1
  }
  
  log_success "Test message sent: $message_id"
  echo "$message_id"
}

# receive_test_message
# Receives messages from queue
#
# Arguments:
#   $1 - queue_url
#   $2 - max_messages (default: 1)
#   $3 - wait_time_seconds (default: 20, long polling)
#   $4 - aws_region (optional)
#
# Returns:
#   0 - Success (messages received)
#   1 - No messages or error
#
# Output:
#   JSON with messages
#
# Example:
#   messages=$(receive_test_message "$queue_url" 10 20)
#
receive_test_message() {
  local queue_url="$1"
  local max_messages="${2:-1}"
  local wait_time="${3:-20}"
  local aws_region="${4:-$(get_aws_region)}"
  
  log_info "Receiving messages from queue (long polling: ${wait_time}s)..."
  
  local messages
  messages=$(aws sqs receive-message \
    --queue-url "$queue_url" \
    --max-number-of-messages "$max_messages" \
    --wait-time-seconds "$wait_time" \
    --region "$aws_region" \
    --output json 2>&1) || {
    log_error "Failed to receive messages: $messages"
    return 1
  }
  
  local count
  count=$(echo "$messages" | jq '.Messages | length')
  
  if [[ "$count" -eq 0 ]]; then
    log_warning "No messages received"
    return 1
  fi
  
  log_success "Received $count message(s)"
  echo "$messages"
}

# ==============================================================================
# SSM OPERATIONS
# ==============================================================================

# store_queue_url_in_ssm
# Stores queue URL in SSM Parameter Store
#
# Arguments:
#   $1 - ssm_path
#   $2 - queue_url
#   $3 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to store parameter
#
# Example:
#   store_queue_url_in_ssm "/sqs/customer/project/prod/events/queue-url" "$queue_url"
#
store_queue_url_in_ssm() {
  local ssm_path="$1"
  local queue_url="$2"
  local aws_region="${3:-$(get_aws_region)}"
  
  log_info "Storing queue URL in SSM: $ssm_path"
  
  put_ssm_parameter "$ssm_path" "$queue_url" "String" "Queue URL for SQS" "$aws_region"
}

# store_kms_key_id_in_ssm
# Stores KMS key ID in SSM Parameter Store
#
# Arguments:
#   $1 - ssm_path
#   $2 - kms_key_id
#   $3 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Failed to store parameter
#
# Example:
#   store_kms_key_id_in_ssm "/sqs/customer/project/prod/kms-key-id" "$kms_key_id"
#
store_kms_key_id_in_ssm() {
  local ssm_path="$1"
  local kms_key_id="$2"
  local aws_region="${3:-$(get_aws_region)}"
  
  log_info "Storing KMS key ID in SSM: $ssm_path"
  
  put_ssm_parameter "$ssm_path" "$kms_key_id" "String" "KMS key ID for SQS encryption" "$aws_region"
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Prerequisites
export -f check_aws_sqs_permissions check_jq_installed

# KMS operations
export -f create_kms_key_for_sqs get_kms_key_id kms_key_exists delete_kms_key

# Queue operations
export -f create_fifo_queue delete_queue purge_queue
export -f get_queue_url get_queue_arn get_queue_attributes

# Policy operations
export -f generate_queue_policy_document attach_queue_policy get_current_policy
export -f add_irsa_to_policy remove_irsa_from_policy

# Testing operations
export -f send_test_message receive_test_message

# SSM operations
export -f store_queue_url_in_ssm store_kms_key_id_in_ssm

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-sqs-operations.sh v${FORGE_SQS_OPERATIONS_VERSION}"
