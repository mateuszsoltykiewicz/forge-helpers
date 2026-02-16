#!/usr/bin/env bash
# ==============================================================================
# Generic AWS ECR Repository Management Script
# ==============================================================================
# Description: Creates/deletes ECR repositories with policies and lifecycle rules
# Version: 3.0.0
# Compatible: bash 3.2+ (macOS compatible)
#
# Library Dependencies:
# - forge-core.sh (logging, validation)
# - forge-patterns.sh (naming conventions, IAM role naming)
# - forge-aws-discovery.sh (AWS account, region, EKS discovery)
# - forge-ecr-operations.sh (ECR operations, policy generation with Docker Builder)
#
# Usage:
#   ./ecr.sh --customer CUSTOMER --project PROJECT --service-name SERVICE \
#            --environment ENV --cluster-name CLUSTER [OPTIONS]
#
# Examples:
#   # Create ECR repository for dev environment
#   ./ecr.sh --customer sanofi --project cronus --service-name video-calling \
#            --environment dev --cluster-name indegene-eks
#
#   # Create for multiple environments
#   ./ecr.sh --customer sanofi --project cronus --service-name video-calling \
#            --environment dev,staging,prod --cluster-name indegene-eks
#
#   # Delete ECR repository
#   ./ecr.sh --customer sanofi --project cronus --service-name video-calling \
#            --environment dev --cluster-name indegene-eks --delete
#
#   # Dry-run (preview changes)
#   ./ecr.sh --customer sanofi --project cronus --service-name video-calling \
#            --environment dev --cluster-name indegene-eks --dry-run
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Script Configuration
# ==============================================================================

readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

# ==============================================================================
# Source Forge Libraries
# ==============================================================================

source "${LIB_DIR}/forge-core.sh"
source "${LIB_DIR}/forge-patterns.sh"
source "${LIB_DIR}/forge-aws-discovery.sh"
source "${LIB_DIR}/forge-ecr-operations.sh"

# Default configuration
DEFAULT_AWS_REGION="eu-central-1"

# ==============================================================================
# Color Codes (kept for banner compatibility)
# ==============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Global Variables
# ==============================================================================

# Required arguments
CUSTOMER=""
PROJECT=""
SERVICE_NAME=""
ENVIRONMENT=""
CLUSTER_NAME=""

# AWS configuration
AWS_REGION="${DEFAULT_AWS_REGION}"
AWS_PROFILE=""

# Operation flags
DELETE_MODE=false
DRY_RUN=false
FORCE=false
VERBOSE=false

# Image operation flags
WIPE_IMAGES=false
DELETE_IMAGE=""
CHECK_IMAGE=""

# Statistics counters
TOTAL_CREATED=0
TOTAL_DELETED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0

# Arrays to store results
declare -a CREATED_REPOS=()
declare -a DELETED_REPOS=()
declare -a FAILED_REPOS=()

# ==============================================================================
# Helper Functions
# ==============================================================================

print_banner() {
  echo -e "${CYAN}"
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║         Generic AWS ECR Repository Management Script         ║
║                       Version 3.0.0                          ║
╚══════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
  echo ""
}

print_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

REQUIRED ARGUMENTS:
  --customer CUSTOMER           Customer name (e.g., sanofi, indegene)
  --project PROJECT             Project name (e.g., cronus, platform)
  --service-name SERVICE        Service name (e.g., video-calling, api-gateway)
  --environment ENV             Environment (dev, staging, prod, or comma-separated)
  --cluster-name CLUSTER        EKS cluster name (for IAM policy)

AWS CONFIGURATION:
  --aws-region REGION           AWS region (default: ${DEFAULT_AWS_REGION})
  --aws-profile PROFILE         AWS CLI profile to use (optional)

CONTROL FLAGS:
  --delete                      Delete ECR repository instead of creating
  --dry-run                     Preview without making changes
  --force                       Skip confirmation prompts
  --verbose                     Enable verbose logging
  -h, --help                    Show this help message
  -v, --version                 Show script version

IMAGE OPERATIONS:
  --wipe-images                 Remove all images from repository (keeps repository)
  --delete-image TAG|DIGEST     Remove specific image by tag or digest
  --image-exists TAG|DIGEST     Check if specific image exists

