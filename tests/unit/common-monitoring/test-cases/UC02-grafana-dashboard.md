# UC-MONITORING-02: Grafana Dashboard Provisioning

## Overview

**Use Case ID**: UC-MONITORING-02  
**Chart**: common-monitoring  
**Feature**: Grafana Dashboard ConfigMap  
**Priority**: HIGH  

## Description

This use case validates that the common-monitoring chart correctly provisions Grafana dashboards via ConfigMaps. The test installs the chart with a custom dashboard configuration and verifies that Grafana automatically discovers and loads the dashboard.

## Prerequisites

- Kubernetes cluster (1.23+)
- Grafana installed in `monitoring` namespace
- Test namespace: `test-monitoring`
- kubectl and helm installed
- curl (for API checks)
- jq (for JSON parsing)

## Test Objectives

1. Install common-monitoring chart with custom dashboard enabled
2. Verify ConfigMap with dashboard JSON is created
3. Verify Grafana sidecar picks up the ConfigMap
4. Access Grafana and confirm dashboard is loaded
5. Verify dashboard panels are correct
6. Test dashboard functionality (query execution)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Test Namespace                             │
│  ┌───────────────────────────────────────────┐             │
│  │  ConfigMap (Dashboard JSON)               │             │
│  │  - Title: "Test Application Metrics"      │             │
│  │  - Panels: Request Rate, Error Rate, P99  │             │
│  │  - Label: grafana_dashboard=1             │             │
│  └───────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ (watched by)
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                  Monitoring Namespace                       │
│  ┌──────────────────────────────────────────┐              │
│  │        Grafana Pod                       │              │
│  │  ┌────────────┐      ┌────────────────┐ │              │
│  │  │  Sidecar   │─────→│  Grafana Core  │ │              │
│  │  │ (k8s watch)│      │  (dashboard DB)│ │              │
│  │  └────────────┘      └────────────────┘ │              │
│  └──────────────────────────────────────────┘              │
│                          │                                  │
│                          │ (serves)                         │
│                          ↓                                  │
│                  ┌──────────────┐                          │
│                  │   Grafana UI │                          │
│                  │  :3000/d/... │                          │
│                  └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## Dashboard JSON Structure

The test dashboard includes three panels:

1. **Request Rate**: `rate(http_requests_total[5m])`
2. **Error Rate**: `rate(http_errors_total[5m])`
3. **P99 Latency**: `histogram_quantile(0.99, rate(http_duration_seconds_bucket[5m]))`

## Test Values Configuration

See: `values/uc02-grafana-dashboard.yaml`

Key configurations:
```yaml
monitoring:
  grafana:
    enabled: true
    dashboard:
      enabled: true
      name: "test-application-metrics"
      folder: "Test"
      json: |
        {
          "dashboard": {
            "title": "Test Application Metrics",
            "panels": [...]
          }
        }
```

## Test Steps

### Step 1: Install Chart

```bash
helm install test-monitoring-uc02 \
  ../../../../charts/common-monitoring \
  -f values/uc02-grafana-dashboard.yaml \
  -n test-monitoring \
  --create-namespace \
  --wait
```

**Expected**: Chart installs successfully

### Step 2: Verify ConfigMap Created

```bash
kubectl get configmap -n test-monitoring | grep dashboard
```

**Expected Output**:
```
NAME                              DATA   AGE
test-application-metrics-dashboard   1      10s
```

### Step 3: Inspect ConfigMap Content

```bash
kubectl get configmap test-application-metrics-dashboard \
  -n test-monitoring -o yaml
```

**Expected**: ConfigMap contains:
- Dashboard JSON in `data` field
- Label: `grafana_dashboard: "1"`
- Annotation with folder name

### Step 4: Verify Dashboard JSON Structure

```bash
kubectl get configmap test-application-metrics-dashboard \
  -n test-monitoring -o jsonpath='{.data}' | jq '.'
```

**Expected**: Valid JSON with:
- `dashboard.title`
- `dashboard.panels[]`
- Panel targets with PromQL queries

### Step 5: Wait for Grafana Sidecar to Sync

