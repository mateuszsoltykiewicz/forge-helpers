{{/*
==============================================================================
Forge Common Library - Monitoring Templates
==============================================================================
PodMonitor and ServiceMonitor for Prometheus.
==============================================================================
*/}}

{{- define "k8s.podmonitor" -}}
{{- if .Values.podMonitor -}}
{{- if .Values.podMonitor.enabled -}}
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "podmonitor" "name" .Values.podMonitor.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.podMonitor.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "forge.selectorLabels" . | nindent 6 }}
  
  {{- with .Values.podMonitor.namespaceSelector }}
  namespaceSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  podMetricsEndpoints:
  {{- range .Values.podMonitor.endpoints }}
  - port: {{ .port | default "metrics" }}
    {{- with .path }}
    path: {{ . }}
    {{- end }}
    {{- with .interval }}
    interval: {{ . }}
    {{- end }}
    {{- with .scrapeTimeout }}
    scrapeTimeout: {{ . }}
    {{- end }}
    {{- with .scheme }}
    scheme: {{ . }}
    {{- end }}
    {{- with .tlsConfig }}
    tlsConfig:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .relabelings }}
    relabelings:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .metricRelabelings }}
    metricRelabelings:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "k8s.servicemonitor" -}}
{{- if .Values.serviceMonitor -}}
{{- if .Values.serviceMonitor.enabled -}}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "servicemonitor" "name" .Values.serviceMonitor.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.serviceMonitor.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "forge.selectorLabels" . | nindent 6 }}
  
  {{- with .Values.serviceMonitor.namespaceSelector }}
  namespaceSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  endpoints:
  {{- range .Values.serviceMonitor.endpoints }}
  - port: {{ .port | default "metrics" }}
    {{- with .path }}
    path: {{ . }}
    {{- end }}
    {{- with .interval }}
    interval: {{ . }}
    {{- end }}
    {{- with .scrapeTimeout }}
    scrapeTimeout: {{ . }}
    {{- end }}
    {{- with .scheme }}
    scheme: {{ . }}
    {{- end }}
    {{- with .tlsConfig }}
    tlsConfig:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .relabelings }}
    relabelings:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .metricRelabelings }}
    metricRelabelings:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
