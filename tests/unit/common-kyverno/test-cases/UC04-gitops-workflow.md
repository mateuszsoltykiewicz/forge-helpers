# UC-KYVERNO-04: GitOps Workflow (Full Enforcement)

## Description
Test complete GitOps workflow with ALL policies enabled simultaneously. This represents production-ready configuration where:
- Users cannot exec/port-forward/proxy/debug/attach to pods
- Users cannot create/update/delete workloads directly
- Only CI/CD ServiceAccounts (deployment-job, flux-cd) can manage resources
- Debug-proxy SA provides emergency access to API operations

This UC validates that all policies work together without conflicts.

## Prerequisites
- Kyverno installed ✅
- test-app namespace created
- test-blocked namespace created (for full enforcement)
- ci-cd namespace with deployment-job SA
- flux-system namespace with flux-cd SA (optional)
- kube-system namespace with debug-proxy SA

## Test Scenario

### Setup
1. Install common-kyverno with ALL policies enabled
2. Test complete workflow:
   - User attempts manual deployment → BLOCKED
   - User attempts kubectl exec → BLOCKED
   - deployment-job creates deployment → ALLOWED
   - debug-proxy performs debugging → ALLOWED
   - User attempts to modify deployment → BLOCKED
3. Verify all PolicyReports show violations

### Expected Results
- ✅ User CREATE deployment is **BLOCKED** (blockWorkloadModifications)
- ✅ User UPDATE deployment is **BLOCKED** (blockWorkloadModifications)
- ✅ User DELETE deployment is **BLOCKED** (blockWorkloadModifications)
- ✅ User kubectl exec is **BLOCKED** (blockExec)
- ✅ User kubectl port-forward is **BLOCKED** (blockPortForward)
- ✅ deployment-job CREATE deployment is **ALLOWED**
- ✅ flux-cd CREATE deployment is **ALLOWED**
- ✅ debug-proxy kubectl exec is **ALLOWED**
- ✅ debug-proxy kubectl port-forward is **ALLOWED**
- ✅ All 5 ClusterPolicies active
- ✅ PolicyReports show violations for all blocked operations

## Values Configuration

File: `values/uc04-gitops-full.yaml`

```yaml
forge:
  customer: "test"
  project: "kyverno"
  environment: "production"
  application: "gitops-full"

kyverno:
  # ======================================================
  # API RESTRICTIONS - All enabled for production
  # ======================================================
  apiRestrictions:
    # Block kubectl exec (except debug-proxy)
    blockExec:
      enabled: true
      action: "enforce"
      severity: "medium"
      failurePolicy: "Fail"
      message: >-
        kubectl exec is blocked in production.
        Use debug-proxy ServiceAccount for emergency debugging.
        All exec operations are audited.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
        - "kube-node-lease"
      excludeUsers: []
    
    # Block kubectl port-forward (except debug-proxy)
    blockPortForward:
      enabled: true
      action: "enforce"
      severity: "low"
      message: >-
        kubectl port-forward is blocked in production.
        Use service endpoints or debug-proxy for debugging.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
    
    # Block kubectl proxy (except debug-proxy)
    blockProxy:
      enabled: true
      action: "enforce"
      severity: "low"
      message: >-
        kubectl proxy is blocked in production.
        Use debug-proxy ServiceAccount for API access.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
    
    # Block ephemeral containers (kubectl debug)
    blockEphemeralContainers:
      enabled: true
      action: "enforce"
      severity: "medium"
      message: >-
        Ephemeral containers (kubectl debug) are blocked in production.
        Use debug-proxy ServiceAccount for debugging.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
    
    # Block kubectl attach (except debug-proxy)
    blockAttach:
      enabled: true
      action: "enforce"
      severity: "low"
      message: >-
        kubectl attach is blocked in production.
        Use logs or debug-proxy ServiceAccount.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
  
  # ======================================================
  # RESOURCE MANAGEMENT - All enabled for production
  # ======================================================
  resourceManagement:
    # Block direct workload modifications (enforce GitOps)
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      severity: "high"
      message: >-
        Direct workload modifications are blocked in production.
        All deployments must go through GitOps pipeline.
        Push changes to Git and let CI/CD deploy.
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
        - "kube-node-lease"
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
        - "system:serviceaccount:flux-system:flux-cd"
        - "system:serviceaccount:flux-system:helm-controller"
        - "system:serviceaccount:flux-system:kustomize-controller"
      excludeUsers: []
      annotations:
        gitops-policy: "enforced"
        environment: "production"
    
    # Additional policies (optional - can enable for stricter control)
    blockNetworkingModifications:
      enabled: false
    
    blockConfigModifications:
      enabled: false
    
    blockStorageModifications:
      enabled: false
    
    blockRBACModifications:
      enabled: false
  
  # ======================================================
  # DEBUG PROXY - Optional helper pod
  # ======================================================
  debugProxy:
    enabled: true
    namespace: "kube-system"
    serviceAccount: "debug-proxy"
    image: "bitnami/kubectl:latest"
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
    annotations:
      description: "Emergency debug proxy for production"
      incident-response: "true"
```

