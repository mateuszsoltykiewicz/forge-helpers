#!/usr/bin/env bash
# ==============================================================================
# Forge Patterns Library
# ==============================================================================
# Description: Forge naming conventions and pattern builders
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - Kubernetes naming patterns (namespace, ServiceAccount, labels)
# - AWS naming patterns (ECR, IRSA, S3, SSM)
# - Database naming patterns (PostgreSQL)
# - Vault naming patterns (secret paths, policies, roles)
# - Resource labeling and tagging patterns
# - Path builders and formatters
#
# Usage:
#   source /path/to/forge-patterns.sh
#   namespace=$(get_namespace_name "sanofi" "cronus" "dev" "video-calling-agent")
#   ecr_repo=$(get_ecr_repository_name "sanofi" "cronus" "dev" "video-calling-agent")
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_PATTERNS_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_PATTERNS_VERSION="1.0.0"
readonly FORGE_PATTERNS_LOADED="true"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Get script directory (only if not already set)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source forge-core if available (optional dependency)
if [[ -f "${SCRIPT_DIR}/forge-core.sh" ]]; then
  source "${SCRIPT_DIR}/forge-core.sh"
else
  # Fallback: define minimal logging functions
  log_debug() { echo "[DEBUG] $*" >&2; }
  to_pascal_case() { echo "$1" | awk -F'[-_ ]' '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1)) tolower(substr($i,2))}'; }
  to_snake_case() { echo "$1" | tr '-' '_'; }
fi

# ==============================================================================
# KUBERNETES NAMING PATTERNS
# ==============================================================================

# get_namespace_name
# Builds Kubernetes namespace name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}
#
# Arguments:
#   $1 - Customer name (e.g., sanofi, indegene)
#   $2 - Project name (e.g., cronus, platform)
#   $3 - Environment (e.g., dev, staging, prod)
#   $4 - Service name (e.g., video-calling-agent)
#
# Output:
#   Namespace name to stdout
#
# Example:
#   get_namespace_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi-cronus-dev-video-calling-agent
#
get_namespace_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}-${project}-${environment}-${service_name}"
}

# get_service_account_name
# Builds ServiceAccount name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}-sa
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   ServiceAccount name to stdout
#
# Example:
#   get_service_account_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi-cronus-dev-video-calling-agent-sa
#
get_service_account_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}-${project}-${environment}-${service_name}-sa"
}

# get_deployment_name
# Builds Deployment name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   Deployment name to stdout
#
# Example:
#   get_deployment_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi-cronus-dev-video-calling-agent
#
get_deployment_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}-${project}-${environment}-${service_name}"
}

# get_service_name
# Builds Kubernetes Service name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   Service name to stdout
#
# Example:
#   get_service_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi-cronus-dev-video-calling-agent
#
get_service_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}-${project}-${environment}-${service_name}"
}

# get_configmap_name
# Builds ConfigMap name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}-{suffix}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - (optional) Suffix (e.g., config, env)
#
# Output:
#   ConfigMap name to stdout
#
# Example:
#   get_configmap_name "sanofi" "cronus" "dev" "video-calling-agent" "config"
#   # Output: sanofi-cronus-dev-video-calling-agent-config
#
get_configmap_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local suffix="${5:-}"
  
  local base="${customer}-${project}-${environment}-${service_name}"
  
  if [[ -n "$suffix" ]]; then
    echo "${base}-${suffix}"
  else
    echo "$base"
  fi
}

# get_secret_name
# Builds Secret name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}-{suffix}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - (optional) Suffix (e.g., credentials, tls)
#
# Output:
#   Secret name to stdout
#
# Example:
#   get_secret_name "sanofi" "cronus" "dev" "video-calling-agent" "credentials"
#   # Output: sanofi-cronus-dev-video-calling-agent-credentials
#
get_secret_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local suffix="${5:-}"
  
  local base="${customer}-${project}-${environment}-${service_name}"
  
  if [[ -n "$suffix" ]]; then
    echo "${base}-${suffix}"
  else
    echo "$base"
  fi
}

# ==============================================================================
# KUBERNETES LABELS
# ==============================================================================

# get_forge_labels
# Builds standard Forge labels for Kubernetes resources
# Returns label key-value pairs suitable for kubectl --labels
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - (optional) Additional labels (key1=value1,key2=value2)
#
# Output:
#   Comma-separated labels to stdout
#
# Example:
#   labels=$(get_forge_labels "sanofi" "cronus" "dev" "video-calling-agent")
#   # Output: forge.moai.io/customer=sanofi,forge.moai.io/project=cronus,...
#
get_forge_labels() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local additional="${5:-}"
  
  local labels="forge.moai.io/customer=${customer}"
  labels+=",forge.moai.io/project=${project}"
  labels+=",forge.moai.io/environment=${environment}"
  labels+=",forge.moai.io/service=${service_name}"
  labels+=",app.kubernetes.io/name=${service_name}"
  labels+=",app.kubernetes.io/instance=${customer}-${project}-${environment}"
  labels+=",app.kubernetes.io/managed-by=forge"
  
  if [[ -n "$additional" ]]; then
    labels+=",${additional}"
  fi
  
  echo "$labels"
}

# auto_detect_service_name
# Automatically detects service name from directory or git remote
# Detection methods (in order of precedence):
#   1. Directory name (current working directory)
#   2. Git remote origin URL
#
# Arguments:
#   None (uses current directory and git context)
#
# Output:
#   Detected service name to stdout
#
# Exit Codes:
#   0 - Service name detected successfully
#   1 - Detection failed
#
# Example:
#   service=$(auto_detect_service_name)
#   # In /path/to/video-calling-agent: "video-calling-agent"
auto_detect_service_name() {
  local service_name=""
  
  # Method 1: Use directory name
  service_name=$(basename "$(pwd)")
  
  # Validate detected name
  if [[ -n "$service_name" ]] && validate_service_name "$service_name"; then
    echo "$service_name"
    return 0
  fi
  
  # Method 2: Try git remote origin
  if command -v git &> /dev/null && git rev-parse --git-dir &> /dev/null; then
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    
    if [[ -n "$remote_url" ]]; then
      # Extract repository name from various URL formats:
      # - https://github.com/org/repo.git
      # - git@github.com:org/repo.git
      # - https://gitlab.com/org/repo
      service_name=$(echo "$remote_url" | sed -E 's#.*/([^/]+)(\.git)?$#\1#' | sed 's/\.git$//')
      
      if [[ -n "$service_name" ]] && validate_service_name "$service_name"; then
        echo "$service_name"
        return 0
      fi
    fi
  fi
  
  log_error "Failed to auto-detect service name"
  return 1
}

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

