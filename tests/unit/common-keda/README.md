# Common-KEDA Test Suite

Comprehensive test suite for the `common-keda` Helm chart, which provides event-driven autoscaling capabilities using KEDA (Kubernetes Event-Driven Autoscaling).

## Overview

KEDA is a Kubernetes-based event-driven autoscaler that extends the native Horizontal Pod Autoscaler (HPA) with additional scalers for external metrics sources like Prometheus, cron schedules, message queues, and more. This test suite validates the `common-keda` chart's ability to deploy and configure ScaledObjects for different scaling scenarios.

## Prerequisites

1. **Kubernetes cluster** (v1.23+)
2. **Helm** (v3.8+)
3. **kubectl** configured for your cluster
4. **KEDA operator** (v2.12.0 or later):
   ```bash
   kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
   ```
5. **Metrics Server** (for CPU scaler):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

## Test Cases

### UC01: CPU ScaledObject
**File**: `test-cases/UC01-cpu-scaler.md`

Tests CPU-based autoscaling using KEDA's CPU scaler (similar to HPA but managed by KEDA). Deploys a ScaledObject that scales based on CPU utilization threshold (50%).

**Key Features**:
- ScaledObject with CPU trigger
- Replicas scale between 1-5 based on CPU usage
- Validates ScaledObject status and deployment scaling behavior

**Run**: `cd test-cases && ./run-uc01.sh`

---

### UC02: Cron ScaledObject
**File**: `test-cases/UC02-cron-scaler.md`

Tests schedule-based autoscaling using cron expressions. Common use case: scale up during business hours (8 AM - 6 PM) and scale down during off-hours.

**Key Features**:
- Cron trigger with start and end schedules
- Business hours pattern (8 AM - 6 PM UTC)
- Replicas scale to 5 during business hours, 1 otherwise

**Run**: `cd test-cases && ./run-uc02.sh`

---

### UC03: External Scaler (Prometheus)
**File**: `test-cases/UC03-external-scaler.md`

Tests external metrics-based autoscaling using Prometheus. Scales based on custom application metrics like HTTP requests per second, queue depth, or business KPIs.

**Key Features**:
- Prometheus scaler with custom query
- Query: `sum(rate(http_requests_total[1m]))`
- Threshold: 100 requests/second
- Replicas scale between 1-10 based on metric value

**Run**: `cd test-cases && ./run-uc03.sh`

**Note**: Requires Prometheus server available in the cluster.

---

## Directory Structure

```
common-keda/
├── README.md                           # This file
├── run-all.sh                          # Run all test cases
├── test-cases/
│   ├── UC01-cpu-scaler.md             # UC01 documentation
│   ├── UC02-cron-scaler.md            # UC02 documentation
│   ├── UC03-external-scaler.md        # UC03 documentation
│   ├── run-uc01.sh                    # UC01 test script
│   ├── run-uc02.sh                    # UC02 test script
│   └── run-uc03.sh                    # UC03 test script
└── values/
    ├── uc01-cpu-scaler.yaml           # CPU scaler values
    ├── uc02-cron-scaler.yaml          # Cron scaler values
    └── uc03-external-scaler.yaml      # Prometheus scaler values
```

## Quick Start

### Run All Tests
```bash
./run-all.sh
```

### Run Individual Tests
```bash
cd test-cases
./run-uc01.sh  # CPU ScaledObject
./run-uc02.sh  # Cron ScaledObject
./run-uc03.sh  # Prometheus ScaledObject
```

### Install KEDA Operator
If KEDA is not installed:
```bash
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keda-operator -n keda --timeout=300s
```

### Verify KEDA Installation
```bash
kubectl get deployment keda-operator -n keda
kubectl get deployment keda-operator-metrics-apiserver -n keda
```

## Common KEDA Concepts

### ScaledObject
A ScaledObject is KEDA's CRD that defines:
- **Target**: Deployment/StatefulSet to scale
- **Min/Max replicas**: Scaling boundaries
- **Triggers**: One or more scalers (CPU, Prometheus, cron, etc.)
- **Polling interval**: How often to check metrics
- **Cooldown period**: Wait time before scaling down

### Scalers
KEDA supports 50+ scalers:
- **CPU/Memory**: Similar to HPA
- **Cron**: Schedule-based scaling
- **Prometheus**: Custom metrics from Prometheus
- **Kafka**: Message queue depth
- **RabbitMQ**: Queue length
- **AWS SQS**: Queue messages
- **Azure Service Bus**: Message count
- **PostgreSQL**: Query result
- And many more...