EXAMPLES:
  # Create ECR repository for dev environment
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev --cluster-name indegene-eks

  # Create for multiple environments
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev,staging,prod --cluster-name indegene-eks

  # Delete ECR repository
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev --cluster-name indegene-eks --delete

  # Dry-run preview
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev --cluster-name indegene-eks --dry-run

  # Use custom AWS profile and region
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment prod --cluster-name prod-cluster \\
                 --aws-profile production --aws-region us-east-1

  # Wipe all images from repository
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev --cluster-name indegene-eks --wipe-images

  # Delete specific image by tag
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev --cluster-name indegene-eks --delete-image 65a945c

  # Check if image exists
  ${SCRIPT_NAME} --customer sanofi --project cronus --service-name video-calling \\
                 --environment dev --cluster-name indegene-eks --image-exists 65a945c

REPOSITORY NAMING:
  Format: {customer}/{project}/{environment}/{service}
  Example: sanofi/cronus/dev/video-calling

POLICIES APPLIED:
  - EKS cluster access policy (restricts pull to specific cluster)
  - Lifecycle policy (keeps last 4 images)
  - Tag mutability: MUTABLE (allows short git commit SHAs)
  - Scan on push: ENABLED

EOF
}

print_version() {
  echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_arguments() {
  if [ $# -eq 0 ]; then
    print_usage
    exit 1
  fi

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
      --service-name)
        SERVICE_NAME="$2"
        shift 2
        ;;
      --environment)
        ENVIRONMENT="$2"
        shift 2
        ;;
      --cluster-name)
        CLUSTER_NAME="$2"
        shift 2
        ;;
      --aws-region)
        AWS_REGION="$2"
        shift 2
        ;;
      --aws-profile)
        AWS_PROFILE="$2"
        shift 2
        ;;
      --delete)
        DELETE_MODE=true
        shift
        ;;
      --wipe-images)
        WIPE_IMAGES=true
        shift
        ;;
      --delete-image)
        DELETE_IMAGE="$2"
        shift 2
        ;;
      --image-exists)
        CHECK_IMAGE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      -v|--version)
        print_version
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        echo ""
        print_usage
        exit 1
        ;;
    esac
  done
}

# ==============================================================================
# Validation Functions
# ==============================================================================
# Using functions from forge-core.sh:
# - validate_required_commands() - Check for required tools
# ==============================================================================

validate_prerequisites() {
  log_debug "Validating prerequisites..."

  # Check for required tools using forge-core
  validate_required_commands "aws" || {
    log_error "Missing required tool: aws"
    log_error "Please install AWS CLI and try again"
    exit 1
  }

  # Optional tool check
  if ! command -v jq &> /dev/null; then
    log_warning "jq not found (optional, used for JSON formatting)"
  fi

  log_debug "All required tools found"
}

