{{/*
==============================================================================
Forge Common Library - Vault Variable Verification
==============================================================================
Environment variable verification pattern from video-calling-service.
Generates shell script to verify required environment variables after
Vault secret injection.

Verification Modes:
  - silent:  No output unless errors
  - minimal: Show only missing variables
  - verbose: Show all variables (✓ set, ✗ missing)

Pattern from: video-calling-service/deployment/helm/service-chart/templates/deployment.yaml

Usage in deployment:
  command: ["/bin/sh", "-c"]
  args:
    - |
      set -e
      {{- include "vault.sections.source" . | nindent 6 }}
      {{- include "vault.verification.check" . | nindent 6 }}
      exec /app/start.sh
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Generate Variable Verification Script (Verbose Mode)
Checks all required variables and prints status for each
Exits with code 1 if any variables are missing

Input (.Values.vault.requiredVars):
  - DB_HOST
  - DB_PORT
  - DB_NAME
  - API_KEY

Output:
  echo "=== Verifying Required Environment Variables ==="
  MISSING_VARS=0
  if [ -z "${DB_HOST:-}" ]; then
    echo "✗ Required variable not set: DB_HOST"
    MISSING_VARS=$((MISSING_VARS + 1))
  else
    echo "✓ DB_HOST: [SET]"
  fi
  ...
  if [ $MISSING_VARS -gt 0 ]; then
    echo "❌ $MISSING_VARS required variable(s) missing!"
    exit 1
  fi
  echo "✅ All required environment variables are set!"
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.verbose" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.verification.enabled -}}
{{- if .Values.vault.requiredVars -}}
echo "=== Verifying Required Environment Variables ==="
MISSING_VARS=0
{{- range .Values.vault.requiredVars }}
if [ -z "${{"{"}}{{ . }}:-}" ]; then
  echo "✗ Required variable not set: {{ . }}"
  MISSING_VARS=$((MISSING_VARS + 1))
else
  echo "✓ {{ . }}: [SET]"
fi
{{- end }}

if [ $MISSING_VARS -gt 0 ]; then
  echo ""
  echo "❌ $MISSING_VARS required variable(s) missing!"
  exit 1
fi
echo "✅ All required environment variables are set!"
echo ""
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Variable Verification Script (Minimal Mode)
Only shows output if variables are missing
Quieter than verbose mode, only reports problems

Output (when variables missing):
  ✗ Required variable not set: DB_HOST
  ✗ Required variable not set: API_KEY
  ❌ 2 required variable(s) missing!

Output (when all set):
  (no output)
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.minimal" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.verification.enabled -}}
{{- if .Values.vault.requiredVars -}}
MISSING_VARS=0
{{- range .Values.vault.requiredVars }}
if [ -z "${{"{"}}{{ . }}:-}" ]; then
  echo "✗ Required variable not set: {{ . }}"
  MISSING_VARS=$((MISSING_VARS + 1))
fi
{{- end }}

if [ $MISSING_VARS -gt 0 ]; then
  echo "❌ $MISSING_VARS required variable(s) missing!"
  exit 1
fi
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Variable Verification Script (Silent Mode)
No output at all, just exits if variables missing
Use for production where you don't want verification logs

Output:
  (exits with code 1 if variables missing, otherwise no output)
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.silent" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.verification.enabled -}}
{{- if .Values.vault.requiredVars -}}
MISSING_VARS=0
{{- range .Values.vault.requiredVars }}
[ -z "${{"{"}}{{ . }}:-}" ] && MISSING_VARS=$((MISSING_VARS + 1))
{{- end }}
[ $MISSING_VARS -gt 0 ] && exit 1
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Automatic Mode Selection
Selects verification mode based on .Values.vault.verification.mode
Defaults to "verbose" if not specified

Modes:
  - verbose: Full output with ✓ and ✗ for each variable
  - minimal: Only show missing variables
  - silent:  No output, just exit code
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.check" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.verification.enabled -}}
{{- $mode := .Values.vault.verification.mode | default "verbose" -}}
{{- if eq $mode "verbose" -}}
{{- include "vault.verification.verbose" . -}}
{{- else if eq $mode "minimal" -}}
{{- include "vault.verification.minimal" . -}}
{{- else if eq $mode "silent" -}}
{{- include "vault.verification.silent" . -}}
{{- else -}}
{{- fail (printf "Invalid vault.verification.mode: %s (must be verbose, minimal, or silent)" $mode) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Verification Script with Custom Variables
Allows verification of specific variables instead of .Values.vault.requiredVars

Usage: {{ include "vault.verification.custom" (dict "context" . "vars" (list "DB_HOST" "API_KEY") "mode" "verbose") }}

Parameters:
  .context - Template context (.)
  .vars    - List of variable names to verify
  .mode    - Verification mode (verbose/minimal/silent)
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.custom" -}}
{{- $ctx := .context -}}
{{- $vars := .vars -}}
{{- $mode := .mode | default "verbose" -}}

{{- if $ctx.Values.vault.enabled -}}
{{- if $vars -}}
{{- if eq $mode "verbose" -}}
echo "=== Verifying Custom Environment Variables ==="
MISSING_VARS=0
{{- range $vars }}
if [ -z "${{"{"}}{{ . }}:-}" ]; then
  echo "✗ Required variable not set: {{ . }}"
  MISSING_VARS=$((MISSING_VARS + 1))
else
  echo "✓ {{ . }}: [SET]"
fi
{{- end }}
if [ $MISSING_VARS -gt 0 ]; then
  echo "❌ $MISSING_VARS required variable(s) missing!"
  exit 1
fi
echo "✅ All required environment variables are set!"
{{- else if eq $mode "minimal" -}}
MISSING_VARS=0
{{- range $vars }}
if [ -z "${{"{"}}{{ . }}:-}" ]; then
  echo "✗ Required variable not set: {{ . }}"
  MISSING_VARS=$((MISSING_VARS + 1))
fi
{{- end }}
if [ $MISSING_VARS -gt 0 ]; then
  echo "❌ $MISSING_VARS required variable(s) missing!"
  exit 1
fi
{{- else if eq $mode "silent" -}}
MISSING_VARS=0
{{- range $vars }}
[ -z "${{"{"}}{{ . }}:-}" ] && MISSING_VARS=$((MISSING_VARS + 1))
{{- end }}
[ $MISSING_VARS -gt 0 ] && exit 1
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Verification with Default Values
Verifies variables and falls back to defaults if not set
Does NOT exit on missing variables, just uses defaults

Usage: {{ include "vault.verification.withDefaults" (dict "context" . "vars" (dict "DB_HOST" "localhost" "DB_PORT" "5432")) }}

Output:
  DB_HOST="${DB_HOST:-localhost}"
  DB_PORT="${DB_PORT:-5432}"
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.withDefaults" -}}
{{- $ctx := .context -}}
{{- $vars := .vars -}}

{{- if $ctx.Values.vault.enabled -}}
{{- if $vars -}}
{{- range $key, $default := $vars }}
{{ $key }}="${{"{"}}{{ $key }}:-{{ $default }}}"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Verification Summary
Counts and reports on variable status without exiting

Output:
  TOTAL_VARS=10
  SET_VARS=8
  MISSING_VARS=2
  echo "Environment Variables: $SET_VARS/$TOTAL_VARS set"
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.summary" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.requiredVars -}}
{{- $count := len .Values.vault.requiredVars -}}
TOTAL_VARS={{ $count }}
SET_VARS=0
MISSING_VARS=0
{{- range .Values.vault.requiredVars }}
if [ -n "${{"{"}}{{ . }}:-}" ]; then
  SET_VARS=$((SET_VARS + 1))
else
  MISSING_VARS=$((MISSING_VARS + 1))
fi
{{- end }}
echo "Environment Variables: $SET_VARS/$TOTAL_VARS set"
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Generate Verification for Optional Variables
Checks optional variables and reports but doesn't fail

Output:
  echo "Optional Variables:"
  [ -n "${OPTIONAL_VAR:-}" ] && echo "  ✓ OPTIONAL_VAR: [SET]" || echo "  ○ OPTIONAL_VAR: [NOT SET]"
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.optional" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.optionalVars -}}
echo "Optional Variables:"
{{- range .Values.vault.optionalVars }}
[ -n "${{"{"}}{{ . }}:-}" ] && echo "  ✓ {{ . }}: [SET]" || echo "  ○ {{ . }}: [NOT SET]"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Combined Verification (Required + Optional)
Checks both required and optional variables

Output:
  === Verifying Environment Variables ===
  Required Variables:
    ✓ DB_HOST: [SET]
    ✗ API_KEY: [NOT SET]
  Optional Variables:
    ✓ DEBUG_MODE: [SET]
    ○ CACHE_TTL: [NOT SET]
  ❌ 1 required variable(s) missing!
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.combined" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.verification.enabled -}}
{{- if or .Values.vault.requiredVars .Values.vault.optionalVars -}}
echo "=== Verifying Environment Variables ==="
{{- if .Values.vault.requiredVars }}
echo "Required Variables:"
MISSING_VARS=0
{{- range .Values.vault.requiredVars }}
if [ -z "${{"{"}}{{ . }}:-}" ]; then
  echo "  ✗ {{ . }}: [NOT SET]"
  MISSING_VARS=$((MISSING_VARS + 1))
else
  echo "  ✓ {{ . }}: [SET]"
fi
{{- end -}}
{{- end -}}
{{- if .Values.vault.optionalVars }}
echo "Optional Variables:"
{{- range .Values.vault.optionalVars }}
[ -n "${{"{"}}{{ . }}:-}" ] && echo "  ✓ {{ . }}: [SET]" || echo "  ○ {{ . }}: [NOT SET]"
{{- end -}}
{{- end }}
{{- if .Values.vault.requiredVars }}
if [ $MISSING_VARS -gt 0 ]; then
  echo ""
  echo "❌ $MISSING_VARS required variable(s) missing!"
  exit 1
fi
echo "✅ All required environment variables are set!"
{{- end }}
echo ""
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Validate Verification Configuration
Returns: error message if invalid, empty if valid
------------------------------------------------------------------------------
*/}}
{{- define "vault.verification.validate" -}}
{{- if .Values.vault.enabled -}}
{{- if .Values.vault.verification.enabled -}}
{{- $errors := list -}}

{{- if .Values.vault.verification.mode -}}
{{- $validModes := list "verbose" "minimal" "silent" -}}
{{- if not (has .Values.vault.verification.mode $validModes) -}}
  {{- $errors = append $errors (printf "Invalid verification mode '%s': must be one of %s" .Values.vault.verification.mode (join ", " $validModes)) -}}
{{- end -}}
{{- end -}}

{{- if not .Values.vault.requiredVars -}}
{{- if not .Values.vault.optionalVars -}}
  {{- $errors = append $errors "vault.verification.enabled=true but no requiredVars or optionalVars defined" -}}
{{- end -}}
{{- end -}}

{{- if $errors -}}
{{- join "; " $errors -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
