{{/*
==============================================================================
Forge Common Library - KEDA ScaledObject
==============================================================================
Template for KEDA ScaledObject resource - event-driven autoscaling.

ScaledObject replaces HPA with event-driven scaling based on external metrics:
  - Prometheus metrics
  - Message queue depth (RabbitMQ, AWS SQS, Kafka, Redis)
  - Database query results (PostgreSQL, MySQL, MongoDB)
  - Cloud provider metrics (AWS CloudWatch, Azure Monitor, GCP)
  - Cron schedules
  - HTTP requests
  - Custom metrics

Compatible with:
  - KEDA 2.10+ (tested with 2.13.0)
  - Kubernetes 1.23-1.29
  - HashiCorp Vault (for trigger authentication)

Usage:
  {{- include "keda.scaledobject" . }}

See Also:
  - https://keda.sh/docs/latest/concepts/scaling-deployments/
  - https://keda.sh/docs/latest/scalers/
==============================================================================
*/}}

{{/*
==============================================================================
KEDA ScaledObject: Main Template
==============================================================================
Generate complete ScaledObject with triggers and authentication.

Usage:
  {{- include "keda.scaledobject" . }}

Requirements:
  .Values.keda.scaledobject.enabled = true
  .Values.keda.scaledobject.scaleTargetRef (workload to scale)
  .Values.keda.scaledobject.triggers (array of trigger configurations)

Output:
  apiVersion: keda.sh/v1alpha1
  kind: ScaledObject
  metadata:
    name: my-app-scaledobject
    namespace: my-namespace
    labels: {...}
  spec:
    scaleTargetRef: {...}
    pollingInterval: 30
    cooldownPeriod: 300
    minReplicaCount: 1
    maxReplicaCount: 10
    triggers: [...]
*/}}

{{- define "keda.scaledobject" -}}
{{- if .Values.keda -}}
{{- if .Values.keda.scaledobject -}}
{{- if .Values.keda.scaledobject.enabled -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "scaledobject" "name" .Values.keda.scaledobject.name) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
    {{- with .Values.keda.scaledobject.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.keda.scaledobject.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  # Target workload to scale
  scaleTargetRef:
    {{- with .Values.keda.scaledobject.scaleTargetRef }}
    {{- toYaml . | nindent 4 }}
    {{- end }}

  # Polling interval (seconds) - how often KEDA checks metrics
  pollingInterval: {{ .Values.keda.scaledobject.pollingInterval | default 30 }}

  # Cooldown period (seconds) - wait after scaling down before next scale down
  cooldownPeriod: {{ .Values.keda.scaledobject.cooldownPeriod | default 300 }}

  # Idle replica count (0 to scale to zero, requires special workload support)
  {{- if hasKey .Values.keda.scaledobject "idleReplicaCount" }}
  idleReplicaCount: {{ .Values.keda.scaledobject.idleReplicaCount }}
  {{- end }}

  # Min/max replica counts
  minReplicaCount: {{ .Values.keda.scaledobject.minReplicaCount | default 1 }}
  maxReplicaCount: {{ .Values.keda.scaledobject.maxReplicaCount | default 10 }}

  # Advanced scaling configuration
  {{- with .Values.keda.scaledobject.advanced }}
  advanced:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  # Fallback configuration (when scalers fail)
  {{- with .Values.keda.scaledobject.fallback }}
  fallback:
    failureThreshold: {{ .failureThreshold | default 3 }}
    replicas: {{ .replicas | default 2 }}
  {{- end }}

  # Triggers (array of scaling triggers)
  triggers:
    {{- range .Values.keda.scaledobject.triggers }}
    - type: {{ .type | required "keda.scaledobject.triggers[].type is required" }}
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
KEDA TriggerAuthentication: Vault Integration
==============================================================================
Generate TriggerAuthentication for Vault-backed secrets.

Usage:
  {{- include "keda.triggerAuthentication" . }}

Requirements:
  .Values.keda.triggerAuthentication.enabled = true
  .Values.vault.enabled = true (from common-vault)

Output:
  apiVersion: keda.sh/v1alpha1
  kind: TriggerAuthentication
  metadata:
    name: my-app-trigger-auth
  spec:
    secretTargetRef:
      - parameter: username
        name: my-app-credentials
        key: username
      - parameter: password
        name: my-app-credentials
        key: password
*/}}

{{- define "keda.triggerAuthentication" -}}
{{- if .Values.keda -}}
{{- if .Values.keda.triggerAuthentication -}}
{{- if .Values.keda.triggerAuthentication.enabled -}}
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "triggerauth" "name" .Values.keda.triggerAuthentication.name) }}
  namespace: {{ include "forge.namespace" . }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
  {{- with .Values.keda.triggerAuthentication.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.keda.triggerAuthentication.secretTargetRef }}
  # Kubernetes Secret references
  secretTargetRef:
    {{- range .Values.keda.triggerAuthentication.secretTargetRef }}
    - parameter: {{ .parameter | required "parameter is required" }}
      name: {{ .name | required "name is required" }}
      key: {{ .key | required "key is required" }}
    {{- end }}
  {{- end }}

  {{- if .Values.keda.triggerAuthentication.env }}
  # Environment variable references
  env:
    {{- range .Values.keda.triggerAuthentication.env }}
    - parameter: {{ .parameter | required "parameter is required" }}
      name: {{ .name | required "name is required" }}
      {{- with .containerName }}
      containerName: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- if .Values.keda.triggerAuthentication.podIdentity }}
  # Pod Identity (AWS IRSA, Azure Workload Identity, GCP Workload Identity)
  podIdentity:
    {{- toYaml .Values.keda.triggerAuthentication.podIdentity | nindent 4 }}
  {{- end }}

  {{- if .Values.keda.triggerAuthentication.hashiCorpVault }}
  # HashiCorp Vault direct integration
  hashiCorpVault:
    {{- toYaml .Values.keda.triggerAuthentication.hashiCorpVault | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: Prometheus
==============================================================================
Generate Prometheus trigger configuration.

Usage:
  triggers:
    - {{- include "keda.trigger.prometheus" (dict "context" . "config" .prometheusConfig) | nindent 6 }}

Arguments:
  .config.query - PromQL query
  .config.threshold - Target value
  .config.serverAddress - Prometheus server URL
*/}}