## Test Steps

### 1. Install Chart

```bash
# From tests/unit/common-kyverno
helm install test-kyverno-uc04 \
  ../../../../charts/common-kyverno \
  -f values/uc04-gitops-full.yaml \
  --namespace test-blocked \
  --create-namespace \
  --wait --timeout 3m
```

**Note**: Using `test-blocked` namespace to represent production with full enforcement.

### 2. Verify All Policies Created

```bash
# List all block policies
kubectl get clusterpolicy | grep block

# Expected: 6 policies total
# - block-kubectl-exec
# - block-kubectl-port-forward
# - block-kubectl-proxy
# - block-ephemeral-containers
# - block-kubectl-attach
# - block-workload-modifications

# Check all are in enforce mode
for policy in $(kubectl get clusterpolicy -o name | grep block); do
  echo "=== $policy ==="
  kubectl get $policy -o jsonpath='{.spec.validationFailureAction}'
  echo ""
done

# All should return: Enforce
```

### 3. Test User Workflow - Step 1: Try Manual Deployment (Should FAIL)

```bash
# Scenario: Developer tries to deploy directly (bad practice)

info "Developer attempting manual deployment..."
kubectl create deployment manual-app --image=nginx:alpine -n test-blocked

# Expected: BLOCKED by blockWorkloadModifications policy
# Error: "Direct workload modifications are blocked in production..."
```

### 4. Test User Workflow - Step 2: Try kubectl exec (Should FAIL)

```bash
# First, create a test pod using deployment-job (we'll test this later)
# For now, assume pod exists

POD_NAME=$(kubectl get pod -n test-blocked -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "none")

if [ "$POD_NAME" != "none" ]; then
  info "Developer attempting kubectl exec..."
  kubectl exec -n test-blocked $POD_NAME -- ls
  
  # Expected: BLOCKED by blockExec policy
  # Error: "kubectl exec is blocked in production..."
else
  echo "No pod yet to test exec (expected at this stage)"
fi
```

### 5. Test GitOps Workflow - CI/CD Deployment (Should SUCCEED)

```bash
# Scenario: Proper GitOps workflow
# 1. Developer pushes to Git
# 2. CI/CD pipeline triggers
# 3. deployment-job SA performs deployment

info "CI/CD pipeline deploying application..."

# Create token for deployment-job SA
DEPLOY_TOKEN=$(kubectl create token deployment-job -n ci-cd --duration=1h)

# Deploy application using Helm (simulating CI/CD)
cat <<EOF > /tmp/test-app-values.yaml
replicaCount: 2
image:
  repository: nginx
  tag: alpine
service:
  type: ClusterIP
  port: 80
EOF

# Option 1: Deploy with kubectl (simple)
kubectl --token=$DEPLOY_TOKEN create deployment gitops-app \
  --image=nginx:alpine \
  --replicas=2 \
  -n test-blocked

# Expected: SUCCESS
# Output: deployment.apps/gitops-app created

# Verify deployment exists
kubectl get deployment gitops-app -n test-blocked

# Verify pods are running
kubectl get pods -n test-blocked -l app=gitops-app
```

### 6. Test User Workflow - Step 3: Try to Scale (Should FAIL)

