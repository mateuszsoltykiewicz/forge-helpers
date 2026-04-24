{{/*
==============================================================================
Forge Common Library - Naming Conventions
==============================================================================
Implements 8 Forge naming patterns for consistent resource naming across
platform, customer, and tenant deployments.

Naming Patterns:
  1. common            → "forge"                          (platform-wide shared)
  2. shared            → "forge-shared"                   (shared infrastructure)
  3. sharedResource    → "forge-shared-{type}"           (typed shared resources)
  4. namespacedResource→ "{app}-{type}"                  (app-scoped resources)
  5. customerClusterWide→ "{customer}-{project}"          (cluster-level customer resources)
  6. customerNamespace → "{customer}-{project}-{app}"    (customer namespaces)
  7. tenantNamespace   → "{customer}-{project}-{env}-{app}" (tenant namespaces)
  8. customerResource  → "{app}-{type}"                  (customer resource naming)

Helper Functions:
  - resourceTypeShort  → Abbreviate resource types (deployment→deploy, serviceaccount→sa)
  - fullname           → Intelligent name generator with override support
==============================================================================
*/}}

{{/*
------------------------------------------------------------------------------
Pattern 1: Common Platform Resources
Scope: Platform-wide shared resources (e.g., cert-manager, ingress-nginx)
Format: "forge"
Usage: Cluster-wide operators, platform controllers
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.common" -}}
forge
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 2: Shared Infrastructure
Scope: Shared infrastructure components
Format: "forge-shared"
Usage: Shared services, common middleware
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.shared" -}}
forge-shared
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 3: Shared Resource with Type
Scope: Typed shared resources
Format: "forge-shared-{type}"
Usage: Shared ConfigMaps, Secrets, ServiceAccounts
Parameters:
  .type - Resource type (e.g., "config", "secret", "sa")
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.sharedResource" -}}
{{- $type := .type | toString -}}
{{- $typeShort := include "forge.resourceTypeShort" $type -}}
{{- printf "forge-shared-%s" $typeShort -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 4: Namespaced Resource
Scope: Application-scoped resources within a namespace
Format: "{app}-{type}"
Usage: Deployments, Services, ConfigMaps within app namespace
Parameters:
  .app  - Application name
  .type - Resource type
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.namespacedResource" -}}
{{- $app := .app | toString -}}
{{- $type := .type | toString -}}
{{- $typeShort := include "forge.resourceTypeShort" $type -}}
{{- printf "%s-%s" $app $typeShort -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 5: Customer Cluster-Wide Resources
Scope: Cluster-level customer resources (namespaces, cluster roles)
Format: "{customer}-{project}"
Usage: Customer namespaces, cluster roles, cluster role bindings
Parameters:
  .customer - Customer identifier
  .project  - Project name
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.customerClusterWide" -}}
{{- $customer := .customer | toString -}}
{{- $project := .project | toString -}}
{{- printf "%s-%s" $customer $project -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 6: Customer Namespace
Scope: Customer application namespace
Format: "{customer}-{project}-{app}"
Usage: Customer-specific application namespaces
Parameters:
  .customer - Customer identifier
  .project  - Project name
  .app      - Application name
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.customerNamespace" -}}
{{- $customer := .customer | toString -}}
{{- $project := .project | toString -}}
{{- $app := .app | toString -}}
{{- printf "%s-%s-%s" $customer $project $app -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 7: Tenant Namespace (Multi-Environment)
Scope: Tenant-specific namespace with environment
Format: "{customer}-{project}-{env}-{app}"
Usage: Multi-tenant deployments with environment separation
Parameters:
  .customer - Customer identifier
  .project  - Project name
  .env      - Environment (dev, staging, prod)
  .app      - Application name
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.tenantNamespace" -}}
{{- $customer := .customer | toString -}}
{{- $project := .project | toString -}}
{{- $env := .env | toString -}}
{{- $app := .app | toString -}}
{{- printf "%s-%s-%s-%s" $customer $project $env $app -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Pattern 8: Customer Resource Naming
Scope: Resources within customer namespaces
Format: "{app}-{type}"
Usage: Customer workload resources (deployments, services)
Parameters:
  .app  - Application name
  .type - Resource type
------------------------------------------------------------------------------
*/}}
{{- define "forge.name.customerResource" -}}
{{- include "forge.name.namespacedResource" . -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Resource Type Abbreviations
Maps full Kubernetes resource types to short forms for compact naming
Examples:
  deployment        → deploy
  statefulset       → sts
  daemonset         → ds
  service           → svc
  serviceaccount    → sa
  configmap         → cm
  secret            → secret
  ingress           → ing
  persistentvolumeclaim → pvc
------------------------------------------------------------------------------
*/}}
{{- define "forge.resourceTypeShort" -}}
{{- $type := . | toString | lower -}}
{{- if eq $type "deployment" -}}deploy
{{- else if eq $type "statefulset" -}}sts
{{- else if eq $type "daemonset" -}}ds
{{- else if eq $type "replicaset" -}}rs
{{- else if eq $type "service" -}}svc
{{- else if eq $type "serviceaccount" -}}sa
{{- else if eq $type "configmap" -}}cm
{{- else if eq $type "secret" -}}secret
{{- else if eq $type "ingress" -}}ing
{{- else if eq $type "ingressclass" -}}ingressclass
{{- else if eq $type "networkpolicy" -}}netpol
{{- else if eq $type "persistentvolume" -}}pv
{{- else if eq $type "persistentvolumeclaim" -}}pvc
{{- else if eq $type "storageclass" -}}sc
{{- else if eq $type "job" -}}job
{{- else if eq $type "cronjob" -}}cronjob
{{- else if eq $type "role" -}}role
{{- else if eq $type "rolebinding" -}}rb
{{- else if eq $type "clusterrole" -}}cr
{{- else if eq $type "clusterrolebinding" -}}crb
{{- else if eq $type "horizontalpodautoscaler" -}}hpa
{{- else if eq $type "verticalpodautoscaler" -}}vpa
{{- else if eq $type "poddisruptionbudget" -}}pdb
{{- else if eq $type "resourcequota" -}}quota
{{- else if eq $type "limitrange" -}}limits
{{- else -}}{{- $type -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Chart Name
Returns sanitized chart name from Chart.yaml
------------------------------------------------------------------------------
*/}}
{{- define "forge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Application Name
Priority: nameOverride > Chart.Name > Release.Name
Returns DNS-1123 compliant name
------------------------------------------------------------------------------
*/}}
{{- define "forge.name" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- include "forge.dns1123" $name -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Full Name Generator (Intelligent Pattern Selection)
Automatically selects appropriate naming pattern based on context.

Priority Order:
  1. fullnameOverride (if set)
  2. Detect pattern from values:
     - Has customer + project + app + env → tenantNamespace
     - Has customer + project + app      → customerNamespace
     - Has customer + project            → customerClusterWide
     - Default                           → Release.Name-Chart.Name

Parameters: Uses .Values context
  .Values.forge.customer
  .Values.forge.project
  .Values.forge.service
  .Values.forge.environment
  .Values.fullnameOverride
  .Values.nameOverride
  .Release.Name
  .Chart.Name

Returns: DNS-1123 compliant full name (max 63 chars)
------------------------------------------------------------------------------
*/}}
{{- define "forge.fullname" -}}
{{- $name := "" -}}

