#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Chart Generator Script
# ==============================================================================
# Description:
#   Generate Helm charts from raw Kubernetes YAML manifests.
#   Converts plain K8s resources into structured, parameterized Helm charts.
#
# Usage:
#   helm-generate.sh --input FILE --output DIR --chart NAME [options]
#
# Examples:
#   # Generate chart from k8s manifests
#   helm-generate.sh --input app.yaml --output ./charts --chart myapp
#
#   # Generate with custom versions
#   helm-generate.sh --input app.yaml --output ./charts --chart myapp \
#     --chart-version 1.0.0 --app-version 2.3.4
#
#   # Generate with common-library integration
#   helm-generate.sh --input app.yaml --output ./charts --chart myapp \
#     --use-common-library
#
#   # Dry-run mode
#   helm-generate.sh --input app.yaml --output ./charts --chart myapp --dry-run
#
# Author: Forge Team
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"

# Default values
INPUT_FILE=""
OUTPUT_DIR="."
CHART_NAME=""
CHART_VERSION="0.1.0"
APP_VERSION="1.0.0"
CHART_DESCRIPTION="A Helm chart for Kubernetes"
USE_COMMON_LIBRARY=false
DRY_RUN=false
VERBOSE=false
OUTPUT_FORMAT="text"

# ==============================================================================
# SOURCE DEPENDENCIES
# ==============================================================================

source "${LIB_DIR}/forge-core.sh"
source "${LIB_DIR}/forge-patterns.sh"
source "${LIB_DIR}/forge-helm-generator.sh"

# ==============================================================================
# USAGE FUNCTION
# ==============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") --input FILE --output DIR --chart NAME [options]

Generate Helm charts from Kubernetes YAML manifests.

Required Arguments:
  --input FILE              Input YAML file with K8s resources
  --output DIR              Output directory for generated chart
  --chart NAME              Name of the chart to generate

Optional Arguments:
  --chart-version VERSION   Chart version (default: ${CHART_VERSION})
  --app-version VERSION     Application version (default: ${APP_VERSION})
  --description TEXT        Chart description
  --use-common-library      Add common-library as dependency
  --dry-run                 Preview without creating files
  --verbose                 Enable verbose output
  --format FORMAT           Output format: text, json, yaml (default: text)
  -h, --help                Show this help message

Examples:
  # Basic chart generation
  $(basename "$0") --input app.yaml --output ./charts --chart myapp

  # With custom versions
  $(basename "$0") --input app.yaml --output ./charts --chart myapp \\
    --chart-version 1.0.0 --app-version 2.3.4

  # With common-library integration
  $(basename "$0") --input app.yaml --output ./charts --chart myapp \\
    --use-common-library

Environment Variables:
  FORGE_LOG_LEVEL          Set log level (DEBUG, INFO, WARN, ERROR)

EOF
    exit 0
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                INPUT_FILE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --chart)
                CHART_NAME="$2"
                shift 2
                ;;
            --chart-version)
                CHART_VERSION="$2"
                shift 2
                ;;
            --app-version)
                APP_VERSION="$2"
                shift 2
                ;;
            --description)
                CHART_DESCRIPTION="$2"
                shift 2
                ;;
            --use-common-library)
                USE_COMMON_LIBRARY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                export FORGE_LOG_LEVEL="DEBUG"
                shift
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                ;;
        esac
    done
}

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

validate_arguments() {
    log_debug "Validating arguments..."
    
    # Check required arguments
    if [[ -z "${INPUT_FILE}" ]]; then
        log_error "Missing required argument: --input"
        exit 1
    fi
    
    if [[ -z "${OUTPUT_DIR}" ]]; then
        log_error "Missing required argument: --output"
        exit 1
    fi
    
    if [[ -z "${CHART_NAME}" ]]; then
        log_error "Missing required argument: --chart"
        exit 1
    fi
    
    # Validate input file exists
    if [[ ! -f "${INPUT_FILE}" ]]; then
        log_error "Input file not found: ${INPUT_FILE}"
        exit 1
    fi
    
    # Validate output directory is writable
    if [[ ! -d "${OUTPUT_DIR}" ]]; then
        log_info "Creating output directory: ${OUTPUT_DIR}"
        mkdir -p "${OUTPUT_DIR}" || {
            log_error "Failed to create output directory: ${OUTPUT_DIR}"
            exit 1
        }
    fi
    
    # Validate chart name
    if ! validate_helm_release_name "${CHART_NAME}"; then
        log_error "Invalid chart name: ${CHART_NAME}"
        log_error "Chart names must be DNS-1123 compliant (lowercase, max 53 chars)"
        exit 1
    fi
    
    # Check if chart already exists
    if [[ -d "${OUTPUT_DIR}/${CHART_NAME}" ]] && [[ "${DRY_RUN}" == "false" ]]; then
        log_warn "Chart directory already exists: ${OUTPUT_DIR}/${CHART_NAME}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted by user"
            exit 0
        fi
    fi
    
    log_success "Validation passed"
}