validate_arguments() {
  log_debug "Validating arguments..."

  local errors=()

  [ -z "$CUSTOMER" ] && errors+=("--customer is required")
  [ -z "$PROJECT" ] && errors+=("--project is required")
  [ -z "$SERVICE_NAME" ] && errors+=("--service-name is required")
  [ -z "$ENVIRONMENT" ] && errors+=("--environment is required")
  [ -z "$CLUSTER_NAME" ] && errors+=("--cluster-name is required")

  if [ ${#errors[@]} -gt 0 ]; then
    for error in "${errors[@]}"; do
      log_error "$error"
    done
    echo ""
    print_usage
    exit 1
  fi

  log_debug "All required arguments provided"
}

# ==============================================================================
# AWS Configuration
# ==============================================================================

configure_aws_cli() {
  log_debug "Configuring AWS CLI..."

  # Set AWS profile if specified
  if [ -n "$AWS_PROFILE" ]; then
    export AWS_PROFILE
    log_debug "Using AWS profile: $AWS_PROFILE"
  fi

  # Verify AWS credentials
  if ! aws sts get-caller-identity &> /dev/null; then
    log_error "Failed to authenticate with AWS"
    log_error "Check your AWS credentials and profile configuration"
    exit 1
  fi

  log_debug "AWS CLI configured successfully"
}

# ==============================================================================
# Image Operations
# ==============================================================================
# Note: These functions remain here as they are not yet in forge-ecr-operations.sh
# Future enhancement: Move to library if needed
# ==============================================================================

is_digest() {
  local identifier="$1"
  # Check if it's a SHA256 digest (sha256:... or 64 hex characters)
  if [[ "$identifier" =~ ^sha256:[a-f0-9]{64}$ ]] || [[ "$identifier" =~ ^[a-f0-9]{64}$ ]]; then
    return 0
  fi
  return 1
}

image_exists() {
  local repository_name="$1"
  local identifier="$2"
  
  log_info "Checking if image exists: $identifier"
  
  local image_param
  if is_digest "$identifier"; then
    image_param="imageDigest=$identifier"
  else
    image_param="imageTag=$identifier"
  fi
  
  local aws_cmd="aws ecr describe-images --repository-name $repository_name --region $AWS_REGION --image-ids $image_param"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "Image exists: $identifier"
    return 0
  else
    log_warning "Image not found: $identifier"
    return 1
  fi
}

delete_specific_image() {
  local repository_name="$1"
  local identifier="$2"
  
  log_info "Deleting image: $identifier"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would delete image: $identifier from $repository_name"
    return 0
  fi
  
  local image_param
  if is_digest "$identifier"; then
    image_param="imageDigest=$identifier"
  else
    image_param="imageTag=$identifier"
  fi
  
  local aws_cmd="aws ecr batch-delete-image --repository-name $repository_name --region $AWS_REGION --image-ids $image_param"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "Image deleted: $identifier"
    return 0
  else
    log_error "Failed to delete image: $identifier"
    return 1
  fi
}

wipe_repository_images() {
  local repository_name="$1"
  
  log_info "Wiping all images from repository: $repository_name"
  
  # Get all image IDs
  local image_ids
  local aws_cmd="aws ecr list-images --repository-name $repository_name --region $AWS_REGION --query 'imageIds[*].[imageDigest]' --output text"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  image_ids=$(eval "$aws_cmd" 2>/dev/null)
  
  if [ -z "$image_ids" ]; then
    log_warning "No images found in repository: $repository_name"
    return 0
  fi
  
  # Count images
  local image_count
  image_count=$(echo "$image_ids" | wc -l | xargs)
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would delete $image_count image(s) from $repository_name"
    return 0
  fi
  
  # Confirmation prompt
  if [ "$FORCE" = false ]; then
    echo ""
    log_warning "⚠️  WARNING: This will delete ALL $image_count images from the repository!"
    echo ""
    read -p "Type 'yes' to confirm: " -r
    echo ""
    if [[ ! $REPLY =~ ^yes$ ]]; then
      log_info "Wipe cancelled by user"
      return 0
    fi
  fi
  
  # Build image IDs for batch delete
  local image_id_params=()
  while IFS= read -r digest; do
    if [ -n "$digest" ]; then
      image_id_params+=("imageDigest=$digest")
    fi
  done <<< "$image_ids"
  
  # AWS supports up to 100 images per batch-delete-image call
  local batch_size=100
  local total=${#image_id_params[@]}
  local deleted=0
  
  for ((i=0; i<total; i+=batch_size)); do
    local batch=("${image_id_params[@]:i:batch_size}")
    local batch_count=${#batch[@]}
    
    log_info "Deleting batch: $((deleted+1))-$((deleted+batch_count)) of $total images..."
    
    local aws_cmd="aws ecr batch-delete-image --repository-name $repository_name --region $AWS_REGION --image-ids ${batch[*]}"
    
    if [ -n "$AWS_PROFILE" ]; then
      aws_cmd="$aws_cmd --profile $AWS_PROFILE"
    fi
    
    if eval "$aws_cmd" >/dev/null 2>&1; then
      ((deleted+=batch_count))
      log_success "Deleted $batch_count images"
    else
      log_error "Failed to delete batch"
      return 1
    fi
  done
  
  log_success "Successfully wiped $deleted images from repository: $repository_name"
  return 0
}

# ==============================================================================
# ECR Repository Operations - Create
# ==============================================================================
# Using functions from forge-ecr-operations.sh:
# - ensure_ecr_repository() - Create repository (idempotent)
# - apply_ecr_cluster_policy_with_builder() - Apply policy with Docker Builder
# - apply_ecr_lifecycle_policy_default() - Apply lifecycle policy (keep 4 images)
# ==============================================================================

create_ecr() {
  local env="$1"
  
  # Generate repository name using forge-patterns
  local repository_name
  repository_name=$(get_ecr_repository_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")
  
  log_info "Configuring ECR repository for: $CUSTOMER/$PROJECT/$env/$SERVICE_NAME"
  log_info "  Repository: $repository_name"
  log_info "  Region: $AWS_REGION"
  
  # Get AWS Account ID using forge-aws-discovery
  local aws_account_id
  aws_account_id=$(get_aws_account_id) || {
    FAILED_REPOS+=("$env: Failed to get AWS account ID")
    ((TOTAL_FAILED++))
    return 1
  }
  
  # Get EKS Cluster ARN using forge-aws-discovery
  local eks_cluster_arn
  eks_cluster_arn=$(get_eks_cluster_arn "$CLUSTER_NAME" "$AWS_REGION") || {
    FAILED_REPOS+=("$env: Failed to get EKS cluster ARN")
    ((TOTAL_FAILED++))
    return 1
  }
  
  # Check if repository exists using forge-ecr-operations
  if ecr_repository_exists "$repository_name" "$AWS_REGION"; then
    log_warning "ECR repository already exists: $repository_name"
    
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
      read -p "Update existing repository policies? (y/N): " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping repository update"
        ((TOTAL_SKIPPED++))
        return 0
      fi
    fi
  else
    # Create ECR repository using forge-ecr-operations
    if [ "$DRY_RUN" = true ]; then
      log_dry_run "Would create ECR repository: $repository_name"
      log_dry_run "  Tag mutability: MUTABLE"
      log_dry_run "  Scan on push: true"
      log_dry_run "  Tags: Customer=$CUSTOMER, Project=$PROJECT, Environment=$env, Service=$SERVICE_NAME"
    else
      local repo_info
      repo_info=$(ensure_ecr_repository \
        "$repository_name" \
        "MUTABLE" \
        "true" \
        "Customer=$CUSTOMER,Project=$PROJECT,Environment=$env,Service=$SERVICE_NAME,ManagedBy=forge") || {
        FAILED_REPOS+=("$env: Failed to create repository")
        ((TOTAL_FAILED++))
        return 1
      }
      log_success "ECR repository created: $repository_name"
      ((TOTAL_CREATED++))
    fi
  fi
  
  # Apply repository policy WITH DOCKER BUILDER using forge-ecr-operations
  # CRITICAL: Pass $SERVICE_NAME to enable per-service Docker Builder IAM role
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would apply repository policy with Docker Builder support"
    log_dry_run "  EKS Cluster: $eks_cluster_arn"
    log_dry_run "  Docker Builder Role: $(get_docker_builder_role_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")"
  else
    if ! apply_ecr_cluster_policy_with_builder \
      "$repository_name" \
      "$eks_cluster_arn" \
      "$aws_account_id" \
      "$CUSTOMER" \
      "$PROJECT" \
      "$env" \
      "$SERVICE_NAME"; then
      FAILED_REPOS+=("$env: Failed to apply repository policy")
      ((TOTAL_FAILED++))
      return 1
    fi
    log_success "Repository policy applied with Docker Builder support"
  fi
  
  # Apply lifecycle policy using forge-ecr-operations
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would apply lifecycle policy (keep last 4 images)"
  else
    if ! apply_ecr_lifecycle_policy_default "$repository_name"; then
      FAILED_REPOS+=("$env: Failed to apply lifecycle policy")
      ((TOTAL_FAILED++))
      return 1
    fi
    log_success "Lifecycle policy applied (keep last 4 images)"
  fi
  
  # Show repository URI
  local repository_uri="${aws_account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repository_name}"
  log_success "ECR repository configured successfully"
  log_info "  URI: $repository_uri"
  log_info "  Docker Builder Role: $(get_docker_builder_role_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")"
  
  CREATED_REPOS+=("$env:$repository_uri")
  
  return 0
}

# ==============================================================================
# ECR Repository Operations - Delete
# ==============================================================================
# Using functions from forge-ecr-operations.sh:
# - ecr_repository_exists() - Check if repository exists
# - delete_ecr_repository() - Delete repository with force option
# ==============================================================================

delete_ecr() {
  local env="$1"
  
  # Generate repository name using forge-patterns
  local repository_name
  repository_name=$(get_ecr_repository_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")
  
  log_info "Deleting ECR repository: $repository_name"
  
  # Check if repository exists using forge-ecr-operations
  if ! ecr_repository_exists "$repository_name" "$AWS_REGION"; then
    log_warning "ECR repository does not exist: $repository_name"
    ((TOTAL_SKIPPED++))
    return 0
  fi
  
  # Get image count
  local image_count
  image_count=$(aws ecr list-images \
    --repository-name "$repository_name" \
    --region "$AWS_REGION" \
    --query 'length(imageIds)' \
    --output text 2>/dev/null || echo "0")
  
  # Confirmation prompt
  if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    echo ""
    log_warning "⚠️  WARNING: This will delete the ECR repository and ALL images!"
    echo ""
    log_warning "Repository: $repository_name"
    log_warning "Images: $image_count"
    echo ""
    read -p "Type 'yes' to confirm deletion: " -r
    echo ""
    if [[ ! $REPLY =~ ^yes$ ]]; then
      log_info "Deletion cancelled by user"
      ((TOTAL_SKIPPED++))
      return 0
    fi
  fi
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would delete ECR repository: $repository_name"
    log_dry_run "  Images to delete: $image_count"
    return 0
  fi
  
  # Delete repository using forge-ecr-operations (force=true)
  if delete_ecr_repository "$repository_name" true; then
    log_success "ECR repository deleted: $repository_name"
    DELETED_REPOS+=("$env:$repository_name")
    ((TOTAL_DELETED++))
    return 0
  else
    log_error "Failed to delete ECR repository: $repository_name"
    FAILED_REPOS+=("$env: Failed to delete repository")
    ((TOTAL_FAILED++))
    return 1
  fi
}

# ==============================================================================
# Summary Functions
# ==============================================================================

print_create_summary() {
  echo ""
  echo -e "${CYAN}======================================${NC}"
  echo -e "${BOLD}      ECR REPOSITORY CREATION SUMMARY${NC}"
  echo -e "${CYAN}======================================${NC}"
  echo -e "Service: ${BOLD}$CUSTOMER/$PROJECT/$SERVICE_NAME${NC}"
  echo ""
  echo "Statistics:"
  echo "  Created:  ${GREEN}$TOTAL_CREATED${NC} repository(s)"
  echo "  Skipped:  ${YELLOW}$TOTAL_SKIPPED${NC} repository(s)"
  echo "  Failed:   ${RED}$TOTAL_FAILED${NC} repository(s)"
  echo ""
  
  if [ ${#CREATED_REPOS[@]} -gt 0 ]; then
    echo "Repository Details:"
    for repo_info in "${CREATED_REPOS[@]}"; do
      IFS=':' read -r env uri <<< "$repo_info"
      echo -e "  ${BOLD}[$env]${NC}"
      echo "    ${GREEN}✓${NC} Repository: ${uri##*/}"
      echo "    ${GREEN}✓${NC} URI: $uri"
      echo "    ${GREEN}✓${NC} Tag Mutability: MUTABLE"
      echo "    ${GREEN}✓${NC} Lifecycle: Keep last 4 images"
      echo "    ${GREEN}✓${NC} Access: EKS cluster $CLUSTER_NAME"
      echo ""
    done
    
    # Get AWS account ID for next steps
    local aws_account_id
    aws_account_id=$(get_aws_account_id)
    local example_uri="${CREATED_REPOS[0]#*:}"
    
    echo "Next Steps:"
    echo "  1. Login to ECR:"
    echo "     ${CYAN}aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${aws_account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com${NC}"
    echo ""
    echo "  2. Build and tag image:"
    echo "     ${CYAN}docker build -t $CUSTOMER/$PROJECT/\${ENV}/$SERVICE_NAME:\${GIT_COMMIT} .${NC}"
    echo ""
    echo "  3. Tag for ECR:"
    echo "     ${CYAN}docker tag $CUSTOMER/$PROJECT/\${ENV}/$SERVICE_NAME:\${GIT_COMMIT} $example_uri:\${GIT_COMMIT}${NC}"
    echo ""
    echo "  4. Push to ECR:"
    echo "     ${CYAN}docker push $example_uri:\${GIT_COMMIT}${NC}"
  fi
  
  if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo ""
    echo "Failed Operations:"
    for failure in "${FAILED_REPOS[@]}"; do
      echo "  ${RED}✗${NC} $failure"
    done
  fi
  
  echo -e "${CYAN}======================================${NC}"
  echo ""
}

print_delete_summary() {
  echo ""
  echo -e "${CYAN}======================================${NC}"
  echo -e "${BOLD}      ECR REPOSITORY DELETION SUMMARY${NC}"
  echo -e "${CYAN}======================================${NC}"
  echo -e "Service: ${BOLD}$CUSTOMER/$PROJECT/$SERVICE_NAME${NC}"
  echo ""
  echo "Statistics:"
  echo "  Deleted:  ${GREEN}$TOTAL_DELETED${NC} repository(s)"
  echo "  Skipped:  ${YELLOW}$TOTAL_SKIPPED${NC} repository(s)"
  echo "  Failed:   ${RED}$TOTAL_FAILED${NC} repository(s)"
  echo ""
  
  if [ ${#DELETED_REPOS[@]} -gt 0 ]; then
    echo "Deleted Repositories:"
    for repo_info in "${DELETED_REPOS[@]}"; do
      IFS=':' read -r env repo_name <<< "$repo_info"
      echo "  ${GREEN}✓${NC} [$env] $repo_name"
    done
    echo ""
  fi
  
  if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo "Failed Operations:"
    for failure in "${FAILED_REPOS[@]}"; do
      echo "  ${RED}✗${NC} $failure"
    done
    echo ""
  fi
  
  echo -e "${CYAN}======================================${NC}"
  echo ""
}

# ==============================================================================
# Main Processing Function
# ==============================================================================

process_environment() {
  local env="$1"
  
  log_step "Processing environment: $env"
  
  local repository_name
  repository_name=$(get_ecr_repository_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")
  
  # Check if repository exists for image operations
  if [ "$WIPE_IMAGES" = true ] || [ -n "$DELETE_IMAGE" ] || [ -n "$CHECK_IMAGE" ]; then
    if ! ecr_repository_exists "$repository_name" "$AWS_REGION"; then
      log_error "ECR repository does not exist: $repository_name"
      ((TOTAL_FAILED++))
      return 1
    fi
  fi
  
  # Handle image operations
  if [ "$WIPE_IMAGES" = true ]; then
    if wipe_repository_images "$repository_name"; then
      ((TOTAL_DELETED++))
    else
      ((TOTAL_FAILED++))
    fi
    return 0
  fi
  
  if [ -n "$DELETE_IMAGE" ]; then
    if delete_specific_image "$repository_name" "$DELETE_IMAGE"; then
      ((TOTAL_DELETED++))
    else
      ((TOTAL_FAILED++))
    fi
    return 0
  fi
  
  if [ -n "$CHECK_IMAGE" ]; then
    if image_exists "$repository_name" "$CHECK_IMAGE"; then
      ((TOTAL_SKIPPED++))  # Count as checked/success
    else
      ((TOTAL_FAILED++))
    fi
    return 0
  fi
  
  # Handle repository operations
  if [ "$DELETE_MODE" = true ]; then
    delete_ecr "$env"
  else
    create_ecr "$env"
  fi
}

# ==============================================================================
# Main Function
# ==============================================================================

main() {
  # Parse command-line arguments
  parse_arguments "$@"
  
  # Print banner
  print_banner
  
  # Validate prerequisites
  validate_prerequisites
  
  # Validate arguments
  validate_arguments
  
  # Configure AWS CLI
  configure_aws_cli
  
  # Show dry-run warning
  if [ "$DRY_RUN" = true ]; then
    log_warning "DRY-RUN MODE: No changes will be made to AWS"
    echo ""
  fi
  
  # Show delete warning
  if [ "$DELETE_MODE" = true ]; then
    log_warning "DELETE MODE: ECR repositories will be removed from AWS"
    echo ""
  fi
  
  # Display configuration
  log_info "Configuration:"
  log_info "  Customer:       $CUSTOMER"
  log_info "  Project:        $PROJECT"
  log_info "  Service:        $SERVICE_NAME"
  log_info "  Environment(s): $ENVIRONMENT"
  log_info "  Cluster:        $CLUSTER_NAME"
  log_info "  AWS Region:     $AWS_REGION"
  [ -n "$AWS_PROFILE" ] && log_info "  AWS Profile:    $AWS_PROFILE"
  echo ""
  
  # Split environments by comma and process each
  IFS=',' read -ra ENVS <<< "$ENVIRONMENT"
  for env in "${ENVS[@]}"; do
    # Trim whitespace
    env=$(echo "$env" | xargs)
    process_environment "$env"
  done
  
  # Print summary
  if [ "$DELETE_MODE" = true ]; then
    print_delete_summary
  else
    print_create_summary
  fi
  
  # Exit with appropriate code
  if [ $TOTAL_FAILED -gt 0 ]; then
    exit 1
  else
    exit 0
  fi
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

main "$@"
