#!/usr/bin/env bash
# ==============================================================================
# Forge AWS Discovery Library
# ==============================================================================
# Description: AWS resource discovery and interaction utilities
# Version: 1.0.0
# Author: Moai Forge Team
# License: Proprietary
#
# Features:
# - Execution mode detection (LOCAL vs IN_CLUSTER/IRSA)
# - AWS region and account ID discovery
# - EKS cluster discovery and configuration
# - ECR repository management
# - SSM Parameter Store access
# - Auto-retry for AWS API calls
#
# Execution Modes:
# - LOCAL: Uses AWS CLI credentials from ~/.aws/ or environment variables
# - IN_CLUSTER: Uses IRSA (IAM Roles for Service Accounts) via ServiceAccount annotations
#
# Usage:
#   source /path/to/forge-aws-discovery.sh
#   region=$(get_aws_region)
#   account_id=$(get_aws_account_id)
#   cluster=$(discover_eks_cluster_by_namespace "customer-project-dev-application-agent")
# ==============================================================================

set -euo pipefail

# ==============================================================================
# LIBRARY METADATA
# ==============================================================================

# Prevent double-loading
if [[ "${FORGE_AWS_DISCOVERY_LOADED:-}" == "true" ]]; then
  return 0
fi

readonly FORGE_AWS_DISCOVERY_VERSION="1.0.0"
readonly FORGE_AWS_DISCOVERY_LOADED="true"

# ==============================================================================
# LOAD DEPENDENCIES
# ==============================================================================

# Get script directory
FORGE_AWS_DISCOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source forge-core (required)
if [[ -f "${FORGE_AWS_DISCOVERY_DIR}/forge-core.sh" ]]; then
  source "${FORGE_AWS_DISCOVERY_DIR}/forge-core.sh"
else
  echo "ERROR: forge-core.sh not found. Cannot continue." >&2
  exit 1
fi

# Source forge-patterns (required)
if [[ -f "${FORGE_AWS_DISCOVERY_DIR}/forge-patterns.sh" ]]; then
  source "${FORGE_AWS_DISCOVERY_DIR}/forge-patterns.sh"
else
  log_error "forge-patterns.sh not found. Cannot continue."
  exit 1
fi

# Validate required commands
validate_required_commands aws jq

# ==============================================================================
# CONSTANTS
# ==============================================================================

readonly AWS_SERVICE_ACCOUNT_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
readonly AWS_DEFAULT_REGION_FALLBACK="eu-central-1"
readonly AWS_RETRY_ATTEMPTS=3
readonly AWS_RETRY_DELAY=2

# ==============================================================================
# EXECUTION MODE DETECTION
# ==============================================================================

# detect_aws_execution_mode
# Detects whether running in-cluster (IRSA) or locally (AWS config)
#
# Detection Logic:
#   - IN_CLUSTER: ServiceAccount token exists at /var/run/secrets/kubernetes.io/serviceaccount/token
#   - LOCAL: No ServiceAccount token, uses ~/.aws/ credentials or environment variables
#
# Output:
#   "IN_CLUSTER" or "LOCAL" to stdout
#
# Example:
#   mode=$(detect_aws_execution_mode)
#   if [[ "$mode" == "IN_CLUSTER" ]]; then
#     echo "Using IRSA authentication"
#   fi
#
detect_aws_execution_mode() {
  if [[ -f "$AWS_SERVICE_ACCOUNT_TOKEN_PATH" ]]; then
    echo "IN_CLUSTER"
  else
    echo "LOCAL"
  fi
}

# ==============================================================================
# AWS REGION AND ACCOUNT DISCOVERY
# ==============================================================================

