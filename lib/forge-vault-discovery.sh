#!/usr/bin/env bash

################################################################################
# Forge Vault Discovery Library
################################################################################
# Version: 1.0.0
# Description: Vault connection management and secret operations with intelligent
#              execution context detection (in-cluster vs local)
#
# Features:
# - Execution mode detection (IN_CLUSTER vs LOCAL)
# - 4-tier CA certificate priority (mounted → provided → extracted → legacy)
# - Automatic connection setup with fallback mechanisms
# - Kubernetes and Token authentication
# - Port-forwarding management (LOCAL mode)
# - AWS SSM token retrieval
# - KV v2 aware secret operations
# - Integration with forge-core, forge-patterns, and forge-k8s-discovery
#
# Dependencies:
# - forge-core.sh
# - forge-patterns.sh
# - forge-k8s-discovery.sh
# - vault CLI
# - kubectl
# - curl
# - aws CLI (for SSM token retrieval)
# - jq
#
# Author: Moai Forge Team
# Created: 2026-02-06
################################################################################

# Prevent double-loading
if [[ -n "${FORGE_VAULT_DISCOVERY_LOADED:-}" ]]; then
	return 0
fi
FORGE_VAULT_DISCOVERY_LOADED=1

################################################################################
# Dependencies
################################################################################

# Determine script directory
FORGE_VAULT_DISCOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -z "${FORGE_CORE_LOADED:-}" ]]; then
	# shellcheck source=forge-core.sh
	source "${FORGE_VAULT_DISCOVERY_DIR}/forge-core.sh"
fi

if [[ -z "${FORGE_PATTERNS_LOADED:-}" ]]; then
	# shellcheck source=forge-patterns.sh
	source "${FORGE_VAULT_DISCOVERY_DIR}/forge-patterns.sh"
fi

if [[ -z "${FORGE_K8S_DISCOVERY_LOADED:-}" ]]; then
	# shellcheck source=forge-k8s-discovery.sh
	source "${FORGE_VAULT_DISCOVERY_DIR}/forge-k8s-discovery.sh"
fi

if [[ -z "${FORGE_AWS_DISCOVERY_LOADED:-}" ]]; then
	# shellcheck source=forge-aws-discovery.sh
	source "${FORGE_VAULT_DISCOVERY_DIR}/forge-aws-discovery.sh"
fi

# Validate required commands
validate_required_commands vault kubectl curl jq

################################################################################
# Constants
################################################################################

readonly VAULT_DEFAULT_NAMESPACE="vault"
readonly VAULT_DEFAULT_SERVICE="vault"
readonly VAULT_DEFAULT_PORT="8200"
readonly VAULT_DEFAULT_SSM_TOKEN_PATH="/forge/shared/middleware/vault/token"
readonly VAULT_TRUST_MANAGER_BUNDLE_NAME="vault-ca-bundle"
readonly VAULT_CERT_MANAGER_SECRET_NAME="vault-ca-key-pair"
readonly VAULT_CONNECTION_TEST_RETRIES=3
readonly VAULT_CONNECTION_TEST_RETRY_DELAY=2
readonly VAULT_PORT_FORWARD_WAIT_TIMEOUT=15

################################################################################
# Execution Mode Detection
################################################################################

# Detect Vault execution mode (IN_CLUSTER vs LOCAL)
# Uses forge-k8s-discovery for Kubernetes detection
# Output: "IN_CLUSTER" or "LOCAL" to stdout
detect_vault_execution_mode() {
	local k8s_mode
	k8s_mode=$(detect_kubernetes_context)
	
	if [[ "$k8s_mode" == "IN_CLUSTER" ]]; then
		echo "IN_CLUSTER"
	else
		echo "LOCAL"
	fi
}

# Alias for naming consistency with other libraries
get_vault_execution_mode() {
	detect_vault_execution_mode
}

################################################################################
# Certificate Management (4-Tier Priority)
################################################################################

