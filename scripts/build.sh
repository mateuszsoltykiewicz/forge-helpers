#!/bin/bash
################################################################################
# Forge Docker Image Builder v3.0.0
################################################################################
# Description: Library-based Docker image builder for Forge services
# Version: 3.0.0
# Author: Moai Forge Team
#
# Features:
# - Library-based implementation (maximum code reuse)
# - Docker Buildx support with fallback to traditional Docker
# - Automatic service name and AWS region detection
# - Git commit SHA tagging (NO latest tags - breaking change)
# - Image existence checking with --force-build override
# - Build and push retry logic with exponential backoff
# - ECR authentication (local AWS CLI + in-cluster IRSA)
# - Image digest verification (local vs remote)
# - Least-config approach via environment variables
# - Dry-run mode for validation
#
# Breaking Changes from v2.0.0:
# - NO latest tags created (SHA tags only)
# - Requires forge-helpers/lib directory
# - Buildx-first architecture
################################################################################

set -euo pipefail

################################################################################
# Script Setup
################################################################################

readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../lib"

################################################################################
# Load Libraries
################################################################################

[[ ! -d "$LIB_DIR" ]] && { echo "ERROR: Library directory not found: $LIB_DIR" >&2; exit 1; }

source "${LIB_DIR}/forge-core.sh" || { echo "ERROR: Failed to load forge-core.sh" >&2; exit 1; }
source "${LIB_DIR}/forge-patterns.sh" || { log_error "Failed to load forge-patterns.sh"; exit 1; }
source "${LIB_DIR}/forge-aws-discovery.sh" || { log_error "Failed to load forge-aws-discovery.sh"; exit 1; }
source "${LIB_DIR}/forge-k8s-discovery.sh" || { log_error "Failed to load forge-k8s-discovery.sh"; exit 1; }
source "${LIB_DIR}/forge-git-operations.sh" || { log_error "Failed to load forge-git-operations.sh"; exit 1; }
source "${LIB_DIR}/forge-docker-discovery.sh" || { log_error "Failed to load forge-docker-discovery.sh"; exit 1; }

################################################################################
# Constants
################################################################################

readonly DEFAULT_BUILD_CONTEXT="."
readonly DEFAULT_DOCKERFILE="Dockerfile"
readonly DEFAULT_PLATFORM="linux/arm64"
readonly DEFAULT_BUILD_RETRIES=3
readonly DEFAULT_PUSH_RETRIES=3

################################################################################
# Configuration Variables
################################################################################

CUSTOMER="${FORGE_CUSTOMER:-}"
PROJECT="${FORGE_PROJECT:-}"
ENVIRONMENT="${FORGE_ENVIRONMENT:-}"
SERVICE_NAME="${FORGE_SERVICE:-}"
BUILD_CONTEXT="${DEFAULT_BUILD_CONTEXT}"
DOCKERFILE_PATH="${DEFAULT_DOCKERFILE}"
PLATFORM="${DEFAULT_PLATFORM}"
GIT_BRANCH=""
GIT_SHA=""
AWS_REGION="${AWS_REGION:-}"
BUILD_RETRIES="${DEFAULT_BUILD_RETRIES}"
PUSH_RETRIES="${DEFAULT_PUSH_RETRIES}"
AWS_ACCOUNT_ID=""
ECR_REGISTRY=""
ECR_REPOSITORY=""
PRIMARY_IMAGE_URI=""
DRY_RUN=false
NO_CACHE=false
FORCE_BUILD=false
SKIP_PUSH=false
VERBOSE=false
BUILD_START_TIME=""
BUILD_END_TIME=""
LOCAL_IMAGE_DIGEST=""
REMOTE_IMAGE_DIGEST=""
BUILD_BACKEND=""
AUTO_DETECTED_SERVICE=false
AUTO_DETECTED_REGION=false
AUTO_DETECTED_SHA=false
AUTO_DETECTED_BRANCH=false

################################################################################
# Help & Usage
################################################################################

print_banner() {
  cat <<'BANNER'
╔══════════════════════════════════════════════════════════════╗
║       Forge Docker Image Builder - v3.0.0                   ║
║       Library-Based | Buildx-First | No Latest Tags         ║
╚══════════════════════════════════════════════════════════════╝
BANNER
  echo ""
}

print_version() {
  echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

print_usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS]

REQUIRED:
  --customer C      Customer name
  --project P       Project name
  --environment E   Environment (dev/staging/prod)

OPTIONAL (auto-detected):
  --service-name S  Service name (default: auto-detect from directory/git)
  --aws-region R    AWS region (default: auto-detect from AWS config)