```bash
# Scenario: Developer tries to scale directly (bypass GitOps)

info "Developer attempting to scale deployment..."
kubectl scale deployment gitops-app --replicas=5 -n test-blocked

# Expected: BLOCKED by blockWorkloadModifications policy
# Error: "Direct workload modifications are blocked in production..."

# Correct way: Update in Git → CI/CD scales deployment
```

### 7. Test User Workflow - Step 4: Try kubectl exec on GitOps app (Should FAIL)

```bash
# Scenario: Developer tries to debug directly

POD_NAME=$(kubectl get pod -n test-blocked -l app=gitops-app -o jsonpath='{.items[0].metadata.name}')

info "Developer attempting kubectl exec on gitops-app..."
kubectl exec -n test-blocked $POD_NAME -- ls

# Expected: BLOCKED by blockExec policy
# Error: "kubectl exec is blocked in production..."
```

### 8. Test Debug-Proxy - Emergency Debugging (Should SUCCEED)

```bash
# Scenario: Production issue, on-call engineer needs to debug

info "On-call engineer using debug-proxy for emergency debugging..."

# Create debug-proxy token
DEBUG_TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=30m)

# Perform debugging operations
echo "Test 1: kubectl exec with debug-proxy"
kubectl --token=$DEBUG_TOKEN exec -n test-blocked $POD_NAME -- ls /usr/share/nginx/html

# Expected: SUCCESS (debug-proxy excluded from blockExec)

echo "Test 2: kubectl port-forward with debug-proxy"
kubectl --token=$DEBUG_TOKEN port-forward -n test-blocked $POD_NAME 9999:80 &
PF_PID=$!
sleep 2

curl -s http://localhost:9999 | head -n 5
kill $PF_PID 2>/dev/null || true

# Expected: SUCCESS (debug-proxy excluded from blockPortForward)

echo "Test 3: kubectl logs (always allowed)"
kubectl logs -n test-blocked $POD_NAME --tail=20

# Expected: SUCCESS (logs not restricted)
```

### 9. Test flux-cd SA - GitOps Operator (Should SUCCEED)

```bash
# Scenario: Flux CD reconciling application

if kubectl get namespace flux-system &> /dev/null && \
   kubectl get sa flux-cd -n flux-system &> /dev/null; then
  
  info "Flux CD reconciling application..."
  
  FLUX_TOKEN=$(kubectl create token flux-cd -n flux-system --duration=1h)
  
  # Flux CD creates/updates deployment
  kubectl --token=$FLUX_TOKEN create deployment flux-app \
    --image=nginx:alpine \
    -n test-blocked
  
  # Expected: SUCCESS (flux-cd excluded from blockWorkloadModifications)
  
  # Flux CD updates deployment
  kubectl --token=$FLUX_TOKEN set image deployment/flux-app \
    nginx=nginx:1.25-alpine \
    -n test-blocked
  
  # Expected: SUCCESS
else
  echo "flux-system namespace or SA not available (optional test)"
fi
```

### 10. Test User Workflow - Step 5: Try to Delete (Should FAIL)

```bash
# Scenario: Developer tries to delete deployment directly

info "Developer attempting to delete deployment..."
kubectl delete deployment gitops-app -n test-blocked

# Expected: BLOCKED by blockWorkloadModifications policy
# Error: "Direct workload modifications are blocked in production..."

# Correct way: Remove from Git → CI/CD deletes deployment
```

### 11. Test CI/CD Cleanup (Should SUCCEED)

```bash
# Scenario: CI/CD pipeline removing old deployment

info "CI/CD pipeline cleaning up deployment..."

kubectl --token=$DEPLOY_TOKEN delete deployment gitops-app -n test-blocked

# Expected: SUCCESS (deployment-job can delete)

# Also cleanup flux-app if created
if kubectl get deployment flux-app -n test-blocked &> /dev/null; then
  kubectl --token=$FLUX_TOKEN delete deployment flux-app -n test-blocked 2>/dev/null || true
fi
```

### 12. Check PolicyReports

