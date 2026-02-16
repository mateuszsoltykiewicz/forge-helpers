#!/bin/bash
# ==============================================================================
# Generic AWS IAM IRSA Role Configuration Script
# ==============================================================================
# Description: Creates AWS IAM roles for Kubernetes Service Accounts (IRSA)
# Version: 2.0.0
# Compatible: bash 3.2+ (macOS compatible)
# ==============================================================================

set -e

# ==============================================================================
# SCRIPT METADATA
# ==============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# ==============================================================================
# DEFAULT CONFIGURATION
# ==============================================================================

DEFAULT_AWS_REGION="eu-central-1"

# ==============================================================================
# GLOBAL VARIABLES (set by parse_arguments)
# ==============================================================================

CUSTOMER=""
PROJECT=""
SERVICE_NAME=""
ENVIRONMENT=""
CLUSTER_NAME=""
POLICY_FILE=""

# AWS Configuration
AWS_REGION="${AWS_REGION:-$DEFAULT_AWS_REGION}"
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_ACCOUNT_ID=""

# Kubernetes Configuration
OIDC_ISSUER=""
OIDC_ID=""
OIDC_ARN=""

# Control Flags
DRY_RUN=false
FORCE=false
VERBOSE=false
UPDATE_EXISTING=false
DELETE_MODE=false

# Statistics
TOTAL_CREATED=0
TOTAL_UPDATED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
TOTAL_DELETED=0

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
  NC='\033[0m'
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
  echo -e "${CYAN}[DRY RUN]${NC} $*"
}

# ==============================================================================
# NAMING CONVENTION FUNCTIONS
# ==============================================================================