# get_aws_region
# Gets AWS region with fallback chain
#
# Priority:
#   1. $AWS_REGION environment variable
#   2. $AWS_DEFAULT_REGION environment variable
#   3. aws configure get region
#   4. Default fallback: eu-central-1
#
# Output:
#   AWS region to stdout
#
# Example:
#   region=$(get_aws_region)
#   echo "Using region: $region"
#
get_aws_region() {
  local region=""
  
  # Try environment variables
  if [[ -n "${AWS_REGION:-}" ]]; then
    region="$AWS_REGION"
    log_debug "AWS region from AWS_REGION: $region"
  elif [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
    region="$AWS_DEFAULT_REGION"
    log_debug "AWS region from AWS_DEFAULT_REGION: $region"
  else
    # Try aws configure
    region=$(aws configure get region 2>/dev/null || echo "")
    if [[ -n "$region" ]]; then
      log_debug "AWS region from aws configure: $region"
    else
      # Fallback to default
      region="$AWS_DEFAULT_REGION_FALLBACK"
      log_debug "AWS region fallback to default: $region"
    fi
  fi
  
  echo "$region"
}

# get_aws_account_id
# Gets AWS account ID using STS get-caller-identity
#
# Returns:
#   0 - Success, account ID printed to stdout
#   1 - Failed to get account ID
#
# Example:
#   account_id=$(get_aws_account_id)
#   echo "AWS Account: $account_id"
#
get_aws_account_id() {
  local account_id
  
  log_debug "Getting AWS account ID..."
  
  if ! account_id=$(retry_command $AWS_RETRY_ATTEMPTS $AWS_RETRY_DELAY \
    aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    log_error "Failed to get AWS account ID"
    return 1
  fi
  
  if [[ -z "$account_id" ]]; then
    log_error "AWS account ID is empty"
    return 1
  fi
  
  log_debug "AWS Account ID: $account_id"
  echo "$account_id"
}

# get_aws_caller_identity
# Gets full AWS caller identity (Account, UserId, Arn)
#
# Output:
#   JSON object with Account, UserId, Arn to stdout
#
# Example:
#   identity=$(get_aws_caller_identity)
#   echo "$identity" | jq -r '.Arn'
#
get_aws_caller_identity() {
  log_debug "Getting AWS caller identity..."
  
  if ! retry_command $AWS_RETRY_ATTEMPTS $AWS_RETRY_DELAY \
    aws sts get-caller-identity 2>/dev/null; then
    log_error "Failed to get AWS caller identity"
    return 1
  fi
}

# ==============================================================================
# EKS CLUSTER DISCOVERY
# ==============================================================================

# list_eks_clusters
# Lists all EKS clusters in specified region
#
# Arguments:
#   $1 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   Space-separated list of cluster names to stdout
#
# Example:
#   clusters=$(list_eks_clusters "eu-central-1")
#   for cluster in $clusters; do
#     echo "Found cluster: $cluster"
#   done
#
list_eks_clusters() {
  local region="${1:-$(get_aws_region)}"
  
  log_debug "Listing EKS clusters in region: $region"
  
  local clusters
  if ! clusters=$(retry_command $AWS_RETRY_ATTEMPTS $AWS_RETRY_DELAY \
    aws eks list-clusters --region "$region" --query 'clusters[]' --output text 2>/dev/null); then
    log_error "Failed to list EKS clusters in region: $region"
    return 1
  fi
  
  if [[ -z "$clusters" ]]; then
    log_debug "No EKS clusters found in region: $region"
    return 0
  fi
  
  echo "$clusters"
}

# get_eks_cluster_info
# Gets detailed information about an EKS cluster
#
# Arguments:
#   $1 - Cluster name
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   JSON object with cluster details to stdout
#
# Example:
#   info=$(get_eks_cluster_info "my-cluster" "eu-central-1")
#   endpoint=$(echo "$info" | jq -r '.cluster.endpoint')
#
get_eks_cluster_info() {
  local cluster_name="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_debug "Getting info for EKS cluster: $cluster_name in region: $region"
  
  if ! retry_command $AWS_RETRY_ATTEMPTS $AWS_RETRY_DELAY \
    aws eks describe-cluster --name "$cluster_name" --region "$region" 2>/dev/null; then
    log_error "Failed to get info for cluster: $cluster_name"
    return 1
  fi
}

# get_eks_cluster_arn
# Gets ARN of EKS cluster (wrapper around get_eks_cluster_info)
#
# Arguments:
#   $1 - Cluster name
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   Cluster ARN string
#
# Example:
#   arn=$(get_eks_cluster_arn "my-cluster" "eu-central-1")
#
get_eks_cluster_arn() {
  local cluster_name="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_debug "Getting ARN for EKS cluster: $cluster_name"
  
  local cluster_info
  cluster_info=$(get_eks_cluster_info "$cluster_name" "$region") || return 1
  
  echo "$cluster_info" | jq -r '.cluster.arn' 2>/dev/null
}

# get_eks_oidc_provider
# Gets OIDC provider information for EKS cluster (required for IRSA)
#
# Arguments:
#   $1 - Cluster name
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   JSON object with issuer, oidc_id, oidc_arn
#
# Example:
#   oidc=$(get_eks_oidc_provider "my-cluster")
#   issuer=$(echo "$oidc" | jq -r '.issuer')
#
get_eks_oidc_provider() {
  local cluster_name="$1"
  local region="${2:-$(get_aws_region)}"
  local account_id
  
  log_debug "Getting OIDC provider for cluster: $cluster_name"
  
  # Get cluster info
  local cluster_info
  if ! cluster_info=$(get_eks_cluster_info "$cluster_name" "$region"); then
    return 1
  fi
  
  # Extract OIDC issuer
  local issuer
  issuer=$(echo "$cluster_info" | jq -r '.cluster.identity.oidc.issuer')
  
  if [[ -z "$issuer" || "$issuer" == "null" ]]; then
    log_error "No OIDC provider found for cluster: $cluster_name"
    return 1
  fi
  
  # Extract OIDC ID from issuer URL
  local oidc_id
  oidc_id=$(echo "$issuer" | sed 's|https://||' | cut -d'/' -f2)
  
  # Get account ID
  if ! account_id=$(get_aws_account_id); then
    return 1
  fi
  
  # Build OIDC provider ARN
  local oidc_arn="arn:aws:iam::${account_id}:oidc-provider/$(echo "$issuer" | sed 's|https://||')"
  
  # Return JSON
  jq -n \
    --arg issuer "$issuer" \
    --arg oidc_id "$oidc_id" \
    --arg oidc_arn "$oidc_arn" \
    '{issuer: $issuer, oidc_id: $oidc_id, oidc_arn: $oidc_arn}'
}

# discover_eks_cluster_by_namespace
# Discovers which EKS cluster contains a specific namespace
# This is the INNOVATION from namespace.sh v3.0.0 (⭐⭐⭐⭐)
#
# Arguments:
#   $1 - Namespace name to search for
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   Cluster name to stdout, or empty if not found
#
# Returns:
#   0 - Cluster found
#   1 - Cluster not found
#
# Example:
#   cluster=$(discover_eks_cluster_by_namespace "customer-project-dev-application-agent")
#   if [[ -n "$cluster" ]]; then
#     echo "Found namespace in cluster: $cluster"
#   fi
#
discover_eks_cluster_by_namespace() {
  local namespace="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_info "Discovering EKS cluster containing namespace: $namespace"
  
  # Get all clusters in region
  local clusters
  if ! clusters=$(list_eks_clusters "$region"); then
    return 1
  fi
  
  if [[ -z "$clusters" ]]; then
    log_warning "No EKS clusters found in region: $region"
    return 1
  fi
  
  # Iterate through clusters
  for cluster_name in $clusters; do
    log_debug "Checking cluster: $cluster_name"
    
    # Update kubeconfig for this cluster (temporarily)
    if ! aws eks update-kubeconfig \
      --name "$cluster_name" \
      --region "$region" \
      --kubeconfig /tmp/kubeconfig-discovery-$$ \
      >/dev/null 2>&1; then
      log_debug "Failed to update kubeconfig for cluster: $cluster_name"
      continue
    fi
    
    # Check if namespace exists in this cluster
    if kubectl get namespace "$namespace" \
      --kubeconfig /tmp/kubeconfig-discovery-$$ \
      >/dev/null 2>&1; then
      log_success "Found namespace '$namespace' in cluster: $cluster_name"
      
      # Cleanup temp kubeconfig
      rm -f /tmp/kubeconfig-discovery-$$
      
      echo "$cluster_name"
      return 0
    fi
  done
  
  # Cleanup temp kubeconfig
  rm -f /tmp/kubeconfig-discovery-$$
  
  log_warning "Namespace '$namespace' not found in any EKS cluster in region: $region"
  return 1
}

# configure_eks_kubeconfig
# Configures kubectl to access an EKS cluster
#
# Arguments:
#   $1 - Cluster name
#   $2 - (optional) AWS region (defaults to get_aws_region)
#   $3 - (optional) Kubeconfig path (defaults to ~/.kube/config)
#
# Returns:
#   0 - Success
#   1 - Failed to configure kubeconfig
#
# Example:
#   configure_eks_kubeconfig "my-cluster" "eu-central-1"
#   kubectl get nodes
#
configure_eks_kubeconfig() {
  local cluster_name="$1"
  local region="${2:-$(get_aws_region)}"
  local kubeconfig="${3:-$HOME/.kube/config}"
  
  log_info "Configuring kubeconfig for EKS cluster: $cluster_name"
  
  if ! aws eks update-kubeconfig \
    --name "$cluster_name" \
    --region "$region" \
    --kubeconfig "$kubeconfig" 2>/dev/null; then
    log_error "Failed to configure kubeconfig for cluster: $cluster_name"
    return 1
  fi
  
  log_success "Kubeconfig configured for cluster: $cluster_name"
}

# discover_eks_cluster
# Smart EKS cluster discovery with multiple strategies
# Can discover by explicit cluster name, namespace search, or Forge patterns
#
# Arguments:
#   $1 - Discovery method: "cluster-name" | "namespace" | "forge-pattern"
#   $2 - Discovery value:
#        - For "cluster-name": cluster name
#        - For "namespace": namespace name
#        - For "forge-pattern": customer name
#   $3 - (optional for forge-pattern) Project name
#   $4 - (optional for forge-pattern) Environment
#   $5 - (optional for forge-pattern) Service name
#   $6 - (optional) AWS region
#
# Output:
#   Cluster name to stdout
#
# Returns:
#   0 - Cluster found
#   1 - Cluster not found
#
# Examples:
#   # Method 1: Direct cluster name
#   cluster=$(discover_eks_cluster "cluster-name" "indegene-eks")
#
#   # Method 2: Search by namespace
#   cluster=$(discover_eks_cluster "namespace" "customer-project-dev-application-agent")
#
#   # Method 3: Auto-build namespace from Forge pattern
#   cluster=$(discover_eks_cluster "forge-pattern" "customer" "project" "dev" "application-agent")
#
discover_eks_cluster() {
  local method="$1"
  local region=""
  
  case "$method" in
    cluster-name)
      local cluster_name="$2"
      region="${3:-$(get_aws_region)}"
      
      log_debug "Verifying cluster exists: $cluster_name"
      
      # Verify cluster exists
      if ! aws eks describe-cluster \
        --name "$cluster_name" \
        --region "$region" \
        >/dev/null 2>&1; then
        log_error "Cluster not found: $cluster_name"
        return 1
      fi
      
      log_success "Cluster verified: $cluster_name"
      echo "$cluster_name"
      return 0
      ;;
      
    namespace)
      local namespace="$2"
      region="${3:-$(get_aws_region)}"
      
      log_info "Discovering cluster by namespace: $namespace"
      discover_eks_cluster_by_namespace "$namespace" "$region"
      return $?
      ;;
      
    forge-pattern)
      local customer="$2"
      local project="$3"
      local environment="$4"
      local service="$5"
      region="${6:-$(get_aws_region)}"
      
      log_info "Discovering cluster using Forge pattern"
      log_debug "Customer: $customer, Project: $project, Env: $environment, Service: $service"
      
      # Validate arguments
      if ! validate_forge_pattern_args "$customer" "$project" "$environment" "$service"; then
        log_error "Invalid Forge pattern arguments"
        return 1
      fi
      
      # Build namespace using forge-patterns
      local namespace
      namespace=$(get_namespace_name "$customer" "$project" "$environment" "$service")
      
      log_info "Built namespace from pattern: $namespace"
      
      # Discover by namespace
      discover_eks_cluster_by_namespace "$namespace" "$region"
      return $?
      ;;
      
    *)
      log_error "Invalid discovery method: $method"
      log_error "Valid methods: cluster-name, namespace, forge-pattern"
      return 1
      ;;
  esac
}

