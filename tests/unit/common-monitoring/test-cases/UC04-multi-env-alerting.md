# UC-MONITORING-04: Multi-Environment Alerting Configuration

## Overview

This Use Case validates the ability to configure different alerting thresholds and behaviors for multiple environments (production, staging, development) using the same `common-monitoring` chart. This pattern is essential for:

- **Production**: Strict thresholds, immediate notifications, critical severity
- **Staging**: Relaxed thresholds, delayed notifications, warning severity  
- **Development**: Very permissive thresholds, optional notifications, info severity

The same Helm chart can be deployed with different `values.yaml` files to achieve environment-specific monitoring policies.

## Test Objectives

1. **Environment Separation**: Deploy the same chart with different configurations
2. **Threshold Differentiation**: Verify production uses stricter thresholds than dev
3. **Severity Mapping**: Confirm critical alerts in prod, warnings in staging, info in dev
4. **Alert Routing**: Validate different Alertmanager routing per environment
5. **Resource Quotas**: Ensure monitoring resources scale with environment criticality

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Prometheus                              │
│  ┌──────────────────┬──────────────────┬──────────────────┐    │
│  │   Production     │     Staging      │   Development    │    │
│  │   Namespace      │     Namespace    │    Namespace     │    │
│  ├──────────────────┼──────────────────┼──────────────────┤    │
│  │ Pod Crash > 2    │ Pod Crash > 5    │ Pod Crash > 10   │    │
│  │ CPU > 80%        │ CPU > 90%        │ CPU > 95%        │    │
│  │ Memory > 85%     │ Memory > 92%     │ Memory > 98%     │    │
│  │ Severity: critical│ Severity: warning│ Severity: info   │    │
│  └──────────────────┴──────────────────┴──────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Alertmanager                              │
│  ┌──────────────────┬──────────────────┬──────────────────┐    │
│  │   Production     │     Staging      │   Development    │    │
│  ├──────────────────┼──────────────────┼──────────────────┤    │
│  │ Route: pagerduty │ Route: slack     │ Route: /dev/null │    │
│  │ Delay: 0s        │ Delay: 5m        │ Delay: 30m       │    │
│  │ Repeat: 4h       │ Repeat: 12h      │ Repeat: never    │    │
│  └──────────────────┴──────────────────┴──────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (EKS 1.23+)
- Prometheus Operator installed
- Alertmanager (optional, for routing tests)
- `kubectl` and `helm` CLI tools
- Multiple namespaces: `production`, `staging`, `development`

## Test Environment

### Production Values (`uc04-prod-alerting.yaml`)

```yaml
# Strict thresholds for production
monitoring:
  enabled: true
  
  podCrashLooping:
    enabled: true
    threshold: 2              # Alert after 2 restarts
    evaluationInterval: "3m"  # Check every 3 minutes
    severity: "critical"
    annotations:
      runbook_url: "https://runbooks.example.com/pod-crash"
      priority: "P1"
      
  resourceUsage:
    enabled: true
    cpu:
      threshold: 80           # 80% CPU utilization
      severity: "critical"
    memory:
      threshold: 85           # 85% memory utilization
      severity: "critical"
      
  slo:
    latency:
      enabled: true
      p99Threshold: "300ms"   # Strict latency SLO
      severity: "critical"
    errorRate:
      enabled: true
      threshold: "0.01"       # 1% error rate
      severity: "critical"

alerting:
  route:
    receiver: "pagerduty-prod"
    groupWait: "10s"
    groupInterval: "5m"
    repeatInterval: "4h"
  
  inhibition:
    enabled: true             # Inhibit lower severity alerts
```

### Staging Values (`uc04-staging-alerting.yaml`)

