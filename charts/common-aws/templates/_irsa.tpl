{{/*
==============================================================================
Forge Common Library - IRSA (IAM Roles for Service Accounts)
==============================================================================
Helpers for AWS IRSA integration with Kubernetes ServiceAccounts.

Compatible with:
  - Amazon EKS 1.23+
  - IAM OIDC Provider
  - Pod Identity Webhook (or built-in EKS IRSA)

Usage:
  {{- include "aws.irsa.serviceAccountAnnotation" . }}
  {{- include "aws.irsa.roleArn" . }}

See Also:
  - https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
==============================================================================
*/}}

{{/*
==============================================================================
AWS IRSA: ServiceAccount Annotation
==============================================================================
Generate eks.amazonaws.com/role-arn annotation for IRSA.

Usage:
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: my-app
    annotations:
      {{- include "aws.irsa.serviceAccountAnnotation" . | nindent 6 }}

Arguments:
  .Values.aws.irsa.enabled - Enable IRSA
  .Values.aws.irsa.roleArn - Full IAM role ARN
  OR
  .Values.aws.irsa.roleNamePrefix - Role name prefix (auto-generates ARN)
  .Values.aws.region - AWS region (default: us-east-1)
  .Values.aws.accountId - AWS account ID

Output:
  eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role
*/}}

{{- define "aws.irsa.serviceAccountAnnotation" -}}
{{- if .Values.aws -}}
{{- if .Values.aws.irsa -}}
{{- if .Values.aws.irsa.enabled -}}
{{- if .Values.aws.irsa.roleArn }}
eks.amazonaws.com/role-arn: {{ .Values.aws.irsa.roleArn }}
{{- else if .Values.aws.irsa.roleNamePrefix }}
eks.amazonaws.com/role-arn: {{ include "aws.irsa.roleArn" . }}
{{- else }}
{{- fail "Either aws.irsa.roleArn or aws.irsa.roleNamePrefix must be set when IRSA is enabled" }}
{{- end }}
{{- with .Values.aws.irsa.tokenExpiration }}
eks.amazonaws.com/token-expiration: {{ . | quote }}
{{- end }}
{{- with .Values.aws.irsa.audienceOverride }}
eks.amazonaws.com/audience: {{ . }}
{{- end }}
{{- with .Values.aws.irsa.stsRegionalEndpoints }}
eks.amazonaws.com/sts-regional-endpoints: {{ . | quote }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
AWS IRSA: Role ARN
==============================================================================
Generate IAM role ARN from components.

Usage:
  {{ include "aws.irsa.roleArn" . }}

Arguments:
  .Values.aws.accountId - AWS account ID (required)
  .Values.aws.irsa.roleNamePrefix - Role name prefix (required)
  .Release.Name - Used as role name suffix

Output:
  arn:aws:iam::123456789012:role/my-app-role-production
*/}}

{{- define "aws.irsa.roleArn" -}}
{{- $accountId := .Values.aws.accountId | required "aws.accountId is required for IRSA" -}}
{{- $rolePrefix := .Values.aws.irsa.roleNamePrefix | required "aws.irsa.roleNamePrefix is required when roleArn is not provided" -}}
{{- $roleName := printf "%s-%s" $rolePrefix .Release.Name -}}
{{- printf "arn:aws:iam::%s:role/%s" $accountId $roleName -}}
{{- end -}}

{{/*
==============================================================================
AWS IRSA: Complete ServiceAccount
==============================================================================
Generate complete ServiceAccount with IRSA annotations.

Usage:
  {{- include "aws.irsa.serviceAccount" . }}

Extends common-kubernetes ServiceAccount template.
*/}}

{{- define "aws.irsa.serviceAccount" -}}
{{- $serviceAccountTemplate := include "kubernetes.serviceaccount" . | fromYaml -}}
{{- if and .Values.aws .Values.aws.irsa .Values.aws.irsa.enabled -}}
  {{- $irsaAnnotation := include "aws.irsa.serviceAccountAnnotation" . | fromYaml -}}
  {{- $_ := set $serviceAccountTemplate.metadata "annotations" (merge ($serviceAccountTemplate.metadata.annotations | default dict) $irsaAnnotation) -}}
{{- end -}}
{{- $serviceAccountTemplate | toYaml -}}
{{- end -}}