get_irsa_role_name() {
  local customer="$1"
  local project="$2"
  local env="$3"
  local service="$4"
  # Convert to PascalCase: SanofiCronusDevVideoCallingIrsa
  local customer_pascal=$(echo "$customer" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
  local project_pascal=$(echo "$project" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
  local env_pascal=$(echo "$env" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
  # Handle hyphenated service names: video-calling -> VideoCalling
  local service_pascal=$(echo "$service" | awk -F'-' '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1)) tolower(substr($i,2))}')
  echo "${customer_pascal}${project_pascal}${env_pascal}${service_pascal}Irsa"
}

get_irsa_policy_name() {
  local customer="$1"
  local project="$2"
  local env="$3"
  local service="$4"
  echo "$(get_irsa_role_name "$customer" "$project" "$env" "$service")Policy"
}

get_service_account_name() {
  local customer="$1"
  local project="$2"
  local env="$3"
  local service="$4"
  echo "${customer}-${project}-${env}-${service}-sa"
}

get_kubernetes_namespace() {
  local customer="$1"
  local project="$2"
  local env="$3"
  local service="$4"
  echo "${customer}-${project}-${env}-${service}"
}

# ==============================================================================
# HELP & USAGE
# ==============================================================================

print_banner() {
  cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║   Generic AWS IAM IRSA Role Configuration Script            ║
║                       Version 2.0.0                          ║
╚══════════════════════════════════════════════════════════════╝
EOF
  echo ""
}

print_version() {
  echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

print_usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

DESCRIPTION:
  Creates or deletes AWS IAM roles for Kubernetes Service Accounts (IRSA).
  Configures OIDC trust policies and attaches IAM policies for EKS workloads.

REQUIRED ARGUMENTS:
  --customer CUSTOMER           Customer name (e.g., sanofi)
  --project PROJECT             Project name (e.g., cronus)
  --service-name SERVICE        Service name (e.g., video-calling)
  --environment ENVIRONMENT     Environment (e.g., dev, staging, prod)
  --cluster-name CLUSTER        EKS cluster name

REQUIRED FOR CREATION:
  --policy-file PATH            Path to IAM policy JSON file (not needed for --delete)

OPTIONAL ARGUMENTS:
  --aws-region REGION           AWS region (default: $DEFAULT_AWS_REGION)
  --aws-profile PROFILE         AWS CLI profile name
  --aws-account-id ACCOUNT      AWS account ID (auto-detected)
  --update-existing             Update existing role policy
  --delete                      Delete IAM role and policy instead of creating
  --dry-run                     Show what would be done
  --force                       Skip confirmation prompts
  --verbose                     Enable verbose output
  --help                        Display this help message
  --version                     Display script version

EXAMPLES:
  # Basic usage
  $SCRIPT_NAME \\
    --customer sanofi \\
    --project cronus \\
    --service-name video-calling \\
    --environment dev \\
    --cluster-name indegene-eks \\
    --policy-file ./policies/video-calling-policy.json

  # With AWS profile
  $SCRIPT_NAME \\
    --customer sanofi \\
    --project cronus \\
    --service-name video-calling \\
    --environment prod \\
    --cluster-name indegene-eks \\
    --policy-file ./policies/video-calling-policy.json \\
    --aws-profile production

  # Delete IAM role and policy
  $SCRIPT_NAME \\
    --customer sanofi \\
    --project cronus \\
    --service-name video-calling \\
    --environment dev \\
    --cluster-name indegene-eks \\
    --delete

  # Delete with dry-run
  $SCRIPT_NAME \\
    --customer sanofi \\
    --project cronus \\
    --service-name video-calling \\
    --environment dev \\
    --cluster-name indegene-eks \\
    --delete \\
    --dry-run

NAMING CONVENTION:
  IAM Role:       {Customer}{Project}{Env}{Service}Irsa (PascalCase)
  IAM Policy:     {Customer}{Project}{Env}{Service}IrsaPolicy
  ServiceAccount: {customer}-{project}-{env}-{service}-sa
  Namespace:      {customer}-{project}-{env}-{service}

  Example: SanofiCronusDevVideoCallingIrsa

EXIT CODES:
  0 - Success
  1 - General error
  2 - Invalid arguments
  3 - AWS API error
  4 - Policy file error
  5 - OIDC provider not configured

VERSION:
  ${SCRIPT_VERSION}
EOF
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
      --cluster-name)
        CLUSTER_NAME="$2"
        shift 2
        ;;
      --policy-file)
        POLICY_FILE="$2"
        shift 2
        ;;
      --aws-region)
        AWS_REGION="$2"
        shift 2
        ;;
      --aws-profile)
        AWS_PROFILE="$2"
        shift 2
        ;;
      --aws-account-id)
        AWS_ACCOUNT_ID="$2"
        shift 2
        ;;
      --update-existing)
        UPDATE_EXISTING=true
        shift
        ;;
      --delete)
        DELETE_MODE=true
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
      *)
        log_error "Unknown option: $1"
        echo ""
        print_usage
        exit 2
        ;;
    esac
  done

  # Validate required arguments
  if [ -z "$CUSTOMER" ] || [ -z "$PROJECT" ] || [ -z "$SERVICE_NAME" ] || [ -z "$ENVIRONMENT" ] || [ -z "$CLUSTER_NAME" ]; then
    log_error "Missing required arguments"
    log_error "Required: --customer, --project, --service-name, --environment, --cluster-name"
    exit 2
  fi

  # Validate policy file exists (only required for creation, not deletion)
  if [ "$DELETE_MODE" != true ]; then
    if [ -z "$POLICY_FILE" ]; then
      log_error "Missing required argument: --policy-file"
      log_error "(Not required when using --delete)"
      exit 2
    fi
    
    if [ ! -f "$POLICY_FILE" ]; then
      log_error "Policy file not found: $POLICY_FILE"
      exit 4
    fi

    # Validate policy file is valid JSON
    if ! jq empty "$POLICY_FILE" 2>/dev/null; then
      log_error "Invalid JSON in policy file: $POLICY_FILE"
      exit 4
    fi
  fi
}

# ==============================================================================
# AWS FUNCTIONS
# ==============================================================================

