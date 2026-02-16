#!/usr/bin/env bash

################################################################################
# Forge SSH Operations Library
################################################################################
# Version: 1.0.0
# Description: SSH key management for Forge build operations with AWS SSM integration
#
# Features:
# - SSH key pair generation (Ed25519 preferred, RSA fallback)
# - AWS SSM Parameter Store integration
# - Forge naming pattern compliance
# - Key existence checking
# - GitHub SSH key deployment helpers
# - SSH agent integration
# - Key rotation support
#
# Dependencies:
# - forge-core.sh
# - forge-patterns.sh
# - forge-aws-discovery.sh
# - AWS CLI
# - ssh-keygen
#
# Author: Moai Forge Team
# Created: 2026-02-07
################################################################################

# Prevent double-loading
if [[ -n "${FORGE_SSH_OPERATIONS_LOADED:-}" ]]; then
    return 0
fi
FORGE_SSH_OPERATIONS_LOADED=1

################################################################################
# Dependencies
################################################################################

# Determine script directory
FORGE_SSH_OPERATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -z "${FORGE_CORE_LOADED:-}" ]]; then
    source "${FORGE_SSH_OPERATIONS_DIR}/forge-core.sh"
fi

if [[ -z "${FORGE_PATTERNS_LOADED:-}" ]]; then
    source "${FORGE_SSH_OPERATIONS_DIR}/forge-patterns.sh"
fi

if [[ -z "${FORGE_AWS_DISCOVERY_LOADED:-}" ]]; then
    source "${FORGE_SSH_OPERATIONS_DIR}/forge-aws-discovery.sh"
fi

# Validate required commands
validate_required_commands ssh-keygen aws

################################################################################
# Constants
################################################################################

readonly SSH_KEY_TYPE_ED25519="ed25519"
readonly SSH_KEY_TYPE_RSA="rsa"
readonly SSH_KEY_BITS_RSA=4096
readonly SSH_KEY_BITS_ED25519=256
readonly SSH_KEY_DEFAULT_TYPE="$SSH_KEY_TYPE_ED25519"
readonly SSM_PARAMETER_TYPE="SecureString"
readonly SSH_KEY_COMMENT_PREFIX="forge-build-key"
readonly SSH_PUSH_TO_SSM_DEFAULT=false  # Local-only by default, SSM push is opt-in

################################################################################
# SSH Key Generation
################################################################################

# Generate SSH key pair
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - (optional) Key type: ed25519 or rsa (default: ed25519)
#   $6 - (optional) Output directory (default: /tmp)
# Output: JSON with private_key_path, public_key_path, fingerprint
# Returns:
#   0 - Success
#   1 - Generation failed
generate_ssh_key() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local key_type="${5:-$SSH_KEY_DEFAULT_TYPE}"
    local output_dir="${6:-/tmp}"
    
    log_info "Generating SSH key pair for ${customer}/${project}/${environment}/${service_name}"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    validate_service_name "$service_name" || return 1
    
    # Get key name
    local key_name
    key_name=$(get_ssh_key_name "$customer" "$project" "$environment" "$service_name") || return 1
    
    # Set key parameters
    local key_file="${output_dir}/${key_name}"
    local key_comment="${SSH_KEY_COMMENT_PREFIX}-${customer}-${project}-${environment}-${service_name}"
    local ssh_keygen_args=()
    
    case "$key_type" in
        "$SSH_KEY_TYPE_ED25519")
            ssh_keygen_args+=(-t ed25519)
            log_info "Using Ed25519 key type"
            ;;
        "$SSH_KEY_TYPE_RSA")
            ssh_keygen_args+=(-t rsa -b "$SSH_KEY_BITS_RSA")
            log_info "Using RSA-${SSH_KEY_BITS_RSA} key type"
            ;;
        *)
            log_error "Invalid key type: $key_type (supported: ed25519, rsa)"
            return 1
            ;;
    esac
    
    # Generate key
    log_info "Generating key at: $key_file"
    
    if ssh-keygen \
        "${ssh_keygen_args[@]}" \
        -f "$key_file" \
        -N "" \
        -C "$key_comment" \
        >/dev/null 2>&1; then
        
        log_success "SSH key pair generated successfully"
    else
        log_error "Failed to generate SSH key pair"
        return 1
    fi
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(ssh-keygen -lf "$key_file" | awk '{print $2}')
    
    log_info "Key fingerprint: $fingerprint"
    
    # Return JSON with paths
    jq -n \
        --arg private_key_path "$key_file" \
        --arg public_key_path "${key_file}.pub" \
        --arg fingerprint "$fingerprint" \
        --arg key_type "$key_type" \
        --arg key_name "$key_name" \
        '{
            private_key_path: $private_key_path,
            public_key_path: $public_key_path,
            fingerprint: $fingerprint,
            key_type: $key_type,
            key_name: $key_name
        }'
    
    return 0
}

