#!/bin/bash
# ==============================================================================
# Generic AWS ECR Image Copy/Promotion Script
# ==============================================================================
# Description: Copies container images between ECR repositories for promotion
# Version: 2.0.0
# Compatible: bash 3.2+ (macOS compatible)
#
# Use Cases:
#   - Promote dev images to staging
#   - Promote staging images to production
#   - Copy images between environments
#   - Disaster recovery / backup
#
# Usage:
#   ./ecr_copy.sh --aws-account-id ACCOUNT --aws-region REGION \
#                 --customer CUSTOMER --project PROJECT --service-name SERVICE \
#                 --source-env ENV --target-env ENV --image-tag TAG [OPTIONS]
#
# Examples:
#   # Promote from dev to staging
#   ./ecr_copy.sh --aws-account-id 398456183268 --aws-region eu-central-1 \
#                 --customer sanofi --project cronus --service-name video-calling \
#                 --source-env dev --target-env staging --image-tag 65a945c
#
#   # Promote to prod with additional tags
#   ./ecr_copy.sh --aws-account-id 398456183268 --aws-region eu-central-1 \
#                 --customer sanofi --project cronus --service-name video-calling \
#                 --source-env staging --target-env prod --image-tag 65a945c \
#                 --target-tags latest,v1.2.3,stable
#
#   # Dry-run preview
#   ./ecr_copy.sh --aws-account-id 398456183268 --aws-region eu-central-1 \
#                 --customer sanofi --project cronus --service-name video-calling \
#                 --source-env dev --target-env staging --image-tag 65a945c \
#                 --dry-run
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Script Configuration
# ==============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ==============================================================================
# Color Codes
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
AWS_ACCOUNT_ID=""
AWS_REGION=""
CUSTOMER=""
PROJECT=""
SERVICE_NAME=""
SOURCE_ENV=""
TARGET_ENV=""
IMAGE_TAG=""

# Optional arguments
TARGET_TAGS=""
AWS_PROFILE=""

# Operation flags
SKIP_SOURCE_CHECK=false
OVERWRITE=false
DRY_RUN=false
FORCE=false
VERBOSE=false

# Computed values (set in main)
SOURCE_REPO_NAME=""
TARGET_REPO_NAME=""
SOURCE_REPO_URI=""
TARGET_REPO_URI=""

# ==============================================================================
# Logging Functions
# ==============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC}  $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC}     $*"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC}  $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
  if [ "$VERBOSE" = true ]; then
    echo -e "${MAGENTA}[DEBUG]${NC} $*"
  fi
}

log_dry_run() {
  echo -e "${CYAN}[DRY]${NC}   $*"
}

log_step() {
  echo ""
  echo -e "${CYAN}========================================${NC}"
  echo -e "${BOLD}$*${NC}"
  echo -e "${CYAN}========================================${NC}"
  echo ""
}

# ==============================================================================
# Helper Functions
# ==============================================================================

print_banner() {
  echo -e "${CYAN}"
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║         Generic AWS ECR Image Copy/Promotion Script         ║
║                       Version 2.0.0                          ║
╚══════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
  echo ""
}

print_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

REQUIRED ARGUMENTS:
  --aws-account-id ACCOUNT          AWS account ID (e.g., 398456183268)
  --aws-region REGION               AWS region (e.g., eu-central-1)
  --customer CUSTOMER               Customer name (e.g., sanofi, indegene)
  --project PROJECT                 Project name (e.g., cronus, platform)
  --service-name SERVICE            Service name (e.g., video-calling, api-gateway)
  --source-env ENV                  Source environment (dev, staging)
  --target-env ENV                  Target environment (staging, prod)
  --image-tag TAG                   Image tag to copy (e.g., 65a945c, v1.2.3, latest)

OPTIONAL ARGUMENTS:
  --target-tags TAGS                Additional tags for target (comma-separated)
                                    Example: --target-tags latest,v1.2.3,stable
  --aws-profile PROFILE             AWS CLI profile to use (optional)
  --skip-source-check               Skip checking if source image exists
  --overwrite                       Overwrite existing target image if it exists

CONTROL FLAGS:
  --dry-run                         Preview without making changes
  --force                           Skip confirmation prompts
  --verbose                         Enable verbose logging
  -h, --help                        Show this help message
  -v, --version                     Show script version

