{{/*
==============================================================================
Forge Common Library - RBAC Templates
==============================================================================
Role, RoleBinding, ClusterRole, ClusterRoleBinding templates.
==============================================================================
*/}}

{{- define "k8s.role" -}}
{{- if .Values.rbac -}}
{{- if .Values.rbac.create -}}
{{- range .Values.rbac.roles }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .name | default (include "forge.resourceName" (dict "context" $ "type" "role")) }}
  namespace: {{ .namespace | default (include "forge.namespace" $) }}
  labels:
    {{- include "forge.labels" $ | nindent 4 }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
rules:
{{- toYaml .rules | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "k8s.rolebinding" -}}
{{- if .Values.rbac -}}
{{- if .Values.rbac.create -}}
{{- range .Values.rbac.roleBindings }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .name | default (include "forge.resourceName" (dict "context" $ "type" "rolebinding")) }}
  namespace: {{ .namespace | default (include "forge.namespace" $) }}
  labels:
    {{- include "forge.labels" $ | nindent 4 }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ .roleName | required "roleBinding.roleName is required" }}
subjects:
{{- toYaml .subjects | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "k8s.clusterrole" -}}
{{- if .Values.rbac -}}
{{- if .Values.rbac.create -}}
{{- range .Values.rbac.clusterRoles }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ .name | default (include "forge.resourceName" (dict "context" $ "type" "clusterrole")) }}
  labels:
    {{- include "forge.labels" $ | nindent 4 }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- with .aggregationRule }}
aggregationRule:
  {{- toYaml . | nindent 2 }}
{{- end }}
rules:
{{- toYaml .rules | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "k8s.clusterrolebinding" -}}
{{- if .Values.rbac -}}
{{- if .Values.rbac.create -}}
{{- range .Values.rbac.clusterRoleBindings }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ .name | default (include "forge.resourceName" (dict "context" $ "type" "clusterrolebinding")) }}
  labels:
    {{- include "forge.labels" $ | nindent 4 }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ .clusterRoleName | required "clusterRoleBinding.clusterRoleName is required" }}
subjects:
{{- toYaml .subjects | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