# Generate SSH key and install to ~/.ssh directory
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - (optional) Key type: ed25519 or rsa (default: ed25519)
#   $6 - (optional) Overwrite if exists (true/false, default: false)
# Output: JSON with private_key_path, public_key_path, fingerprint, key_name
# Returns:
#   0 - Success
#   1 - Generation failed
#   2 - Key already exists (and overwrite=false)
# 
# Workflow:
#   - LOCAL-ONLY by default (does NOT push to SSM)
#   - Generates key with Forge naming convention
#   - Installs to ~/.ssh with correct permissions
#   - For SSM push, use setup_complete_git_ssh_environment() with push_to_ssm=true
#
# Example:
#   generate_and_install_ssh_key "sanofi" "cronus" "dev" "video-calling-agent"
#   # Creates: ~/.ssh/SanofiCronusDevVideoCallingAgentBuildSshKey
generate_and_install_ssh_key() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local key_type="${5:-$SSH_KEY_DEFAULT_TYPE}"
    local overwrite="${6:-false}"
    
    log_step "Generating and installing SSH key for ${customer}/${project}/${environment}/${service_name}"
    
    # Validate inputs
    validate_customer_name "$customer" || return 1
    validate_project_name "$project" || return 1
    validate_environment_name "$environment" || return 1
    validate_service_name "$service_name" || return 1
    
    # Get key name (CamelCase)
    local key_name
    key_name=$(get_ssh_key_name "$customer" "$project" "$environment" "$service_name") || return 1
    
    # SSH directory setup
    local ssh_dir="${HOME}/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        log_info "Creating SSH directory: $ssh_dir"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
    
    # Key file paths
    local private_key_file="${ssh_dir}/${key_name}"
    local public_key_file="${private_key_file}.pub"
    
    # Check if key already exists
    if [[ -f "$private_key_file" ]]; then
        if [[ "$overwrite" == "true" ]]; then
            log_warning "Key already exists, overwriting: $private_key_file"
            rm -f "$private_key_file" "$public_key_file"
        else
            log_error "Key already exists: $private_key_file"
            log_error "Use overwrite=true to replace or delete manually"
            return 2
        fi
    fi
    
    # Set key parameters
    local key_comment="${SSH_KEY_COMMENT_PREFIX}-${customer}-${project}-${environment}-${service_name}"
    local ssh_keygen_args=()
    
    case "$key_type" in
        "$SSH_KEY_TYPE_ED25519")
            ssh_keygen_args+=(-t ed25519)
            log_info "Generating Ed25519 key"
            ;;
        "$SSH_KEY_TYPE_RSA")
            ssh_keygen_args+=(-t rsa -b "$SSH_KEY_BITS_RSA")
            log_info "Generating RSA-${SSH_KEY_BITS_RSA} key"
            ;;
        *)
            log_error "Invalid key type: $key_type (supported: ed25519, rsa)"
            return 1
            ;;
    esac
    
    # Generate key
    log_info "Generating SSH key: $private_key_file"
    
    if ssh-keygen \
        "${ssh_keygen_args[@]}" \
        -f "$private_key_file" \
        -N "" \
        -C "$key_comment" \
        >/dev/null 2>&1; then
        
        # Set correct permissions
        chmod 600 "$private_key_file"
        chmod 644 "$public_key_file"
        
        log_success "SSH key pair generated successfully"
    else
        log_error "Failed to generate SSH key pair"
        return 1
    fi
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(ssh-keygen -lf "$private_key_file" | awk '{print $2}')
    
    log_success "SSH key installed successfully"
    log_info "Private key: $private_key_file"
    log_info "Public key: $public_key_file"
    log_info "Fingerprint: $fingerprint"
    
    # Return JSON with paths
    jq -n \
        --arg private_key_path "$private_key_file" \
        --arg public_key_path "$public_key_file" \
        --arg fingerprint "$fingerprint" \
        --arg key_type "$key_type" \
        --arg key_name "$key_name" \
        '{
            private_key_path: $private_key_path,
            public_key_path: $public_key_path,
            fingerprint: $fingerprint,
            key_type: $key_type,
            key_name: $key_name
        }'
    
    return 0
}

################################################################################
# AWS SSM Parameter Store Operations
################################################################################

# Check if SSH key exists in SSM
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - (optional) AWS region (default: auto-detect)
# Returns:
#   0 - Key exists
#   1 - Key does not exist or check failed
ssh_key_exists_in_ssm() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local aws_region="${5:-}"
    
    # Auto-detect region if not provided
    if [[ -z "$aws_region" ]]; then
        aws_region=$(get_aws_region) || return 1
    fi
    
    # Get SSM parameter path
    local private_key_path
    private_key_path=$(get_ssh_private_key_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    
    log_debug "Checking if SSH key exists in SSM: $private_key_path"
    
    # Check if parameter exists
    if aws ssm get-parameter \
        --name "$private_key_path" \
        --region "$aws_region" \
        >/dev/null 2>&1; then
        
        log_debug "SSH key exists in SSM"
        return 0
    else
        log_debug "SSH key does not exist in SSM"
        return 1
    fi
}

