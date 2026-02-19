#!/usr/bin/env bash
# ==============================================================================
# Forge SSM Operations Library
# ==============================================================================
# Version: 1.0.0
# Description: AWS Systems Manager Parameter Store operations for Forge Platform
#
# This library provides high-level operations for managing secrets in AWS SSM,
# including YAML push/pull, section management, and bulk operations.
#
# Dependencies:
#   - forge-core.sh (logging, validation, utilities)
#   - forge-patterns.sh (naming conventions)
#   - forge-aws-discovery.sh (SSM low-level operations)
#   - aws (AWS CLI v2)
#   - jq (JSON processing)
#   - yq (YAML processing)
#
# ==============================================================================

# Version
FORGE_SSM_OPERATIONS_VERSION="1.0.0"

# ==============================================================================
# LIBRARY DEPENDENCIES
# ==============================================================================

# Get the directory where this script is located
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ ! -f "$LIB_DIR/forge-core.sh" ]]; then
  echo "ERROR: forge-core.sh not found. Cannot continue." >&2
  exit 1
fi
source "$LIB_DIR/forge-core.sh"

if [[ ! -f "$LIB_DIR/forge-patterns.sh" ]]; then
  log_error "forge-patterns.sh not found in: $LIB_DIR"
  exit 1
fi
source "$LIB_DIR/forge-patterns.sh"

if [[ ! -f "$LIB_DIR/forge-aws-discovery.sh" ]]; then
  log_error "forge-aws-discovery.sh not found in: $LIB_DIR"
  exit 1
fi
source "$LIB_DIR/forge-aws-discovery.sh"

# Validate required commands
validate_required_commands aws jq yq

# ==============================================================================
# YAML PARSING TO SSM FORMAT
# ==============================================================================

# parse_yaml_to_ssm_format
# Parses YAML file and converts to SSM path/value pairs
#
# Arguments:
#   $1 - YAML file path
#   $2 - Customer name
#   $3 - Project name
#   $4 - Environment
#   $5 - Service name
#
# Output:
#   JSON array: [{"path": "/customer/project/env/service/section/key", "value": "val"}, ...]
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   params=$(parse_yaml_to_ssm_format "vault.yaml" "customer" "project" "dev" "test-1")
#
parse_yaml_to_ssm_format() {
  local yaml_file="$1"
  local customer="$2"
  local project="$3"
  local environment="$4"
  local service="$5"
  
  validate_file_exists "$yaml_file" "YAML file"
  validate_required_vars customer project environment service
  
  log_debug "Parsing YAML file: $yaml_file"
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$customer" "$project" "$environment" "$service")
  
  # Parse YAML and build parameter list
  local params="[]"
  
  # Get all sections (top-level keys)
  local sections
  sections=$(yq eval 'keys | .[]' "$yaml_file")
  
  while IFS= read -r section; do
    [[ -z "$section" ]] && continue
    
    log_debug "Processing section: $section"
    
    # Get all keys in this section
    local keys
    keys=$(yq eval ".${section} | keys | .[]" "$yaml_file" 2>/dev/null || echo "")
    
    if [[ -z "$keys" ]]; then
      log_debug "Section $section is empty or not a map, skipping"
      continue
    fi
    
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      
      # Get value for this key
      local value
      value=$(yq eval ".${section}.${key}" "$yaml_file")
      
      # Build SSM path
      local ssm_path="${base_path}/${section}/${key}"
      
      # Add to params array
      params=$(echo "$params" | jq -c ". + [{\"path\": \"$ssm_path\", \"value\": \"$value\"}]")
      
    done <<< "$keys"
    
  done <<< "$sections"
  
  echo "$params"
}

# ==============================================================================
# PUSH YAML TO SSM
# ==============================================================================

