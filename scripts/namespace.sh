#!/bin/bash
# ==============================================================================
# Generic Kubernetes Namespace Management Script
# ==============================================================================
# Description: Creates/deletes Kubernetes namespaces with Forge conventions
# Version: 3.0.0
# Compatible: bash 3.2+ (macOS compatible)
# 
# Changelog:
#   v3.0.0 - Auto-detection of Kubernetes context (in-cluster, local-auto, local-explicit)
#            AWS EKS cluster auto-discovery, optional kubeconfig/context flags
#   v2.0.0 - Initial Forge conventions implementation
# ==============================================================================

set -e

# ==============================================================================
# SCRIPT METADATA
# ==============================================================================

readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# ==============================================================================
# DEFAULT CONFIGURATION
# ==============================================================================

DEFAULT_PSS_ENFORCE="baseline"
DEFAULT_PSS_AUDIT="restricted"
DEFAULT_PSS_WARN="restricted"

# ==============================================================================
# GLOBAL VARIABLES (set by parse_arguments)
# ==============================================================================

CUSTOMER=""
PROJECT=""
SERVICE_NAME=""
ENVIRONMENT=""
CONFIG_PATH=""

# Naming
NAMESPACE_OVERRIDE=""

# Kubernetes Authentication - UPDATED v3.0.0
EXECUTION_MODE=""           # in-cluster | local-auto | local-explicit
KUBECONFIG_PATH="${KUBECONFIG:-}"
KUBECTL_CONTEXT=""
AWS_REGION="${AWS_REGION:-}"

# Pod Security Standards
PSS_ENFORCE="$DEFAULT_PSS_ENFORCE"
PSS_AUDIT="$DEFAULT_PSS_AUDIT"
PSS_WARN="$DEFAULT_PSS_WARN"

# Control Flags
DELETE_MODE=false
DRY_RUN=false
VERBOSE=false

# Statistics
TOTAL_CREATED=0
TOTAL_DELETED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# ==============================================================================
# COLORS (if terminal supports it)
# ==============================================================================

if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  BOLD=''
  NC=''
fi

# ==============================================================================
# LOGGING
# ==============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC}  $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[✓]${NC}    $*"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC}  $*"
}

log_debug() {
  if [ "$VERBOSE" = true ]; then
    echo -e "${CYAN}[DEBUG]${NC} $*"
  fi
}

log_dry_run() {
  echo -e "${CYAN}[DRY-RUN]${NC} $*"
}

# ==============================================================================
# NAMING CONVENTION FUNCTIONS
# ==============================================================================

get_namespace_name() {
  local customer="$1"
  local project="$2"
  local env="$3"
  local service="$4"
  
  # Use override if provided
  if [ -n "$NAMESPACE_OVERRIDE" ]; then
    echo "$NAMESPACE_OVERRIDE"
  else
    echo "${customer}-${project}-${env}-${service}"
  fi
}

# ==============================================================================
# KUBERNETES CONTEXT DETECTION (v3.0.0)
# ==============================================================================

