# common-forge

> **Foundation library providing naming conventions, validation, and labeling for the Forge platform**

[![Type: library](https://img.shields.io/badge/Type-library-informational?style=flat-square)](https://helm.sh/docs/topics/library_charts/)
[![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)](https://semver.org/)

## Description

`common-forge` is the foundation library for all Forge Helm charts. It provides:

- **8 Naming Patterns** - Consistent resource naming across platform, customer, and tenant scopes
- **Semantic Validation** - Kubernetes DNS-1123/DNS-1035 compliance checking
- **Label Generators** - Standard Kubernetes + Forge-specific labels
- **Helper Functions** - String manipulation, case conversion, sanitization

This is a **library chart** - it deploys no resources directly. Instead, it provides reusable templates that other charts consume via Helm dependencies.

## Features

### Naming Patterns

| Pattern | Format | Usage |
|---------|--------|-------|
| **common** | `forge` | Platform-wide shared resources |
| **shared** | `forge-shared` | Shared infrastructure |
| **sharedResource** | `forge-shared-{type}` | Shared ConfigMaps, Secrets |
| **namespacedResource** | `{app}-{type}` | Application resources |
| **customerClusterWide** | `{customer}-{project}` | Customer namespaces, cluster roles |
| **customerNamespace** | `{customer}-{project}-{app}` | Customer namespaces |
| **tenantNamespace** | `{customer}-{project}-{app}-{env}` | Multi-tenant environments |
| **customerResource** | `{app}-{type}` | Customer workload resources |

### Validation Functions

- **DNS Validation**: `forge.validate.dns1123`, `forge.validate.dns1035`
- **Label Validation**: `forge.validate.labelKey`, `forge.validate.labelValue`
- **Annotation Validation**: `forge.validate.annotationKey`, `forge.validate.annotationValue`
- **Resource Validation**: `forge.validate.resourceName`, `forge.validate.namespace`, `forge.validate.helmRelease`

### Label Generators

- **Kubernetes Labels**: Standard `app.kubernetes.io/*` labels
- **Forge Labels**: Platform-specific `moai.forge.io/*` labels
- **Selector Labels**: Immutable labels for Deployments, Services
- **Resource-Specific Labels**: Pod, Service, Ingress, ConfigMap, Secret

### Semantic Helpers

- **Case Conversion**: `forge.kebabCase`, `forge.camelCase`, `forge.pascalCase`, `forge.snakeCase`
- **DNS Sanitization**: `forge.dns1123`, `forge.dns1035`
- **Path Sanitization**: `forge.sanitizePath`, `forge.sanitizeNamespace`
- **String Utilities**: `forge.quote`, `forge.truncate`, `forge.replace`, `forge.contains`

## Installation

Add as a dependency in your `Chart.yaml`:

```yaml
dependencies:
  - name: common-forge
    version: ~0.1.0
    repository: file://../../common-forge  # or https://charts.forge.example.com
```

Then run:

```bash
helm dependency update
```

## Usage

### Basic Template Usage

```yaml
{{- /* In your chart's templates/_helpers.tpl */ -}}
{{- define "myapp.fullname" -}}
  {{- include "forge.fullname" . -}}
{{- end -}}

{{- define "myapp.labels" -}}
  {{- include "forge.labels" . -}}
{{- end -}}

{{- define "myapp.selectorLabels" -}}
  {{- include "forge.selectorLabels" . -}}
{{- end -}}
```

### Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "forge.fullname" . }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "forge.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "forge.labels.pod" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "forge.serviceAccountName" . }}
      # ...
```

### Service Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "service") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels.service" . | nindent 4 }}
spec:
  selector:
    {{- include "forge.selectorLabels" . | nindent 4 }}
  # ...
```

### Pattern-Based Naming

```yaml
# values.yaml
forge:
  customer: acme
  project: ecommerce
  application: cart-service
  environment: prod
  component: api
  partOf: ecommerce-platform

# Results in:
# - Namespace: acme-ecommerce-cart-service-prod
# - Deployment: cart-service-deploy
# - Service: cart-service-svc
# - Labels:
#     app.kubernetes.io/name: cart-service
#     app.kubernetes.io/instance: my-release
#     app.kubernetes.io/component: api
#     app.kubernetes.io/part-of: ecommerce-platform
#     moai.forge.io/customer: acme
#     moai.forge.io/project: ecommerce
#     moai.forge.io/application: cart-service
#     moai.forge.io/environment: prod
```

### Validation Example

```yaml
{{- /* Validate namespace name */ -}}
{{- $nsError := include "forge.validate.namespace" .Values.forge.namespace -}}
{{- if $nsError -}}
  {{- fail $nsError -}}
{{- end -}}

{{- /* Validate all labels */ -}}
{{- include "forge.labels.validate" . -}}

{{- /* Assert validation */ -}}
{{- include "forge.validate.assert" (dict 
  "condition" (include "forge.validate.dns1123" "my-resource-name")
  "context" "Resource name validation"
) -}}
```

## Configuration

See [`values.yaml`](values.yaml) for full configuration options.

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `forge.customer` | Customer identifier | `""` |
| `forge.project` | Project name | `""` |
| `forge.application` | Application name | `""` |
| `forge.environment` | Environment (dev/staging/prod) | `""` |
| `forge.component` | Component within app | `""` |
| `forge.partOf` | Higher-level application | `""` |
| `forge.commonLabels` | Labels applied to all resources | `{}` |
| `forge.commonAnnotations` | Annotations applied to all resources | `{}` |
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override full resource name | `""` |
| `validation.strict` | Enable strict validation | `true` |
| `patterns.autoDetect` | Auto-detect naming pattern | `true` |
| `patterns.useShortTypes` | Use abbreviated types | `true` |

## Template Functions Reference

### Naming Functions

```go
{{- include "forge.name" . -}}                          // Chart name
{{- include "forge.fullname" . -}}                      // Full resource name (pattern-based)
{{- include "forge.namespace" . -}}                     // Namespace name
{{- include "forge.chart" . -}}                         // Chart name-version
{{- include "forge.serviceAccountName" . -}}            // ServiceAccount name

{{- include "forge.name.common" . -}}                   // Pattern 1: "forge"
{{- include "forge.name.shared" . -}}                   // Pattern 2: "forge-shared"
{{- include "forge.name.sharedResource" (dict "type" "config") -}}  // Pattern 3
{{- include "forge.name.customerNamespace" (dict "customer" "acme" "project" "app" "app" "cart") -}}  // Pattern 6
{{- include "forge.resourceName" (dict "context" . "type" "deployment") -}}  // Resource name
```

### Label Functions

```go
{{- include "forge.labels" . -}}                        // All labels (K8s + Forge + custom)
{{- include "forge.labels.kubernetes" . -}}             // Kubernetes standard labels
{{- include "forge.labels.forge" . -}}                  // Forge platform labels
{{- include "forge.selectorLabels" . -}}                // Immutable selector labels
{{- include "forge.labels.pod" . -}}                    // Pod labels
{{- include "forge.labels.service" . -}}                // Service labels
{{- include "forge.labels.deployment" . -}}             // Deployment labels
```

### Validation Functions

```go
{{- include "forge.validate.dns1123" "my-resource" -}}         // DNS-1123 subdomain
{{- include "forge.validate.dns1035" "my-service" -}}          // DNS-1035 label
{{- include "forge.validate.labelKey" "app.k8s.io/name" -}}    // Label key
{{- include "forge.validate.labelValue" "my-app" -}}           // Label value
{{- include "forge.validate.namespace" "my-namespace" -}}      // Namespace
{{- include "forge.validate.helmRelease" "my-release" -}}      // Helm release name
{{- include "forge.validate.labels" .Values.labels -}}         // All labels in map
```

### Semantic Helpers

```go
{{- include "forge.kebabCase" "MyApp" -}}               // "my-app"
{{- include "forge.camelCase" "my-app" -}}              // "myApp"
{{- include "forge.pascalCase" "my-app" -}}             // "MyApp"
{{- include "forge.snakeCase" "MyApp" -}}               // "my_app"
{{- include "forge.dns1123" "My_App" -}}                // "my-app"
{{- include "forge.dns1035" "123app" -}}                // "a123app"
{{- include "forge.quote" "string" -}}                  // "\"string\""
{{- include "forge.truncate" (dict "str" "long" "len" 5) -}}  // "long" (truncated)
```

## Requirements

- **Helm**: >= 3.0.0
- **Kubernetes**: >= 1.23.0

## Development

### Testing

```bash
# Lint chart
helm lint charts/common-forge

# Template rendering test
helm template test charts/common-forge \
  --set forge.customer=acme \
  --set forge.project=test \
  --set forge.application=app \
  --set forge.environment=dev

# Install to test cluster
helm install common-forge-test charts/common-forge --dry-run --debug
```

### Integration with Other Charts

Charts depending on `common-forge` should:

1. Add dependency in `Chart.yaml`
2. Import templates in `templates/_helpers.tpl`
3. Use `forge.*` functions for naming, labels, validation
4. Pass `forge.*` values through to enable pattern-based naming

## License

Internal - Proprietary

## Maintainers

| Name | Email |
|------|-------|
| Forge Team | forge@example.com |

---

**Part of the Forge Helm Library Ecosystem**

- [common-forge](../common-forge) - Foundation library (this chart)
- [common-vault](../common-vault) - Vault integration
- [common-kubernetes](../common-kubernetes) - Kubernetes resources
- [common-hardening](../common-hardening) - Namespace hardening
- [common-aws](../common-aws) - AWS integrations
