{{/*
==============================================================================
Forge Common Library - StatefulSet Template
==============================================================================
StatefulSet template for stateful applications with:
- Stable network identities
- Persistent storage (volumeClaimTemplates)
- Ordered deployment and scaling
- Vault integration
- Security contexts

Usage:
  {{- include "k8s.statefulset" . }}
==============================================================================
*/}}

{{- define "k8s.statefulset" -}}
{{- if .Values.statefulset -}}
{{- if .Values.statefulset.enabled -}}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "statefulset" "name" .Values.statefulset.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.statefulset.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  serviceName: {{ .Values.statefulset.serviceName | required "statefulset.serviceName is required" }}
  
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.statefulset.replicas | default 1 }}
  {{- end }}
  
  {{- with .Values.statefulset.podManagementPolicy }}
  podManagementPolicy: {{ . }}
  {{- end }}
  
  {{- with .Values.statefulset.updateStrategy }}
  updateStrategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.statefulset.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  
  {{- with .Values.statefulset.minReadySeconds }}
  minReadySeconds: {{ . }}
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
        {{- with .Values.statefulset.podAnnotations }}
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
      
      {{- with .Values.statefulset.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.statefulset.initContainers }}
      initContainers:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      containers:
      - name: {{ .Values.statefulset.containerName | default .Chart.Name }}
        image: {{ include "k8s.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        
        {{- with .Values.statefulset.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.statefulset.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.statefulset.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.statefulset.ports }}
        ports:
        {{- range .Values.statefulset.ports }}
        - name: {{ .name }}
          containerPort: {{ .containerPort }}
          protocol: {{ .protocol | default "TCP" }}
        {{- end }}
        {{- end }}
        
        {{- with .Values.statefulset.env }}
        env:
        {{- toYaml . | nindent 8 }}
        {{- end }}
        
        {{- with .Values.statefulset.envFrom }}
        envFrom:
        {{- toYaml . | nindent 8 }}
        {{- end }}
        
        {{- with .Values.statefulset.startupProbe }}
        startupProbe:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.statefulset.livenessProbe }}
        livenessProbe:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.statefulset.readinessProbe }}
        readinessProbe:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.statefulset.lifecycle }}
        lifecycle:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.statefulset.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.statefulset.volumeMounts }}
        volumeMounts:
        {{- toYaml .Values.statefulset.volumeMounts | nindent 8 }}
        {{- end }}
      
      {{- with .Values.statefulset.sidecars }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
      
      {{- if .Values.statefulset.volumes }}
      volumes:
      {{- toYaml .Values.statefulset.volumes | nindent 6 }}
      {{- end }}
      
      {{- with .Values.statefulset.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.statefulset.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.statefulset.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.statefulset.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.statefulset.priorityClassName }}
      priorityClassName: {{ . }}
      {{- end }}
      
      {{- if .Values.statefulset.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ .Values.statefulset.terminationGracePeriodSeconds }}
      {{- end }}
  
  {{- if .Values.statefulset.volumeClaimTemplates }}
  volumeClaimTemplates:
  {{- range .Values.statefulset.volumeClaimTemplates }}
  - metadata:
      name: {{ .name }}
      {{- with .labels }}
      labels:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .annotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      accessModes:
        {{- toYaml .accessModes | nindent 8 }}
      {{- with .storageClassName }}
      storageClassName: {{ . }}
      {{- end }}
      resources:
        requests:
          storage: {{ .size | required "volumeClaimTemplate size is required" }}
      {{- with .selector }}
      selector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .dataSource }}
      dataSource:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
Forge Common Library - DaemonSet Template
==============================================================================
DaemonSet template for node-level services.
==============================================================================
*/}}

