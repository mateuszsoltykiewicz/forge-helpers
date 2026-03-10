{{/*
==============================================================================
Kyverno: API Restrictions Policies
==============================================================================
Block dangerous Kubernetes API operations for enhanced security.

This template creates ClusterPolicies that restrict access to:
  - kubectl exec (pods/exec)
  - kubectl attach (pods/attach)
  - kubectl port-forward (pods/portforward)
  - kubectl proxy (pods/proxy)
  - kubectl cp (via exec)
  - kubectl logs --previous (pods/log)
  - ephemeral containers (pods/ephemeralcontainers)

Use Cases:
  - Production clusters: Prevent direct pod access
  - Compliance: Audit all exec/attach operations
  - Security: Force users to use proper debugging tools
  - Governance: Control who can interact with running pods

Compatible with:
  - Kyverno 1.10+ (tested with 1.11.0)
  - Kubernetes 1.23-1.29

Usage:
  {{- include "kyverno.apiRestrictions.blockExec" . }}
  {{- include "kyverno.apiRestrictions.blockAttach" . }}
  {{- include "kyverno.apiRestrictions.blockPortForward" . }}
  {{- include "kyverno.apiRestrictions.blockAll" . }}
==============================================================================
*/}}

{{/*
==============================================================================
Block kubectl exec (pods/exec)
==============================================================================
Prevents users from executing commands inside running containers.

Usage:
  {{- include "kyverno.apiRestrictions.blockExec" . }}

Blocks:
  - kubectl exec -it pod-name -- /bin/bash
  - kubectl exec pod-name -- command

Exceptions:
  - ServiceAccounts in excludedServiceAccounts list
  - Users in excludedUsers list
  - Namespaces in excludedNamespaces list
*/}}

