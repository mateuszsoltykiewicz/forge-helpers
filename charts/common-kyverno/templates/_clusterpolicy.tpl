{{/*
==============================================================================
Forge Common Library - Kyverno ClusterPolicy
==============================================================================
Templates for Kyverno ClusterPolicy resources - cluster-wide policy enforcement.

ClusterPolicy applies to all namespaces and resources in the cluster:
  - Security policies (no privileged containers, enforce pod security standards)
  - Best practice policies (required labels, resource limits)
  - Compliance policies (regulatory requirements, audit logging)
  - Image verification (signed images, trusted registries)
  - Mutation policies (auto-inject sidecars, set defaults)
  - Generation policies (auto-create NetworkPolicies, RBAC)

Compatible with:
  - Kyverno 1.10+ (tested with 1.11.0)
  - Kubernetes 1.23-1.29
  - Pod Security Standards (PSS) - Baseline/Restricted

Usage:
  {{- include "kyverno.clusterpolicy" . }}

See Also:
  - https://kyverno.io/docs/writing-policies/
  - https://kyverno.io/policies/
==============================================================================
*/}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Main Template
==============================================================================
Generate custom ClusterPolicy with validation/mutation/generation rules.

Usage:
  {{- include "kyverno.clusterpolicy" . }}

Requirements:
  .Values.kyverno.clusterpolicy.enabled = true
  .Values.kyverno.clusterpolicy.rules (array of policy rules)

Output:
  apiVersion: kyverno.io/v1
  kind: ClusterPolicy
  metadata:
    name: forge-security-policy
  spec:
    validationFailureAction: audit
    background: true
    rules: [...]
*/}}

