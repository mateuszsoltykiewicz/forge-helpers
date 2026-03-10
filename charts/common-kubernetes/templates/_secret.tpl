{{/*
==============================================================================
Forge Common Library - Secret Template
==============================================================================
Secret template for sensitive data (NOT for Vault-managed secrets).
==============================================================================
*/}}

{{- define "k8s.secret" -}}
{{- if .Values.secret -}}
{{- if .Values.secret.enabled -}}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "secret" "name" .Values.secret.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.secret.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
type: {{ .Values.secret.type | default "Opaque" }}
{{- if .Values.secret.immutable }}
immutable: true
{{- end }}
{{- with .Values.secret.stringData }}
stringData:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.secret.data }}
data:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
