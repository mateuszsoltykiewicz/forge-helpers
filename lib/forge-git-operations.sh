#!/usr/bin/env bash

################################################################################
# Forge Git Operations Library
################################################################################
# Version: 1.0.0
# Description: Git repository operations with intelligent context detection
#              and validation for Forge build/deployment workflows
#
# Features:
# - Git repository detection and validation
# - Commit SHA extraction (configurable length)
# - Branch management (switching, fetching, pulling)
# - Working tree validation (dirty/clean detection)
# - Commit metadata retrieval (message, author, date)
# - Tag operations
# - Remote repository information
# - Git hooks validation
# - Submodule management
#
# Dependencies:
# - forge-core.sh
# - git CLI (version 2.0+)
#
# Author: Moai Forge Team
# Created: 2026-02-07
################################################################################

# Prevent double-loading
if [[ -n "${FORGE_GIT_OPERATIONS_LOADED:-}" ]]; then
	return 0
fi
FORGE_GIT_OPERATIONS_LOADED=1

################################################################################
# Dependencies
################################################################################

# Determine script directory
FORGE_GIT_OPERATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -z "${FORGE_CORE_LOADED:-}" ]]; then
	# shellcheck source=forge-core.sh
	source "${FORGE_GIT_OPERATIONS_DIR}/forge-core.sh"
fi

# Validate required commands
validate_required_commands git

################################################################################
# Constants
################################################################################

readonly GIT_DEFAULT_SHA_LENGTH=7
readonly GIT_MIN_VERSION="2.0.0"
readonly GIT_BRANCH_FETCH_TIMEOUT=30
readonly GIT_PULL_RETRY_ATTEMPTS=3
readonly GIT_PULL_RETRY_DELAY=2

# SSH Authentication Modes
readonly SSH_AUTH_MODE_SSM="ssm"        # Provision from AWS SSM Parameter Store
readonly SSH_AUTH_MODE_LOCAL="local"    # Use existing local SSH keys from ~/.ssh
readonly SSH_AUTH_MODE_AUTO="auto"      # Try local first, fallback to SSM

################################################################################
# Version Detection
################################################################################

# Get git version
# Output: Version string (e.g., "2.39.1")
# Returns:
#   0 - Success
#   1 - Git not found or version detection failed
get_git_version() {
	local version
	version=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
	
	if [[ -z "$version" ]]; then
		log_error "Failed to detect git version"
		return 1
	fi
	
	echo "$version"
	return 0
}

# Validate git version meets minimum requirements
# Arguments:
#   $1 - (optional) Minimum required version (default: GIT_MIN_VERSION)
# Returns:
#   0 - Version meets requirements
#   1 - Version too old or detection failed
validate_git_version() {
	local min_version="${1:-$GIT_MIN_VERSION}"
	local current_version
	
	current_version=$(get_git_version) || return 1
	
	# Use sort -V to compare versions
	if ! printf '%s\n%s\n' "$min_version" "$current_version" | sort -V -C 2>/dev/null; then
		log_error "Git version $current_version is below minimum required version $min_version"
		return 1
	fi
	
	log_debug "Git version $current_version meets requirements (>= $min_version)"
	return 0
}

################################################################################
# Repository Detection
################################################################################

# Check if directory is a git repository
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Is a git repository
#   1 - Not a git repository
is_git_repository() {
	local dir="${1:-.}"
	
	if [[ ! -d "$dir" ]]; then
		log_error "Directory does not exist: $dir"
		return 1
	fi
	
	(cd "$dir" && git rev-parse --git-dir >/dev/null 2>&1)
}

# Check git repository with detailed validation
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Valid repository
#   1 - Invalid or not a repository
check_git_repository() {
	local dir="${1:-.}"
	
	log_info "Checking git repository: $dir"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		log_error "Initialize with: git init"
		return 1
	fi
	
	log_success "Valid git repository: $dir"
	
	# Check if repository has commits
	if ! (cd "$dir" && git rev-parse HEAD >/dev/null 2>&1); then
		log_warning "Repository has no commits yet"
		return 0
	fi
	
	# Log repository details in verbose mode
	if [[ "${VERBOSE:-false}" == "true" ]]; then
		local git_dir
		local is_bare
		local remote_url
		
		git_dir=$(cd "$dir" && git rev-parse --git-dir 2>/dev/null)
		is_bare=$(cd "$dir" && git rev-parse --is-bare-repository 2>/dev/null)
		remote_url=$(cd "$dir" && git config --get remote.origin.url 2>/dev/null || echo "none")
		
		log_debug "Git directory: $git_dir"
		log_debug "Bare repository: $is_bare"
		log_debug "Remote URL: $remote_url"
	fi
	
	return 0
}

# Get git repository root directory
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Output: Absolute path to repository root
# Returns:
#   0 - Success
#   1 - Not a repository
get_git_root() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git rev-parse --show-toplevel 2>/dev/null)
}

################################################################################
# Commit SHA Operations
################################################################################

# Get git commit SHA
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) SHA length (default: GIT_DEFAULT_SHA_LENGTH)
#   $3 - (optional) Commit reference (default: HEAD)
# Output: Commit SHA
# Returns:
#   0 - Success
#   1 - Failed to get SHA
get_git_commit_sha() {
	local dir="${1:-.}"
	local length="${2:-$GIT_DEFAULT_SHA_LENGTH}"
	local ref="${3:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	local sha
	sha=$(cd "$dir" && git rev-parse --short="$length" "$ref" 2>/dev/null)
	
	if [[ -z "$sha" ]]; then
		log_error "Failed to get git commit SHA for ref: $ref"
		return 1
	fi
	
	echo "$sha"
	return 0
}