```yaml
# Relaxed thresholds for staging
monitoring:
  enabled: true
  
  podCrashLooping:
    enabled: true
    threshold: 5              # Alert after 5 restarts
    evaluationInterval: "5m"  # Check every 5 minutes
    severity: "warning"
    
  resourceUsage:
    enabled: true
    cpu:
      threshold: 90           # 90% CPU utilization
      severity: "warning"
    memory:
      threshold: 92           # 92% memory utilization
      severity: "warning"
      
  slo:
    latency:
      enabled: true
      p99Threshold: "1s"      # More relaxed latency
      severity: "warning"
    errorRate:
      enabled: true
      threshold: "0.05"       # 5% error rate
      severity: "warning"

alerting:
  route:
    receiver: "slack-staging"
    groupWait: "30s"
    groupInterval: "10m"
    repeatInterval: "12h"
```

### Development Values (`uc04-dev-alerting.yaml`)

```yaml
# Very permissive thresholds for development
monitoring:
  enabled: true
  
  podCrashLooping:
    enabled: true
    threshold: 10             # Alert after 10 restarts
    evaluationInterval: "10m" # Check every 10 minutes
    severity: "info"
    
  resourceUsage:
    enabled: true
    cpu:
      threshold: 95           # 95% CPU utilization
      severity: "info"
    memory:
      threshold: 98           # 98% memory utilization
      severity: "info"
      
  slo:
    latency:
      enabled: false          # Disable latency SLO
    errorRate:
      enabled: false          # Disable error rate SLO

alerting:
  route:
    receiver: "null"          # No notifications
    groupWait: "5m"
    groupInterval: "30m"
    repeatInterval: "0"       # Never repeat
```

## Test Steps

### Step 1: Create Namespaces

```bash
kubectl create namespace production
kubectl create namespace staging
kubectl create namespace development
```

### Step 2: Deploy to Production

```bash
helm install prod-monitoring charts/common-monitoring \
  -f tests/unit/common-monitoring/values/uc04-prod-alerting.yaml \
  -n production \
  --wait
```

### Step 3: Deploy to Staging

```bash
helm install staging-monitoring charts/common-monitoring \
  -f tests/unit/common-monitoring/values/uc04-staging-alerting.yaml \
  -n staging \
  --wait
```

### Step 4: Deploy to Development

```bash
helm install dev-monitoring charts/common-monitoring \
  -f tests/unit/common-monitoring/values/uc04-dev-alerting.yaml \
  -n development \
  --wait
```

### Step 5: Verify PrometheusRules

```bash
# Production - should have critical severity
kubectl get prometheusrule -n production -o yaml | grep severity

# Staging - should have warning severity
kubectl get prometheusrule -n staging -o yaml | grep severity

# Development - should have info severity
kubectl get prometheusrule -n development -o yaml | grep severity
```

### Step 6: Compare Thresholds

```bash
# Extract pod crash thresholds
echo "Production:"
kubectl get prometheusrule -n production -o yaml | grep -A 5 "kube_pod_container_status_restarts_total"

echo "Staging:"
kubectl get prometheusrule -n staging -o yaml | grep -A 5 "kube_pod_container_status_restarts_total"

echo "Development:"
kubectl get prometheusrule -n development -o yaml | grep -A 5 "kube_pod_container_status_restarts_total"
```

### Step 7: Test Alert Routing (with Alertmanager)

```bash
# Port-forward to Alertmanager
kubectl port-forward -n monitoring svc/alertmanager-kube-prometheus-alertmanager 9093:9093

# Query routing configuration
curl -s http://localhost:9093/api/v2/status | jq '.config.route'
```

## Validation Criteria

### 1. Threshold Hierarchy

```bash
# Verify production has strictest thresholds
PROD_THRESHOLD=$(kubectl get prometheusrule -n production -o yaml | grep -oP 'threshold.*\K[0-9]+' | head -1)
STAGING_THRESHOLD=$(kubectl get prometheusrule -n staging -o yaml | grep -oP 'threshold.*\K[0-9]+' | head -1)
DEV_THRESHOLD=$(kubectl get prometheusrule -n development -o yaml | grep -oP 'threshold.*\K[0-9]+' | head -1)

if [ "$PROD_THRESHOLD" -lt "$STAGING_THRESHOLD" ] && [ "$STAGING_THRESHOLD" -lt "$DEV_THRESHOLD" ]; then
  echo "✅ Threshold hierarchy correct"
else
  echo "❌ Threshold hierarchy incorrect"
fi
```

