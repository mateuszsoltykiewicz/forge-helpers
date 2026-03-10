{{/*
==============================================================================
Forge Common Library - Ingress Template
==============================================================================
Ingress template for HTTP/HTTPS routing.
==============================================================================
*/}}

{{- define "k8s.ingress" -}}
{{- if .Values.ingress -}}
{{- if .Values.ingress.enabled -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "ingress" "name" .Values.ingress.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with .Values.ingress.ingressClassName }}
  ingressClassName: {{ . }}
  {{- end }}
  
  {{- if .Values.ingress.tls }}
  tls:
  {{- range .Values.ingress.tls }}
  - hosts:
    {{- range .hosts }}
    - {{ . | quote }}
    {{- end }}
    {{- with .secretName }}
    secretName: {{ . }}
    {{- end }}
  {{- end }}
  {{- end }}
  
  {{- if .Values.ingress.rules }}
  rules:
  {{- range .Values.ingress.rules }}
  - host: {{ .host | quote }}
    http:
      paths:
      {{- range .paths }}
      - path: {{ .path }}
        pathType: {{ .pathType | default "Prefix" }}
        backend:
          service:
            name: {{ .serviceName | default (include "forge.resourceName" (dict "context" $ "type" "service")) }}
            port:
              {{- if .servicePort }}
              {{- if kindIs "string" .servicePort }}
              name: {{ .servicePort }}
              {{- else }}
              number: {{ .servicePort }}
              {{- end }}
              {{- else }}
              number: {{ $.Values.service.port | default 80 }}
              {{- end }}
      {{- end }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