# Get full git commit SHA (40 characters)
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: Full commit SHA
# Returns:
#   0 - Success
#   1 - Failed to get SHA
get_git_commit_sha_full() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	local sha
	sha=$(cd "$dir" && git rev-parse "$ref" 2>/dev/null)
	
	if [[ -z "$sha" ]]; then
		log_error "Failed to get full git commit SHA for ref: $ref"
		return 1
	fi
	
	echo "$sha"
	return 0
}

################################################################################
# Working Tree Validation
################################################################################

# Check if working tree is clean (no uncommitted changes)
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Working tree is clean
#   1 - Working tree has uncommitted changes
is_working_tree_clean() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git diff-index --quiet HEAD -- 2>/dev/null)
}

# Validate working tree and warn if dirty
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Context message for warning
# Returns:
#   0 - Always (validation is informational)
validate_git_working_tree() {
	local dir="${1:-.}"
	local context="${2:-Build/deployment}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	if is_working_tree_clean "$dir"; then
		log_success "Working tree is clean"
		return 0
	else
		log_warning "Working tree has uncommitted changes"
		log_warning "$context may not reflect actual code state"
		
		if [[ "${VERBOSE:-false}" == "true" ]]; then
			log_debug "Modified files:"
			(cd "$dir" && git status --short 2>/dev/null) | while IFS= read -r line; do
				log_debug "  $line"
			done
		fi
		
		return 0
	fi
}

# Get list of uncommitted changes
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Output: JSON array of changed files
# Returns:
#   0 - Success
#   1 - Failed or not a repository
get_uncommitted_changes() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git status --porcelain 2>/dev/null | \
		jq -R -s -c 'split("\n") | map(select(length > 0))')
}

################################################################################
# Branch Operations
################################################################################

# Get current git branch name
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Output: Branch name
# Returns:
#   0 - Success
#   1 - Failed to get branch name
get_git_branch() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	local branch
	branch=$(cd "$dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
	
	if [[ -z "$branch" ]]; then
		log_error "Failed to get current branch"
		return 1
	fi
	
	echo "$branch"
	return 0
}

# Check if branch exists locally
# Arguments:
#   $1 - Branch name
#   $2 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Branch exists
#   1 - Branch does not exist
branch_exists_local() {
	local branch="$1"
	local dir="${2:-.}"
	
	if ! is_git_repository "$dir"; then
		return 1
	fi
	
	(cd "$dir" && git rev-parse --verify "$branch" >/dev/null 2>&1)
}

# Check if branch exists on remote
# Arguments:
#   $1 - Branch name
#   $2 - (optional) Remote name (default: origin)
#   $3 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Branch exists on remote
#   1 - Branch does not exist on remote
branch_exists_remote() {
	local branch="$1"
	local remote="${2:-origin}"
	local dir="${3:-.}"
	
	if ! is_git_repository "$dir"; then
		return 1
	fi
	
	(cd "$dir" && git ls-remote --heads "$remote" "$branch" 2>/dev/null | grep -q "$branch")
}

# Fetch branch from remote
# Arguments:
#   $1 - Branch name
#   $2 - (optional) Remote name (default: origin)
#   $3 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Success
#   1 - Failed to fetch
fetch_git_branch() {
	local branch="$1"
	local remote="${2:-origin}"
	local dir="${3:-.}"
	
	log_info "Fetching branch '$branch' from remote '$remote'"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	local fetch_output
	local fetch_result=0
	
	# Use timeout if available, otherwise just run git fetch
	if command -v timeout >/dev/null 2>&1; then
		fetch_output=$(cd "$dir" && timeout "$GIT_BRANCH_FETCH_TIMEOUT" git fetch "$remote" "$branch" 2>&1) || fetch_result=$?
	else
		fetch_output=$(cd "$dir" && git fetch "$remote" "$branch" 2>&1) || fetch_result=$?
	fi
	
	if [[ $fetch_result -eq 0 ]]; then
		log_success "Branch '$branch' fetched successfully"
		return 0
	else
		log_error "Failed to fetch branch '$branch'"
		log_debug "Fetch output: $fetch_output"
		return 1
	fi
}

# Switch to git branch (with fetch and pull)
# Arguments:
#   $1 - Branch name
#   $2 - (optional) Directory path (default: current directory)
#   $3 - (optional) Remote name (default: origin)
# Returns:
#   0 - Success
#   1 - Failed to switch branch
switch_git_branch() {
	local branch="$1"
	local dir="${2:-.}"
	local remote="${3:-origin}"
	
	log_info "Switching to branch: $branch"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	local current_branch
	current_branch=$(get_git_branch "$dir")
	
	if [[ "$current_branch" == "$branch" ]]; then
		log_info "Already on branch '$branch'"
	else
		# Fetch branch first
		if ! fetch_git_branch "$branch" "$remote" "$dir"; then
			log_error "Failed to fetch branch '$branch'"
			return 1
		fi
		
		# Checkout branch
		log_info "Checking out branch '$branch'"
		local checkout_output
		if checkout_output=$(cd "$dir" && git checkout "$branch" 2>&1); then
			log_success "Switched to branch '$branch'"
		else
			log_error "Failed to checkout branch '$branch'"
			log_debug "Checkout output: $checkout_output"
			return 1
		fi
	fi
	
	# Pull latest changes with retry
	local retry_count=0
	while [[ $retry_count -lt $GIT_PULL_RETRY_ATTEMPTS ]]; do
		log_info "Pulling latest changes from '$remote/$branch' (attempt $((retry_count + 1))/$GIT_PULL_RETRY_ATTEMPTS)"
		
		local pull_output
		if pull_output=$(cd "$dir" && git pull "$remote" "$branch" 2>&1); then
			log_success "Branch '$branch' updated successfully"
			return 0
		fi
		
		((retry_count++))
		if [[ $retry_count -lt $GIT_PULL_RETRY_ATTEMPTS ]]; then
			log_warning "Pull failed, retrying in ${GIT_PULL_RETRY_DELAY}s..."
			log_debug "Pull output: $pull_output"
			sleep "$GIT_PULL_RETRY_DELAY"
		fi
	done
	
	log_error "Failed to pull latest changes after $GIT_PULL_RETRY_ATTEMPTS attempts"
	return 1
}

