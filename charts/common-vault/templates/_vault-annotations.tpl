{{/*
==============================================================================
Forge Common Library - Vault Annotations
==============================================================================
HashiCorp Vault Agent Injector annotations for Kubernetes pods.
Enables automatic secret injection using Vault Agent sidecar pattern.

Annotation Categories:
  - Agent configuration (injection, limits, pre-populate)
  - Cache configuration (persistence, eviction)
  - Authentication (Kubernetes auth, role)
  - TLS configuration (CA cert, TLS secret)
  - Template configuration (per-secret templates)

References:
  - https://www.vaultproject.io/docs/platform/k8s/injector/annotations
  - https://developer.hashicorp.com/vault/docs/platform/k8s/injector
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Core Vault Agent Annotations
Basic configuration for Vault Agent Injector
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.agent" -}}
{{- if .Values.vault.enabled -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: {{ .Values.vault.role | default (include "forge.fullname" .) | quote }}
vault.hashicorp.com/agent-pre-populate-only: {{ .Values.vault.prePopulateOnly | default "false" | quote }}
{{- if .Values.vault.preserveSecretCase }}
vault.hashicorp.com/agent-inject-secret-case: "preserve"
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Agent Resource Limits
Configure CPU and memory for Vault Agent containers
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.resources" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.agent }}
{{- if .Values.vault.agent.resources }}
{{- if .Values.vault.agent.resources.limits }}
{{- if .Values.vault.agent.resources.limits.cpu }}
vault.hashicorp.com/agent-limits-cpu: {{ .Values.vault.agent.resources.limits.cpu | quote }}
{{- end }}
{{- if .Values.vault.agent.resources.limits.memory }}
vault.hashicorp.com/agent-limits-mem: {{ .Values.vault.agent.resources.limits.memory | quote }}
{{- end }}
{{- end }}
{{- if .Values.vault.agent.resources.requests }}
{{- if .Values.vault.agent.resources.requests.cpu }}
vault.hashicorp.com/agent-requests-cpu: {{ .Values.vault.agent.resources.requests.cpu | quote }}
{{- end }}
{{- if .Values.vault.agent.resources.requests.memory }}
vault.hashicorp.com/agent-requests-mem: {{ .Values.vault.agent.resources.requests.memory | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Agent Cache Configuration
Enable response caching for improved performance
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.cache" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.cache }}
{{- if .Values.vault.cache.enabled }}
vault.hashicorp.com/agent-cache-enable: "true"
{{- if .Values.vault.cache.useAutoAuthToken }}
vault.hashicorp.com/agent-cache-use-auto-auth-token: "true"
{{- end }}
{{- if .Values.vault.cache.persist }}
vault.hashicorp.com/agent-cache-persist: "true"
{{- if .Values.vault.cache.persistPath }}
vault.hashicorp.com/agent-cache-persist-path: {{ .Values.vault.cache.persistPath | quote }}
{{- end }}
{{- end }}
{{- if .Values.vault.cache.exitOnErr }}
vault.hashicorp.com/agent-cache-exit-on-err: "true"
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Agent Init Container Configuration
Configure the init container that pre-populates secrets
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.init" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.init }}
{{- if .Values.vault.init.first }}
vault.hashicorp.com/agent-init-first: "true"
{{- end }}
{{- if .Values.vault.init.resources }}
{{- if .Values.vault.init.resources.limits }}
{{- if .Values.vault.init.resources.limits.cpu }}
vault.hashicorp.com/agent-init-limits-cpu: {{ .Values.vault.init.resources.limits.cpu | quote }}
{{- end }}
{{- if .Values.vault.init.resources.limits.memory }}
vault.hashicorp.com/agent-init-limits-mem: {{ .Values.vault.init.resources.limits.memory | quote }}
{{- end }}
{{- end }}
{{- if .Values.vault.init.resources.requests }}
{{- if .Values.vault.init.resources.requests.cpu }}
vault.hashicorp.com/agent-init-requests-cpu: {{ .Values.vault.init.resources.requests.cpu | quote }}
{{- end }}
{{- if .Values.vault.init.resources.requests.memory }}
vault.hashicorp.com/agent-init-requests-mem: {{ .Values.vault.init.resources.requests.memory | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault TLS Configuration
Configure TLS for secure Vault communication
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.tls" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.tls }}
{{- if .Values.vault.tls.enabled }}
vault.hashicorp.com/ca-cert: {{ .Values.vault.tls.caCertPath | default "/vault/tls/ca.crt" | quote }}
{{- if .Values.vault.tls.secretName }}
vault.hashicorp.com/tls-secret: {{ .Values.vault.tls.secretName | quote }}
{{- else }}
vault.hashicorp.com/tls-secret: {{ include "forge.fullname" . }}-vault-ca-bundle
{{- end }}
{{- if .Values.vault.tls.serverName }}
vault.hashicorp.com/tls-server-name: {{ .Values.vault.tls.serverName | quote }}
{{- end }}
{{- if .Values.vault.tls.skipVerify }}
vault.hashicorp.com/tls-skip-verify: "true"
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Authentication Configuration
Configure Kubernetes authentication method
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.auth" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.auth }}
{{- if .Values.vault.auth.method }}
vault.hashicorp.com/auth-type: {{ .Values.vault.auth.method | quote }}
{{- end }}
{{- if .Values.vault.auth.path }}
vault.hashicorp.com/auth-path: {{ .Values.vault.auth.path | quote }}
{{- end }}
{{- if .Values.vault.auth.config }}
vault.hashicorp.com/auth-config: {{ .Values.vault.auth.config | quote }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Service Configuration
Configure Vault service address
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.service" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.address }}
vault.hashicorp.com/service: {{ .Values.vault.address | quote }}
{{- end }}
{{- if .Values.vault.namespace }}
vault.hashicorp.com/namespace: {{ .Values.vault.namespace | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Log Configuration
Configure logging for Vault Agent
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.log" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.log }}
{{- if .Values.vault.log.level }}
vault.hashicorp.com/log-level: {{ .Values.vault.log.level | quote }}
{{- end }}
{{- if .Values.vault.log.format }}
vault.hashicorp.com/log-format: {{ .Values.vault.log.format | quote }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Agent Run As Configuration
Configure user/group for Vault Agent
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.runAs" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.runAsUser }}
vault.hashicorp.com/agent-run-as-user: {{ .Values.vault.runAsUser | quote }}
{{- end }}
{{- if .Values.vault.runAsGroup }}
vault.hashicorp.com/agent-run-as-group: {{ .Values.vault.runAsGroup | quote }}
{{- end }}
{{- if .Values.vault.runAsSameUser }}
vault.hashicorp.com/agent-run-as-same-user: "true"
{{- end }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Combined Vault Annotations (Base Configuration)
All basic Vault Agent configuration without secret templates
Use this for pod annotations, then add secret-specific annotations separately
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.base" -}}
{{- if .Values.vault.enabled -}}
{{- include "vault.annotations.agent" . }}
{{- include "vault.annotations.resources" . }}
{{- include "vault.annotations.cache" . }}
{{- include "vault.annotations.init" . }}
{{- include "vault.annotations.tls" . }}
{{- include "vault.annotations.auth" . }}
{{- include "vault.annotations.service" . }}
{{- include "vault.annotations.log" . }}
{{- include "vault.annotations.runAs" . }}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Vault Annotation Validation
Validates required Vault configuration
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.validate" -}}
{{- if .Values.vault.enabled -}}
{{- $errors := list -}}

{{- if not .Values.vault.role -}}
{{- if not (include "forge.fullname" .) -}}
  {{- $errors = append $errors "vault.role is required when vault.enabled=true and fullname cannot be determined" -}}
{{- end -}}
{{- end -}}

{{- if .Values.vault.tls -}}
{{- if .Values.vault.tls.enabled -}}
{{- if not .Values.vault.tls.secretName -}}
{{- if not (include "forge.fullname" .) -}}
  {{- $errors = append $errors "vault.tls.secretName is required when vault.tls.enabled=true and fullname cannot be determined" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Assert Vault Annotation Validation
Fails template rendering if Vault configuration is invalid
Usage: {{ include "vault.annotations.assertValid" . }}
------------------------------------------------------------------------------
*/}}
{{- define "vault.annotations.assertValid" -}}
{{- $error := include "vault.annotations.validate" . -}}
{{- if $error -}}
  {{- fail (printf "Vault annotation validation failed: %s" $error) -}}
{{- end -}}
{{- end -}}