# configure_eks_context
# Complete EKS context configuration with smart discovery and execution mode awareness
# This is the HIGH-LEVEL function for EKS setup in scripts
#
# Arguments:
#   $1 - Discovery method: "cluster-name" | "namespace" | "forge-pattern"
#   $2+ - Method-specific arguments (same as discover_eks_cluster)
#
# Execution Modes:
#   - IN_CLUSTER: Already authenticated, just sets context
#   - LOCAL: Configures kubeconfig and switches context
#
# Returns:
#   0 - Success, cluster configured
#   1 - Failed to configure
#
# Examples:
#   # Method 1: Direct cluster name
#   configure_eks_context "cluster-name" "indegene-eks"
#
#   # Method 2: Auto-discover by namespace
#   configure_eks_context "namespace" "customer-project-dev-application-agent"
#
#   # Method 3: Forge pattern (recommended)
#   configure_eks_context "forge-pattern" "customer" "project" "dev" "application-agent"
#
configure_eks_context() {
  local method="$1"
  shift
  
  local execution_mode
  execution_mode=$(detect_aws_execution_mode)
  
  log_info "Configuring EKS context (execution mode: $execution_mode)"
  
  # Discover cluster
  local cluster_name
  if ! cluster_name=$(discover_eks_cluster "$method" "$@"); then
    log_error "Failed to discover EKS cluster"
    return 1
  fi
  
  if [[ -z "$cluster_name" ]]; then
    log_error "No cluster found"
    return 1
  fi
  
  log_info "Discovered cluster: $cluster_name"
  
  # Configure based on execution mode
  if [[ "$execution_mode" == "IN_CLUSTER" ]]; then
    log_info "Running in-cluster - ServiceAccount authentication active"
    log_info "Cluster context: $cluster_name"
    log_success "EKS context ready (in-cluster mode)"
    echo "$cluster_name"
    return 0
  else
    # LOCAL mode - configure kubeconfig
    log_info "Running locally - configuring kubeconfig"
    
    local region
    region=$(get_aws_region)
    
    if ! configure_eks_kubeconfig "$cluster_name" "$region"; then
      log_error "Failed to configure kubeconfig"
      return 1
    fi
    
    # Switch to the cluster context
    local context="arn:aws:eks:${region}:$(get_aws_account_id):cluster/${cluster_name}"
    
    if kubectl config use-context "$context" >/dev/null 2>&1; then
      log_success "Switched to cluster context: $cluster_name"
    else
      log_warning "Cluster configured but context switch failed (may need manual switch)"
    fi
    
    log_success "EKS context configured (local mode)"
    echo "$cluster_name"
    return 0
  fi
}