# push_yaml_to_ssm
# Pushes YAML configuration to AWS SSM Parameter Store
#
# Arguments:
#   $1 - YAML file path
#   $2 - Customer name
#   $3 - Project name
#   $4 - Environment
#   $5 - Service name
#   $6 - (optional) Dry run (true/false, default: false)
#   $7 - (optional) Parameter type (String|SecureString, default: SecureString)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   push_yaml_to_ssm "vault.yaml" "customer" "project" "dev" "test-1" "false"
#
push_yaml_to_ssm() {
  local yaml_file="$1"
  local customer="$2"
  local project="$3"
  local environment="$4"
  local service="$5"
  local dry_run="${6:-false}"
  local param_type="${7:-SecureString}"
  
  log_step "Pushing YAML to SSM Parameter Store"
  
  log_info "YAML file: $yaml_file"
  log_info "Target: ${customer}/${project}/${environment}/${service}"
  
  if [[ "$dry_run" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Auto-detect KMS key for SecureString parameters
  local kms_key_id=""
  if [[ "$param_type" == "SecureString" ]]; then
    # Try to find KMS key with purpose "ssm"
    local kms_alias_ssm="alias/${customer}/${project}/${environment}/${service}/ssm"
    
    log_debug "Looking for KMS key: $kms_alias_ssm"
    if kms_key_exists "$kms_alias_ssm" 2>/dev/null; then
      kms_key_id="$kms_alias_ssm"
      log_info "Using KMS key: $kms_key_id (purpose: ssm)"
    else
      log_warning "No KMS key found for service (purpose: ssm)"
      log_warning "Using default AWS managed key (aws/ssm)"
    fi
  fi
  
  # Parse YAML to SSM format
  local params
  params=$(parse_yaml_to_ssm_format "$yaml_file" "$customer" "$project" "$environment" "$service")
  
  local param_count
  param_count=$(echo "$params" | jq 'length')
  
  log_info "Found $param_count parameters to push"
  
  if [[ "$param_count" -eq 0 ]]; then
    log_warning "No parameters found in YAML file"
    return 0
  fi
  
  # Push each parameter
  local pushed=0
  local failed=0
  
  while IFS= read -r param; do
    local path
    local value
    
    path=$(echo "$param" | jq -r '.path')
    value=$(echo "$param" | jq -r '.value')
    
    if [[ "$dry_run" == "true" ]]; then
      log_dry_run "Would push: $path"
      ((pushed++))
    else
      # Pass KMS key ID to put_ssm_parameter
      local region
      region=$(get_aws_region)
      
      if put_ssm_parameter "$path" "$value" "$param_type" "$region" "true" "$kms_key_id"; then
        ((pushed++))
      else
        ((failed++))
      fi
    fi
  done < <(echo "$params" | jq -c '.[]')
  
  log_info "Parameters pushed: $pushed, failed: $failed"
  
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
}

# ==============================================================================
# PULL SSM TO YAML
# ==============================================================================

# pull_ssm_to_yaml
# Pulls parameters from SSM and generates YAML file
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Output YAML file path
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   pull_ssm_to_yaml "customer" "project" "dev" "test-1" "/tmp/customer-project-dev-test-1.yaml"
#
pull_ssm_to_yaml() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service="$4"
  local output_file="$5"
  
  validate_required_vars customer project environment service output_file
  
  log_step "Pulling SSM parameters to YAML"
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$customer" "$project" "$environment" "$service")
  
  log_info "Base path: $base_path"
  log_info "Output file: $output_file"
  
  # List all parameters under base path
  local params
  params=$(list_ssm_parameters_by_path "$base_path" "true" "true")
  
  local param_count
  param_count=$(echo "$params" | jq 'length')
  
  log_info "Found $param_count parameters in SSM"
  
  if [[ "$param_count" -eq 0 ]]; then
    log_warning "No parameters found in SSM under: $base_path"
    return 0
  fi
  
  # Group parameters by section
  local sections=()
  local section_data=""
  
  while IFS= read -r param; do
    local name
    local value
    
    name=$(echo "$param" | jq -r '.Name')
    value=$(echo "$param" | jq -r '.Value')
    
    # Extract section and key from path
    # Path format: /customer/project/env/service/section/key
    local relative_path="${name#"${base_path}"/}"
    local section="${relative_path%%/*}"
    local key="${relative_path#*/}"
    
    # Skip if no section/key structure
    if [[ "$section" == "$key" ]]; then
      log_debug "Skipping parameter without section: $name"
      continue
    fi
    
    # Track sections
    if [[ ${#sections[@]} -eq 0 ]] || ! printf '%s\n' "${sections[@]}" | grep -q "^${section}$"; then
      sections+=("$section")
    fi
    
    # Build section data (will be converted to YAML later)
    section_data=$(cat <<EOF
${section_data}
${section}:${key}=${value}
EOF
)
  done < <(echo "$params" | jq -c '.[]')
  
  # Build YAML content
  log_info "Building YAML with ${#sections[@]} sections"
  
  # Initialize YAML file
  echo "# Auto-generated from AWS SSM Parameter Store" > "$output_file"
  echo "# Base path: $base_path" >> "$output_file"
  echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$output_file"
  echo "" >> "$output_file"
  
  # Process each section
  for section in "${sections[@]}"; do
    echo "${section}:" >> "$output_file"
    
    # Get all keys for this section
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      
      # Parse section:key=value
      if [[ "$line" =~ ^${section}:(.+)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"
        
        # Quote value if it contains special YAML characters or starts with *
        case "$value" in
          *:*|*'{'*|*'}'*|*'['*|*']'*|*,*|*\'*|*\"*|*#*|'*'*)
            value="\"${value//\"/\\\"}\""
            ;;
        esac
        
        echo "  ${key}: ${value}" >> "$output_file"
      fi
    done <<< "$section_data"
    
    echo "" >> "$output_file"
  done
  
  log_success "YAML file created: $output_file"
  log_info "Sections: ${sections[*]}"
}

# ==============================================================================
# LIST SSM SECTIONS
# ==============================================================================

# list_ssm_sections
# Lists all sections (first-level subdirectories) under service path
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#
# Output:
#   Section names (one per line)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   sections=$(list_ssm_sections "customer" "project" "dev" "test-1")
#
list_ssm_sections() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service="$4"
  
  validate_required_vars customer project environment service
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$customer" "$project" "$environment" "$service")
  
  log_debug "Listing sections under: $base_path"
  
  # List all parameters
  local params
  params=$(list_ssm_parameters_by_path "$base_path" "true" "false")
  
  # Extract unique sections
  local sections
  sections=$(echo "$params" | jq -r '.[].Name' | while read -r name; do
    # Extract section from path: /customer/project/env/service/SECTION/key
    local relative_path="${name#"${base_path}"/}"
    local section="${relative_path%%/*}"
    echo "$section"
  done | sort -u)
  
  echo "$sections"
}

# ==============================================================================
# DELETE SSM SECTION
# ==============================================================================

# delete_ssm_section
# Deletes all parameters in a specific section
#
# Arguments:
#   $1 - Customer name
#   $2 - Project name
#   $3 - Environment
#   $4 - Service name
#   $5 - Section name
#   $6 - (optional) Dry run (true/false, default: false)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Example:
#   delete_ssm_section "customer" "project" "dev" "test-1" "app" "false"
#
delete_ssm_section() {
  local customer="$1"
  local project="$2"
  local environment="$3"
  local service="$4"
  local section="$5"
  local dry_run="${6:-false}"
  
  validate_required_vars customer project environment service section
  
  log_step "Deleting SSM section: $section"
  
  if [[ "$dry_run" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$customer" "$project" "$environment" "$service")
  
  local section_path="${base_path}/${section}"
  
  log_info "Section path: $section_path"
  
  # List all parameters in this section
  local params
  params=$(list_ssm_parameters_by_path "$section_path" "true" "false")
  
  local param_count
  param_count=$(echo "$params" | jq 'length')
  
  log_info "Found $param_count parameters to delete"
  
  if [[ "$param_count" -eq 0 ]]; then
    log_warning "No parameters found in section: $section"
    return 0
  fi
  
  # Delete each parameter
  local deleted=0
  local failed=0
  
  while IFS= read -r param_name; do
    [[ -z "$param_name" ]] && continue
    
    if [[ "$dry_run" == "true" ]]; then
      log_dry_run "Would delete: $param_name"
      ((deleted++))
    else
      if delete_ssm_parameter "$param_name"; then
        ((deleted++))
      else
        ((failed++))
      fi
    fi
  done < <(echo "$params" | jq -r '.[].Name')
  
  log_info "Parameters deleted: $deleted, failed: $failed"
  
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
}

# ==============================================================================
# SYNC YAML TO SSM (DETECT CHANGES)
# ==============================================================================

# sync_yaml_to_ssm
# Syncs YAML to SSM by detecting differences and updating only changed values
#
# Arguments:
#   $1 - YAML file path
#   $2 - Customer name
#   $3 - Project name
#   $4 - Environment
#   $5 - Service name
#   $6 - (optional) Dry run (true/false, default: false)
#   $7 - (optional) Parameter type (String|SecureString, default: SecureString)
#
# Returns:
#   0 - Success
#   1 - Error
#
# Output:
#   Reports added, updated, unchanged, and orphaned parameters
#
# Example:
#   sync_yaml_to_ssm "vault.yaml" "customer" "project" "dev" "test-1" "false"
#
sync_yaml_to_ssm() {
  local yaml_file="$1"
  local customer="$2"
  local project="$3"
  local environment="$4"
  local service="$5"
  local dry_run="${6:-false}"
  local param_type="${7:-SecureString}"
  
  log_step "Syncing YAML to SSM Parameter Store"
  
  if [[ "$dry_run" == "true" ]]; then
    log_warning "DRY-RUN MODE: No changes will be made"
  fi
  
  # Get base SSM path
  local base_path
  base_path=$(get_ssm_base_path "$customer" "$project" "$environment" "$service")
  
  # Parse YAML to get desired state
  local yaml_params
  yaml_params=$(parse_yaml_to_ssm_format "$yaml_file" "$customer" "$project" "$environment" "$service")
  
  # Get current SSM state
  local ssm_params
  ssm_params=$(list_ssm_parameters_by_path "$base_path" "true" "true")
  
  # Track changes
  local added=0
  local updated=0
  local unchanged=0
  local failed=0
  
  # Process each YAML parameter
  while IFS= read -r yaml_param; do
    local path
    local yaml_value
    
    path=$(echo "$yaml_param" | jq -r '.path')
    yaml_value=$(echo "$yaml_param" | jq -r '.value')
    
    # Check if parameter exists in SSM
    local ssm_value
    ssm_value=$(echo "$ssm_params" | jq -r ".[] | select(.Name == \"$path\") | .Value // empty")
    
    if [[ -z "$ssm_value" ]]; then
      # Parameter doesn't exist - ADD
      log_info "[ADD] $path"
      
      if [[ "$dry_run" == "true" ]]; then
        log_dry_run "Would add: $path"
        ((added++))
      else
        if put_ssm_parameter "$path" "$yaml_value" "$param_type"; then
          ((added++))
        else
          ((failed++))
        fi
      fi
      
    elif [[ "$ssm_value" != "$yaml_value" ]]; then
      # Parameter exists but value differs - UPDATE
      log_info "[UPDATE] $path"
      log_debug "  Old: $ssm_value"
      log_debug "  New: $yaml_value"
      
      if [[ "$dry_run" == "true" ]]; then
        log_dry_run "Would update: $path"
        ((updated++))
      else
        if put_ssm_parameter "$path" "$yaml_value" "$param_type"; then
          ((updated++))
        else
          ((failed++))
        fi
      fi
      
    else
      # Parameter exists and value matches - UNCHANGED
      log_debug "[UNCHANGED] $path"
      ((unchanged++))
    fi
    
  done < <(echo "$yaml_params" | jq -c '.[]')
  
  # Detect orphaned parameters (in SSM but not in YAML)
  local orphaned=0
  while IFS= read -r ssm_param; do
    local ssm_path
    ssm_path=$(echo "$ssm_param" | jq -r '.Name')
    
    # Check if this path exists in YAML
    local in_yaml
    in_yaml=$(echo "$yaml_params" | jq -r ".[] | select(.path == \"$ssm_path\") | .path // empty")
    
    if [[ -z "$in_yaml" ]]; then
      log_warning "[ORPHANED] $ssm_path (exists in SSM but not in YAML)"
      ((orphaned++))
    fi
  done < <(echo "$ssm_params" | jq -c '.[]')
  
  # Summary
  log_info "=== Sync Summary ==="
  log_info "Added: $added"
  log_info "Updated: $updated"
  log_info "Unchanged: $unchanged"
  log_info "Failed: $failed"
  if [[ $orphaned -gt 0 ]]; then
    log_warning "Orphaned (in SSM, not in YAML): $orphaned"
    log_warning "Run delete_ssm_section to clean up orphaned parameters"
  fi
  
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
}

# ==============================================================================
# EXPORTS
# ==============================================================================

export -f parse_yaml_to_ssm_format
export -f push_yaml_to_ssm
export -f pull_ssm_to_yaml
export -f list_ssm_sections
export -f delete_ssm_section
export -f sync_yaml_to_ssm

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "forge-ssm-operations.sh loaded (v${FORGE_SSM_OPERATIONS_VERSION})"
