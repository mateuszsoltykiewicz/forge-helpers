# Forge Helpers - Comprehensive Testing Plan

## Executive Summary

**Date**: 2026-02-21  
**Cluster**: EKS (eu-central-1)  
**Testing Approach**: Two-tier (Isolated + Integration)  
**Total Use Cases**: 45+ scenarios

---

## Current Cluster Status

### ✅ Installed Components

| Component | Status | Version/Details |
|-----------|--------|-----------------|
| **Kyverno** | ✅ Installed | 4 controllers (admission, background, cleanup, reports) |
| **Prometheus Operator** | ✅ Installed | monitoring.coreos.com/v1 CRDs |
| **Grafana** | ✅ Installed | prometheus-grafana deployment |
| **KEDA** | ✅ Installed | ScaledObject, ScaledJob CRDs |
| **Vault Agent Injector** | ✅ Installed | vault namespace |
| **ArgoCD** | ✅ Installed | Complete setup with ApplicationSet |

### ❌ Missing Components (Need Installation)

| Component | Required For | Installation Priority |
|-----------|--------------|----------------------|
| **Trivy Operator** | common-security testing | HIGH |
| **Falco** | common-security runtime protection | MEDIUM |

### 📋 Available CRDs

```bash
# Kyverno
- ClusterPolicy, Policy
- ClusterCleanupPolicy, CleanupPolicy
- PolicyException
- EphemeralReport, ClusterEphemeralReport
- GlobalContextEntry

# Prometheus
- PrometheusRule, PrometheusAgent
- ServiceMonitor, PodMonitor

# KEDA
- ScaledObject, ScaledJob
- TriggerAuthentication, ClusterTriggerAuthentication
- CloudEventSource

# ArgoCD
- Application, ApplicationSet (assumed, not in CRD list)
```

---

## Testing Strategy

### Type 1: Chart Alone + Dependencies (Isolated Tests)

**Purpose**: Validate individual chart functionality with minimal dependencies

**Pattern**:
```
Test Chart + common-forge + prerequisites
```

**Validation**:
- Chart renders correctly (helm template)
- Resources are created (helm install)
- Resources function as expected (kubectl tests)
- Values validation works (schema validation)
- Documentation accuracy

### Type 2: Charts Combination (Integration Tests)

**Purpose**: Validate real-world multi-chart scenarios

**Pattern**:
```
Multiple Charts + common-forge + prerequisites
```

**Validation**:
- Charts work together
- No label/naming conflicts
- Cross-chart features (e.g., monitoring policies, securing workloads)
- End-to-end workflows
- Performance impact

---

## Test Structure

```
forge-helpers/
├── tests/
│   ├── unit/                          # Type 1: Isolated tests
│   │   ├── common-kyverno/
│   │   │   ├── prerequisites/         # Required K8s resources
│   │   │   ├── values/               # Test value files
│   │   │   ├── workloads/            # Test applications
│   │   │   ├── test-cases/           # Test scripts
│   │   │   └── README.md             # UC definitions
│   │   ├── common-monitoring/
│   │   ├── common-security/
│   │   ├── common-kubernetes/
│   │   ├── common-hardening/
│   │   ├── common-keda/
│   │   ├── common-vault/
│   │   ├── common-aws/
│   │   └── common-argocd/
│   │
│   ├── integration/                   # Type 2: Combination tests
│   │   ├── full-stack-app/           # kubernetes + monitoring + security + kyverno
│   │   ├── gitops-platform/          # kyverno + argocd + monitoring
│   │   ├── aws-microservice/         # kubernetes + aws + keda + vault
│   │   ├── secure-deployment/        # kyverno + security + hardening
│   │   └── README.md
│   │
│   ├── prerequisites/                 # Cluster-wide prerequisites
│   │   ├── install-trivy-operator.yaml
│   │   ├── install-falco.yaml
│   │   ├── test-namespaces.yaml
│   │   ├── test-serviceaccounts.yaml
│   │   └── README.md
│   │
│   ├── scripts/                       # Test automation
│   │   ├── setup-cluster.sh          # Install missing components
│   │   ├── run-unit-tests.sh         # Run all Type 1 tests
│   │   ├── run-integration-tests.sh  # Run all Type 2 tests
│   │   ├── cleanup.sh                # Clean test resources
│   │   └── validate-results.sh       # Parse test results
│   │
│   └── README.md                      # Main testing guide
```