# Push SSH key to AWS SSM Parameter Store
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Private key file path
#   $6 - Public key file path
#   $7 - (optional) AWS region (default: auto-detect)
#   $8 - (optional) KMS key ID for encryption (default: default AWS managed key)
# Returns:
#   0 - Success
#   1 - Push failed
push_ssh_key_to_ssm() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local private_key_file="$5"
    local public_key_file="$6"
    local aws_region="${7:-}"
    local kms_key_id="${8:-}"
    
    log_info "Pushing SSH key to AWS SSM Parameter Store"
    
    # Validate inputs
    if [[ ! -f "$private_key_file" ]]; then
        log_error "Private key file not found: $private_key_file"
        return 1
    fi
    
    if [[ ! -f "$public_key_file" ]]; then
        log_error "Public key file not found: $public_key_file"
        return 1
    fi
    
    # Auto-detect region if not provided
    if [[ -z "$aws_region" ]]; then
        aws_region=$(get_aws_region) || return 1
    fi
    
    # Get SSM parameter paths
    local private_key_path
    local public_key_path
    local metadata_path
    
    private_key_path=$(get_ssh_private_key_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    public_key_path=$(get_ssh_public_key_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    metadata_path=$(get_ssh_key_metadata_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    
    # Read key contents
    local private_key_content
    local public_key_content
    
    private_key_content=$(cat "$private_key_file") || {
        log_error "Failed to read private key file"
        return 1
    }
    
    public_key_content=$(cat "$public_key_file") || {
        log_error "Failed to read public key file"
        return 1
    }
    
    # Get key fingerprint
    local fingerprint
    fingerprint=$(ssh-keygen -lf "$private_key_file" | awk '{print $2}')
    
    # Create metadata JSON
    local metadata
    metadata=$(jq -n \
        --arg fingerprint "$fingerprint" \
        --arg public_key "$public_key_content" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg customer "$customer" \
        --arg project "$project" \
        --arg environment "$environment" \
        --arg service "$service_name" \
        '{
            fingerprint: $fingerprint,
            public_key: $public_key,
            created_at: $created_at,
            customer: $customer,
            project: $project,
            environment: $environment,
            service: $service
        }')
    
    # Prepare AWS CLI arguments
    local aws_args=(
        --region "$aws_region"
        --type "$SSM_PARAMETER_TYPE"
        --overwrite
    )
    
    # Add KMS key if provided
    if [[ -n "$kms_key_id" ]]; then
        aws_args+=(--key-id "$kms_key_id")
    fi
    
    # Push private key
    log_info "Pushing private key to: $private_key_path"
    if aws ssm put-parameter \
        --name "$private_key_path" \
        --value "$private_key_content" \
        --description "Forge build SSH private key for ${customer}/${project}/${environment}/${service_name}" \
        "${aws_args[@]}" \
        >/dev/null 2>&1; then
        
        log_success "Private key pushed successfully"
    else
        log_error "Failed to push private key to SSM"
        return 1
    fi
    
    # Push public key (as String, not SecureString)
    log_info "Pushing public key to: $public_key_path"
    if aws ssm put-parameter \
        --name "$public_key_path" \
        --value "$public_key_content" \
        --description "Forge build SSH public key for ${customer}/${project}/${environment}/${service_name}" \
        --type String \
        --region "$aws_region" \
        --overwrite \
        >/dev/null 2>&1; then
        
        log_success "Public key pushed successfully"
    else
        log_error "Failed to push public key to SSM"
        return 1
    fi
    
    # Push metadata
    log_info "Pushing metadata to: $metadata_path"
    if aws ssm put-parameter \
        --name "$metadata_path" \
        --value "$metadata" \
        --description "Forge build SSH key metadata for ${customer}/${project}/${environment}/${service_name}" \
        --type String \
        --region "$aws_region" \
        --overwrite \
        >/dev/null 2>&1; then
        
        log_success "Metadata pushed successfully"
    else
        log_warning "Failed to push metadata to SSM (non-critical)"
    fi
    
    log_success "SSH key successfully stored in SSM Parameter Store"
    log_info "Private key: $private_key_path"
    log_info "Public key: $public_key_path"
    log_info "Fingerprint: $fingerprint"
    
    return 0
}

# Pull SSH key from AWS SSM Parameter Store
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Output directory for keys
#   $6 - (optional) AWS region (default: auto-detect)
# Output: JSON with private_key_path, public_key_path, fingerprint
# Returns:
#   0 - Success
#   1 - Pull failed
pull_ssh_key_from_ssm() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local output_dir="$5"
    local aws_region="${6:-}"
    
    log_info "Pulling SSH key from AWS SSM Parameter Store"
    
    # Validate output directory
    if [[ ! -d "$output_dir" ]]; then
        log_error "Output directory does not exist: $output_dir"
        return 1
    fi
    
    # Auto-detect region if not provided
    if [[ -z "$aws_region" ]]; then
        aws_region=$(get_aws_region) || return 1
    fi
    
    # Get SSM parameter paths
    local private_key_path
    local public_key_path
    
    private_key_path=$(get_ssh_private_key_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    public_key_path=$(get_ssh_public_key_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    
    # Get key name
    local key_name
    key_name=$(get_ssh_key_name "$customer" "$project" "$environment" "$service_name") || return 1
    
    # Output file paths
    local private_key_file="${output_dir}/${key_name}"
    local public_key_file="${output_dir}/${key_name}.pub"
    
    # Pull private key
    log_info "Pulling private key from: $private_key_path"
    if aws ssm get-parameter \
        --name "$private_key_path" \
        --region "$aws_region" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text > "$private_key_file" 2>/dev/null; then
        
        chmod 600 "$private_key_file"
        log_success "Private key pulled successfully"
    else
        log_error "Failed to pull private key from SSM"
        return 1
    fi
    
    # Pull public key
    log_info "Pulling public key from: $public_key_path"
    if aws ssm get-parameter \
        --name "$public_key_path" \
        --region "$aws_region" \
        --query 'Parameter.Value' \
        --output text > "$public_key_file" 2>/dev/null; then
        
        chmod 644 "$public_key_file"
        log_success "Public key pulled successfully"
    else
        log_error "Failed to pull public key from SSM"
        rm -f "$private_key_file"
        return 1
    fi
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(ssh-keygen -lf "$private_key_file" | awk '{print $2}')
    
    log_success "SSH key successfully retrieved from SSM"
    log_info "Private key: $private_key_file"
    log_info "Public key: $public_key_file"
    log_info "Fingerprint: $fingerprint"
    
    # Return JSON with paths
    jq -n \
        --arg private_key_path "$private_key_file" \
        --arg public_key_path "$public_key_file" \
        --arg fingerprint "$fingerprint" \
        --arg key_name "$key_name" \
        '{
            private_key_path: $private_key_path,
            public_key_path: $public_key_path,
            fingerprint: $fingerprint,
            key_name: $key_name
        }'
    
    return 0
}

# Get SSH key metadata from SSM
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - (optional) AWS region (default: auto-detect)
# Output: JSON with metadata
# Returns:
#   0 - Success
#   1 - Failed
get_ssh_key_metadata_from_ssm() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local aws_region="${5:-}"
    
    # Auto-detect region if not provided
    if [[ -z "$aws_region" ]]; then
        aws_region=$(get_aws_region) || return 1
    fi
    
    # Get metadata path
    local metadata_path
    metadata_path=$(get_ssh_key_metadata_ssm_path "$customer" "$project" "$environment" "$service_name") || return 1
    
    # Pull metadata
    aws ssm get-parameter \
        --name "$metadata_path" \
        --region "$aws_region" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null
}

################################################################################
# SSH Key Provisioning (Generate or Retrieve)
################################################################################

# Provision SSH key (generate if not exists, retrieve if exists)
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Output directory
#   $6 - (optional) AWS region (default: auto-detect)
#   $7 - (optional) Force regeneration (true/false, default: false)
# Output: JSON with private_key_path, public_key_path, fingerprint, created (true/false)
# Returns:
#   0 - Success
#   1 - Provisioning failed
provision_ssh_key() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local output_dir="$5"
    local aws_region="${6:-}"
    local force_regenerate="${7:-false}"
    
    log_step "Provisioning SSH key for ${customer}/${project}/${environment}/${service_name}"
    
    # Auto-detect region if not provided
    if [[ -z "$aws_region" ]]; then
        aws_region=$(get_aws_region) || return 1
    fi
    
    local created=false
    local result
    
    # Check if key exists in SSM
    if ssh_key_exists_in_ssm "$customer" "$project" "$environment" "$service_name" "$aws_region"; then
        if [[ "$force_regenerate" == "true" ]]; then
            log_warning "SSH key exists in SSM but force regeneration requested"
            created=true
        else
            log_info "SSH key already exists in SSM, pulling..."
            result=$(pull_ssh_key_from_ssm "$customer" "$project" "$environment" "$service_name" "$output_dir" "$aws_region") || return 1
            
            # Add created flag to result
            echo "$result" | jq --arg created "false" '. + {created: ($created == "true")}'
            return 0
        fi
    else
        log_info "SSH key does not exist in SSM, generating..."
        created=true
    fi
    
    # Generate new key
    result=$(generate_ssh_key "$customer" "$project" "$environment" "$service_name" "ed25519" "$output_dir") || return 1
    
    local private_key_path
    local public_key_path
    
    private_key_path=$(echo "$result" | jq -r '.private_key_path')
    public_key_path=$(echo "$result" | jq -r '.public_key_path')
    
    # Push to SSM
    if push_ssh_key_to_ssm "$customer" "$project" "$environment" "$service_name" "$private_key_path" "$public_key_path" "$aws_region"; then
        log_success "SSH key provisioned successfully"
        
        # Add created flag to result
        echo "$result" | jq --arg created "true" '. + {created: ($created == "true")}'
        return 0
    else
        log_error "Failed to push SSH key to SSM"
        return 1
    fi
}