# Checkout git branch with automatic stash handling
# Arguments:
#   $1 - Branch name
#   $2 - (optional) Directory path (default: current directory)
#   $3 - (optional) Remote name (default: origin)
#   $4 - (optional) Auto-stash flag (default: true, set to "false" to disable)
# Returns:
#   0 - Success
#   1 - Failed to checkout branch
#   2 - Checkout blocked by uncommitted changes (when auto-stash=false)
#
# Features:
#   - Automatically stashes uncommitted changes before checkout
#   - Fetches branch from remote if not present locally
#   - Pulls latest changes after checkout
#   - Re-applies stash after successful checkout (if auto-stash enabled)
#   - Handles stash conflicts gracefully
git_checkout_branch() {
	local branch="$1"
	local dir="${2:-.}"
	local remote="${3:-origin}"
	local auto_stash="${4:-true}"
	
	log_info "Checking out branch: $branch"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	# Check current branch
	local current_branch
	current_branch=$(get_git_branch "$dir")
	
	if [[ "$current_branch" == "$branch" ]]; then
		log_info "Already on branch '$branch', pulling latest changes"
		
		# Still pull latest changes
		if (cd "$dir" && git pull "$remote" "$branch" 2>&1); then
			log_success "Branch '$branch' is up to date"
			return 0
		else
			log_warning "Failed to pull latest changes, but already on correct branch"
			return 0
		fi
	fi
	
	# Check for uncommitted changes
	local has_changes=false
	local stashed=false
	
	if ! is_working_tree_clean "$dir"; then
		has_changes=true
		
		if [[ "$auto_stash" == "true" ]]; then
			log_info "Uncommitted changes detected, stashing before checkout"
			
			if (cd "$dir" && git stash push -m "Auto-stash by git_checkout_branch for $branch at $(date +%Y-%m-%d_%H:%M:%S)" 2>&1); then
				log_success "Changes stashed successfully"
				stashed=true
			else
				log_error "Failed to stash changes"
				return 1
			fi
		else
			log_error "Uncommitted changes detected and auto-stash is disabled"
			log_error "Commit or stash your changes before checking out '$branch'"
			return 2
		fi
	fi
	
	# Fetch branch if it doesn't exist locally
	if ! branch_exists_local "$branch" "$dir"; then
		log_info "Branch '$branch' not found locally, fetching from remote"
		
		if ! fetch_git_branch "$branch" "$remote" "$dir"; then
			log_error "Failed to fetch branch '$branch' from remote '$remote'"
			
			# Restore stash if we created one
			if [[ "$stashed" == "true" ]]; then
				log_info "Restoring stashed changes"
				(cd "$dir" && git stash pop 2>&1) || log_warning "Failed to restore stash"
			fi
			
			return 1
		fi
		
		# Set up tracking branch
		log_info "Setting up tracking for '$remote/$branch'"
		if ! (cd "$dir" && git checkout -b "$branch" --track "$remote/$branch" 2>&1); then
			log_error "Failed to create tracking branch"
			
			# Restore stash if we created one
			if [[ "$stashed" == "true" ]]; then
				log_info "Restoring stashed changes"
				(cd "$dir" && git stash pop 2>&1) || log_warning "Failed to restore stash"
			fi
			
			return 1
		fi
	else
		# Branch exists locally, just checkout
		log_info "Checking out existing local branch '$branch'"
		
		if ! (cd "$dir" && git checkout "$branch" 2>&1); then
			log_error "Failed to checkout branch '$branch'"
			
			# Restore stash if we created one
			if [[ "$stashed" == "true" ]]; then
				log_info "Restoring stashed changes"
				(cd "$dir" && git stash pop 2>&1) || log_warning "Failed to restore stash"
			fi
			
			return 1
		fi
	fi
	
	log_success "Switched to branch '$branch'"
	
	# Pull latest changes
	log_info "Pulling latest changes from '$remote/$branch'"
	
	if ! (cd "$dir" && git pull "$remote" "$branch" 2>&1); then
		log_warning "Failed to pull latest changes, but checkout was successful"
	else
		log_success "Branch '$branch' is up to date"
	fi
	
	# Restore stash if we created one
	if [[ "$stashed" == "true" ]]; then
		log_info "Restoring stashed changes"
		
		local stash_output
		if stash_output=$(cd "$dir" && git stash pop 2>&1); then
			log_success "Stashed changes restored successfully"
		else
			log_warning "Failed to automatically restore stash (may have conflicts)"
			log_warning "Stash is preserved, use 'git stash pop' manually"
			log_debug "Stash output: $stash_output"
		fi
	fi
	
	return 0
}

