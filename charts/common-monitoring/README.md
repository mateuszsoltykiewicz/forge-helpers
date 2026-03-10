# Forge Common Library - Monitoring

Library chart for Prometheus and Grafana monitoring resources.

## Overview

This Helm library provides reusable templates for **Prometheus alerting rules** and **Grafana dashboards**, enabling comprehensive observability for Kubernetes applications.

**Features**:
- **PrometheusRule**: Alerting rules for common scenarios
- **Pre-configured Alerts**: Availability, resources, SLO-based
- **Grafana Dashboards**: Application and infrastructure metrics
- **Golden Signals**: Latency, traffic, errors, saturation
- **Multi-severity**: Info, warning, critical alerts
- **Automatic Discovery**: Grafana sidecar integration

**Integrations**:
- **common-forge**: Naming conventions, labels
- **Prometheus Operator**: ServiceMonitor, PrometheusRule CRDs
- **Grafana**: Dashboard provisioning via ConfigMaps

## Installation

Add as a dependency in your `Chart.yaml`:

```yaml
dependencies:
  - name: common-monitoring
    version: ~0.1.0
    repository: file://../common-monitoring
```

## Usage Examples

### Example 1: Pre-configured Availability Alerts

Enable availability alerts for your application:

```yaml
# values.yaml
monitoring:
  alerts:
    availability:
      enabled: true
      
      # Application down threshold
      downFor: "2m"
      
      # Error rate threshold (5%)
      errorRateThreshold: 0.05
      errorFor: "5m"
      errorSeverity: "warning"
      
      # Latency threshold (1s for p99)
      latencyThreshold: 1
      latencyFor: "5m"
      latencySeverity: "warning"
      
      # Success rate threshold (95%)
      successRateThreshold: 0.95
      successFor: "5m"
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.prometheusrule.availability" . }}
```

This creates alerts for:
- **ApplicationDown**: No metrics received for 2m
- **HighErrorRate**: >5% error rate for 5m
- **HighResponseTime**: P99 latency >1s for 5m
- **LowSuccessRate**: <95% success rate for 5m

### Example 2: Resource Utilization Alerts

Monitor CPU, memory, and pod health:

```yaml
# values.yaml
monitoring:
  alerts:
    resources:
      enabled: true
      
      # CPU threshold (80%)
      cpuThreshold: 0.8
      cpuFor: "5m"
      cpuSeverity: "warning"
      
      # Memory threshold (80%)
      memoryThreshold: 0.8
      memoryFor: "5m"
      memorySeverity: "warning"
      
      # Pod restart rate
      restartRateThreshold: 0.01  # ~0.6/min
      restartFor: "5m"
      
      # Pod not ready
      notReadyFor: "5m"
      
      # Replica mismatch
      replicaMismatchFor: "10m"
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.prometheusrule.resources" . }}
```

This creates alerts for:
- **HighCPUUsage**: Pod CPU >80% for 5m
- **HighMemoryUsage**: Pod memory >80% for 5m
- **PodRestartingFrequently**: Restart rate >0.6/min
- **PodNotReady**: Pod not ready for 5m
- **DeploymentReplicaMismatch**: Desired ≠ available replicas for 10m

### Example 3: SLO-based Alerts

Alert when error budget is burning:

```yaml
# values.yaml
monitoring:
  alerts:
    slo:
      enabled: true
      
      # 99.9% availability SLO
      availabilityTarget: 0.999
      
      # P99 latency SLO (1s)
      latencyTarget: 1
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.prometheusrule.slo" . }}
```

This creates alerts for:
- **SLOAvailabilityBudgetBurn**: Error budget burning faster than sustainable
- **SLOLatencyBudgetBurn**: P99 latency exceeding target

### Example 4: Custom PrometheusRule

Create custom alerting rules:

```yaml
# values.yaml
monitoring:
  prometheusrule:
    enabled: true
    name: "custom-alerts"
    namespace: "monitoring"
    
    groups:
      - name: custom-app-alerts
        interval: 30s
        rules:
          # Database connection pool exhaustion
          - alert: DatabasePoolExhausted
            expr: |
              hikaricp_connections_active{application="{{ include "forge.fullname" . }}"}
              /
              hikaricp_connections_max{application="{{ include "forge.fullname" . }}"}
              > 0.9
            for: 2m
            labels:
              severity: critical
              category: database
            annotations:
              summary: "Database connection pool nearly exhausted"
              description: "Connection pool usage is {{ printf \"%.2f\" $value | mul 100 }}%"
              runbook_url: "https://runbooks.example.com/DatabasePoolExhausted"
          
          # Queue depth too high
          - alert: HighQueueDepth
            expr: |
              rabbitmq_queue_messages{queue="{{ include "forge.fullname" . }}"} > 10000
            for: 5m
            labels:
              severity: warning
              category: messaging
            annotations:
              summary: "Message queue depth is high"
              description: "Queue has {{ $value }} messages waiting"
              runbook_url: "https://runbooks.example.com/HighQueueDepth"
          
          # Cache hit ratio too low
          - alert: LowCacheHitRatio
            expr: |
              (
                rate(cache_hits_total{application="{{ include "forge.fullname" . }}"}[5m])
                /
                (rate(cache_hits_total{application="{{ include "forge.fullname" . }}"}[5m]) + rate(cache_misses_total{application="{{ include "forge.fullname" . }}"}[5m]))
              ) < 0.8
            for: 10m
            labels:
              severity: info
              category: performance
            annotations:
              summary: "Cache hit ratio is below 80%"
              description: "Current cache hit ratio is {{ printf \"%.2f\" $value | mul 100 }}%"
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.prometheusrule" . }}
```

### Example 5: Application Metrics Dashboard

Enable pre-configured Grafana dashboard for golden signals:

```yaml
# values.yaml
monitoring:
  grafana:
    dashboards:
      application:
        enabled: true
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.grafana.dashboard.application" . }}
```

This creates a dashboard with:
- **Availability**: Current up/down status
- **Request Rate**: Requests per second
- **Error Rate**: Percentage of 5xx responses
- **P99 Latency**: 99th percentile response time
- **Request Rate by Status**: Breakdown by HTTP status
- **Response Time Percentiles**: P50, P90, P99 over time

### Example 6: Infrastructure Dashboard

Monitor Kubernetes resource utilization:

```yaml
# values.yaml
monitoring:
  grafana:
    dashboards:
      infrastructure:
        enabled: true
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.grafana.dashboard.infrastructure" . }}
```

This creates a dashboard with:
- **CPU Usage by Pod**: Per-pod CPU utilization
- **Memory Usage by Pod**: Per-pod memory consumption
- **Network I/O by Pod**: RX/TX bytes per second
- **Pod Restarts**: Restart count over time

### Example 7: Custom Grafana Dashboard

Provide your own dashboard JSON:

```yaml
# values.yaml
monitoring:
  grafana:
    dashboard:
      enabled: true
      name: "business-metrics"
      namespace: "monitoring"
      
      json: |
        {
          "title": "Business Metrics",
          "panels": [
            {
              "id": 1,
              "title": "Revenue per Minute",
              "type": "graph",
              "targets": [
                {
                  "expr": "sum(rate(revenue_total[1m]))"
                }
              ]
            }
          ]
        }
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.grafana.dashboard" . }}
```

### Example 8: Complete Production Monitoring Setup

Full observability stack:

```yaml
# values.yaml
monitoring:
  # PrometheusRule namespace
  prometheusrule:
    namespace: "monitoring"
    prometheus: "kube-prometheus-stack"
    role: "alert-rules"
  
  # Enable all pre-configured alerts
  alerts:
    # Availability monitoring
    availability:
      enabled: true
      downFor: "1m"
      errorRateThreshold: 0.01  # 1% (strict)
      errorFor: "3m"
      errorSeverity: "critical"
      latencyThreshold: 0.5  # 500ms (strict)
      latencyFor: "5m"
      latencySeverity: "warning"
      successRateThreshold: 0.99  # 99% (strict)
      successFor: "5m"
    
    # Resource monitoring
    resources:
      enabled: true
      cpuThreshold: 0.7  # 70% (early warning)
      cpuFor: "5m"
      cpuSeverity: "warning"
      memoryThreshold: 0.7  # 70% (early warning)
      memoryFor: "5m"
      memorySeverity: "warning"
      restartRateThreshold: 0.005  # ~0.3/min
      restartFor: "5m"
      notReadyFor: "2m"
      replicaMismatchFor: "5m"
    
    # SLO monitoring
    slo:
      enabled: true
      availabilityTarget: 0.999  # 99.9% uptime
      latencyTarget: 0.5  # 500ms p99
  
  # Enable all dashboards
  grafana:
    dashboard:
      namespace: "monitoring"
    
    dashboards:
      application:
        enabled: true
      
      infrastructure:
        enabled: true
```