detect_kubernetes_context() {
  log_info "Detecting Kubernetes execution mode..."
  
  # Mode 1: In-cluster (ServiceAccount token present)
  if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then
    EXECUTION_MODE="in-cluster"
    log_success "Detected: In-cluster mode (ServiceAccount authentication)"
    return 0
  fi
  
  # Mode 2: Local-explicit (user provided kubeconfig and/or context)
  if [ -n "$KUBECONFIG_PATH" ] || [ -n "$KUBECTL_CONTEXT" ]; then
    EXECUTION_MODE="local-explicit"
    log_success "Detected: Local-explicit mode (manual kubeconfig/context)"
    
    # Setup kubeconfig if provided
    if [ -n "$KUBECONFIG_PATH" ]; then
      if [ ! -f "$KUBECONFIG_PATH" ]; then
        log_error "Kubeconfig file not found: $KUBECONFIG_PATH"
        return 1
      fi
      export KUBECONFIG="$KUBECONFIG_PATH"
      log_debug "KUBECONFIG: $KUBECONFIG"
    fi
    
    # Setup context if provided
    if [ -n "$KUBECTL_CONTEXT" ]; then
      if ! kubectl config use-context "$KUBECTL_CONTEXT" >/dev/null 2>&1; then
        log_warning "Context '$KUBECTL_CONTEXT' not found in kubeconfig"
        log_info "Attempting to discover as EKS cluster name..."
        
        # Fallback: Try to discover as EKS cluster
        if command -v aws &> /dev/null; then
          local region="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'eu-central-1')}"
          log_debug "Checking if '$KUBECTL_CONTEXT' is an EKS cluster in region: $region"
          
          # Check if cluster exists in EKS
          if aws eks describe-cluster --name "$KUBECTL_CONTEXT" --region "$region" >/dev/null 2>&1; then
            log_info "Found EKS cluster: $KUBECTL_CONTEXT"
            log_info "Updating kubeconfig..."
            
            if aws eks update-kubeconfig \
              --region "$region" \
              --name "$KUBECTL_CONTEXT" \
              --alias "$KUBECTL_CONTEXT" \
              >/dev/null 2>&1; then
              log_success "Kubeconfig updated for cluster: $KUBECTL_CONTEXT"
              AWS_REGION="$region"
              export KUBECONFIG="${HOME}/.kube/config"
            else
              log_error "Failed to update kubeconfig for cluster: $KUBECTL_CONTEXT"
              return 1
            fi
          else
            log_error "Context '$KUBECTL_CONTEXT' not found in kubeconfig"
            log_error "Cluster '$KUBECTL_CONTEXT' not found in EKS region: $region"
            log_info "Available contexts:"
            kubectl config get-contexts -o name 2>/dev/null | sed 's/^/  - /' || echo "  (none)"
            return 1
          fi
        else
          log_error "Failed to use context: $KUBECTL_CONTEXT"
          log_error "AWS CLI not available for EKS cluster discovery"
          log_info "Available contexts:"
          kubectl config get-contexts -o name 2>/dev/null | sed 's/^/  - /' || echo "  (none)"
          return 1
        fi
      else
        log_debug "Using context: $KUBECTL_CONTEXT"
      fi
    fi
    
    return 0
  fi
  
  # Mode 3: Local-auto (discover EKS cluster automatically)
  EXECUTION_MODE="local-auto"
  log_info "Detected: Local-auto mode (will discover EKS cluster)"
  
  if ! discover_eks_cluster; then
    log_error "Failed to auto-discover EKS cluster"
    log_error "Please provide --kubeconfig and/or --context explicitly"
    return 1
  fi
  
  log_success "Auto-discovery complete"
  return 0
}

discover_eks_cluster() {
  log_info "Starting AWS EKS cluster auto-discovery..."
  
  # Check aws CLI
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Install it or use --kubeconfig/--context"
    return 1
  fi
  
  # Determine AWS region
  if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "eu-central-1")
    log_debug "AWS_REGION not set, using: $AWS_REGION"
  fi
  log_info "Searching EKS clusters in region: $AWS_REGION"
  
  # Build target namespace
  local target_namespace
  target_namespace=$(get_namespace_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  log_info "Looking for namespace: $target_namespace"
  
  # List EKS clusters
  local clusters
  clusters=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output text 2>/dev/null)
  
  if [ -z "$clusters" ]; then
    log_error "No EKS clusters found in region $AWS_REGION"
    return 1
  fi
  
  log_info "Found $(echo "$clusters" | wc -w | tr -d ' ') EKS cluster(s), checking each..."
  
  # Try each cluster
  for cluster_name in $clusters; do
    log_debug "Checking cluster: $cluster_name"
    
    # Update kubeconfig for this cluster
    if ! aws eks update-kubeconfig \
      --region "$AWS_REGION" \
      --name "$cluster_name" \
      --alias "$cluster_name" \
      >/dev/null 2>&1; then
      log_debug "Failed to update kubeconfig for $cluster_name, skipping..."
      continue
    fi
    
    # Check if namespace exists in this cluster
    if kubectl get namespace "$target_namespace" \
      --context "$cluster_name" \
      >/dev/null 2>&1; then
      log_success "Found namespace '$target_namespace' in cluster: $cluster_name"
      KUBECTL_CONTEXT="$cluster_name"
      export KUBECONFIG="${HOME}/.kube/config"  # aws eks update-kubeconfig uses default location
      return 0
    fi
    
    log_debug "Namespace not found in $cluster_name"
  done
  
  log_error "Namespace '$target_namespace' not found in any EKS cluster in region $AWS_REGION"
  log_error "Clusters checked: $clusters"
  return 1
}

