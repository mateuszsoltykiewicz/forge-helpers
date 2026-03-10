{{/*
==============================================================================
Forge Common Library - Semantic Helpers
==============================================================================
Utility functions for string manipulation, case conversion, and sanitization.
Used by all other Forge charts to ensure consistent formatting.

Functions:
  - Quoting: safe string quoting
  - Case conversion: kebab, pascal, snake, camel, lower, upper
  - DNS sanitization: dns1123, dns1035
  - Path sanitization: sanitizePath, sanitizeNamespace
  - Length limiting: truncate with smart suffix handling
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Safe string quoting
Wraps string in double quotes, escaping internal quotes
------------------------------------------------------------------------------
*/}}
{{- define "forge.quote" -}}
{{- $str := . | toString -}}
{{- printf "\"%s\"" ($str | replace "\"" "\\\"") -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Convert to kebab-case (lowercase with hyphens)
Examples: "MyApp" → "my-app", "my_app" → "my-app"
------------------------------------------------------------------------------
*/}}
{{- define "forge.kebabCase" -}}
{{- $str := . | toString -}}
{{- $str = $str | lower -}}
{{- $str = $str | replace "_" "-" -}}
{{- $str = $str | replace " " "-" -}}
{{- $str = regexReplaceAll "[^a-z0-9-]" $str "-" -}}
{{- $str = regexReplaceAll "-+" $str "-" -}}
{{- $str = $str | trimPrefix "-" | trimSuffix "-" -}}
{{- $str -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Convert to PascalCase (capitalize first letter of each word, no separators)
Examples: "my-app" → "MyApp", "my_app" → "MyApp"
------------------------------------------------------------------------------
*/}}
{{- define "forge.pascalCase" -}}
{{- $str := . | toString -}}
{{- $str = $str | replace "-" " " | replace "_" " " -}}
{{- $str = $str | title | replace " " "" -}}
{{- $str -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Convert to camelCase (like PascalCase but first letter lowercase)
Examples: "my-app" → "myApp", "my_app" → "myApp"
------------------------------------------------------------------------------
*/}}
{{- define "forge.camelCase" -}}
{{- $str := include "forge.pascalCase" . -}}
{{- if $str -}}
  {{- $first := substr 0 1 $str | lower -}}
  {{- $rest := substr 1 -1 $str -}}
  {{- printf "%s%s" $first $rest -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Convert to snake_case (lowercase with underscores)
Examples: "MyApp" → "my_app", "my-app" → "my_app"
------------------------------------------------------------------------------
*/}}
{{- define "forge.snakeCase" -}}
{{- $str := . | toString -}}
{{- $str = $str | lower -}}
{{- $str = $str | replace "-" "_" -}}
{{- $str = $str | replace " " "_" -}}
{{- $str = regexReplaceAll "[^a-z0-9_]" $str "_" -}}
{{- $str = regexReplaceAll "_+" $str "_" -}}
{{- $str = $str | trimPrefix "_" | trimSuffix "_" -}}
{{- $str -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Convert to lowercase
------------------------------------------------------------------------------
*/}}
{{- define "forge.lower" -}}
{{- . | toString | lower -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Convert to UPPERCASE
------------------------------------------------------------------------------
*/}}
{{- define "forge.upper" -}}
{{- . | toString | upper -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Sanitize string for DNS-1123 subdomain compliance
Rules: [a-z0-9]([-a-z0-9]*[a-z0-9])?, max 63 chars
Usage: Resource names, namespaces, service names
Examples: "My_App" → "my-app", "App123_Test" → "app123-test"
------------------------------------------------------------------------------
*/}}
{{- define "forge.dns1123" -}}
{{- $str := . | toString -}}
{{- $str = $str | lower -}}
{{- $str = $str | replace "_" "-" -}}
{{- $str = $str | replace " " "-" -}}
{{- $str = regexReplaceAll "[^a-z0-9-]" $str "-" -}}
{{- $str = regexReplaceAll "-+" $str "-" -}}
{{- $str = $str | trimPrefix "-" | trimSuffix "-" -}}
{{- $str = $str | trunc 63 | trimSuffix "-" -}}
{{- $str -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Sanitize string for DNS-1035 label compliance (more restrictive)
Rules: [a-z]([-a-z0-9]*[a-z0-9])?, max 63 chars
Must start with letter, end with alphanumeric
Usage: Service names, pod labels
Examples: "123app" → "a123app", "_app" → "app"
------------------------------------------------------------------------------
*/}}
{{- define "forge.dns1035" -}}
{{- $str := . | toString -}}
{{- $str = $str | lower -}}
{{- $str = $str | replace "_" "-" -}}
{{- $str = $str | replace " " "-" -}}
{{- $str = regexReplaceAll "[^a-z0-9-]" $str "-" -}}
{{- $str = regexReplaceAll "-+" $str "-" -}}
{{- $str = $str | trimPrefix "-" | trimSuffix "-" -}}
{{- /* Ensure starts with letter */ -}}
{{- if not (regexMatch "^[a-z]" $str) -}}
  {{- $str = printf "a%s" $str -}}
{{- end -}}
{{- $str = $str | trunc 63 | trimSuffix "-" -}}
{{- $str -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Sanitize path (remove leading/trailing slashes, collapse multiple slashes)
Examples: "//path//to///resource/" → "path/to/resource"
------------------------------------------------------------------------------
*/}}
{{- define "forge.sanitizePath" -}}
{{- $path := . | toString -}}
{{- $path = regexReplaceAll "/+" $path "/" -}}
{{- $path = $path | trimPrefix "/" | trimSuffix "/" -}}
{{- $path -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Sanitize namespace name (DNS-1123 + additional restrictions)
Examples: "My_Namespace" → "my-namespace"
------------------------------------------------------------------------------
*/}}
{{- define "forge.sanitizeNamespace" -}}
{{- $ns := include "forge.dns1123" . -}}
{{- /* Kubernetes reserves "kube-" prefix */ -}}
{{- if hasPrefix "kube-" $ns -}}
  {{- $ns = printf "app-%s" $ns -}}
{{- end -}}
{{- $ns -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Truncate string with smart suffix handling
If truncated, ensures no trailing hyphens or underscores
Usage: {{ include "forge.truncate" (dict "str" "long-string" "len" 20) }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.truncate" -}}
{{- $str := .str | toString -}}
{{- $len := .len | int -}}
{{- if gt (len $str) $len -}}
  {{- $str = $str | trunc $len | trimSuffix "-" | trimSuffix "_" -}}
{{- end -}}
{{- $str -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Check if string is empty or contains only whitespace
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.isEmpty" -}}
{{- $str := . | toString | trim -}}
{{- if not $str -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Default value if empty
Usage: {{ include "forge.default" (dict "value" .Value "default" "fallback") }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.default" -}}
{{- $value := .value | toString | trim -}}
{{- $default := .default | toString -}}
{{- if $value -}}
  {{- $value -}}
{{- else -}}
  {{- $default -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Join array with separator
Usage: {{ include "forge.join" (dict "list" (list "a" "b" "c") "sep" ",") }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.join" -}}
{{- $list := .list -}}
{{- $sep := .sep | toString -}}
{{- if $list -}}
  {{- join $sep $list -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Split string by separator
Usage: {{ include "forge.split" (dict "str" "a,b,c" "sep" ",") }}
Returns: list
------------------------------------------------------------------------------
*/}}
{{- define "forge.split" -}}
{{- $str := .str | toString -}}
{{- $sep := .sep | toString -}}
{{- if $str -}}
  {{- splitList $sep $str -}}
{{- else -}}
  {{- list -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Indent text by specified number of spaces
Usage: {{ include "forge.indent" (dict "text" "content" "spaces" 4) }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.indent" -}}
{{- $text := .text | toString -}}
{{- $spaces := .spaces | int -}}
{{- $text | nindent $spaces -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Remove leading and trailing whitespace
------------------------------------------------------------------------------
*/}}
{{- define "forge.trim" -}}
{{- . | toString | trim -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Replace all occurrences of a substring
Usage: {{ include "forge.replace" (dict "str" "hello world" "old" "world" "new" "universe") }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.replace" -}}
{{- $str := .str | toString -}}
{{- $old := .old | toString -}}
{{- $new := .new | toString -}}
{{- $str | replace $old $new -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Check if string contains substring
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.contains" -}}
{{- $str := .str | toString -}}
{{- $substr := .substr | toString -}}
{{- if contains $substr $str -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Check if string starts with prefix
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.hasPrefix" -}}
{{- $str := .str | toString -}}
{{- $prefix := .prefix | toString -}}
{{- if hasPrefix $prefix $str -}}
true
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Check if string ends with suffix
Returns: "true" or ""
------------------------------------------------------------------------------
*/}}
{{- define "forge.hasSuffix" -}}
{{- $str := .str | toString -}}
{{- $suffix := .suffix | toString -}}
{{- if hasSuffix $suffix $str -}}
true
{{- end -}}
{{- end -}}