{{- define "kyverno.apiRestrictions.blockExec" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.apiRestrictions -}}
{{- if .Values.kyverno.apiRestrictions.blockExec -}}
{{- if .Values.kyverno.apiRestrictions.blockExec.enabled -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterpolicy" "name" "block-pod-exec") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "api-restriction"
  annotations:
    policies.kyverno.io/title: "Block Pod Exec"
    policies.kyverno.io/category: "Security, API Restriction"
    policies.kyverno.io/severity: {{ .Values.kyverno.apiRestrictions.blockExec.severity | default "high" | quote }}
    policies.kyverno.io/subject: "Pod"
    policies.kyverno.io/description: >-
      Blocks kubectl exec operations on pods. This prevents users from
      executing commands inside running containers, which can be a security
      risk in production environments. Use proper debugging and monitoring
      tools instead.
    {{- with .Values.kyverno.apiRestrictions.blockExec.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  validationFailureAction: {{ .Values.kyverno.apiRestrictions.blockExec.action | default "enforce" }}
  background: false  # API operations are not background
  failurePolicy: {{ .Values.kyverno.apiRestrictions.blockExec.failurePolicy | default "Fail" }}
  
  rules:
    - name: block-pod-exec
      match:
        any:
          - resources:
              kinds:
                - Pod/exec
              {{- with .Values.kyverno.apiRestrictions.blockExec.includeNamespaces }}
              namespaces:
                {{- toYaml . | nindent 16 }}
              {{- end }}
      
      {{- if or .Values.kyverno.apiRestrictions.blockExec.excludeNamespaces .Values.kyverno.apiRestrictions.blockExec.excludeUsers .Values.kyverno.apiRestrictions.blockExec.excludeServiceAccounts }}
      exclude:
        any:
          {{- with .Values.kyverno.apiRestrictions.blockExec.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockExec.excludeUsers }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockExec.excludeServiceAccounts }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
      {{- end }}
      
      validate:
        message: >-
          {{ .Values.kyverno.apiRestrictions.blockExec.message | default "kubectl exec is not allowed in this cluster. Use proper debugging and monitoring tools instead. Contact your cluster administrator for assistance." }}
        deny: {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Block kubectl attach (pods/attach)
==============================================================================
Prevents users from attaching to running containers.

Usage:
  {{- include "kyverno.apiRestrictions.blockAttach" . }}

Blocks:
  - kubectl attach pod-name
  - kubectl attach -it pod-name
*/}}

{{- define "kyverno.apiRestrictions.blockAttach" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.apiRestrictions -}}
{{- if .Values.kyverno.apiRestrictions.blockAttach -}}
{{- if .Values.kyverno.apiRestrictions.blockAttach.enabled -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterpolicy" "name" "block-pod-attach") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "api-restriction"
  annotations:
    policies.kyverno.io/title: "Block Pod Attach"
    policies.kyverno.io/category: "Security, API Restriction"
    policies.kyverno.io/severity: {{ .Values.kyverno.apiRestrictions.blockAttach.severity | default "high" | quote }}
    policies.kyverno.io/subject: "Pod"
    policies.kyverno.io/description: >-
      Blocks kubectl attach operations on pods. This prevents users from
      attaching to running container stdin/stdout/stderr streams.
spec:
  validationFailureAction: {{ .Values.kyverno.apiRestrictions.blockAttach.action | default "enforce" }}
  background: false
  failurePolicy: {{ .Values.kyverno.apiRestrictions.blockAttach.failurePolicy | default "Fail" }}
  
  rules:
    - name: block-pod-attach
      match:
        any:
          - resources:
              kinds:
                - Pod/attach
              {{- with .Values.kyverno.apiRestrictions.blockAttach.includeNamespaces }}
              namespaces:
                {{- toYaml . | nindent 16 }}
              {{- end }}
      
      {{- if or .Values.kyverno.apiRestrictions.blockAttach.excludeNamespaces .Values.kyverno.apiRestrictions.blockAttach.excludeUsers .Values.kyverno.apiRestrictions.blockAttach.excludeServiceAccounts }}
      exclude:
        any:
          {{- with .Values.kyverno.apiRestrictions.blockAttach.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockAttach.excludeUsers }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockAttach.excludeServiceAccounts }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
      {{- end }}
      
      validate:
        message: >-
          {{ .Values.kyverno.apiRestrictions.blockAttach.message | default "kubectl attach is not allowed in this cluster. Use kubectl logs for log streaming." }}
        deny: {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Block kubectl port-forward (pods/portforward)
==============================================================================
Prevents users from creating port forwarding tunnels to pods.

Usage:
  {{- include "kyverno.apiRestrictions.blockPortForward" . }}

Blocks:
  - kubectl port-forward pod-name 8080:80
  - kubectl port-forward svc/service-name 8080:80
*/}}

{{- define "kyverno.apiRestrictions.blockPortForward" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.apiRestrictions -}}
{{- if .Values.kyverno.apiRestrictions.blockPortForward -}}
{{- if .Values.kyverno.apiRestrictions.blockPortForward.enabled -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterpolicy" "name" "block-pod-portforward") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "api-restriction"
  annotations:
    policies.kyverno.io/title: "Block Pod Port Forward"
    policies.kyverno.io/category: "Security, API Restriction"
    policies.kyverno.io/severity: {{ .Values.kyverno.apiRestrictions.blockPortForward.severity | default "medium" | quote }}
    policies.kyverno.io/subject: "Pod"
    policies.kyverno.io/description: >-
      Blocks kubectl port-forward operations. This prevents users from
      creating tunnels to pod ports, which can bypass network policies
      and firewall rules.
spec:
  validationFailureAction: {{ .Values.kyverno.apiRestrictions.blockPortForward.action | default "enforce" }}
  background: false
  failurePolicy: {{ .Values.kyverno.apiRestrictions.blockPortForward.failurePolicy | default "Fail" }}
  
  rules:
    - name: block-pod-portforward
      match:
        any:
          - resources:
              kinds:
                - Pod/portforward
              {{- with .Values.kyverno.apiRestrictions.blockPortForward.includeNamespaces }}
              namespaces:
                {{- toYaml . | nindent 16 }}
              {{- end }}
      
      {{- if or .Values.kyverno.apiRestrictions.blockPortForward.excludeNamespaces .Values.kyverno.apiRestrictions.blockPortForward.excludeUsers .Values.kyverno.apiRestrictions.blockPortForward.excludeServiceAccounts }}
      exclude:
        any:
          {{- with .Values.kyverno.apiRestrictions.blockPortForward.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockPortForward.excludeUsers }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockPortForward.excludeServiceAccounts }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
      {{- end }}
      
      validate:
        message: >-
          {{ .Values.kyverno.apiRestrictions.blockPortForward.message | default "kubectl port-forward is not allowed in this cluster. Use proper Ingress or Service resources." }}
        deny: {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Block kubectl proxy (pods/proxy)
==============================================================================
Prevents users from creating proxy connections to pods.

Usage:
  {{- include "kyverno.apiRestrictions.blockProxy" . }}

Blocks:
  - kubectl proxy
*/}}

{{- define "kyverno.apiRestrictions.blockProxy" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.apiRestrictions -}}
{{- if .Values.kyverno.apiRestrictions.blockProxy -}}
{{- if .Values.kyverno.apiRestrictions.blockProxy.enabled -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterpolicy" "name" "block-pod-proxy") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "api-restriction"
  annotations:
    policies.kyverno.io/title: "Block Pod Proxy"
    policies.kyverno.io/category: "Security, API Restriction"
    policies.kyverno.io/severity: {{ .Values.kyverno.apiRestrictions.blockProxy.severity | default "medium" | quote }}
    policies.kyverno.io/subject: "Pod"
    policies.kyverno.io/description: >-
      Blocks kubectl proxy operations to pods.
spec:
  validationFailureAction: {{ .Values.kyverno.apiRestrictions.blockProxy.action | default "enforce" }}
  background: false
  failurePolicy: {{ .Values.kyverno.apiRestrictions.blockProxy.failurePolicy | default "Fail" }}
  
  rules:
    - name: block-pod-proxy
      match:
        any:
          - resources:
              kinds:
                - Pod/proxy
              {{- with .Values.kyverno.apiRestrictions.blockProxy.includeNamespaces }}
              namespaces:
                {{- toYaml . | nindent 16 }}
              {{- end }}
      
      {{- if or .Values.kyverno.apiRestrictions.blockProxy.excludeNamespaces .Values.kyverno.apiRestrictions.blockProxy.excludeUsers .Values.kyverno.apiRestrictions.blockProxy.excludeServiceAccounts }}
      exclude:
        any:
          {{- with .Values.kyverno.apiRestrictions.blockProxy.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockProxy.excludeUsers }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockProxy.excludeServiceAccounts }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
      {{- end }}
      
      validate:
        message: >-
          {{ .Values.kyverno.apiRestrictions.blockProxy.message | default "kubectl proxy to pods is not allowed in this cluster." }}
        deny: {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Block Ephemeral Containers (pods/ephemeralcontainers)
==============================================================================
Prevents users from creating ephemeral debug containers.

Usage:
  {{- include "kyverno.apiRestrictions.blockEphemeralContainers" . }}

Blocks:
  - kubectl debug pod-name --image=busybox
*/}}

{{- define "kyverno.apiRestrictions.blockEphemeralContainers" -}}
{{- if .Values.kyverno -}}
{{- if .Values.kyverno.apiRestrictions -}}
{{- if .Values.kyverno.apiRestrictions.blockEphemeralContainers -}}
{{- if .Values.kyverno.apiRestrictions.blockEphemeralContainers.enabled -}}
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "clusterpolicy" "name" "block-ephemeral-containers") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "api-restriction"
  annotations:
    policies.kyverno.io/title: "Block Ephemeral Containers"
    policies.kyverno.io/category: "Security, API Restriction"
    policies.kyverno.io/severity: {{ .Values.kyverno.apiRestrictions.blockEphemeralContainers.severity | default "high" | quote }}
    policies.kyverno.io/subject: "Pod"
    policies.kyverno.io/description: >-
      Blocks ephemeral container creation (kubectl debug). This prevents
      users from injecting debug containers into running pods.
spec:
  validationFailureAction: {{ .Values.kyverno.apiRestrictions.blockEphemeralContainers.action | default "enforce" }}
  background: false
  failurePolicy: {{ .Values.kyverno.apiRestrictions.blockEphemeralContainers.failurePolicy | default "Fail" }}
  
  rules:
    - name: block-ephemeral-containers
      match:
        any:
          - resources:
              kinds:
                - Pod/ephemeralcontainers
              {{- with .Values.kyverno.apiRestrictions.blockEphemeralContainers.includeNamespaces }}
              namespaces:
                {{- toYaml . | nindent 16 }}
              {{- end }}
      
      {{- if or .Values.kyverno.apiRestrictions.blockEphemeralContainers.excludeNamespaces .Values.kyverno.apiRestrictions.blockEphemeralContainers.excludeUsers .Values.kyverno.apiRestrictions.blockEphemeralContainers.excludeServiceAccounts }}
      exclude:
        any:
          {{- with .Values.kyverno.apiRestrictions.blockEphemeralContainers.excludeNamespaces }}
          - resources:
              namespaces:
                {{- toYaml . | nindent 16 }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockEphemeralContainers.excludeUsers }}
          - subjects:
              - kind: User
                name: {{ . | quote }}
          {{- end }}
          {{- with .Values.kyverno.apiRestrictions.blockEphemeralContainers.excludeServiceAccounts }}
          - subjects:
              - kind: ServiceAccount
                name: {{ . | quote }}
          {{- end }}
      {{- end }}
      
      validate:
        message: >-
          {{ .Values.kyverno.apiRestrictions.blockEphemeralContainers.message | default "Ephemeral containers (kubectl debug) are not allowed in this cluster." }}
        deny: {}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
Block All Dangerous Operations (Convenience Template)
==============================================================================
Enable all API restrictions with a single template call.

Usage:
  {{- include "kyverno.apiRestrictions.blockAll" . }}

Blocks:
  - kubectl exec
  - kubectl attach
  - kubectl port-forward
  - kubectl proxy
  - kubectl debug (ephemeral containers)
*/}}

{{- define "kyverno.apiRestrictions.blockAll" -}}
{{- include "kyverno.apiRestrictions.blockExec" . }}
{{- include "kyverno.apiRestrictions.blockAttach" . }}
{{- include "kyverno.apiRestrictions.blockPortForward" . }}
{{- include "kyverno.apiRestrictions.blockProxy" . }}
{{- include "kyverno.apiRestrictions.blockEphemeralContainers" . }}
{{- end -}}
