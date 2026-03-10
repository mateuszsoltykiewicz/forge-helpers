{{/*
==============================================================================
Forge Common Library - KEDA ScaledJob
==============================================================================
Template for KEDA ScaledJob resource - event-driven batch processing.

ScaledJob creates Kubernetes Jobs based on external events:
  - Message queue depth (process messages in batches)
  - Database records (batch process pending records)
  - Cloud storage (process files from S3/GCS/Azure Blob)
  - Cron schedules (time-based batch jobs)
  - Custom metrics

Key differences from ScaledObject:
  - Creates Jobs (not scaling Deployments)
  - Each job processes a batch of work
  - Automatic job cleanup after completion
  - Better for batch/ETL workloads

Compatible with:
  - KEDA 2.10+ (tested with 2.13.0)
  - Kubernetes 1.23-1.29
  - HashiCorp Vault (for trigger authentication)

Usage:
  {{- include "keda.scaledjob" . }}

See Also:
  - https://keda.sh/docs/latest/concepts/scaling-jobs/
==============================================================================
*/}}

{{/*
==============================================================================
KEDA ScaledJob: Main Template
==============================================================================
Generate complete ScaledJob with triggers and job template.

Usage:
  {{- include "keda.scaledjob" . }}

Requirements:
  .Values.keda.scaledjob.enabled = true
  .Values.keda.scaledjob.jobTargetRef (Job template)
  .Values.keda.scaledjob.triggers (array of trigger configurations)

Output:
  apiVersion: keda.sh/v1alpha1
  kind: ScaledJob
  metadata:
    name: my-batch-scaledjob
    namespace: my-namespace
  spec:
    jobTargetRef: {...}
    pollingInterval: 30
    maxReplicaCount: 10
    scalingStrategy:
      strategy: "default"
    triggers: [...]
*/}}

{{- define "keda.scaledjob" -}}
{{- if .Values.keda -}}
{{- if .Values.keda.scaledjob -}}
{{- if .Values.keda.scaledjob.enabled -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "scaledjob" "name" .Values.keda.scaledjob.name) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- with .Values.keda.scaledjob.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.keda.scaledjob.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  # Job template (Kubernetes Job spec)
  jobTargetRef:
    {{- with .Values.keda.scaledjob.jobTargetRef }}
    {{- toYaml . | nindent 4 }}
    {{- end }}

  # Polling interval (seconds) - how often KEDA checks metrics
  pollingInterval: {{ .Values.keda.scaledjob.pollingInterval | default 30 }}

  # Success/failure job history
  successfulJobsHistoryLimit: {{ .Values.keda.scaledjob.successfulJobsHistoryLimit | default 5 }}
  failedJobsHistoryLimit: {{ .Values.keda.scaledjob.failedJobsHistoryLimit | default 5 }}

  # Max concurrent jobs
  maxReplicaCount: {{ .Values.keda.scaledjob.maxReplicaCount | default 10 }}

  # Scaling strategy
  {{- with .Values.keda.scaledjob.scalingStrategy }}
  scalingStrategy:
    strategy: {{ .strategy | default "default" }}
    {{- with .customScalingQueueLengthDeduction }}
    customScalingQueueLengthDeduction: {{ . }}
    {{- end }}
    {{- with .customScalingRunningJobPercentage }}
    customScalingRunningJobPercentage: {{ . | quote }}
    {{- end }}
    {{- with .pendingPodConditions }}
    pendingPodConditions:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .multipleScalersCalculation }}
    multipleScalersCalculation: {{ . }}
    {{- end }}
  {{- end }}

  # Rollout strategy
  {{- with .Values.keda.scaledjob.rolloutStrategy }}
  rolloutStrategy: {{ . }}
  {{- end }}

  # Triggers (array of scaling triggers)
  triggers:
    {{- range .Values.keda.scaledjob.triggers }}
    - type: {{ .type | required "keda.scaledjob.triggers[].type is required" }}
      {{- with .name }}
      name: {{ . }}
      {{- end }}
      metadata:
        {{- toYaml .metadata | nindent 8 }}
      {{- if .authenticationRef }}
      authenticationRef:
        {{- toYaml .authenticationRef | nindent 8 }}
      {{- end }}
      {{- with .metricType }}
      metricType: {{ . }}
      {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
KEDA ScaledJob: RabbitMQ Batch Processing
==============================================================================
Helper for common pattern: process RabbitMQ messages in batches.

Usage:
  {{- include "keda.scaledjob.rabbitmqBatch" . }}

Requirements:
  .Values.keda.scaledjob.rabbitmq.enabled = true
  .Values.keda.scaledjob.rabbitmq.queueName
  .Values.keda.scaledjob.rabbitmq.messagesPerJob (how many messages each job processes)
*/}}