################################################################################
# Commit Metadata
################################################################################

# Get commit message
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: Commit message (first line)
# Returns:
#   0 - Success
#   1 - Failed to get message
get_git_commit_message() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git log -1 --pretty=%B "$ref" 2>/dev/null | head -n1)
}

# Get commit author name
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: Author name
# Returns:
#   0 - Success
#   1 - Failed to get author
get_git_commit_author() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git log -1 --pretty=%an "$ref" 2>/dev/null)
}

# Get commit author email
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: Author email
# Returns:
#   0 - Success
#   1 - Failed to get email
get_git_commit_author_email() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git log -1 --pretty=%ae "$ref" 2>/dev/null)
}

# Get commit date (ISO 8601 format)
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: Commit date (ISO 8601)
# Returns:
#   0 - Success
#   1 - Failed to get date
get_git_commit_date() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git log -1 --pretty=%aI "$ref" 2>/dev/null)
}

# Get comprehensive commit metadata (JSON)
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: JSON object with commit metadata
# Returns:
#   0 - Success
#   1 - Failed to get metadata
get_git_commit_metadata() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	local sha_short sha_full message author author_email date
	
	sha_short=$(get_git_commit_sha "$dir" 7 "$ref") || return 1
	sha_full=$(get_git_commit_sha_full "$dir" "$ref") || return 1
	message=$(get_git_commit_message "$dir" "$ref") || return 1
	author=$(get_git_commit_author "$dir" "$ref") || return 1
	author_email=$(get_git_commit_author_email "$dir" "$ref") || return 1
	date=$(get_git_commit_date "$dir" "$ref") || return 1
	
	jq -n \
		--arg sha_short "$sha_short" \
		--arg sha_full "$sha_full" \
		--arg message "$message" \
		--arg author "$author" \
		--arg author_email "$author_email" \
		--arg date "$date" \
		'{
			sha_short: $sha_short,
			sha_full: $sha_full,
			message: $message,
			author: $author,
			author_email: $author_email,
			date: $date
		}'
}

################################################################################
# Tag Operations
################################################################################

# Get latest git tag
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Output: Latest tag name
# Returns:
#   0 - Success
#   1 - No tags or failed
get_git_latest_tag() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git describe --tags --abbrev=0 2>/dev/null)
}

# Check if commit is tagged
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Returns:
#   0 - Commit is tagged
#   1 - Commit is not tagged
is_commit_tagged() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		return 1
	fi
	
	(cd "$dir" && git describe --exact-match "$ref" >/dev/null 2>&1)
}

# Get tag for specific commit
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
#   $2 - (optional) Commit reference (default: HEAD)
# Output: Tag name
# Returns:
#   0 - Success
#   1 - No tag found
get_git_tag_for_commit() {
	local dir="${1:-.}"
	local ref="${2:-HEAD}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git describe --exact-match "$ref" 2>/dev/null)
}

################################################################################
# Remote Operations
################################################################################

# Get remote URL
# Arguments:
#   $1 - (optional) Remote name (default: origin)
#   $2 - (optional) Directory path (default: current directory)
# Output: Remote URL
# Returns:
#   0 - Success
#   1 - Failed to get URL
get_git_remote_url() {
	local remote="${1:-origin}"
	local dir="${2:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git config --get "remote.$remote.url" 2>/dev/null)
}

# Check if repository has remote
# Arguments:
#   $1 - (optional) Remote name (default: origin)
#   $2 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Remote exists
#   1 - Remote does not exist
has_git_remote() {
	local remote="${1:-origin}"
	local dir="${2:-.}"
	
	if ! is_git_repository "$dir"; then
		return 1
	fi
	
	(cd "$dir" && git remote | grep -q "^${remote}$")
}

################################################################################
# Submodule Operations
################################################################################

# Check if repository has submodules
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Has submodules
#   1 - No submodules
has_git_submodules() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		return 1
	fi
	
	[[ -f "$dir/.gitmodules" ]]
}

# Initialize and update submodules
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Success
#   1 - Failed
update_git_submodules() {
	local dir="${1:-.}"
	
	if ! has_git_submodules "$dir"; then
		log_debug "No submodules to update"
		return 0
	fi
	
	log_info "Updating git submodules"
	
	local submodule_output
	if submodule_output=$(cd "$dir" && git submodule update --init --recursive 2>&1); then
		log_success "Submodules updated successfully"
		return 0
	else
		log_error "Failed to update submodules"
		log_debug "Submodule output: $submodule_output"
		return 1
	fi
}

################################################################################
# Utility Functions
################################################################################

# Get git repository name from remote URL
# Arguments:
#   $1 - (optional) Remote name (default: origin)
#   $2 - (optional) Directory path (default: current directory)
# Output: Repository name (without .git extension)
# Returns:
#   0 - Success
#   1 - Failed
get_git_repository_name() {
	local remote="${1:-origin}"
	local dir="${2:-.}"
	
	local url
	url=$(get_git_remote_url "$remote" "$dir") || return 1
	
	# Extract repository name from URL
	basename "$url" .git
}

# Get commit count between two refs
# Arguments:
#   $1 - From ref (e.g., v1.0.0)
#   $2 - To ref (e.g., HEAD)
#   $3 - (optional) Directory path (default: current directory)
# Output: Number of commits
# Returns:
#   0 - Success
#   1 - Failed
get_git_commit_count() {
	local from_ref="$1"
	local to_ref="$2"
	local dir="${3:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git rev-list --count "${from_ref}..${to_ref}" 2>/dev/null)
}