# ==============================================================================
# ECR REPOSITORY MANAGEMENT
# ==============================================================================

# check_ecr_repository_exists
# Checks if an ECR repository exists
#
# Arguments:
#   $1 - Repository name (e.g., customer/project/env/service)
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Returns:
#   0 - Repository exists
#   1 - Repository does not exist
#
# Example:
#   if check_ecr_repository_exists "customer/project/dev/application-agent"; then
#     echo "Repository exists"
#   fi
#
check_ecr_repository_exists() {
  local repository_name="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_debug "Checking if ECR repository exists: $repository_name"
  
  if aws ecr describe-repositories \
    --repository-names "$repository_name" \
    --region "$region" \
    >/dev/null 2>&1; then
    log_debug "ECR repository exists: $repository_name"
    return 0
  else
    log_debug "ECR repository does not exist: $repository_name"
    return 1
  fi
}

# get_ecr_repository_uri
# Gets the URI of an ECR repository
#
# Arguments:
#   $1 - Repository name
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   Repository URI to stdout (e.g., 123456789.dkr.ecr.eu-central-1.amazonaws.com/repo)
#
# Example:
#   uri=$(get_ecr_repository_uri "customer/project/dev/application-agent")
#
get_ecr_repository_uri() {
  local repository_name="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_debug "Getting ECR repository URI: $repository_name"
  
  local uri
  if ! uri=$(aws ecr describe-repositories \
    --repository-names "$repository_name" \
    --region "$region" \
    --query 'repositories[0].repositoryUri' \
    --output text 2>/dev/null); then
    log_error "Failed to get ECR repository URI: $repository_name"
    return 1
  fi
  
  echo "$uri"
}

# create_ecr_repository
# Creates an ECR repository with Forge tags
#
# Arguments:
#   $1 - Repository name (e.g., customer/project/env/service)
#   $2 - Customer name (for tagging)
#   $3 - Project name (for tagging)
#   $4 - Environment (for tagging)
#   $5 - Service name (for tagging)
#   $6 - (optional) AWS region (defaults to get_aws_region)
#
# Returns:
#   0 - Success
#   1 - Failed to create repository
#
# Example:
#   create_ecr_repository "customer/project/dev/application-agent" \
#     "customer" "project" "dev" "application-agent"
#
create_ecr_repository() {
  local repository_name="$1"
  local customer="$2"
  local project="$3"
  local environment="$4"
  local service="$5"
  local region="${6:-$(get_aws_region)}"
  
  log_info "Creating ECR repository: $repository_name"
  
  # Build tags using forge-patterns
  local tags=$(get_aws_tags "$customer" "$project" "$environment" "$service")
  
  # Convert space-separated tags to JSON array
  local tags_json="["
  local first=true
  for tag in $tags; do
    local key="${tag%%=*}"
    local value="${tag#*=}"
    if [[ "$first" == "true" ]]; then
      first=false
    else
      tags_json+=","
    fi
    tags_json+="{\"Key\":\"$key\",\"Value\":\"$value\"}"
  done
  tags_json+="]"
  
  if ! aws ecr create-repository \
    --repository-name "$repository_name" \
    --region "$region" \
    --tags "$tags_json" \
    >/dev/null 2>&1; then
    log_error "Failed to create ECR repository: $repository_name"
    return 1
  fi
  
  log_success "Created ECR repository: $repository_name"
}

# get_ecr_login_password
# Gets ECR authentication token for docker login
#
# Arguments:
#   $1 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   ECR login password to stdout
#
# Example:
#   password=$(get_ecr_login_password)
#   echo "$password" | docker login --username AWS --password-stdin $REGISTRY_URL
#
get_ecr_login_password() {
  local region="${1:-$(get_aws_region)}"
  
  log_debug "Getting ECR login password for region: $region"
  
  if ! retry_command $AWS_RETRY_ATTEMPTS $AWS_RETRY_DELAY \
    aws ecr get-login-password --region "$region" 2>/dev/null; then
    log_error "Failed to get ECR login password"
    return 1
  fi
}

# ecr_docker_login
# Performs docker login to ECR
#
# Arguments:
#   $1 - (optional) AWS region (defaults to get_aws_region)
#
# Returns:
#   0 - Success
#   1 - Failed to login
#
# Example:
#   ecr_docker_login "eu-central-1"
#   docker push $IMAGE_URI
#
ecr_docker_login() {
  local region="${1:-$(get_aws_region)}"
  local account_id
  
  log_info "Logging into ECR..."
  
  if ! account_id=$(get_aws_account_id); then
    return 1
  fi
  
  local registry_url="${account_id}.dkr.ecr.${region}.amazonaws.com"
  
  if ! get_ecr_login_password "$region" | docker login --username AWS --password-stdin "$registry_url" 2>/dev/null; then
    log_error "Failed to login to ECR"
    return 1
  fi
  
  log_success "Logged into ECR: $registry_url"
}

