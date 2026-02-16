#!/usr/bin/env bash

################################################################################
# Forge Docker Discovery Library
################################################################################
# Version: 1.0.0
# Description: Docker and ECR operations using Docker Buildx for maximum
#              compatibility between local and in-cluster execution
#
# Features:
# - Docker Buildx as primary build backend
# - Fallback to traditional Docker for legacy environments
# - Kubernetes driver support for in-cluster builds
# - Unified command interface (98% compatibility)
# - Native IRSA support via AWS SDK in BuildKit
#
# Dependencies:
# - forge-core.sh
# - forge-patterns.sh
# - forge-aws-discovery.sh
# - forge-k8s-discovery.sh
# - forge-git-operations.sh
# - docker CLI with buildx plugin (v0.10+)
# - aws CLI
#
# Author: Moai Forge Team
# Created: 2026-02-07
################################################################################

# Prevent double-loading
if [[ -n "${FORGE_DOCKER_DISCOVERY_LOADED:-}" ]]; then
	return 0
fi
FORGE_DOCKER_DISCOVERY_LOADED=1

################################################################################
# Dependencies
################################################################################

FORGE_DOCKER_DISCOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${FORGE_CORE_LOADED:-}" ]]; then
	# shellcheck source=forge-core.sh
	source "${FORGE_DOCKER_DISCOVERY_DIR}/forge-core.sh"
fi

if [[ -z "${FORGE_PATTERNS_LOADED:-}" ]]; then
	# shellcheck source=forge-patterns.sh
	source "${FORGE_DOCKER_DISCOVERY_DIR}/forge-patterns.sh"
fi

if [[ -z "${FORGE_AWS_DISCOVERY_LOADED:-}" ]]; then
	# shellcheck source=forge-aws-discovery.sh
	source "${FORGE_DOCKER_DISCOVERY_DIR}/forge-aws-discovery.sh"
fi

if [[ -z "${FORGE_K8S_DISCOVERY_LOADED:-}" ]]; then
	# shellcheck source=forge-k8s-discovery.sh
	source "${FORGE_DOCKER_DISCOVERY_DIR}/forge-k8s-discovery.sh"
fi

if [[ -z "${FORGE_GIT_OPERATIONS_LOADED:-}" ]]; then
	# shellcheck source=forge-git-operations.sh
	source "${FORGE_DOCKER_DISCOVERY_DIR}/forge-git-operations.sh"
fi

################################################################################
# Constants
################################################################################

readonly DOCKER_DEFAULT_PLATFORM="linux/arm64"
readonly BUILDX_MIN_VERSION="0.10.0"
readonly BUILDX_BUILDER_NAME="forge-builder"
readonly BUILDX_K8S_NAMESPACE="forge-builds"
readonly ECR_IMAGE_CHECK_RETRIES=3
readonly ECR_IMAGE_CHECK_DELAY=2

################################################################################
# Execution Mode Detection
################################################################################

detect_docker_execution_mode() {
	if [[ -n "${DOCKER_EXECUTION_MODE:-}" ]]; then
		echo "$DOCKER_EXECUTION_MODE"
		return 0
	fi
	
	local k8s_mode
	k8s_mode=$(detect_kubernetes_context)
	
	if [[ "$k8s_mode" == "IN_CLUSTER" ]]; then
		echo "IN_CLUSTER"
	else
		echo "LOCAL"
	fi
}

################################################################################
# Build Backend Detection
################################################################################

is_buildx_available() {
	if command -v docker &>/dev/null; then
		if docker buildx version &>/dev/null 2>&1; then
			return 0
		fi
	fi
	return 1
}

get_buildx_version() {
	if is_buildx_available; then
		docker buildx version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tr -d 'v'
		return 0
	else
		return 1
	fi
}

validate_buildx_version() {
	local min_version="${1:-$BUILDX_MIN_VERSION}"
	local current_version
	
	current_version=$(get_buildx_version) || return 1
	
	if ! printf '%s\n%s\n' "$min_version" "$current_version" | sort -V -C 2>/dev/null; then
		log_error "Buildx version $current_version is below minimum required version $min_version"
		return 1
	fi
	
	log_debug "Buildx version $current_version meets requirements (>= $min_version)"
	return 0
}