# Get Vault CA certificate using 4-level priority mechanism
# Priority:
#   1. Mounted certificate (trust-manager in pod): /vault/tls/ca.crt
#   2. Provided via VAULT_CACERT environment variable
#   3. Extracted from trust-manager ConfigMap: vault-ca-bundle
#   4. Legacy: cert-manager Secret vault-ca-key-pair
#
# Arguments:
#   $1 - (optional) Namespace for ConfigMap extraction (default: vault)
#
# Output: JSON object with certificate_path and source
# Returns:
#   0 - Certificate found
#   1 - No certificate found (will use --skip-tls-verify)
get_vault_certificate() {
	local namespace="${1:-$VAULT_DEFAULT_NAMESPACE}"
	
	log_info "Searching for Vault CA certificate (4-tier priority)..."
	
	# Priority 1: Mounted certificate (trust-manager in pod)
	local mounted_cert="/vault/tls/ca.crt"
	if [[ -f "$mounted_cert" && -r "$mounted_cert" ]]; then
		log_success "Using mounted CA certificate: $mounted_cert"
		log_debug "Source: trust-manager ConfigMap mounted in pod"
		
		jq -n \
			--arg cert_path "$mounted_cert" \
			--arg source "mounted" \
			'{certificate_path: $cert_path, source: $source}'
		return 0
	fi
	
	# Priority 2: Provided via environment variable
	if [[ -n "${VAULT_CACERT:-}" && -f "$VAULT_CACERT" && -r "$VAULT_CACERT" ]]; then
		log_success "Using provided CA certificate: $VAULT_CACERT"
		log_debug "Source: VAULT_CACERT environment variable"
		
		jq -n \
			--arg cert_path "$VAULT_CACERT" \
			--arg source "provided" \
			'{certificate_path: $cert_path, source: $source}'
		return 0
	fi
	
	# Priority 3: Extract from trust-manager ConfigMap
	if command -v kubectl &>/dev/null; then
		log_debug "Attempting to extract certificate from trust-manager ConfigMap..."
		
		# Try current namespace first, then vault namespace
		for ns in "$namespace" "$VAULT_DEFAULT_NAMESPACE"; do
			log_debug "Checking ConfigMap $VAULT_TRUST_MANAGER_BUNDLE_NAME in namespace $ns..."
			
			if execute_kubectl get configmap "$VAULT_TRUST_MANAGER_BUNDLE_NAME" -n "$ns" --request-timeout=5s &>/dev/null; then
				local temp_cert="/tmp/vault-ca-extracted-$$.crt"
				
				if execute_kubectl get configmap "$VAULT_TRUST_MANAGER_BUNDLE_NAME" -n "$ns" \
					--request-timeout=5s -o jsonpath='{.data.ca\.crt}' > "$temp_cert" 2>/dev/null; then
					
					if [[ -s "$temp_cert" ]]; then
						log_success "Extracted CA certificate from trust-manager ConfigMap"
						log_debug "Source: ConfigMap $VAULT_TRUST_MANAGER_BUNDLE_NAME in namespace $ns"
						log_debug "Temporary file: $temp_cert"
						
						jq -n \
							--arg cert_path "$temp_cert" \
							--arg source "extracted" \
							'{certificate_path: $cert_path, source: $source}'
						return 0
					fi
				fi
				
				# Cleanup if extraction failed
				[[ -f "$temp_cert" ]] && rm -f "$temp_cert"
			fi
		done
	fi
	
	# Priority 4: Legacy cert-manager Secret
	if command -v kubectl &>/dev/null; then
		log_debug "Attempting legacy cert-manager Secret extraction..."
		
		if execute_kubectl get secret "$VAULT_CERT_MANAGER_SECRET_NAME" -n "$VAULT_DEFAULT_NAMESPACE" --request-timeout=5s &>/dev/null; then
			local temp_cert="/tmp/vault-ca-legacy-$$.crt"
			
			if execute_kubectl get secret "$VAULT_CERT_MANAGER_SECRET_NAME" -n "$VAULT_DEFAULT_NAMESPACE" \
				--request-timeout=5s -o jsonpath='{.data.ca\.crt}' | base64 -d > "$temp_cert" 2>/dev/null; then
				
				if [[ -s "$temp_cert" ]]; then
					log_success "Extracted CA certificate from legacy cert-manager Secret"
					log_debug "Source: Secret $VAULT_CERT_MANAGER_SECRET_NAME in namespace $VAULT_DEFAULT_NAMESPACE"
					log_warning "Using legacy cert-manager Secret. Consider migrating to trust-manager."
					
					jq -n \
						--arg cert_path "$temp_cert" \
						--arg source "legacy" \
						'{certificate_path: $cert_path, source: $source}'
					return 0
				fi
			fi
			
			# Cleanup if extraction failed
			[[ -f "$temp_cert" ]] && rm -f "$temp_cert"
		fi
	fi
	
	# No certificate found
	log_error "No Vault CA certificate found using any method:"
	log_error "  1. Mounted: $mounted_cert - not found"
	log_error "  2. Provided: VAULT_CACERT - not specified or invalid"
	log_error "  3. trust-manager ConfigMap: $VAULT_TRUST_MANAGER_BUNDLE_NAME - not found"
	log_error "  4. Legacy Secret: $VAULT_CERT_MANAGER_SECRET_NAME - not found"
	log_warning "TLS verification will be DISABLED - NOT RECOMMENDED for production!"
	
	jq -n \
		--arg cert_path "" \
		--arg source "none" \
		'{certificate_path: $cert_path, source: $source}'
	return 1
}