### 2. Severity Levels

```bash
# Production should have "critical" severity
if kubectl get prometheusrule -n production -o yaml | grep -q 'severity.*critical'; then
  echo "✅ Production severity: critical"
else
  echo "❌ Production severity not critical"
fi

# Staging should have "warning" severity
if kubectl get prometheusrule -n staging -o yaml | grep -q 'severity.*warning'; then
  echo "✅ Staging severity: warning"
else
  echo "❌ Staging severity not warning"
fi

# Development should have "info" severity
if kubectl get prometheusrule -n development -o yaml | grep -q 'severity.*info'; then
  echo "✅ Development severity: info"
else
  echo "❌ Development severity not info"
fi
```

### 3. Evaluation Intervals

```bash
# Production should evaluate more frequently (3m)
if kubectl get prometheusrule -n production -o yaml | grep -q 'for: 3m\|for: "3m"'; then
  echo "✅ Production evaluation: 3m"
fi

# Staging should evaluate less frequently (5m)
if kubectl get prometheusrule -n staging -o yaml | grep -q 'for: 5m\|for: "5m"'; then
  echo "✅ Staging evaluation: 5m"
fi

# Development should evaluate least frequently (10m)
if kubectl get prometheusrule -n development -o yaml | grep -q 'for: 10m\|for: "10m"'; then
  echo "✅ Development evaluation: 10m"
fi
```

## Real-World Scenarios

### Scenario 1: Production Incident

**Context**: A production pod starts crashing due to OOM

```bash
# Production alert fires after 2 restarts (6 minutes)
# Severity: critical
# Routes to: PagerDuty
# Engineer on-call is paged immediately
```

**Expected Behavior**:
- Alert fires at 6:02 AM (2 restarts × 3m evaluation)
- PagerDuty notification sent immediately
- Incident created with P1 priority
- Runbook URL included in alert

### Scenario 2: Staging Testing

**Context**: QA team runs stress tests in staging

```bash
# Staging alert fires after 5 restarts (25 minutes)
# Severity: warning
# Routes to: Slack channel #staging-alerts
# Team can investigate during business hours
```

**Expected Behavior**:
- Alert fires at 2:25 PM (5 restarts × 5m evaluation)
- Slack notification posted to #staging-alerts
- No pages or urgent notifications
- Team triages during regular hours

### Scenario 3: Development Experimentation

**Context**: Developer testing new feature with intentional crashes

```bash
# Development alert fires after 10 restarts (100 minutes)
# Severity: info
# Routes to: /dev/null (no notifications)
# Developer can check Prometheus UI manually if needed
```

**Expected Behavior**:
- Alert fires at 4:40 PM (10 restarts × 10m evaluation)
- No notifications sent
- Alert visible in Prometheus UI only
- Developer not interrupted during development

## Advanced Configuration

### 1. Time-Based Routing

```yaml
# Alertmanager config for business hours vs. off-hours
route:
  routes:
    - match:
        severity: critical
        environment: production
      receiver: pagerduty-prod
      continue: true
      
    - match:
        severity: critical
        environment: production
      receiver: slack-prod
      time_intervals:
        - business_hours
```

### 2. Inhibition Rules

```yaml
# Inhibit warning alerts when critical alert is firing
inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal:
      - namespace
      - pod
```

### 3. Grouping Strategy

```yaml
# Production: Group by pod (fine-grained)
route:
  group_by: ['pod', 'container']
  
# Development: Group by namespace (coarse-grained)
route:
  group_by: ['namespace']
```

## Troubleshooting

### Issue: Alerts Not Routing Correctly

**Symptoms**: Production alerts going to wrong receiver

**Solution**:
```bash
# Check Alertmanager configuration
kubectl get secret -n monitoring alertmanager-kube-prometheus-alertmanager -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d

# Verify route matching
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | {labels, receiver}'
```

### Issue: Inconsistent Thresholds

