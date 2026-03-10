# UC-MONITORING-01: Pod Crash Alerts

## Overview

**Use Case ID**: UC-MONITORING-01  
**Chart**: common-monitoring  
**Feature**: Prometheus Alerting  
**Priority**: HIGH  

## Description

This use case validates that the common-monitoring chart correctly creates PrometheusRule resources that fire alerts when pods enter crash loops. The test deploys a deliberately failing pod and verifies that Prometheus detects the crash loop and triggers an alert.

## Prerequisites

- Kubernetes cluster (1.23+)
- Prometheus Operator installed with CRDs
- Prometheus instance running in `monitoring` namespace
- Test namespace: `test-monitoring`
- kubectl and helm installed

## Test Objectives

1. Install common-monitoring chart with availability alerts enabled
2. Deploy a crashloop pod that fails immediately
3. Verify PrometheusRule resource is created
4. Wait for alert to fire in Prometheus
5. Verify alert has correct labels and annotations
6. Verify alert severity is set correctly
7. Test alert recovery (optional)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Test Namespace                          │
│  ┌───────────────┐         ┌──────────────┐               │
│  │ crashloop-pod │─(crash)→│ Pod Status   │               │
│  │   (busybox)   │         │ CrashLoopOff │               │
│  └───────────────┘         └──────────────┘               │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    │ (scrape)
                                    ↓
┌─────────────────────────────────────────────────────────────┐
│                  Monitoring Namespace                       │
│  ┌──────────────────┐     ┌────────────────────┐          │
│  │  PrometheusRule  │────→│    Prometheus      │          │
│  │  (crash-alerts)  │     │  (evaluates rules) │          │
│  └──────────────────┘     └────────────────────┘          │
│                                    │                        │
│                                    │ (alert fires)          │
│                                    ↓                        │
│                           ┌──────────────┐                 │
│                           │   Alerts UI  │                 │
│                           │  (Prometheus)│                 │
│                           └──────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## Test Values Configuration

See: `values/uc01-pod-crash-alerts.yaml`

Key configurations:
```yaml
monitoring:
  prometheus:
    rules:
      availability:
        enabled: true
        podCrashLooping:
          enabled: true
          threshold: 3  # Alert after 3 crashes in 5 minutes
          severity: "warning"
```

## Test Steps

### Step 1: Install Chart

```bash
helm install test-monitoring-uc01 \
  ../../../../charts/common-monitoring \
  -f values/uc01-pod-crash-alerts.yaml \
  -n test-monitoring \
  --create-namespace \
  --wait
```

**Expected**: Chart installs successfully, PrometheusRule created

### Step 2: Verify PrometheusRule Created

```bash
kubectl get prometheusrule -n test-monitoring
```

**Expected Output**:
```
NAME                              AGE
monitoring-availability-alerts    10s
```

### Step 3: Inspect PrometheusRule

```bash
kubectl get prometheusrule monitoring-availability-alerts \
  -n test-monitoring -o yaml
```

**Expected**: Rule contains `PodCrashLooping` alert definition:
```yaml
alert: PodCrashLooping
expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
for: 5m
labels:
  severity: warning
annotations:
  summary: "Pod {{ $labels.pod }} is crash looping"
```

### Step 4: Deploy Crashloop Pod

```bash
kubectl apply -f workloads/crashloop-pod.yaml -n test-monitoring
```

**Expected**: Pod created and immediately starts crashing

### Step 5: Verify Pod is Crashing

```bash
kubectl get pod crashloop-test -n test-monitoring
```

**Expected Output** (after ~30 seconds):
```
NAME              READY   STATUS             RESTARTS   AGE
crashloop-test    0/1     CrashLoopBackOff   3          2m
```

### Step 6: Wait for Alert to Fire

Wait 5-7 minutes for Prometheus to evaluate the rule and fire the alert.

```bash
# Check alert status in Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
```

Open: http://localhost:9090/alerts

**Expected**: `PodCrashLooping` alert in FIRING state

### Step 7: Query Alert via API

```bash
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="PodCrashLooping")'
```

**Expected Output**:
```json
{
  "labels": {
    "alertname": "PodCrashLooping",
    "pod": "crashloop-test",
    "namespace": "test-monitoring",
    "severity": "warning"
  },
  "state": "firing",
  "activeAt": "2026-02-21T10:15:30.123Z",
  "value": "0.016666666666666666"
}
```

### Step 8: Verify Alert Annotations

```bash
kubectl get prometheusrule monitoring-availability-alerts \
  -n test-monitoring -o jsonpath='{.spec.groups[0].rules[0].annotations}'
```

**Expected**: Contains summary, description, runbook_url

### Step 9: Test Alert Recovery (Optional)

Delete the crashloop pod and verify alert resolves:

```bash
kubectl delete pod crashloop-test -n test-monitoring
# Wait 5 minutes
# Alert should transition to RESOLVED state
```

## Validation Criteria

### ✅ Pass Criteria

1. **PrometheusRule Created**: `kubectl get prometheusrule` shows the rule
2. **Pod Crashes**: Pod status shows `CrashLoopBackOff`
3. **Alert Fires**: Alert visible in Prometheus UI in FIRING state
4. **Correct Labels**: Alert has expected labels (pod, namespace, severity)
5. **Correct Threshold**: Alert fires after configured number of restarts
6. **Annotations Present**: Summary and description are set

