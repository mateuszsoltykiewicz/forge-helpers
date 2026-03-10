#!/bin/bash
# Universal wrapper chart creator for testing library charts
# Usage: create_wrapper_chart WRAPPER_NAME LIBRARY_CHART_PATH VALUES_FILE [NAMESPACE]

set -e

WRAPPER_NAME="$1"
LIBRARY_CHART_PATH="$2"
VALUES_FILE="$3"
NAMESPACE="${4:-default}"

if [ -z "$WRAPPER_NAME" ] || [ -z "$LIBRARY_CHART_PATH" ] || [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 WRAPPER_NAME LIBRARY_CHART_PATH VALUES_FILE [NAMESPACE]"
  exit 1
fi

# Get absolute paths
LIBRARY_CHART_PATH=$(cd "$LIBRARY_CHART_PATH" && pwd)
VALUES_FILE=$(cd "$(dirname "$VALUES_FILE")" && pwd)/$(basename "$VALUES_FILE")

# Extract library chart name from Chart.yaml
LIBRARY_CHART_NAME=$(grep '^name:' "$LIBRARY_CHART_PATH/Chart.yaml" | awk '{print $2}')
LIBRARY_CHART_VERSION=$(grep '^version:' "$LIBRARY_CHART_PATH/Chart.yaml" | awk '{print $2}')

# Create temporary wrapper chart directory
WRAPPER_DIR="/tmp/$WRAPPER_NAME-wrapper-$(date +%s)"
mkdir -p "$WRAPPER_DIR/templates"

# Create Chart.yaml for wrapper
cat > "$WRAPPER_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: $WRAPPER_NAME
description: Test wrapper chart for $LIBRARY_CHART_NAME
type: application
version: 0.1.0
appVersion: "1.0"

dependencies:
  - name: $LIBRARY_CHART_NAME
    version: $LIBRARY_CHART_VERSION
    repository: "file://$LIBRARY_CHART_PATH"
EOF

# Create empty templates (templates come from library chart)
cat > "$WRAPPER_DIR/templates/_helpers.tpl" <<'EOF'
{{- define "wrapper.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
EOF

# Create manifest templates that include library chart templates
# Each resource type gets its own file
cat > "$WRAPPER_DIR/templates/deployment.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.deployment.enabled -}}
{{- include "$LIBRARY_CHART_NAME.deployment" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/configmap.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.configMap.enabled -}}
{{- include "$LIBRARY_CHART_NAME.configmap" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/secret.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.secret.enabled -}}
{{- include "$LIBRARY_CHART_NAME.secret" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/service.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.service.enabled -}}
{{- include "$LIBRARY_CHART_NAME.service" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/ingress.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.ingress.enabled -}}
{{- include "$LIBRARY_CHART_NAME.ingress" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/hpa.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.hpa.enabled -}}
{{- include "$LIBRARY_CHART_NAME.hpa" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/serviceaccount.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.serviceAccount.enabled -}}
{{- include "$LIBRARY_CHART_NAME.serviceaccount" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/rbac.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.rbac.enabled -}}
{{- include "$LIBRARY_CHART_NAME.rbac" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/pvc.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.pvc.enabled -}}
{{- include "$LIBRARY_CHART_NAME.pvc" . }}
{{- end }}
EOF

cat > "$WRAPPER_DIR/templates/networkpolicy.yaml" <<EOF
{{- if .Values.$LIBRARY_CHART_NAME.networkPolicy.enabled -}}
{{- include "$LIBRARY_CHART_NAME.networkpolicy" . }}
{{- end }}
EOF

# Copy values from test case and wrap them under subchart name
cat > "$WRAPPER_DIR/values.yaml" <<EOF
# Values for $LIBRARY_CHART_NAME subchart
$LIBRARY_CHART_NAME:
EOF

# Indent original values by 2 spaces for subchart
sed 's/^/  /' "$VALUES_FILE" >> "$WRAPPER_DIR/values.yaml"

# Build dependencies
cd "$WRAPPER_DIR"
helm dependency build >/dev/null 2>&1

# Return only wrapper directory path
echo "$WRAPPER_DIR"