```bash
# Check for policy violations across all policies
kubectl get policyreport -n test-blocked

# Describe reports
kubectl describe policyreport -n test-blocked

# Get violation summary for each policy
echo "=== Violation Summary ==="
for policy in block-kubectl-exec block-kubectl-port-forward block-kubectl-proxy \
              block-ephemeral-containers block-kubectl-attach block-workload-modifications; do
  COUNT=$(kubectl get policyreport -n test-blocked -o json 2>/dev/null | \
          jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$policy\") | .policy" | \
          wc -l || echo "0")
  echo "$policy: $COUNT violations"
done

# Expected: Multiple violations for blockWorkloadModifications and blockExec
```

## Validation Criteria

| Test Case | Policy | Expected Result | Actual Result | Status |
|-----------|--------|----------------|---------------|--------|
| User CREATE deployment | blockWorkloadMods | BLOCKED | | |
| User UPDATE deployment | blockWorkloadMods | BLOCKED | | |
| User DELETE deployment | blockWorkloadMods | BLOCKED | | |
| User kubectl exec | blockExec | BLOCKED | | |
| User kubectl port-forward | blockPortForward | BLOCKED | | |
| deployment-job CREATE | blockWorkloadMods | ALLOWED | | |
| deployment-job UPDATE | blockWorkloadMods | ALLOWED | | |
| deployment-job DELETE | blockWorkloadMods | ALLOWED | | |
| debug-proxy exec | blockExec | ALLOWED | | |
| debug-proxy port-forward | blockPortForward | ALLOWED | | |
| flux-cd CREATE | blockWorkloadMods | ALLOWED | | |
| flux-cd UPDATE | blockWorkloadMods | ALLOWED | | |
| All 6 policies created | All | ✅ Created | | |
| All in enforce mode | All | ✅ Enforce | | |
| PolicyReports generated | All | ✅ Recorded | | |

## Cleanup

```bash
# Delete any remaining deployments (using tokens)
kubectl --token=$DEPLOY_TOKEN delete deployment --all -n test-blocked 2>/dev/null || true

# Uninstall chart
helm uninstall test-kyverno-uc04 -n test-blocked

# Verify all policies removed
kubectl get clusterpolicy | grep block
# Should return no results

# Verify debug-proxy pod removed
kubectl get deployment debug-proxy -n kube-system
# Should return NotFound
```

## Troubleshooting

### Issue: Policy conflicts

**Symptoms**: Some operations blocked unexpectedly, charts fail to install

**Possible causes**:
1. Multiple policies blocking same operation
2. Exclusions not properly configured
3. ServiceAccount names don't match

**Solution**:
```bash
# Check all exclusions across policies
for policy in $(kubectl get clusterpolicy -o name | grep block); do
  echo "=== $policy ==="
  kubectl get $policy -o jsonpath='{.spec.rules[0].exclude}' | jq .
done

# Verify ServiceAccount full names
kubectl get sa deployment-job -n ci-cd -o jsonpath='{.metadata.name}'
# Should output: deployment-job

# Full SA path should be: system:serviceaccount:ci-cd:deployment-job
```

### Issue: Helm operations blocked

**Symptoms**: Helm install/upgrade fails with policy violations

**Possible causes**:
1. Helm's SA not in exclusions
2. Helm performing operations as user context

**Solution**:
```bash
# Check Helm context
helm list -A --kube-context $(kubectl config current-context)

# If using service account for Helm, add to exclusions
# Update values to include: system:serviceaccount:kube-system:tiller (Helm 2)
# or the appropriate Helm 3 SA
```

### Issue: Debug-proxy pod cannot be created

**Symptoms**: Debug-proxy deployment not found after install

**Possible causes**:
1. blockWorkloadModifications blocking Helm
2. Helm's context not excluded

**Solution**:
```bash
# Check Helm release status
helm status test-kyverno-uc04 -n test-blocked

# Check events
kubectl get events -n kube-system | grep debug-proxy

# Manual workaround: Create before installing policies
kubectl create deployment debug-proxy \
  --image=bitnami/kubectl:latest \
  -n kube-system
kubectl set serviceaccount deployment debug-proxy debug-proxy -n kube-system

# Then install policies
```

## GitOps Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitOps Workflow                             │
└─────────────────────────────────────────────────────────────────┘

