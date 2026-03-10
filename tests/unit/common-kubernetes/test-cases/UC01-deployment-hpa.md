# UC-KUBERNETES-01: Deployment with Horizontal Pod Autoscaler

## Overview

This use case validates the deployment of applications with Horizontal Pod Autoscaler (HPA) in Kubernetes. It tests automatic scaling based on resource metrics (CPU/memory), scale up/down behavior, and HPA configuration best practices.

**Test Type**: Type 1 (Isolated Chart Testing)

**Chart**: `common-kubernetes`

**Duration**: ~15 minutes (including scaling observation)

## Test Objectives

1. ✅ Deploy application with HPA configuration
2. ✅ Verify HPA creation and initial state
3. ✅ Validate metrics server integration
4. ✅ Generate load to trigger scale-up
5. ✅ Observe automatic pod scaling
6. ✅ Verify scale-down after load reduction
7. ✅ Test HPA behavior policies
8. ✅ Validate resource requests/limits
9. ✅ Check HPA events and status
10. ✅ Verify pod distribution across nodes

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                      │
│                                                             │
│  ┌──────────────┐         ┌─────────────────────┐         │
│  │   Metrics    │◄────────│   HPA Controller    │         │
│  │   Server     │         │  (kube-controller)  │         │
│  └──────┬───────┘         └──────────┬──────────┘         │
│         │                             │                     │
│         │ CPU/Memory                  │ Scale                │
│         │ Metrics                     │ Pods                │
│         │                             │                     │
│         ▼                             ▼                     │
│  ┌─────────────────────────────────────────────────┐       │
│  │              HPA Resource                       │       │
│  │  minReplicas: 1, maxReplicas: 5                │       │
│  │  targetCPU: 50%, targetMemory: 70%             │       │
│  └────────────────────┬────────────────────────────┘       │
│                       │                                     │
│                       │ Controls                            │
│                       ▼                                     │
│  ┌─────────────────────────────────────────────────┐       │
│  │              Deployment                         │       │
│  │  replicas: <managed by HPA>                    │       │
│  │                                                 │       │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │       │
│  │  │  Pod 1  │  │  Pod 2  │  │  Pod 3  │  ...  │       │
│  │  │ nginx   │  │ nginx   │  │ nginx   │       │       │
│  │  │ CPU:50m │  │ CPU:75m │  │ CPU:60m │       │       │
│  │  └─────────┘  └─────────┘  └─────────┘       │       │
│  └─────────────────────────────────────────────────┘       │
│                       ▲                                     │
│                       │                                     │
│                       │ Service                             │
│                       │                                     │
│  ┌─────────────────────────────────────────────────┐       │
│  │         Load Generator Pod                      │       │
│  │  Sends HTTP requests to service                │       │
│  │  → Increases CPU usage in pods                 │       │
│  │  → Triggers HPA scale-up                       │       │
│  └─────────────────────────────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools

```bash
# kubectl
kubectl version --client

# helm
helm version

# Cluster access
kubectl cluster-info
```

### Cluster Requirements

```bash
# Metrics Server (REQUIRED for HPA)
kubectl get deployment metrics-server -n kube-system

# If not installed:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For minikube/kind, enable metrics:
# minikube addons enable metrics-server
# kind: metrics-server should be patched with --kubelet-insecure-tls

# Verify metrics available:
kubectl top nodes
kubectl top pods -A
```

### Minimum Cluster Size

- **Nodes**: 1+ (preferably 2+ for distribution testing)
- **CPU**: 2+ cores available
- **Memory**: 4GB+ available

## Test Procedure

### 1. Deploy Application with HPA

```bash
# Navigate to test directory
cd tests/unit/common-kubernetes/test-cases

# Install chart with HPA configuration
helm install hpa-test ../../../../charts/common-kubernetes \
  -f ../values/uc01-deployment-hpa.yaml \
  --wait --timeout 5m

# Verify installation
kubectl get deployments
kubectl get hpa
kubectl get pods
```

