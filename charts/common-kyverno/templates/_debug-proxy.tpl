{{/*
Debug Proxy - Helm Chart Templates
==============================================================================

These templates can be included in your application chart to deploy
the debug proxy infrastructure alongside your application.

Usage in Chart.yaml:
  dependencies:
    - name: common-kyverno
      version: ~0.1.0
      repository: file://../common-kyverno

Usage in templates/debug-proxy.yaml:
  {{- include "debugProxy.rbac" . }}
  {{- include "debugProxy.serviceAccount" . }}

==============================================================================
*/}}

{{/*
Debug Proxy: ServiceAccount
Creates the debug-proxy ServiceAccount in the application namespace.
*/}}
{{- define "debugProxy.serviceAccount" -}}
{{- if .Values.debugProxy -}}
{{- if .Values.debugProxy.enabled -}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.debugProxy.serviceAccountName | default "debug-proxy" }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    app.kubernetes.io/component: debug-proxy
  annotations:
    description: "ServiceAccount for controlled pod exec access via debug proxy"
    {{- with .Values.debugProxy.serviceAccountAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Debug Proxy: ClusterRole
Creates ClusterRole with minimal permissions (pods/exec only).
*/}}
{{- define "debugProxy.clusterRole" -}}
{{- if .Values.debugProxy -}}
{{- if .Values.debugProxy.enabled -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterrole" "name" "debug-proxy") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    app.kubernetes.io/component: debug-proxy
rules:
  # Allow exec into pods
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  
  # Allow reading pods (validation)
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  
  # Allow reading pod logs
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  
  {{- if .Values.debugProxy.allowAttach }}
  # Allow attach (optional)
  - apiGroups: [""]
    resources: ["pods/attach"]
    verbs: ["create"]
  {{- end }}
  
  {{- if .Values.debugProxy.allowPortForward }}
  # Allow port-forward (optional)
  - apiGroups: [""]
    resources: ["pods/portforward"]
    verbs: ["create"]
  {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Debug Proxy: ClusterRoleBinding
Binds the ClusterRole to the ServiceAccount.
*/}}
{{- define "debugProxy.clusterRoleBinding" -}}
{{- if .Values.debugProxy -}}
{{- if .Values.debugProxy.enabled -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterrolebinding" "name" "debug-proxy") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    app.kubernetes.io/component: debug-proxy
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterrole" "name" "debug-proxy") }}
subjects:
  - kind: ServiceAccount
    name: {{ .Values.debugProxy.serviceAccountName | default "debug-proxy" }}
    namespace: {{ include "forge.namespace" . }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Debug Proxy: Job Creator Role
Controls who can create debug jobs.
*/}}
{{- define "debugProxy.jobCreatorRole" -}}
{{- if .Values.debugProxy -}}
{{- if .Values.debugProxy.enabled -}}
{{- if .Values.debugProxy.allowJobCreation -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "role" "name" "debug-job-creator") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    app.kubernetes.io/component: debug-proxy
rules:
  # Allow creating/managing debug jobs
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get", "list", "delete"]
  
  # Allow reading job logs
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list"]
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Debug Proxy: Job Creator RoleBinding
Grants users/groups ability to create debug jobs.
*/}}
{{- define "debugProxy.jobCreatorRoleBinding" -}}
{{- if .Values.debugProxy -}}
{{- if .Values.debugProxy.enabled -}}
{{- if .Values.debugProxy.allowJobCreation -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "rolebinding" "name" "debug-job-creator") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    app.kubernetes.io/component: debug-proxy
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "forge.resourceName" (dict "context" . "type" "role" "name" "debug-job-creator") }}
subjects:
  {{- range .Values.debugProxy.allowedUsers }}
  - kind: User
    name: {{ . }}
    apiGroup: rbac.authorization.k8s.io
  {{- end }}
  {{- range .Values.debugProxy.allowedGroups }}
  - kind: Group
    name: {{ . }}
    apiGroup: rbac.authorization.k8s.io
  {{- end }}
  {{- range .Values.debugProxy.allowedServiceAccounts }}
  - kind: ServiceAccount
    name: {{ . }}
    namespace: {{ $.Values.debugProxy.allowedServiceAccountNamespace | default (include "forge.namespace" $) }}
  {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Debug Proxy: All Resources
Convenience template to deploy all debug proxy resources.
*/}}
{{- define "debugProxy.all" -}}
{{- include "debugProxy.serviceAccount" . }}
{{- include "debugProxy.clusterRole" . }}
{{- include "debugProxy.clusterRoleBinding" . }}
{{- include "debugProxy.jobCreatorRole" . }}
{{- include "debugProxy.jobCreatorRoleBinding" . }}
{{- end -}}