detect_build_backend() {
	if [[ -n "${DOCKER_BUILD_BACKEND:-}" ]]; then
		echo "$DOCKER_BUILD_BACKEND"
		return 0
	fi
	
	local exec_mode
	exec_mode=$(detect_docker_execution_mode)
	
	log_info "Detecting build backend (execution mode: $exec_mode)"
	
	if is_buildx_available; then
		if validate_buildx_version; then
			log_info "Build backend: Docker Buildx (preferred)"
			echo "BUILDX"
			return 0
		else
			log_warning "Buildx version too old, checking for standard Docker"
		fi
	fi
	
	if command -v docker &>/dev/null; then
		if docker info &>/dev/null 2>&1; then
			log_warning "Build backend: Docker (legacy mode - no Buildx)"
			log_warning "Consider upgrading to Docker with Buildx for better performance"
			echo "DOCKER"
			return 0
		fi
	fi
	
	log_error "No build backend available"
	log_error "Install Docker with Buildx plugin: https://docs.docker.com/buildx/working-with-buildx/"
	echo "NONE"
	return 1
}

################################################################################
# Buildx Builder Management
################################################################################

buildx_builder_exists() {
	local builder_name="${1:-$BUILDX_BUILDER_NAME}"
	
	docker buildx ls 2>/dev/null | grep -q "^${builder_name}"
}

get_current_buildx_builder() {
	docker buildx ls 2>/dev/null | grep '\*' | awk '{print $1}' | tr -d '*'
}

create_buildx_builder_local() {
	local builder_name="${1:-$BUILDX_BUILDER_NAME}"
	
	if buildx_builder_exists "$builder_name"; then
		log_info "Buildx builder already exists: $builder_name"
		return 0
	fi
	
	log_info "Creating Buildx builder: $builder_name"
	
	if docker buildx create \
		--name "$builder_name" \
		--driver docker-container \
		--bootstrap \
		--use; then
		
		log_success "Buildx builder created: $builder_name"
		return 0
	else
		log_error "Failed to create Buildx builder"
		return 1
	fi
}

create_buildx_builder_kubernetes() {
	local builder_name="${1:-$BUILDX_BUILDER_NAME}"
	local namespace="${2:-$BUILDX_K8S_NAMESPACE}"
	
	if buildx_builder_exists "$builder_name"; then
		log_info "Buildx builder already exists: $builder_name"
		return 0
	fi
	
	log_info "Creating Buildx Kubernetes builder: $builder_name (namespace: $namespace)"
	
	if ! kubectl get namespace "$namespace" &>/dev/null; then
		log_error "Namespace not found: $namespace"
		log_error "Create namespace first: kubectl create namespace $namespace"
		return 1
	fi
	
	if docker buildx create \
		--name "$builder_name" \
		--driver kubernetes \
		--driver-opt namespace="$namespace" \
		--driver-opt replicas=1 \
		--bootstrap \
		--use; then
		
		log_success "Buildx Kubernetes builder created: $builder_name"
		return 0
	else
		log_error "Failed to create Buildx Kubernetes builder"
		log_error "Ensure namespace '$namespace' exists and has necessary RBAC"
		return 1
	fi
}

setup_buildx_builder() {
	local exec_mode
	exec_mode=$(detect_docker_execution_mode)
	
	local builder_name="$BUILDX_BUILDER_NAME"
	
	case "$exec_mode" in
		LOCAL)
			create_buildx_builder_local "$builder_name" || return 1
			;;
		IN_CLUSTER)
			create_buildx_builder_kubernetes "$builder_name" || return 1
			;;
		*)
			log_error "Unknown execution mode: $exec_mode"
			return 1
			;;
	esac
	
	local current_builder
	current_builder=$(get_current_buildx_builder)
	
	if [[ "$current_builder" == "$builder_name" ]]; then
		log_success "Buildx builder is active: $builder_name"
		return 0
	else
		log_warning "Buildx builder exists but not active, switching to it"
		docker buildx use "$builder_name" || return 1
		return 0
	fi
}

