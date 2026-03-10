{{/*
==============================================================================
Forge Common Library - Validation Functions
==============================================================================
Kubernetes semantic validation for names, labels, annotations.
Enforces K8s API conventions per official specifications.

Functions:
  - DNS validation: dns1123, dns1035
  - Label validation: labelKey, labelValue, qualifiedName
  - Annotation validation: annotationKey, annotationValue
  - Resource validation: resourceName, namespace, helmRelease
  - Type checking: isString, isInt, isBool, isList, isDict

References:
  - DNS-1123: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-subdomain-names
  - DNS-1035: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names
  - Labels: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Validate DNS-1123 subdomain (max 253 chars)
Rules: [a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*
Used for: namespaces, service names, pod names
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.dns1123" -}}
{{- $name := . | toString -}}
{{- $errors := list -}}

{{- if not $name -}}
  {{- $errors = append $errors "DNS-1123 name cannot be empty" -}}
{{- else if gt (len $name) 253 -}}
  {{- $errors = append $errors (printf "DNS-1123 name '%s' exceeds 253 characters (len: %d)" $name (len $name)) -}}
{{- else if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" $name) -}}
  {{- $errors = append $errors (printf "DNS-1123 name '%s' invalid: must contain only lowercase alphanumeric, hyphens, dots; start/end with alphanumeric" $name) -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate DNS-1035 label (max 63 chars, must start with letter)
Rules: [a-z]([-a-z0-9]*[a-z0-9])?
Used for: service names (stricter than DNS-1123)
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.dns1035" -}}
{{- $name := . | toString -}}
{{- $errors := list -}}

{{- if not $name -}}
  {{- $errors = append $errors "DNS-1035 label cannot be empty" -}}
{{- else if gt (len $name) 63 -}}
  {{- $errors = append $errors (printf "DNS-1035 label '%s' exceeds 63 characters (len: %d)" $name (len $name)) -}}
{{- else if not (regexMatch "^[a-z]([-a-z0-9]*[a-z0-9])?$" $name) -}}
  {{- $errors = append $errors (printf "DNS-1035 label '%s' invalid: must start with letter, contain only lowercase alphanumeric/hyphens, end with alphanumeric" $name) -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate qualified name (prefix/name format for label keys)
Rules:
  - Prefix (optional): DNS-1123 subdomain, max 253 chars
  - Name: DNS-1123 label segment, max 63 chars, [a-z0-9A-Z]([_.-]?[a-z0-9A-Z])*
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.qualifiedName" -}}
{{- $key := . | toString -}}
{{- $errors := list -}}

{{- if not $key -}}
  {{- $errors = append $errors "Qualified name cannot be empty" -}}
{{- else -}}
  {{- $parts := splitList "/" $key -}}
  {{- $partsLen := len $parts -}}
  
  {{- if gt $partsLen 2 -}}
    {{- $errors = append $errors (printf "Qualified name '%s' invalid: maximum one '/' separator allowed" $key) -}}
  {{- else if eq $partsLen 2 -}}
    {{- $prefix := index $parts 0 -}}
    {{- $name := index $parts 1 -}}
    
    {{- /* Validate prefix as DNS-1123 subdomain */ -}}
    {{- if gt (len $prefix) 253 -}}
      {{- $errors = append $errors (printf "Prefix '%s' exceeds 253 characters" $prefix) -}}
    {{- else if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" $prefix) -}}
      {{- $errors = append $errors (printf "Prefix '%s' invalid: must be valid DNS-1123 subdomain" $prefix) -}}
    {{- end -}}
    
    {{- /* Validate name part */ -}}
    {{- if gt (len $name) 63 -}}
      {{- $errors = append $errors (printf "Name '%s' exceeds 63 characters" $name) -}}
    {{- else if not (regexMatch "^[a-z0-9A-Z]([_.-]?[a-z0-9A-Z])*$" $name) -}}
      {{- $errors = append $errors (printf "Name '%s' invalid: must start/end with alphanumeric, contain only alphanumeric, underscore, hyphen, dot" $name) -}}
    {{- end -}}
  {{- else -}}
    {{- /* No prefix, just validate name */ -}}
    {{- if gt (len $key) 63 -}}
      {{- $errors = append $errors (printf "Name '%s' exceeds 63 characters" $key) -}}
    {{- else if not (regexMatch "^[a-z0-9A-Z]([_.-]?[a-z0-9A-Z])*$" $key) -}}
      {{- $errors = append $errors (printf "Name '%s' invalid: must start/end with alphanumeric, contain only alphanumeric, underscore, hyphen, dot" $key) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate label key
Rules: 
  - Optional prefix (DNS subdomain) + "/" + name
  - Prefix max 253 chars, name max 63 chars
  - Name: [a-z0-9A-Z]([_.-]?[a-z0-9A-Z])*
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.labelKey" -}}
{{- include "forge.validate.qualifiedName" . -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate label value
Rules: 
  - Max 63 chars (can be empty)
  - [a-z0-9A-Z]([_.-]?[a-z0-9A-Z])* (if not empty)
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.labelValue" -}}
{{- $value := . | toString -}}
{{- $errors := list -}}

{{- if $value -}}
  {{- if gt (len $value) 63 -}}
    {{- $errors = append $errors (printf "Label value '%s' exceeds 63 characters (len: %d)" $value (len $value)) -}}
  {{- else if not (regexMatch "^[a-z0-9A-Z]([_.-]?[a-z0-9A-Z])*$" $value) -}}
    {{- $errors = append $errors (printf "Label value '%s' invalid: must start/end with alphanumeric, contain only alphanumeric, underscore, hyphen, dot" $value) -}}
  {{- end -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate annotation key (same as label key)
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.annotationKey" -}}
{{- include "forge.validate.qualifiedName" . -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate annotation value
Rules: No length limit, but should be reasonable (warn if > 256KB)
Returns: warning message if very large, empty otherwise
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.annotationValue" -}}
{{- $value := . | toString -}}
{{- $len := len $value -}}

{{- if gt $len 262144 -}}
  {{- printf "WARNING: Annotation value exceeds 256KB (len: %d), may cause issues" $len -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate resource name (generic Kubernetes resource)
Most resources use DNS-1123 subdomain, max 253 chars
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.resourceName" -}}
{{- include "forge.validate.dns1123" . -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate namespace name
Rules: DNS-1123 label (single segment), max 63 chars
Cannot start with "kube-" (reserved)
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.namespace" -}}
{{- $ns := . | toString -}}
{{- $errors := list -}}

{{- if not $ns -}}
  {{- $errors = append $errors "Namespace cannot be empty" -}}
{{- else if gt (len $ns) 63 -}}
  {{- $errors = append $errors (printf "Namespace '%s' exceeds 63 characters (len: %d)" $ns (len $ns)) -}}
{{- else if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $ns) -}}
  {{- $errors = append $errors (printf "Namespace '%s' invalid: must be DNS-1123 label" $ns) -}}
{{- else if hasPrefix "kube-" $ns -}}
  {{- $errors = append $errors (printf "Namespace '%s' invalid: 'kube-' prefix is reserved" $ns) -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate Helm release name
Rules: DNS-1123 subdomain, max 53 chars (Helm restriction)
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.helmRelease" -}}
{{- $release := . | toString -}}
{{- $errors := list -}}

{{- if not $release -}}
  {{- $errors = append $errors "Helm release name cannot be empty" -}}
{{- else if gt (len $release) 53 -}}
  {{- $errors = append $errors (printf "Helm release '%s' exceeds 53 characters (len: %d)" $release (len $release)) -}}
{{- else if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $release) -}}
  {{- $errors = append $errors (printf "Helm release '%s' invalid: must be DNS-1123 label, max 53 chars" $release) -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate container name
Rules: DNS-1123 label, max 63 chars
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.containerName" -}}
{{- $name := . | toString -}}
{{- $errors := list -}}

{{- if not $name -}}
  {{- $errors = append $errors "Container name cannot be empty" -}}
{{- else if gt (len $name) 63 -}}
  {{- $errors = append $errors (printf "Container name '%s' exceeds 63 characters (len: %d)" $name (len $name)) -}}
{{- else if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
  {{- $errors = append $errors (printf "Container name '%s' invalid: must be DNS-1123 label" $name) -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Type checking: is string?
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.isString" -}}
{{- if kindIs "string" . -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Type checking: is integer?
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.isInt" -}}
{{- if or (kindIs "int" .) (kindIs "int64" .) (kindIs "float64" .) -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Type checking: is boolean?
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.isBool" -}}
{{- if kindIs "bool" . -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Type checking: is list/array?
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.isList" -}}
{{- if kindIs "slice" . -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Type checking: is dict/map?
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.isDict" -}}
{{- if kindIs "map" . -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Assert validation (fail template rendering if invalid)
Usage: {{ include "forge.validate.assert" (dict "condition" (include "forge.validate.dns1123" "my-name") "context" "Deployment name") }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.assert" -}}
{{- $error := .condition -}}
{{- $context := .context | default "Validation" -}}

{{- if $error -}}
  {{- fail (printf "%s failed: %s" $context $error) -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate all labels in a map
Returns: list of error messages (empty if all valid)
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.labels" -}}
{{- $labels := . -}}
{{- $errors := list -}}

{{- range $key, $value := $labels -}}
  {{- $keyErr := include "forge.validate.labelKey" $key -}}
  {{- if $keyErr -}}
    {{- $errors = append $errors $keyErr -}}
  {{- end -}}
  
  {{- $valErr := include "forge.validate.labelValue" $value -}}
  {{- if $valErr -}}
    {{- $errors = append $errors $valErr -}}
  {{- end -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate all annotations in a map
Returns: list of warnings (empty if all ok)
------------------------------------------------------------------------------
*/}}
{{- define "forge.validate.annotations" -}}
{{- $annotations := . -}}
{{- $warnings := list -}}

{{- range $key, $value := $annotations -}}
  {{- $keyErr := include "forge.validate.annotationKey" $key -}}
  {{- if $keyErr -}}
    {{- $warnings = append $warnings $keyErr -}}
  {{- end -}}
  
  {{- $valWarn := include "forge.validate.annotationValue" $value -}}
  {{- if $valWarn -}}
    {{- $warnings = append $warnings $valWarn -}}
  {{- end -}}
{{- end -}}

{{- if $warnings -}}
{{- join "; " $warnings -}}
{{- end -}}
{{- end -}}