################################################################################
# Connection Testing
################################################################################

# Test connectivity to Vault server using health endpoint
# Arguments:
#   $1 - (optional) Vault address (defaults to $VAULT_ADDR)
#   $2 - (optional) CA certificate path
#
# Returns:
#   0 - Connection successful
#   1 - Connection failed after retries
test_vault_connection() {
	local vault_addr="${1:-${VAULT_ADDR:-}}"
	local ca_cert="${2:-}"
	local retry_count=0
	
	if [[ -z "$vault_addr" ]]; then
		log_error "Vault address not provided and VAULT_ADDR not set"
		return 1
	fi
	
	log_info "Testing Vault connection: $vault_addr"
	
	# Build curl command
	local curl_cmd=(curl -sf --connect-timeout 5 --max-time 10)
	
	# Check if TLS verification should be skipped
	if [[ "${VAULT_SKIP_VERIFY:-0}" == "1" ]]; then
		curl_cmd+=(--insecure)
		log_debug "TLS verification disabled (VAULT_SKIP_VERIFY=1)"
	elif [[ -n "$ca_cert" && -f "$ca_cert" ]]; then
		curl_cmd+=(--cacert "$ca_cert")
		log_debug "Using CA certificate: $ca_cert"
	else
		curl_cmd+=(--insecure)
		log_warning "TLS verification disabled (no CA certificate available)"
	fi
	
	# Health check endpoint
	curl_cmd+=("$vault_addr/v1/sys/health")
	
	# Retry loop
	while [[ $retry_count -lt $VAULT_CONNECTION_TEST_RETRIES ]]; do
		log_debug "Connection attempt $((retry_count + 1))/$VAULT_CONNECTION_TEST_RETRIES..."
		
		if "${curl_cmd[@]}" &>/dev/null; then
			log_success "Vault connection successful"
			return 0
		fi
		
		((retry_count++))
		
		if [[ $retry_count -lt $VAULT_CONNECTION_TEST_RETRIES ]]; then
			log_debug "Connection failed, retrying in ${VAULT_CONNECTION_TEST_RETRY_DELAY}s..."
			sleep "$VAULT_CONNECTION_TEST_RETRY_DELAY"
		fi
	done
	
	log_error "Vault connection failed after $VAULT_CONNECTION_TEST_RETRIES attempts"
	return 1
}

################################################################################
# Port-Forwarding Management (LOCAL mode)
################################################################################