# validate_customer_name
# Validates customer name against Forge naming conventions
# Rules:
#   - Must contain only lowercase letters, numbers, and hyphens
#   - Must start and end with alphanumeric character
#   - Length between 2 and 63 characters
#
# Arguments:
#   $1 - Customer name to validate
#
# Exit Codes:
#   0 - Valid customer name
#   1 - Invalid customer name
#
# Example:
#   validate_customer_name "sanofi"  # Returns 0
#   validate_customer_name "123"     # Returns 1
validate_customer_name() {
  local name="$1"
  
  # Check length
  if [[ ${#name} -lt 2 ]] || [[ ${#name} -gt 63 ]]; then
    return 1
  fi
  
  # Check format: lowercase alphanumeric and hyphens only
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z0-9]+$ ]]; then
    return 1
  fi
  
  # Check for consecutive hyphens
  if [[ "$name" =~ -- ]]; then
    return 1
  fi
  
  return 0
}

# validate_project_name
# Validates project name against Forge naming conventions
# Rules:
#   - Must contain only lowercase letters, numbers, and hyphens
#   - Must start and end with alphanumeric character
#   - Length between 2 and 63 characters
#
# Arguments:
#   $1 - Project name to validate
#
# Exit Codes:
#   0 - Valid project name
#   1 - Invalid project name
#
# Example:
#   validate_project_name "cronus"  # Returns 0
validate_project_name() {
  local name="$1"
  
  # Check length
  if [[ ${#name} -lt 2 ]] || [[ ${#name} -gt 63 ]]; then
    return 1
  fi
  
  # Check format: lowercase alphanumeric and hyphens only
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z0-9]+$ ]]; then
    return 1
  fi
  
  # Check for consecutive hyphens
  if [[ "$name" =~ -- ]]; then
    return 1
  fi
  
  return 0
}

# validate_environment_name
# Validates environment name against Forge naming conventions
# Rules:
#   - Must be one of: dev, staging, prod, demo, test
#   - Lowercase only
#
# Arguments:
#   $1 - Environment name to validate
#
# Exit Codes:
#   0 - Valid environment name
#   1 - Invalid environment name
#
# Example:
#   validate_environment_name "dev"   # Returns 0
#   validate_environment_name "prod"  # Returns 0
#   validate_environment_name "foo"   # Returns 1
validate_environment_name() {
  local name="$1"
  
  case "$name" in
    dev|staging|prod|demo|test)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# validate_service_name
# Validates service name against Forge naming conventions
# Rules:
#   - Must contain only lowercase letters, numbers, and hyphens
#   - Must start and end with alphanumeric character
#   - Length between 3 and 63 characters
#
# Arguments:
#   $1 - Service name to validate
#
# Exit Codes:
#   0 - Valid service name
#   1 - Invalid service name
#
# Example:
#   validate_service_name "video-calling-agent"  # Returns 0
#   validate_service_name "-invalid-name-"       # Returns 1
validate_service_name() {
  local name="$1"
  
  # Check length
  if [[ ${#name} -lt 3 ]] || [[ ${#name} -gt 63 ]]; then
    return 1
  fi
  
  # Check format: lowercase alphanumeric and hyphens only, 
  # must start and end with alphanumeric
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
    # Special case: single-segment names (3 chars, no hyphens)
    if [[ ! "$name" =~ ^[a-z0-9]+$ ]]; then
      return 1
    fi
  fi
  
  # Check for consecutive hyphens (not allowed in Kubernetes)
  if [[ "$name" =~ -- ]]; then
    return 1
  fi
  
  return 0
}

# ==============================================================================
# AWS NAMING PATTERNS
# ==============================================================================

# get_ecr_repository_name
# Builds ECR repository name following Forge convention
# Pattern: {customer}/{project}/{environment}/{service-name}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   ECR repository name to stdout
#
# Example:
#   get_ecr_repository_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi/cronus/dev/video-calling-agent
#
get_ecr_repository_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}/${project}/${environment}/${service_name}"
}

# get_ecr_registry_url
# Builds ECR registry URL
# Pattern: {account-id}.dkr.ecr.{region}.amazonaws.com
#
# Arguments:
#   $1 - AWS Account ID
#   $2 - AWS Region
#
# Output:
#   ECR registry URL to stdout
#
# Example:
#   get_ecr_registry_url "398456183268" "eu-central-1"
#   # Output: 398456183268.dkr.ecr.eu-central-1.amazonaws.com
#
get_ecr_registry_url() {
  local account_id="$1"
  local region="$2"
  
  echo "${account_id}.dkr.ecr.${region}.amazonaws.com"
}

# get_ecr_image_uri
# Builds complete ECR image URI
# Pattern: {account-id}.dkr.ecr.{region}.amazonaws.com/{repository}:{tag}
#
# Arguments:
#   $1 - AWS Account ID
#   $2 - AWS Region
#   $3 - Customer name
#   $4 - Project name
#   $5 - Environment
#   $6 - Service name
#   $7 - Image tag
#
# Output:
#   Complete ECR image URI to stdout
#
# Example:
#   get_ecr_image_uri "398456183268" "eu-central-1" "sanofi" "cronus" "dev" "video-calling-agent" "abc123f"
#   # Output: 398456183268.dkr.ecr.eu-central-1.amazonaws.com/sanofi/cronus/dev/video-calling-agent:abc123f
#
get_ecr_image_uri() {
  local account_id="$1"
  local region="$2"
  local customer="$3"
  local project="$4"
  local environment="$5"
  local service_name="$6"
  local tag="$7"
  
  local registry=$(get_ecr_registry_url "$account_id" "$region")
  local repository=$(get_ecr_repository_name "$customer" "$project" "$environment" "$service_name")
  
  echo "${registry}/${repository}:${tag}"
}

# get_irsa_role_name
# Builds IRSA IAM role name following Forge convention
# Pattern: {Customer}{Project}{Environment}{ServiceName}Irsa (PascalCase)
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name (hyphenated)
#
# Output:
#   IRSA role name to stdout
#
# Example:
#   get_irsa_role_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: SanofiCronusDevVideoCallingAgentIrsa
#
get_irsa_role_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  local customer_pascal=$(to_pascal_case "$customer")
  local project_pascal=$(to_pascal_case "$project")
  local env_pascal=$(to_pascal_case "$environment")
  local service_pascal=$(to_pascal_case "$service_name")
  
  echo "${customer_pascal}${project_pascal}${env_pascal}${service_pascal}Irsa"
}