################################################################################
# SSH Agent Integration
################################################################################

# Add SSH key to ssh-agent
# Arguments:
#   $1 - Private key file path
# Returns:
#   0 - Success
#   1 - Failed
add_ssh_key_to_agent() {
    local private_key_file="$1"
    
    if [[ ! -f "$private_key_file" ]]; then
        log_error "Private key file not found: $private_key_file"
        return 1
    fi
    
    log_info "Adding SSH key to ssh-agent"
    
    # Ensure ssh-agent is running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_warning "SSH_AUTH_SOCK not set, starting ssh-agent"
        eval "$(ssh-agent -s)" >/dev/null 2>&1
    fi
    
    # Add key to agent
    if ssh-add "$private_key_file" >/dev/null 2>&1; then
        log_success "SSH key added to ssh-agent"
        return 0
    else
        log_error "Failed to add SSH key to ssh-agent"
        return 1
    fi
}

# Configure SSH for GitHub (create/update ~/.ssh/config)
# Arguments:
#   $1 - Private key file path
#   $2 - (optional) GitHub hostname (default: github.com)
# Returns:
#   0 - Success
#   1 - Failed
configure_ssh_for_github() {
    local private_key_file="$1"
    local github_host="${2:-github.com}"
    
    if [[ ! -f "$private_key_file" ]]; then
        log_error "Private key file not found: $private_key_file"
        return 1
    fi
    
    local ssh_config_file="${HOME}/.ssh/config"
    local ssh_dir="${HOME}/.ssh"
    
    # Ensure .ssh directory exists
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
    
    log_info "Configuring SSH for GitHub: $github_host"
    
    # Check if configuration already exists
    if [[ -f "$ssh_config_file" ]] && grep -q "Host $github_host" "$ssh_config_file"; then
        log_info "GitHub SSH configuration already exists in $ssh_config_file"
        return 0
    fi
    
    # Append configuration
    cat >> "$ssh_config_file" <<SSHEOF

# Forge build SSH configuration for GitHub
Host $github_host
    HostName $github_host
    User git
    IdentityFile $private_key_file
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
SSHEOF
    
    chmod 600 "$ssh_config_file"
    
    log_success "GitHub SSH configuration added to $ssh_config_file"
    return 0
}

