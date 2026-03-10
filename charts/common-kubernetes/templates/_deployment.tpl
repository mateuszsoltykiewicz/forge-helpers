{{/*
==============================================================================
Forge Common Library - Deployment Template
==============================================================================
Production-ready Deployment template with:
- Vault Agent Injector integration
- Security contexts (PSS baseline/restricted)
- Health probes (startup, liveness, readiness)
- Resource management
- Init containers support
- Flexible configuration

Usage:
  {{- include "k8s.deployment" . }}

Required values:
  .Values.deployment.enabled: true
  .Values.image.repository
  .Values.image.tag

Pattern from: video-calling-service deployment.yaml
==============================================================================
*/}}

{{- define "k8s.deployment" -}}
{{- if .Values.deployment -}}
{{- if .Values.deployment.enabled -}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "deployment" "name" .Values.deployment.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels.deployment" . | nindent 4 }}
  {{- with .Values.deployment.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.deployment.replicas | default 1 }}
  {{- end }}
  
  {{- with .Values.deployment.strategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.deployment.minReadySeconds }}
  minReadySeconds: {{ . }}
  {{- end }}
  
  {{- with .Values.deployment.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  
  {{- with .Values.deployment.progressDeadlineSeconds }}
  progressDeadlineSeconds: {{ . }}
  {{- end }}
  
  selector:
    matchLabels:
      {{- include "forge.selectorLabels" . | nindent 6 }}
  
  template:
    metadata:
      annotations:
        {{- if .Values.vault.enabled }}
        {{- include "vault.annotations.base" . | nindent 8 }}
        {{- include "vault.sections.annotations" . | nindent 8 }}
        {{- end }}
        {{- with .Values.deployment.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "forge.labels.pod" . | nindent 8 }}
    
    spec:
      {{- with .Values.image.pullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      serviceAccountName: {{ include "forge.serviceAccountName" . }}
      
      {{- with .Values.deployment.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- if .Values.deployment.hostNetwork }}
      hostNetwork: true
      {{- end }}
      
      {{- with .Values.deployment.dnsPolicy }}
      dnsPolicy: {{ . }}
      {{- end }}
      
      {{- with .Values.deployment.dnsConfig }}
      dnsConfig:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.deployment.hostname }}
      hostname: {{ . }}
      {{- end }}
      
      {{- with .Values.deployment.subdomain }}
      subdomain: {{ . }}
      {{- end }}
      
      {{- if or .Values.deployment.initContainers .Values.deployment.waitForDatabase }}
      initContainers:
        {{- if .Values.deployment.waitForDatabase }}
        {{- include "k8s.initContainer.waitForDatabase" . | nindent 8 }}
        {{- end }}
        {{- with .Values.deployment.initContainers }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
      
      containers:
      - name: {{ .Values.deployment.containerName | default .Chart.Name }}
        image: {{ include "k8s.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        
        {{- with .Values.deployment.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.vault.enabled }}
        {{- if or .Values.vault.sections .Values.deployment.command }}
        command: {{ .Values.deployment.command | default (list "/bin/sh" "-c") | toJson }}
        args:
          - |
            set -e
            
            {{- include "vault.sections.source" . | nindent 12 }}
            
            {{- if and .Values.vault.verification.enabled .Values.vault.requiredVars }}
            {{- include "vault.verification.check" . | nindent 12 }}
            {{- end }}
            
            {{- if .Values.deployment.startupScript }}
            {{- .Values.deployment.startupScript | nindent 12 }}
            {{- else }}
            exec {{ .Values.deployment.execCommand | default "/app/start.sh" }}
            {{- end }}
        {{- end }}
        {{- else }}
        {{- with .Values.deployment.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with .Values.deployment.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- end }}
        
        {{- if .Values.deployment.ports }}
        ports:
        {{- range .Values.deployment.ports }}
        - name: {{ .name }}
          containerPort: {{ .containerPort }}
          protocol: {{ .protocol | default "TCP" }}
          {{- with .hostPort }}
          hostPort: {{ . }}
          {{- end }}
        {{- end }}
        {{- end }}
        
        {{- with .Values.deployment.env }}
        env:
        {{- toYaml . | nindent 8 }}
        {{- end }}
        
        {{- with .Values.deployment.envFrom }}
        envFrom:
        {{- toYaml . | nindent 8 }}
        {{- end }}
        
        {{- with .Values.deployment.startupProbe }}
        startupProbe:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.deployment.livenessProbe }}
        livenessProbe:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.deployment.readinessProbe }}
        readinessProbe:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.deployment.lifecycle }}
        lifecycle:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.deployment.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.deployment.volumeMounts }}
        volumeMounts:
        {{- toYaml .Values.deployment.volumeMounts | nindent 8 }}
        {{- end }}
      
      {{- with .Values.deployment.sidecars }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
      
      {{- if .Values.deployment.volumes }}
      volumes:
      {{- toYaml .Values.deployment.volumes | nindent 6 }}
      {{- end }}
      
      {{- with .Values.deployment.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.deployment.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.deployment.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.deployment.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.deployment.priorityClassName }}
      priorityClassName: {{ . }}
      {{- end }}
      
      {{- with .Values.deployment.runtimeClassName }}
      runtimeClassName: {{ . }}
      {{- end }}
      
      {{- with .Values.deployment.schedulerName }}
      schedulerName: {{ . }}
      {{- end }}
      
      {{- if .Values.deployment.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ .Values.deployment.terminationGracePeriodSeconds }}
      {{- end }}
      
      {{- if .Values.deployment.activeDeadlineSeconds }}
      activeDeadlineSeconds: {{ .Values.deployment.activeDeadlineSeconds }}
      {{- end }}
      
      {{- if hasKey .Values.deployment "enableServiceLinks" }}
      enableServiceLinks: {{ .Values.deployment.enableServiceLinks }}
      {{- end }}
      
      {{- if hasKey .Values.deployment "shareProcessNamespace" }}
      shareProcessNamespace: {{ .Values.deployment.shareProcessNamespace }}
      {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Image Path Generator
Combines repository, tag, and optional digest
------------------------------------------------------------------------------
*/}}
{{- define "k8s.image" -}}
{{- $registry := .Values.image.registry | default "" -}}
{{- $repository := .Values.image.repository | required "image.repository is required" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | toString -}}
{{- $digest := .Values.image.digest | default "" -}}