execute_kubectl() {
  # Smart kubectl wrapper adapting to execution mode
  
  case "$EXECUTION_MODE" in
    in-cluster)
      # In-cluster: no context needed, kubectl uses SA token
      kubectl "$@"
      ;;
    local-explicit|local-auto)
      # Local: add context if available
      if [ -n "$KUBECTL_CONTEXT" ]; then
        kubectl --context "$KUBECTL_CONTEXT" "$@"
      else
        kubectl "$@"
      fi
      ;;
    *)
      # Fallback: direct kubectl
      kubectl "$@"
      ;;
  esac
}

# ==============================================================================
# HELP & USAGE
# ==============================================================================

print_banner() {
  cat <<'BANNER'
╔══════════════════════════════════════════════════════════════╗
║   Generic Kubernetes Namespace Management Script            ║
║                       Version 3.0.0                          ║
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

DESCRIPTION:
  Creates or deletes Kubernetes namespaces with Forge labeling conventions,
  Pod Security Standards, and resource quotas/limits from YAML configuration.

REQUIRED ARGUMENTS:
  --customer CUSTOMER           Customer name (e.g., customer, indegene)
  --project PROJECT             Project name (e.g., project, platform)
  --service-name SERVICE        Service name (e.g., application, api-gateway)
  --environment ENV             Environment (dev, staging, prod, or comma-separated)
  --config-path PATH            Path to YAML configuration file (not required for delete)

NAMING OPTIONS:
  --namespace NAME              Override namespace name (instead of auto-generated)
                                Default: {customer}-{project}-{env}-{service}

KUBERNETES AUTHENTICATION (v3.0.0 - Auto-Detection):
  --kubeconfig PATH             (Optional) Path to kubeconfig file
  --context NAME                (Optional) kubectl context to use
  --aws-region REGION           (Optional) AWS region for EKS discovery (default: from aws config)

  Execution Modes (auto-detected):
  1. In-cluster:     Running inside Kubernetes pod with ServiceAccount
                     - Auto-detected if /var/run/secrets/kubernetes.io/serviceaccount/token exists
  2. Local-explicit: Manual kubeconfig and/or context provided via flags
                     - Activated when --kubeconfig or --context is specified
  3. Local-auto:     Automatic EKS cluster discovery via AWS CLI
                     - Lists EKS clusters in AWS region
                     - Updates kubeconfig for each cluster
                     - Searches for namespace across all clusters
                     - Auto-selects cluster containing the namespace

POD SECURITY STANDARDS:
  --pss-enforce LEVEL           PSS enforce level (default: $DEFAULT_PSS_ENFORCE)
                                Values: privileged, baseline, restricted
  --pss-audit LEVEL             PSS audit level (default: $DEFAULT_PSS_AUDIT)
  --pss-warn LEVEL              PSS warn level (default: $DEFAULT_PSS_WARN)

CONTROL FLAGS:
  --delete                      Delete namespace instead of creating
  --dry-run                     Preview without making changes
  --verbose                     Enable verbose logging
  -h, --help                    Show this help message
  -v, --version                 Show script version

YAML CONFIGURATION FILE:
  The configuration file should contain ResourceQuota and LimitRange specs.
  
  Example structure:
    resourceQuota:
      hard:
        requests.cpu: "4"
        requests.memory: "8Gi"
        limits.cpu: "8"
        limits.memory: "16Gi"
        persistentvolumeclaims: "5"
    
    limitRange:
      limits:
        - max:
            cpu: "2"
            memory: "4Gi"
          min:
            cpu: "100m"
            memory: "128Mi"
          default:
            cpu: "500m"
            memory: "512Mi"
          defaultRequest:
            cpu: "200m"
            memory: "256Mi"
          type: Container

NAMING CONVENTION:
  Namespace: {customer}-{project}-{environment}-{service}
  
  Example: customer-project-dev-application

FORGE LABELS:
  app.kubernetes.io/name: {service}
  app.kubernetes.io/instance: {customer}-{project}-{env}-{service}
  app.kubernetes.io/part-of: {project}
  app.kubernetes.io/managed-by: forge
  forge.moai.io/customer: {customer}
  forge.moai.io/project: {project}
  forge.moai.io/environment: {environment}
  forge.moai.io/service: {service}

EXAMPLES:
  # Create namespace with auto-discovery (v3.0.0 - Recommended)
  # Auto-detects execution mode and discovers EKS cluster
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev \\
    --config-path ./namespace-config.yaml

  # Create namespace with explicit context
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev \\
    --config-path ./namespace-config.yaml \\
    --context indegene-eks

  # Create namespace with explicit kubeconfig and context
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev \\
    --config-path ./namespace-config.yaml \\
    --kubeconfig ~/.kube/config \\
    --context indegene-eks

  # Create multiple environments
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev,staging,prod \\
    --config-path ./namespace-config.yaml

  # Delete namespace with dry-run
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev \\
    --delete \\
    --dry-run

  # Delete namespace (with confirmation)
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev \\
    --delete

  # Custom PSS levels
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment prod \\
    --config-path ./namespace-config.yaml \\
    --pss-enforce restricted

  # Override namespace name
  $SCRIPT_NAME \\
    --customer customer \\
    --project project \\
    --service-name application \\
    --environment dev \\
    --config-path ./namespace-config.yaml \\
    --namespace custom-namespace-name

EXIT CODES:
  0 - Success
  1 - General error
  2 - Invalid arguments
  3 - Kubernetes connection failed
  4 - Configuration file error

VERSION:
  ${SCRIPT_VERSION}
USAGE
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

parse_arguments() {
  if [ $# -eq 0 ]; then
    print_banner
    print_usage
    exit 0
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        print_banner
        print_usage
        exit 0
        ;;
      --version|-v)
        print_version
        exit 0
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
      --environment)
        ENVIRONMENT="$2"
        shift 2
        ;;
      --config-path)
        CONFIG_PATH="$2"
        shift 2
        ;;
      --namespace)
        NAMESPACE_OVERRIDE="$2"
        shift 2
        ;;
      --kubeconfig)
        KUBECONFIG_PATH="$2"
        shift 2
        ;;
      --context)
        KUBECTL_CONTEXT="$2"
        shift 2
        ;;
      --aws-region)
        AWS_REGION="$2"
        shift 2
        ;;
      --pss-enforce)
        PSS_ENFORCE="$2"
        shift 2
        ;;
      --pss-audit)
        PSS_AUDIT="$2"
        shift 2
        ;;
      --pss-warn)
        PSS_WARN="$2"
        shift 2
        ;;
      --delete)
        DELETE_MODE=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        echo ""
        print_usage
        exit 2
        ;;
    esac
  done

  # Validate required arguments
  if [ -z "$CUSTOMER" ] || [ -z "$PROJECT" ] || [ -z "$SERVICE_NAME" ] || [ -z "$ENVIRONMENT" ]; then
    log_error "Missing required arguments"
    log_error "Required: --customer, --project, --service-name, --environment"
    exit 2
  fi

  # Config path required for create mode
  if [ "$DELETE_MODE" = false ] && [ -z "$CONFIG_PATH" ]; then
    log_error "Missing required argument: --config-path"
    log_error "Config path is required when creating namespaces"
    exit 2
  fi

  # Validate config file exists (for create mode)
  if [ "$DELETE_MODE" = false ] && [ ! -f "$CONFIG_PATH" ]; then
    log_error "Configuration file not found: $CONFIG_PATH"
    exit 4
  fi

  # Validate PSS levels
  for level in "$PSS_ENFORCE" "$PSS_AUDIT" "$PSS_WARN"; do
    if [[ ! "$level" =~ ^(privileged|baseline|restricted)$ ]]; then
      log_error "Invalid PSS level: $level"
      log_error "Valid values: privileged, baseline, restricted"
      exit 2
    fi
  done
  
  # Warn if using namespace override with multiple environments
  if [ -n "$NAMESPACE_OVERRIDE" ] && [[ "$ENVIRONMENT" == *","* ]]; then
    log_warning "Using --namespace override with multiple environments"
    log_warning "The same namespace name will be used for all environments"
    log_warning "This may cause conflicts. Consider using auto-generated names."
  fi
}

