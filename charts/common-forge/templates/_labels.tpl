{{/*
==============================================================================
Forge Common Library - Labels
==============================================================================
Label generators following Kubernetes recommended labels plus Forge-specific
metadata. Ensures consistent labeling across all resources.

Label Domains:
  - app.kubernetes.io/*  - Standard Kubernetes labels
  - moai.forge.io/*      - Forge-specific labels
  - helm.sh/*            - Helm metadata

Functions:
  - forge.labels.kubernetes - Standard K8s labels (name, instance, version, etc.)
  - forge.labels.forge      - Forge-specific labels (customer, project, environment)
  - forge.labels            - Combined labels (kubernetes + forge + custom)
  - forge.selectorLabels    - Immutable selector labels (app, instance)
  - forge.labels.merge      - Deep merge label maps

References:
  - https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Kubernetes Recommended Labels
Generates standard app.kubernetes.io/* labels

Labels:
  app.kubernetes.io/name          - Application name
  app.kubernetes.io/instance      - Release instance
  app.kubernetes.io/version       - Application version
  app.kubernetes.io/component     - Component within architecture
  app.kubernetes.io/part-of       - Higher level application
  app.kubernetes.io/managed-by    - Tool managing the resource (Helm)

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.kubernetes" -}}
app.kubernetes.io/name: {{ include "forge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.forge }}
  {{- if .Values.forge.component }}
app.kubernetes.io/component: {{ .Values.forge.component }}
  {{- end }}
  {{- if .Values.forge.partOf }}
app.kubernetes.io/part-of: {{ .Values.forge.partOf }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Forge Platform Labels
Generates moai.forge.io/* labels for Forge-specific metadata

Labels:
  forge.moai.io/customer-id  - Customer identifier
  forge.moai.io/project-id   - Project name
  forge.moai.io/service      - Service name
  forge.moai.io/environment  - Environment (dev, staging, prod)
  forge.moai.io/chart-type   - Chart name-version
  forge.moai.io/app-name     - Helm release name

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.forge" -}}
{{- if .Values.forge }}
  {{- if .Values.forge.customer }}
forge.moai.io/customer-id: {{ .Values.forge.customer }}
  {{- end }}
  {{- if .Values.forge.project }}
forge.moai.io/project-id: {{ .Values.forge.project }}
  {{- end }}
  {{- if .Values.forge.service }}
forge.moai.io/service: {{ .Values.forge.service }}
  {{- end }}
  {{- if .Values.forge.environment }}
forge.moai.io/environment: {{ .Values.forge.environment }}
  {{- end }}
{{- end }}
forge.moai.io/chart-type: {{ include "forge.chart" . }}
forge.moai.io/app-name: {{ .Release.Name }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Combined Labels
Merges Kubernetes + Forge + custom labels
Priority: custom labels override Forge labels override Kubernetes labels

Usage: {{ include "forge.labels" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels" -}}
{{ include "forge.labels.kubernetes" . }}
{{ include "forge.labels.forge" . }}
{{- if .Values.forge }}
  {{- if .Values.forge.commonLabels }}
{{ toYaml .Values.forge.commonLabels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Selector Labels (Immutable)
Returns ONLY immutable labels safe for selectors in Deployments, Services, etc.
Never include version or mutable metadata in selectors.

Labels:
  app.kubernetes.io/name     - Application name
  app.kubernetes.io/instance - Release instance

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "forge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Selector Labels with Component
Includes component in selector for multi-component apps

Labels:
  app.kubernetes.io/name      - Application name
  app.kubernetes.io/instance  - Release instance
  app.kubernetes.io/component - Component name

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.selectorLabelsWithComponent" -}}
{{ include "forge.selectorLabels" . }}
{{- if .Values.forge }}
  {{- if .Values.forge.component }}
app.kubernetes.io/component: {{ .Values.forge.component }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Merge Labels
Deep merge multiple label maps, with later maps overriding earlier ones
Usage: {{ include "forge.labels.merge" (dict "labels" (list .Values.labels1 .Values.labels2)) }}

Parameters:
  .labels - List of label maps to merge

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.merge" -}}
{{- $merged := dict -}}
{{- range .labels -}}
  {{- $merged = merge $merged . -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pod Labels
Labels specifically for Pod templates (includes all standard labels)
Usage: {{ include "forge.labels.pod" . | nindent 8 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.pod" -}}
{{ include "forge.labels" . }}
{{- if .Values.podLabels }}
{{ toYaml .Values.podLabels }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Service Labels
Labels for Service resources
Usage: {{ include "forge.labels.service" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.service" -}}
{{ include "forge.labels" . }}
{{- if .Values.service }}
  {{- if .Values.service.labels }}
{{ toYaml .Values.service.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Deployment Labels
Labels for Deployment metadata
Usage: {{ include "forge.labels.deployment" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.deployment" -}}
{{ include "forge.labels" . }}
{{- if .Values.deployment }}
  {{- if .Values.deployment.labels }}
{{ toYaml .Values.deployment.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Ingress Labels
Labels for Ingress resources
Usage: {{ include "forge.labels.ingress" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.ingress" -}}
{{ include "forge.labels" . }}
{{- if .Values.ingress }}
  {{- if .Values.ingress.labels }}
{{ toYaml .Values.ingress.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
ConfigMap Labels
Labels for ConfigMap resources
Usage: {{ include "forge.labels.configmap" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.configmap" -}}
{{ include "forge.labels" . }}
{{- if .Values.configMap }}
  {{- if .Values.configMap.labels }}
{{ toYaml .Values.configMap.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Secret Labels
Labels for Secret resources
Usage: {{ include "forge.labels.secret" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.secret" -}}
{{ include "forge.labels" . }}
{{- if .Values.secret }}
  {{- if .Values.secret.labels }}
{{ toYaml .Values.secret.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
ServiceAccount Labels
Labels for ServiceAccount resources
Usage: {{ include "forge.labels.serviceaccount" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.serviceaccount" -}}
{{ include "forge.labels" . }}
{{- if .Values.serviceAccount }}
  {{- if .Values.serviceAccount.labels }}
{{ toYaml .Values.serviceAccount.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
PersistentVolumeClaim Labels
Labels for PVC resources
Usage: {{ include "forge.labels.pvc" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.pvc" -}}
{{ include "forge.labels" . }}
{{- if .Values.persistence }}
  {{- if .Values.persistence.labels }}
{{ toYaml .Values.persistence.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Job Labels
Labels for Job resources
Usage: {{ include "forge.labels.job" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.job" -}}
{{ include "forge.labels" . }}
{{- if .Values.job }}
  {{- if .Values.job.labels }}
{{ toYaml .Values.job.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
CronJob Labels
Labels for CronJob resources
Usage: {{ include "forge.labels.cronjob" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.cronjob" -}}
{{ include "forge.labels" . }}
{{- if .Values.cronjob }}
  {{- if .Values.cronjob.labels }}
{{ toYaml .Values.cronjob.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
NetworkPolicy Labels
Labels for NetworkPolicy resources
Usage: {{ include "forge.labels.networkpolicy" . | nindent 4 }}

Returns: YAML map
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.networkpolicy" -}}
{{ include "forge.labels" . }}
{{- if .Values.networkPolicy }}
  {{- if .Values.networkPolicy.labels }}
{{ toYaml .Values.networkPolicy.labels }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Label Validation
Validates all labels in context and fails template if invalid
Usage: {{ include "forge.labels.validate" . }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.labels.validate" -}}
{{- $labels := include "forge.labels" . | fromYaml -}}
{{- $error := include "forge.validate.labels" $labels -}}
{{- if $error -}}
  {{- fail (printf "Label validation failed: %s" $error) -}}
{{- end -}}
{{- end -}}
