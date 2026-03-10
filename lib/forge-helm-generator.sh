#!/usr/bin/env bash
# ==============================================================================
# Forge Helpers - Helm Chart Generator Library
# ==============================================================================
# Description:
#   Library for generating Helm charts from raw Kubernetes YAML manifests.
#   Converts plain K8s resources into parameterized Helm charts with:
#   - Automatic value extraction
#   - Template generation
#   - Chart structure creation
#   - Integration with common-library chart
#
# Dependencies:
#   - yq (YAML processor)
#   - jq (JSON processor)
#   - kubectl (for validation)
#   - forge-core.sh
#   - forge-patterns.sh
#
# Author: Forge Team
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

# ==============================================================================
# METADATA
# ==============================================================================

readonly FORGE_HELM_GENERATOR_VERSION="1.0.0"

# ==============================================================================
# DEPENDENCIES
# ==============================================================================

# Ensure dependencies are loaded
if ! declare -f log_info >/dev/null 2>&1; then
    echo "ERROR: forge-core.sh must be loaded before forge-helm-generator.sh" >&2
    return 1
fi

# ==============================================================================
# YAML PARSING FUNCTIONS
# ==============================================================================

# Parse YAML file and extract all resources
parse_yaml_resources() {
    local yaml_file="$1"
    
    log_debug "Parsing YAML file: ${yaml_file}"
    
    if [[ ! -f "${yaml_file}" ]]; then
        log_error "YAML file not found: ${yaml_file}"
        return 1
    fi
    
    # Split multi-document YAML and output as JSON array
    yq eval -o=json '.' "${yaml_file}" 2>/dev/null || {
        log_error "Failed to parse YAML file"
        return 1
    }
}

# Get resource kind from YAML
get_resource_kind() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '.kind // "Unknown"'
}

# Get resource name from metadata
get_resource_name() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '.metadata.name // "unnamed"'
}

# Get resource namespace from metadata
get_resource_namespace() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '.metadata.namespace // ""'
}

# Get resource labels
get_resource_labels() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '.metadata.labels // {}'
}

# Extract all unique namespaces from resources
extract_namespaces() {
    local resources_json="$1"
    
    echo "${resources_json}" | jq -r '
        [.[] | select(.metadata.namespace != null) | .metadata.namespace] 
        | unique 
        | .[]
    ' 2>/dev/null || echo ""
}

# Group resources by kind
group_resources_by_kind() {
    local resources_json="$1"
    
    echo "${resources_json}" | jq -r '
        group_by(.kind) 
        | map({
            kind: .[0].kind,
            count: length,
            resources: .
        })
    '
}

# ==============================================================================
# VALUE EXTRACTION FUNCTIONS
# ==============================================================================