---

## Type 1: Isolated Chart Tests - Use Case Definitions

### 1. common-kyverno (7,698 lines) - Priority: CRITICAL

**Prerequisites**:
- Kyverno CRDs ✅ (already installed)
- Test namespaces (test-app, test-blocked, test-allowed)
- Test ServiceAccounts (test-user, deployment-job, flux-cd)
- Test workloads (nginx deployment, test pods)

#### UC-KYVERNO-01: Block kubectl exec (API Restrictions)
**Description**: User attempts kubectl exec into pod, Kyverno blocks it  
**Test Steps**:
1. Install common-kyverno with `apiRestrictions.blockExec.enabled=true`
2. Deploy test pod (`kubectl run test-pod --image=nginx`)
3. Attempt exec: `kubectl exec test-pod -- ls`
4. **Expected**: Blocked with message "kubectl exec is not allowed"

**Values File**: `tests/unit/common-kyverno/values/uc01-block-exec.yaml`
```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: "enforce"
      message: "kubectl exec is not allowed. Use debug proxy instead."
      excludeNamespaces: ["kube-system"]
```

**Validation**:
```bash
# Should FAIL
kubectl exec test-pod -- ls

# Should SUCCEED (excluded namespace)
kubectl exec -n kube-system coredns-xxx -- ls
```

---

#### UC-KYVERNO-02: Block Direct Deployments (Resource Management)
**Description**: User attempts to create deployment directly, blocked by GitOps policy  
**Test Steps**:
1. Install common-kyverno with `resourceManagement.blockWorkloadModifications.enabled=true`
2. Attempt: `kubectl create deployment test --image=nginx`
3. **Expected**: Blocked with GitOps message

**Values File**: `tests/unit/common-kyverno/values/uc02-gitops-only.yaml`
```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
```

**Validation**:
```bash
# Should FAIL (user)
kubectl create deployment test --image=nginx

# Should SUCCEED (ServiceAccount with exclusion)
kubectl create sa deployment-job -n ci-cd
# Use SA to create deployment via Job
```

---

#### UC-KYVERNO-03: Debug Proxy Access (Controlled Access)
**Description**: User uses debug proxy ServiceAccount to access blocked APIs  
**Test Steps**:
1. Install common-kyverno with `debugProxy.enabled=true`
2. Block exec for users, allow for debug-proxy SA
3. Create pod using debug-proxy SA
4. Exec into pod using debug-proxy token

**Values File**: `tests/unit/common-kyverno/values/uc03-debug-proxy.yaml`
```yaml
kyverno:
  debugProxy:
    enabled: true
    serviceAccount:
      name: "debug-proxy"
      namespace: "kube-system"
  apiRestrictions:
    blockExec:
      enabled: true
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
```

**Validation**:
```bash
# Regular user: BLOCKED
kubectl exec test-pod -- ls

# Debug proxy SA: ALLOWED
kubectl --as=system:serviceaccount:kube-system:debug-proxy exec test-pod -- ls
```

---

#### UC-KYVERNO-04: GitOps Workflow (Full Enforcement)
**Description**: Complete GitOps-only environment with all resource types blocked  
**Test Steps**:
1. Enable all 5 resource management policies
2. Exclude flux-system namespace
3. Deploy via Flux GitOps (simulated with excluded SA)
4. Attempt direct modifications (should fail)

**Values File**: `tests/unit/common-kyverno/values/uc04-gitops-full.yaml`
```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
    blockNetworkingModifications:
      enabled: true
    blockConfigModifications:
      enabled: true
    blockStorageModifications:
      enabled: true
    blockRBACModifications:
      enabled: true
      severity: "critical"
```

**Validation**:
```bash
# All should FAIL for regular users
kubectl create deployment test --image=nginx        # Workload
kubectl create service clusterip test --tcp=80:80   # Networking
kubectl create configmap test --from-literal=a=b    # Config
kubectl create pvc test --size=1Gi                  # Storage
kubectl create role test --verb=get --resource=pods # RBAC
```

