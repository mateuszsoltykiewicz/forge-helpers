#!/usr/bin/env bash

################################################################################
# Forge Kubernetes Discovery Library
################################################################################
# Version: 1.0.0
# Description: Kubernetes resource discovery and management with intelligent
#              execution context detection (in-cluster vs local)
#
# Features:
# - 3-Mode execution detection (IN_CLUSTER, LOCAL_EXPLICIT, LOCAL_AUTO)
# - ServiceAccount token detection and management
# - Smart kubectl wrapper with context awareness
# - Namespace and pod discovery operations
# - Secret management
# - Integration with forge-core, forge-patterns, and forge-aws-discovery
#
# Dependencies:
# - forge-core.sh
# - forge-patterns.sh
# - forge-aws-discovery.sh (for LOCAL_AUTO mode)
# - kubectl
# - jq
#
# Author: Moai Forge Team
# Created: 2026-02-06
################################################################################

# Prevent double-loading
if [[ -n "${FORGE_K8S_DISCOVERY_LOADED:-}" ]]; then
	return 0
fi
FORGE_K8S_DISCOVERY_LOADED=1

################################################################################
# Dependencies
################################################################################

# Determine script directory
FORGE_K8S_DISCOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -z "${FORGE_CORE_LOADED:-}" ]]; then
	# shellcheck source=forge-core.sh
	source "${FORGE_K8S_DISCOVERY_DIR}/forge-core.sh"
fi

if [[ -z "${FORGE_PATTERNS_LOADED:-}" ]]; then
	# shellcheck source=forge-patterns.sh
	source "${FORGE_K8S_DISCOVERY_DIR}/forge-patterns.sh"
fi

if [[ -z "${FORGE_AWS_DISCOVERY_LOADED:-}" ]]; then
	# shellcheck source=forge-aws-discovery.sh
	source "${FORGE_K8S_DISCOVERY_DIR}/forge-aws-discovery.sh"
fi

# Validate required commands
validate_required_commands kubectl jq

################################################################################
# Constants
################################################################################

readonly K8S_SERVICE_ACCOUNT_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
readonly K8S_SERVICE_ACCOUNT_NAMESPACE_PATH="/var/run/secrets/kubernetes.io/serviceaccount/namespace"
readonly K8S_SERVICE_ACCOUNT_CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
readonly K8S_POD_READY_TIMEOUT=300  # 5 minutes
readonly K8S_POD_READY_INTERVAL=5   # 5 seconds

################################################################################
# Execution Mode Detection
################################################################################

# Check if ServiceAccount token exists (indicates in-cluster execution)
# Output: "true" or "false" to stdout
check_service_account_token() {
	if [[ -f "$K8S_SERVICE_ACCOUNT_TOKEN_PATH" ]]; then
		echo "true"
		return 0
	else
		echo "false"
		return 1
	fi
}

# Detect Kubernetes execution context
# Returns one of three modes:
# - IN_CLUSTER: Running in Kubernetes pod with ServiceAccount
# - LOCAL_EXPLICIT: Running locally with explicit cluster specified
# - LOCAL_AUTO: Running locally without cluster specified (auto-discovery)
#
# Arguments:
#   $1 - (optional) Explicit cluster name
#
# Output: Execution mode to stdout
detect_kubernetes_context() {
	local explicit_cluster="${1:-}"
	
	# Check for ServiceAccount token
	if [[ "$(check_service_account_token)" == "true" ]]; then
		echo "IN_CLUSTER"
		return 0
	fi
	
	# Local execution - check if cluster explicitly specified
	if [[ -n "$explicit_cluster" ]]; then
		echo "LOCAL_EXPLICIT"
		return 0
	fi
	
	# Local execution - auto-discovery mode
	echo "LOCAL_AUTO"
	return 0
}

################################################################################
# ServiceAccount Information
################################################################################

# Get current namespace from ServiceAccount (in-cluster mode)
# Output: Namespace name to stdout
# Returns:
#   0 - Success
#   1 - Not in cluster or failed to get namespace
get_current_namespace() {
	if [[ "$(check_service_account_token)" != "true" ]]; then
		log_error "Not running in cluster - cannot get namespace from ServiceAccount"
		return 1
	fi
	
	if [[ ! -f "$K8S_SERVICE_ACCOUNT_NAMESPACE_PATH" ]]; then
		log_error "ServiceAccount namespace file not found: $K8S_SERVICE_ACCOUNT_NAMESPACE_PATH"
		return 1
	fi
	
	local namespace
	namespace=$(cat "$K8S_SERVICE_ACCOUNT_NAMESPACE_PATH")
	
	if [[ -z "$namespace" ]]; then
		log_error "Empty namespace from ServiceAccount"
		return 1
	fi
	
	echo "$namespace"
	return 0
}