# Setup kubectl port-forward to Vault service
# Arguments:
#   $1 - (optional) Namespace (default: vault)
#   $2 - (optional) Service name (default: vault)
#   $3 - (optional) Port (default: 8200)
#
# Sets:
#   VAULT_PORT_FORWARD_PID - PID of port-forward process
#   VAULT_LOCAL_PORT - Local port number
#   VAULT_ADDR - Vault address (https://localhost:PORT)
#
# Returns:
#   0 - Port-forward established
#   1 - Failed to establish port-forward
setup_vault_port_forward() {
	local namespace="${1:-$VAULT_DEFAULT_NAMESPACE}"
	local service="${2:-$VAULT_DEFAULT_SERVICE}"
	local port="${3:-$VAULT_DEFAULT_PORT}"
	
	log_info "Setting up port-forward to Vault service..."
	log_debug "Service: $service, Namespace: $namespace, Port: $port"
	
	# Check if service exists
	if ! execute_kubectl get service "$service" -n "$namespace" &>/dev/null; then
		log_error "Vault service not found: $service in namespace $namespace"
		return 1
	fi
	
	# Kill existing port-forward if running
	if [[ -n "${VAULT_PORT_FORWARD_PID:-}" ]]; then
		log_debug "Cleaning up existing port-forward (PID: $VAULT_PORT_FORWARD_PID)"
		cleanup_vault_port_forward
	fi
	
	# Start port-forward in background
	log_debug "Starting port-forward: kubectl port-forward -n $namespace svc/$service $port:$port"
	kubectl port-forward -n "$namespace" "svc/$service" "$port:$port" &>/dev/null &
	VAULT_PORT_FORWARD_PID=$!
	
	# Register cleanup trap
	trap cleanup_vault_port_forward EXIT INT TERM
	
	# Wait for port-forward to be ready
	log_debug "Waiting for port-forward to be ready (PID: $VAULT_PORT_FORWARD_PID)..."
	local wait_count=0
	while [[ $wait_count -lt $VAULT_PORT_FORWARD_WAIT_TIMEOUT ]]; do
		if nc -z localhost "$port" &>/dev/null || curl -sf --max-time 1 "http://localhost:$port/v1/sys/health" &>/dev/null; then
			log_success "Port-forward established (PID: $VAULT_PORT_FORWARD_PID)"
			
			# Export environment variables
			export VAULT_LOCAL_PORT="$port"
			export VAULT_ADDR="https://localhost:$port"
			
			# Skip TLS verification in LOCAL mode (cert is for vault.svc.cluster.local, not localhost)
			export VAULT_SKIP_VERIFY=1
			log_debug "TLS verification disabled (LOCAL mode with port-forward)"
			
			return 0
		fi
		
		# Check if process is still running
		if ! kill -0 "$VAULT_PORT_FORWARD_PID" 2>/dev/null; then
			log_error "Port-forward process died unexpectedly"
			return 1
		fi
		
		sleep 1
		((wait_count++))
	done
	
	log_error "Port-forward failed to become ready within ${VAULT_PORT_FORWARD_WAIT_TIMEOUT}s"
	cleanup_vault_port_forward
	return 1
}

# Cleanup Vault port-forward process
cleanup_vault_port_forward() {
	if [[ -n "${VAULT_PORT_FORWARD_PID:-}" ]]; then
		log_debug "Cleaning up port-forward (PID: $VAULT_PORT_FORWARD_PID)"
		
		if kill -0 "$VAULT_PORT_FORWARD_PID" 2>/dev/null; then
			kill "$VAULT_PORT_FORWARD_PID" 2>/dev/null || true
			sleep 1
			
			# Force kill if still running
			if kill -0 "$VAULT_PORT_FORWARD_PID" 2>/dev/null; then
				kill -9 "$VAULT_PORT_FORWARD_PID" 2>/dev/null || true
			fi
		fi
		
		unset VAULT_PORT_FORWARD_PID
	fi
}

################################################################################
# Connection Setup (High-Level)
################################################################################