################################################################################
# ECR Discovery & Operations
################################################################################

verify_ecr_repository() {
	local customer="$1"
	local project="$2"
	local environment="$3"
	local service="$4"
	local aws_region="${5:-$(get_aws_region)}"
	
	local repository
	repository=$(get_ecr_repository_name "$customer" "$project" "$environment" "$service")
	
	log_info "Verifying ECR repository: $repository"
	
	if aws ecr describe-repositories \
		--repository-names "$repository" \
		--region "$aws_region" &>/dev/null; then
		
		log_success "ECR repository exists: $repository"
		return 0
	else
		log_error "ECR repository not found: $repository"
		return 1
	fi
}

get_ecr_registry_url() {
	local account_id="${1:-$(get_aws_account_id)}"
	local aws_region="${2:-$(get_aws_region)}"
	
	echo "${account_id}.dkr.ecr.${aws_region}.amazonaws.com"
}

construct_ecr_image_uri() {
	local registry="$1"
	local repository="$2"
	local tag="$3"
	
	echo "${registry}/${repository}:${tag}"
}

check_ecr_image_exists() {
	local repository="$1"
	local tag="$2"
	local aws_region="${3:-$(get_aws_region)}"
	
	aws ecr describe-images \
		--repository-name "$repository" \
		--image-ids imageTag="$tag" \
		--region "$aws_region" &>/dev/null
}

get_ecr_image_metadata() {
	local repository="$1"
	local tag="$2"
	local aws_region="${3:-$(get_aws_region)}"
	
	aws ecr describe-images \
		--repository-name "$repository" \
		--image-ids imageTag="$tag" \
		--region "$aws_region" \
		--query 'imageDetails[0]' \
		--output json 2>/dev/null
}

################################################################################
# ECR Authentication
################################################################################

authenticate_ecr() {
	local aws_region="${1:-$(get_aws_region)}"
	local ecr_registry="${2:-}"
	
	if [[ -z "$ecr_registry" ]]; then
		local account_id
		account_id=$(get_aws_account_id) || return 1
		ecr_registry=$(get_ecr_registry_url "$account_id" "$aws_region")
	fi
	
	log_info "Authenticating with ECR registry: $ecr_registry"
	
	local exec_mode
	exec_mode=$(detect_docker_execution_mode)
	
	if [[ "$exec_mode" == "IN_CLUSTER" ]]; then
		log_info "Using IRSA authentication (ServiceAccount)"
	else
		log_info "Using local AWS credentials"
	fi
	
	local login_output
	local login_result=0
	
	login_output=$(aws ecr get-login-password --region "$aws_region" 2>&1 | \
		docker login --username AWS --password-stdin "$ecr_registry" 2>&1) || login_result=$?
	
	if [[ $login_result -eq 0 ]]; then
		log_success "Successfully authenticated with ECR"
		return 0
	else
		log_error "Failed to authenticate with ECR"
		log_debug "Login output: $login_output"
		return 1
	fi
}

################################################################################
# Docker Build Operations
################################################################################

check_docker_daemon() {
	log_info "Checking Docker daemon"
	
	if docker info &>/dev/null; then
		log_success "Docker daemon is running"
		return 0
	else
		log_error "Docker daemon is not running"
		log_error "Start Docker daemon or Docker Desktop"
		return 1
	fi
}

_build_with_buildx() {
	local build_context="$1"
	local dockerfile="$2"
	local image_uri="$3"
	local platform="$4"
	local no_cache="$5"
	local auto_push="$6"
	shift 6
	local build_args=("$@")
	
	log_info "Building with Docker Buildx"
	
	local -a buildx_cmd=(
		docker buildx build
		--file "$dockerfile"
		--tag "$image_uri"
		--platform "$platform"
	)
	
	if [[ "$no_cache" == "true" ]]; then
		buildx_cmd+=(--no-cache)
		log_info "Build cache disabled"
	fi
	
	if [[ "$auto_push" == "true" ]]; then
		buildx_cmd+=(--push)
		log_info "Image will be pushed to registry after build"
	else
		buildx_cmd+=(--load)
		log_info "Image will be loaded to local Docker after build"
	fi
	
	for arg in "${build_args[@]}"; do
		buildx_cmd+=("$arg")
	done
	
	buildx_cmd+=("$build_context")
	
	log_debug "Build command: ${buildx_cmd[*]}"
	
	"${buildx_cmd[@]}"
}