################################################################################
# Git and Keychain Configuration
################################################################################

# Configure Git and keychain to use SSH key
# Arguments:
#   $1 - Private key file path
#   $2 - (optional) GitHub hostname (default: github.com)
#   $3 - (optional) Add to keychain permanently (true/false, default: true on macOS)
# Returns:
#   0 - Success
#   1 - Configuration failed
#
# Features:
#   - Starts ssh-agent if not running
#   - Adds key to ssh-agent
#   - macOS: Adds to keychain with --apple-use-keychain (or -K for legacy)
#   - Linux: Adds to ssh-agent only
#   - Updates ~/.ssh/config with GitHub entry
#   - Sets IdentityFile, AddKeysToAgent yes, IdentitiesOnly yes
#   - macOS: Adds UseKeychain yes
#   - Handles existing config entries (update vs create)
configure_git_to_use_ssh_key() {
    local private_key="$1"
    local github_host="${2:-github.com}"
    local add_to_keychain="${3:-true}"
    
    log_step "Configuring Git to use SSH key: $(basename "$private_key")"
    
    # Validate key exists
    if [[ ! -f "$private_key" ]]; then
        log_error "Private key not found: $private_key"
        return 1
    fi
    
    if [[ ! -f "${private_key}.pub" ]]; then
        log_error "Public key not found: ${private_key}.pub"
        return 1
    fi
    
    # 1. Start ssh-agent if not running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_info "Starting ssh-agent"
        eval "$(ssh-agent -s)" >/dev/null 2>&1
    else
        log_debug "ssh-agent already running"
    fi
    
    # 2. Add key to ssh-agent
    log_info "Adding SSH key to ssh-agent"
    
    # Check if key is already added
    local fingerprint
    fingerprint=$(ssh-keygen -lf "$private_key" | awk '{print $2}')
    
    if ssh-add -l 2>/dev/null | grep -q "$fingerprint"; then
        log_info "SSH key already in ssh-agent"
    else
        # Add key with different options based on OS
        if [[ "$OSTYPE" == "darwin"* ]] && [[ "$add_to_keychain" == "true" ]]; then
            # macOS: Add to keychain for persistence
            log_info "Adding key to macOS keychain"
            if ssh-add --apple-use-keychain "$private_key" 2>/dev/null; then
                log_success "Key added to ssh-agent and macOS keychain"
            elif ssh-add -K "$private_key" 2>/dev/null; then
                # Fallback for older macOS versions
                log_success "Key added to ssh-agent and macOS keychain (legacy flag)"
            else
                # Fallback without keychain
                log_warning "Failed to add to keychain, adding to ssh-agent only"
                ssh-add "$private_key" || {
                    log_error "Failed to add SSH key to ssh-agent"
                    return 1
                }
            fi
        else
            # Linux/other: Just add to agent
            ssh-add "$private_key" || {
                log_error "Failed to add SSH key to ssh-agent"
                return 1
            }
            log_success "Key added to ssh-agent"
        fi
    fi
    
    # 3. Configure ~/.ssh/config
    local ssh_config="${HOME}/.ssh/config"
    
    log_info "Configuring SSH config for GitHub"
    
    # Ensure .ssh directory exists
    if [[ ! -d "${HOME}/.ssh" ]]; then
        mkdir -p "${HOME}/.ssh"
        chmod 700 "${HOME}/.ssh"
    fi
    
    # Check if config already has GitHub entry for this key
    if [[ -f "$ssh_config" ]] && grep -q "Host $github_host" "$ssh_config"; then
        # Check if our key is already configured
        if grep -A5 "Host $github_host" "$ssh_config" | grep -q "IdentityFile.*$(basename "$private_key")"; then
            log_info "GitHub SSH config already exists for this key"
        else
            log_warning "GitHub SSH config exists but uses different key"
            log_info "Updating SSH config to use: $private_key"
            
            # Update the IdentityFile line
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS sed
                sed -i '' "/Host $github_host/,/^Host / s|IdentityFile.*|IdentityFile $private_key|" "$ssh_config"
            else
                # GNU sed
                sed -i "/Host $github_host/,/^Host / s|IdentityFile.*|IdentityFile $private_key|" "$ssh_config"
            fi
        fi
    else
        # Add new GitHub configuration
        log_info "Adding GitHub SSH configuration"
        
        cat >> "$ssh_config" <<-SSHEOF
		
		# Forge SSH configuration for GitHub
		# Key: $(basename "$private_key")
		# Generated: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)
		Host $github_host
		    HostName $github_host
		    User git
		    IdentityFile $private_key
		    IdentitiesOnly yes
		    AddKeysToAgent yes
		    StrictHostKeyChecking accept-new
		SSHEOF
        
        # Add macOS-specific keychain option
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # Check macOS version (10.x and later support UseKeychain)
            if sw_vers -productVersion 2>/dev/null | grep -qE "^1[0-9]\."; then
                echo "    UseKeychain yes" >> "$ssh_config"
            fi
        fi
        
        chmod 600 "$ssh_config"
        log_success "GitHub SSH configuration added"
    fi
    
    # 4. Verify configuration
    log_info "Verifying SSH configuration"
    
    # Test that the key is accessible
    if ssh-add -l | grep -q "$fingerprint"; then
        log_success "SSH key is loaded and accessible"
    else
        log_warning "SSH key may not be properly loaded"
    fi
    
    log_success "Git SSH configuration complete"
    log_info "Configuration file: $ssh_config"
    log_info "Test connection: ssh -T git@$github_host"
    
    return 0
}