get_aws_account_id() {
  if [ -n "$AWS_ACCOUNT_ID" ]; then
    return 0
  fi

  log_info "Retrieving AWS account ID..."
  
  local aws_cmd="aws sts get-caller-identity --query Account --output text --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if ! AWS_ACCOUNT_ID=$(eval "$aws_cmd" 2>&1); then
    log_error "Failed to retrieve AWS account ID"
    exit 3
  fi
  
  log_success "AWS account ID: $AWS_ACCOUNT_ID"
}

get_oidc_provider() {
  log_info "Retrieving OIDC provider for cluster: $CLUSTER_NAME"
  
  local aws_cmd="aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.identity.oidc.issuer' --output text"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if ! OIDC_ISSUER=$(eval "$aws_cmd" 2>&1); then
    log_error "Failed to retrieve OIDC issuer for cluster: $CLUSTER_NAME"
    exit 5
  fi
  
  if [ -z "$OIDC_ISSUER" ] || [ "$OIDC_ISSUER" = "None" ]; then
    log_error "OIDC provider not configured for cluster: $CLUSTER_NAME"
    exit 5
  fi
  
  OIDC_ID=$(echo "$OIDC_ISSUER" | sed "s|https://oidc.eks.${AWS_REGION}.amazonaws.com/id/||")
  OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}"
  
  log_success "OIDC ARN: $OIDC_ARN"
}

# ==============================================================================
# IAM FUNCTIONS
# ==============================================================================