# get_irsa_policy_name
# Builds IRSA IAM policy name following Forge convention
# Pattern: {IrsaRoleName}Policy
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   IRSA policy name to stdout
#
# Example:
#   get_irsa_policy_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: SanofiCronusDevVideoCallingAgentIrsaPolicy
#
get_irsa_policy_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "$(get_irsa_role_name "$customer" "$project" "$environment" "$service_name")Policy"
}

# get_s3_bucket_name
# Builds S3 bucket name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}-{suffix}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - (optional) Suffix (e.g., recordings, backups, uploads)
#
# Output:
#   S3 bucket name to stdout
#
# Example:
#   get_s3_bucket_name "sanofi" "cronus" "dev" "video-calling" "recordings"
#   # Output: sanofi-cronus-dev-video-calling-recordings
#
get_s3_bucket_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local suffix="${5:-}"
  
  local base="${customer}-${project}-${environment}-${service_name}"
  
  if [[ -n "$suffix" ]]; then
    echo "${base}-${suffix}"
  else
    echo "$base"
  fi
}

# ==============================================================================
# SSM PARAMETER STORE PATTERNS
# ==============================================================================

# get_ssm_base_path
# Builds base SSM path for a service (without parameter name)
# Pattern: /{customer}/{project}/{environment}/{service-name}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   SSM base path to stdout
#
# Example:
#   get_ssm_base_path "sanofi" "cronus" "dev" "video-calling"
#   # Output: /sanofi/cronus/dev/video-calling
#
get_ssm_base_path() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "/${customer}/${project}/${environment}/${service_name}"
}

# get_ssm_parameter_path
# Builds SSM Parameter Store path following Forge convention
# Pattern: /{customer}/{project}/{environment}/{service-name}/{parameter-name}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Parameter name (e.g., db-password, api-key)
#
# Output:
#   SSM parameter path to stdout
#
# Example:
#   get_ssm_parameter_path "sanofi" "cronus" "dev" "video-calling-agent" "livekit-api-key"
#   # Output: /sanofi/cronus/dev/video-calling-agent/livekit-api-key
#
get_ssm_parameter_path() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local parameter_name="$5"
  
  echo "/${customer}/${project}/${environment}/${service_name}/${parameter_name}"
}

# ==============================================================================
# KMS KEY NAMING PATTERNS
# ==============================================================================

# get_kms_key_alias_path
# Builds KMS key alias following Forge convention
# Pattern: alias/{customer}/{project}/{environment}/{service-name}/{purpose}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose (e.g., "encryption", "signing", "data", "secrets")
#
# Output:
#   KMS key alias to stdout
#
# Example:
#   get_kms_key_alias_path "sanofi" "cronus" "dev" "video-calling" "encryption"
#   # Output: alias/sanofi/cronus/dev/video-calling/encryption
#
get_kms_key_alias_path() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  
  echo "alias/${customer}/${project}/${environment}/${service_name}/${purpose}"
}

# get_kms_key_description
# Builds KMS key description following Forge convention
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose
#
# Output:
#   KMS key description to stdout
#
# Example:
#   get_kms_key_description "sanofi" "cronus" "dev" "video-calling" "encryption"
#   # Output: KMS key for sanofi-cronus-dev-video-calling (purpose: encryption)
#
get_kms_key_description() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  
  echo "KMS key for ${customer}-${project}-${environment}-${service_name} (purpose: ${purpose})"
}

# get_kms_key_tags
# Builds tags for KMS key following Forge convention
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Purpose
#
# Output:
#   Space-separated tag key=value pairs for AWS CLI
#
# Example:
#   get_kms_key_tags "sanofi" "cronus" "dev" "video-calling" "encryption"
#
get_kms_key_tags() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local purpose="$5"
  
  echo "Customer=${customer} Project=${project} Environment=${environment} Service=${service_name} Purpose=${purpose} ManagedBy=forge-helpers"
}

# get_kms_key_policy
# Builds KMS key policy JSON with root access and IRSA role access
#
# Arguments:
#   $1 - AWS Account ID
#   $2 - Customer name
#   $3 - Project name
#   $4 - Environment
#   $5 - Service name
#   $6 - AWS Region
#
# Output:
#   JSON key policy to stdout
#
# Example:
#   policy=$(get_kms_key_policy "123456789012" "sanofi" "cronus" "dev" "video-calling" "eu-central-1")
#
get_kms_key_policy() {
  local account_id="$1"
  local customer="$2"
  local project="$3"
  local environment="$4"
  local service_name="$5"
  local region="$6"
  
  local irsa_role_name
  irsa_role_name=$(get_irsa_role_name "$customer" "$project" "$environment" "$service_name")
  
  cat <<EOF
{
  "Version": "2012-10-17",
  "Id": "kms-key-policy-${customer}-${project}-${environment}-${service_name}",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow IRSA Role to use the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${account_id}:role/${irsa_role_name}"
      },
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:DescribeKey",
        "kms:CreateGrant",
        "kms:RetireGrant",
        "kms:ReEncrypt*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow attachment of persistent resources",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${account_id}:role/${irsa_role_name}"
      },
      "Action": [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "kms:GrantIsForAWSResource": "true"
        }
      }
    }
  ]
}
EOF
}

