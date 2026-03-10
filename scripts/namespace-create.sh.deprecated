#!/usr/bin/env bash
#
# namespace-create.sh - Create Forge-managed Kubernetes namespace (UNHARDENED)
#
# Purpose: Creates a namespace with initial labels and PSS baseline enforcement.
#          Does NOT apply ResourceQuota, NetworkPolicy, or Vault bundle.
#          Hardening is performed AFTER deployment using namespace-hardening.sh.
#
# Workflow:
#   1. namespace-create.sh --name my-app --type application
#   2. helm install my-app ./chart -n my-app
#   3. namespace-hardening.sh --name my-app
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

Creates a Forge-managed Kubernetes namespace in UNHARDENED state.
Hardening (ResourceQuota, NetworkPolicy) is applied AFTER deployment.

Required Arguments:
  --name NAME              Namespace name

  --type TYPE              Namespace type. Valid types:
                           - application      (user apps, restricted PSS)
                           - middleware       (databases, baseline PSS)
                           - forge-operator   (KOPF orchestrator, baseline PSS)
                           - forge-jobs       (bash worker jobs, baseline PSS)
                           - vault            (HashiCorp Vault, privileged PSS)
                           - argocd           (GitOps, privileged PSS)
                           - cert-manager     (cert automation, baseline PSS)
                           - privileged       (system workloads, privileged PSS)
                           - keda             (event autoscaler, baseline PSS)
                           - kyverno          (policy engine, baseline PSS)
                           - monitoring       (Prometheus/Grafana, baseline PSS)

Optional Arguments:
  --owner OWNER            Owner/team name (default: unknown)
  --project PROJECT        Project name (default: unknown)
  --environment ENV        Environment (dev/staging/prod, default: unknown)
  --dry-run                Show what would be created without creating
  --skip-pss               Skip Pod Security Standards labels
  --help                   Show this help message

Examples:
  # Create application namespace
  $(basename "$0") --name my-app --type application --owner platform-team

  # Create middleware namespace for database
  $(basename "$0") --name postgres --type middleware --project customer-portal

  # Create forge-operator namespace (global)
  $(basename "$0") --name forge-operator --type forge-operator --owner platform-team

  # Create forge-jobs namespace (per-customer)
  $(basename "$0") --name forge-jobs-acme --type forge-jobs --owner platform-team

  # Dry run (preview)
  $(basename "$0") --name test --type application --dry-run

Workflow:
  1. Create namespace (this script)
  2. Deploy application (helm install, kubectl apply, etc.)
  3. Harden namespace (namespace-hardening.sh)

See also:
  - namespace-hardening.sh  (measure & harden)
  - namespace-verify.sh     (compliance check)
  - namespace-update.sh     (update labels/metadata)
  - namespace-delete.sh     (safe deletion)

EOF
    exit 0
}

#==============================================================================
# ARGUMENT PARSING
#==============================================================================

NAMESPACE=""
NS_TYPE=""
OWNER="unknown"
PROJECT="unknown"
ENVIRONMENT="unknown"
DRY_RUN=false
SKIP_PSS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            NAMESPACE="$2"
            shift 2
            ;;
        --type)
            NS_TYPE="$2"
            shift 2
            ;;
        --owner)
            OWNER="$2"
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-pss)
            SKIP_PSS=true
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

if [[ -z "${NS_TYPE}" ]]; then
    log_error "Namespace type is required (--type)"
    echo ""
    usage
fi

# Validate namespace name (Kubernetes DNS-1123 label)
if ! [[ "${NAMESPACE}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    log_error "Invalid namespace name: '${NAMESPACE}'"
    log_error "Must be lowercase alphanumeric with hyphens (DNS-1123 label)"
    exit 1
fi

# Validate namespace type
if ! validate_namespace_type "${NS_TYPE}"; then
    log_error "Invalid namespace type: '${NS_TYPE}'"
    log_error "Valid types: application, middleware, forge-operator, forge-jobs, vault, argocd, cert-manager, privileged, keda, kyverno, monitoring, default, kube-system"
    exit 1
fi

# Check if namespace already exists
if namespace_exists "${NAMESPACE}"; then
    log_error "Namespace '${NAMESPACE}' already exists"
    exit 1
fi

# Validate environment
if [[ -n "${ENVIRONMENT}" && "${ENVIRONMENT}" != "unknown" ]]; then
    if ! [[ "${ENVIRONMENT}" =~ ^(dev|development|staging|stage|prod|production|test|qa)$ ]]; then
        log_warn "Environment '${ENVIRONMENT}' is not standard (dev/staging/prod/test/qa)"
    fi
fi

#==============================================================================
# PSS LEVEL SELECTION
#==============================================================================

# Determine Pod Security Standards level based on namespace type
PSS_LEVEL="baseline"

case "${NS_TYPE}" in
    application)
        PSS_LEVEL="restricted"
        ;;
    middleware|forge-operator|forge-jobs|cert-manager|keda|kyverno|monitoring)
        PSS_LEVEL="baseline"
        ;;
    vault|argocd|privileged|default|kube-system)
        PSS_LEVEL="privileged"
        ;;
esac