### Scaling Behavior
- **Scale to Zero**: KEDA can scale down to 0 replicas (when `minReplicaCount: 0`)
- **Multiple Triggers**: Use OR logic (scale if ANY trigger activated)
- **Fallback**: Define fallback replicas if metrics unavailable

## Real-World Examples

### Example 1: Business Hours Scaling
```yaml
# Scale up during office hours, down during nights/weekends
kedaScaledObject:
  enabled: true
  triggers:
    - type: cron
      metadata:
        timezone: America/New_York
        start: "0 9 * * 1-5"  # 9 AM Mon-Fri
        end: "0 18 * * 1-5"   # 6 PM Mon-Fri
        desiredReplicas: "10"
  minReplicaCount: 2
  maxReplicaCount: 15
```

### Example 2: API Rate-Based Scaling
```yaml
# Scale based on API request rate
kedaScaledObject:
  enabled: true
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus:9090
        query: sum(rate(api_requests_total[1m]))
        threshold: "1000"  # Scale up if > 1000 req/s
  minReplicaCount: 5
  maxReplicaCount: 50
```

### Example 3: Queue Depth Scaling
```yaml
# Scale based on message queue length
kedaScaledObject:
  enabled: true
  triggers:
    - type: rabbitmq
      metadata:
        queueName: task-queue
        queueLength: "10"  # Scale up if queue > 10 messages
  minReplicaCount: 1
  maxReplicaCount: 20
```

## Troubleshooting

### ScaledObject Not Scaling
```bash
# Check ScaledObject status
kubectl describe scaledobject <name> -n <namespace>

# Check KEDA operator logs
kubectl logs -l app.kubernetes.io/name=keda-operator -n keda --tail=100

# Verify metrics server (for CPU scaler)
kubectl top nodes
kubectl top pods -n <namespace>
```

### Prometheus Scaler Issues
```bash
# Verify Prometheus connectivity from KEDA
kubectl run curl --image=curlimages/curl -it --rm -- \
  curl http://prometheus-server:9090/api/v1/query?query=up

# Check Prometheus query syntax
kubectl exec -it <prometheus-pod> -n monitoring -- \
  promtool query instant http://localhost:9090 'sum(rate(http_requests_total[1m]))'
```

### Cron Scaler Not Triggering
- **Timezone**: Ensure correct timezone in metadata
- **Testing**: Use near-future times for quick validation:
  ```yaml
  start: "*/5 * * * *"  # Every 5 minutes (for testing)
  ```
- **Logs**: Check KEDA logs for cron schedule parsing errors

## Best Practices

1. **Start Conservative**: Begin with conservative min/max replicas, then tune based on load
2. **Multiple Triggers**: Use multiple scalers for complex scenarios (e.g., CPU + queue depth)
3. **Monitoring**: Always monitor ScaledObject status and KEDA metrics
4. **Cooldown Periods**: Set appropriate cooldowns to prevent flapping
5. **Scale to Zero**: Use cautiously—only for truly idle workloads
6. **Testing**: Test scaling behavior under realistic load before production
7. **Fallback Values**: Always define fallback replicas for metric failures

## Scaling Patterns

### Pattern 1: Burst Workloads
- **Use Case**: Batch jobs, data processing
- **Scaler**: Queue-based (Kafka, RabbitMQ, SQS)
- **Config**: Min 0, max high, fast scale-up

### Pattern 2: Predictable Traffic
- **Use Case**: Business applications, APIs
- **Scaler**: Cron + Prometheus
- **Config**: Business hours baseline + demand-based scaling

### Pattern 3: Continuous Load
- **Use Case**: Microservices, databases
- **Scaler**: CPU/Memory + custom metrics
- **Config**: Higher min replicas, moderate max

## Resources

- [KEDA Documentation](https://keda.sh/docs/)
- [Scaler Catalog](https://keda.sh/docs/latest/scalers/)
- [KEDA GitHub](https://github.com/kedacore/keda)
- [Prometheus Scaler](https://keda.sh/docs/latest/scalers/prometheus/)
- [Cron Scaler](https://keda.sh/docs/latest/scalers/cron/)

## Support

For issues or questions:
1. Check ScaledObject status: `kubectl describe scaledobject`
2. Review KEDA operator logs
3. Consult [KEDA troubleshooting guide](https://keda.sh/docs/latest/troubleshooting/)
4. Open an issue in the common-keda chart repository
