# common-monitoring Tests

This directory contains comprehensive tests for the `common-monitoring` Helm chart, which provides Prometheus-based monitoring, alerting, and observability features.

## Overview

The `common-monitoring` chart provides:
- **Prometheus Rules**: Custom alerting rules for pod crashes, resource usage, SLOs
- **Grafana Dashboards**: Pre-configured dashboards for application metrics
- **ServiceMonitors**: Automatic metrics scraping configuration
- **Multi-Environment Support**: Different alerting thresholds per environment

## Test Structure

```
tests/unit/common-monitoring/
├── README.md                        # This file
├── values/                          # Test configurations
│   ├── uc01-pod-crash-alerts.yaml   # PrometheusRule for crash detection
│   ├── uc02-grafana-dashboard.yaml  # Dashboard with embedded JSON
│   ├── uc03-slo-latency.yaml        # P99 latency SLO configuration
│   ├── uc04-prod-alerting.yaml      # Production environment (strict)
│   └── uc04-dev-alerting.yaml       # Development environment (permissive)
├── workloads/                       # Test applications
│   ├── crashloop-pod.yaml           # Pod that crashes intentionally
│   └── latency-test-app.yaml        # App with Prometheus metrics
└── test-cases/                      # Test scripts
    ├── run-all.sh                   # Run all tests sequentially
    ├── run-uc01.sh                  # Pod crash alerts
    ├── run-uc02.sh                  # Grafana dashboard
    ├── run-uc03.sh                  # SLO latency monitoring
    ├── run-uc04.sh                  # Multi-environment alerting
    ├── UC01-pod-crash-alerts.md     # Documentation
    ├── UC02-grafana-dashboard.md    # Documentation
    ├── UC03-slo-latency.md          # Documentation
    └── UC04-multi-env-alerting.md   # Documentation
```

## Prerequisites

### Required
- Kubernetes cluster (EKS 1.23+)
- `kubectl` CLI tool
- `helm` CLI tool (v3.0+)
- Prometheus Operator with CRDs installed:
  - `prometheusrules.monitoring.coreos.com`
  - `servicemonitors.monitoring.coreos.com`
  - `prometheuses.monitoring.coreos.com`

### Optional
- `hey` tool for load testing (install: `brew install hey`)
- Grafana instance for dashboard verification
- Alertmanager for alert routing tests

### Installing Prometheus Operator

```bash
# Add Prometheus Operator Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus Operator
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --wait
```

## Use Cases

### UC01: Pod Crash Alerts

**Purpose**: Validate PrometheusRule creation for detecting crashlooping pods.

**What it tests**:
- PrometheusRule resource creation
- Alert rule expression with `kube_pod_container_status_restarts_total`
- Threshold configuration (3 restarts)
- Alert severity and annotations
- Crashloop pod deployment and detection

**Run**:
```bash
cd test-cases
./run-uc01.sh
```

**Expected outcome**: Alert fires when pod restarts 3+ times.

---

### UC02: Grafana Dashboard

**Purpose**: Validate Grafana dashboard provisioning via ConfigMap.

**What it tests**:
- ConfigMap creation with dashboard JSON
- `grafana_dashboard: "1"` label for sidecar discovery
- Dashboard JSON structure validation
- Multi-panel dashboard configuration
- Grafana accessibility check

**Run**:
```bash
cd test-cases
./run-uc02.sh
```

**Expected outcome**: Dashboard appears in Grafana UI under "Test" folder.

---

### UC03: SLO Latency Monitoring

**Purpose**: Validate P99 latency SLO monitoring with histogram metrics.

**What it tests**:
- PrometheusRule with `histogram_quantile()` function
- P99 latency threshold (500ms)
- ServiceMonitor for metrics scraping
- Test application with Prometheus metrics endpoint
- Load generation and alert firing

**Run**:
```bash
cd test-cases
./run-uc03.sh
```

**Expected outcome**: Alert fires when P99 latency > 500ms.

---

### UC04: Multi-Environment Alerting

**Purpose**: Validate environment-specific alerting configurations.

**What it tests**:
- Production: Strict thresholds (2 restarts, 80% CPU, critical severity)
- Development: Permissive thresholds (10 restarts, 95% CPU, info severity)
- Threshold hierarchy (prod < staging < dev)
- Severity levels (critical, warning, info)
- Evaluation interval differences (3m, 5m, 10m)

**Run**:
```bash
cd test-cases
./run-uc04.sh
```

**Expected outcome**: Same chart deployed with different alert behaviors per environment.

---

## Running All Tests

Execute all Use Cases sequentially:

```bash
cd test-cases
./run-all.sh
```

Output format:
```
[1/4] Running UC01: Pod Crash Alerts
✅ UC01 PASSED
---
[2/4] Running UC02: Grafana Dashboard
✅ UC02 PASSED
---
[3/4] Running UC03: SLO Latency
✅ UC03 PASSED
---
[4/4] Running UC04: Multi-Environment Alerting
✅ UC04 PASSED
---
🎉 All common-monitoring tests passed!
```

## Test Script Features

Each test script (`run-uc*.sh`) includes:

1. **Prerequisites Check**: Validates `kubectl`, `helm`, Prometheus Operator CRDs
2. **Automated Setup**: Creates namespaces, installs charts, deploys workloads
3. **Validation Tests**: 7-10 individual test cases per UC
4. **Color Output**: 
   - 🔵 Blue: Info messages
   - 🟢 Green: Passed tests
   - 🔴 Red: Failed tests
   - 🟡 Yellow: Warnings