# Setup complete Vault connection with intelligent fallback
# Arguments:
#   $1 - (optional) Explicit Vault address (overrides auto-detection)
#   $2 - (optional) Namespace (default: vault)
#
# Sets:
#   VAULT_ADDR - Vault server address
#   VAULT_CACERT - CA certificate path
#   VAULT_CACERT_SOURCE - Certificate source
#   VAULT_AUTH_METHOD - Authentication method (kubernetes or token)
#
# Returns:
#   0 - Connection established
#   1 - Failed to establish connection
setup_vault_connection() {
	local explicit_addr="${1:-}"
	local namespace="${2:-$VAULT_DEFAULT_NAMESPACE}"
	
	log_info "Setting up Vault connection..."
	
	# Detect execution mode
	local exec_mode
	exec_mode=$(detect_vault_execution_mode)
	log_info "Vault execution mode: $exec_mode"
	
	# Get CA certificate (only in IN_CLUSTER mode)
	local cert_info
	local ca_cert=""
	local ca_source=""
	
	if [[ "$exec_mode" == "LOCAL" ]]; then
		# Skip certificate search in LOCAL mode - we'll use VAULT_SKIP_VERIFY
		log_debug "Skipping certificate search (LOCAL mode uses VAULT_SKIP_VERIFY=1)"
		export VAULT_CACERT=""
		export VAULT_CACERT_SOURCE="skip_verify"
	elif cert_info=$(get_vault_certificate "$namespace"); then
		ca_cert=$(echo "$cert_info" | jq -r '.certificate_path')
		ca_source=$(echo "$cert_info" | jq -r '.source')
		export VAULT_CACERT="$ca_cert"
		export VAULT_CACERT_SOURCE="$ca_source"
	else
		log_warning "Proceeding without CA certificate"
		export VAULT_CACERT=""
		export VAULT_CACERT_SOURCE="none"
	fi
	
	# Determine Vault address
	local vault_addr=""
	
	if [[ -n "$explicit_addr" ]]; then
		# Explicit address provided
		vault_addr="$explicit_addr"
		export VAULT_AUTH_METHOD="token"
		log_info "Using explicitly provided Vault address: $vault_addr"
	
	elif [[ "$exec_mode" == "IN_CLUSTER" ]]; then
		# In-cluster: use Kubernetes DNS
		vault_addr="https://${VAULT_DEFAULT_SERVICE}.${namespace}.svc.cluster.local:${VAULT_DEFAULT_PORT}"
		export VAULT_AUTH_METHOD="kubernetes"
		log_info "Using in-cluster Vault address: $vault_addr"
	
	elif [[ "$exec_mode" == "LOCAL" ]]; then
		# Local: use port-forward
		export VAULT_AUTH_METHOD="token"
		log_info "LOCAL mode: setting up port-forward..."
		
		if ! setup_vault_port_forward "$namespace"; then
			log_error "Failed to set up port-forward"
			return 1
		fi
		
		vault_addr="https://localhost:${VAULT_DEFAULT_PORT}"
		log_info "Using port-forwarded Vault address: $vault_addr"
	else
		log_error "Unknown execution mode: $exec_mode"
		return 1
	fi
	
	# Test connection
	if ! test_vault_connection "$vault_addr" "$ca_cert"; then
		log_error "Vault connection test failed"
		return 1
	fi
	
	# Set final address
	export VAULT_ADDR="$vault_addr"
	
	log_success "Vault connection established"
	log_info "  Address: $VAULT_ADDR"
	log_info "  Auth method: $VAULT_AUTH_METHOD"
	log_info "  CA cert: ${VAULT_CACERT:-none} ($ca_source)"
	
	return 0
}

################################################################################
# Authentication
################################################################################

# Get Vault token from AWS SSM Parameter Store
# Arguments:
#   $1 - (optional) SSM parameter path (default: /vault/tokens/root)
#
# Output: Vault token to stdout
# Returns:
#   0 - Token retrieved
#   1 - Failed to retrieve token
get_vault_token_from_ssm() {
	local ssm_path="${1:-$VAULT_DEFAULT_SSM_TOKEN_PATH}"
	
	log_info "Retrieving Vault token from AWS SSM..."
	log_debug "SSM parameter path: $ssm_path"
	
	# Use get_ssm_parameter from forge-aws-discovery
	if ! command -v get_ssm_parameter &>/dev/null; then
		log_error "forge-aws-discovery not loaded (get_ssm_parameter not available)"
		return 1
	fi
	
	local token
	if ! token=$(get_ssm_parameter "$ssm_path"); then
		log_error "Failed to retrieve Vault token from SSM"
		return 1
	fi
	
	if [[ -z "$token" ]]; then
		log_error "Empty token retrieved from SSM"
		return 1
	fi
	
	echo "$token"
	return 0
}

