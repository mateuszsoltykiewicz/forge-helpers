{{/*
==============================================================================
Forge Common Library - Naming Templates
==============================================================================
Advanced naming functions for different resource types and Forge patterns.

Template Functions:
  - Resource naming: deployment, service, ingress, pvc, etc.
  - Component naming: for multi-component applications
  - Forge pattern utilities
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Generate name for Deployment
------------------------------------------------------------------------------
*/}}
{{- define "common-library.deployment.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for StatefulSet
------------------------------------------------------------------------------
*/}}
{{- define "common-library.statefulset.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for DaemonSet
------------------------------------------------------------------------------
*/}}
{{- define "common-library.daemonset.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for Job
------------------------------------------------------------------------------
*/}}
{{- define "common-library.job.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for CronJob
------------------------------------------------------------------------------
*/}}
{{- define "common-library.cronjob.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for Service
------------------------------------------------------------------------------
*/}}
{{- define "common-library.service.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for additional Service
------------------------------------------------------------------------------
*/}}
{{- define "common-library.service.additionalName" -}}
{{- $fullname := include "common-library.fullname" . -}}
{{- printf "%s-%s" $fullname .name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for Ingress
------------------------------------------------------------------------------
*/}}
{{- define "common-library.ingress.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for additional Ingress
------------------------------------------------------------------------------
*/}}
{{- define "common-library.ingress.additionalName" -}}
{{- $fullname := include "common-library.fullname" . -}}
{{- printf "%s-%s" $fullname .name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for ConfigMap
------------------------------------------------------------------------------
*/}}
{{- define "common-library.configmap.name" -}}
{{- $fullname := include "common-library.fullname" . -}}
{{- if .name }}
  {{- printf "%s-%s" $fullname .name | trunc 63 | trimSuffix "-" }}
{{- else }}
  {{- $fullname }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for Secret
------------------------------------------------------------------------------
*/}}
{{- define "common-library.secret.name" -}}
{{- $fullname := include "common-library.fullname" . -}}
{{- if .name }}
  {{- printf "%s-%s" $fullname .name | trunc 63 | trimSuffix "-" }}
{{- else }}
  {{- $fullname }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for PersistentVolumeClaim
------------------------------------------------------------------------------
*/}}
{{- define "common-library.pvc.name" -}}
{{- $fullname := include "common-library.fullname" . -}}
{{- if .name }}
  {{- printf "%s-%s" $fullname .name | trunc 63 | trimSuffix "-" }}
{{- else }}
  {{- $fullname }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for ServiceAccount
------------------------------------------------------------------------------
*/}}
{{- define "common-library.serviceaccount.name" -}}
{{- if .Values.serviceAccount.name }}
  {{- .Values.serviceAccount.name }}
{{- else }}
  {{- include "common-library.fullname" . }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for Role
------------------------------------------------------------------------------
*/}}
{{- define "common-library.role.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for RoleBinding
------------------------------------------------------------------------------
*/}}
{{- define "common-library.rolebinding.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for NetworkPolicy
------------------------------------------------------------------------------
*/}}
{{- define "common-library.networkpolicy.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for HorizontalPodAutoscaler
------------------------------------------------------------------------------
*/}}
{{- define "common-library.hpa.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for PodDisruptionBudget
------------------------------------------------------------------------------
*/}}
{{- define "common-library.pdb.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for ServiceMonitor
------------------------------------------------------------------------------
*/}}
{{- define "common-library.servicemonitor.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate name for PodMonitor
------------------------------------------------------------------------------
*/}}
{{- define "common-library.podmonitor.name" -}}
{{- include "common-library.fullname" . }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate component-specific name
Useful for multi-component applications
------------------------------------------------------------------------------
*/}}
{{- define "common-library.component.name" -}}
{{- $fullname := include "common-library.fullname" . -}}
{{- $component := required "component is required" .component -}}
{{- printf "%s-%s" $fullname $component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate Forge pattern labels for a specific component
------------------------------------------------------------------------------
*/}}
{{- define "common-library.component.labels" -}}
{{ include "common-library.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate selector labels for a specific component
------------------------------------------------------------------------------
*/}}
{{- define "common-library.component.selectorLabels" -}}
{{ include "common-library.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Forge pattern - Generate release name from components
Validates against 53-character Helm limit
------------------------------------------------------------------------------
*/}}
{{- define "common-library.forge.releaseName" -}}
{{- if .Values.forgeNaming.enabled -}}
  {{- $customer := .Values.forgeNaming.customer -}}
  {{- $project := .Values.forgeNaming.project -}}
  {{- $environment := .Values.forgeNaming.environment -}}
  {{- $service := .Values.forgeNaming.service -}}
  {{- $separator := .Values.forgeNaming.separator | default "-" -}}
  {{- $name := printf "%s%s%s%s%s%s%s" $customer $separator $project $separator $environment $separator $service -}}
  {{- if gt (len $name) 53 }}
    {{- fail (printf "Forge release name '%s' exceeds 53 character limit (length: %d). Please shorten component names." $name (len $name)) }}
  {{- end }}
  {{- $name }}
{{- else }}
  {{- .Release.Name }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Forge pattern - Validate component lengths
------------------------------------------------------------------------------
*/}}
{{- define "common-library.forge.validate" -}}
{{- if .Values.forgeNaming.enabled -}}
  {{- $customer := .Values.forgeNaming.customer -}}
  {{- $project := .Values.forgeNaming.project -}}
  {{- $environment := .Values.forgeNaming.environment -}}
  {{- $service := .Values.forgeNaming.service -}}
  
  {{- if gt (len $customer) 20 }}
    {{- fail (printf "forgeNaming.customer '%s' is too long (%d chars). Maximum 20 characters recommended." $customer (len $customer)) }}
  {{- end }}
  
  {{- if gt (len $project) 20 }}
    {{- fail (printf "forgeNaming.project '%s' is too long (%d chars). Maximum 20 characters recommended." $project (len $project)) }}
  {{- end }}
  
  {{- if gt (len $environment) 10 }}
    {{- fail (printf "forgeNaming.environment '%s' is too long (%d chars). Maximum 10 characters recommended." $environment (len $environment)) }}
  {{- end }}
  
  {{- if gt (len $service) 20 }}
    {{- fail (printf "forgeNaming.service '%s' is too long (%d chars). Maximum 20 characters recommended." $service (len $service)) }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate DNS-safe name (lowercase, alphanumeric + hyphens only)
------------------------------------------------------------------------------
*/}}
{{- define "common-library.dns.safe" -}}
{{- . | lower | replace "_" "-" | regexReplaceAll "[^a-z0-9-]" "" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Generate label-safe value (max 63 chars, valid label format)
------------------------------------------------------------------------------
*/}}
{{- define "common-library.label.safe" -}}
{{- . | trunc 63 | trimPrefix "-" | trimSuffix "-" | trimPrefix "." | trimSuffix "." }}
{{- end }}