{{- /* Priority 1: fullnameOverride */ -}}
{{- if .Values.fullnameOverride -}}
  {{- $name = .Values.fullnameOverride -}}

{{- /* Priority 2: Detect Forge pattern */ -}}
{{- else if .Values.forge -}}
  {{- $customer := .Values.forge.customer | default "" -}}
  {{- $project := .Values.forge.project | default "" -}}
  {{- $app := .Values.forge.service | default "" -}}
  {{- $env := .Values.forge.environment | default "" -}}
  
  {{- if and $customer $project $app $env -}}
    {{- /* Pattern 7: Tenant Namespace */ -}}
    {{- $name = include "forge.name.tenantNamespace" (dict "customer" $customer "project" $project "app" $app "env" $env) -}}
  {{- else if and $customer $project $app -}}
    {{- /* Pattern 6: Customer Namespace */ -}}
    {{- $name = include "forge.name.customerNamespace" (dict "customer" $customer "project" $project "app" $app) -}}
  {{- else if and $customer $project -}}
    {{- /* Pattern 5: Customer Cluster-Wide */ -}}
    {{- $name = include "forge.name.customerClusterWide" (dict "customer" $customer "project" $project) -}}
  {{- end -}}
{{- end -}}

{{- /* Fallback: Release-Chart name */ -}}
{{- if not $name -}}
  {{- $chartName := include "forge.name" . -}}
  {{- if contains $chartName .Release.Name -}}
    {{- $name = .Release.Name -}}
  {{- else -}}
    {{- $name = printf "%s-%s" .Release.Name $chartName -}}
  {{- end -}}
{{- end -}}

