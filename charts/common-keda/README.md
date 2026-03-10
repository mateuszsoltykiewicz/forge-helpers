# Common KEDA - Event-Driven Autoscaling Library

**Forge Common Library** for KEDA (Kubernetes Event-Driven Autoscaling) integration.

This library provides reusable Helm templates for event-driven autoscaling:
- **ScaledObject** - replaces HPA with event-driven scaling
- **ScaledJob** - creates Jobs based on external events (batch processing)
- **TriggerAuthentication** - Vault-backed secrets for trigger authentication
- **60+ trigger types** - Prometheus, RabbitMQ, AWS SQS, Kafka, databases, and more

---

## 🚀 Features

- **Event-Driven Autoscaling** - scale based on real metrics (not just CPU/memory)
- **60+ Scalers** - Prometheus, message queues, databases, cloud providers, HTTP, cron
- **Vault Integration** - secure credential management via TriggerAuthentication
- **Scale to Zero** - reduce costs by scaling to 0 replicas when idle
- **Batch Processing** - ScaledJob for message queues and database record processing
- **Advanced Scaling** - fallback, cooldown, multiple triggers, custom metrics

---

## 📦 Installation

Add as a dependency to your Helm chart:

```yaml
# Chart.yaml
dependencies:
  - name: common-keda
    version: ~0.1.0
    repository: file://../common-keda
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
  - name: common-vault
    version: ~0.1.0
    repository: file://../common-vault
    condition: vault.enabled
```

Update dependencies:
```bash
helm dependency update
```

---

## 📖 Usage

### Basic ScaledObject (Prometheus)

Scale Deployment based on Prometheus metrics:

```yaml
# values.yaml
keda:
  scaledobject:
    enabled: true
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: my-api
    pollingInterval: 30
    cooldownPeriod: 300
    minReplicaCount: 2
    maxReplicaCount: 20
    triggers:
      - type: prometheus
        metadata:
          serverAddress: http://prometheus:9090
          query: sum(rate(http_requests_total{app="my-api"}[2m]))
          threshold: "100"
          activationThreshold: "50"

# templates/scaledobject.yaml
{{- include "keda.scaledobject" . }}
```

### ScaledObject with Multiple Triggers

Combine Prometheus + Cron for business hours scaling:

```yaml
keda:
  scaledobject:
    enabled: true
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: my-api
    minReplicaCount: 1
    maxReplicaCount: 20
    triggers:
      # Traffic-based scaling
      - type: prometheus
        name: traffic-scaler
        metadata:
          serverAddress: http://prometheus:9090
          query: sum(rate(http_requests_total[2m]))
          threshold: "100"
      
      # Business hours scaling (ensure min 5 replicas during work hours)
      - type: cron
        name: business-hours
        metadata:
          timezone: America/New_York
          start: "0 8 * * 1-5"   # 8am weekdays
          end: "0 18 * * 1-5"    # 6pm weekdays
          desiredReplicas: "5"
```

### ScaledObject with RabbitMQ

Scale based on message queue depth:

```yaml
keda:
  scaledobject:
    enabled: true
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: message-processor
    minReplicaCount: 1
    maxReplicaCount: 15
    triggers:
      - type: rabbitmq
        metadata:
          host: amqp://rabbitmq:5672
          queueName: tasks
          queueLength: "10"  # Scale up when queue has >10 messages
        authenticationRef:
          name: rabbitmq-trigger-auth

  triggerAuthentication:
    enabled: true
    name: rabbitmq-trigger-auth
    secretTargetRef:
      - parameter: username
        name: rabbitmq-credentials
        key: username
      - parameter: password
        name: rabbitmq-credentials
        key: password
```

### ScaledJob - RabbitMQ Batch Processing

Process messages in batches (creates Jobs):

```yaml
keda:
  scaledjob:
    enabled: true
    jobTargetRef:
      template:
        metadata:
          labels:
            app: message-batch-processor
        spec:
          containers:
            - name: processor
              image: my-app:latest
              command: ["python", "process_batch.py"]
              env:
                - name: BATCH_SIZE
                  value: "10"
          restartPolicy: OnFailure
    pollingInterval: 30
    maxReplicaCount: 10
    successfulJobsHistoryLimit: 5
    failedJobsHistoryLimit: 5
    scalingStrategy:
      strategy: "accurate"
      customScalingQueueLengthDeduction: 10  # Each job processes 10 messages
      customScalingRunningJobPercentage: "0.5"
    triggers:
      - type: rabbitmq
        metadata:
          host: amqp://rabbitmq:5672
          queueName: batch-tasks
          queueLength: "10"
        authenticationRef:
          name: rabbitmq-trigger-auth
```