BUILD:
  --build-context PATH    Build context (default: .)
  --dockerfile PATH       Dockerfile path (default: Dockerfile)
  --platform PLATFORM     Target platform (default: $DEFAULT_PLATFORM)
  --branch BRANCH         Git branch to checkout
  --no-cache              Disable Docker cache
  --build-retries N       Build retry attempts (default: $DEFAULT_BUILD_RETRIES)
  --push-retries N        Push retry attempts (default: $DEFAULT_PUSH_RETRIES)

FLAGS:
  --dry-run         Preview actions only
  --force-build     Build even if image exists
  --skip-push       Build only, skip push
  --verbose         Verbose logging
  -h, --help        Show help
  -v, --version     Show version

ENVIRONMENT VARIABLES:
  FORGE_CUSTOMER, FORGE_PROJECT, FORGE_ENVIRONMENT, FORGE_SERVICE
  AWS_REGION, BUILD_RETRY_ATTEMPTS, PUSH_RETRY_ATTEMPTS

EXAMPLES:
  # Minimal (auto-detect service and region)
  export FORGE_CUSTOMER=sanofi FORGE_PROJECT=cronus FORGE_ENVIRONMENT=dev
  $SCRIPT_NAME

  # Explicit all parameters
  $SCRIPT_NAME --customer sanofi --project cronus --service-name video-calling-agent --environment dev

  # With retries
  $SCRIPT_NAME --customer sanofi --project cronus --environment dev --build-retries 5 --push-retries 5

EXIT CODES:
  0=Success, 1=General error, 2=Invalid args, 3=AWS/ECR error,
  4=Git error, 5=Build error, 6=Push error, 7=Verification failed
USAGE
}

################################################################################
# Argument Parsing
################################################################################

parse_arguments() {
  [[ $# -eq 0 ]] && { print_banner; print_usage; exit 0; }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) print_banner; print_usage; exit 0 ;;
      --version|-v) print_version; exit 0 ;;
      --customer) CUSTOMER="$2"; shift 2 ;;
      --project) PROJECT="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; AUTO_DETECTED_SERVICE=false; shift 2 ;;
      --environment) ENVIRONMENT="$2"; shift 2 ;;
      --build-context) BUILD_CONTEXT="$2"; shift 2 ;;
      --dockerfile) DOCKERFILE_PATH="$2"; shift 2 ;;
      --platform) PLATFORM="$2"; shift 2 ;;
      --branch) GIT_BRANCH="$2"; AUTO_DETECTED_BRANCH=false; shift 2 ;;
      --aws-region) AWS_REGION="$2"; AUTO_DETECTED_REGION=false; shift 2 ;;
      --build-retries) BUILD_RETRIES="$2"; shift 2 ;;
      --push-retries) PUSH_RETRIES="$2"; shift 2 ;;
      --no-cache) NO_CACHE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --force-build) FORCE_BUILD=true; shift ;;
      --skip-push) SKIP_PUSH=true; shift ;;
      --verbose) VERBOSE=true; shift ;;
      *) log_error "Unknown option: $1"; echo ""; print_usage; exit 2 ;;
    esac
  done
}

################################################################################
# Configuration & Validation
################################################################################

resolve_configuration() {
  log_step "Resolving Configuration"
  
  [[ -z "$CUSTOMER" ]] || [[ -z "$PROJECT" ]] || [[ -z "$ENVIRONMENT" ]] && {
    log_error "Missing required: --customer, --project, --environment"
    exit 2
  }
  
  if [[ -z "$SERVICE_NAME" ]]; then
    log_info "Auto-detecting service name..."
    SERVICE_NAME=$(auto_detect_service_name) || {
      log_error "Failed to auto-detect service name. Use --service-name"
      exit 2
    }
    AUTO_DETECTED_SERVICE=true
    log_success "Auto-detected service: $SERVICE_NAME"
  fi
  
  validate_customer_name "$CUSTOMER" || exit 2
  validate_project_name "$PROJECT" || exit 2
  validate_service_name "$SERVICE_NAME" || exit 2
  validate_environment_name "$ENVIRONMENT" || exit 2
  
  if [[ -z "$AWS_REGION" ]]; then
    log_info "Auto-detecting AWS region..."
    AWS_REGION=$(get_aws_region) || {
      log_error "Failed to auto-detect AWS region. Use --aws-region"
      exit 2
    }
    AUTO_DETECTED_REGION=true
    log_success "Auto-detected region: $AWS_REGION"
  fi
  
  validate_build_context "$BUILD_CONTEXT" "$DOCKERFILE_PATH" || exit 2
  log_success "Configuration validated"
}

check_prerequisites() {
  log_step "Checking Prerequisites"
  validate_required_commands docker aws git || exit 1
  docker info &> /dev/null || { log_error "Docker daemon not running"; exit 1; }
  log_success "All prerequisites satisfied"
}