# Authenticate to Vault using Kubernetes ServiceAccount
# Arguments:
#   $1 - (optional) Vault role name
#
# Sets:
#   VAULT_TOKEN - Vault authentication token
#
# Returns:
#   0 - Authentication successful
#   1 - Authentication failed
authenticate_vault_kubernetes() {
	local role="${1:-}"
	
	if [[ -z "$role" ]]; then
		log_error "Vault role name required for Kubernetes authentication"
		return 1
	fi
	
	log_info "Authenticating to Vault using Kubernetes ServiceAccount..."
	log_debug "Vault role: $role"
	
	# Get ServiceAccount token
	local sa_token_path="/var/run/secrets/kubernetes.io/serviceaccount/token"
	if [[ ! -f "$sa_token_path" ]]; then
		log_error "ServiceAccount token not found: $sa_token_path"
		return 1
	fi
	
	local jwt
	jwt=$(cat "$sa_token_path")
	
	# Authenticate
	local response
	if ! response=$(vault write -format=json "auth/kubernetes/login" \
		role="$role" \
		jwt="$jwt" 2>&1); then
		log_error "Kubernetes authentication failed"
		log_debug "Response: $response"
		return 1
	fi
	
	# Extract token
	local token
	token=$(echo "$response" | jq -r '.auth.client_token')
	
	if [[ -z "$token" || "$token" == "null" ]]; then
		log_error "Failed to extract token from authentication response"
		return 1
	fi
	
	export VAULT_TOKEN="$token"
	log_success "Kubernetes authentication successful"
	
	return 0
}