# Check if repository is shallow clone
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Returns:
#   0 - Is shallow clone
#   1 - Not a shallow clone
is_shallow_clone() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		return 1
	fi
	
	(cd "$dir" && git rev-parse --is-shallow-repository 2>/dev/null | grep -q "true")
}

# Get list of all branches
# Arguments:
#   $1 - (optional) Directory path (default: current directory)
# Output: List of branch names (one per line)
# Returns:
#   0 - Success
#   1 - Failed
get_git_branches() {
	local dir="${1:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git branch --format='%(refname:short)' 2>/dev/null)
}

# Get list of remote branches
# Arguments:
#   $1 - (optional) Remote name (default: origin)
#   $2 - (optional) Directory path (default: current directory)
# Output: List of remote branch names (one per line)
# Returns:
#   0 - Success
#   1 - Failed
get_git_remote_branches() {
	local remote="${1:-origin}"
	local dir="${2:-.}"
	
	if ! is_git_repository "$dir"; then
		log_error "Not a git repository: $dir"
		return 1
	fi
	
	(cd "$dir" && git branch -r --format='%(refname:short)' 2>/dev/null | grep "^${remote}/" | sed "s|^${remote}/||")
}

################################################################################
# SSH Key Discovery and Validation
################################################################################

# Discover SSH keys in ~/.ssh directory
# Arguments:
#   $1 - (optional) Key name pattern (default: id_*)
# Output: JSON array of discovered keys
# Returns:
#   0 - Keys found
#   1 - No keys found
discover_local_ssh_keys() {
	local key_pattern="${1:-id_*}"
	local ssh_dir="${HOME}/.ssh"
	
	log_debug "Discovering SSH keys in: $ssh_dir"
	
	if [[ ! -d "$ssh_dir" ]]; then
		log_debug "SSH directory does not exist: $ssh_dir"
		echo "[]"
		return 1
	fi
	
	local keys_json="["
	local first=true
	
	# Find private keys (files without .pub extension)
	while IFS= read -r -d '' key_file; do
		# Skip if it's a public key
		if [[ "$key_file" == *.pub ]]; then
			continue
		fi
		
		# Skip known_hosts, config, etc.
		local basename
		basename=$(basename "$key_file")
		if [[ "$basename" == "known_hosts"* ]] || \
		   [[ "$basename" == "config" ]] || \
		   [[ "$basename" == "authorized_keys"* ]]; then
			continue
		fi
		
		# Skip if public key doesn't exist
		if [[ ! -f "${key_file}.pub" ]]; then
			continue
		fi
		
		# Validate it's actually an SSH key
		if ! ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
			continue
		fi
		
		# Get key info
		local key_info
		key_info=$(ssh-keygen -l -f "$key_file" 2>/dev/null)
		local fingerprint=$(echo "$key_info" | awk '{print $2}')
		local key_type=$(echo "$key_info" | awk '{print $NF}' | tr -d '()')
		local key_bits=$(echo "$key_info" | awk '{print $1}')
		
		# Add to JSON array
		if [[ "$first" == true ]]; then
			first=false
		else
			keys_json+=","
		fi
		
		keys_json+=$(jq -n \
			--arg private_key "$key_file" \
			--arg public_key "${key_file}.pub" \
			--arg fingerprint "$fingerprint" \
			--arg type "$key_type" \
			--arg bits "$key_bits" \
			'{
				private_key_path: $private_key,
				public_key_path: $public_key,
				fingerprint: $fingerprint,
				type: $type,
				bits: $bits
			}')
		
	done < <(find "$ssh_dir" -maxdepth 1 -type f -name "$key_pattern" -print0 2>/dev/null)
	
	keys_json+="]"
	
	local key_count
	key_count=$(echo "$keys_json" | jq 'length')
	
	if [[ "$key_count" -eq 0 ]]; then
		log_debug "No SSH keys found in $ssh_dir"
		echo "[]"
		return 1
	else
		log_debug "Found $key_count SSH key(s) in $ssh_dir"
		echo "$keys_json"
		return 0
	fi
}

# Find best local SSH key for Git operations
# Priority: Ed25519 > RSA-4096 > RSA-2048
# Arguments:
#   None
# Output: JSON with key info, or empty if none found
# Returns:
#   0 - Key found
#   1 - No suitable key found
find_best_local_ssh_key() {
	log_debug "Finding best local SSH key for Git operations"
	
	local keys_json
	keys_json=$(discover_local_ssh_keys) || {
		log_debug "No local SSH keys found"
		return 1
	}
	
	# Priority order: Ed25519, RSA 4096, RSA 2048+
	local best_key
	
	# Try Ed25519 first
	best_key=$(echo "$keys_json" | jq -r '.[] | select(.type == "ED25519") | @json' | head -n1)
	
	if [[ -n "$best_key" ]]; then
		log_debug "Selected Ed25519 key"
		echo "$best_key" | jq -r '.'
		return 0
	fi
	
	# Try RSA 4096
	best_key=$(echo "$keys_json" | jq -r '.[] | select(.type == "RSA" and (.bits | tonumber) >= 4096) | @json' | head -n1)
	
	if [[ -n "$best_key" ]]; then
		log_debug "Selected RSA-4096+ key"
		echo "$best_key" | jq -r '.'
		return 0
	fi
	
	# Try any RSA >= 2048
	best_key=$(echo "$keys_json" | jq -r '.[] | select(.type == "RSA" and (.bits | tonumber) >= 2048) | @json' | head -n1)
	
	if [[ -n "$best_key" ]]; then
		log_debug "Selected RSA-2048+ key"
		echo "$best_key" | jq -r '.'
		return 0
	fi
	
	log_debug "No suitable SSH key found (require Ed25519 or RSA >= 2048)"
	return 1
}

