{{/*
==============================================================================
Forge Common Library - ArgoCD ApplicationSet
==============================================================================
Templates for ArgoCD ApplicationSet resources - multi-environment deployment.

ApplicationSet provides powerful patterns for managing multiple Applications:
  - List Generator: Explicit list of environments/clusters
  - Git Generator: Discover from Git repository structure
  - Cluster Generator: Discover from Kubernetes clusters
  - Matrix Generator: Combine multiple generators
  - Progressive rollout strategies

Compatible with:
  - ArgoCD 2.8+ (tested with 2.10.0)
  - Kubernetes 1.23-1.29

Usage:
  {{- include "argocd.applicationset" . }}

See Also:
  - https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/
==============================================================================
*/}}

{{/*
==============================================================================
ArgoCD ApplicationSet: Main Template
==============================================================================
Generate ArgoCD ApplicationSet resource with generators.

Usage:
  {{- include "argocd.applicationset" . }}

Requirements:
  .Values.argocd.applicationset.enabled = true
  .Values.argocd.applicationset.generators (at least one generator)

Output:
  apiVersion: argoproj.io/v1alpha1
  kind: ApplicationSet
  metadata:
    name: my-applicationset
    namespace: argocd
  spec:
    generators:
      - list:
          elements:
            - env: dev
              cluster: https://dev-cluster
            - env: prod
              cluster: https://prod-cluster
    template:
      metadata:
        name: '{{env}}-my-app'
      spec:
        source:
          repoURL: https://github.com/org/repo
          path: charts/my-app
        destination:
          server: '{{cluster}}'
          namespace: my-app-{{env}}
*/}}