{{- define "k8s.daemonset" -}}
{{- if .Values.daemonset -}}
{{- if .Values.daemonset.enabled -}}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "daemonset" "name" .Values.daemonset.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.daemonset.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with .Values.daemonset.updateStrategy }}
  updateStrategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  
  {{- with .Values.daemonset.minReadySeconds }}
  minReadySeconds: {{ . }}
  {{- end }}
  
  {{- with .Values.daemonset.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
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
        {{- with .Values.daemonset.podAnnotations }}
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
      
      {{- with .Values.daemonset.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- if .Values.daemonset.hostNetwork }}
      hostNetwork: true
      {{- end }}
      
      {{- if .Values.daemonset.hostPID }}
      hostPID: true
      {{- end }}
      
      {{- if .Values.daemonset.hostIPC }}
      hostIPC: true
      {{- end }}
      
      {{- with .Values.daemonset.initContainers }}
      initContainers:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      containers:
      - name: {{ .Values.daemonset.containerName | default .Chart.Name }}
        image: {{ include "k8s.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        
        {{- with .Values.daemonset.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.daemonset.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.daemonset.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.daemonset.ports }}
        ports:
        {{- range .Values.daemonset.ports }}
        - name: {{ .name }}
          containerPort: {{ .containerPort }}
          protocol: {{ .protocol | default "TCP" }}
          {{- with .hostPort }}
          hostPort: {{ . }}
          {{- end }}
        {{- end }}
        {{- end }}
        
        {{- with .Values.daemonset.env }}
        env:
        {{- toYaml . | nindent 8 }}
        {{- end }}
        
        {{- with .Values.daemonset.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.daemonset.volumeMounts }}
        volumeMounts:
        {{- toYaml .Values.daemonset.volumeMounts | nindent 8 }}
        {{- end }}
      
      {{- if .Values.daemonset.volumes }}
      volumes:
      {{- toYaml .Values.daemonset.volumes | nindent 6 }}
      {{- end }}
      
      {{- with .Values.daemonset.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.daemonset.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.daemonset.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.daemonset.priorityClassName }}
      priorityClassName: {{ . }}
      {{- end }}
      
      {{- if .Values.daemonset.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ .Values.daemonset.terminationGracePeriodSeconds }}
      {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
Forge Common Library - Job Template
==============================================================================
Job template for batch processing.
==============================================================================
*/}}

{{- define "k8s.job" -}}
{{- if .Values.job -}}
{{- if .Values.job.enabled -}}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "job" "name" .Values.job.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels.job" . | nindent 4 }}
  {{- with .Values.job.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with .Values.job.backoffLimit }}
  backoffLimit: {{ . }}
  {{- end }}
  
  {{- with .Values.job.completions }}
  completions: {{ . }}
  {{- end }}
  
  {{- with .Values.job.parallelism }}
  parallelism: {{ . }}
  {{- end }}
  
  {{- with .Values.job.activeDeadlineSeconds }}
  activeDeadlineSeconds: {{ . }}
  {{- end }}
  
  {{- with .Values.job.ttlSecondsAfterFinished }}
  ttlSecondsAfterFinished: {{ . }}
  {{- end }}
  
  template:
    metadata:
      annotations:
        {{- if .Values.vault.enabled }}
        {{- include "vault.annotations.base" . | nindent 8 }}
        {{- if .Values.vault.prePopulateOnly }}
        vault.hashicorp.com/agent-pre-populate-only: "true"
        {{- end }}
        {{- include "vault.sections.annotations" . | nindent 8 }}
        {{- end }}
        {{- with .Values.job.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "forge.labels.pod" . | nindent 8 }}
    
    spec:
      restartPolicy: {{ .Values.job.restartPolicy | default "OnFailure" }}
      
      {{- with .Values.image.pullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      serviceAccountName: {{ include "forge.serviceAccountName" . }}
      
      {{- with .Values.job.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.job.initContainers }}
      initContainers:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      containers:
      - name: {{ .Values.job.containerName | default .Chart.Name }}
        image: {{ include "k8s.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        
        {{- with .Values.job.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.job.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.job.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- with .Values.job.env }}
        env:
        {{- toYaml . | nindent 8 }}
        {{- end }}
        
        {{- with .Values.job.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        
        {{- if .Values.job.volumeMounts }}
        volumeMounts:
        {{- toYaml .Values.job.volumeMounts | nindent 8 }}
        {{- end }}
      
      {{- if .Values.job.volumes }}
      volumes:
      {{- toYaml .Values.job.volumes | nindent 6 }}
      {{- end }}
      
      {{- with .Values.job.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.job.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      
      {{- with .Values.job.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
Forge Common Library - CronJob Template
==============================================================================
CronJob template for scheduled batch processing.
==============================================================================
*/}}

{{- define "k8s.cronjob" -}}
{{- if .Values.cronjob -}}
{{- if .Values.cronjob.enabled -}}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "cronjob" "name" .Values.cronjob.nameOverride) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels.cronjob" . | nindent 4 }}
  {{- with .Values.cronjob.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  schedule: {{ .Values.cronjob.schedule | required "cronjob.schedule is required" | quote }}
  
  {{- with .Values.cronjob.timeZone }}
  timeZone: {{ . }}
  {{- end }}
  
  {{- with .Values.cronjob.concurrencyPolicy }}
  concurrencyPolicy: {{ . }}
  {{- end }}
  
  {{- with .Values.cronjob.suspend }}
  suspend: {{ . }}
  {{- end }}
  
  {{- with .Values.cronjob.successfulJobsHistoryLimit }}
  successfulJobsHistoryLimit: {{ . }}
  {{- end }}
  
  {{- with .Values.cronjob.failedJobsHistoryLimit }}
  failedJobsHistoryLimit: {{ . }}
  {{- end }}
  
  {{- with .Values.cronjob.startingDeadlineSeconds }}
  startingDeadlineSeconds: {{ . }}
  {{- end }}
  
  jobTemplate:
    metadata:
      labels:
        {{- include "forge.labels.job" . | nindent 8 }}
    spec:
      {{- with .Values.cronjob.backoffLimit }}
      backoffLimit: {{ . }}
      {{- end }}
      
      {{- with .Values.cronjob.ttlSecondsAfterFinished }}
      ttlSecondsAfterFinished: {{ . }}
      {{- end }}
      
      template:
        metadata:
          annotations:
            {{- if .Values.vault.enabled }}
            {{- include "vault.annotations.base" . | nindent 12 }}
            vault.hashicorp.com/agent-pre-populate-only: "true"
            {{- include "vault.sections.annotations" . | nindent 12 }}
            {{- end }}
            {{- with .Values.cronjob.podAnnotations }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          labels:
            {{- include "forge.labels.pod" . | nindent 12 }}
        
        spec:
          restartPolicy: {{ .Values.cronjob.restartPolicy | default "OnFailure" }}
          
          {{- with .Values.image.pullSecrets }}
          imagePullSecrets:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          serviceAccountName: {{ include "forge.serviceAccountName" . }}
          
          {{- with .Values.cronjob.podSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          {{- with .Values.cronjob.initContainers }}
          initContainers:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          containers:
          - name: {{ .Values.cronjob.containerName | default .Chart.Name }}
            image: {{ include "k8s.image" . }}
            imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
            
            {{- with .Values.cronjob.securityContext }}
            securityContext:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            
            {{- with .Values.cronjob.command }}
            command:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            
            {{- with .Values.cronjob.args }}
            args:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            
            {{- with .Values.cronjob.env }}
            env:
            {{- toYaml . | nindent 12 }}
            {{- end }}
            
            {{- with .Values.cronjob.resources }}
            resources:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            
            {{- if .Values.cronjob.volumeMounts }}
            volumeMounts:
            {{- toYaml .Values.cronjob.volumeMounts | nindent 12 }}
            {{- end }}
          
          {{- if .Values.cronjob.volumes }}
          volumes:
          {{- toYaml .Values.cronjob.volumes | nindent 10 }}
          {{- end }}
          
          {{- with .Values.cronjob.nodeSelector }}
          nodeSelector:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          {{- with .Values.cronjob.affinity }}
          affinity:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          
          {{- with .Values.cronjob.tolerations }}
          tolerations:
            {{- toYaml . | nindent 12 }}
          {{- end }}
{{- end }}
{{- end }}
{{- end }}