---

#### UC-KYVERNO-05: Break-Glass Procedure (Emergency Access)
**Description**: Cluster admin bypasses policies in emergency  
**Test Steps**:
1. All policies enabled
2. Admin user in excludeUsers list
3. Admin performs emergency operations

**Values File**: `tests/unit/common-kyverno/values/uc05-break-glass.yaml`
```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      excludeUsers: ["cluster-admin", "emergency-user"]
```

**Validation**:
```bash
# Regular user: BLOCKED
kubectl create deployment test --image=nginx

# Admin user: ALLOWED
kubectl --as=cluster-admin create deployment emergency --image=nginx
```

---

#### UC-KYVERNO-06: Audit Mode (Staging/Development)
**Description**: Policies in audit mode, violations logged but not blocked  
**Test Steps**:
1. Enable policies with `action: "audit"`
2. Attempt blocked operations (should succeed)
3. Check PolicyReports for violations

**Values File**: `tests/unit/common-kyverno/values/uc06-audit-mode.yaml`
```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: "audit"  # Log only, don't block
```

**Validation**:
```bash
# Should SUCCEED (audit mode)
kubectl exec test-pod -- ls

# Check for audit entry
kubectl get policyreport -A
kubectl describe policyreport -n default
```

---

### 2. common-monitoring (1,707 lines) - Priority: HIGH

**Prerequisites**:
- Prometheus Operator CRDs ✅ (already installed)
- Prometheus instance running ✅
- Grafana running ✅
- Test application with metrics endpoint

#### UC-MONITORING-01: Prometheus Alerts for Pod Crashes
**Description**: Alert fires when pod crashes repeatedly  
**Test Steps**:
1. Install common-monitoring with availability alerts
2. Deploy crashloop pod
3. Wait for alert to fire

**Values File**: `tests/unit/common-monitoring/values/uc01-availability-alerts.yaml`
```yaml
monitoring:
  prometheus:
    rules:
      availability:
        enabled: true
        podCrashLooping:
          enabled: true
          threshold: 3  # Alert after 3 crashes
```

**Workload**: `tests/unit/common-monitoring/workloads/crashloop-pod.yaml`
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: crashloop-test
  labels:
    app: test
spec:
  containers:
  - name: crash
    image: busybox
    command: ["sh", "-c", "exit 1"]
```

**Validation**:
```bash
# Check PrometheusRule created
kubectl get prometheusrule -A

# Check alert firing
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/alerts
# Look for "PodCrashLooping" alert
```

---

#### UC-MONITORING-02: Grafana Dashboard Provisioning
**Description**: Grafana automatically discovers and loads custom dashboard  
**Test Steps**:
1. Install common-monitoring with custom dashboard
2. Check Grafana for dashboard

**Values File**: `tests/unit/common-monitoring/values/uc02-grafana-dashboard.yaml`
```yaml
monitoring:
  grafana:
    dashboard:
      enabled: true
      name: "test-dashboard"
      namespace: "monitoring"
      json: |
        {
          "dashboard": {
            "title": "Test Application Dashboard",
            "panels": [
              {
                "title": "Request Rate",
                "targets": [{"expr": "rate(http_requests_total[5m])"}]
              }
            ]
          }
        }
```

**Validation**:
```bash
# Check ConfigMap created
kubectl get cm -n monitoring | grep dashboard

# Check Grafana UI
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000
# Look for "Test Application Dashboard"
```

---

#### UC-MONITORING-03: SLO Monitoring (Latency P99)
**Description**: Alert fires when P99 latency exceeds SLO  
**Test Steps**:
1. Install monitoring with SLO rules
2. Deploy app with slow responses
3. Wait for SLO violation alert

**Values File**: `tests/unit/common-monitoring/values/uc03-slo-latency.yaml`
```yaml
monitoring:
  prometheus:
    rules:
      slo:
        enabled: true
        latency:
          enabled: true
          p99Threshold: "500ms"  # Alert if P99 > 500ms
```

**Validation**:
```bash
# Generate slow requests to test app
hey -n 1000 -c 10 -q 5 http://test-app/slow