# ==============================================================================
# CHART GENERATION FUNCTIONS
# ==============================================================================

# Add common-library dependency to Chart.yaml
add_common_library_dependency() {
    local chart_dir="$1"
    
    log_info "Adding common-library dependency"
    
    cat >> "${chart_dir}/Chart.yaml" <<EOF

dependencies:
  - name: common-library
    version: "~0.1.0"
    repository: "file://../common-library"
    condition: common-library.enabled
EOF
    
    log_success "common-library dependency added"
}

# Generate analysis report
generate_analysis_report() {
    local yaml_file="$1"
    local chart_name="$2"
    
    log_info "Analyzing input manifests..."
    
    # Parse resources
    local resources
    resources=$(parse_yaml_resources "${yaml_file}")
    
    # Group by kind
    local grouped
    grouped=$(group_resources_by_kind "${resources}")
    
    # Extract namespaces
    local namespaces
    namespaces=$(extract_namespaces "${resources}")
    
    # Print report
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              YAML Manifest Analysis Report                        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Input File: ${yaml_file}"
    echo "Chart Name: ${chart_name}"
    echo ""
    echo "Resources by Kind:"
    echo "${grouped}" | jq -r '.[] | "  - \(.kind): \(.count) resource(s)"'
    echo ""
    
    if [[ -n "${namespaces}" ]]; then
        echo "Namespaces detected:"
        echo "${namespaces}" | while read -r ns; do
            echo "  - ${ns}"
        done
        echo ""
        log_warn "Namespaces will be removed from templates (managed by Helm)"
    fi
    
    echo ""
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
    log_info "==> Forge Helm Chart Generator v1.0.0"
    echo ""
    
    # Parse arguments
    parse_arguments "$@"
    
    # Validate arguments
    validate_arguments
    
    # Show configuration
    if [[ "${VERBOSE}" == "true" ]]; then
        log_debug "Configuration:"
        log_debug "  Input:        ${INPUT_FILE}"
        log_debug "  Output:       ${OUTPUT_DIR}"
        log_debug "  Chart:        ${CHART_NAME}"
        log_debug "  Version:      ${CHART_VERSION}"
        log_debug "  App Version:  ${APP_VERSION}"
        log_debug "  Description:  ${CHART_DESCRIPTION}"
        log_debug "  Common Lib:   ${USE_COMMON_LIBRARY}"
        log_debug "  Dry Run:      ${DRY_RUN}"
        echo ""
    fi
    
    # Generate analysis report
    generate_analysis_report "${INPUT_FILE}" "${CHART_NAME}"
    
    # Dry-run mode
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry-run mode enabled - no files will be created"
        log_info "Chart would be generated at: ${OUTPUT_DIR}/${CHART_NAME}"
        exit 0
    fi
    
    # Generate chart
    log_info "==> Generating Helm chart..."
    echo ""
    
    if generate_helm_chart_from_yaml \
        "${INPUT_FILE}" \
        "${OUTPUT_DIR}" \
        "${CHART_NAME}" \
        "${CHART_VERSION}" \
        "${APP_VERSION}"; then
        
        # Add common-library dependency if requested
        if [[ "${USE_COMMON_LIBRARY}" == "true" ]]; then
            add_common_library_dependency "${OUTPUT_DIR}/${CHART_NAME}"
        fi
        
        echo ""
        log_success "✓ Chart generated successfully!"
        echo ""
        echo "Chart location: ${OUTPUT_DIR}/${CHART_NAME}"
        echo ""
        echo "Next steps:"
        echo "  1. Review generated templates in ${OUTPUT_DIR}/${CHART_NAME}/templates/"
        echo "  2. Customize values in ${OUTPUT_DIR}/${CHART_NAME}/values.yaml"
        echo "  3. Test chart: helm lint ${OUTPUT_DIR}/${CHART_NAME}"
        echo "  4. Install: helm install my-release ${OUTPUT_DIR}/${CHART_NAME}"
        echo ""
        
        # Output result in requested format
        case "${OUTPUT_FORMAT}" in
            json)
                jq -n \
                    --arg chart "${CHART_NAME}" \
                    --arg version "${CHART_VERSION}" \
                    --arg path "${OUTPUT_DIR}/${CHART_NAME}" \
                    '{
                        status: "success",
                        chart: $chart,
                        version: $version,
                        path: $path
                    }'
                ;;
            yaml)
                cat <<EOF
status: success
chart: ${CHART_NAME}
version: ${CHART_VERSION}
path: ${OUTPUT_DIR}/${CHART_NAME}
EOF
                ;;
            *)
                # Text format already shown above
                ;;
        esac
        
        exit 0
    else
        log_error "Failed to generate chart"
        exit 1
    fi
}

# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