_build_with_docker() {
	local build_context="$1"
	local dockerfile="$2"
	local image_uri="$3"
	local platform="$4"
	local no_cache="$5"
	local auto_push="$6"
	shift 6
	local build_args=("$@")
	
	log_info "Building with Docker (traditional)"
	log_warning "Using legacy Docker build - consider upgrading to Buildx"
	
	local -a docker_cmd=(
		docker build
		--file "$dockerfile"
		--tag "$image_uri"
		--platform "$platform"
	)
	
	if [[ "$no_cache" == "true" ]]; then
		docker_cmd+=(--no-cache)
	fi
	
	for arg in "${build_args[@]}"; do
		docker_cmd+=("$arg")
	done
	
	docker_cmd+=("$build_context")
	
	log_debug "Build command: ${docker_cmd[*]}"
	
	"${docker_cmd[@]}"
	
	if [[ "$auto_push" == "true" ]]; then
		log_warning "Auto-push not supported with traditional Docker"
		log_warning "Caller must push image separately"
	fi
}

build_docker_image() {
	local build_context="$1"
	local dockerfile="$2"
	local image_uri="$3"
	local platform="$4"
	local no_cache="$5"
	local auto_push="${6:-false}"
	shift 6 2>/dev/null || shift 5
	local build_args=("$@")
	
	log_info "Building Docker image: $image_uri"
	log_info "Build context: $build_context"
	log_info "Dockerfile: $dockerfile"
	log_info "Platform: $platform"
	
	local backend
	backend=$(detect_build_backend) || return 1
	
	if [[ "$backend" == "NONE" ]]; then
		log_error "No build backend available"
		return 1
	fi
	
	if [[ "$backend" == "BUILDX" ]]; then
		setup_buildx_builder || {
			log_warning "Failed to setup Buildx builder, falling back to Docker"
			backend="DOCKER"
		}
	fi
	
	local build_start build_end duration
	build_start=$(date +%s)
	
	case "$backend" in
		BUILDX)
			_build_with_buildx "$build_context" "$dockerfile" "$image_uri" \
				"$platform" "$no_cache" "$auto_push" "${build_args[@]}"
			;;
		DOCKER)
			_build_with_docker "$build_context" "$dockerfile" "$image_uri" \
				"$platform" "$no_cache" "$auto_push" "${build_args[@]}"
			;;
		*)
			log_error "Unsupported build backend: $backend"
			return 1
			;;
	esac
	
	local build_result=$?
	
	build_end=$(date +%s)
	duration=$((build_end - build_start))
	
	if [[ $build_result -eq 0 ]]; then
		log_success "Docker image built successfully (${duration}s)"
		
		if [[ "$auto_push" != "true" ]] && [[ "$backend" == "DOCKER" ]]; then
			local image_size
			image_size=$(get_docker_image_size "$image_uri" 2>/dev/null || echo "unknown")
			log_info "Image size: $image_size"
		fi
		
		return 0
	else
		log_error "Docker build failed after ${duration}s"
		return 1
	fi
}