# Validate local SSH key is usable
# Arguments:
#   $1 - Private key path
# Returns:
#   0 - Key is valid and usable
#   1 - Key is invalid or not usable
validate_local_ssh_key() {
	local private_key="$1"
	
	log_debug "Validating local SSH key: $private_key"
	
	# Check private key exists
	if [[ ! -f "$private_key" ]]; then
		log_debug "Private key file not found: $private_key"
		return 1
	fi
	
	# Check public key exists
	if [[ ! -f "${private_key}.pub" ]]; then
		log_debug "Public key file not found: ${private_key}.pub"
		return 1
	fi
	
	# Check permissions (should be 600 or 400)
	local perms
	if [[ "$OSTYPE" == "darwin"* ]]; then
		perms=$(stat -f "%Lp" "$private_key" 2>/dev/null)
	else
		perms=$(stat -c "%a" "$private_key" 2>/dev/null)
	fi
	
	if [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]]; then
		log_warning "Private key has insecure permissions: $perms (expected 600 or 400)"
		log_info "Fixing permissions to 600"
		chmod 600 "$private_key" || {
			log_error "Failed to fix permissions"
			return 1
		}
	fi
	
	# Validate key format
	if ! ssh-keygen -l -f "$private_key" >/dev/null 2>&1; then
		log_debug "Invalid SSH key format: $private_key"
		return 1
	fi
	
	log_debug "SSH key is valid: $private_key"
	return 0
}

# Check if local SSH key is configured for GitHub
# Arguments:
#   $1 - Private key path
#   $2 - (optional) GitHub hostname (default: github.com)
# Returns:
#   0 - Key is configured
#   1 - Key is not configured
is_local_key_configured_for_github() {
	local private_key="$1"
	local github_host="${2:-github.com}"
	local ssh_config="${HOME}/.ssh/config"
	
	log_debug "Checking if local key is configured for GitHub"
	
	if [[ ! -f "$ssh_config" ]]; then
		log_debug "SSH config not found: $ssh_config"
		return 1
	fi
	
	# Check if the key is referenced in SSH config for GitHub
	local key_basename
	key_basename=$(basename "$private_key")
	
	if grep -q "Host $github_host" "$ssh_config" && \
	   grep -A5 "Host $github_host" "$ssh_config" | grep -q "IdentityFile.*$key_basename"; then
		log_debug "Key is configured for GitHub in SSH config"
		return 0
	fi
	
	log_debug "Key is not configured for GitHub"
	return 1
}

################################################################################
# SSH Authentication for Git Operations
################################################################################

