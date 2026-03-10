{{/*
==============================================================================
Forge Common Library - ArgoCD Application
==============================================================================
Templates for ArgoCD Application resources - declarative GitOps deployment.

Application defines a single application to be deployed from a Git repository:
  - Git source configuration (repo, path, revision)
  - Destination cluster and namespace
  - Sync policies (automated, self-heal, prune)
  - Sync waves and hooks for ordering
  - Helm parameter overrides
  - Ignore differences for dynamic fields

Compatible with:
  - ArgoCD 2.8+ (tested with 2.10.0)
  - Kubernetes 1.23-1.29

Usage:
  {{- include "argocd.application" . }}

See Also:
  - https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/
==============================================================================
*/}}

{{/*
==============================================================================
ArgoCD Application: Main Template
==============================================================================
Generate ArgoCD Application resource.

Usage:
  {{- include "argocd.application" . }}

Requirements:
  .Values.argocd.application.enabled = true
  .Values.argocd.application.source.repoURL (Git repository URL)
  .Values.argocd.application.source.path (path to Helm chart)
  .Values.argocd.application.destination.server (Kubernetes API server)
  .Values.argocd.application.destination.namespace (target namespace)

Output:
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: my-application
    namespace: argocd
  spec:
    project: default
    source:
      repoURL: https://github.com/org/repo
      targetRevision: main
      path: charts/my-app
      helm:
        parameters: [...]
        values: |
          ...
    destination:
      server: https://kubernetes.default.svc
      namespace: my-namespace
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
*/}}

{{- define "argocd.application" -}}
{{- if .Values.argocd -}}
{{- if .Values.argocd.application -}}
{{- if .Values.argocd.application.enabled -}}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "application" "name" .Values.argocd.application.name) }}
  namespace: {{ .Values.argocd.application.namespace | default "argocd" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- with .Values.argocd.application.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with .Values.argocd.application.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- if .Values.argocd.application.finalizers }}
  finalizers:
    {{- toYaml .Values.argocd.application.finalizers | nindent 4 }}
  {{- end }}