{{- if $registry -}}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end -}}

{{- if $digest -}}
  {{- printf "%s@%s" $repository $digest -}}
{{- else -}}
  {{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
------------------------------------------------------------------------------
Init Container: Wait for Database
PostgreSQL readiness check with Vault secret support
------------------------------------------------------------------------------
*/}}
{{- define "k8s.initContainer.waitForDatabase" -}}
- name: wait-for-database
  image: {{ .Values.deployment.waitForDatabase.image | default "postgres:16-alpine" }}
  command: ["/bin/sh", "-c"]
  args:
  - |
    echo "==================================="
    echo "🔍 Waiting for database"
    echo "==================================="
    
    {{- if .Values.vault.enabled }}
    # Source Vault secrets
    {{- include "vault.sections.source" . | nindent 4 }}
    {{- end }}
    
    DB_HOST="${DB_HOST:-{{ .Values.deployment.waitForDatabase.host | default "localhost" }}}"
    DB_PORT="${DB_PORT:-{{ .Values.deployment.waitForDatabase.port | default "5432" }}}"
    
    echo "📍 Target: $DB_HOST:$DB_PORT"
    
    TIMEOUT={{ .Values.deployment.waitForDatabase.timeout | default 60 }}
    ELAPSED=0
    
    until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U postgres 2>/dev/null; do
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "❌ Database not ready after ${TIMEOUT}s"
        exit 1
      fi
      
      echo "⏳ Database not ready... (${ELAPSED}s/${TIMEOUT}s)"
      sleep 2
      ELAPSED=$((ELAPSED + 2))
    done
    
    echo "✅ Database is ready!"
    echo "==================================="
  {{- if .Values.vault.enabled }}
  volumeMounts:
    {{- include "vault.sections.volumeMount" . | nindent 4 }}
  {{- end }}
  {{- with .Values.deployment.waitForDatabase.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