{{- define "keda.scaledjob.rabbitmqBatch" -}}
{{- if .Values.keda -}}
{{- if .Values.keda.scaledjob -}}
{{- if .Values.keda.scaledjob.rabbitmq -}}
{{- if .Values.keda.scaledjob.rabbitmq.enabled -}}
{{- $messagesPerJob := .Values.keda.scaledjob.rabbitmq.messagesPerJob | default 10 -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "scaledjob" "name" "rabbitmq-batch") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/batch-type: "rabbitmq"
spec:
  jobTargetRef:
    {{- with .Values.keda.scaledjob.jobTargetRef }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  pollingInterval: {{ .Values.keda.scaledjob.rabbitmq.pollingInterval | default 30 }}
  successfulJobsHistoryLimit: {{ .Values.keda.scaledjob.rabbitmq.successfulJobsHistoryLimit | default 5 }}
  failedJobsHistoryLimit: {{ .Values.keda.scaledjob.rabbitmq.failedJobsHistoryLimit | default 5 }}
  maxReplicaCount: {{ .Values.keda.scaledjob.rabbitmq.maxReplicaCount | default 10 }}
  scalingStrategy:
    strategy: {{ .Values.keda.scaledjob.rabbitmq.scalingStrategy | default "accurate" }}
    customScalingQueueLengthDeduction: {{ $messagesPerJob }}
    customScalingRunningJobPercentage: "0.5"
  triggers:
    - type: rabbitmq
      metadata:
        host: {{ .Values.keda.scaledjob.rabbitmq.host | required "RabbitMQ host is required" }}
        queueName: {{ .Values.keda.scaledjob.rabbitmq.queueName | required "Queue name is required" }}
        queueLength: {{ $messagesPerJob | quote }}
        {{- with .Values.keda.scaledjob.rabbitmq.protocol }}
        protocol: {{ . }}
        {{- end }}
        {{- with .Values.keda.scaledjob.rabbitmq.vhostName }}
        vhostName: {{ . }}
        {{- end }}
      {{- with .Values.keda.scaledjob.rabbitmq.authenticationRef }}
      authenticationRef:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
KEDA ScaledJob: AWS SQS Batch Processing
==============================================================================
Helper for common pattern: process AWS SQS messages in batches.

Usage:
  {{- include "keda.scaledjob.sqsBatch" . }}

Requirements:
  .Values.keda.scaledjob.sqs.enabled = true
  .Values.keda.scaledjob.sqs.queueURL
  .Values.keda.scaledjob.sqs.messagesPerJob
*/}}