EXAMPLES:
  # Promote from dev to staging
  ${SCRIPT_NAME} --aws-account-id 398456183268 --aws-region eu-central-1 \\
                 --customer sanofi --project cronus --service-name video-calling \\
                 --source-env dev --target-env staging --image-tag 65a945c

  # Promote to prod with additional tags
  ${SCRIPT_NAME} --aws-account-id 398456183268 --aws-region eu-central-1 \\
                 --customer sanofi --project cronus --service-name video-calling \\
                 --source-env staging --target-env prod --image-tag 65a945c \\
                 --target-tags latest,v1.2.3,stable

  # Dry-run preview
  ${SCRIPT_NAME} --aws-account-id 398456183268 --aws-region eu-central-1 \\
                 --customer sanofi --project cronus --service-name video-calling \\
                 --source-env dev --target-env staging --image-tag 65a945c \\
                 --dry-run

  # With AWS profile
  ${SCRIPT_NAME} --aws-account-id 398456183268 --aws-region us-east-1 \\
                 --aws-profile production \\
                 --customer indegene --project platform --service-name api-gateway \\
                 --source-env staging --target-env prod --image-tag v2.1.0

  # Force overwrite existing image
  ${SCRIPT_NAME} --aws-account-id 398456183268 --aws-region eu-central-1 \\
                 --customer sanofi --project cronus --service-name video-calling \\
                 --source-env dev --target-env staging --image-tag 65a945c \\
                 --overwrite --force

REPOSITORY NAMING:
  Format: {customer}/{project}/{environment}/{service}
  Source: sanofi/cronus/dev/video-calling
  Target: sanofi/cronus/staging/video-calling

IMAGE COPY PROCESS:
  1. Validate source and target repositories exist
  2. Check source image exists
  3. Login to ECR
  4. Pull source image from ECR
  5. Tag image for target repository
  6. Push image to target repository
  7. Verify image integrity (digest comparison)
  8. Apply additional tags if specified
  9. Cleanup local Docker images

SECURITY:
  - Digest verification ensures byte-for-byte identical copy
  - Confirmation prompts for production promotions
  - Dry-run mode for previewing operations
  - AWS CLI credentials required (IAM user/role)

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
      --aws-account-id)
        AWS_ACCOUNT_ID="$2"
        shift 2
        ;;
      --aws-region)
        AWS_REGION="$2"
        shift 2
        ;;
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
      --source-env)
        SOURCE_ENV="$2"
        shift 2
        ;;
      --target-env)
        TARGET_ENV="$2"
        shift 2
        ;;
      --image-tag)
        IMAGE_TAG="$2"
        shift 2
        ;;
      --target-tags)
        TARGET_TAGS="$2"
        shift 2
        ;;
      --aws-profile)
        AWS_PROFILE="$2"
        shift 2
        ;;
      --skip-source-check)
        SKIP_SOURCE_CHECK=true
        shift
        ;;
      --overwrite)
        OVERWRITE=true
        shift
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