### ❌ Fail Criteria

1. PrometheusRule not created
2. Alert doesn't fire after 10 minutes
3. Alert fires for healthy pods
4. Missing required labels or annotations
5. Incorrect severity level

## Troubleshooting

### Issue: PrometheusRule Not Created

**Symptoms**: `kubectl get prometheusrule` shows no resources

**Debug**:
```bash
helm get values test-monitoring-uc01 -n test-monitoring
# Verify monitoring.prometheus.rules.availability.enabled=true
```

**Fix**: Ensure chart values are correct, reinstall if needed

---

### Issue: Alert Not Firing

**Symptoms**: Pod crashes but no alert after 10 minutes

**Debug**:
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
# Verify kube-state-metrics target is UP

# Check rule evaluation
# Open http://localhost:9090/rules
# Look for PodCrashLooping rule
```

**Possible Causes**:
- Prometheus not scraping kube-state-metrics
- Rule expression incorrect
- Evaluation interval too long

**Fix**:
```bash
# Restart Prometheus
kubectl rollout restart statefulset prometheus-kube-prometheus-prometheus -n monitoring
```

---

### Issue: Alert Fires Immediately

**Symptoms**: Alert fires before pod crashes 3 times

**Debug**:
```bash
# Check rule definition
kubectl get prometheusrule monitoring-availability-alerts -o yaml
# Look at 'expr' and 'for' fields
```

**Fix**: Adjust threshold in values file:
```yaml
monitoring:
  prometheus:
    rules:
      availability:
        podCrashLooping:
          threshold: 5  # Increase threshold
```

---

### Issue: Pod Not Crashing

**Symptoms**: Pod status remains `Running`

**Debug**:
```bash
kubectl logs crashloop-test -n test-monitoring
kubectl describe pod crashloop-test -n test-monitoring
```

**Fix**: Verify crashloop-pod.yaml has correct command:
```yaml
command: ["sh", "-c", "echo 'Simulating crash' && exit 1"]
```

## Real-World Scenarios

### Scenario 1: Production API Crash Loop

**Context**: Production API pod crashes due to missing database connection

**Alert Flow**:
1. Pod crashes 3 times in 5 minutes
2. PodCrashLooping alert fires
3. Alert routes to PagerDuty
4. On-call engineer receives page
5. Engineer checks pod logs
6. Identifies database connection issue
7. Fixes configuration
8. Pod starts successfully
9. Alert auto-resolves

### Scenario 2: Staging Environment Testing

**Context**: QA team tests new feature that has a bug

**Alert Flow**:
1. Buggy code causes pod to crash
2. Alert fires (severity: warning for staging)
3. Alert routes to Slack #staging-alerts
4. Team sees alert, no immediate action needed
5. Bug fixed in next deployment
6. Alert resolves automatically

### Scenario 3: False Positive - Init Container

**Context**: Pod has init container that intentionally fails and retries

**Problem**: Alert fires for init container crashes

**Solution**: Add exclusion for init containers:
```yaml
expr: |
  rate(kube_pod_container_status_restarts_total{container!~"init-.*"}[5m]) > 0
```

## Integration with Alertmanager

### Route Configuration

```yaml
route:
  routes:
  - match:
      alertname: PodCrashLooping
      severity: critical
    receiver: pagerduty
  - match:
      alertname: PodCrashLooping
      severity: warning
    receiver: slack
```

### Inhibition Rules

Prevent PodCrashLooping alert if higher severity alert is firing:

```yaml
inhibit_rules:
- source_match:
    alertname: KubePodNotReady
  target_match:
    alertname: PodCrashLooping
  equal: ['pod', 'namespace']
```

## Performance Considerations

### Alert Evaluation Frequency

- **Default**: Every 30 seconds
- **Impact**: Low (simple PromQL query)
- **Recommendation**: Keep default

### Alert History

- **Retention**: 15 days (Prometheus default)
- **Storage Impact**: ~10KB per alert firing
- **Total**: ~150KB for 15 alerts/day

## Security Considerations

### RBAC Requirements

Service account needs permissions to read pod status:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

### Alert Data Exposure

**Risk**: Alert annotations may contain sensitive pod names/namespaces

**Mitigation**: 
- Use templating carefully in annotations
- Avoid including sensitive data in labels
- Restrict Prometheus UI access via authentication

## Metrics Used

### kube_pod_container_status_restarts_total

**Source**: kube-state-metrics  
**Type**: Counter  
**Labels**: `pod`, `namespace`, `container`  
**Description**: Total number of container restarts

**Example Query**:
```promql
rate(kube_pod_container_status_restarts_total{namespace="test-monitoring"}[5m])
```

## Test Cleanup

```bash
# Delete crashloop pod
kubectl delete pod crashloop-test -n test-monitoring

# Uninstall chart
helm uninstall test-monitoring-uc01 -n test-monitoring

# Delete namespace (optional)
kubectl delete namespace test-monitoring
```

## References

- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Prometheus Operator API](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md)
- [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)

## Test Execution

**Run automated test**:
```bash
cd test-cases
./run-uc01.sh
```

**Expected Duration**: 8-10 minutes (includes 5-7 min wait for alert)

**Exit Codes**:
- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Prerequisites not met