# ==============================================================================
# SSM PARAMETER STORE
# ==============================================================================

# get_ssm_parameter
# Gets a parameter from SSM Parameter Store
#
# Arguments:
#   $1 - Parameter name/path
#   $2 - (optional) AWS region (defaults to get_aws_region)
#   $3 - (optional) --with-decryption flag (true/false, default: true)
#
# Output:
#   Parameter value to stdout
#
# Example:
#   api_key=$(get_ssm_parameter "/customer/project/dev/application-agent/livekit-api-key")
#
get_ssm_parameter() {
  local parameter_name="$1"
  local region="${2:-$(get_aws_region)}"
  local with_decryption="${3:-true}"
  
  log_debug "Getting SSM parameter: $parameter_name"
  
  local decrypt_flag=""
  if [[ "$with_decryption" == "true" ]]; then
    decrypt_flag="--with-decryption"
  fi
  
  local value
  if ! value=$(retry_command $AWS_RETRY_ATTEMPTS $AWS_RETRY_DELAY \
    aws ssm get-parameter \
      --name "$parameter_name" \
      --region "$region" \
      $decrypt_flag \
      --query 'Parameter.Value' \
      --output text 2>/dev/null); then
    log_error "Failed to get SSM parameter: $parameter_name"
    return 1
  fi
  
  echo "$value"
}

# put_ssm_parameter
# Puts a parameter into SSM Parameter Store
#
# Arguments:
#   $1 - Parameter name/path
#   $2 - Parameter value
#   $3 - (optional) Parameter type (String|StringList|SecureString, default: SecureString)
#   $4 - (optional) AWS region (defaults to get_aws_region)
#   $5 - (optional) Overwrite existing (true/false, default: true)
#
# Returns:
#   0 - Success
#   1 - Failed to put parameter
#
# Example:
#   put_ssm_parameter "/customer/project/dev/application-agent/api-key" "secret123" "SecureString"
#
put_ssm_parameter() {
  local parameter_name="$1"
  local parameter_value="$2"
  local parameter_type="${3:-SecureString}"
  local region="${4:-$(get_aws_region)}"
  local overwrite="${5:-true}"
  local kms_key_id="${6:-}"
  
  log_info "Putting SSM parameter: $parameter_name"
  
  local overwrite_flag=""
  if [[ "$overwrite" == "true" ]]; then
    overwrite_flag="--overwrite"
  fi
  
  # Add KMS key ID if provided and parameter type is SecureString
  if [[ -n "$kms_key_id" ]] && [[ "$parameter_type" == "SecureString" ]]; then
    log_debug "Using KMS key: $kms_key_id"
    
    if ! aws ssm put-parameter \
      --name "$parameter_name" \
      --value "$parameter_value" \
      --type "$parameter_type" \
      --region "$region" \
      $overwrite_flag \
      --key-id "$kms_key_id" \
      >/dev/null 2>&1; then
      log_error "Failed to put SSM parameter: $parameter_name"
      return 1
    fi
  else
    if ! aws ssm put-parameter \
      --name "$parameter_name" \
      --value "$parameter_value" \
      --type "$parameter_type" \
      --region "$region" \
      $overwrite_flag \
      >/dev/null 2>&1; then
      log_error "Failed to put SSM parameter: $parameter_name"
      return 1
    fi
  fi
  
  log_success "Put SSM parameter: $parameter_name"
}

# list_ssm_parameters_by_path
# Lists all parameters under a given path
#
# Arguments:
#   $1 - Base path (e.g., /customer/project/dev/application)
#   $2 - (optional) Recursive (true/false, default: true)
#   $3 - (optional) With decryption (true/false, default: true)
#   $4 - (optional) AWS region (defaults to get_aws_region)
#
# Returns:
#   0 - Success (even if no parameters found)
#   1 - Failed to list parameters
#
# Output:
#   JSON array of parameters with Name and Value
#   [{"Name": "/path/to/param", "Value": "decrypted_value"}, ...]
#
# Example:
#   params=$(list_ssm_parameters_by_path "/customer/project/dev/application" "true" "true")
#   echo "$params" | jq -r '.[] | "\(.Name)=\(.Value)"'
#
list_ssm_parameters_by_path() {
  local base_path="$1"
  local recursive="${2:-true}"
  local with_decryption="${3:-true}"
  local region="${4:-$(get_aws_region)}"
  
  log_debug "Listing SSM parameters under: $base_path (recursive: $recursive)"
  
  local recursive_flag=""
  if [[ "$recursive" == "true" ]]; then
    recursive_flag="--recursive"
  fi
  
  local decrypt_flag=""
  if [[ "$with_decryption" == "true" ]]; then
    decrypt_flag="--with-decryption"
  fi
  
  # Collect all parameters (handle pagination)
  local all_parameters="[]"
  local next_token=""
  
  while true; do
    local token_flag=""
    if [[ -n "$next_token" ]]; then
      token_flag="--starting-token $next_token"
    fi
    
    local result
    if ! result=$(aws ssm get-parameters-by-path \
      --path "$base_path" \
      $recursive_flag \
      $decrypt_flag \
      --region "$region" \
      $token_flag \
      --output json 2>/dev/null); then
      log_debug "No parameters found or error listing: $base_path"
      echo "[]"
      return 0
    fi
    
    # Extract parameters and append to collection
    local parameters
    parameters=$(echo "$result" | jq -c '.Parameters')
    all_parameters=$(echo "$all_parameters" | jq -c ". + $parameters")
    
    # Check for next token
    next_token=$(echo "$result" | jq -r '.NextToken // empty')
    if [[ -z "$next_token" ]]; then
      break
    fi
  done
  
  echo "$all_parameters"
}