# ==============================================================================
# KUBERNETES AUTHENTICATION (v3.0.0)
# ==============================================================================

setup_kubernetes_auth() {
  log_info "Setting up Kubernetes authentication..."
  
  # Detect execution mode and configure accordingly
  if ! detect_kubernetes_context; then
    log_error "Failed to detect Kubernetes context"
    exit 3
  fi
  
  log_info "Execution mode: $EXECUTION_MODE"
  
  # Verify connection
  if ! execute_kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 3
  fi
  
  local k8s_version
  k8s_version=$(execute_kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}' || echo "unknown")
  log_success "Connected to Kubernetes cluster (${k8s_version})"
  
  if [ -n "$KUBECTL_CONTEXT" ]; then
    log_info "Cluster context: $KUBECTL_CONTEXT"
  fi
  if [ -n "$AWS_REGION" ]; then
    log_info "AWS region: $AWS_REGION"
  fi
}

# ==============================================================================
# YAML GENERATION
# ==============================================================================

generate_namespace_yaml() {
  local namespace="$1"
  local customer="$2"
  local project="$3"
  local env="$4"
  local service="$5"
  
  cat <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
  labels:
    # Kubernetes standard labels
    app.kubernetes.io/name: ${service}
    app.kubernetes.io/instance: ${namespace}
    app.kubernetes.io/part-of: ${project}
    app.kubernetes.io/managed-by: forge
    # Forge custom labels
    forge.moai.io/customer: ${customer}
    forge.moai.io/project: ${project}
    forge.moai.io/environment: ${env}
    forge.moai.io/service: ${service}
    # Pod Security Standards
    pod-security.kubernetes.io/enforce: ${PSS_ENFORCE}
    pod-security.kubernetes.io/audit: ${PSS_AUDIT}
    pod-security.kubernetes.io/warn: ${PSS_WARN}
YAML
}