# get_aws_tags
# Builds AWS resource tags following Forge convention
# Returns tag key-value pairs suitable for AWS CLI --tags
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - (optional) Additional tags (Key1=Value1,Key2=Value2)
#
# Output:
#   Space-separated tags to stdout (Key=Value format)
#
# Example:
#   tags=$(get_aws_tags "sanofi" "cronus" "dev" "video-calling-agent")
#   # Output: Customer=sanofi Project=cronus Environment=dev Service=video-calling-agent ManagedBy=forge
#
get_aws_tags() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local additional="${5:-}"
  
  local tags="Customer=${customer} Project=${project} Environment=${environment} Service=${service_name} ManagedBy=forge"
  
  if [[ -n "$additional" ]]; then
    tags+=" ${additional}"
  fi
  
  echo "$tags"
}

# ==============================================================================
# DATABASE NAMING PATTERNS
# ==============================================================================

# get_database_name
# Builds PostgreSQL database name following Forge convention
# Pattern: {customer}_{project}_{environment}_{service}_db[_{suffix}]
# All hyphens are replaced with underscores
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - (optional) Custom suffix (e.g., "recordings")
#
# Output:
#   Database name to stdout
#
# Example:
#   get_database_name "sanofi" "cronus" "prod" "videocalling"
#   # Output: sanofi_cronus_prod_videocalling_db
#
#   get_database_name "sanofi" "cronus" "prod" "videocalling" "recordings"
#   # Output: sanofi_cronus_prod_videocalling_recordings_db
#
get_database_name() {
  local customer=$(to_snake_case "$1")
  local project=$(to_snake_case "$2")
  local environment=$(to_snake_case "$3")
  local service=$(to_snake_case "$4")
  local suffix="${5:-}"
  
  if [[ -n "${suffix}" ]]; then
    local suffix_underscored=$(to_snake_case "$suffix")
    echo "${customer}_${project}_${environment}_${service}_${suffix_underscored}_db"
  else
    echo "${customer}_${project}_${environment}_${service}_db"
  fi
}

# get_database_user
# Builds PostgreSQL user name following Forge convention
# Pattern: {customer}_{project}_{environment}_{service}_user
# All hyphens are replaced with underscores
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   Database user name to stdout
#
# Example:
#   get_database_user "sanofi" "cronus" "prod" "videocalling"
#   # Output: sanofi_cronus_prod_videocalling_user
#
get_database_user() {
  local customer=$(to_snake_case "$1")
  local project=$(to_snake_case "$2")
  local environment=$(to_snake_case "$3")
  local service=$(to_snake_case "$4")
  
  echo "${customer}_${project}_${environment}_${service}_user"
}

# get_rds_instance_identifier
# Builds RDS instance identifier following Forge convention
# Pattern: {customer}-{project}-{environment}-db
# Hyphens are preserved (RDS naming convention)
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#
# Output:
#   RDS instance identifier to stdout
#
# Example:
#   get_rds_instance_identifier "sanofi" "cronus" "prod"
#   # Output: sanofi-cronus-prod-db
#
get_rds_instance_identifier() {
  local customer=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  local project=$(echo "$2" | tr '[:upper:]' '[:lower:]')
  local environment=$(echo "$3" | tr '[:upper:]' '[:lower:]')
  
  echo "${customer}-${project}-${environment}-db"
}

# get_default_schema_name
# Returns default PostgreSQL schema name
#
# Output:
#   Schema name to stdout
#
# Example:
#   schema=$(get_default_schema_name)
#   # Output: public
#
get_default_schema_name() {
  echo "public"
}

# ==============================================================================
# RDS SSM PARAMETER PATHS
# ==============================================================================

# get_rds_admin_username_path
# Builds SSM parameter path for RDS admin username
# Pattern: /rds/{customer}/{project}/{environment}/db/username
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#
# Output:
#   SSM parameter path to stdout
#
# Example:
#   get_rds_admin_username_path "sanofi" "cronus" "prod"
#   # Output: /rds/sanofi/cronus/prod/db/username
#
get_rds_admin_username_path() {
  local customer=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  local project=$(echo "$2" | tr '[:upper:]' '[:lower:]')
  local environment=$(echo "$3" | tr '[:upper:]' '[:lower:]')
  
  echo "/rds/${customer}/${project}/${environment}/db/username"
}

# get_rds_admin_password_path
# Builds SSM parameter path for RDS admin password
# Pattern: /rds/{customer}/{project}/{environment}/db/password
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#
# Output:
#   SSM parameter path to stdout
#
# Example:
#   get_rds_admin_password_path "sanofi" "cronus" "prod"
#   # Output: /rds/sanofi/cronus/prod/db/password
#
get_rds_admin_password_path() {
  local customer=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  local project=$(echo "$2" | tr '[:upper:]' '[:lower:]')
  local environment=$(echo "$3" | tr '[:upper:]' '[:lower:]')
  
  echo "/rds/${customer}/${project}/${environment}/db/password"
}

# get_database_connection_string
# Builds PostgreSQL connection string
# Pattern: postgresql://{user}:{password}@{host}:{port}/{database}
#
# Arguments:
#   $1 - Database host
#   $2 - Database port (default: 5432)
#   $3 - Database name
#   $4 - Database user
#   $5 - (optional) Database password (omit for IAM auth)
#
# Output:
#   Connection string to stdout
#
# Example:
#   get_database_connection_string "mydb.rds.amazonaws.com" "5432" "dev_video_calling_agent_db" "dev_video_calling_agent_user" "password123"
#   # Output: postgresql://dev_video_calling_agent_user:password123@mydb.rds.amazonaws.com:5432/dev_video_calling_agent_db
#
get_database_connection_string() {
  local host="$1"
  local port="${2:-5432}"
  local database="$3"
  local user="$4"
  local password="${5:-}"
  
  if [[ -n "$password" ]]; then
    echo "postgresql://${user}:${password}@${host}:${port}/${database}"
  else
    echo "postgresql://${user}@${host}:${port}/${database}"
  fi
}

