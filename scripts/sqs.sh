#!/bin/bash

################################################################################
# SQS Queue Management Script
################################################################################
# Purpose:
#   Provision, verify, and manage AWS SQS FIFO queues with zero-config approach.
#   Supports IRSA for EKS workloads and local AWS credentials.
#
# Features:
#   - FIFO queues with KMS encryption at rest
#   - Auto-discovery of EKS cluster, region, VPC endpoints
#   - Multi-service IRSA support (comma-separated service names)
#   - In-cluster (IRSA) and local execution modes
#   - Producer (write) and Consumer (read) access types
#   - Message testing (send/receive) for verification
#   - SSM Parameter Store integration
#
# Usage:
#   ./scripts/sqs.sh provision --customer customer --project project --environment prod \
#     --purpose videocalling-events --service-names application-api,application-agent \
#     --access-type producer [--dry-run] [--verbose]
#
#   ./scripts/sqs.sh verify --customer customer --project project --environment prod \
#     --purpose videocalling-events --access-type producer [--verbose]
#
#   ./scripts/sqs.sh delete --customer customer --project project --environment prod \
#     --purpose videocalling-events [--delete-kms] [--dry-run] [--verbose]
#
# Naming Convention:
#   Queue: {customer}-{project}-{environment}-{purpose}.fifo
#   Example: customer-project-prod-videocalling-events.fifo
#
# Requirements:
#   - AWS CLI configured with appropriate credentials
#   - jq (JSON processor)
#   - For in-cluster mode: running inside EKS pod with IRSA
#
# Author: Forge Platform Team
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Script directory and library imports
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source required libraries
source "${LIB_DIR}/forge-core.sh"
source "${LIB_DIR}/forge-patterns.sh"
source "${LIB_DIR}/forge-aws-discovery.sh"
source "${LIB_DIR}/forge-sqs-operations.sh"

################################################################################
# Global variables
################################################################################

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="1.0.0"

# Operation mode
MODE=""  # provision, verify, delete

# Required parameters
CUSTOMER=""
PROJECT=""
ENVIRONMENT=""
PURPOSE=""

# Service specifications (array of "name:access_type" entries)
SERVICES=()

# Optional parameters
MESSAGE_RETENTION_PERIOD="345600"  # 4 days in seconds (default)
VISIBILITY_TIMEOUT="30"  # 30 seconds (default)
RECEIVE_WAIT_TIME="20"  # Long polling 20s (default)
CONTENT_BASED_DEDUPLICATION="true"  # Enable for FIFO (default)

# Flags
DRY_RUN=false
VERBOSE=false
DELETE_KMS=false

# Auto-discovered values (will be populated during execution)
EXECUTION_MODE=""  # in-cluster or local
REGION=""
ACCOUNT_ID=""
EKS_CLUSTER_NAME=""
OIDC_PROVIDER_ARN=""
VPC_ENDPOINT_ID=""
KMS_KEY_ID=""
QUEUE_URL=""
QUEUE_ARN=""

################################################################################
# Functions
################################################################################

#######################################
# Display usage information
# Globals:
#   SCRIPT_NAME
# Arguments:
#   None
# Outputs:
#   Usage information to stdout
#######################################
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} <mode> [options]

Modes:
    provision       Create SQS FIFO queue with KMS encryption and IRSA policies
    verify          Verify queue access and test message send/receive
    delete          Delete SQS queue and optionally KMS key

Options:
    Required:
        --customer <name>           Customer name (e.g., customer)
        --project <name>            Project name (e.g., project)
        --environment <name>        Environment name (e.g., dev, staging, prod)
        --purpose <name>            Queue purpose (e.g., videocalling-events)
        --service <name:access>     Service with access type (repeatable)
                                    Format: service-name:producer|consumer
                                    Examples:
                                      --service application-api:consumer
                                      --service application-agent:producer
                                    Required for provision mode (at least one)

    Optional:
        --message-retention <sec>   Message retention period in seconds (60-1209600)
                                    Default: 345600 (4 days)
        
        --visibility-timeout <sec>  Visibility timeout in seconds (0-43200)
                                    Default: 30
        
        --receive-wait-time <sec>   Long polling wait time in seconds (0-20)
                                    Default: 20
        
        --content-dedup <bool>      Enable content-based deduplication (true/false)
                                    Default: true

    Flags:
        --dry-run                   Show what would be done without making changes
        --verbose                   Enable verbose output
        --delete-kms                Delete KMS key when deleting queue (delete mode only)
        --help                      Display this help message

