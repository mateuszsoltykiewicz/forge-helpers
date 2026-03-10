{{/*
==============================================================================
Forge Common Library - AWS ALB Ingress Controller Annotations
==============================================================================
Modular annotation templates for AWS Load Balancer Controller.

Compatible with:
  - AWS Load Balancer Controller v2.x
  - Application Load Balancer (ALB)
  - Network Load Balancer (NLB)

Modules:
  1. Base annotations (scheme, target type, IP mode)
  2. Health checks (path, interval, thresholds)
  3. SSL/TLS (certificates, policies, redirect)
  4. Authentication (Cognito, OIDC)
  5. Target group attributes (stickiness, deregistration delay)
  6. WAF integration
  7. Shield protection
  8. Access logs
  9. Tags and resource naming

Usage:
  {{- include "aws.alb.annotations" . }}
  {{- include "aws.alb.annotations.healthcheck" . }}
  {{- include "aws.alb.annotations.ssl" . }}

See Also:
  - https://kubernetes-sigs.github.io/aws-load-balancer-controller/
==============================================================================
*/}}

{{/*
==============================================================================
AWS ALB: Base Annotations
==============================================================================
Core ALB configuration (scheme, target type, IP mode).
*/}}

{{- define "aws.alb.annotations.base" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.enabled -}}
{{- /* ALB or NLB */ -}}
alb.ingress.kubernetes.io/load-balancer-name: {{ include "forge.resourceName" (dict "context" . "type" "alb" "name" .Values.aws.alb.name) }}
{{- with .Values.aws.alb.scheme }}
alb.ingress.kubernetes.io/scheme: {{ . }}
{{- end }}
{{- with .Values.aws.alb.targetType }}
alb.ingress.kubernetes.io/target-type: {{ . }}
{{- end }}
{{- with .Values.aws.alb.ipAddressType }}
alb.ingress.kubernetes.io/ip-address-type: {{ . }}
{{- end }}
{{- with .Values.aws.alb.subnets }}
alb.ingress.kubernetes.io/subnets: {{ . | join "," }}
{{- end }}
{{- with .Values.aws.alb.securityGroups }}
alb.ingress.kubernetes.io/security-groups: {{ . | join "," }}
{{- end }}
{{- with .Values.aws.alb.inboundCidrs }}
alb.ingress.kubernetes.io/inbound-cidrs: {{ . | join "," }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Health Check Annotations
==============================================================================
ALB target group health check configuration.
*/}}

{{- define "aws.alb.annotations.healthcheck" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.healthcheck -}}
{{- with .Values.aws.alb.healthcheck.enabled }}
alb.ingress.kubernetes.io/healthcheck-protocol: {{ $.Values.aws.alb.healthcheck.protocol | default "HTTP" }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.path }}
alb.ingress.kubernetes.io/healthcheck-path: {{ . }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.port }}
alb.ingress.kubernetes.io/healthcheck-port: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.intervalSeconds }}
alb.ingress.kubernetes.io/healthcheck-interval-seconds: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.timeoutSeconds }}
alb.ingress.kubernetes.io/healthcheck-timeout-seconds: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.healthyThresholdCount }}
alb.ingress.kubernetes.io/healthy-threshold-count: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.unhealthyThresholdCount }}
alb.ingress.kubernetes.io/unhealthy-threshold-count: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.healthcheck.successCodes }}
alb.ingress.kubernetes.io/success-codes: {{ . | quote }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: SSL/TLS Annotations
==============================================================================
SSL certificate, policies, and HTTPS redirect configuration.
*/}}