validate_prerequisites() {
  log_debug "Validating prerequisites..."
  
  local missing_tools=()
  
  # Check for Docker
  if ! command -v docker &> /dev/null; then
    missing_tools+=("docker")
  else
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
      log_error "Docker daemon is not running"
      log_error "Start Docker and try again"
      exit 1
    fi
  fi
  
  # Check for AWS CLI
  if ! command -v aws &> /dev/null; then
    missing_tools+=("aws")
  fi
  
  # Check for jq (optional)
  if ! command -v jq &> /dev/null; then
    log_warning "jq not found (optional, used for JSON formatting)"
  fi
  
  if [ ${#missing_tools[@]} -gt 0 ]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    log_error "Install missing tools:"
    for tool in "${missing_tools[@]}"; do
      if [ "$tool" = "docker" ]; then
        log_error "  - Docker: https://docs.docker.com/get-docker/"
      elif [ "$tool" = "aws" ]; then
        log_error "  - AWS CLI: brew install awscli"
      fi
    done
    exit 1
  fi
  
  log_debug "All required tools found"
}

validate_arguments() {
  log_debug "Validating arguments..."
  
  local errors=()
  
  [ -z "$AWS_ACCOUNT_ID" ] && errors+=("--aws-account-id is required")
  [ -z "$AWS_REGION" ] && errors+=("--aws-region is required")
  [ -z "$CUSTOMER" ] && errors+=("--customer is required")
  [ -z "$PROJECT" ] && errors+=("--project is required")
  [ -z "$SERVICE_NAME" ] && errors+=("--service-name is required")
  [ -z "$SOURCE_ENV" ] && errors+=("--source-env is required")
  [ -z "$TARGET_ENV" ] && errors+=("--target-env is required")
  [ -z "$IMAGE_TAG" ] && errors+=("--image-tag is required")
  
  # Validate AWS account ID format (12 digits)
  if [ -n "$AWS_ACCOUNT_ID" ] && ! [[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    errors+=("--aws-account-id must be a 12-digit number")
  fi
  
  # Validate source and target are different
  if [ -n "$SOURCE_ENV" ] && [ -n "$TARGET_ENV" ] && [ "$SOURCE_ENV" = "$TARGET_ENV" ]; then
    errors+=("--source-env and --target-env must be different")
  fi
  
  if [ ${#errors[@]} -gt 0 ]; then
    for error in "${errors[@]}"; do
      log_error "$error"
    done
    echo ""
    print_usage
    exit 1
  fi
  
  log_debug "All required arguments provided and valid"
}

configure_aws_cli() {
  log_debug "Configuring AWS CLI..."
  
  # Set AWS profile if specified
  if [ -n "$AWS_PROFILE" ]; then
    export AWS_PROFILE
    log_debug "Using AWS profile: $AWS_PROFILE"
  fi
  
  # Verify AWS credentials
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "Failed to authenticate with AWS"
    log_error "Check your AWS credentials and profile configuration"
    exit 1
  fi
  
  log_debug "AWS CLI configured successfully"
}

# ==============================================================================
# Naming Convention Functions
# ==============================================================================

get_ecr_repository_name() {
  local customer="$1"
  local project="$2"
  local env="$3"
  local service="$4"
  echo "${customer}/${project}/${env}/${service}"
}

get_ecr_repository_uri() {
  local account_id="$1"
  local region="$2"
  local customer="$3"
  local project="$4"
  local env="$5"
  local service="$6"
  
  local repo_name
  repo_name=$(get_ecr_repository_name "$customer" "$project" "$env" "$service")
  echo "${account_id}.dkr.ecr.${region}.amazonaws.com/${repo_name}"
}

# ==============================================================================
# ECR Helper Functions
# ==============================================================================

image_exists_in_ecr() {
  local repository_name="$1"
  local tag="$2"
  
  log_debug "Checking if image exists: ${repository_name}:${tag}"
  
  local aws_cmd="aws ecr describe-images --repository-name $repository_name --region $AWS_REGION --image-ids imageTag=$tag"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_debug "Image exists: ${repository_name}:${tag}"
    return 0
  else
    log_debug "Image not found: ${repository_name}:${tag}"
    return 1
  fi
}

get_image_digest() {
  local repository_name="$1"
  local tag="$2"
  
  log_debug "Getting image digest for: ${repository_name}:${tag}"
  
  local aws_cmd="aws ecr describe-images --repository-name $repository_name --region $AWS_REGION --image-ids imageTag=$tag --query 'imageDetails[0].imageDigest' --output text"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  local digest
  digest=$(eval "$aws_cmd" 2>/dev/null)
  
  if [ -z "$digest" ] || [ "$digest" = "None" ]; then
    log_error "Failed to get image digest"
    return 1
  fi
  
  echo "$digest"
}

validate_repositories() {
  log_info "Validating ECR repositories..."
  
  # Check source repository
  local source_check_cmd="aws ecr describe-repositories --repository-names $SOURCE_REPO_NAME --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    source_check_cmd="$source_check_cmd --profile $AWS_PROFILE"
  fi
  
  if ! eval "$source_check_cmd" >/dev/null 2>&1; then
    log_error "Source repository does not exist: $SOURCE_REPO_NAME"
    log_error "Create it first with: ./ecr.sh --customer $CUSTOMER --project $PROJECT --service-name $SERVICE_NAME --environment $SOURCE_ENV --cluster-name <cluster>"
    return 1
  fi
  log_success "Source repository exists: $SOURCE_REPO_NAME"
  
  # Check target repository
  local target_check_cmd="aws ecr describe-repositories --repository-names $TARGET_REPO_NAME --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    target_check_cmd="$target_check_cmd --profile $AWS_PROFILE"
  fi
  
  if ! eval "$target_check_cmd" >/dev/null 2>&1; then
    log_error "Target repository does not exist: $TARGET_REPO_NAME"
    log_error "Create it first with: ./ecr.sh --customer $CUSTOMER --project $PROJECT --service-name $SERVICE_NAME --environment $TARGET_ENV --cluster-name <cluster>"
    return 1
  fi
  log_success "Target repository exists: $TARGET_REPO_NAME"
  
  return 0
}

ecr_login() {
  local account_id="$1"
  local region="$2"
  
  log_info "Logging into ECR..."
  
  local login_cmd="aws ecr get-login-password --region $region"
  
  if [ -n "$AWS_PROFILE" ]; then
    login_cmd="$login_cmd --profile $AWS_PROFILE"
  fi
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would login to ECR: ${account_id}.dkr.ecr.${region}.amazonaws.com"
    return 0
  fi
  
  if eval "$login_cmd" | docker login --username AWS --password-stdin "${account_id}.dkr.ecr.${region}.amazonaws.com" >/dev/null 2>&1; then
    log_success "ECR login successful"
    return 0
  else
    log_error "ECR login failed"
    return 1
  fi
}

# ==============================================================================
# Image Copy Functions
# ==============================================================================

tag_target_image() {
  local target_repo_uri="$1"
  local source_tag="$2"
  local additional_tag="$3"
  
  log_info "Applying additional tag: $additional_tag"
  
  local source_image="${target_repo_uri}:${source_tag}"
  local tagged_image="${target_repo_uri}:${additional_tag}"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would apply tag: $additional_tag"
    return 0
  fi
  
  # Pull the target image (already in ECR)
  if ! docker pull "${source_image}" >/dev/null 2>&1; then
    log_error "Failed to pull target image for tagging"
    return 1
  fi
  
  # Tag with additional tag
  if ! docker tag "${source_image}" "${tagged_image}" >/dev/null 2>&1; then
    log_error "Failed to apply additional tag"
    return 1
  fi
  
  # Push with new tag
  if ! docker push "${tagged_image}" >/dev/null 2>&1; then
    log_error "Failed to push image with additional tag"
    return 1
  fi
  
  log_success "Additional tag applied: $additional_tag"
  docker rmi "${tagged_image}" >/dev/null 2>&1 || true
  
  return 0
}

copy_image() {
  local source_repo_uri="$1"
  local source_tag="$2"
  local target_repo_uri="$3"
  local target_tag="$4"
  
  local source_image="${source_repo_uri}:${source_tag}"
  local target_image="${target_repo_uri}:${target_tag}"
  
  log_info "Copying image:"
  log_info "  Source: ${source_image}"
  log_info "  Target: ${target_image}"
  echo ""
  
  # Step 1: Get source image digest
  log_debug "Getting source image digest..."
  local source_digest
  source_digest=$(get_image_digest "$SOURCE_REPO_NAME" "$source_tag") || return 1
  log_debug "Source digest: $source_digest"
  
  # Step 2: Check if target image already exists
  if image_exists_in_ecr "$TARGET_REPO_NAME" "$target_tag"; then
    log_warning "Target image already exists: ${target_image}"
    
    if [ "$OVERWRITE" = false ]; then
      log_error "Use --overwrite to replace existing image"
      return 1
    fi
    
    log_warning "Overwriting existing image..."
  fi
  
  # Step 3: Pull source image
  log_info "Pulling source image..."
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would pull: docker pull ${source_image}"
  else
    if ! docker pull "${source_image}" >/dev/null 2>&1; then
      log_error "Failed to pull source image"
      return 1
    fi
    log_success "Source image pulled"
  fi
  
  # Step 4: Tag image for target repository
  log_info "Tagging image for target repository..."
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would tag: docker tag ${source_image} ${target_image}"
  else
    if ! docker tag "${source_image}" "${target_image}" >/dev/null 2>&1; then
      log_error "Failed to tag image"
      return 1
    fi
    log_success "Image tagged for target"
  fi
  
  # Step 5: Push to target repository
  log_info "Pushing to target repository..."
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would push: docker push ${target_image}"
  else
    if ! docker push "${target_image}" >/dev/null 2>&1; then
      log_error "Failed to push to target repository"
      return 1
    fi
    log_success "Image pushed to target repository"
  fi
  
  # Step 6: Verify digest matches
  log_info "Verifying image integrity..."
  if [ "$DRY_RUN" = false ]; then
    local target_digest
    target_digest=$(get_image_digest "$TARGET_REPO_NAME" "$target_tag")
    
    if [ "$source_digest" != "$target_digest" ]; then
      log_error "Digest mismatch! Source and target images differ"
      log_error "  Source digest: $source_digest"
      log_error "  Target digest: $target_digest"
      return 1
    fi
    log_success "Image integrity verified (digests match)"
  else
    log_dry_run "Would verify digest: $source_digest"
  fi
  
  # Step 7: Apply additional tags if specified
  if [ -n "$TARGET_TAGS" ]; then
    echo ""
    log_info "Applying additional tags..."
    IFS=',' read -ra EXTRA_TAGS <<< "$TARGET_TAGS"
    for extra_tag in "${EXTRA_TAGS[@]}"; do
      extra_tag=$(echo "$extra_tag" | xargs)  # Trim whitespace
      tag_target_image "$target_repo_uri" "$target_tag" "$extra_tag" || return 1
    done
  fi
  
  # Step 8: Cleanup local images
  if [ "$DRY_RUN" = false ]; then
    log_debug "Cleaning up local images..."
    docker rmi "${source_image}" >/dev/null 2>&1 || true
    docker rmi "${target_image}" >/dev/null 2>&1 || true
  fi
  
  log_success "Image copy completed successfully"
  return 0
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
  
  # Build repository names and URIs
  SOURCE_REPO_NAME=$(get_ecr_repository_name "$CUSTOMER" "$PROJECT" "$SOURCE_ENV" "$SERVICE_NAME")
  TARGET_REPO_NAME=$(get_ecr_repository_name "$CUSTOMER" "$PROJECT" "$TARGET_ENV" "$SERVICE_NAME")
  SOURCE_REPO_URI=$(get_ecr_repository_uri "$AWS_ACCOUNT_ID" "$AWS_REGION" "$CUSTOMER" "$PROJECT" "$SOURCE_ENV" "$SERVICE_NAME")
  TARGET_REPO_URI=$(get_ecr_repository_uri "$AWS_ACCOUNT_ID" "$AWS_REGION" "$CUSTOMER" "$PROJECT" "$TARGET_ENV" "$SERVICE_NAME")
  
  # Display configuration
  log_info "Configuration:"
  log_info "  Customer:        $CUSTOMER"
  log_info "  Project:         $PROJECT"
  log_info "  Service:         $SERVICE_NAME"
  log_info "  Image Tag:       $IMAGE_TAG"
  log_info "  Source Env:      $SOURCE_ENV"
  log_info "  Target Env:      $TARGET_ENV"
  log_info "  AWS Account ID:  $AWS_ACCOUNT_ID"
  log_info "  AWS Region:      $AWS_REGION"
  [ -n "$AWS_PROFILE" ] && log_info "  AWS Profile:     $AWS_PROFILE"
  [ -n "$TARGET_TAGS" ] && log_info "  Additional Tags: $TARGET_TAGS"
  echo ""
  
  log_info "Image Copy:"
  log_info "  FROM: ${SOURCE_REPO_URI}:${IMAGE_TAG}"
  log_info "  TO:   ${TARGET_REPO_URI}:${IMAGE_TAG}"
  echo ""
  
  # Dry-run warning
  if [ "$DRY_RUN" = true ]; then
    log_warning "DRY-RUN MODE: No images will be copied"
    echo ""
  fi
  
  # Validate repositories exist
  validate_repositories || exit 1
  echo ""
  
  # Check if source image exists (unless skipped)
  if [ "$SKIP_SOURCE_CHECK" = false ]; then
    if ! image_exists_in_ecr "$SOURCE_REPO_NAME" "$IMAGE_TAG"; then
      log_error "Source image does not exist: ${SOURCE_REPO_URI}:${IMAGE_TAG}"
      echo ""
      log_info "Available tags in source repository:"
      local list_cmd="aws ecr list-images --repository-name $SOURCE_REPO_NAME --region $AWS_REGION --query 'imageIds[*].imageTag' --output table"
      if [ -n "$AWS_PROFILE" ]; then
        list_cmd="$list_cmd --profile $AWS_PROFILE"
      fi
      eval "$list_cmd" || true
      exit 1
    fi
    log_success "Source image found: ${SOURCE_REPO_URI}:${IMAGE_TAG}"
    echo ""
  fi
  
  # Confirmation prompt
  if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    log_warning "⚠️  You are about to copy an image between environments:"
    log_warning "    FROM: $SOURCE_ENV"
    log_warning "    TO:   $TARGET_ENV"
    echo ""
    read -p "Type 'yes' to confirm: " -r
    echo ""
    if [[ ! $REPLY =~ ^yes$ ]]; then
      log_info "Copy cancelled by user"
      exit 0
    fi
  fi
  
  # Login to ECR
  ecr_login "$AWS_ACCOUNT_ID" "$AWS_REGION" || exit 1
  echo ""
  
  # Copy the image
  if copy_image "$SOURCE_REPO_URI" "$IMAGE_TAG" "$TARGET_REPO_URI" "$IMAGE_TAG"; then
    log_step "IMAGE COPY SUCCESSFUL"
    
    log_success "Image successfully promoted from $SOURCE_ENV to $TARGET_ENV"
    echo ""
    log_info "Target Image:"
    log_info "  ${TARGET_REPO_URI}:${IMAGE_TAG}"
    echo ""
    
    if [ -n "$TARGET_TAGS" ]; then
      log_info "Applied additional tags:"
      IFS=',' read -ra EXTRA_TAGS <<< "$TARGET_TAGS"
      for tag in "${EXTRA_TAGS[@]}"; do
        tag=$(echo "$tag" | xargs)
        log_info "  ✓ ${TARGET_REPO_URI}:${tag}"
      done
      echo ""
    fi
    
    log_info "Next Steps:"
    log_info "  1. Update Helm values for $TARGET_ENV environment:"
    log_info "     ${CYAN}image.tag: \"${IMAGE_TAG}\"${NC}"
    echo ""
    log_info "  2. Deploy to $TARGET_ENV:"
    log_info "     ${CYAN}helm upgrade <release> <chart> -f values-${TARGET_ENV}.yaml${NC}"
    echo ""
    
    exit 0
  else
    log_error "Image copy failed"
    exit 1
  fi
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

main "$@"

# ==============================================================================
# FUTURE FEATURES
# ==============================================================================
# The following features could be added in future versions:
#
# 1. CROSS-REGION COPY
#    - Copy images between different AWS regions
#    - Arguments: --source-region, --target-region
#    - Use case: Disaster recovery, multi-region deployments
#
# 2. CROSS-ACCOUNT COPY
#    - Copy images between different AWS accounts
#    - Arguments: --source-account-id, --target-account-id
#    - Use case: Multi-account architectures, partner integrations
#
# 3. BATCH PROMOTION
#    - Promote multiple images in a single operation
#    - Arguments: --image-tags (comma-separated list)
#    - Use case: Promoting all microservices at once
#
# 4. ROLLBACK SUPPORT
#    - Track promotion history and enable rollbacks
#    - Arguments: --rollback, --history
#    - Use case: Quick recovery from failed deployments
#
# 5. MANIFEST INSPECTION
#    - Display image layers, size, and metadata before copy
#    - Arguments: --inspect
#    - Use case: Pre-copy validation, size estimation
#
# 6. COPY WITH FILTERING
#    - Copy only specific image layers or architectures
#    - Arguments: --architecture (amd64, arm64, etc.)
#    - Use case: Multi-architecture images, layer optimization
#
# 7. AUTOMATED TAGGING
#    - Auto-generate tags based on patterns (date, version bump)
#    - Arguments: --auto-tag-pattern
#    - Use case: Consistent versioning, automated releases
#
# 8. SLACK/TEAMS NOTIFICATIONS
#    - Send notifications on successful promotions
#    - Arguments: --notify-webhook
#    - Use case: Team awareness, audit trail
#
# 9. PROMOTION APPROVAL
#    - Require manual approval before copying to prod
#    - Arguments: --require-approval
#    - Use case: Production safety, compliance
#
# 10. COST ESTIMATION
#     - Estimate ECR storage and transfer costs
#     - Arguments: --estimate-cost
#     - Use case: Budget planning, cost optimization
#
# ==============================================================================