Examples:
    # Provision queue for producer service
    ${SCRIPT_NAME} provision \\
        --customer customer \\
        --project project \\
        --environment prod \\
        --purpose videocalling-events \\
        --service-names application-api \\
        --access-type producer \\
        --verbose

    # Provision queue for multiple consumer services
    ${SCRIPT_NAME} provision \\
        --customer customer \\
        --project project \\
        --environment prod \\
        --purpose videocalling-events \\
        --service-names application-agent,notification-service \\
        --access-type consumer

    # Verify queue access (dry-run)
    ${SCRIPT_NAME} verify \\
        --customer customer \\
        --project project \\
        --environment prod \\
        --purpose videocalling-events \\
        --access-type producer \\
        --dry-run

    # Delete queue and KMS key
    ${SCRIPT_NAME} delete \\
        --customer customer \\
        --project project \\
        --environment prod \\
        --purpose videocalling-events \\
        --delete-kms \\
        --verbose

Queue Naming:
    {customer}-{project}-{environment}-{purpose}.fifo
    Example: customer-project-prod-videocalling-events.fifo

IRSA Role Naming:
    {Customer}{Project}{Environment}{Service}Irsa (PascalCase)
    Example: customerprojectProdVideoCallingApiIrsa

ServiceAccount Naming:
    {customer}-{project}-{environment}-{service}-sa (kebab-case)
    Example: customer-project-prod-application-api-sa

Access Types:
    producer    - Grants SendMessage permission
    consumer    - Grants ReceiveMessage, DeleteMessage, ChangeMessageVisibility permissions

Execution Modes:
    in-cluster  - Running inside EKS pod, uses IRSA for authentication
    local       - Running locally, uses AWS credentials from environment

EOF
    exit 0
}