**Expected Output**:
```
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
hpa-test-app    1/1     1            1           30s

NAME           REFERENCE                 TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
hpa-test-app   Deployment/hpa-test-app   2%/50%, 5%/70%  1         5         1          30s

NAME                            READY   STATUS    RESTARTS   AGE
hpa-test-app-5d7c8b9f4d-abc12   1/1     Running   0          30s
```

### 2. Verify HPA Configuration

```bash
# Check HPA details
kubectl describe hpa hpa-test-app

# View HPA in YAML
kubectl get hpa hpa-test-app -o yaml

# Check metrics availability
kubectl get hpa hpa-test-app -o jsonpath='{.status.currentMetrics}' | jq
```

**Expected HPA Status**:
- **Reference**: Deployment/hpa-test-app
- **Metrics**: CPU: <50%, Memory: <70% (idle state)
- **Min/Max Replicas**: 1/5
- **Current Replicas**: 1
- **Behavior**: Scale up/down policies configured

### 3. Deploy Load Generator

```bash
# Apply load generator pod
kubectl apply -f ../workloads/load-generator.yaml

# Monitor load generator logs
kubectl logs -f load-generator
```

**Load Generator Actions**:
1. Starts sending HTTP requests to service (10 req/sec)
2. Runs for 5 minutes
3. Increases pod CPU usage to trigger HPA

### 4. Monitor HPA Scaling

```bash
# Watch HPA in real-time (separate terminal)
kubectl get hpa hpa-test-app -w

# Watch pod scaling
kubectl get pods -l app=hpa-test-app -w

# Monitor resource usage
watch kubectl top pods -l app=hpa-test-app
```

**Expected Behavior**:

**Initial State (0-60s)**:
```
NAME           REFERENCE                 TARGETS         MINPODS   MAXPODS   REPLICAS
hpa-test-app   Deployment/hpa-test-app   5%/50%, 8%/70%  1         5         1
```

**Load Increasing (60-120s)**:
```
NAME           REFERENCE                 TARGETS           MINPODS   MAXPODS   REPLICAS
hpa-test-app   Deployment/hpa-test-app   65%/50%, 35%/70%  1         5         1
```

**Scale-Up Triggered (120s+)**:
```
NAME           REFERENCE                 TARGETS           MINPODS   MAXPODS   REPLICAS
hpa-test-app   Deployment/hpa-test-app   68%/50%, 38%/70%  1         5         2  ← Scaled to 2
```

**Further Scaling (180s+)**:
```
NAME           REFERENCE                 TARGETS           MINPODS   MAXPODS   REPLICAS
hpa-test-app   Deployment/hpa-test-app   55%/50%, 32%/70%  1         5         3  ← Scaled to 3
```

**Load Ends (300s)**:
- Load generator completes
- CPU usage drops
- HPA enters stabilization window (300s for scale-down)

**Scale-Down (600s+)**:
```
NAME           REFERENCE                 TARGETS         MINPODS   MAXPODS   REPLICAS
hpa-test-app   Deployment/hpa-test-app   2%/50%, 5%/70%  1         5         2  ← Scaled down to 2
```

**Final State (900s+)**:
```
NAME           REFERENCE                 TARGETS         MINPODS   MAXPODS   REPLICAS
hpa-test-app   Deployment/hpa-test-app   1%/50%, 4%/70%  1         5         1  ← Back to min
```

### 5. Verify HPA Events

```bash
# View HPA events
kubectl describe hpa hpa-test-app | grep -A 20 Events

# View deployment events
kubectl describe deployment hpa-test-app | grep -A 20 Events

# View pod events
kubectl get events --sort-by='.lastTimestamp' | grep hpa-test-app
```

**Expected Events**:
```
Type    Reason             Age    Message
----    ------             ----   -------
Normal  SuccessfulRescale  3m     New size: 2; reason: cpu resource utilization above target
Normal  SuccessfulRescale  2m     New size: 3; reason: cpu resource utilization above target
Normal  SuccessfulRescale  8m     New size: 2; reason: All metrics below target
Normal  SuccessfulRescale  13m    New size: 1; reason: All metrics below target
```