# Setup SSH for Git operations with mode selection
# Arguments:
#   $1 - (optional) Authentication mode: ssm, local, auto (default: auto)
#   $2 - Customer name (required for SSM mode)
#   $3 - Project name (required for SSM mode)
#   $4 - Environment name (required for SSM mode)
#   $5 - Service name (required for SSM mode)
#   $6 - (optional) AWS region (for SSM mode, default: auto-detect)
#   $7 - (optional) Output directory (for SSM mode, default: /tmp)
#   $8 - (optional) Local key path (for local mode, default: auto-discover)
# Output: JSON with mode, private_key_path, public_key_path, fingerprint
# Returns:
#   0 - Success
#   1 - Setup failed
setup_git_ssh_authentication() {
	local auth_mode="${1:-auto}"
	local customer="${2:-}"
	local project="${3:-}"
	local environment="${4:-}"
	local service_name="${5:-}"
	local aws_region="${6:-}"
	local output_dir="${7:-/tmp}"
	local local_key_path="${8:-}"
	
	log_step "Setting up SSH authentication for Git operations"
	log_info "Authentication mode: $auth_mode"
	
	local key_info
	local private_key_path
	local actual_mode
	
	case "$auth_mode" in
		"$SSH_AUTH_MODE_LOCAL")
			log_info "Using LOCAL mode (existing SSH key)"
			
			# Use specified key or discover best available
			if [[ -n "$local_key_path" ]]; then
				log_info "Using specified local key: $local_key_path"
				
				if ! validate_local_ssh_key "$local_key_path"; then
					log_error "Specified local SSH key is invalid: $local_key_path"
					return 1
				fi
				
				private_key_path="$local_key_path"
			else
				log_info "Auto-discovering best local SSH key"
				
				key_info=$(find_best_local_ssh_key) || {
					log_error "No suitable local SSH key found"
					log_error "Generate a key with: ssh-keygen -t ed25519 -C 'your_email@example.com'"
					return 1
				}
				
				private_key_path=$(echo "$key_info" | jq -r '.private_key_path')
				log_info "Selected local key: $private_key_path"
			fi
			
			actual_mode="$SSH_AUTH_MODE_LOCAL"
			;;
			
		"$SSH_AUTH_MODE_SSM")
			log_info "Using SSM mode (provision from AWS SSM)"
			
			# Validate required parameters
			if [[ -z "$customer" ]] || [[ -z "$project" ]] || [[ -z "$environment" ]] || [[ -z "$service_name" ]]; then
				log_error "SSM mode requires customer, project, environment, and service_name"
				return 1
			fi
			
			# Source SSH operations library if not loaded
			if [[ -z "${FORGE_SSH_OPERATIONS_LOADED:-}" ]]; then
				source "${FORGE_GIT_OPERATIONS_DIR}/forge-ssh-operations.sh"
			fi
			
			# Provision SSH key (pull from SSM or generate if not exists)
			key_info=$(provision_ssh_key "$customer" "$project" "$environment" "$service_name" "$output_dir" "$aws_region") || {
				log_error "Failed to provision SSH key from SSM"
				return 1
			}
			
			private_key_path=$(echo "$key_info" | jq -r '.private_key_path')
			log_info "Provisioned key from SSM: $private_key_path"
			
			actual_mode="$SSH_AUTH_MODE_SSM"
			;;
			
		"$SSH_AUTH_MODE_AUTO"|*)
			log_info "Using AUTO mode (try local first, fallback to SSM)"
			
			# Try local first
			if key_info=$(find_best_local_ssh_key 2>/dev/null); then
				private_key_path=$(echo "$key_info" | jq -r '.private_key_path')
				
				if validate_local_ssh_key "$private_key_path"; then
					log_success "Using local SSH key: $private_key_path"
					actual_mode="$SSH_AUTH_MODE_LOCAL"
				else
					log_warning "Local SSH key is invalid, falling back to SSM mode"
					key_info=""
				fi
			else
				log_info "No local SSH keys found, falling back to SSM mode"
			fi
			
			# Fallback to SSM if local failed
			if [[ -z "$key_info" ]]; then
				if [[ -z "$customer" ]] || [[ -z "$project" ]] || [[ -z "$environment" ]] || [[ -z "$service_name" ]]; then
					log_error "No local SSH key available and SSM mode requires customer/project/environment/service_name"
					return 1
				fi
				
				# Source SSH operations library if not loaded
				if [[ -z "${FORGE_SSH_OPERATIONS_LOADED:-}" ]]; then
					source "${FORGE_GIT_OPERATIONS_DIR}/forge-ssh-operations.sh"
				fi
				
				key_info=$(provision_ssh_key "$customer" "$project" "$environment" "$service_name" "$output_dir" "$aws_region") || {
					log_error "Failed to provision SSH key from SSM"
					return 1
				}
				
				private_key_path=$(echo "$key_info" | jq -r '.private_key_path')
				log_success "Provisioned key from SSM: $private_key_path"
				actual_mode="$SSH_AUTH_MODE_SSM"
			fi
			;;
	esac
	
	# Common setup for both modes
	
	# Add to ssh-agent
	log_info "Adding SSH key to ssh-agent"
	if [[ "$actual_mode" == "$SSH_AUTH_MODE_SSM" ]]; then
		# Source SSH operations library if not loaded
		if [[ -z "${FORGE_SSH_OPERATIONS_LOADED:-}" ]]; then
			source "${FORGE_GIT_OPERATIONS_DIR}/forge-ssh-operations.sh"
		fi
		add_ssh_key_to_agent "$private_key_path" || {
			log_error "Failed to add SSH key to ssh-agent"
			return 1
		}
	else
		# For local keys, try to add but don't fail if it's already there
		if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$private_key_path" | awk '{print $2}')"; then
			ssh-add "$private_key_path" 2>/dev/null || log_warning "Could not add key to ssh-agent (may already be added)"
		fi
	fi
	
	# Configure SSH for GitHub (only if not already configured)
	if ! is_local_key_configured_for_github "$private_key_path"; then
		log_info "Configuring SSH for GitHub"
		
		if [[ "$actual_mode" == "$SSH_AUTH_MODE_SSM" ]]; then
			# Source SSH operations library if not loaded
			if [[ -z "${FORGE_SSH_OPERATIONS_LOADED:-}" ]]; then
				source "${FORGE_GIT_OPERATIONS_DIR}/forge-ssh-operations.sh"
			fi
			configure_ssh_for_github "$private_key_path" || {
				log_error "Failed to configure SSH for GitHub"
				return 1
			}
		else
			# For local keys, add minimal config
			local ssh_config="${HOME}/.ssh/config"
			if [[ ! -f "$ssh_config" ]] || ! grep -q "Host github.com" "$ssh_config"; then
				cat >> "$ssh_config" <<-SSHEOF
				
				# Forge Git SSH configuration
				Host github.com
				    HostName github.com
				    User git
				    IdentityFile $private_key_path
				    IdentitiesOnly yes
				    StrictHostKeyChecking accept-new
				SSHEOF
				chmod 600 "$ssh_config"
				log_info "GitHub SSH configuration added to $ssh_config"
			fi
		fi
	else
		log_info "SSH already configured for GitHub"
	fi
	
	log_success "SSH authentication configured successfully"
	log_info "Mode: $actual_mode"
	log_info "Key: $private_key_path"
	
	# Export key path and mode for use in other functions
	export GIT_SSH_KEY_PATH="$private_key_path"
	export GIT_SSH_AUTH_MODE="$actual_mode"
	
	# Return info
	local fingerprint
	fingerprint=$(ssh-keygen -lf "$private_key_path" | awk '{print $2}')
	
	jq -n \
		--arg mode "$actual_mode" \
		--arg private_key "$private_key_path" \
		--arg public_key "${private_key_path}.pub" \
		--arg fingerprint "$fingerprint" \
		'{
			mode: $mode,
			private_key_path: $private_key,
			public_key_path: $public_key,
			fingerprint: $fingerprint
		}'
	
	return 0
}