#######################################
# Parse command line arguments
# Globals:
#   MODE, CUSTOMER, PROJECT, ENVIRONMENT, PURPOSE, SERVICE_NAMES, ACCESS_TYPE,
#   MESSAGE_RETENTION_PERIOD, VISIBILITY_TIMEOUT, RECEIVE_WAIT_TIME,
#   CONTENT_BASED_DEDUPLICATION, DRY_RUN, VERBOSE, DELETE_KMS
# Arguments:
#   $@ - All command line arguments
# Returns:
#   0 on success, exits on error
#######################################
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        echo "Error: No arguments provided"
        echo ""
        usage
    fi

    # First argument is the mode
    MODE="$1"
    shift

    # Validate mode
    if [[ ! "${MODE}" =~ ^(provision|verify|delete)$ ]]; then
        echo "Error: Invalid mode '${MODE}'. Must be: provision, verify, or delete"
        usage
    fi

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --customer)
                CUSTOMER="$2"
                shift 2
                ;;
            --project)
                PROJECT="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --purpose)
                PURPOSE="$2"
                shift 2
                ;;
            --service)
                SERVICES+=("$2")
                shift 2
                ;;
            --message-retention)
                MESSAGE_RETENTION_PERIOD="$2"
                shift 2
                ;;
            --visibility-timeout)
                VISIBILITY_TIMEOUT="$2"
                shift 2
                ;;
            --receive-wait-time)
                RECEIVE_WAIT_TIME="$2"
                shift 2
                ;;
            --content-dedup)
                CONTENT_BASED_DEDUPLICATION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --delete-kms)
                DELETE_KMS=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                echo "Error: Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${CUSTOMER}" ]]; then
        echo "Error: --customer is required"
        exit "${EXIT_ERROR_MISSING_PARAMETER}"
    fi

    if [[ -z "${PROJECT}" ]]; then
        echo "Error: --project is required"
        exit "${EXIT_ERROR_MISSING_PARAMETER}"
    fi

    if [[ -z "${ENVIRONMENT}" ]]; then
        echo "Error: --environment is required"
        exit "${EXIT_ERROR_MISSING_PARAMETER}"
    fi

    if [[ -z "${PURPOSE}" ]]; then
        echo "Error: --purpose is required"
        exit "${EXIT_ERROR_MISSING_PARAMETER}"
    fi

    # Mode-specific validation
    if [[ "${MODE}" == "provision" ]] && [[ ${#SERVICES[@]} -eq 0 ]]; then
        echo "Error: At least one --service is required for provision mode"
        exit "${EXIT_ERROR_MISSING_PARAMETER}"
    fi
    
    if [[ "${MODE}" == "verify" ]] && [[ ${#SERVICES[@]} -ne 1 ]]; then
        echo "Error: Exactly one --service is required for verify mode"
        echo "Verify mode tests access for a specific service"
        exit "${EXIT_ERROR_INVALID_PARAMETER}"
    fi
    
    # Validate service specifications format
    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        for service_spec in "${SERVICES[@]}"; do
            if [[ ! "$service_spec" =~ ^[a-zA-Z0-9_-]+:(producer|consumer)$ ]]; then
                echo "Error: Invalid --service format: '$service_spec'"
                echo "Expected format: service-name:producer or service-name:consumer"
                exit "${EXIT_ERROR_INVALID_PARAMETER}"
            fi
        done
    fi

    # Validate numeric parameters
    if ! is_valid_message_retention "${MESSAGE_RETENTION_PERIOD}"; then
        echo "Error: Invalid message retention period: ${MESSAGE_RETENTION_PERIOD}"
        echo "Must be between 60 and 1209600 seconds (1 minute to 14 days)"
        exit "${EXIT_ERROR_INVALID_PARAMETER}"
    fi

    if ! is_valid_visibility_timeout "${VISIBILITY_TIMEOUT}"; then
        echo "Error: Invalid visibility timeout: ${VISIBILITY_TIMEOUT}"
        echo "Must be between 0 and 43200 seconds (12 hours)"
        exit "${EXIT_ERROR_INVALID_PARAMETER}"
    fi

    # Validate boolean parameters
    if [[ ! "${CONTENT_BASED_DEDUPLICATION}" =~ ^(true|false)$ ]]; then
        echo "Error: --content-dedup must be 'true' or 'false', got: ${CONTENT_BASED_DEDUPLICATION}"
        exit "${EXIT_ERROR_INVALID_PARAMETER}"
    fi
}

#######################################
# Initialize environment and auto-discover AWS resources
# Globals:
#   EXECUTION_MODE, REGION, ACCOUNT_ID, EKS_CLUSTER_NAME, OIDC_PROVIDER_ARN,
#   VPC_ENDPOINT_ID, CUSTOMER, PROJECT, ENVIRONMENT, VERBOSE
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
initialize_environment() {
    log_info "Initializing environment..."

    # Check prerequisites
    check_jq_installed
    check_aws_sqs_permissions

    # Determine execution mode
    EXECUTION_MODE=$(get_execution_mode)
    log_info "Execution mode: ${EXECUTION_MODE}"

    # Discover AWS region
    REGION=$(get_aws_region)
    log_info "AWS Region: ${REGION}"

    # Discover AWS account ID
    ACCOUNT_ID=$(get_aws_account_id)
    log_info "AWS Account ID: ${ACCOUNT_ID}"

    # Discover EKS cluster (if in-cluster mode)
    if [[ "${EXECUTION_MODE}" == "in-cluster" ]]; then
        EKS_CLUSTER_NAME=$(discover_eks_cluster_by_naming_convention "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}")
        log_info "EKS Cluster: ${EKS_CLUSTER_NAME}"

        # Get OIDC provider ARN for IRSA
        OIDC_PROVIDER_ARN=$(get_eks_oidc_provider_arn "${EKS_CLUSTER_NAME}" "${REGION}" "${ACCOUNT_ID}")
        log_info "OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"
    else
        log_info "Skipping EKS discovery (local execution mode)"
    fi

    # Verify VPC endpoint for SQS (optional, warn if not found)
    if verify_vpc_endpoint_sqs "${CUSTOMER}" "${PROJECT}" "${REGION}"; then
        local vpc_endpoint_name
        vpc_endpoint_name=$(get_vpc_endpoint_name_sqs "${CUSTOMER}" "${PROJECT}")
        VPC_ENDPOINT_ID=$(get_vpc_endpoint_id "${vpc_endpoint_name}" "${REGION}")
        log_info "VPC Endpoint for SQS: ${VPC_ENDPOINT_ID} (${vpc_endpoint_name})"
    else
        local vpc_endpoint_name
        vpc_endpoint_name=$(get_vpc_endpoint_name_sqs "${CUSTOMER}" "${PROJECT}")
        log_warning "VPC Endpoint for SQS not found: ${vpc_endpoint_name}"
        log_warning "Queue will use public SQS endpoints"
    fi

    log_success "Environment initialization complete"
}

#######################################
# Provision SQS FIFO queue with KMS encryption and IRSA policies
# Globals:
#   CUSTOMER, PROJECT, ENVIRONMENT, PURPOSE, SERVICE_NAMES, ACCESS_TYPE,
#   MESSAGE_RETENTION_PERIOD, VISIBILITY_TIMEOUT, RECEIVE_WAIT_TIME,
#   CONTENT_BASED_DEDUPLICATION, REGION, ACCOUNT_ID, EKS_CLUSTER_NAME,
#   OIDC_PROVIDER_ARN, DRY_RUN, VERBOSE
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
provision_queue() {
    log_step "Provisioning SQS Queue"

    # Generate queue name
    local queue_name
    queue_name=$(get_queue_name "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${PURPOSE}")
    log_info "Queue name: ${queue_name}"

    # Validate queue name
    if ! is_valid_queue_name "${queue_name}"; then
        echo "Error: Invalid queue name: ${queue_name}"
        exit "${EXIT_ERROR_SQS}"
    fi

    # Check if queue already exists
    if queue_exists "${queue_name}" "${REGION}"; then
        log_warning "Queue already exists: ${queue_name}"
        
        # Get existing queue details
        QUEUE_URL=$(get_queue_url "${queue_name}" "${REGION}")
        QUEUE_ARN=$(get_queue_arn "${QUEUE_URL}" "${REGION}")
        
        log_info "Queue URL: ${QUEUE_URL}"
        log_info "Queue ARN: ${QUEUE_ARN}"
        
        # Update IRSA policies for existing queue
        if [[ ${#SERVICES[@]} -gt 0 ]]; then
            log_info "Updating IRSA policies for existing queue..."
            
            if [[ "${DRY_RUN}" == true ]]; then
                log_info "[DRY-RUN] Would update IRSA policies for ${#SERVICES[@]} service(s)"
                for service_spec in "${SERVICES[@]}"; do
                    IFS=':' read -r service_name access_type <<< "$service_spec"
                    log_info "[DRY-RUN]   - ${service_name}: ${access_type}"
                done
            else
                configure_queue_irsa_policies
            fi
        fi
        
        log_success "Queue provisioning complete (existing queue)"
        return 0
    fi

    # Step 1: Create or retrieve KMS key
    log_info "Step 1: Setting up KMS encryption key..."
    
    local kms_key_alias
    kms_key_alias=$(get_kms_key_alias "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}")
    
    if kms_key_exists "${kms_key_alias}" "${REGION}"; then
        KMS_KEY_ID=$(get_kms_key_id "${kms_key_alias}" "${REGION}")
        log_info "Using existing KMS key: ${kms_key_alias} (${KMS_KEY_ID})"
    else
        if [[ "${DRY_RUN}" == true ]]; then
            log_info "[DRY-RUN] Would create KMS key: ${kms_key_alias}"
            KMS_KEY_ID="arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/00000000-0000-0000-0000-000000000000"
        else
            KMS_KEY_ID=$(create_kms_key_for_sqs \
                "${CUSTOMER}" \
                "${PROJECT}" \
                "${ENVIRONMENT}" \
                "${REGION}")
            
            log_success "Created KMS key: ${kms_key_alias} (${KMS_KEY_ID})"
            
            # Store KMS key ID in SSM
            local ssm_kms_path
            ssm_kms_path=$(get_sqs_kms_key_id_path "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}")
            store_kms_key_id_in_ssm "${ssm_kms_path}" "${KMS_KEY_ID}" "${REGION}"
        fi
    fi

    # Step 2: Create FIFO queue
    log_info "Step 2: Creating FIFO queue..."
    
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would create queue: ${queue_name}"
        log_info "[DRY-RUN] Message retention: ${MESSAGE_RETENTION_PERIOD}s"
        log_info "[DRY-RUN] Visibility timeout: ${VISIBILITY_TIMEOUT}s"
        log_info "[DRY-RUN] Receive wait time: ${RECEIVE_WAIT_TIME}s"
        log_info "[DRY-RUN] Content-based deduplication: ${CONTENT_BASED_DEDUPLICATION}"
        log_info "[DRY-RUN] KMS encryption: ${KMS_KEY_ID}"
        
        QUEUE_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/${queue_name}"
        QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:${queue_name}"
    else
        QUEUE_URL=$(create_fifo_queue \
            "${queue_name}" \
            "${KMS_KEY_ID}" \
            "${REGION}" \
            "${MESSAGE_RETENTION_PERIOD}" \
            "${VISIBILITY_TIMEOUT}" \
            "${CONTENT_BASED_DEDUPLICATION}")
        
        QUEUE_ARN=$(get_queue_arn "${QUEUE_URL}" "${REGION}")
        
        log_success "Created queue: ${queue_name}"
        log_info "Queue URL: ${QUEUE_URL}"
        log_info "Queue ARN: ${QUEUE_ARN}"
        
        # Store queue URL in SSM
        local ssm_queue_path
        ssm_queue_path=$(get_sqs_queue_url_path "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${PURPOSE}")
        store_queue_url_in_ssm "${ssm_queue_path}" "${QUEUE_URL}" "${REGION}"
    fi

    # Step 3: Generate and attach IRSA policies
    log_info "Step 3: Configuring IRSA policies..."
    
    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            log_info "[DRY-RUN] Would configure IRSA for ${#SERVICES[@]} service(s):"
            for service_spec in "${SERVICES[@]}"; do
                IFS=':' read -r service_name access_type <<< "$service_spec"
                log_info "[DRY-RUN]   - ${service_name}: ${access_type}"
            done
            
            # In verbose mode, show what the policy would look like
            if [[ "${VERBOSE}" == true ]]; then
                local service_specs_with_arns=()
                for service_spec in "${SERVICES[@]}"; do
                    IFS=':' read -r service_name access_type <<< "$service_spec"
                    local irsa_role_arn
                    irsa_role_arn=$(get_sqs_irsa_role_arn "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${service_name}" "${REGION}" "${ACCOUNT_ID}")
                    log_debug "[DRY-RUN] IRSA Role for ${service_name}: ${irsa_role_arn}"
                    service_specs_with_arns+=("${service_name}:${access_type}:${irsa_role_arn}")
                done
                
                local policy_json
                policy_json=$(generate_merged_queue_policy "${QUEUE_ARN}" "${service_specs_with_arns[@]}")
                log_info "[DRY-RUN] Generated policy document:"
                echo "${policy_json}" | jq '.'
            fi
        else
            configure_queue_irsa_policies
        fi
    else
        log_info "No services provided, skipping IRSA policy configuration"
    fi

    log_success "Queue provisioning complete"
    
    # Display summary
    log_step "Provisioning Summary"
    echo "Queue Name:       ${queue_name}"
    echo "Queue URL:        ${QUEUE_URL}"
    echo "Queue ARN:        ${QUEUE_ARN}"
    echo "KMS Key ID:       ${KMS_KEY_ID}"
    echo "Execution Mode:   ${EXECUTION_MODE}"
    
    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        echo "IRSA Services:"
        for service_spec in "${SERVICES[@]}"; do
            IFS=':' read -r service_name access_type <<< "$service_spec"
            echo "  - ${service_name} (${access_type})"
        done
    fi
}

#######################################
# Configure IRSA policies for queue (initial creation)
# Globals:
#   SERVICES, QUEUE_ARN, QUEUE_URL, REGION, ACCOUNT_ID,
#   CUSTOMER, PROJECT, ENVIRONMENT, VERBOSE
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
configure_queue_irsa_policies() {
    local service_specs_with_arns=()
    
    # Build array of service specifications with IRSA ARNs
    # Format: "service-name:access-type:irsa-arn"
    for service_spec in "${SERVICES[@]}"; do
        IFS=':' read -r service_name access_type <<< "$service_spec"
        
        local irsa_role_arn
        irsa_role_arn=$(get_sqs_irsa_role_arn "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${service_name}" "${REGION}" "${ACCOUNT_ID}")
        
        log_info "IRSA Role for ${service_name} (${access_type}): ${irsa_role_arn}"
        
        # Add to array with full specification
        service_specs_with_arns+=("${service_name}:${access_type}:${irsa_role_arn}")
    done
    
    # Generate merged queue policy document
    local policy_json
    policy_json=$(generate_merged_queue_policy "${QUEUE_ARN}" "${service_specs_with_arns[@]}")
    
    if [[ "${VERBOSE}" == true ]]; then
        log_info "Generated policy document:"
        echo "${policy_json}" | jq '.'
    fi
    
    # Attach policy to queue
    attach_queue_policy "${QUEUE_URL}" "${policy_json}" "${REGION}"
    
    log_success "IRSA policies configured for ${#SERVICES[@]} service(s)"
}

#######################################
# Update IRSA policies for existing queue
# Globals:
#   SERVICE_NAMES, ACCESS_TYPE, QUEUE_URL, QUEUE_ARN, REGION, ACCOUNT_ID,
#   CUSTOMER, PROJECT, ENVIRONMENT
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
update_queue_irsa_policies() {
    local service_array
    IFS=',' read -ra service_array <<< "${SERVICE_NAMES}"
    
    # Get current policy
    local current_policy
    current_policy=$(get_current_policy "${QUEUE_URL}" "${REGION}")
    
    if [[ "${VERBOSE}" == true ]]; then
        log_info "Current policy:"
        echo "${current_policy}" | jq '.'
    fi
    
    # Add each IRSA role to policy
    for service in "${service_array[@]}"; do
        local irsa_role_arn
        # Use get_sqs_irsa_role_arn which internally uses get_irsa_role_name (PascalCase)
        irsa_role_arn=$(get_sqs_irsa_role_arn "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${service}" "${REGION}" "${ACCOUNT_ID}")
        
        log_info "Adding IRSA role to policy: ${irsa_role_arn}"
        
        current_policy=$(add_irsa_to_policy \
            "${current_policy}" \
            "${QUEUE_ARN}" \
            "${ACCESS_TYPE}" \
            "${irsa_role_arn}")
    done
    
    if [[ "${VERBOSE}" == true ]]; then
        log_info "Updated policy:"
        echo "${current_policy}" | jq '.'
    fi
    
    # Attach updated policy
    attach_queue_policy "${QUEUE_URL}" "${current_policy}" "${REGION}"
    
    log_success "IRSA policies updated for ${#service_array[@]} service(s)"
}

#######################################
# Verify SQS queue access and test message send/receive
# Globals:
#   CUSTOMER, PROJECT, ENVIRONMENT, PURPOSE, ACCESS_TYPE, REGION, DRY_RUN
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
verify_queue() {
    log_step "Verifying SQS Queue"

    # Parse service specification (verify requires exactly one)
    local service_name
    local access_type
    IFS=':' read -r service_name access_type <<< "${SERVICES[0]}"
    
    log_info "Service: ${service_name}"
    log_info "Access type: ${access_type}"

    # Generate queue name
    local queue_name
    queue_name=$(get_queue_name "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${PURPOSE}")
    log_info "Queue name: ${queue_name}"

    # Check if queue exists
    if ! queue_exists "${queue_name}" "${REGION}"; then
        echo "Error: Queue does not exist: ${queue_name}"
        exit "${EXIT_ERROR_QUEUE_NOT_FOUND}"
    fi

    # Get queue details
    QUEUE_URL=$(get_queue_url "${queue_name}" "${REGION}")
    QUEUE_ARN=$(get_queue_arn "${QUEUE_URL}" "${REGION}")
    
    log_info "Queue URL: ${QUEUE_URL}"
    log_info "Queue ARN: ${QUEUE_ARN}"

    # Get queue attributes
    log_info "Retrieving queue attributes..."
    local attributes
    attributes=$(get_queue_attributes "${QUEUE_URL}" "${REGION}")
    
    if [[ "${VERBOSE}" == true ]]; then
        log_info "Queue attributes:"
        echo "${attributes}" | jq '.'
    fi

    # Extract key attributes
    local approx_messages
    local approx_messages_not_visible
    local created_timestamp
    
    approx_messages=$(echo "${attributes}" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
    approx_messages_not_visible=$(echo "${attributes}" | jq -r '.Attributes.ApproximateNumberOfMessagesNotVisible // "0"')
    created_timestamp=$(echo "${attributes}" | jq -r '.Attributes.CreatedTimestamp // "unknown"')
    
    log_info "Messages in queue: ${approx_messages}"
    log_info "Messages in flight: ${approx_messages_not_visible}"
    log_info "Created at: $(date -r "${created_timestamp}" 2>/dev/null || echo "${created_timestamp}")"

    # Test message operations based on access type
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would test ${access_type} access to queue for service: ${service_name}"
    else
        if [[ "${access_type}" == "producer" ]]; then
            log_info "Testing producer access (send message)..."
            test_producer_access
        elif [[ "${access_type}" == "consumer" ]]; then
            log_info "Testing consumer access (receive message)..."
            test_consumer_access
        fi
    fi

    log_success "Queue verification complete"
    
    # Display summary
    log_step "Verification Summary"
    echo "Queue Name:              ${queue_name}"
    echo "Queue URL:               ${QUEUE_URL}"
    echo "Messages Available:      ${approx_messages}"
    echo "Messages In Flight:      ${approx_messages_not_visible}"
    echo "Service Tested:          ${service_name}"
    echo "Access Type Tested:      ${access_type}"
}

#######################################
# Test producer access by sending a test message
# Globals:
#   QUEUE_URL, REGION
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
test_producer_access() {
    local test_message="Test message from sqs.sh verify mode - $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local message_group_id="test-group"
    local deduplication_id="test-$(date +%s)-$$"
    
    log_info "Sending test message..."
    log_info "Message: ${test_message}"
    
    local message_id
    message_id=$(send_test_message \
        "${QUEUE_URL}" \
        "${test_message}" \
        "${message_group_id}" \
        "${deduplication_id}" \
        "${REGION}")
    
    if [[ -n "${message_id}" ]]; then
        log_success "Test message sent successfully"
        log_info "Message ID: ${message_id}"
    else
        echo "Error: Failed to send test message"
        exit "${EXIT_ERROR_QUEUE_ACCESS_DENIED}"
    fi
}

#######################################
# Test consumer access by receiving messages
# Globals:
#   QUEUE_URL, REGION
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
test_consumer_access() {
    local max_messages=1
    local wait_time=5  # Shorter wait for testing
    
    log_info "Attempting to receive messages (wait time: ${wait_time}s)..."
    
    local messages
    messages=$(receive_test_message \
        "${QUEUE_URL}" \
        "${max_messages}" \
        "${wait_time}" \
        "${REGION}")
    
    local message_count
    message_count=$(echo "${messages}" | jq -r '.Messages | length')
    
    if [[ "${message_count}" -gt 0 ]]; then
        log_success "Received ${message_count} message(s)"
        
        if [[ "${VERBOSE}" == true ]]; then
            log_info "Message details:"
            echo "${messages}" | jq -r '.Messages[] | "Body: \(.Body)\nMessageId: \(.MessageId)\nReceiptHandle: \(.ReceiptHandle)"'
        else
            local body
            body=$(echo "${messages}" | jq -r '.Messages[0].Body')
            log_info "Message body: ${body}"
        fi
        
        # Optionally delete the received message
        local receipt_handle
        receipt_handle=$(echo "${messages}" | jq -r '.Messages[0].ReceiptHandle')
        
        log_info "Deleting test message..."
        if aws sqs delete-message \
            --queue-url "${QUEUE_URL}" \
            --receipt-handle "${receipt_handle}" \
            --region "${REGION}" >/dev/null 2>&1; then
            log_success "Test message deleted"
        else
            log_warning "Failed to delete test message"
        fi
    else
        log_warning "No messages available in queue (this is normal if queue is empty)"
        log_info "Consumer access permissions verified (no errors during receive attempt)"
    fi
}

#######################################
# Delete SQS queue and optionally KMS key
# Globals:
#   CUSTOMER, PROJECT, ENVIRONMENT, PURPOSE, REGION, DELETE_KMS, DRY_RUN
# Arguments:
#   None
# Returns:
#   0 on success, exits on error
#######################################
delete_queue() {
    log_step "Deleting SQS Queue"

    # Generate queue name
    local queue_name
    queue_name=$(get_queue_name "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${PURPOSE}")
    log_info "Queue name: ${queue_name}"

    # Check if queue exists
    if ! queue_exists "${queue_name}" "${REGION}"; then
        log_warning "Queue does not exist: ${queue_name}"
        log_info "Nothing to delete"
        return 0
    fi

    # Get queue URL
    QUEUE_URL=$(get_queue_url "${queue_name}" "${REGION}")
    log_info "Queue URL: ${QUEUE_URL}"

    # Delete queue
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would delete queue: ${queue_name}"
    else
        log_warning "Deleting queue: ${queue_name}"
        
        if delete_queue_internal "${QUEUE_URL}" "${REGION}"; then
            log_success "Queue deleted successfully"
        else
            echo "Error: Failed to delete queue"
            exit "${EXIT_ERROR_SQS}"
        fi
        
        # Remove from SSM
        local ssm_queue_path
        ssm_queue_path=$(get_sqs_queue_url_path "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}" "${PURPOSE}")
        
        log_info "Removing queue URL from SSM: ${ssm_queue_path}"
        if aws ssm delete-parameter \
            --name "${ssm_queue_path}" \
            --region "${REGION}" >/dev/null 2>&1; then
            log_success "Queue URL removed from SSM"
        else
            log_warning "Failed to remove queue URL from SSM (may not exist)"
        fi
    fi

    # Delete KMS key if requested
    if [[ "${DELETE_KMS}" == true ]]; then
        log_info "Deleting KMS key..."
        delete_kms_key_for_queue
    else
        log_info "Skipping KMS key deletion (use --delete-kms to delete)"
    fi

    log_success "Queue deletion complete"
}

#######################################
# Delete KMS key for queue
# Globals:
#   CUSTOMER, PROJECT, ENVIRONMENT, REGION, DRY_RUN
# Arguments:
#   None
# Returns:
#   0 on success, logs warning on error
#######################################
delete_kms_key_for_queue() {
    local kms_key_alias
    kms_key_alias=$(get_kms_key_alias "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}")
    
    if ! kms_key_exists "${kms_key_alias}" "${REGION}"; then
        log_warning "KMS key does not exist: ${kms_key_alias}"
        return 0
    fi
    
    local kms_key_id
    kms_key_id=$(get_kms_key_id "${kms_key_alias}" "${REGION}")
    
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would schedule KMS key deletion: ${kms_key_alias} (${kms_key_id})"
    else
        log_warning "Scheduling KMS key deletion: ${kms_key_alias} (${kms_key_id})"
        log_warning "Key will be deleted after 30-day waiting period"
        
        if delete_kms_key "${kms_key_id}" 30 "${REGION}"; then
            log_success "KMS key deletion scheduled"
        else
            log_warning "Failed to schedule KMS key deletion"
        fi
        
        # Remove from SSM
        local ssm_kms_path
        ssm_kms_path=$(get_sqs_kms_key_id_path "${CUSTOMER}" "${PROJECT}" "${ENVIRONMENT}")
        
        log_info "Removing KMS key ID from SSM: ${ssm_kms_path}"
        if aws ssm delete-parameter \
            --name "${ssm_kms_path}" \
            --region "${REGION}" >/dev/null 2>&1; then
            log_success "KMS key ID removed from SSM"
        else
            log_warning "Failed to remove KMS key ID from SSM (may not exist)"
        fi
    fi
}

#######################################
# Internal function to delete queue (wrapper for library function)
# Arguments:
#   $1 - Queue URL
#   $2 - AWS region
# Returns:
#   0 on success, 1 on error
#######################################
delete_queue_internal() {
    local queue_url="$1"
    local region="$2"
    
    delete_queue "${queue_url}" "${region}"
}

#######################################
# Main function
# Globals:
#   MODE
# Arguments:
#   $@ - All command line arguments
# Returns:
#   0 on success, exits on error
#######################################
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Display script header (uppercase mode for display)
    local mode_upper
    mode_upper=$(echo "${MODE}" | tr '[:lower:]' '[:upper:]')
    log_step "SQS Queue Management - ${mode_upper} Mode"
    
    if [[ "${DRY_RUN}" == true ]]; then
        log_warning "DRY-RUN MODE: No changes will be made"
    fi

    # Initialize environment
    initialize_environment

    # Execute mode-specific operation
    case "${MODE}" in
        provision)
            provision_queue
            ;;
        verify)
            verify_queue
            ;;
        delete)
            delete_queue
            ;;
        *)
            echo "Error: Unknown mode: ${MODE}"
            exit "${EXIT_ERROR_INVALID_PARAMETER}"
            ;;
    esac

    log_step "Operation Complete"
    exit 0
}

################################################################################
# Script execution
################################################################################

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