# Check alert
kubectl get prometheusrule -o yaml | grep -A 10 "HighLatencyP99"
```

---

#### UC-MONITORING-04: Multi-Environment Alerting
**Description**: Different alert thresholds per environment  
**Test Steps**:
1. Deploy monitoring with environment-specific rules
2. Verify production has stricter thresholds

**Values File**: `tests/unit/common-monitoring/values/uc04-multi-env.yaml`
```yaml
forge:
  environment: "production"

monitoring:
  prometheus:
    rules:
      availability:
        errorRateThreshold: "0.01"  # 1% for prod (strict)
      slo:
        latency:
          p99Threshold: "200ms"  # 200ms for prod
```

---

### 3. common-security (1,651 lines) - Priority: HIGH

**Prerequisites**:
- ❌ Trivy Operator (NEEDS INSTALLATION)
- ❌ Falco (NEEDS INSTALLATION)

#### UC-SECURITY-01: Trivy Vulnerability Scanning
**Description**: Scan image for vulnerabilities on deployment  
**Test Steps**:
1. Install Trivy Operator
2. Install common-security with vulnerability scanning
3. Deploy image with known vulnerabilities
4. Check VulnerabilityReport

**Values File**: `tests/unit/common-security/values/uc01-trivy-vuln.yaml`
```yaml
security:
  trivy:
    vulnerability:
      enabled: true
      scanOnDeploy: true
      severity: ["CRITICAL", "HIGH"]
```

**Workload**: `tests/unit/common-security/workloads/vulnerable-app.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vulnerable-app
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: app
        image: nginx:1.14.0  # Old version with CVEs
```

**Validation**:
```bash
# Check VulnerabilityReport CRD
kubectl get vulnerabilityreport -A

# Check scan results
kubectl get vulnerabilityreport vulnerable-app -o yaml
```

---

#### UC-SECURITY-02: Secret Detection in Images
**Description**: Detect hardcoded secrets in container images  
**Test Steps**:
1. Install common-security with secret scanning
2. Deploy image with secrets in ENV
3. Check for secret detection

**Values File**: `tests/unit/common-security/values/uc02-secret-scan.yaml`
```yaml
security:
  trivy:
    secret:
      enabled: true
      patterns:
        - "password"
        - "api_key"
        - "AWS_SECRET"
```

---

#### UC-SECURITY-03: Falco Runtime Protection
**Description**: Detect suspicious runtime behavior  
**Test Steps**:
1. Install Falco
2. Install common-security with Falco rules
3. Trigger suspicious activity (exec bash, write to /etc)
4. Check Falco alerts

**Values File**: `tests/unit/common-security/values/uc03-falco-runtime.yaml`
```yaml
security:
  falco:
    enabled: true
    rules:
      suspiciousShell:
        enabled: true
      sensitiveFileWrite:
        enabled: true
```

**Validation**:
```bash
# Trigger suspicious activity
kubectl exec test-pod -- bash -c "echo 'test' > /etc/test"

# Check Falco logs
kubectl logs -n falco -l app=falco | grep "Warning"
```

---

#### UC-SECURITY-04: Scheduled Security Scans
**Description**: CronJob runs nightly security scans  
**Test Steps**:
1. Install common-security with CronJob
2. Manually trigger scan job
3. Check results

**Values File**: `tests/unit/common-security/values/uc04-scheduled-scan.yaml`
```yaml
security:
  trivy:
    scanJob:
      enabled: true
      schedule: "0 2 * * *"  # 2 AM daily