Developer                 Git Repository              CI/CD Pipeline
    │                           │                           │
    │  1. Push code            │                           │
    ├──────────────────────────>│                           │
    │                           │                           │
    │                           │  2. Webhook trigger       │
    │                           ├──────────────────────────>│
    │                           │                           │
    │                           │                           │  3. Build & Test
    │                           │                           │     deployment-job SA
    │                           │                           │
    │                           │                           │  4. Deploy via Helm
    │                           │                           ├───────────────┐
    │                           │                           │               │
    │  ❌ Direct deployment     │                           │               ▼
    │      BLOCKED              │                           │         Kubernetes
    │                           │                           │       (test-blocked)
    │                           │                           │               │
    │  ❌ kubectl exec          │                           │               │
    │      BLOCKED              │                           │    ✅ deployment-job
    │                           │                           │       CREATE allowed
    │  ❌ Scale/Update          │                           │               │
    │      BLOCKED              │                           │    ✅ Pods running
    │                           │                           │               │
    │                           │                           │               │
    │  ✅ debug-proxy exec      │                           │               │
    │      ALLOWED (emergency)  │                           │               │
    │                           │                           │               │
    └───────────────────────────┴───────────────────────────┴───────────────┘

Kyverno Policies:
  • blockWorkloadModifications: Enforce GitOps (only SA can deploy)
  • blockExec: Prevent direct container access (except debug-proxy)
  • blockPortForward: Prevent tunneling (except debug-proxy)
  • blockProxy: Prevent API proxy (except debug-proxy)
  • blockEphemeralContainers: Prevent debug containers (except debug-proxy)
  • blockAttach: Prevent container attach (except debug-proxy)
```

## Performance Metrics

- **Chart install time**: < 30 seconds (6 policies + deployment)
- **Policy enforcement time**: < 100ms per request
- **GitOps deployment time**: Normal Helm install time + policy validation (~5-10s)
- **Cleanup time**: < 20 seconds

## Real-World Production Configuration

This UC represents a production-ready Kyverno configuration suitable for:

1. **Production Clusters**: Full security enforcement
2. **Compliance Requirements**: PCI-DSS, SOC2, HIPAA
3. **Multi-Tenant Platforms**: Strict isolation
4. **Financial Services**: High security requirements
5. **Regulated Industries**: Audit trail required

## Integration Patterns

### Pattern 1: GitHub Actions CI/CD

```yaml
# .github/workflows/deploy.yaml
name: Deploy to Production
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Get deployment-job token
        run: |
          DEPLOY_TOKEN=$(kubectl create token deployment-job -n ci-cd --duration=15m)
          echo "::add-mask::$DEPLOY_TOKEN"
          echo "DEPLOY_TOKEN=$DEPLOY_TOKEN" >> $GITHUB_ENV
      
      - name: Deploy with Helm
        run: |
          helm upgrade --install myapp ./chart \
            --namespace production \
            --kube-token=$DEPLOY_TOKEN \
            --wait
```

### Pattern 2: Flux CD Integration

```yaml
# flux-system/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: fleet
  serviceAccountName: flux-cd  # Excluded from Kyverno policies
```

### Pattern 3: ArgoCD Integration

```yaml
# Add ArgoCD application-controller to exclusions
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      excludeServiceAccounts:
        - "system:serviceaccount:argocd:argocd-application-controller"
        - "system:serviceaccount:argocd:argocd-server"
```

## Related Use Cases

- UC-KYVERNO-01: Block kubectl exec
- UC-KYVERNO-02: Block Direct Deployments
- UC-KYVERNO-03: Debug Proxy Access
- UC-KYVERNO-05: Break-Glass Procedure (emergency override of UC04)
- UC-KYVERNO-06: Audit Mode (UC04 in audit-only mode)
- UC-ARGOCD-01: GitOps Application Deployment
- UC-MONITORING-02: Alert on Policy Violations

## References

- Kyverno Best Practices: https://kyverno.io/docs/writing-policies/best-practices/
- GitOps Principles: https://opengitops.dev/
- Kubernetes Security: https://kubernetes.io/docs/concepts/security/
- Common-Kyverno Full Stack: `charts/common-kyverno/PRODUCTION-SETUP.md`
