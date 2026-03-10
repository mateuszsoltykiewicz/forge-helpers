{{/*
==============================================================================
Forge Common Library - Service Template
==============================================================================
Service template for exposing applications.
==============================================================================
*/}}

{{- define "k8s.service" -}}
{{- if .Values.service -}}
{{- if .Values.service.enabled -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "service" "name" .Values.service.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  
  {{- if .Values.service.clusterIP }}
  clusterIP: {{ .Values.service.clusterIP }}
  {{- end }}
  
  {{- with .Values.service.externalIPs }}
  externalIPs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.service.loadBalancerIP }}
  loadBalancerIP: {{ . }}
  {{- end }}
  
  {{- with .Values.service.loadBalancerSourceRanges }}
  loadBalancerSourceRanges:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.service.externalName }}
  externalName: {{ . }}
  {{- end }}
  
  {{- with .Values.service.externalTrafficPolicy }}
  externalTrafficPolicy: {{ . }}
  {{- end }}
  
  {{- with .Values.service.sessionAffinity }}
  sessionAffinity: {{ . }}
  {{- end }}
  
  {{- with .Values.service.sessionAffinityConfig }}
  sessionAffinityConfig:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.service.publishNotReadyAddresses }}
  publishNotReadyAddresses: {{ . }}
  {{- end }}
  
  {{- if .Values.service.ports }}
  ports:
  {{- range .Values.service.ports }}
  - name: {{ .name }}
    port: {{ .port }}
    targetPort: {{ .targetPort | default .port }}
    protocol: {{ .protocol | default "TCP" }}
    {{- if and (or (eq $.Values.service.type "NodePort") (eq $.Values.service.type "LoadBalancer")) .nodePort }}
    nodePort: {{ .nodePort }}
    {{- end }}
    {{- with .appProtocol }}
    appProtocol: {{ . }}
    {{- end }}
  {{- end }}
  {{- end }}
  
  selector:
    {{- include "forge.selectorLabels" . | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
Headless Service Template (for StatefulSets)
==============================================================================
*/}}

{{- define "k8s.service.headless" -}}
{{- if .Values.service -}}
{{- if .Values.service.headless -}}
{{- if .Values.service.headless.enabled -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "service" "name" .Values.service.headless.nameOverride) }}-headless
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/service-type: headless
  {{- with .Values.service.headless.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  clusterIP: None
  publishNotReadyAddresses: {{ .Values.service.headless.publishNotReadyAddresses | default false }}
  
  {{- if .Values.service.headless.ports }}
  ports:
  {{- range .Values.service.headless.ports }}
  - name: {{ .name }}
    port: {{ .port }}
    targetPort: {{ .targetPort | default .port }}
    protocol: {{ .protocol | default "TCP" }}
  {{- end }}
  {{- end }}
  
  selector:
    {{- include "forge.selectorLabels" . | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
