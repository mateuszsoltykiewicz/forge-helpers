{{/*
==============================================================================
Forge Common Library - NetworkPolicy Template
==============================================================================
NetworkPolicy template for pod-level network segmentation.
==============================================================================
*/}}

{{- define "k8s.networkpolicy" -}}
{{- if .Values.networkPolicy -}}
{{- if .Values.networkPolicy.enabled -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" .Values.networkPolicy.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.networkPolicy.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  podSelector:
    {{- if .Values.networkPolicy.podSelector }}
    {{- toYaml .Values.networkPolicy.podSelector | nindent 4 }}
    {{- else }}
    matchLabels:
      {{- include "forge.selectorLabels" . | nindent 6 }}
    {{- end }}
  
  policyTypes:
  {{- if .Values.networkPolicy.ingress }}
  - Ingress
  {{- end }}
  {{- if .Values.networkPolicy.egress }}
  - Egress
  {{- end }}
  
  {{- with .Values.networkPolicy.ingress }}
  ingress:
  {{- toYaml . | nindent 2 }}
  {{- end }}
  
  {{- with .Values.networkPolicy.egress }}
  egress:
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
