# UC-MONITORING-03: SLO Monitoring (P99 Latency)

## Overview

**Use Case ID**: UC-MONITORING-03  
**Chart**: common-monitoring  
**Feature**: Service Level Objective (SLO) Alerting  
**Priority**: HIGH  

## Description

This use case validates that the common-monitoring chart correctly creates PrometheusRule resources for Service Level Objectives (SLOs), specifically P99 latency monitoring. The test deploys a test application with configurable latency and verifies that alerts fire when the P99 latency exceeds the defined SLO threshold.

## Prerequisites

- Kubernetes cluster (1.23+)
- Prometheus Operator installed with CRDs
- Prometheus instance running in `monitoring` namespace
- Test namespace: `test-monitoring`
- kubectl, helm, curl installed
- hey (load testing tool) or similar

## Test Objectives

1. Install common-monitoring chart with SLO latency rules enabled
2. Deploy test application with slow endpoint
3. Generate traffic with varying latencies
4. Verify PrometheusRule for P99 latency is created
5. Verify alert fires when P99 exceeds threshold (500ms)
6. Verify alert resolves when latency improves
7. Test different percentiles (P95, P99, P99.9)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Test Namespace                          │
│  ┌───────────────┐         ┌──────────────┐               │
│  │   Test App    │────────→│   Metrics    │               │
│  │  /fast (10ms) │         │   Endpoint   │               │
│  │  /slow (1s)   │         │   :9090/m    │               │
│  └───────────────┘         └──────────────┘               │
│         ↑                                                   │
│         │ (load testing)                                    │
│  ┌───────────────┐                                         │
│  │  hey/curl     │                                         │
│  │  (traffic gen)│                                         │
│  └───────────────┘                                         │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    │ (scrape)
                                    ↓
┌─────────────────────────────────────────────────────────────┐
│                  Monitoring Namespace                       │
│  ┌──────────────────┐     ┌────────────────────┐          │
│  │  PrometheusRule  │────→│    Prometheus      │          │
│  │  (slo-latency)   │     │  (histogram_quantile)         │
│  └──────────────────┘     └────────────────────┘          │
│                                    │                        │
│                  expr: histogram_quantile(0.99, ...)       │
│                        > 0.5  # 500ms threshold            │
│                                    │                        │
│                                    ↓                        │
│                           ┌──────────────┐                 │
│                           │ Alert: FIRING│                 │
│                           │ HighLatencyP99                 │
│                           └──────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## Test Values Configuration

See: `values/uc03-slo-latency.yaml`

Key configurations:
```yaml
monitoring:
  prometheus:
    rules:
      slo:
        enabled: true
        latency:
          enabled: true
          p99Threshold: "500ms"  # Alert if P99 > 500ms
          evaluationInterval: "5m"
          severity: "warning"
```

## Test Steps

### Step 1: Install Chart

```bash
helm install test-monitoring-uc03 \
  ../../../../charts/common-monitoring \
  -f values/uc03-slo-latency.yaml \
  -n test-monitoring \
  --create-namespace \
  --wait
```

**Expected**: Chart installs successfully

### Step 2: Verify PrometheusRule Created

```bash
kubectl get prometheusrule -n test-monitoring
```

**Expected Output**:
```
NAME                     AGE
monitoring-slo-alerts    10s
```

### Step 3: Inspect SLO Rule

```bash
kubectl get prometheusrule monitoring-slo-alerts \
  -n test-monitoring -o yaml
```

**Expected**: Rule contains P99 latency alert:
```yaml
- alert: HighLatencyP99
  expr: |
    histogram_quantile(0.99,
      rate(http_request_duration_seconds_bucket[5m])
    ) > 0.5
  for: 5m
  labels:
    severity: warning
    slo: latency
  annotations:
    summary: "High P99 latency detected"
    description: "P99 latency is {{ $value }}s (threshold: 0.5s)"
```

### Step 4: Deploy Test Application

Create a simple Go application with two endpoints:

```go
// main.go
package main

import (
    "math/rand"
    "net/http"
    "time"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    httpDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "HTTP request duration in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"path", "method"},
    )
)

func init() {
    prometheus.MustRegister(httpDuration)
}

func fastHandler(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    
    // Fast response: 10ms ± 5ms
    delay := time.Duration(10 + rand.Intn(5)) * time.Millisecond
    time.Sleep(delay)
    
    duration := time.Since(start).Seconds()
    httpDuration.WithLabelValues("/fast", r.Method).Observe(duration)
    
    w.Write([]byte("OK"))
}

func slowHandler(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    
    // Slow response: 1000ms ± 200ms
    delay := time.Duration(1000 + rand.Intn(200)) * time.Millisecond
    time.Sleep(delay)
    
    duration := time.Since(start).Seconds()
    httpDuration.WithLabelValues("/slow", r.Method).Observe(duration)
    
    w.Write([]byte("Slow response"))
}

func main() {
    http.HandleFunc("/fast", fastHandler)
    http.HandleFunc("/slow", slowHandler)
    http.Handle("/metrics", promhttp.Handler())
    
    http.ListenAndServe(":8080", nil)
}
```

