{{/*
==============================================================================
Forge Common Library - ConfigMap Template
==============================================================================
ConfigMap template for application configuration.
==============================================================================
*/}}

{{- define "k8s.configmap" -}}
{{- if .Values.configMap -}}
{{- if .Values.configMap.enabled -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "configmap" "name" .Values.configMap.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.configMap.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- if .Values.configMap.immutable }}
immutable: true
{{- end }}
{{- with .Values.configMap.data }}
data:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.configMap.binaryData }}
binaryData:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
