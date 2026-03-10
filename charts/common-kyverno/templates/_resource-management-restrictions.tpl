{{/*
Resource Management Restrictions - Block direct resource manipulation
Users: Only allow automated systems (operators, jobs) to manage Kubernetes resources
Pattern: GitOps-only, no direct kubectl apply/create/delete by users
*/}}

{{/*
Block workload resource modifications (Deployments, StatefulSets, DaemonSets)
Only allow operators and deployment jobs to manage workloads
*/}}
{{- define "kyverno.resourceManagement.blockWorkloadModifications" -}}
{{- if .Values.kyverno.resourceManagement.blockWorkloadModifications.enabled }}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-workload-modifications
  annotations:
    policies.kyverno.io/title: "Block Workload Modifications"
    policies.kyverno.io/category: "Security, Resource Management"
    policies.kyverno.io/severity: {{ .Values.kyverno.resourceManagement.blockWorkloadModifications.severity | default "high" | quote }}
    policies.kyverno.io/subject: "Deployment, StatefulSet, DaemonSet"
    policies.kyverno.io/description: >-
      Prevents users from directly creating, updating, or deleting workload resources.
      Only operators and deployment jobs can manage workloads (GitOps pattern).
    {{- with .Values.kyverno.resourceManagement.blockWorkloadModifications.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "resource-management"
spec:
  validationFailureAction: {{ .Values.kyverno.resourceManagement.blockWorkloadModifications.action | default "enforce" }}
  failurePolicy: {{ .Values.kyverno.resourceManagement.blockWorkloadModifications.failurePolicy | default "Fail" }}
  background: false
  rules:
    - name: block-workload-modifications
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
                - DaemonSet
                - ReplicaSet
              operations:
                - CREATE
                - UPDATE
                - DELETE
      {{- if or .Values.kyverno.resourceManagement.blockWorkloadModifications.excludeNamespaces .Values.kyverno.resourceManagement.blockWorkloadModifications.excludeServiceAccounts .Values.kyverno.resourceManagement.blockWorkloadModifications.excludeUsers }}
      exclude:
        any:
          {{- with .Values.kyverno.resourceManagement.blockWorkloadModifications.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockWorkloadModifications.excludeServiceAccounts }}
          {{- range . }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockWorkloadModifications.excludeUsers }}
          {{- range . }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
      {{- end }}
      validate:
        message: >-
          {{ .Values.kyverno.resourceManagement.blockWorkloadModifications.message | default "Direct workload modifications are not allowed. Use Helm charts deployed via operators or deployment jobs." }}
        deny: {}
{{- end }}
{{- end }}

{{/*
Block service and networking resource modifications
Only allow operators to manage Services, Ingresses, NetworkPolicies
*/}}
{{- define "kyverno.resourceManagement.blockNetworkingModifications" -}}
{{- if .Values.kyverno.resourceManagement.blockNetworkingModifications.enabled }}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-networking-modifications
  annotations:
    policies.kyverno.io/title: "Block Networking Modifications"
    policies.kyverno.io/category: "Security, Resource Management"
    policies.kyverno.io/severity: {{ .Values.kyverno.resourceManagement.blockNetworkingModifications.severity | default "high" | quote }}
    policies.kyverno.io/subject: "Service, Ingress, NetworkPolicy"
    policies.kyverno.io/description: >-
      Prevents users from directly creating, updating, or deleting networking resources.
      Only operators can manage network configuration.
    {{- with .Values.kyverno.resourceManagement.blockNetworkingModifications.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "resource-management"
spec:
  validationFailureAction: {{ .Values.kyverno.resourceManagement.blockNetworkingModifications.action | default "enforce" }}
  failurePolicy: {{ .Values.kyverno.resourceManagement.blockNetworkingModifications.failurePolicy | default "Fail" }}
  background: false
  rules:
    - name: block-networking-modifications
      match:
        any:
          - resources:
              kinds:
                - Service
                - Ingress
                - NetworkPolicy
              operations:
                - CREATE
                - UPDATE
                - DELETE
      {{- if or .Values.kyverno.resourceManagement.blockNetworkingModifications.excludeNamespaces .Values.kyverno.resourceManagement.blockNetworkingModifications.excludeServiceAccounts .Values.kyverno.resourceManagement.blockNetworkingModifications.excludeUsers }}
      exclude:
        any:
          {{- with .Values.kyverno.resourceManagement.blockNetworkingModifications.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockNetworkingModifications.excludeServiceAccounts }}
          {{- range . }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockNetworkingModifications.excludeUsers }}
          {{- range . }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
      {{- end }}
      validate:
        message: >-
          {{ .Values.kyverno.resourceManagement.blockNetworkingModifications.message | default "Direct networking modifications are not allowed. Use Helm charts deployed via operators." }}
        deny: {}
{{- end }}
{{- end }}

{{/*
Block configuration resource modifications (ConfigMaps, Secrets)
Only allow operators and deployment jobs to manage configuration
*/}}
{{- define "kyverno.resourceManagement.blockConfigModifications" -}}
{{- if .Values.kyverno.resourceManagement.blockConfigModifications.enabled }}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-config-modifications
  annotations:
    policies.kyverno.io/title: "Block Configuration Modifications"
    policies.kyverno.io/category: "Security, Resource Management"
    policies.kyverno.io/severity: {{ .Values.kyverno.resourceManagement.blockConfigModifications.severity | default "medium" | quote }}
    policies.kyverno.io/subject: "ConfigMap, Secret"
    policies.kyverno.io/description: >-
      Prevents users from directly creating, updating, or deleting configuration resources.
      Only operators and deployment jobs can manage ConfigMaps and Secrets.
    {{- with .Values.kyverno.resourceManagement.blockConfigModifications.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "resource-management"
spec:
  validationFailureAction: {{ .Values.kyverno.resourceManagement.blockConfigModifications.action | default "enforce" }}
  failurePolicy: {{ .Values.kyverno.resourceManagement.blockConfigModifications.failurePolicy | default "Fail" }}
  background: false
  rules:
    - name: block-config-modifications
      match:
        any:
          - resources:
              kinds:
                - ConfigMap
                - Secret
              operations:
                - CREATE
                - UPDATE
                - DELETE
      {{- if or .Values.kyverno.resourceManagement.blockConfigModifications.excludeNamespaces .Values.kyverno.resourceManagement.blockConfigModifications.excludeServiceAccounts .Values.kyverno.resourceManagement.blockConfigModifications.excludeUsers }}
      exclude:
        any:
          {{- with .Values.kyverno.resourceManagement.blockConfigModifications.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockConfigModifications.excludeServiceAccounts }}
          {{- range . }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockConfigModifications.excludeUsers }}
          {{- range . }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
      {{- end }}
      validate:
        message: >-
          {{ .Values.kyverno.resourceManagement.blockConfigModifications.message | default "Direct configuration modifications are not allowed. Use Helm charts deployed via operators or deployment jobs." }}
        deny: {}
{{- end }}
{{- end }}

{{/*
Block storage resource modifications (PVCs, PVs)
Only allow operators to manage storage
*/}}
{{- define "kyverno.resourceManagement.blockStorageModifications" -}}
{{- if .Values.kyverno.resourceManagement.blockStorageModifications.enabled }}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-storage-modifications
  annotations:
    policies.kyverno.io/title: "Block Storage Modifications"
    policies.kyverno.io/category: "Security, Resource Management"
    policies.kyverno.io/severity: {{ .Values.kyverno.resourceManagement.blockStorageModifications.severity | default "high" | quote }}
    policies.kyverno.io/subject: "PersistentVolumeClaim, PersistentVolume"
    policies.kyverno.io/description: >-
      Prevents users from directly creating, updating, or deleting storage resources.
      Only operators can manage PVCs and PVs.
    {{- with .Values.kyverno.resourceManagement.blockStorageModifications.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "resource-management"
spec:
  validationFailureAction: {{ .Values.kyverno.resourceManagement.blockStorageModifications.action | default "enforce" }}
  failurePolicy: {{ .Values.kyverno.resourceManagement.blockStorageModifications.failurePolicy | default "Fail" }}
  background: false
  rules:
    - name: block-storage-modifications
      match:
        any:
          - resources:
              kinds:
                - PersistentVolumeClaim
                - PersistentVolume
              operations:
                - CREATE
                - UPDATE
                - DELETE
      {{- if or .Values.kyverno.resourceManagement.blockStorageModifications.excludeNamespaces .Values.kyverno.resourceManagement.blockStorageModifications.excludeServiceAccounts .Values.kyverno.resourceManagement.blockStorageModifications.excludeUsers }}
      exclude:
        any:
          {{- with .Values.kyverno.resourceManagement.blockStorageModifications.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockStorageModifications.excludeServiceAccounts }}
          {{- range . }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockStorageModifications.excludeUsers }}
          {{- range . }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
      {{- end }}
      validate:
        message: >-
          {{ .Values.kyverno.resourceManagement.blockStorageModifications.message | default "Direct storage modifications are not allowed. Use Helm charts deployed via operators." }}
        deny: {}
{{- end }}
{{- end }}

{{/*
Block RBAC resource modifications
Only allow cluster administrators to manage RBAC
*/}}
{{- define "kyverno.resourceManagement.blockRBACModifications" -}}
{{- if .Values.kyverno.resourceManagement.blockRBACModifications.enabled }}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-rbac-modifications
  annotations:
    policies.kyverno.io/title: "Block RBAC Modifications"
    policies.kyverno.io/category: "Security, Resource Management"
    policies.kyverno.io/severity: {{ .Values.kyverno.resourceManagement.blockRBACModifications.severity | default "critical" | quote }}
    policies.kyverno.io/subject: "Role, RoleBinding, ClusterRole, ClusterRoleBinding"
    policies.kyverno.io/description: >-
      Prevents users from directly creating, updating, or deleting RBAC resources.
      Only cluster administrators can manage permissions.
    {{- with .Values.kyverno.resourceManagement.blockRBACModifications.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "resource-management"
spec:
  validationFailureAction: {{ .Values.kyverno.resourceManagement.blockRBACModifications.action | default "enforce" }}
  failurePolicy: {{ .Values.kyverno.resourceManagement.blockRBACModifications.failurePolicy | default "Fail" }}
  background: false
  rules:
    - name: block-rbac-modifications
      match:
        any:
          - resources:
              kinds:
                - Role
                - RoleBinding
                - ClusterRole
                - ClusterRoleBinding
              operations:
                - CREATE
                - UPDATE
                - DELETE
      {{- if or .Values.kyverno.resourceManagement.blockRBACModifications.excludeNamespaces .Values.kyverno.resourceManagement.blockRBACModifications.excludeServiceAccounts .Values.kyverno.resourceManagement.blockRBACModifications.excludeUsers }}
      exclude:
        any:
          {{- with .Values.kyverno.resourceManagement.blockRBACModifications.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockRBACModifications.excludeServiceAccounts }}
          {{- range . }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
          {{- with .Values.kyverno.resourceManagement.blockRBACModifications.excludeUsers }}
          {{- range . }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- end }}
      {{- end }}
      validate:
        message: >-
          {{ .Values.kyverno.resourceManagement.blockRBACModifications.message | default "Direct RBAC modifications are not allowed. Contact cluster administrators." }}
        deny: {}
{{- end }}
{{- end }}

{{/*
Convenience template: Block all resource modifications
Includes workloads, networking, config, storage, and RBAC
*/}}
{{- define "kyverno.resourceManagement.blockAll" -}}
{{- include "kyverno.resourceManagement.blockWorkloadModifications" . }}
{{- include "kyverno.resourceManagement.blockNetworkingModifications" . }}
{{- include "kyverno.resourceManagement.blockConfigModifications" . }}
{{- include "kyverno.resourceManagement.blockStorageModifications" . }}
{{- include "kyverno.resourceManagement.blockRBACModifications" . }}
{{- end }}