build_docker_image_multi_tag() {
	local build_context="$1"
	local dockerfile="$2"
	local primary_uri="$3"
	local platform="$4"
	local no_cache="$5"
	local auto_push="$6"
	shift 6
	
	local -a build_args=()
	local -a additional_tags=()
	local parsing_build_args=true
	
	for arg in "$@"; do
		if [[ "$arg" == "--additional-tag" ]]; then
			parsing_build_args=false
			continue
		fi
		
		if $parsing_build_args; then
			build_args+=("$arg")
		else
			additional_tags+=("$arg")
		fi
	done
	
	local backend
	backend=$(detect_build_backend) || return 1
	
	if [[ "$backend" == "BUILDX" ]]; then
		setup_buildx_builder || return 1
		
		local -a buildx_cmd=(
			docker buildx build
			--file "$dockerfile"
			--tag "$primary_uri"
			--platform "$platform"
		)
		
		for tag_uri in "${additional_tags[@]}"; do
			buildx_cmd+=(--tag "$tag_uri")
			log_info "Additional tag: $tag_uri"
		done
		
		if [[ "$no_cache" == "true" ]]; then
			buildx_cmd+=(--no-cache)
		fi
		
		if [[ "$auto_push" == "true" ]]; then
			buildx_cmd+=(--push)
		else
			buildx_cmd+=(--load)
		fi
		
		for arg in "${build_args[@]}"; do
			buildx_cmd+=("$arg")
		done
		
		buildx_cmd+=("$build_context")
		
		log_info "Building with multiple tags (Buildx)"
		"${buildx_cmd[@]}"
	else
		log_info "Building primary tag with Docker (traditional)"
		build_docker_image "$build_context" "$dockerfile" "$primary_uri" \
			"$platform" "$no_cache" "false" "${build_args[@]}" || return 1
		
		for tag_uri in "${additional_tags[@]}"; do
			log_info "Tagging: $primary_uri -> $tag_uri"
			docker tag "$primary_uri" "$tag_uri" || return 1
		done
	fi
}

################################################################################
# Image Operations
################################################################################

push_docker_image() {
	local image_uri="$1"
	
	log_info "Pushing image to registry: $image_uri"
	
	if docker push "$image_uri"; then
		log_success "Image pushed successfully"
		return 0
	else
		log_error "Failed to push image"
		return 1
	fi
}

tag_docker_image() {
	local source="$1"
	local target="$2"
	
	log_info "Tagging image: $source -> $target"
	
	if docker tag "$source" "$target"; then
		log_success "Image tagged successfully"
		return 0
	else
		log_error "Failed to tag image"
		return 1
	fi
}

get_docker_image_digest() {
	local image_uri="$1"
	
	docker inspect --format='{{index .RepoDigests 0}}' "$image_uri" 2>/dev/null | \
		grep -oE 'sha256:[a-f0-9]+' || echo ""
}

get_docker_image_size() {
	local image_uri="$1"
	
	local size_bytes
	size_bytes=$(docker inspect --format='{{.Size}}' "$image_uri" 2>/dev/null)
	
	if [[ -n "$size_bytes" ]]; then
		numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "$size_bytes bytes"
	else
		echo "unknown"
	fi
}

################################################################################
# Image Verification
################################################################################

verify_local_image() {
	local image_uri="$1"
	
	log_info "Verifying local image: $image_uri"
	
	local digest
	digest=$(get_docker_image_digest "$image_uri")
	
	if [[ -n "$digest" ]]; then
		log_success "Local image verified: $digest"
		echo "$digest"
		return 0
	else
		log_error "Local image not found"
		return 1
	fi
}

verify_remote_image() {
	local repository="$1"
	local tag="$2"
	local aws_region="${3:-$(get_aws_region)}"
	
	log_info "Verifying remote image: $repository:$tag"
	
	local retries="$ECR_IMAGE_CHECK_RETRIES"
	local delay="$ECR_IMAGE_CHECK_DELAY"
	local digest=""
	
	for ((i=1; i<=retries; i++)); do
		digest=$(aws ecr describe-images \
			--repository-name "$repository" \
			--image-ids imageTag="$tag" \
			--region "$aws_region" \
			--query 'imageDetails[0].imageDigest' \
			--output text 2>/dev/null)
		
		if [[ -n "$digest" ]] && [[ "$digest" != "None" ]]; then
			log_success "Remote image verified: $digest"
			echo "$digest"
			return 0
		fi
		
		if [[ $i -lt $retries ]]; then
			log_warning "Image not found yet (attempt $i/$retries), retrying in ${delay}s..."
			sleep "$delay"
		fi
	done
	
	log_error "Remote image not found after $retries attempts"
	return 1
}