generate_resource_quota_yaml() {
  local namespace="$1"
  local config_file="$2"
  
  log_debug "Reading ResourceQuota from config: $config_file"
  
  # Extract resourceQuota section using yq or parse manually
  if command -v yq &> /dev/null; then
    local quota_spec
    quota_spec=$(yq eval '.resourceQuota' "$config_file" 2>/dev/null)
    
    if [ "$quota_spec" = "null" ] || [ -z "$quota_spec" ]; then
      log_debug "No resourceQuota found in config"
      return 0
    fi
    
    cat <<YAML
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: resource-quota
  namespace: ${namespace}
spec:
$(echo "$quota_spec" | sed 's/^/  /')
YAML
  else
    log_warning "yq not found, skipping ResourceQuota generation"
    log_warning "Install yq: brew install yq"
    return 0
  fi
}

generate_limit_range_yaml() {
  local namespace="$1"
  local config_file="$2"
  
  log_debug "Reading LimitRange from config: $config_file"
  
  if command -v yq &> /dev/null; then
    local limitrange_spec
    limitrange_spec=$(yq eval '.limitRange' "$config_file" 2>/dev/null)
    
    if [ "$limitrange_spec" = "null" ] || [ -z "$limitrange_spec" ]; then
      log_debug "No limitRange found in config"
      return 0
    fi
    
    cat <<YAML
---
apiVersion: v1
kind: LimitRange
metadata:
  name: limit-range
  namespace: ${namespace}
spec:
$(echo "$limitrange_spec" | sed 's/^/  /')
YAML
  else
    log_warning "yq not found, skipping LimitRange generation"
    return 0
  fi
}

# ==============================================================================
# NAMESPACE OPERATIONS
# ==============================================================================

namespace_exists() {
  local namespace="$1"
  execute_kubectl get namespace "$namespace" >/dev/null 2>&1
}