### ScaledJob - AWS SQS Batch Processing

Process AWS SQS messages with IRSA authentication:

```yaml
keda:
  scaledjob:
    enabled: true
    jobTargetRef:
      template:
        spec:
          serviceAccountName: my-app-sa  # With IRSA role
          containers:
            - name: processor
              image: my-app:latest
              command: ["python", "process_sqs.py"]
          restartPolicy: OnFailure
    maxReplicaCount: 10
    scalingStrategy:
      strategy: "accurate"
      customScalingQueueLengthDeduction: 10
    triggers:
      - type: aws-sqs-queue
        metadata:
          queueURL: https://sqs.us-east-1.amazonaws.com/123456789012/my-queue
          queueLength: "10"
          awsRegion: us-east-1
          identityOwner: operator  # Use IRSA from operator
```

### ScaledJob - Database Batch Processing

Process pending database records in batches:

```yaml
keda:
  scaledjob:
    enabled: true
    jobTargetRef:
      template:
        spec:
          containers:
            - name: processor
              image: my-app:latest
              command: ["python", "process_records.py"]
              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: database-credentials
                      key: url
          restartPolicy: OnFailure
    pollingInterval: 60
    maxReplicaCount: 5
    scalingStrategy:
      strategy: "accurate"
      customScalingQueueLengthDeduction: 100  # Each job processes 100 records
    triggers:
      - type: postgresql
        metadata:
          query: "SELECT COUNT(*) FROM orders WHERE status = 'pending'"
          targetQueryValue: "100"
          connectionFromEnv: DATABASE_URL
```

### Pre-configured Batch Processing Patterns

**RabbitMQ Batch** (using helper template):

```yaml
keda:
  scaledjob:
    jobTargetRef:
      template:
        spec:
          containers:
            - name: processor
              image: my-app:latest
          restartPolicy: OnFailure
    rabbitmq:
      enabled: true
      host: amqp://rabbitmq:5672
      queueName: batch-tasks
      messagesPerJob: 10
      maxReplicaCount: 10
      authenticationRef:
        name: rabbitmq-trigger-auth

# templates/scaledjob.yaml
{{- include "keda.scaledjob.rabbitmqBatch" . }}
```

**AWS SQS Batch** (using helper template):

```yaml
keda:
  scaledjob:
    jobTargetRef:
      template:
        spec:
          serviceAccountName: my-app-sa
          containers:
            - name: processor
              image: my-app:latest
          restartPolicy: OnFailure
    sqs:
      enabled: true
      queueURL: https://sqs.us-east-1.amazonaws.com/123456789012/my-queue
      awsRegion: us-east-1
      messagesPerJob: 10
      maxReplicaCount: 10

# templates/scaledjob.yaml
{{- include "keda.scaledjob.sqsBatch" . }}
```

**Database Batch** (using helper template):

```yaml
keda:
  scaledjob:
    jobTargetRef:
      template:
        spec:
          containers:
            - name: processor
              image: my-app:latest
              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: db-creds
                      key: url
          restartPolicy: OnFailure
    database:
      enabled: true
      type: postgresql
      query: "SELECT COUNT(*) FROM pending_tasks WHERE status = 'pending'"
      recordsPerJob: 100
      maxReplicaCount: 5
      connectionFromEnv: DATABASE_URL

# templates/scaledjob.yaml
{{- include "keda.scaledjob.databaseBatch" . }}
```

---

## 📚 Templates Reference

### ScaledObject

#### Main Template
```yaml
{{- include "keda.scaledobject" . }}
```
Generates complete ScaledObject with triggers and authentication.

**Requirements**:
- `.Values.keda.scaledobject.enabled = true`
- `.Values.keda.scaledobject.scaleTargetRef` - target workload
- `.Values.keda.scaledobject.triggers` - array of trigger configurations

### ScaledJob

#### Main Template
```yaml
{{- include "keda.scaledjob" . }}
```
Generates complete ScaledJob for batch processing.

**Requirements**:
- `.Values.keda.scaledjob.enabled = true`
- `.Values.keda.scaledjob.jobTargetRef` - Job template
- `.Values.keda.scaledjob.triggers` - array of trigger configurations