# delete_ssm_parameter
# Deletes a parameter from SSM Parameter Store
#
# Arguments:
#   $1 - Parameter name/path
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Returns:
#   0 - Success
#   1 - Failed to delete parameter
#
# Example:
#   delete_ssm_parameter "/customer/project/dev/application/app/port"
#
delete_ssm_parameter() {
  local parameter_name="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_info "Deleting SSM parameter: $parameter_name"
  
  if ! aws ssm delete-parameter \
    --name "$parameter_name" \
    --region "$region" \
    >/dev/null 2>&1; then
    log_error "Failed to delete SSM parameter: $parameter_name"
    return 1
  fi
  
  log_success "Deleted SSM parameter: $parameter_name"
}

# ==============================================================================
# RDS DISCOVERY
# ==============================================================================

# discover_rds_instance
# Discovers RDS instance endpoint and port
#
# Arguments:
#   $1 - RDS instance identifier
#   $2 - (optional) AWS region (defaults to get_aws_region)
#
# Output:
#   JSON object with endpoint and port to stdout
#   {
#     "endpoint": "hostname.rds.amazonaws.com",
#     "port": "5432"
#   }
#
# Returns:
#   0 - Success
#   1 - Failed to discover RDS instance
#
# Example:
#   rds_info=$(discover_rds_instance "customer-project-prod-db")
#   endpoint=$(echo "$rds_info" | jq -r '.endpoint')
#   port=$(echo "$rds_info" | jq -r '.port')
#
discover_rds_instance() {
  local rds_instance_id="$1"
  local region="${2:-$(get_aws_region)}"
  
  log_debug "Discovering RDS instance: $rds_instance_id in region $region"
  
  # Get RDS instance details
  local rds_info
  if ! rds_info=$(aws rds describe-db-instances \
    --db-instance-identifier "$rds_instance_id" \
    --region "$region" \
    --output json 2>/dev/null); then
    log_error "Failed to describe RDS instance: $rds_instance_id"
    return 1
  fi
  
  # Extract endpoint and port
  local endpoint
  local port
  
  endpoint=$(echo "$rds_info" | jq -r '.DBInstances[0].Endpoint.Address // empty')
  port=$(echo "$rds_info" | jq -r '.DBInstances[0].Endpoint.Port // empty')
  
  if [[ -z "$endpoint" ]] || [[ -z "$port" ]]; then
    log_error "RDS instance endpoint not found: $rds_instance_id"
    return 1
  fi
  
  # Return as JSON
  echo "{\"endpoint\":\"$endpoint\",\"port\":\"$port\"}"
}

# ==============================================================================
# EKS DISCOVERY (EXTENDED)
# ==============================================================================

# discover_eks_cluster
# Discovers EKS cluster by name and returns detailed information
#
# Arguments:
#   $1 - cluster_name
#   $2 - aws_region (optional, auto-detect if not provided)
#
# Returns:
#   0 - Cluster found
#   1 - Cluster not found or error
#
# Output:
#   JSON: {
#     "name": "...",
#     "endpoint": "...",
#     "oidc_provider": "...",
#     "vpc_id": "...",
#     "security_groups": [...]
#   }
#
# Example:
#   cluster_info=$(discover_eks_cluster "customer-project-prod-eks" "eu-central-1")
#
discover_eks_cluster() {
  local cluster_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Discovering EKS cluster: $cluster_name in region $aws_region"
  
  # Get cluster info
  local cluster_info
  cluster_info=$(aws eks describe-cluster \
    --name "$cluster_name" \
    --region "$aws_region" \
    --query 'cluster' \
    --output json 2>&1) || {
    log_debug "Cluster not found: $cluster_name"
    return 1
  }
  
  # Extract key information
  local endpoint
  local oidc_provider
  local vpc_id
  local security_groups
  
  endpoint=$(echo "$cluster_info" | jq -r '.endpoint')
  oidc_provider=$(echo "$cluster_info" | jq -r '.identity.oidc.issuer' | sed 's|https://||')
  vpc_id=$(echo "$cluster_info" | jq -r '.resourcesVpcConfig.vpcId')
  security_groups=$(echo "$cluster_info" | jq -c '.resourcesVpcConfig.securityGroupIds')
  
  # Build result JSON
  jq -n \
    --arg name "$cluster_name" \
    --arg endpoint "$endpoint" \
    --arg oidc "$oidc_provider" \
    --arg vpc "$vpc_id" \
    --argjson sg "$security_groups" \
    '{
      name: $name,
      endpoint: $endpoint,
      oidc_provider: $oidc,
      vpc_id: $vpc,
      security_groups: $sg
    }'
}

# discover_eks_cluster_by_naming_convention
# Auto-discovers EKS cluster based on naming convention
# Pattern: {customer}-{project}-{environment}-eks
# Fallback: {customer}-{project}-shared-eks if not found
#
# Arguments:
#   $1 - customer
#   $2 - project
#   $3 - environment
#   $4 - aws_region (optional)
#
# Returns:
#   0 - Cluster found
#   1 - Cluster not found
#
# Output:
#   JSON with cluster info
#
# Example:
#   cluster_info=$(discover_eks_cluster_by_naming_convention "customer" "project" "dev")
#
discover_eks_cluster_by_naming_convention() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local aws_region="${4:-$(get_aws_region)}"
  
  # Try environment-specific cluster first
  local cluster_name
  cluster_name=$(get_eks_cluster_name "$customer" "$project" "$environment")
  
  log_info "Looking for EKS cluster: $cluster_name"
  
  local cluster_info
  if cluster_info=$(discover_eks_cluster "$cluster_name" "$aws_region" 2>/dev/null); then
    log_success "Found environment-specific cluster: $cluster_name"
    echo "$cluster_info"
    return 0
  fi
  
  # Fallback to shared cluster
  cluster_name=$(get_eks_cluster_name "$customer" "$project" "shared")
  
  log_warning "Environment-specific cluster not found, trying shared cluster: $cluster_name"
  
  if cluster_info=$(discover_eks_cluster "$cluster_name" "$aws_region" 2>/dev/null); then
    log_success "Found shared cluster: $cluster_name"
    echo "$cluster_info"
    return 0
  fi
  
  log_error "No EKS cluster found for $customer-$project-$environment (tried: $environment and shared)"
  return 1
}