# Get ServiceAccount information (in-cluster mode)
# Output: JSON object with namespace, token_path, ca_path
get_service_account_info() {
	if [[ "$(check_service_account_token)" != "true" ]]; then
		log_error "Not running in cluster - no ServiceAccount available"
		return 1
	fi
	
	local namespace
	if ! namespace=$(get_current_namespace); then
		return 1
	fi
	
	jq -n \
		--arg namespace "$namespace" \
		--arg token_path "$K8S_SERVICE_ACCOUNT_TOKEN_PATH" \
		--arg ca_path "$K8S_SERVICE_ACCOUNT_CA_PATH" \
		'{
			namespace: $namespace,
			token_path: $token_path,
			ca_path: $ca_path
		}'
	
	return 0
}

################################################################################
# Kubectl Context Management
################################################################################

# Setup kubeconfig for EKS cluster (local mode)
# Arguments:
#   $1 - Cluster name (optional - will auto-discover if not provided)
#   $2 - Discovery method (optional - for auto-discovery: "forge-pattern", "namespace")
#   $3+ - Discovery method arguments (optional)
#
# Returns:
#   0 - Success
#   1 - Failed
setup_kubernetes_context() {
	local cluster="${1:-}"
	local discovery_method="${2:-}"
	shift 2 2>/dev/null || shift $# 2>/dev/null
	local discovery_args=("$@")
	
	# If cluster not provided, auto-discover
	if [[ -z "$cluster" ]]; then
		if [[ -z "$discovery_method" ]]; then
			log_error "Cluster name or discovery method required"
			return 1
		fi
		
		log_info "Auto-discovering cluster using method: $discovery_method"
		
		# Use configure_eks_context from forge-aws-discovery
		if ! cluster=$(configure_eks_context "$discovery_method" "${discovery_args[@]}"); then
			log_error "Failed to discover and configure cluster"
			return 1
		fi
		
		log_success "Cluster configured: $cluster"
		return 0
	fi
	
	# Explicit cluster - configure it
	log_info "Configuring kubeconfig for cluster: $cluster"
	
	if ! configure_eks_context "cluster-name" "$cluster"; then
		log_error "Failed to configure cluster: $cluster"
		return 1
	fi
	
	log_success "Cluster configured: $cluster"
	return 0
}

# Execute kubectl command with context awareness
# In IN_CLUSTER mode: uses in-cluster auth automatically
# In LOCAL modes: uses configured kubeconfig
#
# Arguments:
#   $@ - kubectl command arguments
#
# Returns: kubectl exit code
execute_kubectl() {
	local mode
	mode=$(detect_kubernetes_context)
	
	if [[ "$mode" == "IN_CLUSTER" ]]; then
		# In-cluster mode - kubectl uses ServiceAccount automatically
		retry_command 3 2 kubectl "$@"
	else
		# Local modes - use configured kubeconfig
		retry_command 3 2 kubectl "$@"
	fi
}

################################################################################
# Namespace Operations
################################################################################

