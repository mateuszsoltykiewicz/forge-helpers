{{/*
==============================================================================
Forge Common Library - Autoscaling Templates
==============================================================================
HPA, VPA, PDB templates for autoscaling and availability.
==============================================================================
*/}}

{{- define "k8s.hpa" -}}
{{- if .Values.autoscaling -}}
{{- if .Values.autoscaling.enabled -}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "hpa" "name" .Values.autoscaling.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.autoscaling.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ .Values.autoscaling.targetKind | default "Deployment" }}
    name: {{ .Values.autoscaling.targetName | default (include "forge.resourceName" (dict "context" . "type" "deployment")) }}
  
  minReplicas: {{ .Values.autoscaling.minReplicas | default 1 }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas | required "autoscaling.maxReplicas is required" }}
  
  {{- with .Values.autoscaling.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  metrics:
  {{- if .Values.autoscaling.targetCPUUtilizationPercentage }}
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
  {{- end }}
  {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
  {{- end }}
  {{- with .Values.autoscaling.customMetrics }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "k8s.vpa" -}}
{{- if .Values.vpa -}}
{{- if .Values.vpa.enabled -}}
---
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "vpa" "name" .Values.vpa.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.vpa.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  targetRef:
    apiVersion: apps/v1
    kind: {{ .Values.vpa.targetKind | default "Deployment" }}
    name: {{ .Values.vpa.targetName | default (include "forge.resourceName" (dict "context" . "type" "deployment")) }}
  
  {{- with .Values.vpa.updatePolicy }}
  updatePolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.vpa.resourcePolicy }}
  resourcePolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "k8s.pdb" -}}
{{- if .Values.pdb -}}
{{- if .Values.pdb.enabled -}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "pdb" "name" .Values.pdb.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.pdb.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.pdb.minAvailable }}
  minAvailable: {{ .Values.pdb.minAvailable }}
  {{- end }}
  {{- if .Values.pdb.maxUnavailable }}
  maxUnavailable: {{ .Values.pdb.maxUnavailable }}
  {{- end }}
  
  selector:
    matchLabels:
      {{- include "forge.selectorLabels" . | nindent 6 }}
  
  {{- with .Values.pdb.unhealthyPodEvictionPolicy }}
  unhealthyPodEvictionPolicy: {{ . }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