################################################################################
# Git Operations
################################################################################

handle_git_operations() {
  log_step "Git Operations"
  
  is_git_repository "$BUILD_CONTEXT" || { log_error "Not a git repository: $BUILD_CONTEXT"; exit 4; }
  
  if [[ -n "$GIT_BRANCH" ]] && ! $AUTO_DETECTED_BRANCH; then
    [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY-RUN] Would checkout branch: $GIT_BRANCH"; } || {
      git_checkout_branch "$GIT_BRANCH" "$BUILD_CONTEXT" || exit 4
    }
  else
    GIT_BRANCH=$(get_git_branch "$BUILD_CONTEXT") || exit 4
    AUTO_DETECTED_BRANCH=true
    log_info "Current branch: $GIT_BRANCH"
  fi
  
  GIT_SHA=$(get_git_commit_sha "$BUILD_CONTEXT" 7) || exit 4
  AUTO_DETECTED_SHA=true
  log_success "Git commit SHA: $GIT_SHA"
  
  is_working_tree_clean "$BUILD_CONTEXT" || {
    log_warning "Working directory has uncommitted changes"
    log_warning "Image tagged with SHA: $GIT_SHA (code may differ)"
  }
}

################################################################################
# AWS/ECR Discovery
################################################################################

discover_aws_and_ecr() {
  log_step "AWS/ECR Discovery"
  
  AWS_ACCOUNT_ID=$(get_aws_account_id) || exit 3
  log_success "AWS Account ID: $AWS_ACCOUNT_ID"
  
  ECR_REPOSITORY=$(get_ecr_repository_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  ECR_REGISTRY=$(get_ecr_registry_url "$AWS_ACCOUNT_ID" "$AWS_REGION")
  PRIMARY_IMAGE_URI=$(construct_ecr_image_uri "$ECR_REGISTRY" "$ECR_REPOSITORY" "$GIT_SHA")
  
  log_info "ECR Repository: $ECR_REPOSITORY"
  log_info "ECR Registry: $ECR_REGISTRY"
  log_info "Image URI: $PRIMARY_IMAGE_URI"
  
  verify_ecr_repository "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME" "$AWS_REGION" || {
    log_error "ECR repository not found: $ECR_REPOSITORY"
    exit 3
  }
  
  log_success "ECR repository verified"
}

check_if_image_exists() {
  log_step "Checking for Existing Image"
  
  [[ "$FORCE_BUILD" == "true" ]] && { log_info "Force build enabled, skipping duplicate check"; return 0; }
  
  log_info "Checking for image with tag: $GIT_SHA"
  
  if check_ecr_image_exists "$ECR_REPOSITORY" "$GIT_SHA" "$AWS_REGION"; then
    log_warning "Image already exists: $PRIMARY_IMAGE_URI"
    log_info "Use --force-build to rebuild anyway"
    [[ "$DRY_RUN" != "true" ]] && { log_success "Skipping build (image exists)"; exit 0; }
  else
    log_success "No existing image found with tag: $GIT_SHA"
  fi
}

################################################################################
# Docker Build & Push
################################################################################

execute_build_and_push() {
  log_step "Docker Build & Push"
  
  export BUILD_RETRY_ATTEMPTS="$BUILD_RETRIES"
  export PUSH_RETRY_ATTEMPTS="$PUSH_RETRIES"
  
  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY-RUN] Would authenticate with ECR"; } || {
    authenticate_ecr "$AWS_REGION" "$ECR_REGISTRY" || exit 3
  }
  
  BUILD_BACKEND=$(detect_build_backend) || exit 5
  log_info "Build backend: $BUILD_BACKEND"
  
  [[ "$BUILD_BACKEND" == "BUILDX" ]] && {
    setup_buildx_builder || {
      log_warning "Buildx setup failed, falling back to Docker"
      BUILD_BACKEND="DOCKER"
    }
  }
  
  local -a build_args_array
  while IFS= read -r line; do
    [[ -n "$line" ]] && build_args_array+=("$line")
  done < <(construct_build_args "$CUSTOMER" "$PROJECT" "$SERVICE_NAME" "$ENVIRONMENT" "$GIT_SHA")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would build image: $PRIMARY_IMAGE_URI"
    log_info "[DRY-RUN] Platform: $PLATFORM | No cache: $NO_CACHE | Retries: $BUILD_RETRIES"
  else
    BUILD_START_TIME=$(date +%s)
    
    build_docker_image_with_retry \
      "$BUILD_CONTEXT" \
      "$DOCKERFILE_PATH" \
      "$PRIMARY_IMAGE_URI" \
      "$PLATFORM" \
      "$NO_CACHE" \
      "false" \
      "${build_args_array[@]}" || exit 5
    
    BUILD_END_TIME=$(date +%s)
    log_success "Build completed in $((BUILD_END_TIME - BUILD_START_TIME))s"
  fi
  
  if [[ "$SKIP_PUSH" == "true" ]]; then
    log_info "Push skipped (--skip-push flag)"
  elif [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would push image: $PRIMARY_IMAGE_URI (retries: $PUSH_RETRIES)"
  else
    push_docker_image_with_retry "$PRIMARY_IMAGE_URI" || exit 6
  fi
}

