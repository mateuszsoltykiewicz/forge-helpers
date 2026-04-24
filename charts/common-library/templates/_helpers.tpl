{{/*
==============================================================================
Forge Common Library - Helper Templates
==============================================================================
Core helper functions for naming, labels, selectors, and common patterns.

Template Functions:
  - Naming: fullname, name, chart
  - Labels: labels, selectorLabels, metaLabels
  - Service Account: serviceAccountName
  - Image: image reference builder
  - Validation: required field checks
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Expand the name of the chart
------------------------------------------------------------------------------
*/}}
{{- define "common-library.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Create a default fully qualified app name
Uses Forge naming pattern if enabled, otherwise standard Helm naming
------------------------------------------------------------------------------
*/}}
{{- define "common-library.fullname" -}}
{{- if .Values.forgeNaming.enabled -}}
  {{- $customer := required "forgeNaming.customer is required when forgeNaming.enabled=true" .Values.forgeNaming.customer -}}
  {{- $project := required "forgeNaming.project is required when forgeNaming.enabled=true" .Values.forgeNaming.project -}}
  {{- $environment := required "forgeNaming.environment is required when forgeNaming.enabled=true" .Values.forgeNaming.environment -}}
  {{- $service := required "forgeNaming.service is required when forgeNaming.enabled=true" .Values.forgeNaming.service -}}
  {{- $separator := .Values.forgeNaming.separator | default "-" -}}
  {{- $maxLength := .Values.forgeNaming.maxLength | default 53 -}}
  {{- printf "%s%s%s%s%s%s%s" $customer $separator $project $separator $environment $separator $service | trunc (int $maxLength) | trimSuffix $separator -}}
{{- else -}}
  {{- if .Values.fullnameOverride }}
    {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
  {{- else }}
    {{- $name := default .Chart.Name .Values.nameOverride }}
    {{- if contains $name .Release.Name }}
      {{- .Release.Name | trunc 63 | trimSuffix "-" }}
    {{- else }}
      {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Create chart name and version as used by the chart label
------------------------------------------------------------------------------
*/}}
{{- define "common-library.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Common labels - Applied to all resources
Includes: Helm standard labels + Forge custom labels
------------------------------------------------------------------------------
*/}}
{{- define "common-library.labels" -}}
helm.sh/chart: {{ include "common-library.chart" . }}
{{ include "common-library.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.forgeNaming.enabled }}
forge.moai.io/customer: {{ .Values.forgeNaming.customer | quote }}
forge.moai.io/project: {{ .Values.forgeNaming.project | quote }}
forge.moai.io/environment: {{ .Values.forgeNaming.environment | quote }}
forge.moai.io/service: {{ .Values.forgeNaming.service | quote }}
{{- end }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Selector labels - Used for pod selectors (immutable)
------------------------------------------------------------------------------
*/}}
{{- define "common-library.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common-library.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Meta labels - For metadata only (non-selector labels)
------------------------------------------------------------------------------
*/}}
{{- define "common-library.metaLabels" -}}
app.kubernetes.io/component: {{ .Values.component | default "application" }}
app.kubernetes.io/part-of: {{ .Values.partOf | default .Release.Name }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Create the name of the service account to use
------------------------------------------------------------------------------
*/}}
{{- define "common-library.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
  {{- default (include "common-library.fullname" .) .Values.serviceAccount.name }}
{{- else }}
  {{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return the proper image reference
Handles: registry override, digest, tag defaults
------------------------------------------------------------------------------
*/}}
{{- define "common-library.image" -}}
{{- $registry := .Values.image.registry | default .Values.global.imageRegistry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $digest := .Values.image.digest -}}
{{- if $registry }}
  {{- printf "%s/%s" $registry $repository -}}
{{- else }}
  {{- $repository -}}
{{- end }}
{{- if $digest }}
  {{- printf "@%s" $digest -}}
{{- else if $tag }}
  {{- printf ":%s" $tag -}}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return the proper image pull secrets
Merges global and local image pull secrets
------------------------------------------------------------------------------
*/}}
{{- define "common-library.imagePullSecrets" -}}
{{- $pullSecrets := list }}
{{- if .Values.global.imagePullSecrets }}
  {{- range .Values.global.imagePullSecrets }}
    {{- $pullSecrets = append $pullSecrets . }}
  {{- end }}
{{- end }}
{{- if .Values.image.pullSecrets }}
  {{- range .Values.image.pullSecrets }}
    {{- $pullSecrets = append $pullSecrets . }}
  {{- end }}
{{- end }}
{{- if $pullSecrets }}
imagePullSecrets:
  {{- range $pullSecrets | uniq }}
  - name: {{ .name }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return storage class
Uses value from persistence, or falls back to global
------------------------------------------------------------------------------
*/}}
{{- define "common-library.storageClass" -}}
{{- $storageClass := .Values.persistence.storageClass | default .Values.global.storageClass -}}
{{- if $storageClass }}
storageClassName: {{ $storageClass | quote }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Validate required fields
------------------------------------------------------------------------------
*/}}
{{- define "common-library.validateRequired" -}}
{{- if .Values.forgeNaming.enabled }}
  {{- required "forgeNaming.customer is required when forgeNaming.enabled=true" .Values.forgeNaming.customer }}
  {{- required "forgeNaming.project is required when forgeNaming.enabled=true" .Values.forgeNaming.project }}
  {{- required "forgeNaming.environment is required when forgeNaming.enabled=true" .Values.forgeNaming.environment }}
  {{- required "forgeNaming.service is required when forgeNaming.enabled=true" .Values.forgeNaming.service }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return the appropriate apiVersion for HPA
------------------------------------------------------------------------------
*/}}
{{- define "common-library.hpa.apiVersion" -}}
{{- if .Values.autoscaling.apiVersion }}
  {{- .Values.autoscaling.apiVersion }}
{{- else if .Capabilities.APIVersions.Has "autoscaling/v2" }}
  {{- print "autoscaling/v2" }}
{{- else if .Capabilities.APIVersions.Has "autoscaling/v2beta2" }}
  {{- print "autoscaling/v2beta2" }}
{{- else }}
  {{- print "autoscaling/v2beta1" }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return the appropriate apiVersion for Ingress
------------------------------------------------------------------------------
*/}}
{{- define "common-library.ingress.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "networking.k8s.io/v1" }}
  {{- print "networking.k8s.io/v1" }}
{{- else if .Capabilities.APIVersions.Has "networking.k8s.io/v1beta1" }}
  {{- print "networking.k8s.io/v1beta1" }}
{{- else }}
  {{- print "extensions/v1beta1" }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return the appropriate apiVersion for PodDisruptionBudget
------------------------------------------------------------------------------
*/}}
{{- define "common-library.pdb.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "policy/v1" }}
  {{- print "policy/v1" }}
{{- else }}
  {{- print "policy/v1beta1" }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Check if workload type is valid
------------------------------------------------------------------------------
*/}}
{{- define "common-library.workload.isValid" -}}
{{- $validTypes := list "deployment" "statefulset" "daemonset" "job" "cronjob" "none" }}
{{- if has .Values.workload.type $validTypes }}
  {{- print "true" }}
{{- else }}
  {{- fail (printf "Invalid workload.type '%s'. Must be one of: %s" .Values.workload.type (join ", " $validTypes)) }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return namespace for resource
Uses Release.Namespace by default, can be overridden
------------------------------------------------------------------------------
*/}}
{{- define "common-library.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Common annotations
Merges global and resource-specific annotations
------------------------------------------------------------------------------
*/}}
{{- define "common-library.annotations" -}}
{{- $annotations := merge (.Values.annotations | default dict) (.Values.global.annotations | default dict) }}
{{- if $annotations }}
{{- toYaml $annotations }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Return container name
Defaults to chart name if not specified
------------------------------------------------------------------------------
*/}}
{{- define "common-library.containerName" -}}
{{- default .Chart.Name .Values.container.name }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Check if a capability is available
------------------------------------------------------------------------------
*/}}
{{- define "common-library.capabilities.kubeVersion" -}}
{{- default .Capabilities.KubeVersion.Version .Values.kubeVersionOverride }}
{{- end }}