#==============================================================================
# DRY RUN PREVIEW
#==============================================================================

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN - Preview of namespace creation"
    echo ""
    echo "Namespace Configuration:"
    echo "  Name:        ${NAMESPACE}"
    echo "  Type:        ${NS_TYPE}"
    echo "  Owner:       ${OWNER}"
    echo "  Project:     ${PROJECT}"
    echo "  Environment: ${ENVIRONMENT}"
    echo "  PSS Level:   ${PSS_LEVEL}"
    echo ""
    echo "Labels to apply:"
    echo "  moai.forge.io/managed: true"
    echo "  moai.forge.io/type: ${NS_TYPE}"
    echo "  moai.forge.io/owner: ${OWNER}"
    echo "  moai.forge.io/project: ${PROJECT}"
    echo "  moai.forge.io/environment: ${ENVIRONMENT}"
    echo "  moai.forge.io/hardened: false"
    echo "  moai.forge.io/created-at: $(date -u +%Y%m%d-%H%M%S)"
    echo ""
    if [[ "${SKIP_PSS}" == "false" ]]; then
        echo "PSS Labels:"
        echo "  pod-security.kubernetes.io/enforce: ${PSS_LEVEL}"
        echo "  pod-security.kubernetes.io/audit: ${PSS_LEVEL}"
        echo "  pod-security.kubernetes.io/warn: ${PSS_LEVEL}"
        echo ""
    fi
    echo "ResourceQuota: NOT APPLIED (unhardened state)"
    echo "NetworkPolicy: NOT APPLIED (unhardened state)"
    echo "Vault Bundle:  NOT APPLIED (unhardened state)"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy application: helm install ${NAMESPACE} ./chart -n ${NAMESPACE}"
    echo "  2. Harden namespace:   ./namespace-hardening.sh --name ${NAMESPACE}"
    echo ""
    log_success "Dry run complete (no changes made)"
    exit 0
fi

#==============================================================================
# NAMESPACE CREATION
#==============================================================================

log_info "Creating namespace '${NAMESPACE}' with type '${NS_TYPE}'..."
echo ""

# Create namespace manifest
NAMESPACE_MANIFEST=$(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    moai.forge.io/managed: "true"
    moai.forge.io/type: "${NS_TYPE}"
    moai.forge.io/owner: "${OWNER}"
    moai.forge.io/project: "${PROJECT}"
    moai.forge.io/environment: "${ENVIRONMENT}"
    moai.forge.io/hardened: "false"
    moai.forge.io/created-at: "$(date -u +%Y%m%d-%H%M%S)"
EOF
)

# Add PSS labels if not skipped
if [[ "${SKIP_PSS}" == "false" ]]; then
    NAMESPACE_MANIFEST+=$(cat <<EOF

    pod-security.kubernetes.io/enforce: "${PSS_LEVEL}"
    pod-security.kubernetes.io/audit: "${PSS_LEVEL}"
    pod-security.kubernetes.io/warn: "${PSS_LEVEL}"
EOF
)
fi

# Apply namespace
echo "${NAMESPACE_MANIFEST}" | kubectl apply -f -

if [[ $? -ne 0 ]]; then
    log_error "Failed to create namespace '${NAMESPACE}'"
    exit 1
fi

# Wait a moment for namespace to be fully created
sleep 1

#==============================================================================
# VERIFICATION
#==============================================================================

# Verify namespace was created
if ! namespace_exists "${NAMESPACE}"; then
    log_error "Namespace '${NAMESPACE}' was not created successfully"
    exit 1
fi

# Verify labels
ACTUAL_TYPE=$(get_namespace_type "${NAMESPACE}")
if [[ "${ACTUAL_TYPE}" != "${NS_TYPE}" ]]; then
    log_error "Namespace type mismatch: expected '${NS_TYPE}', got '${ACTUAL_TYPE}'"
    exit 1
fi

ACTUAL_HARDENED=$(get_namespace_label "${NAMESPACE}" "hardened")
if [[ "${ACTUAL_HARDENED}" != "false" ]]; then
    log_error "Namespace hardening flag should be 'false', got '${ACTUAL_HARDENED}'"
    exit 1
fi

#==============================================================================
# SUCCESS OUTPUT
#==============================================================================

echo ""
log_success "Namespace '${NAMESPACE}' created successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Namespace Details:"
echo "   Name:        ${NAMESPACE}"
echo "   Type:        ${NS_TYPE}"
echo "   Owner:       ${OWNER}"
echo "   Project:     ${PROJECT}"
echo "   Environment: ${ENVIRONMENT}"
echo "   PSS Level:   ${PSS_LEVEL}"
echo "   Hardened:    ❌ NO (unhardened state)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  IMPORTANT: This namespace is NOT HARDENED"
echo ""
echo "   ❌ No ResourceQuota applied"
echo "   ❌ No NetworkPolicy applied"
echo "   ❌ No Vault bundle created"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Next Steps:"
echo ""
echo "   1️⃣  Deploy your application to the namespace:"
echo ""
echo "      # Using Helm"
echo "      helm install ${NAMESPACE} ./chart -n ${NAMESPACE}"
echo ""
echo "      # Or using kubectl"
echo "      kubectl apply -f deployment.yaml -n ${NAMESPACE}"
echo ""
echo "   2️⃣  Harden the namespace (can be done IMMEDIATELY after deployment):"
echo ""
echo "      ./namespace-hardening.sh --name ${NAMESPACE}"
echo ""
echo "      💡 No waiting needed! We use MAXIMUM values (HPA maxReplicas,"
echo "         VPA upperBound, max nodes for DaemonSets), not current usage."
echo ""
echo "   3️⃣  Verify compliance:"
echo ""
echo "      ./namespace-verify.sh --name ${NAMESPACE}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 Documentation:"
echo "   - Architecture: docs/NAMESPACE_OPERATIONS_V2.md"
echo "   - Workflows:    docs/NAMESPACE_WORKFLOWS.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