# get_eks_oidc_provider_arn
# Extracts OIDC provider ARN from cluster info
#
# Arguments:
#   $1 - cluster_name
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   ARN of OIDC provider
#
# Example:
#   oidc_arn=$(get_eks_oidc_provider_arn "customer-project-prod-eks")
#
get_eks_oidc_provider_arn() {
  local cluster_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Getting OIDC provider ARN for cluster: $cluster_name"
  
  # Get OIDC issuer URL
  local oidc_issuer
  oidc_issuer=$(aws eks describe-cluster \
    --name "$cluster_name" \
    --region "$aws_region" \
    --query 'cluster.identity.oidc.issuer' \
    --output text 2>&1) || {
    log_error "Failed to get OIDC issuer for cluster: $cluster_name"
    return 1
  }
  
  # Extract OIDC ID from issuer URL
  local oidc_id
  oidc_id=$(echo "$oidc_issuer" | awk -F'/' '{print $NF}')
  
  # Get AWS account ID
  local account_id
  account_id=$(get_aws_account_id)
  
  # Build OIDC provider ARN
  echo "arn:aws:iam::${account_id}:oidc-provider/oidc.eks.${aws_region}.amazonaws.com/id/${oidc_id}"
}

# ==============================================================================
# VPC ENDPOINT DISCOVERY
# ==============================================================================

# verify_vpc_endpoint_sqs
# Checks if SQS VPC endpoint exists
# Pattern: {customer}-{project}-sqs-vpce
#
# Arguments:
#   $1 - customer
#   $2 - project
#   $3 - aws_region (optional)
#
# Returns:
#   0 - VPC endpoint exists
#   1 - VPC endpoint not found
#
# Example:
#   if verify_vpc_endpoint_sqs "customer" "project"; then
#     log_info "SQS VPC endpoint available"
#   fi
#
verify_vpc_endpoint_sqs() {
  local customer="$1"
  local project="$2"
  local aws_region="${3:-$(get_aws_region)}"
  
  local endpoint_name
  endpoint_name=$(get_vpc_endpoint_name_sqs "$customer" "$project")
  
  log_debug "Verifying SQS VPC endpoint: $endpoint_name"
  
  # Search for VPC endpoint by Name tag
  local endpoint_id
  endpoint_id=$(get_vpc_endpoint_id "$endpoint_name" "$aws_region")
  
  if [[ -n "$endpoint_id" ]]; then
    log_debug "SQS VPC endpoint found: $endpoint_id"
    return 0
  else
    log_debug "SQS VPC endpoint not found: $endpoint_name"
    return 1
  fi
}

# get_vpc_endpoint_id
# Returns VPC endpoint ID by tag Name
#
# Arguments:
#   $1 - endpoint_name
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Endpoint found
#   1 - Endpoint not found
#
# Output:
#   VPC endpoint ID (e.g., "vpce-1234567890abcdef0")
#
# Example:
#   endpoint_id=$(get_vpc_endpoint_id "customer-project-sqs-vpce")
#
get_vpc_endpoint_id() {
  local endpoint_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Looking for VPC endpoint: $endpoint_name"
  
  local endpoint_id
  endpoint_id=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=tag:Name,Values=$endpoint_name" \
    --region "$aws_region" \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text 2>&1)
  
  if [[ "$endpoint_id" == "None" ]] || [[ -z "$endpoint_id" ]]; then
    return 1
  fi
  
  echo "$endpoint_id"
}

# ==============================================================================
# SQS QUEUE DISCOVERY
# ==============================================================================

# discover_queue_by_name
# Discovers SQS queue URL and attributes by name
#
# Arguments:
#   $1 - queue_name
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Queue found
#   1 - Queue not found
#
# Output:
#   JSON: {"url": "...", "arn": "...", "attributes": {...}}
#
# Example:
#   queue_info=$(discover_queue_by_name "customer-project-prod-events.fifo")
#
discover_queue_by_name() {
  local queue_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Discovering SQS queue: $queue_name in region $aws_region"
  
  # Get queue URL
  local queue_url
  queue_url=$(aws sqs get-queue-url \
    --queue-name "$queue_name" \
    --region "$aws_region" \
    --query 'QueueUrl' \
    --output text 2>&1) || {
    log_debug "Queue not found: $queue_name"
    return 1
  }
  
  # Get queue attributes
  local attributes
  attributes=$(aws sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --attribute-names All \
    --region "$aws_region" \
    --output json)
  
  local queue_arn
  queue_arn=$(echo "$attributes" | jq -r '.Attributes.QueueArn')
  
  # Return as JSON
  jq -n \
    --arg url "$queue_url" \
    --arg arn "$queue_arn" \
    --argjson attrs "$(echo "$attributes" | jq '.Attributes')" \
    '{url: $url, arn: $arn, attributes: $attrs}'
}

# queue_exists
# Checks if SQS queue exists
#
# Arguments:
#   $1 - queue_name
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Queue exists
#   1 - Queue does not exist
#
# Example:
#   if queue_exists "customer-project-prod-events.fifo"; then
#     log_info "Queue exists"
#   fi
#
queue_exists() {
  local queue_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  aws sqs get-queue-url \
    --queue-name "$queue_name" \
    --region "$aws_region" \
    --output text &>/dev/null
}

# ==============================================================================
# KMS KEY DISCOVERY
# ==============================================================================