{{- define "keda.scaledjob.sqsBatch" -}}
{{- if .Values.keda -}}
{{- if .Values.keda.scaledjob -}}
{{- if .Values.keda.scaledjob.sqs -}}
{{- if .Values.keda.scaledjob.sqs.enabled -}}
{{- $messagesPerJob := .Values.keda.scaledjob.sqs.messagesPerJob | default 10 -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "scaledjob" "name" "sqs-batch") }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/batch-type: "aws-sqs"
spec:
  jobTargetRef:
    {{- with .Values.keda.scaledjob.jobTargetRef }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  pollingInterval: {{ .Values.keda.scaledjob.sqs.pollingInterval | default 30 }}
  successfulJobsHistoryLimit: {{ .Values.keda.scaledjob.sqs.successfulJobsHistoryLimit | default 5 }}
  failedJobsHistoryLimit: {{ .Values.keda.scaledjob.sqs.failedJobsHistoryLimit | default 5 }}
  maxReplicaCount: {{ .Values.keda.scaledjob.sqs.maxReplicaCount | default 10 }}
  scalingStrategy:
    strategy: {{ .Values.keda.scaledjob.sqs.scalingStrategy | default "accurate" }}
    customScalingQueueLengthDeduction: {{ $messagesPerJob }}
    customScalingRunningJobPercentage: "0.5"
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: {{ .Values.keda.scaledjob.sqs.queueURL | required "SQS queue URL is required" }}
        queueLength: {{ $messagesPerJob | quote }}
        awsRegion: {{ .Values.keda.scaledjob.sqs.awsRegion | default "us-east-1" }}
        {{- with .Values.keda.scaledjob.sqs.activationQueueLength }}
        activationQueueLength: {{ . | quote }}
        {{- end }}
        {{- with .Values.keda.scaledjob.sqs.identityOwner }}
        identityOwner: {{ . }}
        {{- end }}
      {{- with .Values.keda.scaledjob.sqs.authenticationRef }}
      authenticationRef:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
KEDA ScaledJob: Database Batch Processing
==============================================================================
Helper for common pattern: process pending database records in batches.

Usage:
  {{- include "keda.scaledjob.databaseBatch" . }}

Requirements:
  .Values.keda.scaledjob.database.enabled = true
  .Values.keda.scaledjob.database.type (postgresql, mysql, mongodb)
  .Values.keda.scaledjob.database.query (returns count of pending records)
  .Values.keda.scaledjob.database.recordsPerJob
*/}}

{{- define "keda.scaledjob.databaseBatch" -}}
{{- if .Values.keda -}}
{{- if .Values.keda.scaledjob -}}
{{- if .Values.keda.scaledjob.database -}}
{{- if .Values.keda.scaledjob.database.enabled -}}
{{- $recordsPerJob := .Values.keda.scaledjob.database.recordsPerJob | default 100 -}}
{{- $dbType := .Values.keda.scaledjob.database.type | required "Database type is required (postgresql, mysql, mongodb)" -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "scaledjob" "name" (printf "%s-batch" $dbType)) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    moai.forge.io/batch-type: {{ $dbType }}
spec:
  jobTargetRef:
    {{- with .Values.keda.scaledjob.jobTargetRef }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  pollingInterval: {{ .Values.keda.scaledjob.database.pollingInterval | default 60 }}
  successfulJobsHistoryLimit: {{ .Values.keda.scaledjob.database.successfulJobsHistoryLimit | default 5 }}
  failedJobsHistoryLimit: {{ .Values.keda.scaledjob.database.failedJobsHistoryLimit | default 5 }}
  maxReplicaCount: {{ .Values.keda.scaledjob.database.maxReplicaCount | default 5 }}
  scalingStrategy:
    strategy: {{ .Values.keda.scaledjob.database.scalingStrategy | default "accurate" }}
    customScalingQueueLengthDeduction: {{ $recordsPerJob }}
  triggers:
    - type: {{ $dbType }}
      metadata:
        query: {{ .Values.keda.scaledjob.database.query | required "Database query is required" | quote }}
        targetQueryValue: {{ $recordsPerJob | quote }}
        {{- if eq $dbType "postgresql" }}
        {{- with .Values.keda.scaledjob.database.connectionFromEnv }}
        connectionFromEnv: {{ . }}
        {{- end }}
        {{- else if eq $dbType "mysql" }}
        {{- with .Values.keda.scaledjob.database.connectionFromEnv }}
        connectionStringFromEnv: {{ . }}
        {{- end }}
        {{- else if eq $dbType "mongodb" }}
        {{- with .Values.keda.scaledjob.database.connectionFromEnv }}
        connectionStringFromEnv: {{ . }}
        {{- end }}
        {{- with .Values.keda.scaledjob.database.collection }}
        collection: {{ . }}
        {{- end }}
        {{- end }}
      {{- with .Values.keda.scaledjob.database.authenticationRef }}
      authenticationRef:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