### 6. Test HPA Behavior Policies

```bash
# Check scale-up policy
kubectl get hpa hpa-test-app -o jsonpath='{.spec.behavior.scaleUp}' | jq

# Check scale-down policy
kubectl get hpa hpa-test-app -o jsonpath='{.spec.behavior.scaleDown}' | jq
```

**Scale-Up Policy**:
- **Stabilization**: 60 seconds
- **Policies**: Add max 2 pods or 50% of current (whichever is higher)
- **Result**: Fast response to load increases

**Scale-Down Policy**:
- **Stabilization**: 300 seconds (5 minutes)
- **Policies**: Remove max 1 pod or 10% of current (whichever is lower)
- **Result**: Conservative scale-down to avoid flapping

### 7. Validate Resource Configuration

```bash
# Check pod resource requests/limits
kubectl get pods -l app=hpa-test-app -o jsonpath='{.items[0].spec.containers[0].resources}' | jq

# Verify CPU requests (HPA baseline)
kubectl get pods -l app=hpa-test-app -o jsonpath='{.items[*].spec.containers[*].resources.requests.cpu}'
```

**Expected Resources**:
```json
{
  "requests": {
    "cpu": "100m",      ← HPA uses this as 100% baseline
    "memory": "128Mi"
  },
  "limits": {
    "cpu": "200m",
    "memory": "256Mi"
  }
}
```

**Critical**: HPA calculates utilization as `(current usage / requests) * 100%`

### 8. Test Manual Scaling (Conflict Check)

```bash
# Attempt manual scale (should be reverted by HPA)
kubectl scale deployment hpa-test-app --replicas=10

# Watch HPA revert the change
kubectl get deployment hpa-test-app -w
kubectl get hpa hpa-test-app -w
```

**Expected Behavior**:
1. Deployment scales to 10 replicas
2. HPA detects change
3. HPA reverts to calculated replica count (1-5)
4. Warning in HPA events about manual scaling

### 9. Cleanup

```bash
# Delete load generator
kubectl delete -f ../workloads/load-generator.yaml

# Uninstall chart
helm uninstall hpa-test

# Verify cleanup
kubectl get all -l test-case=uc01
```

## Validation Criteria

### ✅ Pass Criteria

1. **Deployment Created**: Deployment with 1 replica running
2. **HPA Created**: HPA resource exists with correct min/max replicas
3. **Metrics Available**: HPA shows current CPU/memory metrics
4. **Scale-Up Works**: Pods increase when load is applied
5. **Scale-Down Works**: Pods decrease after load ends
6. **Stabilization**: Scale-down waits for stabilization window
7. **Resource Limits**: All pods have requests/limits defined
8. **Events Logged**: HPA events show scaling decisions

### ❌ Fail Criteria

1. **No Metrics**: HPA shows `<unknown>` for metrics
2. **No Scaling**: Pods don't increase despite high CPU
3. **Flapping**: Rapid scale up/down (indicates poor configuration)
4. **Pod Failures**: Pods fail to start after scaling
5. **Resource Issues**: Pods evicted due to resource limits

## Troubleshooting

### HPA Shows `<unknown>` Metrics

**Problem**: HPA cannot read metrics
```bash
kubectl describe hpa hpa-test-app
# Output: "unable to get metrics for resource cpu"
```

**Solution**:
```bash
# Check metrics-server
kubectl get deployment metrics-server -n kube-system
kubectl logs -n kube-system deployment/metrics-server

# For minikube/kind, patch metrics-server:
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Wait for metrics to be available (30-60s)
kubectl top nodes
kubectl top pods
```

### HPA Not Scaling Up

**Problem**: CPU is high but HPA doesn't scale

**Check**:
```bash
# 1. Verify resource requests are set
kubectl get pods -l app=hpa-test-app -o yaml | grep -A 5 resources

# 2. Check actual CPU usage
kubectl top pods -l app=hpa-test-app

# 3. Verify HPA calculation
kubectl describe hpa hpa-test-app | grep -i cpu
```