create_namespace() {
  local env="$1"
  local namespace
  namespace=$(get_namespace_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")
  
  log_info "Creating namespace: $namespace"
  log_debug "  PSS Enforce: $PSS_ENFORCE"
  log_debug "  PSS Audit: $PSS_AUDIT"
  log_debug "  PSS Warn: $PSS_WARN"
  
  if namespace_exists "$namespace"; then
    log_warning "Namespace already exists: $namespace"
    
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
      read -p "Update existing namespace? (y/N): " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping namespace update"
        ((TOTAL_SKIPPED++))
        return 0
      fi
    fi
  fi
  
  # Generate complete YAML
  local namespace_yaml
  namespace_yaml=$(generate_namespace_yaml "$namespace" "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")
  
  local quota_yaml
  quota_yaml=$(generate_resource_quota_yaml "$namespace" "$CONFIG_PATH")
  
  local limitrange_yaml
  limitrange_yaml=$(generate_limit_range_yaml "$namespace" "$CONFIG_PATH")
  
  local full_yaml="${namespace_yaml}"
  
  if [ -n "$quota_yaml" ]; then
    full_yaml="${full_yaml}
${quota_yaml}"
  fi
  
  if [ -n "$limitrange_yaml" ]; then
    full_yaml="${full_yaml}
${limitrange_yaml}"
  fi
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would create/update namespace: $namespace"
    log_dry_run "YAML manifest:"
    echo "$full_yaml" | sed 's/^/    /'
    return 0
  fi
  
  # Apply the configuration
  log_debug "Applying YAML configuration..."
  local apply_output
  local apply_exit_code
  
  apply_output=$(echo "$full_yaml" | execute_kubectl apply -f - 2>&1)
  apply_exit_code=$?
  
  if [ $apply_exit_code -eq 0 ]; then
    log_success "Namespace created/updated: $namespace"
    ((TOTAL_CREATED++))
    
    # Show quota status if exists
    if execute_kubectl get resourcequota -n "$namespace" resource-quota >/dev/null 2>&1; then
      local quota_status
      quota_status=$(execute_kubectl get resourcequota -n "$namespace" resource-quota -o json | \
        jq -r '.status.used | to_entries[] | "  \(.key): \(.value)"' 2>/dev/null || echo "  (status unavailable)")
      log_info "Resource quota status:"
      echo "$quota_status"
    fi
    
    return 0
  else
    log_error "Failed to create namespace: $namespace"
    log_error "kubectl output:"
    echo "$apply_output" | sed 's/^/  /' >&2
    ((TOTAL_FAILED++))
    return 1
  fi
}

delete_namespace() {
  local env="$1"
  local namespace
  namespace=$(get_namespace_name "$CUSTOMER" "$PROJECT" "$env" "$SERVICE_NAME")
  
  log_info "Deleting namespace: $namespace"
  
  if ! namespace_exists "$namespace"; then
    log_warning "Namespace does not exist: $namespace"
    ((TOTAL_SKIPPED++))
    return 0
  fi
  
  # Count resources in namespace
  local pod_count
  local svc_count
  local deploy_count
  
  pod_count=$(execute_kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  svc_count=$(execute_kubectl get services -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  deploy_count=$(execute_kubectl get deployments -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  
  if [ "$DRY_RUN" = false ]; then
    echo ""
    log_warning "⚠️  WARNING: This will delete the namespace and ALL resources inside it!"
    echo ""
    log_warning "Namespace: $namespace"
    log_warning "Resources found:"
    log_warning "  - $pod_count Pod(s)"
    log_warning "  - $svc_count Service(s)"
    log_warning "  - $deploy_count Deployment(s)"
    echo ""
    read -p "Type 'yes' to confirm deletion: " -r
    echo ""
    if [[ ! $REPLY =~ ^yes$ ]]; then
      log_info "Deletion cancelled by user"
      exit 0
    fi
  fi
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would delete namespace: $namespace"
    log_dry_run "  $pod_count Pod(s)"
    log_dry_run "  $svc_count Service(s)"
    log_dry_run "  $deploy_count Deployment(s)"
    return 0
  fi
  
  if execute_kubectl delete namespace "$namespace" >/dev/null 2>&1; then
    log_success "Namespace deleted: $namespace"
    ((TOTAL_DELETED++))
    return 0
  else
    log_error "Failed to delete namespace: $namespace"
    ((TOTAL_FAILED++))
    return 1
  fi
}

# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================

configure_environment() {
  local env="$1"
  
  echo ""
  echo "========================================"
  log_info "Processing environment: $env"
  echo "========================================"
  
  if [ "$DELETE_MODE" = true ]; then
    delete_namespace "$env"
  else
    create_namespace "$env"
  fi
  
  echo "========================================"
  return 0
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
  parse_arguments "$@"
  
  print_banner
  
  if [ "$DRY_RUN" = true ]; then
    if [ "$DELETE_MODE" = true ]; then
      log_warning "DRY-RUN MODE: No namespaces will be deleted"
    else
      log_warning "DRY-RUN MODE: No namespaces will be created"
    fi
    echo ""
  fi
  
  if [ "$DELETE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
    log_warning "DELETE MODE: Namespaces will be removed from Kubernetes"
    echo ""
  fi
  
  log_info "Configuration:"
  log_info "  Customer:       $CUSTOMER"
  log_info "  Project:        $PROJECT"
  log_info "  Service:        $SERVICE_NAME"
  log_info "  Environment(s): $ENVIRONMENT"
  
  if [ -n "$NAMESPACE_OVERRIDE" ]; then
    log_info "  Namespace:      $NAMESPACE_OVERRIDE (override)"
  fi
  
  if [ "$DELETE_MODE" = false ]; then
    log_info "  Config Path:    $CONFIG_PATH"
    log_info "  PSS Enforce:    $PSS_ENFORCE"
    log_info "  PSS Audit:      $PSS_AUDIT"
    log_info "  PSS Warn:       $PSS_WARN"
  fi
  echo ""
  
  # Check prerequisites
  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found"
    log_error "Install: brew install kubectl (macOS)"
    exit 1
  fi
  
  if [ "$DELETE_MODE" = false ] && ! command -v yq &> /dev/null; then
    log_warning "yq not found - ResourceQuota and LimitRange will be skipped"
    log_warning "Install: brew install yq (macOS)"
  fi
  
  # Setup Kubernetes authentication
  setup_kubernetes_auth
  echo ""
  
  # Process environments
  IFS=',' read -ra ENV_ARRAY <<< "$ENVIRONMENT"
  
  for env in "${ENV_ARRAY[@]}"; do
    configure_environment "$env"
  done
  
  # Summary
  echo ""
  echo "========================================"
  if [ "$DELETE_MODE" = true ]; then
    echo "      NAMESPACE DELETION SUMMARY       "
  else
    echo "      NAMESPACE CREATION SUMMARY       "
  fi
  echo "========================================"
  log_info "Service: $CUSTOMER/$PROJECT/$SERVICE_NAME"
  echo ""
  
  if [ "$DRY_RUN" = true ]; then
    log_info "Mode: DRY-RUN (no actual changes performed)"
  else
    if [ "$DELETE_MODE" = true ]; then
      log_success "Deleted:  $TOTAL_DELETED namespace(s)"
    else
      log_success "Created:  $TOTAL_CREATED namespace(s)"
    fi
    log_warning "Failed:   $TOTAL_FAILED namespace(s)"
    log_info "Skipped:  $TOTAL_SKIPPED namespace(s)"
  fi
  
  echo "========================================"
  
  if [ "$DELETE_MODE" = false ] && [ "$TOTAL_CREATED" -gt 0 ] && [ "$DRY_RUN" = false ]; then
    log_success "Namespace configuration completed successfully!"
  elif [ "$DELETE_MODE" = true ] && [ "$TOTAL_DELETED" -gt 0 ] && [ "$DRY_RUN" = false ]; then
    log_success "Namespace deletion completed successfully!"
  elif [ "$DRY_RUN" = true ]; then
    log_info "Dry-run completed. Remove --dry-run to apply changes."
  fi
  
  return 0
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

main "$@"
