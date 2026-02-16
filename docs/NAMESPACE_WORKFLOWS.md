# Namespace Workflows: Real-World Usage Examples

**Practical workflows for common namespace management scenarios.**

---

## 📋 Table of Contents

1. [Application Deployment Workflows](#application-deployment-workflows)
2. [Infrastructure Namespace Workflows](#infrastructure-namespace-workflows)
3. [Emergency Operations](#emergency-operations)
4. [Compliance & Monitoring](#compliance--monitoring)
5. [GitOps Integration](#gitops-integration)
6. [Multi-Environment Patterns](#multi-environment-patterns)
7. [Troubleshooting Workflows](#troubleshooting-workflows)

---

## Application Deployment Workflows

### 🚀 Workflow 1: New Microservice Deployment

**Scenario:** Deploy a new payment processing microservice with Helm.

**Prerequisites:**
- Helm chart ready
- VPA installed in cluster (for accurate measurement)
- HPA configured in Helm chart (optional but recommended)

**Steps:**

```bash
# ============================================================================
# STEP 1: Create unhardened namespace
# ============================================================================
./namespace-create.sh \
  --name payment-service \
  --type application \
  --owner team-payments \
  --project metis \
  --environment production

# Output:
# ✓ Namespace 'payment-service' created
# ⚠️  UNHARDENED - Must harden within 4 hours
# moai.forge.io/hardened: false

# ============================================================================
# STEP 2: Deploy application via Helm
# ============================================================================
helm install payment-api ./charts/payment-api \
  --namespace payment-service \
  --set image.tag=v1.2.3 \
  --set replicas=3 \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=3 \
  --set autoscaling.maxReplicas=10 \
  --set resources.requests.cpu=200m \
  --set resources.requests.memory=512Mi \
  --set resources.limits.cpu=1000m \
  --set resources.limits.memory=2Gi

# Verify deployment
kubectl get pods -n payment-service
# NAME                           READY   STATUS    RESTARTS   AGE
# payment-api-7d9f8c5b6f-abcde   1/1     Running   0          30s
# payment-api-7d9f8c5b6f-fghij   1/1     Running   0          30s
# payment-api-7d9f8c5b6f-klmno   1/1     Running   0          30s

# ============================================================================
# STEP 3: Wait for VPA recommendations (30-60 minutes in production)
# ============================================================================
# For testing/demo: 5-10 minutes may be sufficient
# For production: Wait 24-48 hours for accurate P99 data

# Check VPA status
kubectl get vpa -n payment-service
# NAME              MODE   CPU    MEMORY   AGE
# payment-api-vpa   Auto   800m   1536Mi   45m

# View detailed VPA recommendations
kubectl describe vpa payment-api-vpa -n payment-service
# Recommendation:
#   Container Recommendations:
#     Container Name:  payment-api
#     Lower Bound:
#       Cpu:     200m
#       Memory:  512Mi
#     Target:
#       Cpu:     600m
#       Memory:  1Gi
#     Upper Bound:
#       Cpu:     1000m    ← We use this
#       Memory:  2Gi      ← We use this

# ============================================================================
# STEP 4: Harden the namespace
# ============================================================================
./namespace-hardening.sh --name payment-service

# Output:
# === Namespace Hardening: payment-service ===
# 
# [1/4] MEASUREMENT PHASE
#   ✓ Namespace exists: payment-service
#   ✓ Workloads detected: 1 deployment, 3 pods
#   ✓ VPA recommendations found:
#       - payment-api: CPU 1 core, Memory 2Gi
#   ✓ HPA configurations found:
#       - payment-api: maxReplicas=10
# 
# [2/4] CALCULATION PHASE
#   ✓ Total CPU (VPA): 1 core × 3 replicas = 3 cores
#   ✓ Total memory (VPA): 2Gi × 3 replicas = 6Gi
#   ✓ Max pods (HPA): 10 replicas + 5 buffer = 15 pods
#   ✓ Safety buffer (20%):
#       - CPU: 3 → 3.6 cores (rounded to 4)
#       - Memory: 6Gi → 7.2Gi (rounded to 8Gi)
#       - Pods: 15 → 18 (rounded to 20)
# 
# [3/4] HARDENING PHASE
#   ✓ Applied ResourceQuota: 4 CPU, 8Gi memory, 20 pods
#   ✓ Applied NetworkPolicy: default-deny-ingress
#   ✓ Applied PSS labels: restricted
#   ✓ Created Vault certificate bundle
#   ✓ Updated namespace labels
# 
# [4/4] VERIFICATION PHASE
#   ✓ All checks passed
# 
# === Hardening Complete ===

# ============================================================================
# STEP 5: Verify hardened state
# ============================================================================
./namespace-verify.sh --name payment-service

# Output:
# ✓ payment-service (application)
#   - Hardened: 2026-02-11T14:30:00Z
#   - Quota: 4 CPU, 8Gi memory, 20 pods
#   - Usage: 1.8 CPU (45%), 4.5Gi memory (56%), 3 pods (15%)
#   - Status: COMPLIANT

# Check ResourceQuota details
kubectl describe resourcequota namespace-quota -n payment-service
# Name:                   namespace-quota
# Resource                Used   Hard
# --------                ----   ----
# limits.cpu              3      4
# limits.memory           6Gi    8Gi
# pods                    3      20
# persistentvolumeclaims  0      5
```

**Expected Timeline:**
- Step 1 (Create): 5 seconds
- Step 2 (Deploy): 2-5 minutes
- Step 3 (Wait VPA): 30-60 minutes (or 24-48 hours for production)
- Step 4 (Harden): 10-30 seconds
- Step 5 (Verify): 5 seconds

**Total:** ~1 hour (dev/staging) or ~2 days (production with accurate VPA data)

---

### 📊 Workflow 2: Database Namespace (Middleware Type)

**Scenario:** Deploy PostgreSQL cluster with persistent storage.

```bash
# ============================================================================
# STEP 1: Create middleware namespace
# ============================================================================
./namespace-create.sh \
  --name postgres-cluster \
  --type middleware \
  --owner team-platform \
  --project infrastructure

# ============================================================================
# STEP 2: Deploy PostgreSQL via Helm (Bitnami chart)
# ============================================================================
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres bitnami/postgresql \
  --namespace postgres-cluster \
  --set primary.resources.requests.cpu=2 \
  --set primary.resources.requests.memory=4Gi \
  --set primary.resources.limits.cpu=4 \
  --set primary.resources.limits.memory=8Gi \
  --set primary.persistence.size=100Gi \
  --set readReplicas.replicaCount=2 \
  --set readReplicas.resources.requests.cpu=1 \
  --set readReplicas.resources.requests.memory=2Gi

# ============================================================================
# STEP 3: Wait for stabilization (no VPA for databases typically)
# ============================================================================
# Databases often don't use VPA due to predictable resource patterns
# Wait for pods to stabilize (15-30 minutes)

kubectl get pods -n postgres-cluster
# NAME                 READY   STATUS    RESTARTS   AGE
# postgres-primary-0   1/1     Running   0          20m
# postgres-read-0      1/1     Running   0          20m
# postgres-read-1      1/1     Running   0          20m

# ============================================================================
# STEP 4: Harden based on pod limits (no VPA available)
# ============================================================================
./namespace-hardening.sh --name postgres-cluster --skip-vpa

# Output:
# [1/4] MEASUREMENT PHASE
#   ⚠️  No VPA detected, using pod resource limits
#   ✓ Pod CPU limits: Primary 4 cores, Replicas 1 core × 2 = 6 cores total
#   ✓ Pod memory limits: Primary 8Gi, Replicas 2Gi × 2 = 12Gi total
#   ✓ Pod count: 3 current + 50% buffer = 5 pods
# 
# [2/4] CALCULATION PHASE
#   ✓ Safety buffer (20%):
#       - CPU: 6 → 7.2 cores (rounded to 8)
#       - Memory: 12Gi → 14.4Gi (rounded to 15Gi)
#       - Pods: 5 → 6
# 
# [3/4] HARDENING PHASE
#   ✓ Applied ResourceQuota: 8 CPU, 15Gi memory, 6 pods, 3 PVCs
#   ✓ Applied NetworkPolicy: default-deny-all (middleware type)
#   ✓ Applied PSS labels: baseline (allows privileged for persistence)
#   ⚠️  Skipped Vault bundle (not application type)

# ============================================================================
# STEP 5: Verify PVC quotas
# ============================================================================
kubectl get pvc -n postgres-cluster
# NAME                      STATUS   VOLUME     CAPACITY   STORAGE CLASS
# data-postgres-primary-0   Bound    pv-xxx     100Gi      gp3
# data-postgres-read-0      Bound    pv-yyy     100Gi      gp3
# data-postgres-read-1      Bound    pv-zzz     100Gi      gp3

kubectl describe resourcequota namespace-quota -n postgres-cluster
# Resource                Used   Hard
# --------                ----   ----
# persistentvolumeclaims  3      3  ← Locked at current usage
# requests.storage        300Gi  300Gi
```

---

## Infrastructure Namespace Workflows

### 🏗️ Workflow 3: Lock System Namespaces (Post-Kubernetes Install)

**Scenario:** Fresh Kubernetes cluster installed, lock default and kube-system to prevent resource creep.

```bash
# ============================================================================
# STEP 1: Verify fresh cluster state
# ============================================================================
kubectl get pods -n kube-system
# NAME                              READY   STATUS    RESTARTS   AGE
# coredns-1234abcd-xxxxx            1/1     Running   0          10m
# coredns-1234abcd-yyyyy            1/1     Running   0          10m
# etcd-master-1                     1/1     Running   0          10m
# kube-apiserver-master-1           1/1     Running   0          10m
# kube-controller-manager-master-1  1/1     Running   0          10m
# kube-proxy-zzzzz                  1/1     Running   0          10m
# kube-scheduler-master-1           1/1     Running   0          10m

kubectl get pods -n default
# No resources found in default namespace.

# ============================================================================
# STEP 2: Create namespace quota for kube-system (already exists)
# ============================================================================
# Note: kube-system namespace already exists, we just add management labels
kubectl label namespace kube-system \
  moai.forge.io/managed=true \
  moai.forge.io/type=kube-system \
  moai.forge.io/hardened=false

# ============================================================================
# STEP 3: Harden kube-system immediately
# ============================================================================
./namespace-hardening.sh --name kube-system --skip-vpa --skip-hpa

# Output:
# [1/4] MEASUREMENT PHASE
#   ✓ Namespace exists: kube-system
#   ✓ Workloads detected: 7 pods (system components)
#   ⚠️  No VPA/HPA (system namespace)
#   ✓ Using pod resource limits
#   ✓ Total CPU: 2.5 cores (apiserver, controller, scheduler)
#   ✓ Total memory: 5Gi
#   ✓ Pod count: 7
# 
# [2/4] CALCULATION PHASE
#   ✓ Safety buffer (20%):
#       - CPU: 2.5 → 3 cores
#       - Memory: 5Gi → 6Gi
#       - Pods: 7 → 9 (rounded to 10 for safety)
# 
# [3/4] HARDENING PHASE
#   ✓ Applied ResourceQuota: 3 CPU, 6Gi memory, 10 pods
#   ✓ Skipped NetworkPolicy (system namespace)
#   ✓ Applied PSS labels: privileged (system components need access)
# 
# 🔒 kube-system LOCKED - No new workloads can be added

# ============================================================================
# STEP 4: Lock default namespace (empty)
# ============================================================================
kubectl label namespace default \
  moai.forge.io/managed=true \
  moai.forge.io/type=default \
  moai.forge.io/hardened=false

./namespace-hardening.sh --name default --skip-vpa --skip-hpa

# Output:
# [1/4] MEASUREMENT PHASE
#   ⚠️  No workloads detected in namespace default
#   ⚠️  Setting minimal quota (1 CPU, 1Gi, 3 pods)
# 
# [3/4] HARDENING PHASE
#   ✓ Applied ResourceQuota: 1 CPU, 1Gi memory, 3 pods, 0 PVCs
# 
# 🔒 default LOCKED - Prevents accidental deployments

# ============================================================================
# STEP 5: Verify system namespace lock
# ============================================================================
./namespace-verify.sh --name kube-system

# Try to deploy to kube-system (should fail)
kubectl run test-pod --image=nginx -n kube-system
# Error from server (Forbidden): pods "test-pod" is forbidden: 
# exceeded quota: namespace-quota, requested: pods=1, used: pods=7, limited: pods=10
```

**Purpose:** Prevent operators from accidentally deploying workloads to system namespaces, forcing proper namespace hygiene.

---

### ⚡ Workflow 4: KEDA Namespace (Pre-Sized Infrastructure)

**Scenario:** Deploy KEDA event-driven autoscaler with HA configuration.

```bash
# ============================================================================
# STEP 1: Create KEDA namespace (pre-sized for 3x3 HA)
# ============================================================================
./namespace-create.sh \
  --name keda \
  --type keda \
  --owner team-platform

# ============================================================================
# STEP 2: Install KEDA via Helm (HA mode)
# ============================================================================
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda \
  --namespace keda \
  --set replicaCount=3 \
  --set metricsServer.replicaCount=3 \
  --set webhooks.replicaCount=3 \
  --set resources.operator.limits.cpu=1 \
  --set resources.operator.limits.memory=1Gi \
  --set resources.metricServer.limits.cpu=1 \
  --set resources.metricServer.limits.memory=1Gi \
  --set resources.webhooks.limits.cpu=500m \
  --set resources.webhooks.limits.memory=512Mi

# Verify deployment
kubectl get pods -n keda
# NAME                                      READY   STATUS    RESTARTS   AGE
# keda-operator-7d9f8c5b6f-abc              1/1     Running   0          1m
# keda-operator-7d9f8c5b6f-def              1/1     Running   0          1m
# keda-operator-7d9f8c5b6f-ghi              1/1     Running   0          1m
# keda-metrics-apiserver-6b8d7c9f5d-jkl     1/1     Running   0          1m
# keda-metrics-apiserver-6b8d7c9f5d-mno     1/1     Running   0          1m
# keda-metrics-apiserver-6b8d7c9f5d-pqr     1/1     Running   0          1m
# keda-admission-webhooks-5c8f9d6b7c-stu    1/1     Running   0          1m
# keda-admission-webhooks-5c8f9d6b7c-vwx    1/1     Running   0          1m
# keda-admission-webhooks-5c8f9d6b7c-yz     1/1     Running   0          1m

# ============================================================================
# STEP 3: Harden KEDA namespace
# ============================================================================
./namespace-hardening.sh --name keda --skip-vpa

# Output:
# [1/4] MEASUREMENT PHASE
#   ✓ Detected 9 pods (3 deployments × 3 replicas)
#   ✓ Total CPU: 2.5 cores (1 + 1 + 0.5 per deployment)
#   ✓ Total memory: 7.5Gi (1Gi + 1Gi + 512Mi per deployment)
# 
# [2/4] CALCULATION PHASE
#   ✓ Safety buffer (20%):
#       - CPU: 2.5 → 3 cores
#       - Memory: 7.5Gi → 9Gi
#       - Pods: 9 → 11 (rounded to 12 for headroom)
# 
# [3/4] HARDENING PHASE
#   ✓ Applied ResourceQuota: 3 CPU, 9Gi memory, 12 pods
#   ✓ Applied NetworkPolicy: default-deny-all
#   ✓ Applied PSS labels: baseline

# ============================================================================
# STEP 4: Verify KEDA can scale workloads in other namespaces
# ============================================================================
# KEDA operates cluster-wide, this quota only affects KEDA's own pods

kubectl get scaledobjects -A
# Should work - KEDA not restricted by its own namespace quota
```

---

## Emergency Operations

### 🚨 Workflow 5: Emergency Quota Increase (Black Friday Traffic)

**Scenario:** Payment service needs urgent scaling for Black Friday, current quota too restrictive.

```bash
# ============================================================================
# CURRENT STATE: Quota exhausted
# ============================================================================
kubectl get resourcequota namespace-quota -n payment-service
# Resource                Used   Hard
# --------                ----   ----
# limits.cpu              4      4    ← AT LIMIT
# limits.memory           8Gi    8Gi  ← AT LIMIT
# pods                    19     20   ← NEAR LIMIT

# Try to scale deployment
kubectl scale deployment payment-api -n payment-service --replicas=15
# Error: exceeded quota: namespace-quota

# ============================================================================
# STEP 1: Initiate emergency update
# ============================================================================
./namespace-update.sh --name payment-service --auto

# Output:
# === Namespace Update: payment-service ===
# 
# Current quota:
#   CPU: 4 cores (100% used)
#   Memory: 8Gi (100% used)
#   Pods: 20 (95% used)
# 
# [1/2] EXPANSION PHASE
#   ✓ Backed up quota to: /tmp/payment-service-quota-backup-20260211.yaml
#   ✓ Removed ResourceQuota (TEMPORARY PERMISSIVE STATE)
#   ✓ Namespace is now UNHARDENED
# 
# 🚀 You can now scale workloads freely
# 
# Press ENTER when ready to re-measure and re-harden...

# ============================================================================
# STEP 2: Scale deployment (no quota blocking)
# ============================================================================
kubectl scale deployment payment-api -n payment-service --replicas=15
# deployment.apps/payment-api scaled

# Update HPA for higher max
kubectl patch hpa payment-api-hpa -n payment-service -p '{"spec":{"maxReplicas":20}}'
# horizontalpodautoscaler.autoscaling/payment-api-hpa patched

# Wait for pods to stabilize
kubectl get pods -n payment-service
# NAME                           READY   STATUS    RESTARTS   AGE
# payment-api-xxx (15 pods running)

# ============================================================================
# STEP 3: Press ENTER to re-harden
# ============================================================================
# [User presses ENTER]

# [2/2] RE-HARDENING PHASE
#   ✓ Measuring current workloads...
#   ✓ VPA recommendations:
#       - payment-api: CPU 1 core, Memory 2Gi (per pod)
#   ✓ New totals (with 20% buffer):
#       - CPU: 15 pods × 1 core × 1.2 = 18 cores
#       - Memory: 15 pods × 2Gi × 1.2 = 36Gi
#       - Pods: 20 max replicas + 5 buffer = 25 pods
#   ✓ Applied new ResourceQuota
# 
# === Update Complete ===
# 
# Quota changes:
#   CPU: 4 → 18 cores (+350%)
#   Memory: 8Gi → 36Gi (+350%)
#   Pods: 20 → 25 (+25%)

# ============================================================================
# STEP 4: Verify new quota
# ============================================================================
kubectl describe resourcequota namespace-quota -n payment-service
# Resource                Used   Hard
# --------                ----   ----
# limits.cpu              15     18   ← New limit
# limits.memory           30Gi   36Gi ← New limit
# pods                    15     25   ← New limit

# ============================================================================
# STEP 5: Monitor during Black Friday
# ============================================================================
watch kubectl top pods -n payment-service
# Every 2.0s: kubectl top pods -n payment-service
# 
# NAME                           CPU    MEMORY
# payment-api-xxx                950m   1.8Gi
# (15 pods, total ~14 CPU, ~27Gi - within new quota)
```

**Timeline:**
- Detection: Immediate (monitoring alerts)
- Update execution: 2-3 minutes
- Scaling: 5-10 minutes (pod startup)
- Re-hardening: 30 seconds

**Total emergency response: ~10 minutes**

---

### 🔧 Workflow 6: Manual Quota Override (Non-Auto Mode)

**Scenario:** Platform team needs to set specific quotas based on capacity planning.

```bash
# ============================================================================
# Manual quota increase with explicit values
# ============================================================================
./namespace-update.sh \
  --name analytics-pipeline \
  --cpu-limit 32 \
  --memory-limit 64Gi \
  --max-pods 100

# Output:
# === Namespace Update: analytics-pipeline ===
# 
# Current quota:
#   CPU: 16 cores
#   Memory: 32Gi
#   Pods: 50
# 
# Requested new quota:
#   CPU: 32 cores (+100%)
#   Memory: 64Gi (+100%)
#   Pods: 100 (+100%)
# 
# ⚠️  Large increase detected (>50% change)
# Require manual confirmation: [yes/no] yes
# 
# [1/2] EXPANSION PHASE
#   ✓ Removed current quota
# 
# [2/2] HARDENING PHASE
#   ✓ Applied new quota: 32 CPU, 64Gi, 100 pods
# 
# === Update Complete ===

# Verify
kubectl get resourcequota namespace-quota -n analytics-pipeline -o yaml
```

---

## Compliance & Monitoring

### 📊 Workflow 7: Daily Compliance Check (Automated)

**Scenario:** Platform team runs daily compliance verification.

```bash
# ============================================================================
# Cron job: Daily at 8 AM
# ============================================================================
#!/bin/bash
# /opt/scripts/daily-namespace-compliance.sh

REPORT_DIR="/var/reports/namespace-compliance"
REPORT_FILE="$REPORT_DIR/compliance-$(date +%Y%m%d).json"
ALERT_WEBHOOK="https://slack.com/api/webhooks/xxx"

# Create report directory
mkdir -p "$REPORT_DIR"

# Generate compliance report
/opt/forge-helpers/scripts/namespace-verify.sh \
  --all \
  --report "$REPORT_FILE"

EXIT_CODE=$?

# Parse report
VIOLATIONS=$(jq -r '.summary.violations' "$REPORT_FILE")
UNHARDENED=$(jq -r '.summary.unhardened' "$REPORT_FILE")

# Send Slack alert if violations found
if [[ "$VIOLATIONS" -gt 0 ]] || [[ "$UNHARDENED" -gt 0 ]]; then
  cat <<EOF | curl -X POST -H 'Content-type: application/json' \
    --data @- "$ALERT_WEBHOOK"
{
  "text": "🚨 Namespace Compliance Alert",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Namespace Compliance Issues Detected*\n• Violations: $VIOLATIONS\n• Unhardened: $UNHARDENED\n\nReport: \`$REPORT_FILE\`"
      }
    }
  ]
}
EOF
fi

# Clean up old reports (keep 30 days)
find "$REPORT_DIR" -name "compliance-*.json" -mtime +30 -delete

exit $EXIT_CODE
```

**Crontab entry:**
```cron
0 8 * * * /opt/scripts/daily-namespace-compliance.sh
```

**Sample Report Output:**
```json
{
  "generated_at": "2026-02-11T08:00:00Z",
  "summary": {
    "total_namespaces": 15,
    "hardened": 14,
    "unhardened": 1,
    "violations": 1,
    "warnings": 2
  },
  "namespaces": [
    {
      "name": "forgotten-app",
      "type": "application",
      "hardened": false,
      "created_at": "2026-02-09T10:00:00Z",
      "age_hours": 46,
      "compliance": "VIOLATION",
      "reason": "Unhardened for >4 hours",
      "action": "./namespace-hardening.sh --name forgotten-app"
    },
    {
      "name": "payment-service",
      "type": "application",
      "hardened": true,
      "quota": {
        "cpu": "18",
        "memory": "36Gi",
        "pods": "25"
      },
      "usage": {
        "cpu": "15",
        "memory": "30Gi",
        "pods": "15"
      },
      "usage_percent": {
        "cpu": 83,
        "memory": 83,
        "pods": 60
      },
      "compliance": "WARNING",
      "reason": "CPU/Memory usage >80%",
      "action": "Monitor for capacity increase"
    }
  ]
}
```

---

### 🔍 Workflow 8: Incident Response - Unhardened Namespace Alert

**Scenario:** Monitoring detects namespace unhardened for 6 hours.

```bash
# ============================================================================
# Alert received: "Namespace 'analytics-v2' unhardened for 6 hours"
# ============================================================================

# STEP 1: Investigate namespace state
kubectl get namespace analytics-v2 -o yaml | grep moai.forge.io
# moai.forge.io/created-at: "2026-02-11T02:00:00Z"
# moai.forge.io/hardened: "false"
# moai.forge.io/type: "application"

# STEP 2: Check for workloads
kubectl get pods -n analytics-v2
# NAME                          READY   STATUS    RESTARTS   AGE
# data-processor-xxx            1/1     Running   0          6h
# data-processor-yyy            1/1     Running   0          6h

# STEP 3: Check if VPA/HPA available
kubectl get vpa,hpa -n analytics-v2
# NAME                                 MODE   CPU    MEMORY   AGE
# verticalpodautoscaler/processor-vpa  Auto   2000m  4Gi      5h

# STEP 4: Harden immediately
./namespace-hardening.sh --name analytics-v2

# STEP 5: Document in incident log
echo "$(date): Hardened analytics-v2 after 6-hour delay. Root cause: Developer forgot step 3 of deployment workflow." >> /var/log/namespace-incidents.log

# STEP 6: Follow-up action
# - Update deployment runbook
# - Add pre-commit hook to check hardening status
# - Consider automated hardening via GitOps sync hook
```

---

## GitOps Integration

### 🔄 Workflow 9: ArgoCD Sync Hook for Auto-Hardening

**Scenario:** Automatically harden namespace after ArgoCD deploys application.

**ArgoCD Application with PostSync Hook:**

```yaml
# argocd-app-payment-service.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/payment-api
    targetRevision: main
    path: charts/payment-api
  destination:
    server: https://kubernetes.default.svc
    namespace: payment-service
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=false  # We create via namespace-create.sh
    
    # PostSync hook to harden namespace
    hooks:
    - name: namespace-hardening
      enabled: true
      hook: PostSync
      hookType: Job
      hookDeletePolicy: BeforeHookCreation
      manifest: |
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: namespace-hardening-hook
          namespace: payment-service
        spec:
          template:
            spec:
              serviceAccountName: namespace-hardening-sa
              containers:
              - name: hardening
                image: myregistry/namespace-tools:v2.0.0
                command:
                - /bin/bash
                - -c
                - |
                  # Wait for VPA to have data (check age)
                  VPA_COUNT=$(kubectl get vpa -n payment-service --no-headers | wc -l)
                  if [[ "$VPA_COUNT" -gt 0 ]]; then
                    echo "VPA detected, checking data age..."
                    # In production, would check VPA age > 7 days
                    # For demo, proceed if VPA exists
                    /opt/forge-helpers/scripts/namespace-hardening.sh --name payment-service
                  else
                    echo "No VPA yet, scheduling delayed hardening..."
                    # Create CronJob to check again in 24 hours
                    kubectl create job namespace-hardening-retry-$(date +%s) \
                      --from=cronjob/namespace-hardening-scheduler \
                      -n payment-service
                  fi
              restartPolicy: Never
          backoffLimit: 3
```

**ServiceAccount for Hardening Job:**

```yaml
# namespace-hardening-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: namespace-hardening-sa
  namespace: payment-service
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: namespace-hardening
rules:
- apiGroups: [""]
  resources: ["namespaces", "resourcequotas", "networkpolicies"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: ["autoscaling.k8s.io"]
  resources: ["verticalpodautoscalers"]
  verbs: ["get", "list"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: namespace-hardening-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: namespace-hardening
subjects:
- kind: ServiceAccount
  name: namespace-hardening-sa
  namespace: payment-service
```

**Workflow:**
1. Developer commits code → GitHub
2. ArgoCD detects change → Syncs application
3. PostSync hook runs → Calls namespace-hardening.sh
4. Namespace automatically hardened
5. ArgoCD marks sync as complete

---

## Multi-Environment Patterns

### 🌍 Workflow 10: Multi-Environment Namespace Management

**Scenario:** Same application deployed to dev, staging, production with different quotas.

```bash
# ============================================================================
# DEVELOPMENT ENVIRONMENT (Small quotas, fast iteration)
# ============================================================================
./namespace-create.sh \
  --name payment-service \
  --type application \
  --owner team-payments \
  --environment dev

# Deploy dev version (1 replica, no HPA)
helm install payment-api ./charts/payment-api \
  --namespace payment-service \
  --values values-dev.yaml \
  --set replicas=1 \
  --set autoscaling.enabled=false

# Harden with minimal resources
./namespace-hardening.sh --name payment-service --skip-vpa --skip-hpa
# Result: ~1 CPU, 2Gi memory, 3 pods

# ============================================================================
# STAGING ENVIRONMENT (Medium quotas, mirrors production topology)
# ============================================================================
./namespace-create.sh \
  --name payment-service \
  --type application \
  --owner team-payments \
  --environment staging

# Deploy staging version (3 replicas, HPA enabled)
helm install payment-api ./charts/payment-api \
  --namespace payment-service \
  --values values-staging.yaml \
  --set replicas=3 \
  --set autoscaling.enabled=true \
  --set autoscaling.maxReplicas=5

# Wait 24 hours for VPA data
sleep 86400  # In reality, would be manual

# Harden with measured resources
./namespace-hardening.sh --name payment-service
# Result: ~4 CPU, 8Gi memory, 10 pods

# ============================================================================
# PRODUCTION ENVIRONMENT (Large quotas, HA, full observability)
# ============================================================================
./namespace-create.sh \
  --name payment-service \
  --type application \
  --owner team-payments \
  --environment production

# Deploy production version (3 replicas, HPA, VPA, Goldilocks)
kubectl label namespace payment-service goldilocks.fairwinds.com/enabled=true

helm install payment-api ./charts/payment-api \
  --namespace payment-service \
  --values values-production.yaml \
  --set replicas=3 \
  --set autoscaling.enabled=true \
  --set autoscaling.maxReplicas=20 \
  --set vpa.enabled=true

# Wait 7 days for accurate VPA data
sleep 604800  # In reality, would be manual

# Harden with full measurement
./namespace-hardening.sh --name payment-service
# Result: ~18 CPU, 36Gi memory, 25 pods
```

**Summary Table:**

| Environment | Replicas | HPA Max | VPA | Goldilocks | Hardened Quota |
|-------------|----------|---------|-----|------------|----------------|
| Dev         | 1        | N/A     | ❌  | ❌         | 1 CPU, 2Gi, 3 pods |
| Staging     | 3        | 5       | ✅  | ❌         | 4 CPU, 8Gi, 10 pods |
| Production  | 3        | 20      | ✅  | ✅         | 18 CPU, 36Gi, 25 pods |

---

## Troubleshooting Workflows

### 🔧 Workflow 11: Hardening Failed - No Workloads Detected

**Error:**
```
❌ ERROR: No workloads detected in namespace 'my-app'
Cannot measure resources without running pods.
```

**Resolution:**

```bash
# STEP 1: Verify namespace exists
kubectl get namespace my-app
# NAME     STATUS   AGE
# my-app   Active   5m

# STEP 2: Check for deployments/statefulsets
kubectl get deployments,statefulsets,daemonsets -n my-app
# No resources found in my-app namespace.

# STEP 3: Root cause - forgot to deploy application!
# Deploy application first
helm install my-app ./chart -n my-app

# STEP 4: Verify pods running
kubectl get pods -n my-app
# NAME                      READY   STATUS    RESTARTS   AGE
# my-app-7d9f8c5b6f-abcde   1/1     Running   0          30s

# STEP 5: Retry hardening
./namespace-hardening.sh --name my-app
# ✓ Success
```

---

### 🔧 Workflow 12: VPA Recommendations Immature

**Error:**
```
⚠️  WARNING: VPA 'my-app-vpa' only 2 hours old (need 168 hours)
Recommendations may not be accurate yet
```

**Resolution Options:**

**Option 1: Wait for mature data (recommended for production)**
```bash
# Wait 7 days, then re-run
sleep 604800
./namespace-hardening.sh --name my-app
```

**Option 2: Skip VPA, use pod limits (acceptable for dev/staging)**
```bash
./namespace-hardening.sh --name my-app --skip-vpa
# Uses current pod resource limits instead
```

**Option 3: Force hardening with current VPA data (not recommended)**
```bash
# Edit namespace-hardening.sh to reduce min_age_seconds
./namespace-hardening.sh --name my-app
# Accept warning, proceed with immature data
```

---

### 🔧 Workflow 13: Quota Sanity Check Failed

**Error:**
```
❌ ERROR: CPU quota 128 exceeds maximum 64 cores
Review VPA recommendations or increase --max-cpu-limit
```

**Resolution:**

```bash
# STEP 1: Investigate VPA recommendations
kubectl get vpa -n my-app -o yaml

# Output:
# upperBound:
#   cpu: 50000m  ← 50 cores per pod!
#   memory: 100Gi

# STEP 2: Check deployment replica count
kubectl get deployment my-app -n my-app -o yaml | grep replicas
# replicas: 3

# STEP 3: Calculate total
# 3 replicas × 50 cores = 150 cores
# 150 × 1.2 buffer = 180 cores
# 180 > 64 max → FAIL

# STEP 4: Root cause analysis
# Option A: VPA misconfigured (bug/attack)
# Option B: Legitimate large workload (ML training)

# STEP 5A: If VPA bug, reset VPA
kubectl delete vpa my-app-vpa -n my-app
kubectl apply -f vpa-config-fixed.yaml

# STEP 5B: If legitimate, increase cluster max
./namespace-hardening.sh --name my-app --max-cpu-limit 200

# STEP 6: Document exception
echo "$(date): Approved 200 CPU limit for my-app (ML training workload)" >> /var/log/quota-exceptions.log
```

---

## Summary

### 📊 Workflow Patterns

| Workflow | Duration | Automation | Complexity |
|----------|----------|------------|------------|
| New Application | ~1 hour (dev) / ~2 days (prod) | Medium | Low |
| Database (Middleware) | ~30 min | Medium | Low |
| Lock System NS | ~5 min | High | Low |
| KEDA/Kyverno (Infra) | ~10 min | High | Medium |
| Emergency Quota Increase | ~10 min | Low | Medium |
| GitOps Auto-Hardening | Automatic | High | High |
| Daily Compliance | Automatic | High | Low |
| Multi-Environment | ~3 days (all envs) | Medium | Medium |

### ✅ Best Practices Summary

1. **Always create → deploy → harden** - Never skip hardening step
2. **Wait for VPA data in production** - 7 days minimum for accuracy
3. **Use --dry-run first** - Preview changes before applying
4. **Monitor unhardened namespaces** - Alert after 4-hour grace period
5. **GitOps auto-hardening** - Integrate with ArgoCD/FluxCD sync hooks
6. **Document exceptions** - Audit trail for manual overrides
7. **Regular compliance checks** - Daily verification recommended
8. **Emergency procedures** - Practice quota increase workflows

---

**Document Version:** 2.0.0  
**Last Updated:** 2026-02-11  
**Author:** Forge Platform Team  
**Status:** Active
