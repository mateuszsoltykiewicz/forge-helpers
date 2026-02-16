#!/usr/bin/env bash
################################################################################
# Forge ECR Operations Library
################################################################################
# Version: 1.0.0
# Description: AWS ECR registry management operations
#
# Features:
# - ECR repository creation/deletion
# - Repository and lifecycle policy management
# - Image operations (list/delete/wipe)
# - ECR authentication helpers
# - Policy generators for EKS cluster access with Docker Builder support
#
# Dependencies:
# - forge-core.sh (logging, validation)
# - forge-aws-discovery.sh (AWS account, region)
# - forge-patterns.sh (ECR naming conventions, IAM role naming)
# - AWS CLI
# - jq
#
# Author: Moai Forge Team
# Created: 2026-02-09
################################################################################

set -euo pipefail

# Prevent double-loading
if [[ -n "${FORGE_ECR_OPERATIONS_LOADED:-}" ]]; then
  return 0
fi
readonly FORGE_ECR_OPERATIONS_LOADED=true

# Library version
readonly FORGE_ECR_OPERATIONS_VERSION="1.0.0"

################################################################################
# Dependencies
################################################################################

readonly FORGE_ECR_OPERATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "${FORGE_ECR_OPERATIONS_DIR}/forge-core.sh"
source "${FORGE_ECR_OPERATIONS_DIR}/forge-aws-discovery.sh"
source "${FORGE_ECR_OPERATIONS_DIR}/forge-patterns.sh"

################################################################################
# Constants
################################################################################

readonly ECR_DEFAULT_TAG_MUTABILITY="MUTABLE"
readonly ECR_DEFAULT_SCAN_ON_PUSH="true"
readonly ECR_DEFAULT_LIFECYCLE_KEEP_COUNT=4
readonly ECR_BATCH_DELETE_MAX_SIZE=100

################################################################################
# Section 2: Repository Existence & Discovery
################################################################################