**Symptoms**: Different pods in same namespace have different thresholds

**Solution**:
```bash
# List all PrometheusRules in namespace
kubectl get prometheusrule -n production -o yaml | grep -A 20 "spec:"

# Consolidate into single PrometheusRule
helm upgrade prod-monitoring charts/common-monitoring \
  -f values/uc04-prod-alerting.yaml \
  -n production \
  --set monitoring.consolidateRules=true
```

### Issue: Alert Fatigue

**Symptoms**: Too many development alerts

**Solution**:
```yaml
# Disable non-critical alerts in development
monitoring:
  podCrashLooping:
    enabled: false  # Disable for dev
  resourceUsage:
    enabled: false  # Disable for dev
  slo:
    enabled: false  # Disable for dev
```

## Integration with CI/CD

### GitOps with ArgoCD

```yaml
# applications/prod-monitoring.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-monitoring
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/example/helm-charts
    path: charts/common-monitoring
    targetRevision: HEAD
    helm:
      valueFiles:
        - ../../environments/production/monitoring-values.yaml
  destination:
    namespace: production
    server: https://kubernetes.default.svc
```

### Terraform Deployment

```hcl
# Production monitoring
resource "helm_release" "prod_monitoring" {
  name       = "prod-monitoring"
  namespace  = "production"
  chart      = "./charts/common-monitoring"
  
  values = [
    file("${path.module}/values/uc04-prod-alerting.yaml")
  ]
  
  set {
    name  = "monitoring.podCrashLooping.threshold"
    value = var.prod_crash_threshold  # From variable
  }
}

# Staging monitoring
resource "helm_release" "staging_monitoring" {
  name       = "staging-monitoring"
  namespace  = "staging"
  chart      = "./charts/common-monitoring"
  
  values = [
    file("${path.module}/values/uc04-staging-alerting.yaml")
  ]
}
```

## Performance Considerations

### 1. Rule Evaluation Load

```yaml
# Production: Frequent evaluation (high load)
monitoring:
  evaluationInterval: "3m"  # Every 3 minutes
  
# Development: Infrequent evaluation (low load)
monitoring:
  evaluationInterval: "10m"  # Every 10 minutes
```

**Impact**: Development environment consumes 70% less Prometheus resources.

### 2. Alert Volume

```bash
# Production: 10-20 alerts/day (strict thresholds)
# Staging: 3-5 alerts/day (relaxed thresholds)
# Development: 0-1 alerts/day (very permissive)
```

### 3. Prometheus Query Load

```yaml
# Optimize with recording rules for production
monitoring:
  recordingRules:
    enabled: true  # Pre-compute expensive queries
    interval: "30s"
```

## Best Practices

1. **Start Strict**: Begin with production thresholds, then relax for lower environments
2. **Document Differences**: Maintain a comparison matrix of threshold differences
3. **Test in Staging First**: Validate alerting changes in staging before production
4. **Use GitOps**: Store environment-specific values in version control
5. **Monitor Alert Volume**: Track alert rates per environment to avoid fatigue
6. **Regular Reviews**: Quarterly review of thresholds based on actual incidents
7. **Automate Testing**: Include alerting tests in CI/CD pipelines

## Success Metrics

- **Production Alert Precision**: >90% of critical alerts are actionable
- **Staging Alert Volume**: <10 alerts/day to avoid noise
- **Development Alert Silence**: <1 alert/week (intentionally quiet)
- **Time to Alert**: Production <5 minutes, Staging <15 minutes, Dev <30 minutes
- **False Positive Rate**: <5% across all environments

## Related Use Cases

- **UC-MONITORING-01**: Pod Crash Alerts (foundational alerting)
- **UC-MONITORING-03**: SLO Monitoring (latency thresholds)
- **UC-KYVERNO-04**: Multi-Environment Policies (similar environment pattern)

## References

- [Prometheus Best Practices - Alerting](https://prometheus.io/docs/practices/alerting/)
- [Alertmanager Routing Tree](https://prometheus.io/docs/alerting/latest/configuration/#route)
- [SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