```

---

### 4. common-kubernetes - Priority: HIGH

**Prerequisites**:
- Standard K8s cluster ✅

#### UC-KUBERNETES-01: Deployment with HPA
**Description**: Deploy app with horizontal pod autoscaler  
**Values File**: `tests/unit/common-kubernetes/values/uc01-hpa.yaml`

#### UC-KUBERNETES-02: Service + Ingress
**Description**: Expose app via Ingress with TLS  
**Values File**: `tests/unit/common-kubernetes/values/uc02-ingress.yaml`

#### UC-KUBERNETES-03: ConfigMap/Secret Management
**Description**: Inject config and secrets into pods  
**Values File**: `tests/unit/common-kubernetes/values/uc03-config-secrets.yaml`

#### UC-KUBERNETES-04: RBAC Setup
**Description**: Create ServiceAccount with limited permissions  
**Values File**: `tests/unit/common-kubernetes/values/uc04-rbac.yaml`

---

### 5. common-hardening - Priority: MEDIUM

#### UC-HARDENING-01: Network Policies (Deny-All Baseline)
**Description**: Default deny all traffic, explicit allow DNS  
**Values File**: `tests/unit/common-hardening/values/uc01-deny-all.yaml`

#### UC-HARDENING-02: Resource Quotas
**Description**: Limit namespace resource consumption  
**Values File**: `tests/unit/common-hardening/values/uc02-quotas.yaml`

#### UC-HARDENING-03: Pod Security Standards
**Description**: Enforce restricted PSS profile  
**Values File**: `tests/unit/common-hardening/values/uc03-pss.yaml`

---

### 6. common-keda - Priority: MEDIUM

**Prerequisites**:
- KEDA CRDs ✅ (already installed)
- Test message queue (RabbitMQ or Redis)

#### UC-KEDA-01: CPU-Based Autoscaling
**Description**: Scale deployment based on CPU  
**Values File**: `tests/unit/common-keda/values/uc01-cpu-scaling.yaml`

#### UC-KEDA-02: Queue-Based Job Scaling
**Description**: Scale jobs based on queue length  
**Values File**: `tests/unit/common-keda/values/uc02-queue-jobs.yaml`

#### UC-KEDA-03: Cron-Based Scaling
**Description**: Scale up during business hours  
**Values File**: `tests/unit/common-keda/values/uc03-cron-scaling.yaml`

---

### 7. common-vault - Priority: MEDIUM

**Prerequisites**:
- Vault Agent Injector ✅ (already installed)
- Vault server with secrets

#### UC-VAULT-01: Secret Injection
**Description**: Inject Vault secrets into pod via annotations  
**Values File**: `tests/unit/common-vault/values/uc01-secret-injection.yaml`

#### UC-VAULT-02: Dynamic Secrets
**Description**: Generate dynamic database credentials  
**Values File**: `tests/unit/common-vault/values/uc02-dynamic-secrets.yaml`

---

### 8. common-aws - Priority: LOW (AWS-specific)

**Prerequisites**:
- EKS cluster ✅
- IAM roles configured

#### UC-AWS-01: IRSA (IAM Roles for Service Accounts)
**Description**: Pod assumes IAM role via ServiceAccount  
**Values File**: `tests/unit/common-aws/values/uc01-irsa.yaml`

#### UC-AWS-02: ALB Ingress
**Description**: Create ALB via Ingress  
**Values File**: `tests/unit/common-aws/values/uc02-alb-ingress.yaml`

---

### 9. common-argocd - Priority: LOW

**Prerequisites**:
- ArgoCD CRDs ✅ (already installed)

#### UC-ARGOCD-01: Application Deployment
**Description**: Deploy app via ArgoCD Application CRD  
**Values File**: `tests/unit/common-argocd/values/uc01-application.yaml`

#### UC-ARGOCD-02: Multi-Cluster ApplicationSet
**Description**: Deploy to multiple clusters via ApplicationSet  
**Values File**: `tests/unit/common-argocd/values/uc02-appset.yaml`

---

## Type 2: Integration Tests - Use Case Definitions

### Integration-01: Full Stack Application

**Description**: Complete production application with all security/monitoring  
**Charts**: common-kubernetes + common-monitoring + common-security + common-kyverno

**Scenario**:
1. Deploy web application (Deployment, Service, Ingress)
2. Monitor with Prometheus/Grafana (golden signals)
3. Scan for vulnerabilities (Trivy)
4. Enforce GitOps (Kyverno policies)

**Values File**: `tests/integration/full-stack-app/values.yaml`

**Test Cases**:
- TC-INT-01-01: App deploys successfully
- TC-INT-01-02: Prometheus scrapes metrics
- TC-INT-01-03: Grafana shows dashboard
- TC-INT-01-04: Trivy scans image
- TC-INT-01-05: Direct kubectl modifications blocked
- TC-INT-01-06: Alerts fire on high error rate

---

### Integration-02: GitOps Platform

**Description**: Platform team setup for GitOps enforcement  
**Charts**: common-kyverno + common-argocd + common-monitoring

**Scenario**:
1. Install Kyverno policies (GitOps-only)
2. Deploy ArgoCD Applications
3. Monitor policy violations
4. Block manual deployments

**Values File**: `tests/integration/gitops-platform/values.yaml`

**Test Cases**:
- TC-INT-02-01: Kyverno blocks user deployments
- TC-INT-02-02: ArgoCD can deploy (excluded SA)
- TC-INT-02-03: Policy violations logged to Prometheus
- TC-INT-02-04: Grafana dashboard shows policy metrics

---

### Integration-03: AWS Microservice

**Description**: Microservice with AWS integrations  
**Charts**: common-kubernetes + common-aws + common-keda + common-vault

**Scenario**:
1. Deploy microservice with IRSA
2. Use Vault for DB credentials
3. Scale with KEDA (SQS queue)
4. Access S3 via IAM role

**Values File**: `tests/integration/aws-microservice/values.yaml`

**Test Cases**:
- TC-INT-03-01: Pod assumes IAM role
- TC-INT-03-02: Vault injects DB password
- TC-INT-03-03: KEDA scales based on SQS queue
- TC-INT-03-04: App writes to S3 successfully

---

### Integration-04: Secure Deployment Pipeline

**Description**: CI/CD pipeline with security gates  
**Charts**: common-kyverno + common-security + common-hardening

**Scenario**:
1. CI/CD job deploys app (excluded from Kyverno)
2. Trivy scans before deployment
3. Network policies isolate app
4. Resource quotas prevent overuse

**Values File**: `tests/integration/secure-deployment/values.yaml`

**Test Cases**:
- TC-INT-04-01: CI/CD job can deploy (exclusion)
- TC-INT-04-02: Trivy blocks vulnerable images
- TC-INT-04-03: Network policy denies unexpected traffic
- TC-INT-04-04: Resource quota limits enforced

---

### Integration-05: Multi-Tenant Platform

**Description**: Isolated tenants with governance  
**Charts**: common-hardening + common-kyverno + common-monitoring

**Scenario**:
1. Create tenant namespaces
2. Apply network policies (tenant isolation)
3. Resource quotas per tenant
4. Monitor per-tenant metrics
5. Prevent cross-tenant access

**Values File**: `tests/integration/multi-tenant/values.yaml`

**Test Cases**:
- TC-INT-05-01: Tenant A cannot access Tenant B pods
- TC-INT-05-02: Tenant resource quotas enforced
- TC-INT-05-03: Tenant-specific monitoring dashboards
- TC-INT-05-04: Kyverno policies per tenant

---

## Installation Prerequisites

### 1. Install Trivy Operator

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set="trivy.ignoreUnfixed=true"
```