In your templates:

```yaml
# templates/monitoring.yaml
{{- include "monitoring.prometheusrule.availability" . }}
{{- include "monitoring.prometheusrule.resources" . }}
{{- include "monitoring.prometheusrule.slo" . }}
{{- include "monitoring.grafana.dashboard.application" . }}
{{- include "monitoring.grafana.dashboard.infrastructure" . }}
```

## Templates Reference

### PrometheusRule Templates

**Custom PrometheusRule**:
```yaml
{{- include "monitoring.prometheusrule" . }}
```

**Pre-configured Availability Alerts**:
```yaml
{{- include "monitoring.prometheusrule.availability" . }}
```

**Pre-configured Resource Alerts**:
```yaml
{{- include "monitoring.prometheusrule.resources" . }}
```

**Pre-configured SLO Alerts**:
```yaml
{{- include "monitoring.prometheusrule.slo" . }}
```

### Grafana Dashboard Templates

**Custom Dashboard**:
```yaml
{{- include "monitoring.grafana.dashboard" . }}
```

**Application Metrics Dashboard**:
```yaml
{{- include "monitoring.grafana.dashboard.application" . }}
```

**Infrastructure Metrics Dashboard**:
```yaml
{{- include "monitoring.grafana.dashboard.infrastructure" . }}
```

## Alert Severity Levels

- **info**: Informational, no immediate action required
- **warning**: Degraded performance, investigate soon
- **critical**: Service impact, immediate action required

## Alert Categories

- **availability**: Application uptime and health
- **resources**: CPU, memory, disk, network
- **slo**: Service Level Objective compliance
- **database**: Database connections, queries
- **messaging**: Queue depth, processing rate
- **performance**: Cache hit ratio, response time

## Metric Requirements

### Availability Alerts

Requires the following Prometheus metrics:
- `up{job="<app-name>"}` - Application availability
- `http_requests_total{status="..."}` - Request count by status
- `http_request_duration_seconds_bucket` - Request latency histogram

### Resource Alerts

Requires the following Prometheus metrics (from cAdvisor):
- `container_cpu_usage_seconds_total` - CPU usage
- `container_spec_cpu_quota` / `container_spec_cpu_period` - CPU limits
- `container_memory_working_set_bytes` - Memory usage
- `container_spec_memory_limit_bytes` - Memory limits
- `kube_pod_container_status_restarts_total` - Restart count
- `kube_pod_status_ready` - Pod readiness
- `kube_deployment_spec_replicas` / `kube_deployment_status_replicas_available` - Replica count

### SLO Alerts

Same as availability alerts, calculated over 1-hour windows.

## Grafana Dashboard Discovery

Grafana dashboards are automatically discovered when:
1. Dashboard is a ConfigMap in the monitored namespace
2. ConfigMap has label `grafana_dashboard: "1"`
3. Grafana sidecar is enabled in your Grafana deployment

Example Grafana Helm values:

```yaml
# Grafana chart values
sidecar:
  dashboards:
    enabled: true
    label: grafana_dashboard
    searchNamespace: ALL
```

## Configuration

See [values.yaml](values.yaml) for full configuration options.

## Best Practices

### Alert Thresholds

**Development**:
- CPU: 90% (loose)
- Memory: 90% (loose)
- Error rate: 10% (loose)
- Latency: 2s (loose)

**Production**:
- CPU: 70% (tight, early warning)
- Memory: 70% (tight, early warning)
- Error rate: 1% (tight)
- Latency: 500ms (tight)

### Alert Duration

- **Transient issues**: 5m (avoid flapping)
- **Critical issues**: 1-2m (quick response)
- **Capacity planning**: 10-15m (sustained trends)

### Runbook URLs

Always include runbook URLs in alert annotations:

```yaml
annotations:
  runbook_url: "https://runbooks.example.com/AlertName"
```

Runbooks should include:
- Alert description and impact
- Root cause investigation steps
- Remediation procedures
- Escalation contacts

### Dashboard Organization

- **Application dashboards**: Per-service metrics (golden signals)
- **Infrastructure dashboards**: Kubernetes resources (CPU, memory, network)
- **Business dashboards**: Business KPIs (revenue, users, conversions)

## Requirements

- **Helm**: 3.0+
- **Prometheus Operator**: 0.60+ (for PrometheusRule)
- **Grafana**: 9.0+ (tested with 10.2.0)
- **Kubernetes**: 1.23-1.29

## License

Part of the Moai Forge platform.