# Ensure GitHub server keys are in known_hosts
# Arguments:
#   $1 - (optional) GitHub hostname (default: github.com)
#   $2 - (optional) Force refresh (true/false, default: false)
# Returns:
#   0 - Success
#   1 - Failed to add known_hosts
#
# Features:
#   - Creates ~/.ssh/known_hosts if doesn't exist
#   - Checks for existing GitHub entries (avoids duplicates)
#   - Fetches GitHub SSH keys using ssh-keyscan
#   - Fallback: Uses GitHub's documented public keys
#   - Supports force refresh (remove old + add new)
#   - Verifies file permissions (644)
ensure_github_known_hosts() {
    local github_host="${1:-github.com}"
    local force_refresh="${2:-false}"
    
    log_step "Ensuring GitHub server keys in known_hosts"
    
    local known_hosts="${HOME}/.ssh/known_hosts"
    
    # Ensure .ssh directory exists
    if [[ ! -d "${HOME}/.ssh" ]]; then
        mkdir -p "${HOME}/.ssh"
        chmod 700 "${HOME}/.ssh"
    fi
    
    # Create known_hosts if doesn't exist
    if [[ ! -f "$known_hosts" ]]; then
        touch "$known_hosts"
        chmod 644 "$known_hosts"
        log_info "Created known_hosts file: $known_hosts"
    fi
    
    # Check if GitHub keys already exist
    if [[ "$force_refresh" != "true" ]] && grep -q "^${github_host}" "$known_hosts"; then
        log_info "GitHub host keys already in known_hosts"
        
        # Count how many keys exist
        local key_count
        key_count=$(grep -c "^${github_host}" "$known_hosts")
        log_debug "Found $key_count existing GitHub host key(s)"
        
        return 0
    fi
    
    # Remove old GitHub keys if force refresh
    if [[ "$force_refresh" == "true" ]]; then
        log_info "Removing old GitHub host keys"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed
            sed -i '' "/^${github_host}/d" "$known_hosts"
        else
            # GNU sed
            sed -i "/^${github_host}/d" "$known_hosts"
        fi
    fi
    
    # Fetch GitHub's current host keys
    log_info "Fetching GitHub SSH host keys"
    
    # GitHub publishes their SSH keys at https://api.github.com/meta
    # But we can also use ssh-keyscan for reliability
    local temp_keys
    temp_keys=$(mktemp)
    
    # Try to fetch keys using ssh-keyscan
    if ssh-keyscan -H "$github_host" 2>/dev/null > "$temp_keys"; then
        local keys_fetched
        keys_fetched=$(wc -l < "$temp_keys" | tr -d ' ')
        
        if [[ "$keys_fetched" -gt 0 ]]; then
            log_success "Fetched $keys_fetched host key(s) from GitHub"
            
            # Add keys to known_hosts (avoiding duplicates)
            while IFS= read -r key_line; do
                # Check if this exact key already exists
                if ! grep -Fxq "$key_line" "$known_hosts"; then
                    echo "$key_line" >> "$known_hosts"
                    log_debug "Added hashed host key: $(echo "$key_line" | awk '{print $2}')"
                else
                    log_debug "Key already exists, skipping"
                fi
            done < "$temp_keys"
            
            rm -f "$temp_keys"
            log_success "GitHub host keys added to known_hosts"
            return 0
        else
            log_warning "No keys fetched from ssh-keyscan"
        fi
    else
        log_warning "ssh-keyscan failed, trying alternative method"
    fi
    
    # Fallback: Add GitHub's documented public keys manually
    # Source: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
    log_info "Adding GitHub's documented SSH keys"
    
    local github_keys=(
        "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
        "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
        "github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
    )
    
    local added_count=0
    for key_line in "${github_keys[@]}"; do
        # Check if key already exists (exact match)
        if ! grep -Fxq "$key_line" "$known_hosts"; then
            echo "$key_line" >> "$known_hosts"
            ((added_count++))
            log_debug "Added: $(echo "$key_line" | awk '{print $2}')"
        else
            log_debug "Key already exists: $(echo "$key_line" | awk '{print $2}')"
        fi
    done
    
    if [[ $added_count -gt 0 ]]; then
        log_success "Added $added_count GitHub host key(s) to known_hosts"
    else
        log_info "All GitHub host keys already present"
    fi
    
    # Verify known_hosts permissions
    chmod 644 "$known_hosts"
    
    log_success "GitHub known_hosts configuration complete"
    log_info "Known hosts file: $known_hosts"
    
    rm -f "$temp_keys" 2>/dev/null
    
    return 0
}

