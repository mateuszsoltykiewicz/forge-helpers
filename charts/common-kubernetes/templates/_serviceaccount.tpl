{{/*
==============================================================================
Forge Common Library - ServiceAccount Template
==============================================================================
ServiceAccount template with optional IRSA/Workload Identity support.
==============================================================================
*/}}

{{- define "k8s.serviceaccount" -}}
{{- if .Values.serviceAccount -}}
{{- if .Values.serviceAccount.create -}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "forge.serviceAccountName" . }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  annotations:
    {{- if .Values.serviceAccount.annotations }}
    {{- toYaml .Values.serviceAccount.annotations | nindent 4 }}
    {{- end }}
    {{- /* AWS IRSA annotation (populated by common-aws in future) */}}
    {{- if .Values.serviceAccount.awsRoleArn }}
    eks.amazonaws.com/role-arn: {{ .Values.serviceAccount.awsRoleArn }}
    {{- end }}
    {{- /* Azure Workload Identity annotation */}}
    {{- if .Values.serviceAccount.azureClientId }}
    azure.workload.identity/client-id: {{ .Values.serviceAccount.azureClientId }}
    {{- end }}
    {{- /* GCP Workload Identity annotation */}}
    {{- if .Values.serviceAccount.gcpServiceAccount }}
    iam.gke.io/gcp-service-account: {{ .Values.serviceAccount.gcpServiceAccount }}
    {{- end }}
{{- with .Values.serviceAccount.automountServiceAccountToken }}
automountServiceAccountToken: {{ . }}
{{- end }}
{{- with .Values.serviceAccount.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.serviceAccount.secrets }}
secrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
