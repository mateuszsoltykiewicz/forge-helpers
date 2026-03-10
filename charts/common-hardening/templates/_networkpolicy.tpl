{{/*
==============================================================================
Forge Common Library - NetworkPolicy Templates (by Namespace Type)
==============================================================================
NetworkPolicy templates following namespace-hardening.sh patterns.

Namespace Types:
  1. application  - User applications (default deny all, selective egress)
  2. middleware   - Platform middleware (database access, message queues)
  3. forge-jobs   - Batch jobs (similar to application)
  4. forge-operator - Operators (need API server access)
  5. admin        - Administrative namespaces (full access)
  6. platform     - Platform services (DNS, monitoring, etc.)

Default Policy: DENY ALL
Each namespace type gets tailored policies for its specific needs.

Usage:
  {{- include "hardening.networkpolicy" . }}

See Also:
  - scripts/namespace-hardening.sh - apply_network_policy function
==============================================================================
*/}}

{{- define "hardening.networkpolicy" -}}
{{- if .Values.networkPolicy -}}
{{- if .Values.networkPolicy.enabled -}}
{{- $type := .Values.networkPolicy.namespaceType | default "application" -}}

{{- if eq $type "application" -}}
{{- include "hardening.networkpolicy.application" . -}}
{{- else if eq $type "middleware" -}}
{{- include "hardening.networkpolicy.middleware" . -}}
{{- else if eq $type "forge-jobs" -}}
{{- include "hardening.networkpolicy.forgeJobs" . -}}
{{- else if eq $type "forge-operator" -}}
{{- include "hardening.networkpolicy.forgeOperator" . -}}
{{- else if eq $type "admin" -}}
{{- include "hardening.networkpolicy.admin" . -}}
{{- else if eq $type "platform" -}}
{{- include "hardening.networkpolicy.platform" . -}}
{{- else -}}
{{- include "hardening.networkpolicy.application" . -}}
{{- end -}}

{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
NetworkPolicy: Application Namespace (Default)
==============================================================================
Policies for user applications:
  - Deny all ingress by default (must be explicitly allowed by Ingress)
  - Allow egress to:
    * DNS (kube-system)
    * HTTPS (443) anywhere (for external APIs)
    * Platform services (prometheus, grafana, etc.)
    * Other application namespaces (if configured)
==============================================================================
*/}}

{{- define "hardening.networkpolicy.application" -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "default-deny-all") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "default-deny"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-dns") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-dns"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-https-egress") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-https-egress"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
{{- if .Values.networkPolicy.allowInternalTraffic }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-internal") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-internal"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
{{- end }}
{{- end -}}

{{/*
==============================================================================
NetworkPolicy: Middleware Namespace
==============================================================================
Policies for middleware services (databases, message queues, caches):
  - Deny all ingress by default
  - Allow ingress from application namespaces (labeled with moai.forge.io/type=application)
  - Allow egress to DNS
  - Allow egress to HTTPS (for backups, cloud storage)
  - Allow internal traffic (for clustering)
==============================================================================
*/}}

{{- define "hardening.networkpolicy.middleware" -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "default-deny-all") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "default-deny"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-from-applications") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-from-applications"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          moai.forge.io/type: application
  - from:
    - namespaceSelector:
        matchLabels:
          moai.forge.io/type: forge-jobs
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-dns") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-dns"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-internal") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-internal"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
{{- end -}}

{{/*
==============================================================================
NetworkPolicy: Forge Jobs Namespace
==============================================================================
Policies for batch jobs:
  - Same as application namespace
  - Deny all ingress (jobs don't receive traffic)
  - Allow egress to DNS, HTTPS, application services
==============================================================================
*/}}

{{- define "hardening.networkpolicy.forgeJobs" -}}
{{- include "hardening.networkpolicy.application" . -}}
{{- end -}}

{{/*
==============================================================================
NetworkPolicy: Forge Operator Namespace
==============================================================================
Policies for operators (controllers):
  - Deny all ingress by default
  - Allow egress to:
    * DNS
    * Kubernetes API server (port 443)
    * All namespaces (for resource management)
    * HTTPS (for webhooks, external integrations)
==============================================================================
*/}}

{{- define "hardening.networkpolicy.forgeOperator" -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "default-deny-all") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "default-deny"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-api-server") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-api-server"
  annotations:
    moai.forge.io/description: "Allow access to Kubernetes API server for operator reconciliation"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: default
    ports:
    - protocol: TCP
      port: 443
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-dns") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-dns"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
{{- end -}}

{{/*
==============================================================================
NetworkPolicy: Admin Namespace
==============================================================================
Policies for administrative namespaces:
  - Allow all egress (admin tools need full access)
  - Deny ingress from non-admin namespaces
  - Allow ingress from within namespace (for dashboards, etc.)
==============================================================================
*/}}

{{- define "hardening.networkpolicy.admin" -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "default-deny-ingress") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "default-deny-ingress"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-internal") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-internal"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-all-egress") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-all-egress"
  annotations:
    moai.forge.io/description: "Admin namespace needs full egress access for management tools"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - {}
{{- end -}}

{{/*
==============================================================================
NetworkPolicy: Platform Namespace
==============================================================================
Policies for platform services (monitoring, logging, service mesh):
  - Allow ingress from all namespaces (for metrics collection, logging)
  - Allow egress to DNS
  - Allow egress to HTTPS (for external alerting, storage)
  - Allow internal traffic
==============================================================================
*/}}

{{- define "hardening.networkpolicy.platform" -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-from-all") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-from-all"
  annotations:
    moai.forge.io/description: "Platform services (monitoring, logging) need access from all namespaces"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-dns") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-dns"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "networkpolicy" "name" "allow-https-egress") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/policy-type: "allow-https-egress"
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
{{- end -}}