Deploy as Deployment + Service:

```bash
kubectl apply -f workloads/latency-test-app.yaml -n test-monitoring
```

### Step 5: Verify Application is Running

```bash
kubectl get pods -n test-monitoring | grep latency-test
kubectl get svc latency-test-app -n test-monitoring
```

**Expected**: Pod running, service created

### Step 6: Verify Metrics Endpoint

```bash
kubectl port-forward svc/latency-test-app 8080:8080 -n test-monitoring &
curl http://localhost:8080/metrics | grep http_request_duration
```

**Expected**: Prometheus histogram metrics visible

### Step 7: Generate Fast Traffic (Baseline)

```bash
# Generate 1000 requests to /fast endpoint
hey -n 1000 -c 10 -q 20 http://latency-test-app.test-monitoring:8080/fast
```

**Expected**: P99 latency ~15ms (well under threshold)

Wait 5 minutes and check Prometheus - alert should NOT fire.

### Step 8: Generate Slow Traffic (Trigger SLO Violation)

```bash
# Generate 1000 requests to /slow endpoint
hey -n 1000 -c 10 -q 20 http://latency-test-app.test-monitoring:8080/slow
```

**Expected**: P99 latency ~1200ms (exceeds 500ms threshold)

### Step 9: Wait for Alert to Fire

Wait 5-7 minutes for:
1. Prometheus to scrape metrics (30s interval)
2. Evaluate rule (1m interval)
3. Alert pending period (5m for duration)

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
```

Open: http://localhost:9090/alerts

**Expected**: `HighLatencyP99` alert in FIRING state

### Step 10: Query P99 Latency in Prometheus

```bash
# Query current P99 latency
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket[5m]))' | jq '.data.result[0].value'
```

**Expected Output** (after slow traffic):
```json
[
  1708515230,
  "1.2034"
]
```
(Value > 0.5 seconds)

### Step 11: Test Alert Recovery

Generate fast traffic again to bring latency down:

```bash
hey -n 2000 -c 10 -q 30 http://latency-test-app.test-monitoring:8080/fast
```

Wait 10 minutes for alert to resolve.

**Expected**: Alert transitions to RESOLVED state

### Step 12: Test Different Percentiles

Query other percentiles:

```promql
# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# P99.9 latency
histogram_quantile(0.999, rate(http_request_duration_seconds_bucket[5m]))

# P50 (median) latency
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
```

## Validation Criteria

### ✅ Pass Criteria

1. **PrometheusRule Created**: SLO latency rule exists
2. **Correct Expression**: Uses `histogram_quantile(0.99, ...)`
3. **Threshold Correct**: Alert expr checks `> 0.5` (500ms)
4. **Alert Fires**: Alert goes to FIRING after slow traffic
5. **Alert Resolves**: Alert resolves after fast traffic returns
6. **Correct Labels**: Alert has severity, slo labels
7. **Histogram Metrics**: App exports proper histogram buckets

### ❌ Fail Criteria

1. PrometheusRule not created
2. Alert uses wrong percentile (not P99)
3. Alert fires for fast traffic (false positive)
4. Alert doesn't fire for slow traffic (false negative)
5. Missing histogram buckets in metrics
6. Alert doesn't resolve when latency improves

## Troubleshooting

### Issue: No Histogram Metrics

**Symptoms**: Query returns no data

**Debug**:
```bash
# Check if app exports metrics
kubectl port-forward svc/latency-test-app 8080:8080 -n test-monitoring
curl http://localhost:8080/metrics | grep http_request_duration_seconds_bucket
```

**Fix**: Ensure app uses Prometheus histogram (not summary or gauge)

---

### Issue: Alert Fires Immediately

**Symptoms**: Alert fires with fast traffic

**Debug**:
```bash
# Check actual P99 value
curl 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket[5m]))' | jq '.'
```

**Possible Causes**:
- Threshold too low
- Not enough traffic data
- Incorrect histogram buckets

**Fix**: Adjust threshold or generate more baseline traffic

---

### Issue: Alert Doesn't Fire with Slow Traffic

**Symptoms**: Slow endpoint called but no alert

**Debug**:
```bash
# Check if metrics are scraped
kubectl logs -n monitoring prometheus-kube-prometheus-prometheus-0 | grep latency-test-app

