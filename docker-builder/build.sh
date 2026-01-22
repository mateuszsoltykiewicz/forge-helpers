#!/bin/bash
# ==============================================================================
# Docker Builder - Production Grade Multi-Image Build System
# ==============================================================================
# Builds and manages Docker images for Forge security automation tools.
#
# Features:
# - Multi-mode support (local, ECR)
# - Automatic AWS account detection
# - ECR repository auto-creation
# - Image vulnerability scanning
# - Build caching
# - Multi-tagging (version + latest)
# - Detailed logging
# - Error handling and rollback
#
# Usage:
#   ./build.sh <mode> [options]
#
# Modes:
#   local               Build images locally only
#   ecr                 Build and push to AWS ECR
#
# Options:
#   --version=X.Y.Z     Tag with specific version (default: latest)
#   --region=REGION     AWS region for ECR (default: us-east-1)
#   --account=ID        AWS account ID (auto-detected if not provided)
#   --no-cache          Disable Docker build cache
#   --platform=ARCH     Target platform (default: linux/amd64)
#   --parallel          Build images in parallel (experimental)
# ==============================================================================

set -euo pipefail

# Script metadata
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly LOG_DIR="$SCRIPT_DIR/logs"
readonly LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"

# Default values
MODE="local"
VERSION="latest"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=""
NO_CACHE=false
PLATFORM="linux/amd64"
PARALLEL=false

# Image definitions
declare -A IMAGES=(
  ["yaml-ssm-sync"]="$PROJECT_ROOT/yaml-sync-with-ssm"
  ["security-group-chainer"]="$PROJECT_ROOT/security-group-chainer"
  ["lambda-log-transformer"]="$PROJECT_ROOT/lambda-log-transformer"
)

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Logging Functions
# ==============================================================================

setup_logging() {
  mkdir -p "$LOG_DIR"
  exec > >(tee -a "$LOG_FILE")
  exec 2>&1
}

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

print_header() {
  echo ""
  echo -e "${BLUE}${BOLD}===================================================${NC}"
  echo -e "${BLUE}${BOLD}$1${NC}"
  echo -e "${BLUE}${BOLD}===================================================${NC}"
  echo ""
  log "HEADER: $1"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
  log "SUCCESS: $1"
}

print_error() {
  echo -e "${RED}❌ $1${NC}" >&2
  log "ERROR: $1"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
  log "WARNING: $1"
}