Wait 30-60 seconds for Grafana sidecar to detect and load the dashboard.

```bash
# Check Grafana pod logs
kubectl logs -n monitoring deployment/prometheus-grafana -c grafana-sc-dashboard --tail=50
```

**Expected Log**:
```
Detected new dashboard: test-application-metrics
Provisioning dashboard: Test Application Metrics
Dashboard provisioned successfully
```

### Step 6: Access Grafana UI

```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Get admin password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

Open: http://localhost:3000
- Username: `admin`
- Password: (from above command)

### Step 7: Search for Dashboard

In Grafana UI:
1. Click "Search dashboards" (🔍)
2. Type "Test Application"
3. Dashboard should appear in results

**Expected**: Dashboard listed with correct title

### Step 8: Open Dashboard

Click on "Test Application Metrics" dashboard

**Expected**:
- Dashboard opens without errors
- Three panels visible:
  1. Request Rate
  2. Error Rate  
  3. P99 Latency
- Panels may show "No data" (normal if no metrics exist)

### Step 9: Verify Dashboard via API

```bash
# Search dashboards via API
GRAFANA_URL="http://localhost:3000"
ADMIN_PASS=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

curl -s -u "admin:$ADMIN_PASS" \
  "$GRAFANA_URL/api/search?query=Test%20Application" | jq '.'
```

**Expected Output**:
```json
[
  {
    "id": 123,
    "uid": "abc123",
    "title": "Test Application Metrics",
    "type": "dash-db",
    "tags": [],
    "isStarred": false
  }
]
```

### Step 10: Get Dashboard Details

```bash
DASHBOARD_UID=$(curl -s -u "admin:$ADMIN_PASS" \
  "$GRAFANA_URL/api/search?query=Test%20Application" | \
  jq -r '.[0].uid')

curl -s -u "admin:$ADMIN_PASS" \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | jq '.dashboard.panels[].title'
```

**Expected Output**:
```
"Request Rate"
"Error Rate"
"P99 Latency"
```

## Validation Criteria

### ✅ Pass Criteria

1. **ConfigMap Created**: Dashboard ConfigMap exists in test namespace
2. **Correct Labels**: ConfigMap has `grafana_dashboard: "1"` label
3. **Valid JSON**: Dashboard JSON is valid and well-formed
4. **Panels Present**: Dashboard has all expected panels
5. **Grafana Loads Dashboard**: Dashboard appears in Grafana UI
6. **API Accessible**: Dashboard accessible via Grafana API

### ❌ Fail Criteria

1. ConfigMap not created
2. Missing grafana_dashboard label
3. Invalid JSON structure
4. Dashboard not loaded in Grafana after 2 minutes
5. Missing panels in dashboard
6. API returns 404 for dashboard

## Troubleshooting

### Issue: ConfigMap Not Created

**Debug**:
```bash
helm get values test-monitoring-uc02 -n test-monitoring | grep -A 10 "grafana"
```

**Fix**: Ensure `monitoring.grafana.dashboard.enabled=true`

---

### Issue: Dashboard Not Appearing in Grafana

**Symptoms**: ConfigMap exists but dashboard not in Grafana UI

**Debug**:
```bash
# Check ConfigMap labels
kubectl get configmap test-application-metrics-dashboard \
  -n test-monitoring -o jsonpath='{.metadata.labels}'

# Check Grafana sidecar logs
kubectl logs -n monitoring deployment/prometheus-grafana \
  -c grafana-sc-dashboard --tail=100
```

**Possible Causes**:
1. Missing `grafana_dashboard: "1"` label
2. Sidecar not watching test-monitoring namespace
3. Invalid JSON syntax

**Fix**:
```bash
# Add label if missing
kubectl label configmap test-application-metrics-dashboard \
  grafana_dashboard=1 -n test-monitoring

# Restart Grafana to force reload
kubectl rollout restart deployment/prometheus-grafana -n monitoring
```

---

### Issue: Invalid JSON Error

**Symptoms**: Grafana logs show JSON parsing error

**Debug**:
```bash
kubectl get configmap test-application-metrics-dashboard \
  -n test-monitoring -o jsonpath='{.data}' | jq '.'