{{- define "kyverno.clusterpolicy" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.clusterpolicy -}}
{{- if .Values.kyverno.clusterpolicy.enabled -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterpolicy" "name" .Values.kyverno.clusterpolicy.name) }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- with .Values.kyverno.clusterpolicy.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    policies.kyverno.io/title: {{ .Values.kyverno.clusterpolicy.title | default "Forge Security Policy" }}
    policies.kyverno.io/category: {{ .Values.kyverno.clusterpolicy.category | default "Security" }}
    policies.kyverno.io/severity: {{ .Values.kyverno.clusterpolicy.severity | default "medium" }}
    policies.kyverno.io/description: {{ .Values.kyverno.clusterpolicy.description | default "Forge platform security policy" }}
    {{- with .Values.kyverno.clusterpolicy.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  # Validation failure action: audit (log only) or enforce (block)
  validationFailureAction: {{ .Values.kyverno.clusterpolicy.validationFailureAction | default "audit" }}

  # Background processing (scan existing resources)
  background: {{ .Values.kyverno.clusterpolicy.background | default true }}

  # Failure policy (Fail or Ignore)
  {{- with .Values.kyverno.clusterpolicy.failurePolicy }}
  failurePolicy: {{ . }}
  {{- end }}

  # Webhook timeout
  {{- with .Values.kyverno.clusterpolicy.webhookTimeoutSeconds }}
  webhookTimeoutSeconds: {{ . }}
  {{- end }}

  # Policy rules
  rules:
    {{- range .Values.kyverno.clusterpolicy.rules }}
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
Kyverno ClusterPolicy: Require Non-Root Containers
==============================================================================
Security policy: containers must not run as root (UID 0).

Usage:
  {{- include "kyverno.clusterpolicy.requireNonRoot" . }}
*/}}

{{- define "kyverno.clusterpolicy.requireNonRoot" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.requireNonRoot -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-non-root-containers
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Require Non-Root Containers"
    policies.kyverno.io/category: "Pod Security Standards (Restricted)"
    policies.kyverno.io/severity: "high"
    policies.kyverno.io/description: "Containers must run as non-root user (UID != 0)"
spec:
  validationFailureAction: {{ .Values.kyverno.policies.requireNonRoot.action | default "audit" }}
  background: true
  rules:
    - name: check-runAsNonRoot
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Containers must run as non-root user (set securityContext.runAsNonRoot=true)"
        pattern:
          spec:
            securityContext:
              runAsNonRoot: true
            containers:
              - securityContext:
                  runAsNonRoot: true
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Disallow Privileged Containers
==============================================================================
Security policy: containers must not run in privileged mode.

Usage:
  {{- include "kyverno.clusterpolicy.disallowPrivileged" . }}
*/}}

{{- define "kyverno.clusterpolicy.disallowPrivileged" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.disallowPrivileged -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Disallow Privileged Containers"
    policies.kyverno.io/category: "Pod Security Standards (Baseline)"
    policies.kyverno.io/severity: "high"
    policies.kyverno.io/description: "Privileged mode disables most security mechanisms and must not be allowed"
spec:
  validationFailureAction: {{ .Values.kyverno.policies.disallowPrivileged.action | default "enforce" }}
  background: true
  rules:
    - name: check-privileged
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Privileged mode is disallowed. Set privileged=false in securityContext."
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(privileged): false
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Require Resource Limits
==============================================================================
Best practice policy: all containers must have CPU and memory limits.

Usage:
  {{- include "kyverno.clusterpolicy.requireResourceLimits" . }}
*/}}

{{- define "kyverno.clusterpolicy.requireResourceLimits" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.requireResourceLimits -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Require Resource Limits"
    policies.kyverno.io/category: "Best Practices"
    policies.kyverno.io/severity: "medium"
    policies.kyverno.io/description: "All containers must have CPU and memory limits defined"
spec:
  validationFailureAction: {{ .Values.kyverno.policies.requireResourceLimits.action | default "audit" }}
  background: true
  rules:
    - name: check-cpu-memory-limits
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "CPU and memory limits are required for all containers"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"
                    memory: "?*"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Require Read-Only Root Filesystem
==============================================================================
Security policy: containers should use read-only root filesystem.

Usage:
  {{- include "kyverno.clusterpolicy.requireReadOnlyRoot" . }}
*/}}

{{- define "kyverno.clusterpolicy.requireReadOnlyRoot" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.requireReadOnlyRoot -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-ro-rootfs
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Require Read-Only Root Filesystem"
    policies.kyverno.io/category: "Pod Security Standards (Restricted)"
    policies.kyverno.io/severity: "medium"
    policies.kyverno.io/description: "Containers should use read-only root filesystem to prevent malicious writes"
spec:
  validationFailureAction: {{ .Values.kyverno.policies.requireReadOnlyRoot.action | default "audit" }}
  background: true
  rules:
    - name: check-readOnlyRootFilesystem
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Root filesystem must be read-only. Set securityContext.readOnlyRootFilesystem=true"
        pattern:
          spec:
            containers:
              - securityContext:
                  readOnlyRootFilesystem: true
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Require Forge Labels
==============================================================================
Best practice policy: all resources must have required Forge labels.

Usage:
  {{- include "kyverno.clusterpolicy.requireForgeLabels" . }}
*/}}

{{- define "kyverno.clusterpolicy.requireForgeLabels" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.requireForgeLabels -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-forge-labels
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Require Forge Labels"
    policies.kyverno.io/category: "Forge Best Practices"
    policies.kyverno.io/severity: "low"
    policies.kyverno.io/description: "Resources must have required Forge labels for tracking and organization"
spec:
  validationFailureAction: {{ .Values.kyverno.policies.requireForgeLabels.action | default "audit" }}
  background: true
  rules:
    - name: check-forge-labels
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
                - DaemonSet
                - Service
      validate:
        message: "Required Forge labels are missing: app.kubernetes.io/name, app.kubernetes.io/instance, moai.forge.io/component"
        pattern:
          metadata:
            labels:
              app.kubernetes.io/name: "?*"
              app.kubernetes.io/instance: "?*"
              moai.forge.io/component: "?*"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Disallow Latest Tag
==============================================================================
Best practice policy: container images must not use :latest tag.

Usage:
  {{- include "kyverno.clusterpolicy.disallowLatestTag" . }}
*/}}

{{- define "kyverno.clusterpolicy.disallowLatestTag" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.disallowLatestTag -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Disallow Latest Tag"
    policies.kyverno.io/category: "Best Practices"
    policies.kyverno.io/severity: "medium"
    policies.kyverno.io/description: "Container images must use specific version tags, not :latest"
spec:
  validationFailureAction: {{ .Values.kyverno.policies.disallowLatestTag.action | default "audit" }}
  background: true
  rules:
    - name: check-image-tag
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Image tag :latest is not allowed. Use a specific version tag."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Kyverno ClusterPolicy: Add Default NetworkPolicy
==============================================================================
Generation policy: auto-create default deny NetworkPolicy for new namespaces.

Usage:
  {{- include "kyverno.clusterpolicy.addDefaultNetworkPolicy" . }}
*/}}

{{- define "kyverno.clusterpolicy.addDefaultNetworkPolicy" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.policies -}}
{{- if .Values.kyverno.policies.addDefaultNetworkPolicy -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-networkpolicy
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: "Add Default NetworkPolicy"
    policies.kyverno.io/category: "Security"
    policies.kyverno.io/severity: "medium"
    policies.kyverno.io/description: "Auto-create default deny NetworkPolicy for new namespaces"
spec:
  validationFailureAction: audit
  background: false
  rules:
    - name: generate-default-deny-networkpolicy
      match:
        any:
          - resources:
              kinds:
                - Namespace
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kube-public
                - kube-node-lease
                - kyverno
      generate:
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        name: default-deny-all
        namespace: "{{`{{request.object.metadata.name}}`}}"
        synchronize: true
        data:
          spec:
            podSelector: {}
            policyTypes:
              - Ingress
              - Egress
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