# ==============================================================================
# VAULT NAMING PATTERNS
# ==============================================================================

# get_vault_secret_path
# Builds Vault KV v2 secret path following Forge convention
# Pattern: secret/{customer}/{project}/{environment}/{service-name}/{section}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Secret section (e.g., app, livekit, database, stt)
#
# Output:
#   Vault secret path to stdout
#
# Example:
#   get_vault_secret_path "sanofi" "cronus" "dev" "video-calling-agent" "livekit"
#   # Output: secret/sanofi/cronus/dev/video-calling-agent/livekit
#
get_vault_secret_path() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local section="$5"
  
  echo "secret/${customer}/${project}/${environment}/${service_name}/${section}"
}

# get_vault_secret_data_path
# Builds Vault KV v2 data path (for reading secrets)
# Pattern: secret/data/{customer}/{project}/{environment}/{service-name}/{section}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Secret section
#
# Output:
#   Vault secret data path to stdout
#
# Example:
#   get_vault_secret_data_path "sanofi" "cronus" "dev" "video-calling-agent" "livekit"
#   # Output: secret/data/sanofi/cronus/dev/video-calling-agent/livekit
#
get_vault_secret_data_path() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local section="$5"
  
  echo "secret/data/${customer}/${project}/${environment}/${service_name}/${section}"
}

# get_vault_secret_metadata_path
# Builds Vault KV v2 metadata path (for listing secrets)
# Pattern: secret/metadata/{customer}/{project}/{environment}/{service-name}/{section}
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Secret section
#
# Output:
#   Vault secret metadata path to stdout
#
# Example:
#   get_vault_secret_metadata_path "sanofi" "cronus" "dev" "video-calling-agent" "livekit"
#   # Output: secret/metadata/sanofi/cronus/dev/video-calling-agent/livekit
#
get_vault_secret_metadata_path() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local section="$5"
  
  echo "secret/metadata/${customer}/${project}/${environment}/${service_name}/${section}"
}

# get_vault_policy_name
# Builds Vault policy name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}-policy
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   Vault policy name to stdout
#
# Example:
#   get_vault_policy_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi-cronus-dev-video-calling-agent-policy
#
get_vault_policy_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}-${project}-${environment}-${service_name}-policy"
}

# get_vault_role_name
# Builds Vault Kubernetes auth role name following Forge convention
# Pattern: {customer}-{project}-{environment}-{service-name}-role
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   Vault role name to stdout
#
# Example:
#   get_vault_role_name "sanofi" "cronus" "dev" "video-calling-agent"
#   # Output: sanofi-cronus-dev-video-calling-agent-role
#
get_vault_role_name() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  echo "${customer}-${project}-${environment}-${service_name}-role"
}

# ==============================================================================
# PATH BUILDERS
# ==============================================================================

# get_config_path
# Builds configuration file path following Forge convention
# Pattern: deployment/configuration/{environment}/{file}
#
# Arguments:
#   $1 - Environment
#   $2 - Configuration file name (e.g., service.yaml, vault.yaml)
#
# Output:
#   Configuration file path to stdout
#
# Example:
#   get_config_path "dev" "vault.yaml"
#   # Output: deployment/configuration/dev/vault.yaml
#
get_config_path() {
  local environment="$1"
  local file_name="$2"
  
  echo "deployment/configuration/${environment}/${file_name}"
}

# get_helm_values_path
# Builds Helm values file path following Forge convention
# Pattern: deployment/helm/{chart-name}/values-{environment}.yaml
#
# Arguments:
#   $1 - Chart name
#   $2 - Environment
#
# Output:
#   Helm values file path to stdout
#
# Example:
#   get_helm_values_path "service-chart" "dev"
#   # Output: deployment/helm/service-chart/values-dev.yaml
#
get_helm_values_path() {
  local chart_name="$1"
  local environment="$2"
  
  echo "deployment/helm/${chart_name}/values-${environment}.yaml"
}

# ==============================================================================
# VALIDATION HELPERS
# ==============================================================================

# validate_forge_pattern_args
# Validates common Forge pattern arguments
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Returns:
#   0 - All arguments valid
#   1 - One or more arguments invalid
#
# Example:
#   validate_forge_pattern_args "$CUSTOMER" "$PROJECT" "$ENV" "$SERVICE" || exit 1
#
validate_forge_pattern_args() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  
  local errors=0
  
  if [[ -z "$customer" ]]; then
    echo "ERROR: Customer name cannot be empty" >&2
    ((errors++))
  fi
  
  if [[ -z "$project" ]]; then
    echo "ERROR: Project name cannot be empty" >&2
    ((errors++))
  fi
  
  if [[ -z "$environment" ]]; then
    echo "ERROR: Environment cannot be empty" >&2
    ((errors++))
  fi
  
  if [[ -z "$service_name" ]]; then
    echo "ERROR: Service name cannot be empty" >&2
    ((errors++))
  fi
  
  # Validate environment value
  local valid_envs="dev staging prod"
  if [[ ! " $valid_envs " =~ " $environment " ]]; then
    echo "WARNING: Environment '$environment' is not standard (expected: dev, staging, prod)" >&2
  fi
  
  return $errors
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Kubernetes patterns
export -f get_namespace_name get_service_account_name get_deployment_name
export -f get_service_name get_configmap_name get_secret_name get_forge_labels

# AWS patterns
export -f get_ecr_repository_name get_ecr_registry_url get_ecr_image_uri
export -f get_irsa_role_name get_irsa_policy_name get_s3_bucket_name
export -f get_ssm_base_path get_ssm_parameter_path get_aws_tags
export -f get_kms_key_alias_path get_kms_key_description get_kms_key_tags get_kms_key_policy

# Database patterns
export -f get_database_name get_database_user get_database_connection_string
export -f get_rds_instance_identifier get_default_schema_name
export -f get_rds_admin_username_path get_rds_admin_password_path

# Vault patterns
export -f get_vault_secret_path get_vault_secret_data_path get_vault_secret_metadata_path
export -f get_vault_policy_name get_vault_role_name