compare_image_digests() {
	local local_digest="$1"
	local remote_digest="$2"
	
	log_info "Comparing image digests"
	log_debug "Local:  $local_digest"
	log_debug "Remote: $remote_digest"
	
	if [[ "$local_digest" == "$remote_digest" ]]; then
		log_success "Image digests match - verified integrity"
		return 0
	else
		log_error "Image digests do not match"
		log_error "Local:  $local_digest"
		log_error "Remote: $remote_digest"
		return 1
	fi
}

################################################################################
# Build/Push Retry Wrappers
################################################################################

# build_docker_image_with_retry
# Wrapper for build_docker_image with exponential backoff retry logic
# Arguments:
#   $1 - Build context path
#   $2 - Dockerfile path (relative to context or absolute)
#   $3 - Full image URI (registry/repository:tag)
#   $4 - Platform (e.g., "linux/amd64,linux/arm64")
#   $5 - No cache flag ("true" or "false")
#   $6 - Auto-push flag ("true" or "false")
#   $7+ - Build args (--build-arg KEY=VALUE format)
#   
# Environment Variables:
#   BUILD_RETRY_ATTEMPTS - Max retry attempts (default: 3)
#   BUILD_RETRY_DELAY_BASE - Base delay in seconds (default: 5)
#   BUILD_RETRY_EXPONENTIAL - Use exponential backoff (default: true)
#
# Returns:
#   0 - Build succeeded
#   1 - Build failed after all retries
build_docker_image_with_retry() {
	local build_context="$1"
	local dockerfile="$2"
	local image_uri="$3"
	local platform="$4"
	local no_cache="$5"
	local auto_push="${6:-false}"
	shift 6 2>/dev/null || shift 5
	local build_args=("$@")
	
	local max_attempts="${BUILD_RETRY_ATTEMPTS:-3}"
	local base_delay="${BUILD_RETRY_DELAY_BASE:-5}"
	local exponential="${BUILD_RETRY_EXPONENTIAL:-true}"
	
	log_info "Starting Docker build with retry (max attempts: $max_attempts)"
	
	for ((attempt=1; attempt<=max_attempts; attempt++)); do
		log_info "Build attempt $attempt/$max_attempts"
		
		# Call the actual build function
		if build_docker_image "$build_context" "$dockerfile" "$image_uri" \
			"$platform" "$no_cache" "$auto_push" "${build_args[@]}"; then
			log_success "Build succeeded on attempt $attempt"
			return 0
		fi
		
		# Check if we should retry
		if [[ $attempt -lt $max_attempts ]]; then
			local delay=$base_delay
			
			# Calculate exponential backoff delay
			if [[ "$exponential" == "true" ]]; then
				delay=$((base_delay * (2 ** (attempt - 1))))
			fi
			
			log_warning "Build failed, retrying in ${delay}s..."
			sleep "$delay"
		fi
	done
	
	log_error "Build failed after $max_attempts attempts"
	return 1
}

# push_docker_image_with_retry
# Wrapper for push_docker_image with exponential backoff retry logic
# Arguments:
#   $1 - Full image URI to push
#
# Environment Variables:
#   PUSH_RETRY_ATTEMPTS - Max retry attempts (default: 3)
#   PUSH_RETRY_DELAY_BASE - Base delay in seconds (default: 2)
#   PUSH_RETRY_EXPONENTIAL - Use exponential backoff (default: true)
#
# Returns:
#   0 - Push succeeded
#   1 - Push failed after all retries
push_docker_image_with_retry() {
	local image_uri="$1"
	
	local max_attempts="${PUSH_RETRY_ATTEMPTS:-3}"
	local base_delay="${PUSH_RETRY_DELAY_BASE:-2}"
	local exponential="${PUSH_RETRY_EXPONENTIAL:-true}"
	
	log_info "Starting Docker push with retry (max attempts: $max_attempts)"
	
	for ((attempt=1; attempt<=max_attempts; attempt++)); do
		log_info "Push attempt $attempt/$max_attempts"
		
		# Call the actual push function
		if push_docker_image "$image_uri"; then
			log_success "Push succeeded on attempt $attempt"
			return 0
		fi
		
		# Check if we should retry
		if [[ $attempt -lt $max_attempts ]]; then
			local delay=$base_delay
			
			# Calculate exponential backoff delay
			if [[ "$exponential" == "true" ]]; then
				delay=$((base_delay * (2 ** (attempt - 1))))
			fi
			
			log_warning "Push failed, retrying in ${delay}s..."
			sleep "$delay"
		fi
	done
	
	log_error "Push failed after $max_attempts attempts"
	return 1
}

