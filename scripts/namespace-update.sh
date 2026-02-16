#!/usr/bin/env bash
#
# namespace-update.sh - Update Forge-managed namespace labels and metadata
#
# Purpose: Updates namespace labels without affecting hardening resources
#          (ResourceQuota, NetworkPolicy remain unchanged).
#
# Author: Forge Platform Team
# License: Proprietary
# Version: 2.0.0

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# shellcheck source=lib/forge-core.sh
source "${LIB_DIR}/forge-core.sh"
# shellcheck source=lib/forge-namespace-operations.sh
source "${LIB_DIR}/forge-namespace-operations.sh"

#==============================================================================
# USAGE
#==============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Updates labels and metadata for a Forge-managed namespace.
Does NOT modify hardening resources (ResourceQuota, NetworkPolicy).

Required Arguments:
  --name NAME              Namespace name

Optional Arguments:
  --owner OWNER            Update owner label
  --project PROJECT        Update project label
  --environment ENV        Update environment label
  --add-label KEY=VALUE    Add/update custom label (can be repeated)
  --remove-label KEY       Remove custom label (can be repeated)
  --dry-run                Show what would be changed without applying
  --help                   Show this help message

Examples:
  # Update owner
  $(basename "$0") --name my-app --owner new-team

  # Update multiple metadata fields
  $(basename "$0") --name my-app --owner platform-team --project customer-portal --environment prod

  # Add custom labels
  $(basename "$0") --name my-app --add-label "cost-center=engineering" --add-label "sla=high"

  # Remove custom label
  $(basename "$0") --name my-app --remove-label "cost-center"

  # Dry run (preview changes)
  $(basename "$0") --name my-app --owner new-team --dry-run

Notes:
  - Cannot modify namespace type (immutable)
  - Cannot modify hardening status (use namespace-hardening.sh)
  - Only managed namespaces (moai.forge.io/managed=true) can be updated
  - Custom labels must use prefix other than 'moai.forge.io/' or 'pod-security.kubernetes.io/'

See also:
  - namespace-create.sh     (create namespace)
  - namespace-hardening.sh  (measure & harden)
  - namespace-verify.sh     (compliance check)

EOF
    exit 0
}

#==============================================================================
# ARGUMENT PARSING
#==============================================================================

NAMESPACE=""
NEW_OWNER=""
NEW_PROJECT=""
NEW_ENVIRONMENT=""
LABELS_TO_ADD=()
LABELS_TO_REMOVE=()
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            NAMESPACE="$2"
            shift 2
            ;;
        --owner)
            NEW_OWNER="$2"
            shift 2
            ;;
        --project)
            NEW_PROJECT="$2"
            shift 2
            ;;
        --environment)
            NEW_ENVIRONMENT="$2"
            shift 2
            ;;
        --add-label)
            LABELS_TO_ADD+=("$2")
            shift 2
            ;;
        --remove-label)
            LABELS_TO_REMOVE+=("$2")
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown argument: $1"
            echo ""
            usage
            ;;
    esac
done

#==============================================================================
# VALIDATION
#==============================================================================

if [[ -z "${NAMESPACE}" ]]; then
    log_error "Namespace name is required (--name)"
    echo ""
    usage
fi

# Check if namespace exists
if ! namespace_exists "${NAMESPACE}"; then
    log_error "Namespace '${NAMESPACE}' does not exist"
    exit 1
fi

# Check if namespace is managed
MANAGED=$(get_namespace_label "${NAMESPACE}" "managed")
if [[ "${MANAGED}" != "true" ]]; then
    log_error "Namespace '${NAMESPACE}' is not managed by Forge (moai.forge.io/managed != true)"
    log_error "Only Forge-managed namespaces can be updated with this script"
    exit 1
fi