# Path builders
export -f get_config_path get_helm_values_path

# Validation
export -f validate_forge_pattern_args

# ==============================================================================
# STRING UTILITIES
# ==============================================================================

################################################################################
# Convert string to CamelCase
# Arguments:
#   $1 - Input string (kebab-case, snake_case, or lowercase)
# Output: CamelCase string
# Returns: 0 always
# Examples:
#   to_camel_case "video-calling-service" -> "VideoCallingService"
#   to_camel_case "my_service_name" -> "MyServiceName"
#   to_camel_case "sanofi" -> "Sanofi"
################################################################################
to_camel_case() {
    local input="$1"
    
    # Replace hyphens and underscores with spaces, capitalize each word, remove spaces
    echo "$input" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1' | sed 's/ //g'
}

export -f to_camel_case

# ==============================================================================
# SSH KEY NAMING PATTERNS
# ==============================================================================

################################################################################
# Get SSH key name for build operations
# Pattern: {Customer}{Project}{Environment}{ServiceName}BuildSshKey (CamelCase)
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: SSH key name (CamelCase)
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_ssh_key_name "sanofi" "cronus" "dev" "video-calling-agent"
#   -> "SanofiCronusDevVideoCallingAgentBuildSshKey"
################################################################################
get_ssh_key_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    validate_service_name "$service_name" || return 1
    
    # Convert to CamelCase
    local customer_camel=$(to_camel_case "$customer")
    local project_camel=$(to_camel_case "$project")
    local environment_camel=$(to_camel_case "$environment")
    local service_camel=$(to_camel_case "$service_name")
    
    echo "${customer_camel}${project_camel}${environment_camel}${service_camel}BuildSshKey"
    return 0
}

################################################################################
# Get SSM parameter path for SSH private key
# Path: /forge/{customer}/{project}/{environment}/{service}/ssh/{KeyName}/private
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: SSM parameter path
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_ssh_private_key_ssm_path "sanofi" "cronus" "dev" "video-calling-agent"
#   -> "/forge/sanofi/cronus/dev/video-calling-agent/ssh/SanofiCronusDevVideoCallingAgentBuildSshKey/private"
################################################################################
get_ssh_private_key_ssm_path() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    local key_name
    key_name=$(get_ssh_key_name "$customer" "$project" "$environment" "$service_name") || return 1
    
    echo "/forge/${customer}/${project}/${environment}/${service_name}/ssh/${key_name}/private"
    return 0
}

################################################################################
# Get SSM parameter path for SSH public key
# Path: /forge/{customer}/{project}/{environment}/{service}/ssh/{KeyName}/public
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: SSM parameter path
# Returns:
#   0 - Success
#   1 - Validation failed
################################################################################
get_ssh_public_key_ssm_path() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    local key_name
    key_name=$(get_ssh_key_name "$customer" "$project" "$environment" "$service_name") || return 1
    
    echo "/forge/${customer}/${project}/${environment}/${service_name}/ssh/${key_name}/public"
    return 0
}

################################################################################
# Get SSM parameter path for SSH key metadata
# Path: /forge/{customer}/{project}/{environment}/{service}/ssh/{KeyName}/metadata
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: SSM parameter path
# Returns:
#   0 - Success
#   1 - Validation failed
################################################################################
get_ssh_key_metadata_ssm_path() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    local key_name
    key_name=$(get_ssh_key_name "$customer" "$project" "$environment" "$service_name") || return 1
    
    echo "/forge/${customer}/${project}/${environment}/${service_name}/ssh/${key_name}/metadata"
    return 0
}

# Export SSH functions
export -f get_ssh_key_name
export -f get_ssh_private_key_ssm_path
export -f get_ssh_public_key_ssm_path
export -f get_ssh_key_metadata_ssm_path

# ==============================================================================
# GENERIC IAM ROLE NAMING PATTERNS (SERVICE-SCOPED WITH PURPOSE)
# ==============================================================================

################################################################################
# Get generic IAM role name with purpose suffix
# Pattern: {Customer}{Project}{Environment}{ServiceName}{Purpose}Irsa (PascalCase)
# 
# This is a generic builder for all service-scoped IAM roles.
# Use specific wrappers for common purposes (DockerBuilder, S3Reader, etc.)
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Purpose (e.g., "DockerBuilder", "S3Reader", "SecretsManager")
# Output: IAM role name
# Returns:
#   0 - Success
#   1 - Validation failed
# Examples:
#   get_iam_role_name "sanofi" "cronus" "dev" "video-calling-agent" "DockerBuilder"
#   -> "SanofiCronusDevVideoCallingAgentDockerBuilderIrsa"
#
#   get_iam_role_name "sanofi" "cronus" "dev" "video-calling-agent" "S3Reader"
#   -> "SanofiCronusDevVideoCallingAgentS3ReaderIrsa"
################################################################################
get_iam_role_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local purpose="$5"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    validate_service_name "$service_name" || return 1
    
    if [ -z "$purpose" ]; then
        log_error "Purpose cannot be empty for IAM role name"
        return 1
    fi
    
    # Convert to PascalCase
    local customer_pascal=$(to_pascal_case "$customer")
    local project_pascal=$(to_pascal_case "$project")
    local environment_pascal=$(to_pascal_case "$environment")
    local service_pascal=$(to_pascal_case "$service_name")
    
    # Purpose is assumed to be already in PascalCase (e.g., "DockerBuilder", "S3Reader")
    # Do NOT convert to avoid losing internal capitalization
    local purpose_pascal="$purpose"
    
    # Pattern: {Customer}{Project}{Environment}{ServiceName}{Purpose}Irsa
    echo "${customer_pascal}${project_pascal}${environment_pascal}${service_pascal}${purpose_pascal}Irsa"
    return 0
}