# Check service monitor
kubectl get servicemonitor -n test-monitoring
```

**Fix**: Ensure ServiceMonitor targets correct service

---

### Issue: Histogram Buckets Incorrect

**Symptoms**: P99 always returns same value

**Debug**:
```bash
curl http://localhost:8080/metrics | grep http_request_duration_seconds_bucket
```

**Expected**: Multiple buckets from 0.005 to 10+ seconds

**Fix**: Use proper Prometheus histogram buckets:
```go
Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10}
```

## Real-World Scenarios

### Scenario 1: API Performance Degradation

**Context**: Production API's P99 latency suddenly increases

**Alert Flow**:
1. Database query slows down
2. API latency increases to 800ms P99
3. SLO alert fires (threshold: 500ms)
4. Team investigates - finds missing index
5. Index added, latency returns to 100ms
6. Alert auto-resolves

**Outcome**: SLO violation detected before customer complaints

### Scenario 2: Gradual Performance Decline

**Context**: Memory leak causes gradual slowdown over days

**Alert Flow**:
1. Day 1: P99 = 200ms (OK)
2. Day 3: P99 = 450ms (approaching SLO)
3. Day 5: P99 = 550ms (SLO violated, alert fires)
4. Team restarts service, investigates leak
5. Fix deployed, latency stable at 180ms
6. Alert resolves

**Outcome**: Issue caught before complete outage

### Scenario 3: Load Testing

**Context**: Team load tests new feature

**Alert Flow**:
1. Load test generates 10K req/s
2. Latency increases to 600ms P99
3. SLO alert fires (expected during test)
4. Team marks alert as maintenance window
5. Load test completes
6. Latency returns to normal
7. Alert resolves

**Outcome**: Expected alert, properly managed

## SLO Best Practices

### Define SLOs Based on User Experience

```yaml
# User-facing API
p99Threshold: "200ms"  # Strict
severity: "critical"

# Internal API
p99Threshold: "500ms"  # Relaxed
severity: "warning"

# Batch processing
p99Threshold: "10s"    # Very relaxed
severity: "info"
```

### Multi-Percentile Monitoring

```yaml
slo:
  latency:
    p50: "50ms"   # Median
    p95: "200ms"  # Good user experience
    p99: "500ms"  # Acceptable
    p99_9: "1s"   # Edge cases
```

### Error Budget Tracking

Calculate SLO compliance:

```promql
# 99.9% SLO = 99.9% of requests under threshold
sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m]))
/
sum(rate(http_request_duration_seconds_count[5m]))
> 0.999  # 99.9% compliance
```

## Performance Considerations

### Histogram Bucket Selection

**Principle**: Buckets should span expected latency range

```go
// For 10ms - 1s API
Buckets: []float64{.01, .025, .05, .1, .25, .5, 1}

// For 1ms - 100ms API
Buckets: []float64{.001, .005, .01, .025, .05, .1}

// For 100ms - 10s API
Buckets: []float64{.1, .25, .5, 1, 2.5, 5, 10}
```

### Cardinality Impact

**High cardinality** (many unique label combinations) = high memory

```yaml
# BAD - too many labels
http_duration_seconds_bucket{path="/api/user/123", method="GET"}

# GOOD - aggregated labels
http_duration_seconds_bucket{path="/api/user/:id", method="GET"}
```

### Query Performance

```promql
# SLOW - large time range
histogram_quantile(0.99, rate(http_duration_seconds_bucket[1h]))

# FAST - shorter time range
histogram_quantile(0.99, rate(http_duration_seconds_bucket[5m]))
```

## Integration with Alertmanager

### Route SLO Alerts by Severity

```yaml
route:
  routes:
  - match:
      slo: latency
      severity: critical
    receiver: pagerduty
    repeat_interval: 1h
  
  - match:
      slo: latency
      severity: warning
    receiver: slack
    repeat_interval: 4h
```

### Group SLO Alerts

```yaml
route:
  group_by: ['slo', 'service']
  group_wait: 10s
  group_interval: 5m
```

## Metrics Used

### http_request_duration_seconds_bucket

**Type**: Histogram  
**Labels**: `path`, `method`, `status`  
**Buckets**: Configurable (e.g., 0.005, 0.01, 0.025, ...)

**Example**:
```
http_request_duration_seconds_bucket{path="/api/users",method="GET",le="0.5"} 950
http_request_duration_seconds_bucket{path="/api/users",method="GET",le="1.0"} 990
http_request_duration_seconds_bucket{path="/api/users",method="GET",le="+Inf"} 1000
http_request_duration_seconds_count{path="/api/users",method="GET"} 1000
http_request_duration_seconds_sum{path="/api/users",method="GET"} 234.567
```

### Calculating Percentiles

```promql
# P99 latency
histogram_quantile(0.99,
  rate(http_request_duration_seconds_bucket[5m])
)

# P99 latency per path
histogram_quantile(0.99,
  sum by (path, le) (rate(http_request_duration_seconds_bucket[5m]))
)
```

## Test Cleanup

```bash
# Delete test app
kubectl delete -f workloads/latency-test-app.yaml -n test-monitoring

# Uninstall chart
helm uninstall test-monitoring-uc03 -n test-monitoring

# Delete namespace (optional)
kubectl delete namespace test-monitoring
```

## References

- [Prometheus Histograms](https://prometheus.io/docs/concepts/metric_types/#histogram)
- [Histogram Quantiles](https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile)
- [SLO Best Practices](https://sre.google/workbook/implementing-slos/)
- [Percentile Calculations](https://www.datadoghq.com/blog/engineering/computing-accurate-percentiles-with-ddsketch/)

## Test Execution

**Run automated test**:
```bash
cd test-cases
./run-uc03.sh
```

**Expected Duration**: 12-15 minutes (includes load testing and alert wait time)

**Exit Codes**:
- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Prerequisites not met