5. **Cleanup Trap**: Automatic cleanup on exit (Ctrl+C safe)
6. **Summary Report**: Pass/fail counts and next steps

## Troubleshooting

### Issue: PrometheusRule CRD not found

```bash
# Check if Prometheus Operator is installed
kubectl get crd prometheusrules.monitoring.coreos.com

# If not found, install Prometheus Operator (see Prerequisites)
```

### Issue: Grafana dashboard not appearing

```bash
# Check ConfigMap has correct label
kubectl get configmap -n test-monitoring -l grafana_dashboard=1

# Check Grafana sidecar logs
kubectl logs -n monitoring deployment/prometheus-grafana -c grafana-sc-dashboard
```

### Issue: Alerts not firing

```bash
# Check PrometheusRule status
kubectl describe prometheusrule -n test-monitoring

# Query Prometheus directly
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/rules

# Check Prometheus scrape targets
# Open http://localhost:9090/targets
```

### Issue: Metrics not being scraped

```bash
# Verify ServiceMonitor created
kubectl get servicemonitor -n test-monitoring

# Check Prometheus Operator logs
kubectl logs -n monitoring deployment/prometheus-operator

# Test metrics endpoint manually
POD=$(kubectl get pod -n test-monitoring -l app=latency-test -o name | head -1)
kubectl exec -n test-monitoring $POD -- wget -qO- localhost:9090/metrics
```

## Integration with CI/CD

### GitHub Actions

```yaml
name: Monitoring Tests
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup K8s
        uses: helm/kind-action@v1
      - name: Install Prometheus Operator
        run: |
          helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
          helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace --wait
      - name: Run Tests
        run: |
          cd tests/unit/common-monitoring/test-cases
          ./run-all.sh
```

### Jenkins Pipeline

```groovy
pipeline {
  agent any
  stages {
    stage('Monitoring Tests') {
      steps {
        sh '''
          kubectl config use-context test-cluster
          cd tests/unit/common-monitoring/test-cases
          ./run-all.sh
        '''
      }
    }
  }
}
```

## Real-World Usage

### Production Deployment

```bash
# Deploy with production values
helm install prod-monitoring charts/common-monitoring \
  -f tests/unit/common-monitoring/values/uc04-prod-alerting.yaml \
  -n production \
  --set alerting.route.receiver=pagerduty \
  --wait
```

### Staging Deployment

```bash
# Deploy with relaxed thresholds
helm install staging-monitoring charts/common-monitoring \
  -f tests/unit/common-monitoring/values/uc04-staging-alerting.yaml \
  -n staging \
  --set alerting.route.receiver=slack \
  --wait
```

### Custom Dashboard

```bash
# Deploy with custom Grafana dashboard
helm install app-monitoring charts/common-monitoring \
  -f tests/unit/common-monitoring/values/uc02-grafana-dashboard.yaml \
  -n app-namespace \
  --set grafana.dashboards.custom.enabled=true \
  --wait
```

## Performance Benchmarks

| Use Case | Setup Time | Test Duration | Cleanup Time | Total Time |
|----------|------------|---------------|--------------|------------|
| UC01     | ~30s       | ~60s          | ~10s         | ~100s      |
| UC02     | ~30s       | ~40s          | ~10s         | ~80s       |
| UC03     | ~40s       | ~90s          | ~10s         | ~140s      |
| UC04     | ~60s       | ~80s          | ~15s         | ~155s      |
| **Total**| ~160s      | ~270s         | ~45s         | **~475s**  |

## Chart Coverage

This test suite covers:

✅ **PrometheusRule Creation**: Pod crashes, resource usage, SLOs  
✅ **Grafana Dashboard Provisioning**: ConfigMap-based dashboards  
✅ **ServiceMonitor Configuration**: Automatic metrics scraping  
✅ **Multi-Environment Support**: Prod/staging/dev configurations  
✅ **Alert Severity Levels**: critical, warning, info  
✅ **Threshold Configuration**: Customizable alert thresholds  
✅ **Evaluation Intervals**: Adjustable alert evaluation timing  

## Related Charts

- **common-kyverno**: Policy validation (see `../common-kyverno/`)
- **common-security**: Trivy, Falco (see `../common-security/`)
- **common-kubernetes**: HPA, Ingress (see `../common-kubernetes/`)

## Support

For issues or questions:
1. Check test script output for specific error messages
2. Review UC documentation files (`UC*.md`)
3. Verify prerequisites (Prometheus Operator, CRDs)
4. Check Kubernetes cluster logs

## Version Compatibility

| Component               | Minimum Version | Tested Version |
|------------------------|-----------------|----------------|
| Kubernetes             | 1.23            | 1.28           |
| Helm                   | 3.0             | 3.13           |
| Prometheus Operator    | 0.60            | 0.70           |
| kube-prometheus-stack  | 48.0            | 54.0           |
| kubectl                | 1.23            | 1.28           |
| hey (optional)         | 0.1.4           | 0.1.4          |

## Contributing

When adding new Use Cases:

1. Create documentation file: `UC0X-feature.md`
2. Create values file: `values/uc0X-feature.yaml`
3. Create test script: `test-cases/run-uc0X.sh`
4. Add workload if needed: `workloads/uc0X-app.yaml`
5. Update `run-all.sh` to include new UC
6. Update this README with UC description
7. Test locally: `./run-uc0X.sh`
8. Test full suite: `./run-all.sh`

## License

MIT License - See repository root for details.