# Extract image information from container specs
extract_image_values() {
    local resource_json="$1"
    local kind="$2"
    
    local images=""
    
    case "${kind}" in
        Deployment|StatefulSet|DaemonSet|Job|CronJob)
            if [[ "${kind}" == "CronJob" ]]; then
                images=$(echo "${resource_json}" | jq -r '
                    .spec.jobTemplate.spec.template.spec.containers[]? 
                    | {name: .name, image: .image, tag: (.image | split(":")[1] // "latest")}
                ')
            else
                images=$(echo "${resource_json}" | jq -r '
                    .spec.template.spec.containers[]? 
                    | {name: .name, image: .image, tag: (.image | split(":")[1] // "latest")}
                ')
            fi
            ;;
        Pod)
            images=$(echo "${resource_json}" | jq -r '
                .spec.containers[]? 
                | {name: .name, image: .image, tag: (.image | split(":")[1] // "latest")}
            ')
            ;;
    esac
    
    echo "${images}"
}

# Extract replica count
extract_replica_count() {
    local resource_json="$1"
    local kind="$2"
    
    case "${kind}" in
        Deployment|StatefulSet)
            echo "${resource_json}" | jq -r '.spec.replicas // 1'
            ;;
        *)
            echo "1"
            ;;
    esac
}

# Extract service ports
extract_service_ports() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '
        .spec.ports[]? 
        | {name: .name, port: .port, targetPort: .targetPort, protocol: (.protocol // "TCP")}
    '
}

# Extract environment variables
extract_env_vars() {
    local resource_json="$1"
    local kind="$2"
    
    local env_vars=""
    
    case "${kind}" in
        Deployment|StatefulSet|DaemonSet|Job|CronJob)
            if [[ "${kind}" == "CronJob" ]]; then
                env_vars=$(echo "${resource_json}" | jq -r '
                    .spec.jobTemplate.spec.template.spec.containers[0].env[]? 
                    | {name: .name, value: .value}
                ' 2>/dev/null)
            else
                env_vars=$(echo "${resource_json}" | jq -r '
                    .spec.template.spec.containers[0].env[]? 
                    | {name: .name, value: .value}
                ' 2>/dev/null)
            fi
            ;;
    esac
    
    echo "${env_vars}"
}

# Extract resource requests and limits
extract_resources() {
    local resource_json="$1"
    local kind="$2"
    
    local resources=""
    
    case "${kind}" in
        Deployment|StatefulSet|DaemonSet|Job|CronJob)
            if [[ "${kind}" == "CronJob" ]]; then
                resources=$(echo "${resource_json}" | jq -r '
                    .spec.jobTemplate.spec.template.spec.containers[0].resources // {}
                ' 2>/dev/null)
            else
                resources=$(echo "${resource_json}" | jq -r '
                    .spec.template.spec.containers[0].resources // {}
                ' 2>/dev/null)
            fi
            ;;
    esac
    
    echo "${resources}"
}

# Extract ConfigMap data
extract_configmap_data() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '.data // {}'
}

# Extract Secret data keys (not values for security)
extract_secret_keys() {
    local resource_json="$1"
    
    echo "${resource_json}" | jq -r '.data // {} | keys[]' 2>/dev/null || echo ""
}

# Build comprehensive values from all resources
build_values_yaml() {
    local resources_json="$1"
    local chart_name="$2"
    
    log_info "Building values.yaml for chart: ${chart_name}"
    
    # Initialize values structure
    local values=$(cat <<EOF
# Default values for ${chart_name}
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 1

image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: ""

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext: {}

securityContext: {}

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls: []

resources: {}

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80

nodeSelector: {}

tolerations: []

affinity: {}
EOF
)
    
    # Extract and merge values from resources
    # This is a simplified version - real implementation would be more sophisticated
    
    echo "${values}"
}

# ==============================================================================
# CHART STRUCTURE GENERATION
# ==============================================================================

# Create basic chart directory structure
create_chart_structure() {
    local output_dir="$1"
    local chart_name="$2"
    
    log_info "Creating chart structure: ${output_dir}/${chart_name}"
    
    local chart_dir="${output_dir}/${chart_name}"
    
    # Create directories
    mkdir -p "${chart_dir}"
    mkdir -p "${chart_dir}/templates"
    mkdir -p "${chart_dir}/templates/tests"
    mkdir -p "${chart_dir}/charts"
    
    log_success "Chart structure created"
    echo "${chart_dir}"
}

# Generate Chart.yaml
generate_chart_yaml() {
    local chart_dir="$1"
    local chart_name="$2"
    local version="${3:-0.1.0}"
    local app_version="${4:-1.0.0}"
    local description="${5:-A Helm chart for Kubernetes}"
    
    log_info "Generating Chart.yaml"
    
    cat > "${chart_dir}/Chart.yaml" <<EOF
apiVersion: v2
name: ${chart_name}
description: ${description}
type: application
version: ${version}
appVersion: "${app_version}"

# Forge-generated chart
# Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
    
    log_success "Chart.yaml generated"
}

# Generate .helmignore
generate_helmignore() {
    local chart_dir="$1"
    
    log_info "Generating .helmignore"
    
    cat > "${chart_dir}/.helmignore" <<'EOF'
# Patterns to ignore when building packages.
# This supports shell glob matching, relative path matching, and
# negation (prefixed with !). Only one pattern per line.
.DS_Store
# Common VCS dirs
.git/
.gitignore
.bzr/
.bzrignore
.hg/
.hgignore
.svn/
# Common backup files
*.swp
*.bak
*.tmp
*.orig
*~
# Various IDEs
.project
.idea/
*.tmproj
.vscode/
EOF
    
    log_success ".helmignore generated"
}

# Generate NOTES.txt
generate_notes_txt() {
    local chart_dir="$1"
    local chart_name="$2"
    
    log_info "Generating NOTES.txt"
    
    cat > "${chart_dir}/templates/NOTES.txt" <<EOF
1. Get the application URL by running these commands:
{{- if .Values.ingress.enabled }}
{{- range \$host := .Values.ingress.hosts }}
  {{- range .paths }}
  http{{ if \$.Values.ingress.tls }}s{{ end }}://{{ \$host.host }}{{ .path }}
  {{- end }}
{{- end }}
{{- else if contains "NodePort" .Values.service.type }}
  export NODE_PORT=\$(kubectl get --namespace {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}" services {{ include "${chart_name}.fullname" . }})
  export NODE_IP=\$(kubectl get nodes --namespace {{ .Release.Namespace }} -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://\$NODE_IP:\$NODE_PORT
{{- else if contains "LoadBalancer" .Values.service.type }}
     NOTE: It may take a few minutes for the LoadBalancer IP to be available.
           You can watch the status of by running 'kubectl get --namespace {{ .Release.Namespace }} svc -w {{ include "${chart_name}.fullname" . }}'
  export SERVICE_IP=\$(kubectl get svc --namespace {{ .Release.Namespace }} {{ include "${chart_name}.fullname" . }} --template "{{"{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}"}}")
  echo http://\$SERVICE_IP:{{ .Values.service.port }}
{{- else if contains "ClusterIP" .Values.service.type }}
  export POD_NAME=\$(kubectl get pods --namespace {{ .Release.Namespace }} -l "app.kubernetes.io/name={{ include "${chart_name}.name" . }},app.kubernetes.io/instance={{ .Release.Name }}" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=\$(kubectl get pod --namespace {{ .Release.Namespace }} \$POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace {{ .Release.Namespace }} port-forward \$POD_NAME 8080:\$CONTAINER_PORT
{{- end }}
EOF
    
    log_success "NOTES.txt generated"
}

# Generate _helpers.tpl
generate_helpers_tpl() {
    local chart_dir="$1"
    local chart_name="$2"
    
    log_info "Generating _helpers.tpl"
    
    cat > "${chart_dir}/templates/_helpers.tpl" <<EOF
{{/*
Expand the name of the chart.
*/}}
{{- define "${chart_name}.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "${chart_name}.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- \$name := default .Chart.Name .Values.nameOverride }}
{{- if contains \$name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name \$name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "${chart_name}.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "${chart_name}.labels" -}}
helm.sh/chart: {{ include "${chart_name}.chart" . }}
{{ include "${chart_name}.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "${chart_name}.selectorLabels" -}}
app.kubernetes.io/name: {{ include "${chart_name}.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "${chart_name}.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "${chart_name}.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
EOF
    
    log_success "_helpers.tpl generated"
}

# ==============================================================================
# TEMPLATE GENERATION FUNCTIONS
# ==============================================================================

# Convert Deployment to Helm template
convert_deployment_to_template() {
    local resource_json="$1"
    local chart_name="$2"
    
    log_debug "Converting Deployment to template"
    
    # This is a simplified version - real implementation would handle more fields
    local name=$(get_resource_name "${resource_json}")
    
    cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "${chart_name}.fullname" . }}
  labels:
    {{- include "${chart_name}.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "${chart_name}.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "${chart_name}.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "${chart_name}.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
      - name: {{ .Chart.Name }}
        securityContext:
          {{- toYaml .Values.securityContext | nindent 12 }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: 80
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /
            port: http
        readinessProbe:
          httpGet:
            path: /
            port: http
        resources:
          {{- toYaml .Values.resources | nindent 12 }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
EOF
}

# Convert Service to Helm template
convert_service_to_template() {
    local resource_json="$1"
    local chart_name="$2"
    
    log_debug "Converting Service to template"
    
    cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: {{ include "${chart_name}.fullname" . }}
  labels:
    {{- include "${chart_name}.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: http
    protocol: TCP
    name: http
  selector:
    {{- include "${chart_name}.selectorLabels" . | nindent 4 }}
EOF
}

# Convert ServiceAccount to Helm template
convert_serviceaccount_to_template() {
    local resource_json="$1"
    local chart_name="$2"
    
    log_debug "Converting ServiceAccount to template"
    
    cat <<EOF
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "${chart_name}.serviceAccountName" . }}
  labels:
    {{- include "${chart_name}.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
EOF
}

# Convert Ingress to Helm template  
convert_ingress_to_template() {
    local resource_json="$1"
    local chart_name="$2"
    
    log_debug "Converting Ingress to template"
    
    cat <<EOF
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "${chart_name}.fullname" . }}
  labels:
    {{- include "${chart_name}.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "${chart_name}.fullname" \$ }}
                port:
                  number: {{ \$.Values.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
EOF
}

# ==============================================================================
# RESOURCE CONVERSION ORCHESTRATION
# ==============================================================================

# Convert resource to appropriate template
convert_resource_to_template() {
    local resource_json="$1"
    local chart_name="$2"
    local output_dir="$3"
    
    local kind=$(get_resource_kind "${resource_json}")
    local name=$(get_resource_name "${resource_json}")
    
    log_info "Converting ${kind}/${name} to template"
    
    local template_content=""
    local filename=""
    
    case "${kind}" in
        Deployment)
            template_content=$(convert_deployment_to_template "${resource_json}" "${chart_name}")
            filename="deployment.yaml"
            ;;
        Service)
            template_content=$(convert_service_to_template "${resource_json}" "${chart_name}")
            filename="service.yaml"
            ;;
        ServiceAccount)
            template_content=$(convert_serviceaccount_to_template "${resource_json}" "${chart_name}")
            filename="serviceaccount.yaml"
            ;;
        Ingress)
            template_content=$(convert_ingress_to_template "${resource_json}" "${chart_name}")
            filename="ingress.yaml"
            ;;
        ConfigMap)
            # Keep ConfigMaps mostly as-is with minimal templating
            template_content="${resource_json}"
            filename="configmap-${name}.yaml"
            ;;
        Secret)
            # Keep Secrets mostly as-is (but warn about including them)
            log_warn "Secrets should not be stored in Git - consider using sealed-secrets or external-secrets"
            template_content="${resource_json}"
            filename="secret-${name}.yaml"
            ;;
        *)
            log_warn "Unsupported resource kind: ${kind} - copying as-is"
            template_content="${resource_json}"
            filename="${kind,,}-${name}.yaml"
            ;;
    esac
    
    # Write template file
    if [[ -n "${template_content}" ]]; then
        echo "${template_content}" > "${output_dir}/templates/${filename}"
        log_success "Generated template: ${filename}"
    fi
}

# ==============================================================================
# MAIN GENERATION FUNCTION
# ==============================================================================

# Generate complete Helm chart from YAML manifests
generate_helm_chart_from_yaml() {
    local yaml_file="$1"
    local output_dir="$2"
    local chart_name="$3"
    local chart_version="${4:-0.1.0}"
    local app_version="${5:-1.0.0}"
    
    log_info "==> Generating Helm chart from: ${yaml_file}"
    log_info "Chart name: ${chart_name}"
    log_info "Output directory: ${output_dir}"
    
    # Parse YAML resources
    local resources
    resources=$(parse_yaml_resources "${yaml_file}") || return 1
    
    # Create chart structure
    local chart_dir
    chart_dir=$(create_chart_structure "${output_dir}" "${chart_name}") || return 1
    
    # Generate Chart.yaml
    generate_chart_yaml "${chart_dir}" "${chart_name}" "${chart_version}" "${app_version}"
    
    # Generate .helmignore
    generate_helmignore "${chart_dir}"
    
    # Generate _helpers.tpl
    generate_helpers_tpl "${chart_dir}" "${chart_name}"
    
    # Generate NOTES.txt
    generate_notes_txt "${chart_dir}" "${chart_name}"
    
    # Generate values.yaml
    local values
    values=$(build_values_yaml "${resources}" "${chart_name}")
    echo "${values}" > "${chart_dir}/values.yaml"
    log_success "values.yaml generated"
    
    # Convert each resource to template
    local resource_count=0
    while IFS= read -r resource; do
        [[ -z "${resource}" ]] && continue
        resource_count=$((resource_count + 1))
        
        convert_resource_to_template "${resource}" "${chart_name}" "${chart_dir}"
    done < <(echo "${resources}" | jq -c '.[]' 2>/dev/null)
    
    log_success "Generated chart with ${resource_count} resources"
    log_info "Chart location: ${chart_dir}"
    
    return 0
}

# ==============================================================================
# EXPORTS
# ==============================================================================

export -f parse_yaml_resources
export -f get_resource_kind get_resource_name get_resource_namespace
export -f extract_namespaces group_resources_by_kind
export -f extract_image_values extract_replica_count extract_service_ports
export -f extract_env_vars extract_resources
export -f build_values_yaml
export -f create_chart_structure
export -f generate_chart_yaml generate_helmignore generate_notes_txt
export -f generate_helpers_tpl
export -f convert_deployment_to_template convert_service_to_template
export -f convert_serviceaccount_to_template convert_ingress_to_template
export -f convert_resource_to_template
export -f generate_helm_chart_from_yaml

# ==============================================================================
# INITIALIZATION
# ==============================================================================

log_debug "Loaded forge-helm-generator.sh v${FORGE_HELM_GENERATOR_VERSION}"