{{- define "keda.trigger.prometheus" -}}
type: prometheus
metadata:
  serverAddress: {{ .config.serverAddress | default "http://prometheus:9090" }}
  query: {{ .config.query | required "Prometheus query is required" | quote }}
  threshold: {{ .config.threshold | default "10" | quote }}
  {{- with .config.activationThreshold }}
  activationThreshold: {{ . | quote }}
  {{- end }}
  {{- with .config.namespace }}
  namespace: {{ . }}
  {{- end }}
{{- with .config.authenticationRef }}
authenticationRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: RabbitMQ
==============================================================================
Generate RabbitMQ trigger configuration.

Usage:
  triggers:
    - {{- include "keda.trigger.rabbitmq" (dict "context" . "config" .rabbitmqConfig) | nindent 6 }}

Arguments:
  .config.host - RabbitMQ connection string
  .config.queueName - Queue to monitor
  .config.queueLength - Target queue length
*/}}

{{- define "keda.trigger.rabbitmq" -}}
type: rabbitmq
metadata:
  host: {{ .config.host | required "RabbitMQ host is required" }}
  queueName: {{ .config.queueName | required "Queue name is required" }}
  queueLength: {{ .config.queueLength | default "10" | quote }}
  {{- with .config.protocol }}
  protocol: {{ . }}
  {{- end }}
  {{- with .config.vhostName }}
  vhostName: {{ . }}
  {{- end }}
  {{- with .config.useRegex }}
  useRegex: {{ . | quote }}
  {{- end }}
{{- with .config.authenticationRef }}
authenticationRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: AWS SQS
==============================================================================
Generate AWS SQS trigger configuration.

Usage:
  triggers:
    - {{- include "keda.trigger.awsSqs" (dict "context" . "config" .sqsConfig) | nindent 6 }}

Arguments:
  .config.queueURL - SQS queue URL
  .config.queueLength - Target queue length
  .config.awsRegion - AWS region
*/}}

{{- define "keda.trigger.awsSqs" -}}
type: aws-sqs-queue
metadata:
  queueURL: {{ .config.queueURL | required "SQS queue URL is required" }}
  queueLength: {{ .config.queueLength | default "5" | quote }}
  awsRegion: {{ .config.awsRegion | default "us-east-1" }}
  {{- with .config.activationQueueLength }}
  activationQueueLength: {{ . | quote }}
  {{- end }}
  {{- with .config.identityOwner }}
  identityOwner: {{ . }}
  {{- end }}
{{- with .config.authenticationRef }}
authenticationRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: Kafka
==============================================================================
Generate Kafka trigger configuration.