#### Pre-configured Batch Patterns
```yaml
{{- include "keda.scaledjob.rabbitmqBatch" . }}
{{- include "keda.scaledjob.sqsBatch" . }}
{{- include "keda.scaledjob.databaseBatch" . }}
```

### TriggerAuthentication

```yaml
{{- include "keda.triggerAuthentication" . }}
```
Generates TriggerAuthentication with Vault-backed secrets.

### Trigger Helpers

Individual trigger configuration helpers:
```yaml
{{- include "keda.trigger.prometheus" (dict "context" . "config" .prometheusConfig) }}
{{- include "keda.trigger.rabbitmq" (dict "context" . "config" .rabbitmqConfig) }}
{{- include "keda.trigger.awsSqs" (dict "context" . "config" .sqsConfig) }}
{{- include "keda.trigger.kafka" (dict "context" . "config" .kafkaConfig) }}
{{- include "keda.trigger.redis" (dict "context" . "config" .redisConfig) }}
{{- include "keda.trigger.cron" (dict "context" . "config" .cronConfig) }}
{{- include "keda.trigger.postgresql" (dict "context" . "config" .postgresConfig) }}
```

---

## 🔧 Configuration

See [`values.yaml`](./values.yaml) for all configuration options.

### Key Configuration Sections

- **keda.scaledobject**: ScaledObject configuration
  - scaleTargetRef, pollingInterval, cooldownPeriod
  - minReplicaCount, maxReplicaCount, idleReplicaCount
  - advanced (HPA behavior), fallback
  - triggers (array of trigger configurations)

- **keda.scaledjob**: ScaledJob configuration
  - jobTargetRef (Job template)
  - pollingInterval, maxReplicaCount
  - successfulJobsHistoryLimit, failedJobsHistoryLimit
  - scalingStrategy (default, custom, accurate)
  - triggers (array of trigger configurations)

- **keda.triggerAuthentication**: TriggerAuthentication configuration
  - secretTargetRef (Kubernetes Secrets)
  - env (environment variables)
  - podIdentity (AWS IRSA, Azure, GCP)
  - hashiCorpVault (direct Vault integration)

---

## 🎯 Supported Trigger Types

- **prometheus** - Prometheus/Thanos metrics
- **rabbitmq** - RabbitMQ queue depth
- **aws-sqs-queue** - AWS SQS queue depth
- **kafka** - Kafka consumer lag
- **redis** - Redis list/stream length
- **cron** - Time-based scaling
- **postgresql** - PostgreSQL query results
- **mysql** - MySQL query results
- **mongodb** - MongoDB query results
- **azure-queue** - Azure Queue Storage
- **gcp-pubsub** - GCP Pub/Sub
- **http** - HTTP endpoints
- ...and 50+ more!

See [KEDA Scalers Documentation](https://keda.sh/docs/latest/scalers/) for complete list.

---

## 🧪 Examples

### Scale to Zero (Cost Optimization)

```yaml
keda:
  scaledobject:
    enabled: true
    idleReplicaCount: 0  # Scale to zero when no traffic
    minReplicaCount: 0
    maxReplicaCount: 10
    triggers:
      - type: prometheus
        metadata:
          serverAddress: http://prometheus:9090
          query: sum(rate(http_requests_total[2m]))
          threshold: "1"
          activationThreshold: "1"  # Scale up on first request
```

### Multi-Region with Fallback

```yaml
keda:
  scaledobject:
    enabled: true
    minReplicaCount: 2
    maxReplicaCount: 20
    fallback:
      failureThreshold: 3  # After 3 failed checks
      replicas: 5          # Fall back to 5 replicas
    triggers:
      - type: prometheus
        metadata:
          serverAddress: http://prometheus-us-east-1:9090
          query: sum(rate(http_requests_total[2m]))
          threshold: "100"
```

---

## 🔗 Integration with Other Libraries

This library works seamlessly with:

- **common-forge**: Provides naming conventions and labels
- **common-vault**: Vault integration for trigger authentication
- **common-kubernetes**: Base Kubernetes resource templates
- **common-aws**: IRSA integration for AWS scalers (SQS, CloudWatch)

---

## 🛠️ Dependencies

- **common-forge** (~0.1.0): Naming and validation helpers
- **common-vault** (~0.1.0): Vault integration (optional)

---

## 📝 License

Part of the Forge Platform - Internal Use Only

---

## 🤝 Contributing

See main repository contributing guidelines.

---

## 📞 Support

For issues or questions, contact the Platform Engineering team.
