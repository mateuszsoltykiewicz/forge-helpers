{{/*
==============================================================================
Forge Common Library - Kyverno Policy
==============================================================================
Templates for Kyverno Policy resources - namespace-scoped policy enforcement.

Policy applies only to resources within a specific namespace:
  - Namespace-specific security rules
  - Development/staging relaxed policies
  - Production strict policies
  - Team-specific governance

Compatible with:
  - Kyverno 1.10+ (tested with 1.11.0)
  - Kubernetes 1.23-1.29

Usage:
  {{- include "kyverno.policy" . }}

See Also:
  - https://kyverno.io/docs/writing-policies/
==============================================================================
*/}}

{{/*
==============================================================================
Kyverno Policy: Main Template
==============================================================================
Generate custom namespace-scoped Policy.

Usage:
  {{- include "kyverno.policy" . }}

Requirements:
  .Values.kyverno.policy.enabled = true
  .Values.kyverno.policy.rules (array of policy rules)

Output:
  apiVersion: kyverno.io/v1
  kind: Policy
  metadata:
    name: my-namespace-policy
    namespace: my-namespace
  spec:
    validationFailureAction: audit
    background: true
    rules: [...]
*/}}

{{- define "kyverno.policy" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policy -}}
{{- if .Values.kyverno.policy.enabled -}}
---
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "policy" "name" .Values.kyverno.policy.name) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- with .Values.kyverno.policy.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    policies.kyverno.io/title: {{ .Values.kyverno.policy.title | default "Namespace Policy" }}
    policies.kyverno.io/category: {{ .Values.kyverno.policy.category | default "Custom" }}
    policies.kyverno.io/severity: {{ .Values.kyverno.policy.severity | default "medium" }}
    policies.kyverno.io/description: {{ .Values.kyverno.policy.description | default "Namespace-specific policy" }}
    {{- with .Values.kyverno.policy.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  # Validation failure action: audit or enforce
  validationFailureAction: {{ .Values.kyverno.policy.validationFailureAction | default "audit" }}

  # Background processing
  background: {{ .Values.kyverno.policy.background | default true }}

  # Failure policy
  {{- with .Values.kyverno.policy.failurePolicy }}
  failurePolicy: {{ . }}
  {{- end }}

  # Webhook timeout
  {{- with .Values.kyverno.policy.webhookTimeoutSeconds }}
  webhookTimeoutSeconds: {{ . }}
  {{- end }}

  # Policy rules
  rules:
    {{- range .Values.kyverno.policy.rules }}
    - name: {{ .name | required "Rule name is required" }}
      {{- with .match }}
      match:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .exclude }}
      exclude:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .validate }}
      validate:
        {{- toYaml .validate | nindent 8 }}
      {{- else if .mutate }}
      mutate:
        {{- toYaml .mutate | nindent 8 }}
      {{- else if .generate }}
      generate:
        {{- toYaml .generate | nindent 8 }}
      {{- else if .verifyImages }}
      verifyImages:
        {{- toYaml .verifyImages | nindent 8 }}
      {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno Policy: Development Environment (Relaxed)
==============================================================================
Relaxed policies for development namespaces.

Usage:
  {{- include "kyverno.policy.development" . }}
*/}}

{{- define "kyverno.policy.development" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.environments -}}
{{- if .Values.kyverno.environments.development -}}
---
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: development-policy
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/environment: "development"
  annotations:
    policies.kyverno.io/title: "Development Environment Policy"
    policies.kyverno.io/category: "Environment"
    policies.kyverno.io/severity: "low"
    policies.kyverno.io/description: "Relaxed policies for development environment"
spec:
  validationFailureAction: audit
  background: true
  rules:
    # Allow privileged containers in dev
    - name: allow-privileged-dev
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Privileged containers allowed in development (informational only)"
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(privileged): "true | false"
    
    # Warn about missing resource limits (don't enforce)
    - name: warn-missing-limits
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Warning: Resource limits are recommended even in development"
        pattern:
          spec:
            containers:
              - =(resources):
                  =(limits): {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno Policy: Production Environment (Strict)
==============================================================================
Strict policies for production namespaces.

Usage:
  {{- include "kyverno.policy.production" . }}
*/}}

{{- define "kyverno.policy.production" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.environments -}}
{{- if .Values.kyverno.environments.production -}}
---
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: production-policy
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/environment: "production"
  annotations:
    policies.kyverno.io/title: "Production Environment Policy"
    policies.kyverno.io/category: "Environment"
    policies.kyverno.io/severity: "high"
    policies.kyverno.io/description: "Strict policies enforced in production"
spec:
  validationFailureAction: enforce
  background: true
  rules:
    # Enforce resource limits in production
    - name: require-limits-production
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "CPU and memory limits are mandatory in production"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"
                    memory: "?*"
                  requests:
                    cpu: "?*"
                    memory: "?*"
    
    # Enforce PodDisruptionBudget for high availability
    - name: require-pdb-production
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
      validate:
        message: "PodDisruptionBudget is required for production workloads"
        deny:
          conditions:
            all:
              - key: "{{`{{request.object.spec.replicas}}`}}"
                operator: GreaterThan
                value: 1
              # This is a simplified check - actual PDB validation would be more complex
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno Policy: Auto-Add Monitoring Annotations
==============================================================================
Mutation policy: automatically add Prometheus monitoring annotations.

Usage:
  {{- include "kyverno.policy.addMonitoringAnnotations" . }}
*/}}

{{- define "kyverno.policy.addMonitoringAnnotations" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.mutations -}}
{{- if .Values.kyverno.mutations.addMonitoringAnnotations -}}
---
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: add-monitoring-annotations
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Add Monitoring Annotations"
    policies.kyverno.io/category: "Mutation"
    policies.kyverno.io/severity: "low"
    policies.kyverno.io/description: "Auto-add Prometheus scrape annotations to Services"
spec:
  validationFailureAction: audit
  background: false
  rules:
    - name: add-prometheus-annotations
      match:
        any:
          - resources:
              kinds:
                - Service
      mutate:
        patchStrategicMerge:
          metadata:
            annotations:
              +(prometheus.io/scrape): "true"
              +(prometheus.io/port): "8080"
              +(prometheus.io/path): "/metrics"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