################################################################################
# Check if ECR repository exists
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Returns:
#   0 - Repository exists
#   1 - Repository does not exist
################################################################################
ecr_repository_exists() {
    local repository_name="$1"
    local region="$2"
    
    if aws ecr describe-repositories \
        --repository-names "$repository_name" \
        --region "$region" \
        --output json > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Get ECR repository information
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Output: JSON with repository metadata
# Returns:
#   0 - Success
#   1 - Repository not found
################################################################################
get_ecr_repository_info() {
    local repository_name="$1"
    local region="$2"
    
    aws ecr describe-repositories \
        --repository-names "$repository_name" \
        --region "$region" \
        --output json 2>/dev/null || return 1
}

################################################################################
# List ECR repositories (optionally filtered by prefix)
# Arguments:
#   $1 - (optional) Repository name prefix filter
#   $2 - AWS region
# Output: JSON array of repository names
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
list_ecr_repositories() {
    local prefix="${1:-}"
    local region="$2"
    
    local repos
    repos=$(aws ecr describe-repositories \
        --region "$region" \
        --output json 2>/dev/null | jq -r '.repositories[].repositoryName') || return 1
    
    if [[ -n "$prefix" ]]; then
        echo "$repos" | grep "^${prefix}"
    else
        echo "$repos"
    fi
}

################################################################################
# Section 3: Repository Creation
################################################################################

################################################################################
# Create ECR repository with configuration
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
#   $3 - (optional) Tag mutability (MUTABLE|IMMUTABLE, default: MUTABLE)
#   $4 - (optional) Scan on push (true|false, default: true)
#   $5 - (optional) Tags in JSON format
# Output: JSON with repositoryUri and repositoryArn
# Returns:
#   0 - Success
#   1 - Creation failed
################################################################################
create_ecr_repository() {
    local repository_name="$1"
    local region="$2"
    local tag_mutability="${3:-$ECR_DEFAULT_TAG_MUTABILITY}"
    local scan_on_push="${4:-$ECR_DEFAULT_SCAN_ON_PUSH}"
    local tags="${5:-}"
    
    log_debug "Creating ECR repository: $repository_name in $region"
    
    local cmd=(
        aws ecr create-repository
        --repository-name "$repository_name"
        --region "$region"
        --image-tag-mutability "$tag_mutability"
    )
    
    if [[ "$scan_on_push" == "true" ]]; then
        cmd+=(--image-scanning-configuration scanOnPush=true)
    else
        cmd+=(--image-scanning-configuration scanOnPush=false)
    fi
    
    if [[ -n "$tags" ]]; then
        cmd+=(--tags "$tags")
    fi
    
    "${cmd[@]}" --output json 2>&1 || return 1
}

################################################################################
# Ensure ECR repository exists (idempotent)
# Creates repository if it doesn't exist, returns info if it does
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Output: JSON with repository info
# Returns:
#   0 - Success (created or already exists)
#   1 - Failed
################################################################################
ensure_ecr_repository() {
    local repository_name="$1"
    local region="$2"
    
    if ecr_repository_exists "$repository_name" "$region"; then
        log_debug "ECR repository already exists: $repository_name"
        get_ecr_repository_info "$repository_name" "$region"
        return 0
    else
        log_info "Creating ECR repository: $repository_name"
        create_ecr_repository "$repository_name" "$region"
    fi
}

################################################################################
# Section 4: Repository Deletion
################################################################################

################################################################################
# Delete ECR repository
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
#   $3 - Force delete (true|false, deletes even with images)
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
delete_ecr_repository() {
    local repository_name="$1"
    local region="$2"
    local force="${3:-true}"
    
    log_debug "Deleting ECR repository: $repository_name (force=$force)"
    
    if [[ "$force" == "true" ]]; then
        aws ecr delete-repository \
            --repository-name "$repository_name" \
            --region "$region" \
            --force \
            --output json > /dev/null 2>&1 || return 1
    else
        aws ecr delete-repository \
            --repository-name "$repository_name" \
            --region "$region" \
            --output json > /dev/null 2>&1 || return 1
    fi
    
    return 0
}

################################################################################
# Delete ECR repository only if empty (safe delete)
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Returns:
#   0 - Success
#   1 - Failed (repository has images or doesn't exist)
################################################################################
delete_ecr_repository_safe() {
    local repository_name="$1"
    local region="$2"
    
    # Check if repository exists and count images
    local image_count
    image_count=$(aws ecr list-images \
        --repository-name "$repository_name" \
        --region "$region" \
        --output json 2>/dev/null | jq '.imageIds | length') || return 1
    
    if [[ "$image_count" -gt 0 ]]; then
        log_error "Repository $repository_name contains $image_count images. Cannot delete safely."
        return 1
    fi
    
    delete_ecr_repository "$repository_name" "$region" "false"
}

################################################################################
# Section 5: Repository Policy Management
################################################################################

################################################################################
# Generate ECR repository policy with Docker Builder access
# This is the PRIMARY policy generator - includes EKS + Docker Builder access
# 
# Arguments:
#   $1 - EKS cluster ARN
#   $2 - AWS account ID
#   $3 - Customer name
#   $4 - Project name
#   $5 - Environment name
#   $6 - Service name
# Output: JSON policy document
# Returns: 0 always
# Example:
#   policy=$(generate_ecr_cluster_policy_with_builder \
#     "arn:aws:eks:eu-central-1:123:cluster/my-cluster" \
#     "123456789012" \
#     "sanofi" "cronus" "dev" "video-calling-agent")
################################################################################
generate_ecr_cluster_policy_with_builder() {
    local eks_cluster_arn="$1"
    local aws_account_id="$2"
    local customer="$3"
    local project="$4"
    local environment="$5"
    local service_name="$6"
    
    # Extract cluster name from ARN
    local cluster_name
    cluster_name=$(echo "$eks_cluster_arn" | awk -F'/' '{print $NF}')
    
    # Get Docker builder role name using forge-patterns.sh
    local builder_role_name
    builder_role_name=$(get_docker_builder_role_name "$customer" "$project" "$environment" "$service_name")
    local builder_role_arn="arn:aws:iam::${aws_account_id}:role/${builder_role_name}"
    
    log_debug "Generating ECR policy with Docker Builder access"
    log_debug "  EKS Cluster: $cluster_name"
    log_debug "  Builder Role: $builder_role_name"
    log_debug "  Builder ARN: $builder_role_arn"
    
    # Generate policy with 4 Statements
    cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSClusterAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Condition": {
        "StringEquals": {
          "aws:SourceArn": "${eks_cluster_arn}"
        }
      }
    },
    {
      "Sid": "EKSNodeAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_account_id}:role/${cluster_name}-node-group"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    },
    {
      "Sid": "DockerBuilderAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${builder_role_arn}"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:GetAuthorizationToken"
      ]
    },
    {
      "Sid": "DeveloperReadAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_account_id}:root"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ]
    }
  ]
}
EOF
}

################################################################################
# Generate ECR repository policy (LEGACY - without Docker Builder)
# For backward compatibility with existing workflows
# Arguments:
#   $1 - EKS cluster ARN
#   $2 - AWS account ID
# Output: JSON policy document
# Returns: 0 always
################################################################################
generate_ecr_cluster_policy() {
    local eks_cluster_arn="$1"
    local aws_account_id="$2"
    
    # Extract cluster name
    local cluster_name
    cluster_name=$(echo "$eks_cluster_arn" | awk -F'/' '{print $NF}')
    
    log_debug "Generating ECR policy (legacy - no builder access)"
    
    cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSClusterAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Condition": {
        "StringEquals": {
          "aws:SourceArn": "${eks_cluster_arn}"
        }
      }
    },
    {
      "Sid": "EKSNodeAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_account_id}:role/${cluster_name}-node-group"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    },
    {
      "Sid": "DeveloperReadAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_account_id}:root"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ]
    }
  ]
}
EOF
}

################################################################################
# Get current ECR repository policy
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Output: JSON policy document
# Returns:
#   0 - Success
#   1 - No policy found or error
################################################################################
get_ecr_repository_policy() {
    local repository_name="$1"
    local region="$2"
    
    aws ecr get-repository-policy \
        --repository-name "$repository_name" \
        --region "$region" \
        --output json 2>/dev/null || return 1
}