**Common Issues**:
- Missing CPU requests (HPA cannot calculate percentage)
- CPU usage below threshold (increase load)
- Stabilization window (wait 60s after last scale event)

### HPA Flapping (Rapid Scale Up/Down)

**Problem**: Pods constantly scaling up and down

**Solution**:
```bash
# Increase stabilization windows
helm upgrade hpa-test --set hpa.behavior.scaleDown.stabilizationWindowSeconds=600

# Adjust thresholds (give more headroom)
helm upgrade hpa-test --set hpa.targetCPUUtilizationPercentage=60
```

### Pods Not Distributing Across Nodes

**Problem**: All pods on same node

**Check**:
```bash
# View pod node assignments
kubectl get pods -l app=hpa-test-app -o wide

# Check anti-affinity configuration
kubectl get deployment hpa-test-app -o yaml | grep -A 10 affinity
```

**Solution**:
```bash
# Add pod anti-affinity to spread pods
helm upgrade hpa-test --set affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey=kubernetes.io/hostname
```

## Real-World Scenarios

### Scenario 1: Production Web Application

**Requirements**:
- Handle traffic spikes (3x normal load)
- Maintain 70% CPU utilization target
- Keep minimum 3 replicas for HA
- Scale up quickly, scale down slowly

**Configuration**:
```yaml
hpa:
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30  # Fast response
      policies:
      - type: Percent
        value: 100  # Double pods
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 600  # 10 min wait
      policies:
      - type: Pods
        value: 1  # Remove 1 at a time
        periodSeconds: 120  # Every 2 minutes
```

### Scenario 2: API Service with Memory Constraints

**Requirements**:
- Memory-intensive operations
- Scale based on memory usage
- Limit maximum pods due to data store limits

**Configuration**:
```yaml
hpa:
  minReplicas: 2
  maxReplicas: 8
  targetCPUUtilizationPercentage: 60
  targetMemoryUtilizationPercentage: 75
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### Scenario 3: Background Worker (Event-Driven)

**Requirements**:
- Scale based on queue depth (custom metric)
- Conservative scaling to avoid wasting resources
- Allow aggressive scale-down when idle

**Configuration**:
```yaml
hpa:
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: External
    external:
      metric:
        name: sqs_queue_depth
      target:
        type: AverageValue
        averageValue: "30"  # 30 messages per pod
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 120
      policies:
      - type: Pods
        value: 2
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 180
      policies:
      - type: Percent
        value: 50  # Remove half when idle
        periodSeconds: 60
```

## Best Practices

### Resource Requests/Limits

1. **Always Set Requests**: HPA requires CPU/memory requests
2. **Request = Target Usage**: Set requests to expected average usage
3. **Limit = 2x Request**: Give headroom for bursts
4. **Test Under Load**: Verify requests match actual usage

### HPA Configuration

1. **Conservative Thresholds**: Start with 70-80% CPU target
2. **Slow Scale-Down**: Use 5-10 minute stabilization windows
3. **Fast Scale-Up**: Use 30-60 second stabilization windows
4. **Test Scaling**: Generate load to verify behavior

### Deployment Strategy

1. **RollingUpdate**: Use with HPA to maintain availability
2. **PodDisruptionBudget**: Prevent too many pods terminating
3. **Readiness Probes**: Ensure new pods are ready before receiving traffic
4. **Anti-Affinity**: Spread pods across nodes for HA

### Monitoring

1. **HPA Metrics**: Monitor scaling events and decisions
2. **Resource Usage**: Track actual CPU/memory usage
3. **Response Time**: Ensure scaling happens fast enough
4. **Cost**: Monitor cloud costs (pod count × time)

## References

- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Custom Metrics](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-custom-metrics)
- [HPA Behavior Configuration](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior)

## Next Steps

After completing UC01, proceed to:
- **UC02**: Service + Ingress Configuration
- **UC03**: ConfigMap/Secret Management
- **UC04**: RBAC Setup

Test all use cases together:
```bash
cd tests/unit/common-kubernetes
./run-all.sh
```