# Check if namespace exists in cluster
# Arguments:
#   $1 - Namespace name
#
# Returns:
#   0 - Namespace exists
#   1 - Namespace does not exist
check_namespace_exists() {
	local namespace="$1"
	
	if [[ -z "$namespace" ]]; then
		log_error "Namespace name required"
		return 1
	fi
	
	if execute_kubectl get namespace "$namespace" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Get namespace details
# Arguments:
#   $1 - Namespace name
#
# Output: JSON object with namespace details
get_namespace_info() {
	local namespace="$1"
	
	if [[ -z "$namespace" ]]; then
		log_error "Namespace name required"
		return 1
	fi
	
	if ! check_namespace_exists "$namespace"; then
		log_error "Namespace does not exist: $namespace"
		return 1
	fi
	
	execute_kubectl get namespace "$namespace" -o json
}

################################################################################
# Pod Operations
################################################################################

# Get pod information
# Arguments:
#   $1 - Pod name
#   $2 - Namespace
#
# Output: JSON object with pod details
get_pod_info() {
	local pod_name="$1"
	local namespace="$2"
	
	if [[ -z "$pod_name" || -z "$namespace" ]]; then
		log_error "Pod name and namespace required"
		return 1
	fi
	
	execute_kubectl get pod "$pod_name" -n "$namespace" -o json
}

# Check if pod is ready
# Arguments:
#   $1 - Pod name
#   $2 - Namespace
#
# Returns:
#   0 - Pod is ready
#   1 - Pod is not ready
check_pod_ready() {
	local pod_name="$1"
	local namespace="$2"
	
	if [[ -z "$pod_name" || -z "$namespace" ]]; then
		log_error "Pod name and namespace required"
		return 1
	fi
	
	local ready_status
	ready_status=$(execute_kubectl get pod "$pod_name" -n "$namespace" \
		-o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
	
	if [[ "$ready_status" == "True" ]]; then
		return 0
	else
		return 1
	fi
}

# Wait for pod to be ready
# Arguments:
#   $1 - Pod name
#   $2 - Namespace
#   $3 - (optional) Timeout in seconds (default: K8S_POD_READY_TIMEOUT)
#
# Returns:
#   0 - Pod became ready
#   1 - Timeout or error
wait_for_pod_ready() {
	local pod_name="$1"
	local namespace="$2"
	local timeout="${3:-$K8S_POD_READY_TIMEOUT}"
	
	if [[ -z "$pod_name" || -z "$namespace" ]]; then
		log_error "Pod name and namespace required"
		return 1
	fi
	
	log_info "Waiting for pod to be ready: $pod_name (timeout: ${timeout}s)"
	
	local elapsed=0
	while [[ $elapsed -lt $timeout ]]; do
		if check_pod_ready "$pod_name" "$namespace"; then
			log_success "Pod is ready: $pod_name"
			return 0
		fi
		
		sleep "$K8S_POD_READY_INTERVAL"
		elapsed=$((elapsed + K8S_POD_READY_INTERVAL))
		
		if [[ $((elapsed % 30)) -eq 0 ]]; then
			log_info "Still waiting... (${elapsed}s / ${timeout}s)"
		fi
	done
	
	log_error "Timeout waiting for pod to be ready: $pod_name"
	return 1
}

# List pods in namespace with optional label selector
# Arguments:
#   $1 - Namespace
#   $2 - (optional) Label selector (e.g., "app=myapp")
#
# Output: Space-separated list of pod names
list_pods() {
	local namespace="$1"
	local label_selector="${2:-}"
	
	if [[ -z "$namespace" ]]; then
		log_error "Namespace required"
		return 1
	fi
	
	local cmd=(get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
	
	if [[ -n "$label_selector" ]]; then
		cmd+=(-l "$label_selector")
	fi
	
	execute_kubectl "${cmd[@]}"
}

################################################################################
# Secret Operations
################################################################################

# Check if secret exists
# Arguments:
#   $1 - Secret name
#   $2 - Namespace
#
# Returns:
#   0 - Secret exists
#   1 - Secret does not exist
check_secret_exists() {
	local secret_name="$1"
	local namespace="$2"
	
	if [[ -z "$secret_name" || -z "$namespace" ]]; then
		log_error "Secret name and namespace required"
		return 1
	fi
	
	if execute_kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Get secret value by key
# Arguments:
#   $1 - Secret name
#   $2 - Namespace
#   $3 - Secret key
#
# Output: Base64-decoded secret value to stdout
get_secret_value() {
	local secret_name="$1"
	local namespace="$2"
	local key="$3"
	
	if [[ -z "$secret_name" || -z "$namespace" || -z "$key" ]]; then
		log_error "Secret name, namespace, and key required"
		return 1
	fi
	
	if ! check_secret_exists "$secret_name" "$namespace"; then
		log_error "Secret does not exist: $secret_name in namespace $namespace"
		return 1
	fi
	
	execute_kubectl get secret "$secret_name" -n "$namespace" \
		-o jsonpath="{.data.$key}" | base64 -d
}

# Get all secret data
# Arguments:
#   $1 - Secret name
#   $2 - Namespace
#
# Output: JSON object with all decoded secret values
get_secret_data() {
	local secret_name="$1"
	local namespace="$2"
	
	if [[ -z "$secret_name" || -z "$namespace" ]]; then
		log_error "Secret name and namespace required"
		return 1
	fi
	
	if ! check_secret_exists "$secret_name" "$namespace"; then
		log_error "Secret does not exist: $secret_name in namespace $namespace"
		return 1
	fi
	
	local secret_json
	secret_json=$(execute_kubectl get secret "$secret_name" -n "$namespace" -o json)
	
	# Decode all base64 values
	echo "$secret_json" | jq -r '.data | to_entries | map({key: .key, value: (.value | @base64d)}) | from_entries'
}

################################################################################
# ConfigMap Operations
################################################################################

# Check if configmap exists
# Arguments:
#   $1 - ConfigMap name
#   $2 - Namespace
#
# Returns:
#   0 - ConfigMap exists
#   1 - ConfigMap does not exist
check_configmap_exists() {
	local configmap_name="$1"
	local namespace="$2"
	
	if [[ -z "$configmap_name" || -z "$namespace" ]]; then
		log_error "ConfigMap name and namespace required"
		return 1
	fi
	
	if execute_kubectl get configmap "$configmap_name" -n "$namespace" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Get configmap value by key
# Arguments:
#   $1 - ConfigMap name
#   $2 - Namespace
#   $3 - ConfigMap key
#
# Output: ConfigMap value to stdout
get_configmap_value() {
	local configmap_name="$1"
	local namespace="$2"
	local key="$3"
	
	if [[ -z "$configmap_name" || -z "$namespace" || -z "$key" ]]; then
		log_error "ConfigMap name, namespace, and key required"
		return 1
	fi
	
	if ! check_configmap_exists "$configmap_name" "$namespace"; then
		log_error "ConfigMap does not exist: $configmap_name in namespace $namespace"
		return 1
	fi
	
	execute_kubectl get configmap "$configmap_name" -n "$namespace" \
		-o jsonpath="{.data.$key}"
}

################################################################################
# Service Operations
################################################################################

# Check if service exists
# Arguments:
#   $1 - Service name
#   $2 - Namespace
#
# Returns:
#   0 - Service exists
#   1 - Service does not exist
check_service_exists() {
	local service_name="$1"
	local namespace="$2"
	
	if [[ -z "$service_name" || -z "$namespace" ]]; then
		log_error "Service name and namespace required"
		return 1
	fi
	
	if execute_kubectl get service "$service_name" -n "$namespace" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Get service endpoint
# Arguments:
#   $1 - Service name
#   $2 - Namespace
#
# Output: Service cluster IP to stdout
get_service_endpoint() {
	local service_name="$1"
	local namespace="$2"
	
	if [[ -z "$service_name" || -z "$namespace" ]]; then
		log_error "Service name and namespace required"
		return 1
	fi
	
	if ! check_service_exists "$service_name" "$namespace"; then
		log_error "Service does not exist: $service_name in namespace $namespace"
		return 1
	fi
	
	execute_kubectl get service "$service_name" -n "$namespace" \
		-o jsonpath='{.spec.clusterIP}'
}

################################################################################
# Export Functions
################################################################################

export -f check_service_account_token
export -f detect_kubernetes_context
export -f get_current_namespace
export -f get_service_account_info
export -f setup_kubernetes_context
export -f execute_kubectl
export -f check_namespace_exists
export -f get_namespace_info
export -f get_pod_info
export -f check_pod_ready
export -f wait_for_pod_ready
export -f list_pods
export -f check_secret_exists
export -f get_secret_value
export -f get_secret_data
export -f check_configmap_exists
export -f get_configmap_value
export -f check_service_exists
export -f get_service_endpoint

################################################################################
# Initialization
################################################################################

log_info "Forge Kubernetes Discovery Library loaded (v1.0.0)"

# Detect and log execution mode
K8S_EXECUTION_MODE=$(detect_kubernetes_context)
export K8S_EXECUTION_MODE

if [[ "$K8S_EXECUTION_MODE" == "IN_CLUSTER" ]]; then
	log_info "Kubernetes execution mode: IN_CLUSTER (ServiceAccount detected)"
	
	# Log ServiceAccount info if available
	if current_ns=$(get_current_namespace 2>/dev/null); then
		log_info "Current namespace: $current_ns"
	fi
else
	log_info "Kubernetes execution mode: LOCAL (will use kubeconfig)"
fi