################################################################################
# Set ECR repository policy
# Arguments:
#   $1 - Repository name
#   $2 - Policy JSON string
#   $3 - AWS region
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
set_ecr_repository_policy() {
    local repository_name="$1"
    local policy_json="$2"
    local region="$3"
    
    log_debug "Applying ECR policy to: $repository_name"
    
    aws ecr set-repository-policy \
        --repository-name "$repository_name" \
        --policy-text "$policy_json" \
        --region "$region" \
        --output json > /dev/null 2>&1 || return 1
    
    return 0
}

################################################################################
# Delete ECR repository policy
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
delete_ecr_repository_policy() {
    local repository_name="$1"
    local region="$2"
    
    aws ecr delete-repository-policy \
        --repository-name "$repository_name" \
        --region "$region" \
        --output json > /dev/null 2>&1 || return 1
}

################################################################################
# Apply ECR cluster policy with Docker Builder access (orchestrator)
# Wrapper: generate + set in one step
# Arguments:
#   $1 - Repository name
#   $2 - EKS cluster ARN
#   $3 - AWS account ID
#   $4 - Customer name
#   $5 - Project name
#   $6 - Environment name
#   $7 - Service name
#   $8 - AWS region
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
apply_ecr_cluster_policy_with_builder() {
    local repository_name="$1"
    local eks_cluster_arn="$2"
    local aws_account_id="$3"
    local customer="$4"
    local project="$5"
    local environment="$6"
    local service_name="$7"
    local region="$8"
    
    log_step "Applying ECR policy with Docker Builder access"
    
    # Generate policy
    local policy_json
    policy_json=$(generate_ecr_cluster_policy_with_builder \
        "$eks_cluster_arn" \
        "$aws_account_id" \
        "$customer" \
        "$project" \
        "$environment" \
        "$service_name") || return 1
    
    # Apply policy
    set_ecr_repository_policy "$repository_name" "$policy_json" "$region" || return 1
    
    log_success "ECR policy applied with Docker Builder access"
    return 0
}

################################################################################
# Section 6: Lifecycle Policy Management
################################################################################

################################################################################
# Get current ECR lifecycle policy
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Output: JSON lifecycle policy
# Returns:
#   0 - Success
#   1 - No policy found or error
################################################################################
get_ecr_lifecycle_policy() {
    local repository_name="$1"
    local region="$2"
    
    aws ecr get-lifecycle-policy \
        --repository-name "$repository_name" \
        --region "$region" \
        --output json 2>/dev/null || return 1
}

################################################################################
# Set ECR lifecycle policy
# Arguments:
#   $1 - Repository name
#   $2 - Lifecycle policy JSON string
#   $3 - AWS region
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
set_ecr_lifecycle_policy() {
    local repository_name="$1"
    local lifecycle_policy_json="$2"
    local region="$3"
    
    log_debug "Applying lifecycle policy to: $repository_name"
    
    aws ecr put-lifecycle-policy \
        --repository-name "$repository_name" \
        --lifecycle-policy-text "$lifecycle_policy_json" \
        --region "$region" \
        --output json > /dev/null 2>&1 || return 1
    
    return 0
}

################################################################################
# Delete ECR lifecycle policy
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
delete_ecr_lifecycle_policy() {
    local repository_name="$1"
    local region="$2"
    
    aws ecr delete-lifecycle-policy \
        --repository-name "$repository_name" \
        --region "$region" \
        --output json > /dev/null 2>&1 || return 1
}

################################################################################
# Generate ECR lifecycle policy (keep last N images)
# Arguments:
#   $1 - (optional) Number of images to keep (default: 4)
# Output: JSON lifecycle policy
# Returns: 0 always
# Example:
#   policy=$(generate_ecr_lifecycle_policy 4)
################################################################################
generate_ecr_lifecycle_policy() {
    local keep_count="${1:-$ECR_DEFAULT_LIFECYCLE_KEEP_COUNT}"
    
    log_debug "Generating lifecycle policy (keep last ${keep_count} images)"
    
    cat <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last ${keep_count} images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": ${keep_count}
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
}

################################################################################
# Apply ECR lifecycle policy with default settings (keep last 4 images)
# Wrapper: generate + set in one step
# Arguments:
#   $1 - Repository name
#   $2 - AWS region
# Returns:
#   0 - Success
#   1 - Failed
################################################################################
apply_ecr_lifecycle_policy_default() {
    local repository_name="$1"
    local region="$2"
    
    log_debug "Applying default lifecycle policy to: $repository_name"
    
    # Generate policy
    local lifecycle_policy_json
    lifecycle_policy_json=$(generate_ecr_lifecycle_policy) || return 1
    
    # Apply policy
    set_ecr_lifecycle_policy "$repository_name" "$lifecycle_policy_json" "$region" || return 1
    
    log_success "Lifecycle policy applied (keep last ${ECR_DEFAULT_LIFECYCLE_KEEP_COUNT} images)"
    return 0
}

################################################################################
# Initialization
################################################################################

log_debug "forge-ecr-operations.sh v${FORGE_ECR_OPERATIONS_VERSION} loaded"