# Clone repository with SSH authentication (dual mode)
# Arguments:
#   $1 - Repository URL (SSH format: git@github.com:org/repo.git)
#   $2 - Destination directory
#   $3 - (optional) Branch name
#   $4 - (optional) Auth mode: ssm, local, auto (default: auto)
#   $5 - Customer name (required for SSM mode)
#   $6 - Project name (required for SSM mode)
#   $7 - Environment name (required for SSM mode)
#   $8 - Service name (required for SSM mode)
#   $9 - (optional) AWS region (for SSM mode)
# Returns:
#   0 - Success
#   1 - Clone failed
# Examples:
#   # Auto mode (uses local key if available)
#   git_clone_with_ssh "git@github.com:org/repo.git" "/workspace"
#   
#   # Local mode (force use of local key)
#   git_clone_with_ssh "git@github.com:org/repo.git" "/workspace" "main" "local"
#   
#   # SSM mode (force SSM provisioning)
#   git_clone_with_ssh "git@github.com:org/repo.git" "/workspace" "main" "ssm" "sanofi" "cronus" "dev" "video-calling-agent"
git_clone_with_ssh() {
	local repo_url="$1"
	local dest_dir="$2"
	local branch="${3:-}"
	local auth_mode="${4:-auto}"
	local customer="${5:-}"
	local project="${6:-}"
	local environment="${7:-}"
	local service_name="${8:-}"
	local aws_region="${9:-}"
	
	log_info "Cloning repository: $repo_url"
	
	# Setup SSH authentication (will use mode logic)
	setup_git_ssh_authentication \
		"$auth_mode" \
		"$customer" \
		"$project" \
		"$environment" \
		"$service_name" \
		"$aws_region" \
		>/dev/null || return 1
	
	# Clone arguments
	local clone_args=(clone "$repo_url" "$dest_dir")
	
	if [[ -n "$branch" ]]; then
		clone_args+=(--branch "$branch")
		log_info "Cloning branch: $branch"
	fi
	
	# Clone repository
	if git "${clone_args[@]}" 2>&1; then
		log_success "Repository cloned successfully"
		return 0
	else
		log_error "Failed to clone repository"
		return 1
	fi
}

# Fetch repository with SSH authentication (dual mode)
# Arguments:
#   $1 - Repository directory
#   $2 - Customer name
#   $1 - Repository directory
#   $2 - (optional) Remote name (default: origin)
#   $3 - (optional) Auth mode: ssm, local, auto (default: auto)
#   $4 - Customer name (required for SSM mode)
#   $5 - Project name (required for SSM mode)
#   $6 - Environment name (required for SSM mode)
#   $7 - Service name (required for SSM mode)
#   $8 - (optional) AWS region (for SSM mode)
# Returns:
#   0 - Success
#   1 - Fetch failed
git_fetch_with_ssh() {
	local repo_dir="${1:-.}"
	local remote="${2:-origin}"
	local auth_mode="${3:-auto}"
	local customer="${4:-}"
	local project="${5:-}"
	local environment="${6:-}"
	local service_name="${7:-}"
	local aws_region="${8:-}"
	
	log_info "Fetching from remote: $remote"
	
	# Check if directory exists
	if [[ ! -d "$repo_dir" ]]; then
		log_error "Repository directory does not exist: $repo_dir"
		return 1
	fi
	
	# Setup SSH authentication
	setup_git_ssh_authentication \
		"$auth_mode" \
		"$customer" \
		"$project" \
		"$environment" \
		"$service_name" \
		"$aws_region" \
		>/dev/null || return 1
	
	# Fetch
	if (cd "$repo_dir" && git fetch "$remote" 2>&1); then
		log_success "Fetch completed successfully"
		return 0
	else
		log_error "Failed to fetch from $remote"
		return 1
	fi
}

# Pull repository with SSH authentication (dual mode)
# Arguments:
#   $1 - Repository directory
#   $2 - (optional) Remote name (default: origin)
#   $3 - (optional) Branch name (default: current)
#   $4 - (optional) Auth mode: ssm, local, auto (default: auto)
#   $5 - Customer name (required for SSM mode)
#   $6 - Project name (required for SSM mode)
#   $7 - Environment name (required for SSM mode)
#   $8 - Service name (required for SSM mode)
#   $9 - (optional) AWS region (for SSM mode)
# Returns:
#   0 - Success
#   1 - Pull failed
git_pull_with_ssh() {
	local repo_dir="${1:-.}"
	local remote="${2:-origin}"
	local branch="${3:-}"
	local auth_mode="${4:-auto}"
	local customer="${5:-}"
	local project="${6:-}"
	local environment="${7:-}"
	local service_name="${8:-}"
	local aws_region="${9:-}"
	
	log_info "Pulling from remote: $remote"
	
	# Check if directory exists
	if [[ ! -d "$repo_dir" ]]; then
		log_error "Repository directory does not exist: $repo_dir"
		return 1
	fi
	
	# Setup SSH authentication
	setup_git_ssh_authentication \
		"$auth_mode" \
		"$customer" \
		"$project" \
		"$environment" \
		"$service_name" \
		"$aws_region" \
		>/dev/null || return 1
	
	# Get current branch if not specified
	if [[ -z "$branch" ]]; then
		branch=$(cd "$repo_dir" && get_git_branch) || return 1
	fi
	
	# Pull
	if (cd "$repo_dir" && git pull "$remote" "$branch" 2>&1); then
		log_success "Pull completed successfully"
		return 0
	else
		log_error "Failed to pull from $remote"
		return 1
	fi
}

################################################################################
# Export Functions
################################################################################

log_info "Forge Git Operations Library loaded (v1.0.0)"