{{- /* Sanitize and truncate */ -}}
{{- $name = include "forge.dns1123" $name -}}
{{- $name = $name | trunc 63 | trimSuffix "-" -}}
{{- $name -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Namespace Name
Returns namespace from context, with fallback to Release.Namespace
Applies DNS-1123 sanitization and namespace validation
------------------------------------------------------------------------------
*/}}
{{- define "forge.namespace" -}}
{{- $ns := "" -}}

{{- /* Check for explicit namespace in values */ -}}
{{- if .Values.forge -}}
  {{- if .Values.forge.namespace -}}
    {{- $ns = .Values.forge.namespace -}}
  {{- else if and .Values.forge.customer .Values.forge.project .Values.forge.service -}}
    {{- /* Generate namespace from customer/project/service */ -}}
    {{- if .Values.forge.environment -}}
      {{- $ns = include "forge.name.tenantNamespace" (dict "customer" .Values.forge.customer "project" .Values.forge.project "app" .Values.forge.service "env" .Values.forge.environment) -}}
    {{- else -}}
      {{- $ns = include "forge.name.customerNamespace" (dict "customer" .Values.forge.customer "project" .Values.forge.project "app" .Values.forge.service) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- /* Fallback to Release.Namespace */ -}}
{{- if not $ns -}}
  {{- $ns = .Release.Namespace -}}
{{- end -}}

{{- /* Sanitize */ -}}
{{- $ns = include "forge.sanitizeNamespace" $ns -}}
{{- $ns -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Resource Name Generator
Generates resource name using pattern 4 or 8 (app-type format)
Usage: {{ include "forge.resourceName" (dict "context" . "type" "deployment") }}

Parameters:
  .context - Template context (.)
  .type    - Resource type
  .name    - Optional name override
------------------------------------------------------------------------------
*/}}
{{- define "forge.resourceName" -}}
{{- $ctx := .context -}}
{{- $type := .type | toString -}}
{{- $name := .name | default "" -}}

{{- if $name -}}
  {{- $name = include "forge.dns1123" $name -}}
{{- else -}}
  {{- $fullname := include "forge.fullname" $ctx -}}
  {{- $typeShort := include "forge.resourceTypeShort" $type -}}
  {{- $name = printf "%s-%s" $fullname $typeShort -}}
{{- end -}}

{{- $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Service Account Name
Returns service account name with fallback to "default"
Usage: {{ include "forge.serviceAccountName" . }}
------------------------------------------------------------------------------
*/}}
{{- define "forge.serviceAccountName" -}}
{{- if .Values.serviceAccount -}}
  {{- if .Values.serviceAccount.create -}}
    {{- default (include "forge.fullname" .) .Values.serviceAccount.name -}}
  {{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
  {{- end -}}
{{- else -}}
  {{- "default" -}}
{{- end -}}
{{- end -}}