```

**Fix**: Validate JSON syntax, common issues:
- Trailing commas
- Missing quotes
- Unescaped special characters

---

### Issue: Panels Show No Data

**Symptoms**: Dashboard loads but panels empty

**Note**: This is EXPECTED if test metrics don't exist

**To Generate Test Data**:
```bash
# Deploy test app that exports metrics
kubectl apply -f workloads/metrics-app.yaml -n test-monitoring
```

---

### Issue: Grafana API Authentication Failed

**Debug**:
```bash
# Verify admin password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Test connection
curl -v -u "admin:CORRECT_PASSWORD" http://localhost:3000/api/health
```

## Real-World Scenarios

### Scenario 1: Team-Specific Dashboards

**Context**: Each team wants custom dashboards for their services

**Implementation**:
```yaml
# In team-a namespace
monitoring:
  grafana:
    dashboard:
      name: "team-a-services"
      folder: "Team A"
      json: |
        { "dashboard": { "title": "Team A Services", ... }}
```

**Result**: Dashboard appears in "Team A" folder in Grafana

### Scenario 2: Multi-Environment Dashboards

**Context**: Different dashboards for prod/staging/dev

**Implementation**:
```yaml
# Production
forge:
  environment: "production"
monitoring:
  grafana:
    dashboard:
      title: "Production Metrics"
      json: |
        { "dashboard": { "title": "Production - {{ .Values.forge.service }}", ... }}
```

### Scenario 3: Dashboard Versioning

**Context**: Update dashboard without downtime

**Process**:
1. Update dashboard JSON in values file
2. Run `helm upgrade`
3. Grafana sidecar detects change
4. Dashboard auto-updates in UI

## Dashboard Templating

### Using Helm Templates in JSON

```yaml
dashboard:
  json: |
    {
      "dashboard": {
        "title": "{{ .Values.forge.service | title }} Metrics",
        "panels": [
          {
            "title": "Request Rate",
            "targets": [{
              "expr": "rate({{ .Values.forge.service }}_requests_total[5m])"
            }]
          }
        ]
      }
    }
```

### Variable Dashboards

```json
{
  "dashboard": {
    "templating": {
      "list": [
        {
          "name": "namespace",
          "type": "query",
          "query": "label_values(kube_pod_info, namespace)"
        }
      ]
    }
  }
}
```

## Performance Considerations

### Dashboard Complexity

- **Simple** (1-5 panels): < 1 second load time
- **Medium** (6-15 panels): 1-3 seconds
- **Complex** (16+ panels): 3-10 seconds

**Recommendation**: Keep dashboards focused, create multiple dashboards instead of one huge dashboard

### Sidecar Sync Time

- **Typical**: 10-30 seconds after ConfigMap creation
- **Max**: 60 seconds
- **Configurable**: Via sidecar `--watch-interval`

## Security Considerations

### Dashboard Access Control

Grafana RBAC controls who can view dashboards:

```yaml
# Read-only access to folder
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: grafana-dashboard-viewer
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
```

### Sensitive Data in Dashboards

**Risk**: Dashboard JSON may contain:
- Internal service names
- Infrastructure details
- Query patterns

**Mitigation**:
- Use Grafana folder permissions
- Don't embed secrets in dashboard JSON
- Review dashboards before production

## Integration with GitOps

### ArgoCD Sync

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-dashboards
spec:
  source:
    path: charts/common-monitoring
    helm:
      values: |
        monitoring:
          grafana:
            dashboard:
              enabled: true
              json: |
                {{ .Files.Get "dashboards/app-metrics.json" | indent 16 }}
```

## Test Cleanup

```bash
# Uninstall chart
helm uninstall test-monitoring-uc02 -n test-monitoring

# Delete namespace (optional)
kubectl delete namespace test-monitoring
```

## References

- [Grafana Dashboard Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards)
- [Grafana Sidecar](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards)
- [Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/json-model/)

## Test Execution

**Run automated test**:
```bash
cd test-cases
./run-uc02.sh
```

**Expected Duration**: 2-3 minutes

**Exit Codes**:
- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Prerequisites not met