Usage:
  triggers:
    - {{- include "keda.trigger.kafka" (dict "context" . "config" .kafkaConfig) | nindent 6 }}

Arguments:
  .config.bootstrapServers - Kafka brokers
  .config.consumerGroup - Consumer group
  .config.topic - Topic to monitor
  .config.lagThreshold - Target lag threshold
*/}}

{{- define "keda.trigger.kafka" -}}
type: kafka
metadata:
  bootstrapServers: {{ .config.bootstrapServers | required "Kafka bootstrap servers required" }}
  consumerGroup: {{ .config.consumerGroup | required "Consumer group is required" }}
  topic: {{ .config.topic | required "Topic is required" }}
  lagThreshold: {{ .config.lagThreshold | default "10" | quote }}
  {{- with .config.offsetResetPolicy }}
  offsetResetPolicy: {{ . }}
  {{- end }}
  {{- with .config.allowIdleConsumers }}
  allowIdleConsumers: {{ . | quote }}
  {{- end }}
  {{- with .config.version }}
  version: {{ . }}
  {{- end }}
{{- with .config.authenticationRef }}
authenticationRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: Redis
==============================================================================
Generate Redis trigger configuration.

Usage:
  triggers:
    - {{- include "keda.trigger.redis" (dict "context" . "config" .redisConfig) | nindent 6 }}

Arguments:
  .config.address - Redis server address
  .config.listName - List to monitor (for list length)
  .config.listLength - Target list length
*/}}

{{- define "keda.trigger.redis" -}}
type: redis
metadata:
  address: {{ .config.address | required "Redis address is required" }}
  {{- if .config.listName }}
  listName: {{ .config.listName }}
  listLength: {{ .config.listLength | default "5" | quote }}
  {{- else if .config.streamName }}
  stream: {{ .config.streamName }}
  pendingEntriesCount: {{ .config.pendingEntriesCount | default "5" | quote }}
  {{- end }}
  {{- with .config.databaseIndex }}
  databaseIndex: {{ . | quote }}
  {{- end }}
  {{- with .config.enableTLS }}
  enableTLS: {{ . | quote }}
  {{- end }}
{{- with .config.authenticationRef }}
authenticationRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: Cron
==============================================================================
Generate Cron trigger configuration for time-based scaling.

Usage:
  triggers:
    - {{- include "keda.trigger.cron" (dict "context" . "config" .cronConfig) | nindent 6 }}

Arguments:
  .config.timezone - Timezone (e.g., America/New_York)
  .config.start - Cron expression for scale up
  .config.end - Cron expression for scale down
  .config.desiredReplicas - Target replica count during active period
*/}}

{{- define "keda.trigger.cron" -}}
type: cron
metadata:
  timezone: {{ .config.timezone | default "UTC" }}
  start: {{ .config.start | required "Cron start expression is required" }}
  end: {{ .config.end | required "Cron end expression is required" }}
  desiredReplicas: {{ .config.desiredReplicas | default "3" | quote }}
{{- end -}}

{{/*
==============================================================================
KEDA Trigger: PostgreSQL
==============================================================================
Generate PostgreSQL trigger configuration.

Usage:
  triggers:
    - {{- include "keda.trigger.postgresql" (dict "context" . "config" .postgresConfig) | nindent 6 }}

Arguments:
  .config.connectionString - PostgreSQL connection string (from Vault)
  .config.query - SQL query returning single numeric value
  .config.targetQueryValue - Target value
*/}}

{{- define "keda.trigger.postgresql" -}}
type: postgresql
metadata:
  query: {{ .config.query | required "PostgreSQL query is required" | quote }}
  targetQueryValue: {{ .config.targetQueryValue | default "10" | quote }}
  {{- with .config.activationTargetQueryValue }}
  activationTargetQueryValue: {{ . | quote }}
  {{- end }}
  {{- with .config.connectionFromEnv }}
  connectionFromEnv: {{ . }}
  {{- end }}
{{- with .config.authenticationRef }}
authenticationRef:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