################################################################################
# Get IAM policy name for a role
# Pattern: {RoleName}Policy
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Purpose
# Output: IAM policy name
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_iam_policy_name "sanofi" "cronus" "dev" "video-calling-agent" "DockerBuilder"
#   -> "SanofiCronusDevVideoCallingAgentDockerBuilderIrsaPolicy"
################################################################################
get_iam_policy_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local purpose="$5"
    
    local role_name
    role_name=$(get_iam_role_name "$customer" "$project" "$environment" "$service_name" "$purpose") || return 1
    
    echo "${role_name}Policy"
    return 0
}

################################################################################
# Get generic Kubernetes ServiceAccount name with purpose suffix
# Pattern: {customer}-{project}-{environment}-{service-name}-{purpose}-sa
# 
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Purpose (e.g., "DockerBuilder", "S3Reader")
# Output: ServiceAccount name
# Returns:
#   0 - Success
#   1 - Validation failed
# Examples:
#   get_service_account_name_with_purpose "sanofi" "cronus" "dev" "video-calling-agent" "DockerBuilder"
#   -> "sanofi-cronus-dev-video-calling-agent-docker-builder-sa"
#
#   get_service_account_name_with_purpose "sanofi" "cronus" "dev" "video-calling-agent" "S3Reader"
#   -> "sanofi-cronus-dev-video-calling-agent-s3-reader-sa"
# 
# Note: PascalCase purpose is converted to kebab-case (DockerBuilder -> docker-builder)
################################################################################
get_service_account_name_with_purpose() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local purpose="$5"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    validate_service_name "$service_name" || return 1
    
    if [ -z "$purpose" ]; then
        log_error "Purpose cannot be empty for ServiceAccount name"
        return 1
    fi
    
    # Convert purpose to kebab-case (PascalCase -> kebab-case)
    # DockerBuilder -> docker-builder, S3Reader -> s3-reader
    local purpose_kebab
    purpose_kebab=$(echo "$purpose" | sed 's/\([A-Z]\)/-\1/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-//')
    
    echo "${customer}-${project}-${environment}-${service_name}-${purpose_kebab}-sa"
    return 0
}

################################################################################
# Get generic Kubernetes Job name with purpose suffix
# Pattern: {customer}-{project}-{environment}-{service-name}-{purpose}
# 
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Purpose (e.g., "docker-build", "db-migration")
# Output: Job name
# Returns:
#   0 - Success
#   1 - Validation failed
# Examples:
#   get_job_name "sanofi" "cronus" "dev" "video-calling-agent" "docker-build"
#   -> "sanofi-cronus-dev-video-calling-agent-docker-build"
#
#   get_job_name "sanofi" "cronus" "dev" "video-calling-agent" "db-migration"
#   -> "sanofi-cronus-dev-video-calling-agent-db-migration"
################################################################################
get_job_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local purpose="$5"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    validate_service_name "$service_name" || return 1
    
    if [ -z "$purpose" ]; then
        log_error "Purpose cannot be empty for Job name"
        return 1
    fi
    
    # Convert purpose to kebab-case if needed
    local purpose_kebab
    purpose_kebab=$(echo "$purpose" | sed 's/\([A-Z]\)/-\1/g' | tr '[:upper:]' '[:lower:]' | sed 's/^-//')
    
    echo "${customer}-${project}-${environment}-${service_name}-${purpose_kebab}"
    return 0
}

# ==============================================================================
# DOCKER BUILDER IAM ROLE NAMING (WRAPPERS)
# ==============================================================================

################################################################################
# Get IAM role name for Docker builder (wrapper around generic function)
# Pattern: {Customer}{Project}{Environment}{ServiceName}DockerBuilderIrsa (PascalCase)
# 
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: IAM role name
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_docker_builder_role_name "sanofi" "cronus" "dev" "video-calling-agent"
#   -> "SanofiCronusDevVideoCallingAgentDockerBuilderIrsa"
################################################################################
get_docker_builder_role_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    # Use generic function with "DockerBuilder" purpose
    get_iam_role_name "$customer" "$project" "$environment" "$service_name" "DockerBuilder"
}

################################################################################
# Get IAM policy name for Docker builder
# Pattern: {DockerBuilderRoleName}Policy
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: IAM policy name
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_docker_builder_policy_name "sanofi" "cronus" "dev" "video-calling-agent"
#   -> "SanofiCronusDevVideoCallingAgentDockerBuilderIrsaPolicy"
################################################################################
get_docker_builder_policy_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    # Use generic function with "DockerBuilder" purpose
    get_iam_policy_name "$customer" "$project" "$environment" "$service_name" "DockerBuilder"
}

################################################################################
# Get Kubernetes ServiceAccount name for Docker builder
# Pattern: {customer}-{project}-{environment}-{service-name}-docker-builder-sa
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: ServiceAccount name
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_docker_builder_service_account_name "sanofi" "cronus" "dev" "video-calling-agent"
#   -> "sanofi-cronus-dev-video-calling-agent-docker-builder-sa"
################################################################################
get_docker_builder_service_account_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    # Use generic function with "DockerBuilder" purpose (will be converted to docker-builder)
    get_service_account_name_with_purpose "$customer" "$project" "$environment" "$service_name" "DockerBuilder"
}

################################################################################
# Get Kubernetes Job name for Docker builder
# Pattern: {customer}-{project}-{environment}-{service-name}-docker-build
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
# Output: Job name
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_docker_builder_job_name "sanofi" "cronus" "dev" "video-calling-agent"
#   -> "sanofi-cronus-dev-video-calling-agent-docker-build"
################################################################################
get_docker_builder_job_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    
    # Use generic function with "docker-build" purpose
    get_job_name "$customer" "$project" "$environment" "$service_name" "docker-build"
}

# ==============================================================================
# SQS NAMING PATTERNS
# ==============================================================================

################################################################################
# Get SQS queue name
# Pattern: {customer}-{project}-{environment}-{purpose}.fifo
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Purpose (e.g., "videocalling-events")
#   $5 - Is FIFO (default: "true")
# Output: Queue name
# Returns:
#   0 - Success
#   1 - Validation failed
# Example:
#   get_queue_name "sanofi" "cronus" "prod" "videocalling-events"
#   -> "sanofi-cronus-prod-videocalling-events.fifo"
################################################################################
get_queue_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local purpose="$4"
    local is_fifo="${5:-true}"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    
    # Sanitize purpose
    local sanitized_purpose
    sanitized_purpose=$(to_lowercase "$purpose")
    
    # Build queue name
    local queue_name="${customer}-${project}-${environment}-${sanitized_purpose}"
    
    # Add .fifo suffix for FIFO queues
    if [[ "$is_fifo" == "true" ]]; then
        queue_name="${queue_name}.fifo"
    fi
    
    echo "$queue_name"
}