# compare_local_and_remote_digests
# Compares digest of local Docker image with remote ECR image
# Arguments:
#   $1 - Local image URI (with tag)
#   $2 - ECR repository name
#   $3 - Image tag
#   $4 - (optional) AWS region (defaults to current region)
#
# Returns:
#   0 - Digests match (verification successful)
#   1 - Digests do not match or verification failed
#   2 - Unable to retrieve one or both digests
compare_local_and_remote_digests() {
	local local_image="$1"
	local repository="$2"
	local tag="$3"
	local aws_region="${4:-$(get_aws_region)}"
	
	log_info "Comparing local and remote image digests"
	
	# Get local digest
	local local_digest
	local_digest=$(verify_local_image "$local_image" 2>&1 | tail -n1)
	
	if [[ -z "$local_digest" ]] || [[ ! "$local_digest" =~ ^sha256: ]]; then
		log_error "Failed to retrieve local image digest"
		return 2
	fi
	
	# Get remote digest
	local remote_digest
	remote_digest=$(verify_remote_image "$repository" "$tag" "$aws_region" 2>&1 | tail -n1)
	
	if [[ -z "$remote_digest" ]] || [[ ! "$remote_digest" =~ ^sha256: ]]; then
		log_error "Failed to retrieve remote image digest"
		return 2
	fi
	
	# Compare digests
	if compare_image_digests "$local_digest" "$remote_digest"; then
		log_success "Image verification successful: local and remote digests match"
		return 0
	else
		log_error "Image verification failed: digests do not match"
		return 1
	fi
}

################################################################################
# Build Metadata & Validation
################################################################################

construct_build_args() {
	local customer="$1"
	local project="$2"
	local service="$3"
	local environment="$4"
	local git_commit="${5:-}"
	
	if [[ -z "$git_commit" ]]; then
		git_commit=$(get_git_commit_sha "." 7 2>/dev/null) || git_commit="unknown"
	fi
	
	local build_date
	build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
	
	cat <<EOF
--build-arg
BUILD_DATE=${build_date}
--build-arg
GIT_COMMIT=${git_commit}
--build-arg
VERSION=${git_commit}
--build-arg
CUSTOMER=${customer}
--build-arg
PROJECT=${project}
--build-arg
SERVICE=${service}
--build-arg
ENVIRONMENT=${environment}
EOF
}

validate_build_context() {
	local build_context="$1"
	local dockerfile="$2"
	
	log_info "Validating build context"
	
	if [[ ! -d "$build_context" ]]; then
		log_error "Build context directory not found: $build_context"
		return 1
	fi
	
	local dockerfile_full_path
	if [[ "$dockerfile" == /* ]]; then
		dockerfile_full_path="$dockerfile"
	else
		dockerfile_full_path="${build_context}/${dockerfile}"
	fi
	
	if [[ ! -f "$dockerfile_full_path" ]]; then
		log_error "Dockerfile not found: $dockerfile_full_path"
		return 1
	fi
	
	log_success "Build context validated"
	return 0
}

################################################################################
# Initialization
################################################################################

log_info "Forge Docker Discovery Library loaded (v1.0.0 - Buildx-First)"

DOCKER_EXECUTION_MODE=$(detect_docker_execution_mode)
export DOCKER_EXECUTION_MODE

log_info "Docker execution mode: $DOCKER_EXECUTION_MODE"

DOCKER_BUILD_BACKEND=$(detect_build_backend)
export DOCKER_BUILD_BACKEND

if [[ "$DOCKER_BUILD_BACKEND" != "NONE" ]]; then
	log_info "Docker build backend: $DOCKER_BUILD_BACKEND"
else
	log_warning "No Docker build backend detected"
fi