{{- define "argocd.applicationset" -}}
{{- if .Values.argocd -}}
{{- if .Values.argocd.applicationset -}}
{{- if .Values.argocd.applicationset.enabled -}}
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "applicationset" "name" .Values.argocd.applicationset.name) }}
  namespace: {{ .Values.argocd.applicationset.namespace | default "argocd" }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- with .Values.argocd.applicationset.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with .Values.argocd.applicationset.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  # Generators define how to create Applications
  generators:
    {{- if .Values.argocd.applicationset.generators.list }}
    # List Generator: Explicit list of environments
    - list:
        elements:
          {{- toYaml .Values.argocd.applicationset.generators.list.elements | nindent 10 }}
        {{- with .Values.argocd.applicationset.generators.list.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- if .Values.argocd.applicationset.generators.git }}
    # Git Generator: Discover from Git repository
    - git:
        repoURL: {{ .Values.argocd.applicationset.generators.git.repoURL | required "Git generator repoURL is required" }}
        revision: {{ .Values.argocd.applicationset.generators.git.revision | default "HEAD" }}
        
        {{- if .Values.argocd.applicationset.generators.git.directories }}
        # Directory-based discovery
        directories:
          {{- toYaml .Values.argocd.applicationset.generators.git.directories | nindent 10 }}
        {{- end }}

        {{- if .Values.argocd.applicationset.generators.git.files }}
        # File-based discovery
        files:
          {{- toYaml .Values.argocd.applicationset.generators.git.files | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.generators.git.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- if .Values.argocd.applicationset.generators.cluster }}
    # Cluster Generator: Discover from Kubernetes clusters
    - cluster:
        {{- with .Values.argocd.applicationset.generators.cluster.selector }}
        selector:
          {{- toYaml . | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.generators.cluster.values }}
        values:
          {{- toYaml . | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.generators.cluster.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- if .Values.argocd.applicationset.generators.matrix }}
    # Matrix Generator: Combine multiple generators
    - matrix:
        generators:
          {{- toYaml .Values.argocd.applicationset.generators.matrix.generators | nindent 10 }}

        {{- with .Values.argocd.applicationset.generators.matrix.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- if .Values.argocd.applicationset.generators.merge }}
    # Merge Generator: Merge parameters from multiple generators
    - merge:
        mergeKeys:
          {{- toYaml .Values.argocd.applicationset.generators.merge.mergeKeys | nindent 10 }}
        generators:
          {{- toYaml .Values.argocd.applicationset.generators.merge.generators | nindent 10 }}

        {{- with .Values.argocd.applicationset.generators.merge.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- if .Values.argocd.applicationset.generators.pullRequest }}
    # Pull Request Generator: Create Applications for PRs
    - pullRequest:
        {{- if .Values.argocd.applicationset.generators.pullRequest.github }}
        github:
          {{- toYaml .Values.argocd.applicationset.generators.pullRequest.github | nindent 10 }}
        {{- else if .Values.argocd.applicationset.generators.pullRequest.gitlab }}
        gitlab:
          {{- toYaml .Values.argocd.applicationset.generators.pullRequest.gitlab | nindent 10 }}
        {{- else if .Values.argocd.applicationset.generators.pullRequest.gitea }}
        gitea:
          {{- toYaml .Values.argocd.applicationset.generators.pullRequest.gitea | nindent 10 }}
        {{- else if .Values.argocd.applicationset.generators.pullRequest.bitbucket }}
        bitbucketServer:
          {{- toYaml .Values.argocd.applicationset.generators.pullRequest.bitbucket | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.generators.pullRequest.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- if .Values.argocd.applicationset.generators.scmProvider }}
    # SCM Provider Generator: Discover repositories
    - scmProvider:
        {{- if .Values.argocd.applicationset.generators.scmProvider.github }}
        github:
          {{- toYaml .Values.argocd.applicationset.generators.scmProvider.github | nindent 10 }}
        {{- else if .Values.argocd.applicationset.generators.scmProvider.gitlab }}
        gitlab:
          {{- toYaml .Values.argocd.applicationset.generators.scmProvider.gitlab | nindent 10 }}
        {{- else if .Values.argocd.applicationset.generators.scmProvider.gitea }}
        gitea:
          {{- toYaml .Values.argocd.applicationset.generators.scmProvider.gitea | nindent 10 }}
        {{- else if .Values.argocd.applicationset.generators.scmProvider.bitbucket }}
        bitbucketServer:
          {{- toYaml .Values.argocd.applicationset.generators.scmProvider.bitbucket | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.generators.scmProvider.template }}
        template:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    {{- end }}

    {{- with .Values.argocd.applicationset.generators.custom }}
    # Custom generators
    {{- toYaml . | nindent 4 }}
    {{- end }}

  # Application template
  template:
    metadata:
      name: {{ .Values.argocd.applicationset.template.metadata.name | required "ApplicationSet template name is required" }}
      {{- with .Values.argocd.applicationset.template.metadata.namespace }}
      namespace: {{ . }}
      {{- end }}
      {{- with .Values.argocd.applicationset.template.metadata.labels }}
      labels:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.argocd.applicationset.template.metadata.annotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.argocd.applicationset.template.metadata.finalizers }}
      finalizers:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      # Project
      project: {{ .Values.argocd.applicationset.template.spec.project | default "default" }}

      # Source
      source:
        repoURL: {{ .Values.argocd.applicationset.template.spec.source.repoURL | required "ApplicationSet template source.repoURL is required" }}
        targetRevision: {{ .Values.argocd.applicationset.template.spec.source.targetRevision | default "HEAD" }}
        
        {{- with .Values.argocd.applicationset.template.spec.source.path }}
        path: {{ . }}
        {{- end }}

        {{- with .Values.argocd.applicationset.template.spec.source.chart }}
        chart: {{ . }}
        {{- end }}

        {{- with .Values.argocd.applicationset.template.spec.source.helm }}
        helm:
          {{- toYaml . | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.template.spec.source.kustomize }}
        kustomize:
          {{- toYaml . | nindent 10 }}
        {{- end }}

        {{- with .Values.argocd.applicationset.template.spec.source.directory }}
        directory:
          {{- toYaml . | nindent 10 }}
        {{- end }}

      # Destination
      destination:
        {{- if .Values.argocd.applicationset.template.spec.destination.server }}
        server: {{ .Values.argocd.applicationset.template.spec.destination.server }}
        {{- else if .Values.argocd.applicationset.template.spec.destination.name }}
        name: {{ .Values.argocd.applicationset.template.spec.destination.name }}
        {{- else }}
        server: https://kubernetes.default.svc
        {{- end }}
        namespace: {{ .Values.argocd.applicationset.template.spec.destination.namespace | required "ApplicationSet template destination.namespace is required" }}

      {{- with .Values.argocd.applicationset.template.spec.syncPolicy }}
      # Sync policy
      syncPolicy:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.argocd.applicationset.template.spec.ignoreDifferences }}
      # Ignore differences
      ignoreDifferences:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.argocd.applicationset.template.spec.info }}
      # Additional info
      info:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.argocd.applicationset.template.spec.revisionHistoryLimit }}
      # Revision history limit
      revisionHistoryLimit: {{ . }}
      {{- end }}

  {{- if .Values.argocd.applicationset.syncPolicy }}
  # ApplicationSet sync policy
  syncPolicy:
    {{- with .Values.argocd.applicationset.syncPolicy.preserveResourcesOnDeletion }}
    # Preserve Applications when ApplicationSet is deleted
    preserveResourcesOnDeletion: {{ . }}
    {{- end }}

    {{- if .Values.argocd.applicationset.syncPolicy.applicationsSync }}
    # Sync policy for generated Applications
    applicationsSync: {{ .Values.argocd.applicationset.syncPolicy.applicationsSync }}
    {{- end }}
  {{- end }}

  {{- with .Values.argocd.applicationset.strategy }}
  # Progressive rollout strategy
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
