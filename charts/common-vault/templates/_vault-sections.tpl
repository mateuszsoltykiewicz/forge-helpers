{{/*
==============================================================================
Forge Common Library - Vault Sections
==============================================================================
Implements the sections-based secret organization pattern from video-calling-service.
Allows organizing secrets into logical sections (app, database, external-services)
with automatic template generation for environment variable export.

Pattern:
  vault.sections:
    - app: "secret/data/customer/project/app/config"
    - database: "secret/data/customer/project/app/database"
    - external-services: "secret/data/customer/project/app/external"

Generates:
  - vault.hashicorp.com/agent-inject-secret-{section}: {path}
  - vault.hashicorp.com/agent-inject-template-{section}: export statements

Usage in deployment:
  annotations:
    {{- include "vault.annotations.base" . | nindent 8 }}
    {{- include "vault.sections.annotations" . | nindent 8 }}

Source secrets in container:
  {{- include "vault.sections.source" . | nindent 12 }}

References:
  - video-calling-service/deployment/helm/service-chart/templates/_helpers.tpl
  - video-calling-service/deployment/helm/service-chart/templates/deployment.yaml
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Generate Vault Sections Annotations
Creates agent-inject-secret and agent-inject-template annotations for each section

Input format (.Values.vault.sections):
  - app: "secret/data/acme/ecommerce/cart/config"
  - database: "secret/data/acme/ecommerce/cart/database"
  - external-services: "secret/data/acme/ecommerce/cart/external"

Output (annotations):
  vault.hashicorp.com/agent-inject-secret-app: "secret/data/acme/ecommerce/cart/config"
  vault.hashicorp.com/agent-inject-template-app: |
    {{- with secret "secret/data/acme/ecommerce/cart/config" -}}
    {{- range $k, $v := .Data.data }}
    export {{ $k }}="{{ $v }}"
    {{- end }}
    {{- end }}
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.annotations" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
{{- range .Values.vault.sections -}}
{{- $section := keys . | first -}}
{{- $path := index . $section -}}
vault.hashicorp.com/agent-inject-secret-{{ $section }}: {{ $path | quote }}
vault.hashicorp.com/agent-inject-template-{{ $section }}: |
  {{`{{- with secret "`}}{{ $path }}{{`" -}}
  {{- range $k, $v := .Data.data }}
  export {{ $k }}="{{ $v }}"
  {{- end }}
  {{- end }}`}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Source Commands for All Sections
Creates shell commands to source all Vault secret files

Output (shell script):
  if [ -f /vault/secrets/app ]; then
    source /vault/secrets/app
  fi
  if [ -f /vault/secrets/database ]; then
    source /vault/secrets/database
  fi

Usage in deployment command:
  command: ["/bin/sh", "-c"]
  args:
    - |
      set -e
      {{- include "vault.sections.source" . | nindent 6 }}
      exec /app/entrypoint.sh
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.source" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
# Source all Vault secret files
{{- range .Values.vault.sections -}}
{{- $section := keys . | first }}
if [ -f /vault/secrets/{{ $section }} ]; then
  source /vault/secrets/{{ $section }}
fi
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Source Commands with Set -a (Auto Export)
Alternative sourcing method that automatically exports all variables

Output (shell script):
  set -a
  [ -f /vault/secrets/app ] && . /vault/secrets/app
  [ -f /vault/secrets/database ] && . /vault/secrets/database
  set +a
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.sourceAutoExport" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
# Source all Vault secrets with auto-export
set -a
{{- range .Values.vault.sections -}}
{{- $section := keys . | first }}
[ -f /vault/secrets/{{ $section }} ] && . /vault/secrets/{{ $section }}
{{- end }}
set +a
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
List All Section Names
Returns comma-separated list of section names
Usage: APP_SECTIONS="{{ include "vault.sections.list" . }}"
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.list" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
{{- $sections := list -}}
{{- range .Values.vault.sections -}}
{{- $section := keys . | first -}}
{{- $sections = append $sections $section -}}
{{- end -}}
{{- join "," $sections -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Get Section Count
Returns number of sections defined
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.count" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
{{- len .Values.vault.sections -}}
{{- else -}}
0
{{- end -}}
{{- else -}}
0
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Check if Section Exists
Usage: {{ include "vault.sections.has" (dict "context" . "section" "database") }}
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.has" -}}
{{- $ctx := .context -}}
{{- $sectionName := .section -}}
{{- if $ctx.Values.vault.enabled -}}
{{- if $ctx.Values.vault.sections -}}
{{- range $ctx.Values.vault.sections -}}
{{- $section := keys . | first -}}
{{- if eq $section $sectionName -}}
true
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Get Section Path
Usage: {{ include "vault.sections.path" (dict "context" . "section" "database") }}
Returns: Vault path for specified section
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.path" -}}
{{- $ctx := .context -}}
{{- $sectionName := .section -}}
{{- if $ctx.Values.vault.enabled -}}
{{- if $ctx.Values.vault.sections -}}
{{- range $ctx.Values.vault.sections -}}
{{- $section := keys . | first -}}
{{- if eq $section $sectionName -}}
{{- $path := index . $section -}}
{{- $path -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Init Container Volume Mount for Vault Secrets
Creates volumeMount for /vault/secrets in init containers

Output:
  - name: vault-secrets
    mountPath: /vault/secrets
    readOnly: true
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.volumeMount" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
- name: vault-secrets
  mountPath: /vault/secrets
  readOnly: true
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Template for Custom Format
Allows custom template format instead of export statements

Usage: {{ include "vault.sections.customTemplate" (dict "context" . "section" "app" "template" "{{ $k }}={{ $v }}") }}

Parameters:
  .context  - Template context (.)
  .section  - Section name
  .template - Custom Go template for each key-value pair
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.customTemplate" -}}
{{- $ctx := .context -}}
{{- $section := .section -}}
{{- $template := .template -}}
{{- $path := include "vault.sections.path" (dict "context" $ctx "section" $section) -}}
{{- if $path -}}
vault.hashicorp.com/agent-inject-secret-{{ $section }}: {{ $path | quote }}
vault.hashicorp.com/agent-inject-template-{{ $section }}: |
  {{`{{- with secret "`}}{{ $path }}{{`" -}}
  {{- range $k, $v := .Data.data }}`}}
  {{ $template }}
  {{`{{- end }}
  {{- end }}`}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate JSON Format Template
Exports secrets as JSON instead of shell export statements

Output format:
  {
    "KEY1": "value1",
    "KEY2": "value2"
  }
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.jsonTemplate" -}}
{{- $ctx := .context -}}
{{- $section := .section -}}
{{- $path := include "vault.sections.path" (dict "context" $ctx "section" $section) -}}
{{- if $path -}}
vault.hashicorp.com/agent-inject-secret-{{ $section }}: {{ $path | quote }}
vault.hashicorp.com/agent-inject-template-{{ $section }}: |
  {{`{{- with secret "`}}{{ $path }}{{`" -}}
  {{- .Data.data | toJSONPretty }}
  {{- end }}`}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate YAML Format Template
Exports secrets as YAML

Output format:
  KEY1: value1
  KEY2: value2
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.yamlTemplate" -}}
{{- $ctx := .context -}}
{{- $section := .section -}}
{{- $path := include "vault.sections.path" (dict "context" $ctx "section" $section) -}}
{{- if $path -}}
vault.hashicorp.com/agent-inject-secret-{{ $section }}: {{ $path | quote }}
vault.hashicorp.com/agent-inject-template-{{ $section }}: |
  {{`{{- with secret "`}}{{ $path }}{{`" -}}
  {{- .Data.data | toYAML }}
  {{- end }}`}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate Vault Sections Configuration
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.validate" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.sections -}}
{{- $errors := list -}}
{{- $seenSections := dict -}}

{{- range .Values.vault.sections -}}
{{- $keys := keys . -}}
{{- if ne (len $keys) 1 -}}
  {{- $errors = append $errors (printf "Each section must have exactly one key-value pair, got %d keys" (len $keys)) -}}
{{- else -}}
  {{- $section := first $keys -}}
  {{- $path := index . $section -}}
  
  {{- /* Check for duplicate sections */ -}}
  {{- if hasKey $seenSections $section -}}
    {{- $errors = append $errors (printf "Duplicate section name: %s" $section) -}}
  {{- end -}}
  {{- $_ := set $seenSections $section true -}}
  
  {{- /* Validate section name (DNS-1123 label) */ -}}
  {{- $sectionError := include "forge.validate.dns1123" $section -}}
  {{- if $sectionError -}}
    {{- $errors = append $errors (printf "Invalid section name '%s': %s" $section $sectionError) -}}
  {{- end -}}
  
  {{- /* Validate path is not empty */ -}}
  {{- if not $path -}}
    {{- $errors = append $errors (printf "Section '%s' has empty path" $section) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Assert Vault Sections Validation
Fails template rendering if sections configuration is invalid
Usage: {{ include "vault.sections.assertValid" . }}
------------------------------------------------------------------------------
*/}}
{{- define "vault.sections.assertValid" -}}
{{- $error := include "vault.sections.validate" . -}}
{{- if $error -}}
  {{- fail (printf "Vault sections validation failed: %s" $error) -}}
{{- end -}}
{{- end -}}