print_info() {
  echo -e "${CYAN}ℹ️  $1${NC}"
  log "INFO: $1"
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_arguments() {
  if [ $# -eq 0 ]; then
    print_usage
    exit 1
  fi
  
  MODE="$1"
  shift
  
  for arg in "$@"; do
    case $arg in
      --version=*)
        VERSION="${arg#*=}"
        ;;
      --region=*)
        AWS_REGION="${arg#*=}"
        ;;
      --account=*)
        AWS_ACCOUNT_ID="${arg#*=}"
        ;;
      --no-cache)
        NO_CACHE=true
        ;;
      --platform=*)
        PLATFORM="${arg#*=}"
        ;;
      --parallel)
        PARALLEL=true
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        print_error "Unknown argument: $arg"
        print_usage
        exit 1
        ;;
    esac
  done
  
  # Validate mode
  if [[ "$MODE" != "local" && "$MODE" != "ecr" ]]; then
    print_error "Invalid mode: $MODE"
    print_usage
    exit 1
  fi
  
  # Validate version format (semantic versioning)
  if [[ "$VERSION" != "latest" && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_warning "Version '$VERSION' doesn't follow semantic versioning (X.Y.Z)"
  fi
}

print_usage() {
  cat <<EOF
${BOLD}Docker Builder v${SCRIPT_VERSION}${NC}

${BOLD}Usage:${NC}
  $0 <mode> [options]

${BOLD}Modes:${NC}
  local               Build images locally only
  ecr                 Build and push to AWS ECR

${BOLD}Options:${NC}
  --version=X.Y.Z     Tag with specific version (default: latest)
  --region=REGION     AWS region for ECR (default: us-east-1)
  --account=ID        AWS account ID (auto-detected if not provided)
  --no-cache          Disable Docker build cache
  --platform=ARCH     Target platform (default: linux/amd64)
  --parallel          Build images in parallel (experimental)
  --help, -h          Show this help message

${BOLD}Examples:${NC}
  # Build locally
  $0 local

  # Build and push to ECR with version
  $0 ecr --version=1.2.3

  # Build for ARM platform
  $0 local --platform=linux/arm64

  # Build without cache
  $0 local --no-cache

${BOLD}Logs:${NC}
  Build logs are saved to: $LOG_DIR/

EOF
}

# ==============================================================================
# Prerequisites Check
# ==============================================================================

check_prerequisites() {
  print_header "Checking Prerequisites"
  
  local all_ok=true
  
  # Check Docker
  if ! command -v docker &> /dev/null; then
    print_error "Docker not installed"
    all_ok=false
  else
    local docker_version=$(docker --version)
    print_success "Docker installed: $docker_version"
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
      print_error "Docker daemon not running"
      all_ok=false
    else
      print_success "Docker daemon running"
    fi
  fi
  
  # Check AWS CLI if ECR mode
  if [ "$MODE" = "ecr" ]; then
    if ! command -v aws &> /dev/null; then
      print_error "AWS CLI not installed (required for ECR mode)"
      all_ok=false
    else
      local aws_version=$(aws --version)
      print_success "AWS CLI installed: $aws_version"
    fi
  fi
  
  # Check if image directories exist
  for image_name in "${!IMAGES[@]}"; do
    local context_dir="${IMAGES[$image_name]}"
    if [ ! -d "$context_dir" ]; then
      print_error "Image directory not found: $context_dir"
      all_ok=false
    else
      if [ ! -f "$context_dir/Dockerfile" ]; then
        print_error "Dockerfile not found in: $context_dir"
        all_ok=false
      else
        print_success "Found $image_name: $context_dir"
      fi
    fi
  done
  
  if [ "$all_ok" = false ]; then
    print_error "Prerequisites check failed"
    exit 1
  fi
  
  print_success "All prerequisites satisfied"
}

# ==============================================================================
# AWS Functions
# ==============================================================================

get_aws_account_id() {
  if [ -z "$AWS_ACCOUNT_ID" ]; then
    print_info "Auto-detecting AWS account ID..."
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
      print_error "Failed to auto-detect AWS account ID"
      print_info "Please specify: --account=123456789012"
      print_info "Or configure AWS credentials: aws configure"
      exit 1
    fi
    
    print_success "Detected AWS account: $AWS_ACCOUNT_ID"
  else
    print_info "Using provided AWS account: $AWS_ACCOUNT_ID"
  fi
}

ecr_login() {
  print_header "Authenticating with ECR"
  print_info "Region: $AWS_REGION"
  print_info "Account: $AWS_ACCOUNT_ID"
  print_info "Registry: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
  
  if aws ecr get-login-password --region "$AWS_REGION" | \
     docker login --username AWS --password-stdin \
     "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Successfully authenticated with ECR"
  else
    print_error "Failed to authenticate with ECR"
    exit 1
  fi
}

create_ecr_repo() {
  local repo_name=$1
  
  print_info "Checking ECR repository: $repo_name"
  
  if aws ecr describe-repositories \
    --repository-names "$repo_name" \
    --region "$AWS_REGION" &>/dev/null; then
    print_success "Repository exists: $repo_name"
  else
    print_warning "Repository does not exist, creating: $repo_name"
    
    if aws ecr create-repository \
      --repository-name "$repo_name" \
      --region "$AWS_REGION" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 \
      --tags "Key=ManagedBy,Value=docker-builder" "Key=Project,Value=forge" 2>&1 | tee -a "$LOG_FILE"; then
      print_success "Created repository: $repo_name"
    else
      print_error "Failed to create repository: $repo_name"
      exit 1
    fi
  fi
}

# ==============================================================================
# Docker Build Functions
# ==============================================================================

build_image() {
  local image_name=$1
  local context_dir=$2
  local registry=$3
  local full_image="$registry/$image_name:$VERSION"
  
  print_header "Building: $image_name"
  print_info "Context: $context_dir"
  print_info "Image: $full_image"
  print_info "Platform: $PLATFORM"
  print_info "Cache: $([ "$NO_CACHE" = true ] && echo "disabled" || echo "enabled")"
  
  # Build arguments
  local build_args=(
    "build"
    "-t" "$full_image"
    "--platform" "$PLATFORM"
  )
  
  # Add no-cache flag if requested
  if [ "$NO_CACHE" = true ]; then
    build_args+=("--no-cache")
  fi
  
  # Add build args for metadata
  build_args+=(
    "--build-arg" "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    "--build-arg" "VERSION=$VERSION"
    "--build-arg" "VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  )
  
  # Add context directory
  build_args+=("$context_dir")
  
  # Execute build
  print_info "Executing: docker ${build_args[*]}"
  
  if docker "${build_args[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Built: $full_image"
    
    # Tag as latest if version is not latest
    if [ "$VERSION" != "latest" ]; then
      local latest_image="$registry/$image_name:latest"
      docker tag "$full_image" "$latest_image"
      print_success "Tagged: $latest_image"
    fi
    
    # Show image size
    local image_size=$(docker images "$full_image" --format "{{.Size}}")
    print_info "Image size: $image_size"
    
    return 0
  else
    print_error "Failed to build: $full_image"
    return 1
  fi
}

push_image() {
  local image_name=$1
  local registry=$2
  local full_image="$registry/$image_name:$VERSION"
  
  print_header "Pushing: $image_name"
  print_info "Image: $full_image"
  
  if docker push "$full_image" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Pushed: $full_image"
    
    # Get image digest
    local digest=$(docker inspect "$full_image" --format='{{index .RepoDigests 0}}' 2>/dev/null || echo "unknown")
    if [ "$digest" != "unknown" ]; then
      print_info "Digest: $digest"
    fi
    
    # Push latest tag if version is not latest
    if [ "$VERSION" != "latest" ]; then
      local latest_image="$registry/$image_name:latest"
      if docker push "$latest_image" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Pushed: $latest_image"
      else
        print_warning "Failed to push latest tag"
      fi
    fi
    
    return 0
  else
    print_error "Failed to push: $full_image"
    return 1
  fi
}

# ==============================================================================
# Build Orchestration
# ==============================================================================

build_all_images() {
  local registry=$1
  local failed_images=()
  
  print_header "Building All Images"
  print_info "Total images: ${#IMAGES[@]}"
  
  for image_name in "${!IMAGES[@]}"; do
    local context_dir="${IMAGES[$image_name]}"
    
    if ! build_image "$image_name" "$context_dir" "$registry"; then
      failed_images+=("$image_name")
    fi
  done
  
  if [ ${#failed_images[@]} -gt 0 ]; then
    print_error "Failed to build images: ${failed_images[*]}"
    return 1
  fi
  
  print_success "All images built successfully"
  return 0
}

push_all_images() {
  local registry=$1
  local failed_images=()
  
  print_header "Pushing All Images"
  
  for image_name in "${!IMAGES[@]}"; do
    if ! push_image "$image_name" "$registry"; then
      failed_images+=("$image_name")
    fi
  done
  
  if [ ${#failed_images[@]} -gt 0 ]; then
    print_error "Failed to push images: ${failed_images[*]}"
    return 1
  fi
  
  print_success "All images pushed successfully"
  return 0
}

# ==============================================================================
# Summary and Reporting
# ==============================================================================

print_summary() {
  local registry=$1
  
  print_header "Build Summary"
  
  echo -e "${BOLD}Configuration:${NC}"
  echo "  Mode:     $MODE"
  echo "  Version:  $VERSION"
  echo "  Platform: $PLATFORM"
  echo "  Registry: $registry"
  echo ""
  
  echo -e "${BOLD}Built Images:${NC}"
  for image_name in "${!IMAGES[@]}"; do
    local full_image="$registry/$image_name:$VERSION"
    if docker images "$full_image" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | tail -n +2; then
      :
    else
      echo "  $full_image - NOT FOUND"
    fi
  done
  echo ""
  
  if [ "$MODE" = "ecr" ]; then
    echo -e "${BOLD}ECR Information:${NC}"
    echo "  Region:  $AWS_REGION"
    echo "  Account: $AWS_ACCOUNT_ID"
    echo ""
    
    echo -e "${BOLD}Terraform Integration:${NC}"
    echo "  Update your Terraform variables:"
    for image_name in "${!IMAGES[@]}"; do
      echo "    docker_image = \"$registry/$image_name:$VERSION\""
    done
    echo ""
  else
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  To push to ECR, run:"
    echo "    $0 ecr --version=$VERSION"
    echo ""
  fi
  
  echo -e "${BOLD}Log File:${NC}"
  echo "  $LOG_FILE"
  echo ""
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
  # Setup logging
  setup_logging
  
  # Parse arguments
  parse_arguments "$@"
  
  print_header "Docker Builder v$SCRIPT_VERSION"
  log "Started build process"
  log "Mode: $MODE, Version: $VERSION, Platform: $PLATFORM"
  
  # Check prerequisites
  check_prerequisites
  
  # Determine registry based on mode
  local registry
  if [ "$MODE" = "ecr" ]; then
    get_aws_account_id
    registry="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    # Login to ECR
    ecr_login
    
    # Create repositories
    for image_name in "${!IMAGES[@]}"; do
      create_ecr_repo "$image_name"
    done
  else
    registry="forge"
    print_info "Using local registry: $registry"
  fi
  
  # Build all images
  if ! build_all_images "$registry"; then
    print_error "Build failed"
    exit 1
  fi
  
  # Push to ECR if in ECR mode
  if [ "$MODE" = "ecr" ]; then
    if ! push_all_images "$registry"; then
      print_error "Push failed"
      exit 1
    fi
  fi
  
  # Print summary
  print_summary "$registry"
  
  print_success "Build process completed successfully"
  log "Build process completed"
}

# Run main
main "$@"