################################################################################
# Complete SSH Environment Setup
################################################################################

# Complete SSH setup for Git operations (all-in-one)
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - (optional) Key type: ed25519 or rsa (default: ed25519)
#   $6 - (optional) GitHub hostname (default: github.com)
#   $7 - (optional) Overwrite existing key (true/false, default: false)
#   $8 - (optional) Push to SSM after generation (true/false, default: false)
#   $9 - (optional) AWS region (for SSM push)
# Output: JSON with configuration details
# Returns:
#   0 - Success
#   1 - Setup failed
#
# Workflow:
#   LOCAL-ONLY (default, push_to_ssm=false):
#     1. Generate SSH key in ~/.ssh with Forge naming
#     2. Configure Git and keychain
#     3. Add GitHub to known_hosts
#     4. SKIP SSM push (local development workflow)
#
#   LOCAL+SSM (opt-in, push_to_ssm=true):
#     1. Generate SSH key in ~/.ssh with Forge naming
#     2. Configure Git and keychain
#     3. Add GitHub to known_hosts
#     4. Push key to AWS SSM Parameter Store (team sharing/backup)
#
# Example:
#   # Local-only (default)
#   setup_complete_git_ssh_environment "sanofi" "cronus" "dev" "video-calling-agent"
#
#   # Local + SSM backup
#   setup_complete_git_ssh_environment "sanofi" "cronus" "dev" "video-calling-agent" \
#       "ed25519" "github.com" "false" "true" "eu-central-1"
setup_complete_git_ssh_environment() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local key_type="${5:-ed25519}"
    local github_host="${6:-github.com}"
    local overwrite="${7:-false}"
    local push_to_ssm="${8:-${SSH_PUSH_TO_SSM_DEFAULT}}"
    local aws_region="${9:-}"
    
    log_step "Complete SSH setup for ${customer}/${project}/${environment}/${service_name}"
    
    # Validate SSM push requirements BEFORE generating key
    if [[ "$push_to_ssm" == "true" ]]; then
        log_info "SSM push requested - validating parameters"
        
        if [[ -z "$customer" ]] || [[ -z "$project" ]] || [[ -z "$environment" ]] || [[ -z "$service_name" ]]; then
            log_error "SSM push requires customer, project, environment, and service_name to be provided"
            log_error "Missing parameters - cannot proceed with SSM push"
            return 1
        fi
        
        if [[ -z "$aws_region" ]]; then
            log_info "No AWS region provided, auto-detecting..."
            aws_region=$(get_aws_region) || {
                log_error "Failed to detect AWS region for SSM push"
                log_error "Please provide region explicitly or configure AWS CLI"
                return 1
            }
            log_info "Detected AWS region: $aws_region"
        fi
        
        log_success "SSM push parameters validated"
    else
        log_info "SSM push disabled (local-only workflow)"
    fi
    
    # Step 1: Generate and install SSH key
    log_info "Step 1/4: Generating SSH key"
    local key_info
    key_info=$(generate_and_install_ssh_key \
        "$customer" \
        "$project" \
        "$environment" \
        "$service_name" \
        "$key_type" \
        "$overwrite") || {
        log_error "Failed to generate SSH key"
        return 1
    }
    
    local private_key_path
    local public_key_path
    local fingerprint
    local key_name
    
    private_key_path=$(echo "$key_info" | jq -r '.private_key_path')
    public_key_path=$(echo "$key_info" | jq -r '.public_key_path')
    fingerprint=$(echo "$key_info" | jq -r '.fingerprint')
    key_name=$(echo "$key_info" | jq -r '.key_name')
    
    log_success "SSH key generated: $(basename "$private_key_path")"
    
    # Step 2: Configure Git to use the key
    log_info "Step 2/4: Configuring Git and keychain"
    if configure_git_to_use_ssh_key "$private_key_path" "$github_host"; then
        log_success "Git configured successfully"
    else
        log_error "Failed to configure Git"
        return 1
    fi
    
    # Step 3: Ensure GitHub known_hosts
    log_info "Step 3/4: Adding GitHub to known_hosts"
    if ensure_github_known_hosts "$github_host"; then
        log_success "GitHub added to known_hosts"
    else
        log_error "Failed to add GitHub to known_hosts"
        return 1
    fi
    
    # Step 4: Optionally push to SSM
    local ssm_pushed=false
    if [[ "$push_to_ssm" == "true" ]]; then
        log_info "Step 4/4: Pushing SSH key to AWS SSM"
        
        if push_ssh_key_to_ssm \
            "$customer" \
            "$project" \
            "$environment" \
            "$service_name" \
            "$private_key_path" \
            "$public_key_path" \
            "$aws_region"; then
            log_success "SSH key pushed to SSM"
            ssm_pushed=true
        else
            log_warning "Failed to push SSH key to SSM (non-critical)"
            log_warning "Local key is still configured and usable"
        fi
    else
        log_info "Step 4/4: Skipping SSM push (local-only workflow)"
    fi
    
    # Print summary
    log_success "Complete SSH setup finished successfully!"
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
    log_info "SSH Key Configuration Summary"
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Customer:     $customer"
    log_info "Project:      $project"
    log_info "Environment:  $environment"
    log_info "Service:      $service_name"
    log_info "Key Name:     $key_name"
    log_info "Key Type:     $key_type"
    log_info "Fingerprint:  $fingerprint"
    log_info "Private Key:  $private_key_path"
    log_info "Public Key:   $public_key_path"
    log_info "SSH Config:   ${HOME}/.ssh/config"
    log_info "Known Hosts:  ${HOME}/.ssh/known_hosts"
    if [[ "$ssm_pushed" == "true" ]]; then
        log_info "SSM Backup:   ✓ Pushed to AWS SSM Parameter Store"
    else
        log_info "SSM Backup:   ✗ Local-only (not pushed to SSM)"
    fi
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    log_info "Next steps:"
    log_info "1. Add public key to GitHub:"
    log_info "   cat $public_key_path"
    log_info "2. Test SSH connection:"
    log_info "   ssh -T git@$github_host"
    log_info "3. Clone a repository:"
    log_info "   git clone git@$github_host:org/repo.git"
    
    # Return JSON
    jq -n \
        --arg private_key "$private_key_path" \
        --arg public_key "$public_key_path" \
        --arg fingerprint "$fingerprint" \
        --arg key_name "$key_name" \
        --arg ssh_config "${HOME}/.ssh/config" \
        --arg known_hosts "${HOME}/.ssh/known_hosts" \
        --argjson pushed_to_ssm "$([[ "$ssm_pushed" == "true" ]] && echo "true" || echo "false")" \
        '{
            private_key_path: $private_key,
            public_key_path: $public_key,
            fingerprint: $fingerprint,
            key_name: $key_name,
            ssh_config: $ssh_config,
            known_hosts: $known_hosts,
            pushed_to_ssm: $pushed_to_ssm
        }'
    
    return 0
}