{{- define "aws.alb.annotations.ssl" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.ssl -}}
{{- if .Values.aws.alb.ssl.enabled -}}
{{- with .Values.aws.alb.ssl.certificateArn }}
alb.ingress.kubernetes.io/certificate-arn: {{ . }}
{{- end }}
{{- with .Values.aws.alb.ssl.sslPolicy }}
alb.ingress.kubernetes.io/ssl-policy: {{ . }}
{{- end }}
{{- if .Values.aws.alb.ssl.redirectHttp }}
alb.ingress.kubernetes.io/ssl-redirect: "443"
{{- end }}
{{- with .Values.aws.alb.ssl.listenPorts }}
alb.ingress.kubernetes.io/listen-ports: {{ . | toJson | quote }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Authentication Annotations (Cognito)
==============================================================================
AWS Cognito authentication configuration.
*/}}

{{- define "aws.alb.annotations.auth.cognito" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.auth -}}
{{- if .Values.aws.alb.auth.cognito -}}
{{- if .Values.aws.alb.auth.cognito.enabled -}}
alb.ingress.kubernetes.io/auth-type: cognito
alb.ingress.kubernetes.io/auth-idp-cognito: {{ .Values.aws.alb.auth.cognito.userPoolArn | required "aws.alb.auth.cognito.userPoolArn is required" }}:{{ .Values.aws.alb.auth.cognito.userPoolClientId | required "aws.alb.auth.cognito.userPoolClientId is required" }}:{{ .Values.aws.alb.auth.cognito.userPoolDomain | required "aws.alb.auth.cognito.userPoolDomain is required" }}
{{- with .Values.aws.alb.auth.cognito.scope }}
alb.ingress.kubernetes.io/auth-scope: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.cognito.sessionCookieName }}
alb.ingress.kubernetes.io/auth-session-cookie: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.cognito.sessionTimeout }}
alb.ingress.kubernetes.io/auth-session-timeout: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.auth.cognito.onUnauthenticatedRequest }}
alb.ingress.kubernetes.io/auth-on-unauthenticated-request: {{ . }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Authentication Annotations (OIDC)
==============================================================================
Generic OIDC authentication configuration.
*/}}

{{- define "aws.alb.annotations.auth.oidc" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.auth -}}
{{- if .Values.aws.alb.auth.oidc -}}
{{- if .Values.aws.alb.auth.oidc.enabled -}}
alb.ingress.kubernetes.io/auth-type: oidc
alb.ingress.kubernetes.io/auth-idp-oidc: {{ .Values.aws.alb.auth.oidc.issuer | required "aws.alb.auth.oidc.issuer is required" }}:{{ .Values.aws.alb.auth.oidc.clientId | required "aws.alb.auth.oidc.clientId is required" }}:{{ .Values.aws.alb.auth.oidc.clientSecret | required "aws.alb.auth.oidc.clientSecret is required" }}
{{- with .Values.aws.alb.auth.oidc.authorizationEndpoint }}
alb.ingress.kubernetes.io/auth-idp-oidc-authorization-endpoint: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.oidc.tokenEndpoint }}
alb.ingress.kubernetes.io/auth-idp-oidc-token-endpoint: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.oidc.userInfoEndpoint }}
alb.ingress.kubernetes.io/auth-idp-oidc-user-info-endpoint: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.oidc.scope }}
alb.ingress.kubernetes.io/auth-scope: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.oidc.sessionCookieName }}
alb.ingress.kubernetes.io/auth-session-cookie: {{ . }}
{{- end }}
{{- with .Values.aws.alb.auth.oidc.sessionTimeout }}
alb.ingress.kubernetes.io/auth-session-timeout: {{ . | quote }}
{{- end }}
{{- with .Values.aws.alb.auth.oidc.onUnauthenticatedRequest }}
alb.ingress.kubernetes.io/auth-on-unauthenticated-request: {{ . }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Target Group Attributes
==============================================================================
Stickiness, deregistration delay, connection settings.
*/}}