**Validation**:
```bash
kubectl get deploy -n trivy-system
kubectl get crd | grep trivy
```

---

### 2. Install Falco

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set tty=true
```

**Validation**:
```bash
kubectl get ds -n falco
kubectl logs -n falco -l app=falco --tail=20
```

---

### 3. Create Test Namespaces

```yaml
# tests/prerequisites/test-namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: test-app
  labels:
    testing: "true"
    environment: "test"
---
apiVersion: v1
kind: Namespace
metadata:
  name: test-blocked
  labels:
    testing: "true"
    kyverno-policy: "enforce"
---
apiVersion: v1
kind: Namespace
metadata:
  name: test-allowed
  labels:
    testing: "true"
    kyverno-policy: "excluded"
---
apiVersion: v1
kind: Namespace
metadata:
  name: ci-cd
  labels:
    purpose: "deployment"
```

---

### 4. Create Test ServiceAccounts

```yaml
# tests/prerequisites/test-serviceaccounts.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployment-job
  namespace: ci-cd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deployment-job-role
rules:
- apiGroups: ["apps", ""]
  resources: ["deployments", "services", "configmaps", "secrets"]
  verbs: ["create", "update", "patch", "delete", "get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: deployment-job-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deployment-job-role
subjects:
- kind: ServiceAccount
  name: deployment-job
  namespace: ci-cd
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: debug-proxy
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: debug-proxy-role
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec", "pods/portforward"]
  verbs: ["get", "list", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: debug-proxy-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: debug-proxy-role
subjects:
- kind: ServiceAccount
  name: debug-proxy
  namespace: kube-system
```

---

## Test Execution Scripts

### Setup Script

```bash
#!/bin/bash
# tests/scripts/setup-cluster.sh

set -e

echo "=== Setting up test environment ==="

# 1. Install missing operators
echo "Installing Trivy Operator..."
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set="trivy.ignoreUnfixed=true" \
  --wait

echo "Installing Falco..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set tty=true \
  --wait

# 2. Create test namespaces
echo "Creating test namespaces..."
kubectl apply -f ../prerequisites/test-namespaces.yaml

# 3. Create test ServiceAccounts
echo "Creating test ServiceAccounts..."
kubectl apply -f ../prerequisites/test-serviceaccounts.yaml

echo "✅ Setup complete!"
```

---

### Run Unit Tests Script

```bash
#!/bin/bash
# tests/scripts/run-unit-tests.sh

set -e

RESULTS_DIR="./test-results"
mkdir -p "$RESULTS_DIR"

echo "=== Running Unit Tests ==="

# Test each chart
for chart in unit/*/; do
  chart_name=$(basename "$chart")
  echo ""
  echo "Testing $chart_name..."
  
  cd "$chart"
  
  # Run test cases
  if [ -f "./test-cases/run-all.sh" ]; then
    ./test-cases/run-all.sh | tee "$RESULTS_DIR/$chart_name.log"
  else
    echo "⚠️  No test script found for $chart_name"
  fi
  
  cd -
done

echo ""
echo "=== Unit Test Results ==="
grep -E "PASS|FAIL" "$RESULTS_DIR"/*.log | tee "$RESULTS_DIR/summary.txt"
```

---

## Success Metrics

### Coverage Goals

| Test Type | Target | Current |
|-----------|--------|---------|
| Unit Tests (Type 1) | 30+ UCs | 25 defined |
| Integration Tests (Type 2) | 5+ scenarios | 5 defined |
| Chart Coverage | 100% | 9/9 charts |
| Code Coverage | N/A (templates) | Template validation |

### Quality Gates

- ✅ All unit tests pass
- ✅ All integration tests pass
- ✅ No Helm lint errors
- ✅ No schema validation errors
- ✅ Documentation matches behavior
- ✅ Performance: <5s chart render time
- ✅ No resource leaks after cleanup

---

## Next Steps

### Immediate (Week 1)
1. ✅ Create testing plan (DONE)
2. 🔄 Install missing operators (Trivy, Falco)
3. 🔄 Create test prerequisites
4. 🔄 Implement UC-KYVERNO-01 to 06 (common-kyverno tests)

### Short-term (Week 2-3)
5. Implement common-monitoring tests (4 UCs)
6. Implement common-security tests (4 UCs)
7. Implement common-kubernetes tests (4 UCs)
8. Create automation scripts

### Medium-term (Week 4-6)
9. Implement integration tests (5 scenarios)
10. Performance testing
11. Documentation validation
12. CI/CD integration

---

## Summary

**Total Use Cases**: 45+
- Type 1 (Isolated): 25+ UCs across 9 charts
- Type 2 (Integration): 5 scenarios

**Priority Distribution**:
- CRITICAL: common-kyverno (6 UCs)
- HIGH: common-monitoring (4 UCs), common-security (4 UCs), common-kubernetes (4 UCs)
- MEDIUM: common-hardening (3 UCs), common-keda (3 UCs), common-vault (2 UCs)
- LOW: common-aws (2 UCs), common-argocd (2 UCs)

**Cluster Status**:
- ✅ Kyverno ready
- ✅ Prometheus/Grafana ready
- ✅ KEDA ready
- ✅ Vault ready
- ✅ ArgoCD ready
- ❌ Trivy Operator (needs installation)
- ❌ Falco (needs installation)

**Next Action**: Install Trivy Operator and Falco, then start with UC-KYVERNO-01