# ------------------------------------------------------------------------------
# discover_kms_key_by_alias
# ------------------------------------------------------------------------------
# Description:
#   Discover KMS key by alias name
#
# Arguments:
#   $1 - alias_name (with or without 'alias/' prefix)
#   $2 - aws_region (optional)
#
# Returns:
#   Key ID if found, empty string otherwise
#
# Example:
#   key_id=$(discover_kms_key_by_alias "alias/customer/project/dev/application/encryption")
#   key_id=$(discover_kms_key_by_alias "customer/project/dev/application/encryption")
#
discover_kms_key_by_alias() {
  local alias_name="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  # Ensure alias has 'alias/' prefix
  if [[ ! "$alias_name" =~ ^alias/ ]]; then
    alias_name="alias/${alias_name}"
  fi
  
  log_debug "Discovering KMS key by alias: $alias_name in region $aws_region"
  
  local key_id
  if key_id=$(aws kms describe-key \
    --key-id "$alias_name" \
    --region "$aws_region" \
    --query 'KeyMetadata.KeyId' \
    --output text 2>/dev/null); then
    echo "$key_id"
    return 0
  fi
  
  return 1
}

# ------------------------------------------------------------------------------
# list_kms_keys_by_service
# ------------------------------------------------------------------------------
# Description:
#   List all KMS keys for a specific service using alias prefix
#
# Arguments:
#   $1 - customer
#   $2 - project
#   $3 - environment
#   $4 - service_name
#   $5 - aws_region (optional)
#
# Returns:
#   JSON array of key metadata
#
# Example:
#   keys=$(list_kms_keys_by_service "customer" "project" "dev" "application")
#
list_kms_keys_by_service() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service_name="$4"
  local aws_region="${5:-$(get_aws_region)}"
  
  local alias_prefix="alias/${customer}/${project}/${environment}/${service_name}/"
  
  log_debug "Listing KMS keys with prefix: $alias_prefix in region $aws_region"
  
  # List all aliases and filter by prefix
  aws kms list-aliases \
    --region "$aws_region" \
    --query "Aliases[?starts_with(AliasName, '${alias_prefix}')]" \
    --output json
}

# ------------------------------------------------------------------------------
# get_kms_key_arn
# ------------------------------------------------------------------------------
# Description:
#   Get KMS key ARN by alias or key ID
#
# Arguments:
#   $1 - key_identifier (alias or key ID)
#   $2 - aws_region (optional)
#
# Returns:
#   Key ARN if found, empty string otherwise
#
# Example:
#   arn=$(get_kms_key_arn "alias/customer/project/dev/application/encryption")
#   arn=$(get_kms_key_arn "e80dc880-d391-4f52-b7d1-3bc2cfa0f288")
#
get_kms_key_arn() {
  local key_identifier="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Getting KMS key ARN for: $key_identifier in region $aws_region"
  
  aws kms describe-key \
    --key-id "$key_identifier" \
    --region "$aws_region" \
    --query 'KeyMetadata.Arn' \
    --output text 2>/dev/null || return 1
}

# ------------------------------------------------------------------------------
# kms_key_exists
# ------------------------------------------------------------------------------
# Description:
#   Check if KMS key exists by alias or key ID
#
# Arguments:
#   $1 - key_identifier (alias or key ID)
#   $2 - aws_region (optional)
#
# Returns:
#   0 - Key exists
#   1 - Key does not exist
#
# Example:
#   if kms_key_exists "alias/customer/project/dev/application/encryption"; then
#     log_info "Key exists"
#   fi
#
kms_key_exists() {
  local key_identifier="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  # Ensure alias has 'alias/' prefix if it looks like an alias
  if [[ "$key_identifier" =~ ^[a-z0-9/-]+$ ]] && [[ ! "$key_identifier" =~ ^alias/ ]]; then
    key_identifier="alias/${key_identifier}"
  fi
  
  aws kms describe-key \
    --key-id "$key_identifier" \
    --region "$aws_region" \
    --output text &>/dev/null
}

# ------------------------------------------------------------------------------
# get_kms_key_metadata
# ------------------------------------------------------------------------------
# Description:
#   Get full KMS key metadata
#
# Arguments:
#   $1 - key_identifier (alias or key ID)
#   $2 - aws_region (optional)
#
# Returns:
#   JSON object with key metadata
#
# Example:
#   metadata=$(get_kms_key_metadata "alias/customer/project/dev/application/encryption")
#   key_state=$(echo "$metadata" | jq -r '.KeyMetadata.KeyState')
#
get_kms_key_metadata() {
  local key_identifier="$1"
  local aws_region="${2:-$(get_aws_region)}"
  
  log_debug "Getting KMS key metadata for: $key_identifier in region $aws_region"
  
  aws kms describe-key \
    --key-id "$key_identifier" \
    --region "$aws_region" \
    --output json 2>/dev/null || return 1
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Execution mode
export -f detect_aws_execution_mode

# Region and account
export -f get_aws_region get_aws_account_id get_aws_caller_identity

# EKS
export -f list_eks_clusters get_eks_cluster_info get_eks_cluster_arn get_eks_oidc_provider
export -f discover_eks_cluster_by_namespace configure_eks_kubeconfig
export -f discover_eks_cluster configure_eks_context

# EKS Extended
export -f discover_eks_cluster discover_eks_cluster_by_naming_convention get_eks_oidc_provider_arn

# VPC Endpoints
export -f verify_vpc_endpoint_sqs get_vpc_endpoint_id

# SQS
export -f discover_queue_by_name queue_exists

# KMS
export -f discover_kms_key_by_alias list_kms_keys_by_service get_kms_key_arn
export -f kms_key_exists get_kms_key_metadata

# ECR
export -f check_ecr_repository_exists get_ecr_repository_uri create_ecr_repository
export -f get_ecr_login_password ecr_docker_login

# SSM
export -f get_ssm_parameter put_ssm_parameter list_ssm_parameters_by_path delete_ssm_parameter

# RDS
export -f discover_rds_instance

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-aws-discovery.sh v${FORGE_AWS_DISCOVERY_VERSION}"

# Detect and log execution mode
AWS_EXECUTION_MODE=$(detect_aws_execution_mode)
log_debug "AWS execution mode: $AWS_EXECUTION_MODE"

if [[ "$AWS_EXECUTION_MODE" == "IN_CLUSTER" ]]; then
  log_debug "Using IRSA (IAM Roles for Service Accounts) authentication"
else
  log_debug "Using local AWS credentials from ~/.aws/ or environment"
fi