# Authenticate to Vault using token (LOCAL mode)
# Arguments:
#   $1 - (optional) Vault token or SSM parameter path
#
# Sets:
#   VAULT_TOKEN - Vault authentication token
#
# Returns:
#   0 - Authentication successful
#   1 - Authentication failed
authenticate_vault_token() {
	local token_or_path="${1:-}"
	
	log_info "Authenticating to Vault using token..."
	
	local token=""
	
	# If token_or_path starts with /, assume it's SSM path
	if [[ "$token_or_path" == /* ]]; then
		log_debug "Retrieving token from SSM: $token_or_path"
		if ! token=$(get_vault_token_from_ssm "$token_or_path"); then
			return 1
		fi
	elif [[ -n "$token_or_path" ]]; then
		# Direct token
		token="$token_or_path"
	elif [[ -n "${VAULT_TOKEN:-}" ]]; then
		# Use existing VAULT_TOKEN
		log_info "Using existing VAULT_TOKEN environment variable"
		token="$VAULT_TOKEN"
	else
		# Try default SSM path
		log_debug "No token provided, trying default SSM path..."
		if ! token=$(get_vault_token_from_ssm); then
			log_error "Failed to retrieve token from default SSM path"
			return 1
		fi
	fi
	
	if [[ -z "$token" ]]; then
		log_error "No Vault token available"
		return 1
	fi
	
	export VAULT_TOKEN="$token"
	
	# Verify VAULT_ADDR is set
	if [[ -z "${VAULT_ADDR:-}" ]]; then
		log_error "VAULT_ADDR not set - cannot verify token"
		return 1
	fi
	
	# Skip certificate lookup in LOCAL mode (using VAULT_SKIP_VERIFY)
	if [[ -z "${VAULT_CACERT:-}" ]] && [[ "${VAULT_SKIP_VERIFY:-0}" != "1" ]]; then
		log_debug "Attempting to find Vault certificate..."
		
		# Try to get certificate
		local cert_info
		if cert_info=$(get_vault_certificate 2>&1 | grep -E '^\{'); then
			local cert_path
			cert_path=$(echo "$cert_info" | jq -r '.certificate_path')
			
			if [[ -n "$cert_path" && -f "$cert_path" ]]; then
				export VAULT_CACERT="$cert_path"
				log_debug "Using certificate: $cert_path"
			fi
		fi
	elif [[ "${VAULT_SKIP_VERIFY:-0}" == "1" ]]; then
		log_debug "Skipping certificate lookup (VAULT_SKIP_VERIFY=1)"
	fi
	
	# Verify token using vault CLI
	log_debug "Verifying token with: vault token lookup"
	if ! vault token lookup &>/dev/null; then
		log_error "Token authentication failed (token invalid or expired)"
		log_debug "VAULT_ADDR: ${VAULT_ADDR:-not set}"
		log_debug "VAULT_CACERT: ${VAULT_CACERT:-not set}"
		return 1
	fi
	
	log_success "Token authentication successful"
	return 0
}

# High-level authentication wrapper
# Arguments:
#   $1 - (optional) Vault role (for kubernetes) or token/SSM path (for token)
#
# Returns:
#   0 - Authentication successful
#   1 - Authentication failed
authenticate_vault() {
	local auth_arg="${1:-}"
	
	if [[ "${VAULT_AUTH_METHOD:-}" == "kubernetes" ]]; then
		authenticate_vault_kubernetes "$auth_arg"
	else
		authenticate_vault_token "$auth_arg"
	fi
}

################################################################################
# Secret Operations (KV v2 Aware)
################################################################################

# Read secret from Vault (KV v2 aware)
# Arguments:
#   $1 - Secret path (e.g., secret/data/myapp/config)
#
# Output: JSON object with secret data
read_vault_secret() {
	local secret_path="$1"
	
	if [[ -z "$secret_path" ]]; then
		log_error "Secret path required"
		return 1
	fi
	
	log_debug "Reading secret: $secret_path"
	
	local response
	if ! response=$(vault kv get -format=json "$secret_path" 2>&1); then
		log_error "Failed to read secret: $secret_path"
		log_debug "Response: $response"
		return 1
	fi
	
	# Extract data
	local data
	data=$(echo "$response" | jq -r '.data.data // .data')
	
	echo "$data"
	return 0
}

# Write secret to Vault (KV v2 aware)
# Arguments:
#   $1 - Secret path
#   $2 - JSON data to write
#
# Returns:
#   0 - Success
#   1 - Failed
write_vault_secret() {
	local secret_path="$1"
	local data="$2"
	
	if [[ -z "$secret_path" || -z "$data" ]]; then
		log_error "Secret path and data required"
		return 1
	fi
	
	log_debug "Writing secret: $secret_path"
	
	# Convert JSON data to key=value pairs for vault kv put
	local kv_args=()
	while IFS= read -r key; do
		local value
		value=$(echo "$data" | jq -r ".[\"$key\"]")
		kv_args+=("$key=$value")
	done < <(echo "$data" | jq -r 'keys[]')
	
	if ! vault kv put "$secret_path" "${kv_args[@]}" &>/dev/null; then
		log_error "Failed to write secret: $secret_path"
		return 1
	fi
	
	log_success "Secret written: $secret_path"
	return 0
}

################################################################################
# Export Functions
################################################################################

export -f detect_vault_execution_mode
export -f get_vault_execution_mode
export -f get_vault_certificate
export -f test_vault_connection
export -f setup_vault_port_forward
export -f cleanup_vault_port_forward
export -f setup_vault_connection
export -f get_vault_token_from_ssm
export -f authenticate_vault_kubernetes
export -f authenticate_vault_token
export -f authenticate_vault
export -f read_vault_secret
export -f write_vault_secret

################################################################################
# Initialization
################################################################################

log_info "Forge Vault Discovery Library loaded (v1.0.0)"

# Detect and log execution mode
VAULT_EXECUTION_MODE=$(detect_vault_execution_mode)
export VAULT_EXECUTION_MODE

log_info "Vault execution mode: $VAULT_EXECUTION_MODE"