################################################################################
# Get SQS queue policy name
# Pattern: {customer}-{project}-{environment}-{purpose}-sqs-policy
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Purpose
# Output: Policy name
# Example:
#   get_queue_policy_name "sanofi" "cronus" "prod" "videocalling-events"
#   -> "sanofi-cronus-prod-videocalling-events-sqs-policy"
################################################################################
get_queue_policy_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local purpose="$4"
    
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    
    local sanitized_purpose
    sanitized_purpose=$(to_lowercase "$purpose")
    
    echo "${customer}-${project}-${environment}-${sanitized_purpose}-sqs-policy"
}

################################################################################
# Get KMS key alias for SQS encryption (legacy - specific to SQS)
# Pattern: alias/{customer}-{project}-{environment}-sqs-key
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
# Output: KMS key alias
# Example:
#   get_sqs_kms_key_alias "sanofi" "cronus" "prod"
#   -> "alias/sanofi-cronus-prod-sqs-key"
################################################################################
get_sqs_kms_key_alias() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    
    echo "alias/${customer}-${project}-${environment}-sqs-key"
}

################################################################################
# Get KMS key description for SQS (legacy - specific to SQS)
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
# Output: KMS key description
# Example:
#   get_sqs_kms_key_description "sanofi" "cronus" "prod"
#   -> "SQS encryption key for sanofi-cronus-prod"
################################################################################
get_sqs_kms_key_description() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    
    echo "SQS encryption key for ${customer}-${project}-${environment}"
}

################################################################################
# Get IRSA role ARN for SQS (uses existing get_irsa_role_name from line ~570)
# Pattern: arn:aws:iam::{account_id}:role/{PascalCaseRoleName}
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - AWS region
#   $6 - AWS account ID
# Output: IRSA role ARN
# Example:
#   get_irsa_role_arn "sanofi" "cronus" "prod" "video-calling-api" "eu-central-1" "123456789012"
#   -> "arn:aws:iam::123456789012:role/SanofiCronusProdVideoCallingApiIrsa"
################################################################################
get_sqs_irsa_role_arn() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local region="$5"
    local account_id="$6"
    
    # Use existing get_irsa_role_name (PascalCase) from line ~570
    local role_name
    role_name=$(get_irsa_role_name "$customer" "$project" "$environment" "$service_name")
    
    echo "arn:aws:iam::${account_id}:role/${role_name}"
}

################################################################################
# Get Kubernetes namespace
# Pattern: {customer}-{project}-{environment}
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
# Output: Kubernetes namespace
# Example:
#   get_kubernetes_namespace "sanofi" "cronus" "prod"
#   -> "sanofi-cronus-prod"
################################################################################
get_kubernetes_namespace() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    
    echo "${customer}-${project}-${environment}"
}

################################################################################
# Get EKS cluster name
# Pattern: {customer}-{project}-{environment}-eks
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
# Output: EKS cluster name
# Example:
#   get_eks_cluster_name "sanofi" "cronus" "prod"
#   -> "sanofi-cronus-prod-eks"
################################################################################
get_eks_cluster_name() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    
    echo "${customer}-${project}-${environment}-eks"
}

################################################################################
# Get VPC Endpoint name for SQS
# Pattern: {customer}-{project}-sqs-vpce
# Note: VPC endpoint is shared across environments
# Arguments:
#   $1 - Customer name
#   $2 - Project name
# Output: VPC Endpoint name
# Example:
#   get_vpc_endpoint_name_sqs "sanofi" "cronus"
#   -> "sanofi-cronus-sqs-vpce"
################################################################################
get_vpc_endpoint_name_sqs() {
    local customer="$1"
    local project="$2"
    
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    
    echo "${customer}-${project}-sqs-vpce"
}

################################################################################
# Get SSM parameter path for SQS KMS key ID
# Pattern: /sqs/{customer}/{project}/{environment}/kms-key-id
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
# Output: SSM parameter path
# Example:
#   get_sqs_kms_key_id_path "sanofi" "cronus" "prod"
#   -> "/sqs/sanofi/cronus/prod/kms-key-id"
################################################################################
get_sqs_kms_key_id_path() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    
    echo "/sqs/${customer}/${project}/${environment}/kms-key-id"
}

################################################################################
# Get SSM parameter path for SQS queue URL
# Pattern: /sqs/{customer}/{project}/{environment}/{purpose}/queue-url
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Purpose
# Output: SSM parameter path
# Example:
#   get_sqs_queue_url_path "sanofi" "cronus" "prod" "videocalling-events"
#   -> "/sqs/sanofi/cronus/prod/videocalling-events/queue-url"
################################################################################
get_sqs_queue_url_path() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local purpose="$4"
    
    echo "/sqs/${customer}/${project}/${environment}/${purpose}/queue-url"
}

# Export generic IAM naming functions
export -f get_iam_role_name
export -f get_iam_policy_name
export -f get_service_account_name_with_purpose
export -f get_job_name

# Export Docker Builder wrapper functions
export -f get_docker_builder_role_name
export -f get_docker_builder_policy_name
export -f get_docker_builder_service_account_name
export -f get_docker_builder_job_name

# Export SQS naming functions
export -f get_queue_name
export -f get_queue_policy_name
export -f get_sqs_kms_key_alias
export -f get_sqs_kms_key_description
export -f get_sqs_irsa_role_arn
export -f get_kubernetes_namespace
export -f get_eks_cluster_name
export -f get_vpc_endpoint_name_sqs
export -f get_sqs_kms_key_id_path
export -f get_sqs_queue_url_path

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-patterns.sh v${FORGE_PATTERNS_VERSION}"

