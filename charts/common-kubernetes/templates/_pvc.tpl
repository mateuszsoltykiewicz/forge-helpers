{{/*
==============================================================================
Forge Common Library - PersistentVolumeClaim Template
==============================================================================
PVC template for persistent storage.
==============================================================================
*/}}

{{- define "k8s.pvc" -}}
{{- if .Values.pvc -}}
{{- if .Values.pvc.enabled -}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "pvc" "name" .Values.pvc.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.pvc.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  accessModes:
  {{- range .Values.pvc.accessModes }}
  - {{ . }}
  {{- end }}
  
  {{- with .Values.pvc.storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
  
  resources:
    requests:
      storage: {{ .Values.pvc.size | required "pvc.size is required" }}
  
  {{- with .Values.pvc.volumeMode }}
  volumeMode: {{ . }}
  {{- end }}
  
  {{- with .Values.pvc.selector }}
  selector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.pvc.dataSource }}
  dataSource:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