spec:
  # ArgoCD project
  project: {{ .Values.argocd.application.project | default "default" }}

  # Source configuration
  source:
    # Git repository URL
    repoURL: {{ .Values.argocd.application.source.repoURL | required "argocd.application.source.repoURL is required" }}
    
    # Target revision (branch, tag, commit SHA)
    targetRevision: {{ .Values.argocd.application.source.targetRevision | default "HEAD" }}
    
    # Path to Helm chart or Kubernetes manifests
    {{- with .Values.argocd.application.source.path }}
    path: {{ . }}
    {{- end }}
    
    # Chart name (for Helm chart in Helm repository)
    {{- with .Values.argocd.application.source.chart }}
    chart: {{ . }}
    {{- end }}

    {{- if .Values.argocd.application.source.helm }}
    # Helm-specific configuration
    helm:
      {{- with .Values.argocd.application.source.helm.releaseName }}
      releaseName: {{ . }}
      {{- end }}

      {{- with .Values.argocd.application.source.helm.values }}
      # Inline values
      values: |
        {{- . | nindent 8 }}
      {{- end }}

      {{- with .Values.argocd.application.source.helm.valueFiles }}
      # Value files from repo
      valueFiles:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.argocd.application.source.helm.parameters }}
      # Helm parameters
      parameters:
        {{- range . }}
        - name: {{ .name | required "Helm parameter name is required" }}
          value: {{ .value | required "Helm parameter value is required" | quote }}
          {{- with .forceString }}
          forceString: {{ . }}
          {{- end }}
        {{- end }}
      {{- end }}

      {{- with .Values.argocd.application.source.helm.fileParameters }}
      # File parameters
      fileParameters:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.argocd.application.source.helm.version }}
      # Helm version
      version: {{ . }}
      {{- end }}

      {{- if hasKey .Values.argocd.application.source.helm "passCredentials" }}
      # Pass credentials
      passCredentials: {{ .Values.argocd.application.source.helm.passCredentials }}
      {{- end }}

      {{- if hasKey .Values.argocd.application.source.helm "skipCrds" }}
      # Skip CRDs
      skipCrds: {{ .Values.argocd.application.source.helm.skipCrds }}
      {{- end }}
    {{- end }}

    {{- if .Values.argocd.application.source.kustomize }}
    # Kustomize-specific configuration
    kustomize:
      {{- with .Values.argocd.application.source.kustomize.namePrefix }}
      namePrefix: {{ . }}
      {{- end }}
      {{- with .Values.argocd.application.source.kustomize.nameSuffix }}
      nameSuffix: {{ . }}
      {{- end }}
      {{- with .Values.argocd.application.source.kustomize.images }}
      images:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.argocd.application.source.kustomize.commonLabels }}
      commonLabels:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.argocd.application.source.kustomize.commonAnnotations }}
      commonAnnotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}

    {{- if .Values.argocd.application.source.directory }}
    # Directory-specific configuration
    directory:
      {{- with .Values.argocd.application.source.directory.recurse }}
      recurse: {{ . }}
      {{- end }}
      {{- with .Values.argocd.application.source.directory.jsonnet }}
      jsonnet:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}

  # Destination configuration
  destination:
    # Kubernetes API server URL
    {{- if .Values.argocd.application.destination.server }}
    server: {{ .Values.argocd.application.destination.server }}
    {{- else if .Values.argocd.application.destination.name }}
    name: {{ .Values.argocd.application.destination.name }}
    {{- else }}
    server: https://kubernetes.default.svc
    {{- end }}
    
    # Target namespace
    namespace: {{ .Values.argocd.application.destination.namespace | required "argocd.application.destination.namespace is required" }}

  {{- if .Values.argocd.application.syncPolicy }}
  # Sync policy
  syncPolicy:
    {{- if .Values.argocd.application.syncPolicy.automated }}
    # Automated sync
    automated:
      # Prune resources
      prune: {{ .Values.argocd.application.syncPolicy.automated.prune | default false }}
      
      # Self-heal
      selfHeal: {{ .Values.argocd.application.syncPolicy.automated.selfHeal | default false }}
      
      {{- with .Values.argocd.application.syncPolicy.automated.allowEmpty }}
      # Allow empty
      allowEmpty: {{ . }}
      {{- end }}
    {{- end }}

    {{- with .Values.argocd.application.syncPolicy.syncOptions }}
    # Sync options
    syncOptions:
      {{- toYaml . | nindent 6 }}
    {{- end }}

    {{- if .Values.argocd.application.syncPolicy.retry }}
    # Retry policy
    retry:
      limit: {{ .Values.argocd.application.syncPolicy.retry.limit | default 5 }}
      backoff:
        duration: {{ .Values.argocd.application.syncPolicy.retry.backoff.duration | default "5s" }}
        factor: {{ .Values.argocd.application.syncPolicy.retry.backoff.factor | default 2 }}
        maxDuration: {{ .Values.argocd.application.syncPolicy.retry.backoff.maxDuration | default "3m" }}
    {{- end }}

    {{- with .Values.argocd.application.syncPolicy.managedNamespaceMetadata }}
    # Managed namespace metadata
    managedNamespaceMetadata:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- end }}

  {{- with .Values.argocd.application.ignoreDifferences }}
  # Ignore differences (for dynamic fields)
  ignoreDifferences:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  {{- with .Values.argocd.application.info }}
  # Additional info
  info:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  {{- if .Values.argocd.application.revisionHistoryLimit }}
  # Revision history limit
  revisionHistoryLimit: {{ .Values.argocd.application.revisionHistoryLimit }}
  {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
ArgoCD Application: Sync Waves Helper
==============================================================================
Generate sync wave annotation for resource ordering.

Usage:
  annotations:
    {{- include "argocd.syncWave" 5 | nindent 4 }}

Output:
  argocd.argoproj.io/sync-wave: "5"
*/}}

{{- define "argocd.syncWave" -}}
argocd.argoproj.io/sync-wave: {{ . | quote }}
{{- end -}}

{{/*
==============================================================================
ArgoCD Application: Sync Hook Helper
==============================================================================
Generate sync hook annotation for lifecycle management.

Usage:
  annotations:
    {{- include "argocd.syncHook" "PreSync" | nindent 4 }}

Hooks:
  - PreSync: Before sync
  - Sync: During sync
  - PostSync: After sync
  - SyncFail: On sync failure
  - Skip: Skip resource

Output:
  argocd.argoproj.io/hook: PreSync
*/}}

{{- define "argocd.syncHook" -}}
argocd.argoproj.io/hook: {{ . }}
{{- end -}}

{{/*
==============================================================================
ArgoCD Application: Hook Delete Policy Helper
==============================================================================
Generate hook deletion policy annotation.

Usage:
  annotations:
    {{- include "argocd.hookDeletePolicy" "HookSucceeded" | nindent 4 }}

Policies:
  - HookSucceeded: Delete after successful hook
  - HookFailed: Delete after failed hook
  - BeforeHookCreation: Delete before new hook created

Output:
  argocd.argoproj.io/hook-delete-policy: HookSucceeded
*/}}

{{- define "argocd.hookDeletePolicy" -}}
argocd.argoproj.io/hook-delete-policy: {{ . }}
{{- end -}}