################################################################################
# Image Verification
################################################################################

verify_built_images() {
  log_step "Image Verification"
  
  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY-RUN] Would verify image digests"; return 0; }
  
  LOCAL_IMAGE_DIGEST=$(verify_local_image "$PRIMARY_IMAGE_URI") || exit 7
  log_success "Local image digest: ${LOCAL_IMAGE_DIGEST:0:19}..."
  
  [[ "$SKIP_PUSH" != "true" ]] && {
    REMOTE_IMAGE_DIGEST=$(verify_remote_image "$ECR_REPOSITORY" "$GIT_SHA" "$AWS_REGION") || exit 7
    log_success "Remote image digest: ${REMOTE_IMAGE_DIGEST:0:19}..."
    
    compare_local_and_remote_digests "$PRIMARY_IMAGE_URI" "$ECR_REPOSITORY" "$GIT_SHA" "$AWS_REGION" || {
      log_error "Image verification failed"
      exit 7
    }
    log_success "Image verification successful"
  }
}

################################################################################
# Summary
################################################################################

print_summary() {
  echo ""
  log_step "Build Summary"
  
  cat <<SUMMARY
╔══════════════════════════════════════════════════════════════╗
║                    BUILD SUMMARY                             ║
╚══════════════════════════════════════════════════════════════╝

Forge Context:
  Customer:     $CUSTOMER
  Project:      $PROJECT
  Service:      $SERVICE_NAME $([ "$AUTO_DETECTED_SERVICE" = true ] && echo "(auto-detected)" || echo "")
  Environment:  $ENVIRONMENT

Build Configuration:
  Context:      $BUILD_CONTEXT
  Dockerfile:   $DOCKERFILE_PATH
  Platform:     $PLATFORM
  No Cache:     $NO_CACHE
  Backend:      $BUILD_BACKEND

Git Information:
  Branch:       $GIT_BRANCH $([ "$AUTO_DETECTED_BRANCH" = true ] && echo "(current)" || echo "")
  Commit SHA:   $GIT_SHA

AWS/ECR:
  Region:       $AWS_REGION $([ "$AUTO_DETECTED_REGION" = true ] && echo "(auto-detected)" || echo "")
  Account ID:   $AWS_ACCOUNT_ID
  Repository:   $ECR_REPOSITORY

Image:
  URI:          $PRIMARY_IMAGE_URI
  Tag:          $GIT_SHA (SHA only, no 'latest')
SUMMARY

  [[ -n "$LOCAL_IMAGE_DIGEST" ]] && echo "  Local Digest: ${LOCAL_IMAGE_DIGEST:0:19}..."
  [[ -n "$REMOTE_IMAGE_DIGEST" ]] && [[ "$SKIP_PUSH" != "true" ]] && echo "  Remote Digest: ${REMOTE_IMAGE_DIGEST:0:19}..."
  [[ -n "$BUILD_START_TIME" ]] && [[ -n "$BUILD_END_TIME" ]] && echo "  Build Time:   $((BUILD_END_TIME - BUILD_START_TIME))s"
  
  cat <<SUMMARY2

Retry Configuration:
  Build Retries: $BUILD_RETRIES
  Push Retries:  $PUSH_RETRIES

SUMMARY2

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Mode: DRY-RUN (no actual build/push performed)"
  elif [[ "$SKIP_PUSH" == "true" ]]; then
    echo "Mode: Build only (push skipped)"
  else
    echo "Mode: Build and push completed"
  fi
  
  echo ""
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
}

################################################################################
# Main Function
################################################################################

main() {
  parse_arguments "$@"
  print_banner
  
  [[ "$DRY_RUN" == "true" ]] && { log_warning "DRY-RUN MODE: No images will be built or pushed"; echo ""; }
  
  resolve_configuration
  check_prerequisites
  handle_git_operations
  discover_aws_and_ecr
  check_if_image_exists
  execute_build_and_push
  verify_built_images
  print_summary
  
  if [[ "$DRY_RUN" != "true" ]]; then
    log_success "Docker build and push completed successfully!"
  else
    log_info "Dry-run completed. Review the actions above."
  fi
  
  return 0
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
