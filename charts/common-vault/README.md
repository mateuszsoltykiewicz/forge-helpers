# common-vault

> **HashiCorp Vault integration library for Kubernetes secret injection**

[![Type: library](https://img.shields.io/badge/Type-library-informational?style=flat-square)](https://helm.sh/docs/topics/library_charts/)
[![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)](https://semver.org/)

## Description

`common-vault` provides HashiCorp Vault Agent Injector integration for Kubernetes pods. It implements the sections-based secret organization pattern from **video-calling-service**, enabling:

- **Vault Agent Injection** - Automatic secret injection using sidecar/init containers
- **Sections-Based Organization** - Logical grouping of secrets (app, database, external-services)
- **Template Generation** - Automatic creation of shell export scripts from Vault secrets
- **Variable Verification** - Validate required environment variables after injection
- **TLS Support** - Secure communication with Vault servers
- **Flexible Configuration** - Extensive customization of agent behavior, caching, and resources

This is a **library chart** - it provides reusable templates for Vault integration.

## Features

### Vault Agent Injector Annotations

Complete annotation support for Vault Agent Injector:

- **Agent Configuration**: Injection, role, pre-populate mode
- **Resource Limits**: CPU and memory for agent and init containers
- **Cache Configuration**: Response caching, persistence, auto-auth token
- **TLS Configuration**: CA certificates, TLS secrets, server name verification
- **Authentication**: Kubernetes auth (default), JWT, AWS, Azure, GCP
- **Logging**: Configurable log level and format

### Sections-Based Secret Organization

Organize secrets into logical sections with automatic template generation:

```yaml
vault:
  sections:
    - app: "secret/data/acme/ecommerce/cart/config"
    - database: "secret/data/acme/ecommerce/cart/database"
    - external-services: "secret/data/acme/ecommerce/cart/external"
```

**Generates** files in `/vault/secrets/`:
- `/vault/secrets/app` - Application config secrets
- `/vault/secrets/database` - Database credentials
- `/vault/secrets/external-services` - External API keys

Each file contains:
```bash
export API_KEY="xyz123"
export DB_HOST="postgres.example.com"
export DB_PORT="5432"
```

### Variable Verification

Verify required environment variables after secret injection:

```yaml
vault:
  verification:
    enabled: true
    mode: "verbose"  # or "minimal" or "silent"
  requiredVars:
    - DB_HOST
    - DB_PORT
    - API_KEY
  optionalVars:
    - DEBUG_MODE
    - CACHE_TTL
```

**Verification Modes**:
- **verbose**: Shows all variables (✓ set, ✗ missing)
- **minimal**: Only shows missing variables
- **silent**: No output, just exit code

## Installation

Add as a dependency in your `Chart.yaml`:

```yaml
dependencies:
  - name: common-vault
    version: ~0.1.0
    repository: file://../../common-vault
  - name: common-forge
    version: ~0.1.0
    repository: file://../../common-forge
```

Then run:

```bash
helm dependency update
```

## Usage

### Basic Deployment with Vault

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "forge.fullname" . }}
spec:
  template:
    metadata:
      annotations:
        {{- include "vault.annotations.base" . | nindent 8 }}
        {{- include "vault.sections.annotations" . | nindent 8 }}
    spec:
      containers:
      - name: app
        image: myapp:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -e
            
            # Source Vault secrets
            {{- include "vault.sections.source" . | nindent 12 }}
            
            # Verify required variables
            {{- include "vault.verification.check" . | nindent 12 }}
            
            # Start application
            exec /app/start.sh
```

### Values Configuration

```yaml
# values.yaml
vault:
  enabled: true
  role: "my-app-vault-role"
  
  # Secret sections
  sections:
    - app: "secret/data/acme/ecommerce/cart/config"
    - database: "secret/data/acme/ecommerce/cart/database"
  
  # Variable verification
  verification:
    enabled: true
    mode: "verbose"
  
  requiredVars:
    - DB_HOST
    - DB_PORT
    - DB_NAME
    - DB_USER
    - DB_PASSWORD
    - API_KEY
  
  optionalVars:
    - DEBUG_MODE
    - LOG_LEVEL
  
  # TLS configuration
  tls:
    enabled: true
    secretName: "vault-ca-bundle"
  
  # Agent resources
  agent:
    resources:
      limits:
        cpu: "100m"
        memory: "128Mi"
      requests:
        cpu: "50m"
        memory: "64Mi"
```

### Advanced: Custom Template Format

Use custom template format instead of shell exports:

```yaml
# JSON format
{{- include "vault.sections.jsonTemplate" (dict "context" . "section" "app") | nindent 8 }}

# YAML format
{{- include "vault.sections.yamlTemplate" (dict "context" . "section" "database") | nindent 8 }}

# Custom format
{{- include "vault.sections.customTemplate" (dict 
  "context" . 
  "section" "app" 
  "template" "{{ $k }}={{ $v }}"
) | nindent 8 }}
```

### Init Container with Vault Secrets

Access Vault secrets in init containers:

```yaml
initContainers:
- name: wait-for-database
  image: postgres:16-alpine
  command: ["/bin/sh", "-c"]
  args:
  - |
    # Source database secrets
    if [ -f /vault/secrets/database ]; then
      source /vault/secrets/database
    fi
    
    # Wait for database
    until pg_isready -h "$DB_HOST" -p "$DB_PORT"; do
      echo "Waiting for database..."
      sleep 2
    done
  volumeMounts:
    {{- include "vault.sections.volumeMount" . | nindent 4 }}
```

### Job/CronJob with Pre-Populate Only

For jobs that don't need continuous secret updates:

```yaml
vault:
  enabled: true
  prePopulateOnly: true  # No sidecar, just init container
  sections:
    - job: "secret/data/acme/jobs/backup/config"
```

## Configuration

See [`values.yaml`](values.yaml) for full configuration options.

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vault.enabled` | Enable Vault Agent Injector | `false` |
| `vault.role` | Vault Kubernetes auth role | `""` (uses fullname) |
| `vault.address` | Vault service address | `""` (uses injector default) |
| `vault.prePopulateOnly` | Init only, no sidecar | `false` |
| `vault.sections` | Secret sections | `[]` |
| `vault.requiredVars` | Required environment variables | `[]` |
| `vault.optionalVars` | Optional environment variables | `[]` |
| `vault.verification.enabled` | Enable variable verification | `false` |
| `vault.verification.mode` | Verification mode | `"verbose"` |
| `vault.cache.enabled` | Enable response caching | `true` |
| `vault.tls.enabled` | Enable TLS | `false` |

## Template Functions Reference

### Annotation Functions

```go
{{- include "vault.annotations.base" . -}}              // All base annotations (no secrets)
{{- include "vault.annotations.agent" . -}}             // Agent configuration
{{- include "vault.annotations.resources" . -}}         // Resource limits
{{- include "vault.annotations.cache" . -}}             // Cache configuration
{{- include "vault.annotations.init" . -}}              // Init container config
{{- include "vault.annotations.tls" . -}}               // TLS configuration
{{- include "vault.annotations.auth" . -}}              // Authentication
{{- include "vault.annotations.service" . -}}           // Vault service address
{{- include "vault.annotations.log" . -}}               // Logging config
{{- include "vault.annotations.runAs" . -}}             // Security context
```

### Sections Functions

```go
{{- include "vault.sections.annotations" . -}}          // Generate all section annotations
{{- include "vault.sections.source" . -}}               // Source all section files
{{- include "vault.sections.sourceAutoExport" . -}}     // Source with set -a
{{- include "vault.sections.list" . -}}                 // Comma-separated section names
{{- include "vault.sections.count" . -}}                // Number of sections
{{- include "vault.sections.has" (dict "context" . "section" "database") -}}  // Check if section exists
{{- include "vault.sections.path" (dict "context" . "section" "app") -}}      // Get section path
{{- include "vault.sections.volumeMount" . -}}          // Volume mount for init containers
```

### Verification Functions

```go
{{- include "vault.verification.check" . -}}            // Automatic mode selection
{{- include "vault.verification.verbose" . -}}          // Verbose mode
{{- include "vault.verification.minimal" . -}}          // Minimal mode
{{- include "vault.verification.silent" . -}}           // Silent mode
{{- include "vault.verification.custom" (dict "context" . "vars" (list "DB_HOST") "mode" "verbose") -}}
{{- include "vault.verification.withDefaults" (dict "context" . "vars" (dict "DB_HOST" "localhost")) -}}
{{- include "vault.verification.summary" . -}}          // Variable count summary
{{- include "vault.verification.optional" . -}}         // Optional variables only
{{- include "vault.verification.combined" . -}}         // Required + optional
```

### Template Format Functions

```go
{{- include "vault.sections.jsonTemplate" (dict "context" . "section" "app") -}}    // JSON format
{{- include "vault.sections.yamlTemplate" (dict "context" . "section" "app") -}}    // YAML format
{{- include "vault.sections.customTemplate" (dict "context" . "section" "app" "template" "...") -}}
```

## Requirements

- **Helm**: >= 3.0.0
- **Kubernetes**: >= 1.23.0
- **Vault**: >= 1.16.0
- **Vault Agent Injector**: Installed in cluster
- **common-forge**: ~0.1.0

## Development

### Testing

```bash
# Lint chart
helm lint charts/common-vault

# Template rendering test
helm template test charts/common-vault \
  --set vault.enabled=true \
  --set vault.role=test-role \
  --set vault.sections[0].app=secret/data/test/app

# Dry-run install
helm install vault-test charts/common-vault --dry-run --debug
```

## License

Internal - Proprietary

## Maintainers

| Name | Email |
|------|-------|
| Forge Team | forge@example.com |

---

**Part of the Forge Helm Library Ecosystem**

- [common-forge](../common-forge) - Foundation library
- [common-vault](../common-vault) - Vault integration (this chart)
- [common-kubernetes](../common-kubernetes) - Kubernetes resources (coming soon)