{{- define "aws.alb.annotations.targetGroup" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.targetGroup -}}
{{- with .Values.aws.alb.targetGroup.stickinessEnabled }}
alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled={{ . }}
{{- end }}
{{- with .Values.aws.alb.targetGroup.stickinessDurationSeconds }}
{{- if $.Values.aws.alb.targetGroup.stickinessEnabled }},{{ end }}stickiness.lb_cookie.duration_seconds={{ . }}
{{- end }}
{{- with .Values.aws.alb.targetGroup.deregistrationDelaySeconds }}
{{- if or $.Values.aws.alb.targetGroup.stickinessEnabled $.Values.aws.alb.targetGroup.stickinessDurationSeconds }},{{ end }}deregistration_delay.timeout_seconds={{ . }}
{{- end }}
{{- with .Values.aws.alb.targetGroup.slowStartDurationSeconds }}
{{- if or $.Values.aws.alb.targetGroup.stickinessEnabled $.Values.aws.alb.targetGroup.stickinessDurationSeconds $.Values.aws.alb.targetGroup.deregistrationDelaySeconds }},{{ end }}slow_start.duration_seconds={{ . }}
{{- end }}
{{- with .Values.aws.alb.targetGroup.loadBalancingAlgorithm }}
alb.ingress.kubernetes.io/target-group-attributes: load_balancing.algorithm.type={{ . }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: WAF Integration
==============================================================================
AWS WAF WebACL association.
*/}}

{{- define "aws.alb.annotations.waf" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.waf -}}
{{- if .Values.aws.alb.waf.enabled -}}
{{- with .Values.aws.alb.waf.webAclArn }}
alb.ingress.kubernetes.io/wafv2-acl-arn: {{ . }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Shield Protection
==============================================================================
AWS Shield Advanced protection.
*/}}

{{- define "aws.alb.annotations.shield" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.shield -}}
{{- if .Values.aws.alb.shield.enabled -}}
alb.ingress.kubernetes.io/shield-advanced-protection: "true"
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Access Logs
==============================================================================
S3 bucket for ALB access logs.
*/}}

{{- define "aws.alb.annotations.accessLogs" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.accessLogs -}}
{{- if .Values.aws.alb.accessLogs.enabled -}}
alb.ingress.kubernetes.io/load-balancer-attributes: access_logs.s3.enabled=true,access_logs.s3.bucket={{ .Values.aws.alb.accessLogs.s3Bucket | required "aws.alb.accessLogs.s3Bucket is required" }}
{{- with .Values.aws.alb.accessLogs.s3Prefix }}
,access_logs.s3.prefix={{ . }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Tags
==============================================================================
Custom AWS tags for cost allocation and organization.
*/}}

{{- define "aws.alb.annotations.tags" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.alb -}}
{{- if .Values.aws.alb.tags -}}
{{- $tags := list -}}
{{- range $key, $value := .Values.aws.alb.tags }}
{{- $tags = append $tags (printf "%s=%s" $key $value) -}}
{{- end }}
{{- if $tags }}
alb.ingress.kubernetes.io/tags: {{ $tags | join "," }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS ALB: Combined Annotations
==============================================================================
All ALB annotations in one template.
*/}}

{{- define "aws.alb.annotations" -}}
{{- include "aws.alb.annotations.base" . }}
{{- include "aws.alb.annotations.healthcheck" . }}
{{- include "aws.alb.annotations.ssl" . }}
{{- if .Values.aws.alb.auth -}}
  {{- if .Values.aws.alb.auth.cognito -}}
    {{- if .Values.aws.alb.auth.cognito.enabled -}}
      {{- include "aws.alb.annotations.auth.cognito" . }}
    {{- end -}}
  {{- end -}}
  {{- if .Values.aws.alb.auth.oidc -}}
    {{- if .Values.aws.alb.auth.oidc.enabled -}}
      {{- include "aws.alb.annotations.auth.oidc" . }}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- include "aws.alb.annotations.targetGroup" . }}
{{- include "aws.alb.annotations.waf" . }}
{{- include "aws.alb.annotations.shield" . }}
{{- include "aws.alb.annotations.accessLogs" . }}
{{- include "aws.alb.annotations.tags" . }}
{{- end -}}