generate_trust_policy() {
  local namespace="$1"
  local service_account="$2"
  
  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:${namespace}:${service_account}",
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

role_exists() {
  local role_name="$1"
  
  local aws_cmd="aws iam get-role --role-name $role_name --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  eval "$aws_cmd" >/dev/null 2>&1
}

policy_exists() {
  local policy_name="$1"
  
  local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
  local aws_cmd="aws iam get-policy --policy-arn $policy_arn --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  eval "$aws_cmd" >/dev/null 2>&1
}

create_iam_role() {
  local role_name="$1"
  local trust_policy="$2"
  
  log_info "Creating IAM role: $role_name"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would create IAM role: $role_name"
    return 0
  fi
  
  local aws_cmd="aws iam create-role --role-name $role_name --assume-role-policy-document '$trust_policy' --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "IAM role created: $role_name"
    ((TOTAL_CREATED++))
  else
    log_error "Failed to create IAM role: $role_name"
    ((TOTAL_FAILED++))
    return 1
  fi
}

create_iam_policy() {
  local policy_name="$1"
  
  log_info "Creating IAM policy: $policy_name"
  log_debug "Policy file: $POLICY_FILE"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would create IAM policy: $policy_name from $POLICY_FILE"
    return 0
  fi
  
  local aws_cmd="aws iam create-policy --policy-name $policy_name --policy-document file://$POLICY_FILE --region $AWS_REGION --query 'Policy.Arn' --output text"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  local policy_arn
  if policy_arn=$(eval "$aws_cmd" 2>&1); then
    log_success "IAM policy created: $policy_name"
    log_debug "Policy ARN: $policy_arn"
    echo "$policy_arn"
    ((TOTAL_CREATED++))
  else
    log_error "Failed to create IAM policy: $policy_name"
    ((TOTAL_FAILED++))
    return 1
  fi
}

attach_policy_to_role() {
  local role_name="$1"
  local policy_arn="$2"
  
  log_info "Attaching policy to role"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would attach policy to role: $role_name"
    return 0
  fi
  
  local aws_cmd="aws iam attach-role-policy --role-name $role_name --policy-arn $policy_arn --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "Policy attached to role"
    ((TOTAL_UPDATED++))
  else
    log_error "Failed to attach policy to role"
    ((TOTAL_FAILED++))
    return 1
  fi
}

get_role_arn() {
  local role_name="$1"
  
  local aws_cmd="aws iam get-role --role-name $role_name --region $AWS_REGION --query 'Role.Arn' --output text"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  eval "$aws_cmd" 2>/dev/null
}

detach_policy_from_role() {
  local role_name="$1"
  local policy_arn="$2"
  
  log_info "Detaching policy from role: $role_name"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would detach policy: $policy_arn"
    log_dry_run "From role: $role_name"
    return 0
  fi
  
  local aws_cmd="aws iam detach-role-policy --role-name $role_name --policy-arn $policy_arn --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "Policy detached from role"
    return 0
  else
    log_warning "Failed to detach policy from role (may not be attached)"
    return 1
  fi
}

delete_iam_role() {
  local role_name="$1"
  
  log_info "Deleting IAM role: $role_name"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would delete IAM role: $role_name"
    return 0
  fi
  
  local aws_cmd="aws iam delete-role --role-name $role_name --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "IAM role deleted: $role_name"
    ((TOTAL_DELETED++))
  else
    log_error "Failed to delete IAM role: $role_name"
    ((TOTAL_FAILED++))
    return 1
  fi
}

delete_iam_policy() {
  local policy_name="$1"
  
  log_info "Deleting IAM policy: $policy_name"
  
  local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
  
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "Would delete IAM policy: $policy_name"
    log_dry_run "Policy ARN: $policy_arn"
    return 0
  fi
  
  local aws_cmd="aws iam delete-policy --policy-arn $policy_arn --region $AWS_REGION"
  
  if [ -n "$AWS_PROFILE" ]; then
    aws_cmd="$aws_cmd --profile $AWS_PROFILE"
  fi
  
  if eval "$aws_cmd" >/dev/null 2>&1; then
    log_success "IAM policy deleted: $policy_name"
    ((TOTAL_DELETED++))
  else
    log_error "Failed to delete IAM policy: $policy_name"
    ((TOTAL_FAILED++))
    return 1
  fi
}

# ==============================================================================
# MAIN CONFIGURATION LOGIC
# ==============================================================================

configure_irsa() {
  local role_name
  local policy_name
  local service_account
  local namespace
  local trust_policy
  local policy_arn
  local role_arn
  
  # Generate resource names
  role_name=$(get_irsa_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  policy_name=$(get_irsa_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  service_account=$(get_service_account_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  namespace=$(get_kubernetes_namespace "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  
  log_info "IRSA Configuration for: $CUSTOMER/$PROJECT/$ENVIRONMENT/$SERVICE_NAME"
  log_info "  IAM Role:        $role_name"
  log_info "  IAM Policy:      $policy_name"
  log_info "  ServiceAccount:  $service_account"
  log_info "  Namespace:       $namespace"
  log_info "  Policy File:     $POLICY_FILE"
  echo ""
  
  # Generate trust policy
  trust_policy=$(generate_trust_policy "$namespace" "$service_account")
  
  # Check if role already exists
  if role_exists "$role_name"; then
    if [ "$UPDATE_EXISTING" = true ]; then
      log_warning "Role already exists: $role_name (will update policy)"
      ((TOTAL_SKIPPED++))
    else
      log_error "Role already exists: $role_name"
      log_error "Use --update-existing to update the policy"
      ((TOTAL_SKIPPED++))
      return 1
    fi
  else
    # Confirmation prompt (unless --force or --dry-run)
    if [ "$FORCE" != true ] && [ "$DRY_RUN" != true ]; then
      echo ""
      log_warning "This will create IAM role and policy in AWS account: $AWS_ACCOUNT_ID"
      read -p "Continue? (y/N): " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 6
      fi
    fi
    
    # Create IAM role
    if ! create_iam_role "$role_name" "$trust_policy"; then
      return 1
    fi
  fi
  
  # Check if policy already exists
  if policy_exists "$policy_name"; then
    log_warning "Policy already exists: $policy_name (using existing)"
    policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    ((TOTAL_SKIPPED++))
  else
    # Create IAM policy from file
    if ! policy_arn=$(create_iam_policy "$policy_name"); then
      return 1
    fi
  fi
  
  # Attach policy to role
  if [ "$DRY_RUN" != true ]; then
    if ! attach_policy_to_role "$role_name" "$policy_arn"; then
      return 1
    fi
    
    # Get and display role ARN
    role_arn=$(get_role_arn "$role_name")
    if [ -n "$role_arn" ]; then
      echo ""
      log_success "Role ARN: $role_arn"
      echo ""
      log_info "To use this role, add this annotation to your ServiceAccount:"
      echo "  eks.amazonaws.com/role-arn: $role_arn"
    fi
  fi
  
  return 0
}

delete_irsa() {
  local role_name
  local policy_name
  local service_account
  local namespace
  local policy_arn
  
  # Generate resource names
  role_name=$(get_irsa_role_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  policy_name=$(get_irsa_policy_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  service_account=$(get_service_account_name "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  namespace=$(get_kubernetes_namespace "$CUSTOMER" "$PROJECT" "$ENVIRONMENT" "$SERVICE_NAME")
  policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
  
  log_info "IRSA Deletion for: $CUSTOMER/$PROJECT/$ENVIRONMENT/$SERVICE_NAME"
  log_info "  IAM Role:        $role_name"
  log_info "  IAM Policy:      $policy_name"
  log_info "  ServiceAccount:  $service_account"
  log_info "  Namespace:       $namespace"
  echo ""
  
  # Check if role exists
  if ! role_exists "$role_name"; then
    log_warning "Role does not exist: $role_name"
    ((TOTAL_SKIPPED++))
  else
    # Confirmation prompt (unless --force or --dry-run)
    if [ "$FORCE" != true ] && [ "$DRY_RUN" != true ]; then
      echo ""
      log_warning "This will DELETE IAM role and policy from AWS account: $AWS_ACCOUNT_ID"
      log_warning "Role: $role_name"
      log_warning "Policy: $policy_name"
      read -p "Are you sure? (y/N): " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 6
      fi
    fi
    
    # Detach policy from role (if attached)
    if policy_exists "$policy_name"; then
      detach_policy_from_role "$role_name" "$policy_arn"
    fi
    
    # Delete IAM role
    if ! delete_iam_role "$role_name"; then
      log_error "Failed to delete role, skipping policy deletion"
      return 1
    fi
  fi
  
  # Check if policy exists and delete it
  if ! policy_exists "$policy_name"; then
    log_warning "Policy does not exist: $policy_name"
    ((TOTAL_SKIPPED++))
  else
    if ! delete_iam_policy "$policy_name"; then
      return 1
    fi
  fi
  
  return 0
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
  parse_arguments "$@"
  
  print_banner
  
  # Get AWS account ID
  get_aws_account_id
  
  # Get OIDC provider info (only needed for creation, not deletion)
  if [ "$DELETE_MODE" != true ]; then
    get_oidc_provider
  fi
  
  # Delete or Configure IRSA
  if [ "$DELETE_MODE" = true ]; then
    # Delete mode
    if delete_irsa; then
      echo ""
      log_success "=== IRSA deletion completed successfully ==="
      
      if [ "$DRY_RUN" != true ]; then
        echo ""
        log_info "Statistics:"
        log_info "  Deleted: $TOTAL_DELETED"
        log_info "  Skipped: $TOTAL_SKIPPED"
        log_info "  Failed:  $TOTAL_FAILED"
      fi
    else
      echo ""
      log_error "=== IRSA deletion failed ==="
      exit 1
    fi
  else
    # Create/update mode
    if configure_irsa; then
      echo ""
      log_success "=== IRSA configuration completed successfully ==="
      
      if [ "$DRY_RUN" != true ]; then
        echo ""
        log_info "Statistics:"
        log_info "  Created: $TOTAL_CREATED"
        log_info "  Updated: $TOTAL_UPDATED"
        log_info "  Skipped: $TOTAL_SKIPPED"
        log_info "  Failed:  $TOTAL_FAILED"
      fi
    else
      echo ""
      log_error "=== IRSA configuration failed ==="
      exit 1
    fi
  fi
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

main "$@"