################################################################################
# GitHub Integration Helpers
################################################################################

# Get GitHub SSH public key for deployment
# Arguments:
#   $1 - Public key file path
# Output: Public key content (suitable for GitHub deploy keys)
# Returns:
#   0 - Success
#   1 - Failed
get_github_deploy_key() {
    local public_key_file="$1"
    
    if [[ ! -f "$public_key_file" ]]; then
        log_error "Public key file not found: $public_key_file"
        return 1
    fi
    
    cat "$public_key_file"
}

# Test GitHub SSH connection
# Arguments:
#   $1 - (optional) GitHub hostname (default: github.com)
# Returns:
#   0 - Connection successful
#   1 - Connection failed
test_github_ssh_connection() {
    local github_host="${1:-github.com}"
    
    log_info "Testing GitHub SSH connection to $github_host"
    
    if ssh -T "git@${github_host}" 2>&1 | grep -q "successfully authenticated"; then
        log_success "GitHub SSH connection successful"
        return 0
    else
        log_error "GitHub SSH connection failed"
        log_error "Ensure the public key is added as a deploy key to the repository"
        return 1
    fi
}

################################################################################
# Key Rotation
################################################################################

# Rotate SSH key (generate new, push to SSM, mark old as deprecated)
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment name
#   $4 - Service name
#   $5 - Output directory
#   $6 - (optional) AWS region (default: auto-detect)
# Returns:
#   0 - Success
#   1 - Rotation failed
rotate_ssh_key() {
    local customer="$1"
    local project="$2"
    local environment="$3"
    local service_name="$4"
    local output_dir="$5"
    local aws_region="${6:-}"
    
    log_step "Rotating SSH key for ${customer}/${project}/${environment}/${service_name}"
    
    # Force regeneration
    provision_ssh_key "$customer" "$project" "$environment" "$service_name" "$output_dir" "$aws_region" "true"
}

################################################################################
# Export Functions
################################################################################

export -f generate_ssh_key
export -f ssh_key_exists_in_ssm
export -f push_ssh_key_to_ssm
export -f pull_ssh_key_from_ssm
export -f get_ssh_key_metadata_from_ssm
export -f provision_ssh_key
export -f add_ssh_key_to_agent
export -f configure_ssh_for_github
export -f get_github_deploy_key
export -f test_github_ssh_connection
export -f rotate_ssh_key

log_info "Forge SSH Operations Library loaded (v1.0.0)"