# Validate custom labels don't use reserved prefixes
for label in "${LABELS_TO_ADD[@]}"; do
    label_key="${label%%=*}"
    
    if [[ "${label_key}" == moai.forge.io/* ]]; then
        log_error "Cannot add label with reserved prefix 'moai.forge.io/': ${label_key}"
        log_error "Use --owner, --project, or --environment for Forge metadata"
        exit 1
    fi
    
    if [[ "${label_key}" == pod-security.kubernetes.io/* ]]; then
        log_error "Cannot add label with reserved prefix 'pod-security.kubernetes.io/': ${label_key}"
        log_error "PSS labels are managed automatically by namespace-create.sh"
        exit 1
    fi
done

# Check if any update was requested
if [[ -z "${NEW_OWNER}" && -z "${NEW_PROJECT}" && -z "${NEW_ENVIRONMENT}" && \
      ${#LABELS_TO_ADD[@]} -eq 0 && ${#LABELS_TO_REMOVE[@]} -eq 0 ]]; then
    log_error "No updates specified"
    log_error "Use --owner, --project, --environment, --add-label, or --remove-label"
    echo ""
    usage
fi

#==============================================================================
# GET CURRENT VALUES
#==============================================================================

CURRENT_OWNER=$(get_namespace_label "${NAMESPACE}" "owner")
CURRENT_PROJECT=$(get_namespace_label "${NAMESPACE}" "project")
CURRENT_ENVIRONMENT=$(get_namespace_label "${NAMESPACE}" "environment")
CURRENT_TYPE=$(get_namespace_type "${NAMESPACE}")
CURRENT_HARDENED=$(get_namespace_label "${NAMESPACE}" "hardened")

#==============================================================================
# DRY RUN PREVIEW
#==============================================================================

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN - Preview of namespace updates"
    echo ""
    echo "Namespace: ${NAMESPACE}"
    echo ""
    echo "Current Values:"
    echo "  Type:        ${CURRENT_TYPE} (immutable)"
    echo "  Owner:       ${CURRENT_OWNER}"
    echo "  Project:     ${CURRENT_PROJECT}"
    echo "  Environment: ${CURRENT_ENVIRONMENT}"
    echo "  Hardened:    ${CURRENT_HARDENED} (managed by namespace-hardening.sh)"
    echo ""
    echo "Proposed Changes:"
    
    if [[ -n "${NEW_OWNER}" ]]; then
        echo "  Owner:       ${CURRENT_OWNER} → ${NEW_OWNER}"
    fi
    
    if [[ -n "${NEW_PROJECT}" ]]; then
        echo "  Project:     ${CURRENT_PROJECT} → ${NEW_PROJECT}"
    fi
    
    if [[ -n "${NEW_ENVIRONMENT}" ]]; then
        echo "  Environment: ${CURRENT_ENVIRONMENT} → ${NEW_ENVIRONMENT}"
    fi
    
    if [[ ${#LABELS_TO_ADD[@]} -gt 0 ]]; then
        echo ""
        echo "Labels to add/update:"
        for label in "${LABELS_TO_ADD[@]}"; do
            echo "  + ${label}"
        done
    fi
    
    if [[ ${#LABELS_TO_REMOVE[@]} -gt 0 ]]; then
        echo ""
        echo "Labels to remove:"
        for label in "${LABELS_TO_REMOVE[@]}"; do
            echo "  - ${label}"
        done
    fi
    
    echo ""
    log_success "Dry run complete (no changes made)"
    exit 0
fi

#==============================================================================
# APPLY UPDATES
#==============================================================================

log_info "Updating namespace '${NAMESPACE}'..."
echo ""

# Build label arguments
LABEL_ARGS=()

if [[ -n "${NEW_OWNER}" ]]; then
    LABEL_ARGS+=("moai.forge.io/owner=${NEW_OWNER}")
    log_info "Updating owner: ${CURRENT_OWNER} → ${NEW_OWNER}"
fi

if [[ -n "${NEW_PROJECT}" ]]; then
    LABEL_ARGS+=("moai.forge.io/project=${NEW_PROJECT}")
    log_info "Updating project: ${CURRENT_PROJECT} → ${NEW_PROJECT}"
fi

if [[ -n "${NEW_ENVIRONMENT}" ]]; then
    LABEL_ARGS+=("moai.forge.io/environment=${NEW_ENVIRONMENT}")
    log_info "Updating environment: ${CURRENT_ENVIRONMENT} → ${NEW_ENVIRONMENT}"
fi

# Add custom labels
for label in "${LABELS_TO_ADD[@]}"; do
    LABEL_ARGS+=("${label}")
    log_info "Adding label: ${label}"
done

# Apply label updates
if [[ ${#LABEL_ARGS[@]} -gt 0 ]]; then
    if ! apply_namespace_labels "${NAMESPACE}" "${LABEL_ARGS[@]}"; then
        log_error "Failed to apply label updates"
        exit 1
    fi
fi

# Remove labels
for label_key in "${LABELS_TO_REMOVE[@]}"; do
    log_info "Removing label: ${label_key}"
    kubectl label namespace "${NAMESPACE}" "${label_key}-" 2>/dev/null || true
done

#==============================================================================
# VERIFICATION
#==============================================================================

# Verify updates were applied
if [[ -n "${NEW_OWNER}" ]]; then
    ACTUAL_OWNER=$(get_namespace_label "${NAMESPACE}" "owner")
    if [[ "${ACTUAL_OWNER}" != "${NEW_OWNER}" ]]; then
        log_error "Owner update verification failed: expected '${NEW_OWNER}', got '${ACTUAL_OWNER}'"
        exit 1
    fi
fi

if [[ -n "${NEW_PROJECT}" ]]; then
    ACTUAL_PROJECT=$(get_namespace_label "${NAMESPACE}" "project")
    if [[ "${ACTUAL_PROJECT}" != "${NEW_PROJECT}" ]]; then
        log_error "Project update verification failed: expected '${NEW_PROJECT}', got '${ACTUAL_PROJECT}'"
        exit 1
    fi
fi

if [[ -n "${NEW_ENVIRONMENT}" ]]; then
    ACTUAL_ENVIRONMENT=$(get_namespace_label "${NAMESPACE}" "environment")
    if [[ "${ACTUAL_ENVIRONMENT}" != "${NEW_ENVIRONMENT}" ]]; then
        log_error "Environment update verification failed: expected '${NEW_ENVIRONMENT}', got '${ACTUAL_ENVIRONMENT}'"
        exit 1
    fi
fi

#==============================================================================
# SUCCESS OUTPUT
#==============================================================================

echo ""
log_success "Namespace '${NAMESPACE}' updated successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Updated Namespace Details:"
echo "   Name:        ${NAMESPACE}"
echo "   Type:        ${CURRENT_TYPE}"
echo "   Owner:       $(get_namespace_label "${NAMESPACE}" "owner")"
echo "   Project:     $(get_namespace_label "${NAMESPACE}" "project")"
echo "   Environment: $(get_namespace_label "${NAMESPACE}" "environment")"
echo "   Hardened:    ${CURRENT_HARDENED}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Notes:"
echo "   - Hardening resources (ResourceQuota, NetworkPolicy) were NOT modified"
echo "   - Namespace type cannot be changed (immutable)"
echo "   - To verify compliance: ./namespace-verify.sh --name ${NAMESPACE}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
