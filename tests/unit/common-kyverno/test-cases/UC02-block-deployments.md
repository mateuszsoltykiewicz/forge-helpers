# UC-KYVERNO-02: Block Direct Deployments (Resource Management)

## Description
Test GitOps-only pattern where regular users cannot create/modify/delete workload resources directly. Only excluded ServiceAccounts (deployment-job, flux-cd) can manage deployments.

## Prerequisites
- Kyverno installed ✅
- test-app namespace created
- ci-cd namespace created
- deployment-job ServiceAccount created
- flux-system namespace created
- flux-cd ServiceAccount created

## Test Scenario

### Setup
1. Install common-kyverno with blockWorkloadModifications policy enabled
2. Attempt to create deployment as regular user (should be blocked)
3. Attempt to create deployment as deployment-job SA (should be allowed)
4. Attempt to update deployment as user (should be blocked)
5. Attempt to delete deployment as user (should be blocked)

### Expected Results
- ✅ Regular user CREATE deployment is **BLOCKED**
- ✅ Regular user UPDATE deployment is **BLOCKED**
- ✅ Regular user DELETE deployment is **BLOCKED**
- ✅ deployment-job SA CREATE deployment is **ALLOWED**
- ✅ flux-cd SA CREATE deployment is **ALLOWED**
- ✅ Kyverno returns clear GitOps error message
- ✅ PolicyReport shows violations

## Values Configuration

File: `values/uc02-gitops-only.yaml`

```yaml
forge:
  customer: "test"
  project: "kyverno"
  environment: "test"
  application: "gitops-test"

kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      severity: "high"
      message: >-
        Direct workload modifications are not allowed. 
        Use Helm charts deployed via operators or deployment jobs.
        GitOps workflow required. Contact platform team for assistance.
      
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
        - "kube-node-lease"
      
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
        - "system:serviceaccount:flux-system:flux-cd"
      
      excludeUsers: []
      
      annotations:
        gitops-policy: "enforced"
    
    # Disable other resource management policies for this test
    blockNetworkingModifications:
      enabled: false
    
    blockConfigModifications:
      enabled: false
    
    blockStorageModifications:
      enabled: false
    
    blockRBACModifications:
      enabled: false
  
  # Disable API restrictions for this test
  apiRestrictions:
    blockExec:
      enabled: false
    blockPortForward:
      enabled: false
    blockProxy:
      enabled: false
    blockEphemeralContainers:
      enabled: false
    blockAttach:
      enabled: false
  
  # Disable debug proxy
  debugProxy:
    enabled: false
```

## Test Steps

### 1. Install Chart

```bash
# From tests/unit/common-kyverno
helm install test-kyverno-uc02 \
  ../../../../charts/common-kyverno \
  -f values/uc02-gitops-only.yaml \
  --namespace test-app \
  --create-namespace \
  --wait
```

### 2. Verify Policy Created

```bash
# Check ClusterPolicy exists
kubectl get clusterpolicy block-workload-modifications

# Verify policy details
kubectl describe clusterpolicy block-workload-modifications
```

Expected output:
```
Name:         block-workload-modifications
Annotations:  policies.kyverno.io/category: Security, Resource Management
              policies.kyverno.io/severity: high
              policies.kyverno.io/title: Block Workload Modifications
Spec:
  Background:                  false
  Validation Failure Action:   enforce
  Rules:
    Name:  block-workload-modifications
    Match:
      Any:
        Resources:
          Kinds:
            Deployment
            StatefulSet
            DaemonSet
            ReplicaSet
          Operations:
            CREATE
            UPDATE
            DELETE
```

### 3. Test Regular User CREATE (Should FAIL)

```bash
# Attempt to create deployment as regular user
kubectl create deployment blocked-test --image=nginx -n test-app

# Expected: BLOCKED
```

Expected error:
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 

policy ClusterPolicy/block-workload-modifications for resource violation:

block-workload-modifications:
  Direct workload modifications are not allowed. Use Helm charts deployed via 
  operators or deployment jobs. GitOps workflow required. 
  Contact platform team for assistance.
```

Alternative test with YAML:
```bash
cat <<EOF | kubectl apply -f - -n test-app
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blocked-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blocked
  template:
    metadata:
      labels:
        app: blocked
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
EOF

# Expected: BLOCKED
```

### 4. Test deployment-job SA CREATE (Should SUCCEED)

```bash
# Create token for deployment-job SA
DEPLOY_TOKEN=$(kubectl create token deployment-job -n ci-cd --duration=1h)

# Create deployment using deployment-job identity
kubectl --token=$DEPLOY_TOKEN create deployment allowed-test --image=nginx -n test-app

# Expected: SUCCESS
# Output: deployment.apps/allowed-test created
```

Verify deployment created:
```bash
kubectl get deployment allowed-test -n test-app
```

### 5. Test Regular User UPDATE (Should FAIL)

```bash
# Try to scale the deployment created by deployment-job
kubectl scale deployment allowed-test --replicas=3 -n test-app

# Expected: BLOCKED
```

Alternative update test:
```bash
# Try to change image
kubectl set image deployment/allowed-test nginx=nginx:latest -n test-app

# Expected: BLOCKED
```

### 6. Test Regular User DELETE (Should FAIL)

```bash
# Try to delete the deployment
kubectl delete deployment allowed-test -n test-app

# Expected: BLOCKED
```

### 7. Test flux-cd SA CREATE (Should SUCCEED)

```bash
# Create token for flux-cd SA
FLUX_TOKEN=$(kubectl create token flux-cd -n flux-system --duration=1h)

# Create deployment using flux-cd identity
kubectl --token=$FLUX_TOKEN create deployment flux-test --image=nginx -n test-app

# Expected: SUCCESS
```

### 8. Test StatefulSet, DaemonSet (Should Also Be BLOCKED)

```bash
# Test StatefulSet
kubectl create statefulset blocked-sts --image=nginx -n test-app

# Expected: BLOCKED

# Test DaemonSet (if allowed by RBAC)
cat <<EOF | kubectl apply -f - -n test-app
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: blocked-ds
spec:
  selector:
    matchLabels:
      app: blocked-ds
  template:
    metadata:
      labels:
        app: blocked-ds
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
EOF

# Expected: BLOCKED (by Kyverno, even if RBAC allows)
```

### 9. Test Excluded Namespace (Should SUCCEED)

```bash
# Create deployment in kube-system (excluded namespace)
kubectl create deployment test-excluded --image=nginx -n kube-system 2>/dev/null || \
  echo "RBAC may prevent this, but Kyverno should allow it"

# Note: This may fail due to RBAC, but should NOT fail due to Kyverno policy
```

### 10. Check PolicyReport

```bash
# Check for policy violations
kubectl get policyreport -n test-app

# Describe reports
kubectl describe policyreport -n test-app

# Should show violations for blocked deployment attempts
```

Expected PolicyReport:
```yaml
results:
  - message: "Direct workload modifications are not allowed..."
    policy: block-workload-modifications
    result: fail
    scored: true
    source: kyverno
    resource:
      kind: Deployment
      name: blocked-test
      namespace: test-app
```

## Validation Criteria

| Test Case | Expected Result | Actual Result | Status |
|-----------|----------------|---------------|--------|
| User CREATE deployment | BLOCKED | | |
| User UPDATE deployment | BLOCKED | | |
| User DELETE deployment | BLOCKED | | |
| User CREATE StatefulSet | BLOCKED | | |
| User CREATE DaemonSet | BLOCKED | | |
| deployment-job SA CREATE | ALLOWED | | |
| flux-cd SA CREATE | ALLOWED | | |
| kube-system deployment | ALLOWED | | |
| Policy created | ✅ Created | | |
| PolicyReport shows violations | ✅ Recorded | | |
| Clear error message | ✅ Descriptive | | |

## Cleanup

```bash
# Delete deployments created by SAs (if any)
kubectl --token=$DEPLOY_TOKEN delete deployment allowed-test -n test-app 2>/dev/null || true
kubectl --token=$FLUX_TOKEN delete deployment flux-test -n test-app 2>/dev/null || true

# Uninstall chart
helm uninstall test-kyverno-uc02 -n test-app

# Verify policy removed
kubectl get clusterpolicy block-workload-modifications
# Should return: NotFound
```

## Troubleshooting

### Issue: User can still create deployments

**Symptoms**: kubectl create deployment succeeds for regular users

**Possible causes**:
1. Policy action set to "audit" instead of "enforce"
2. User in excludeUsers list
3. Namespace in excludeNamespaces list
4. Kyverno webhooks not intercepting requests

**Solution**:
```bash
# Check policy action
kubectl get clusterpolicy block-workload-modifications -o yaml | grep validationFailureAction

# Check exclusions
kubectl get clusterpolicy block-workload-modifications -o yaml | grep -A 10 "exclude"

# Check Kyverno admission controller
kubectl get deploy -n kyverno kyverno-admission-controller
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50
```

### Issue: deployment-job SA also blocked

**Symptoms**: deployment-job ServiceAccount cannot create deployments

**Possible causes**:
1. SA not in excludeServiceAccounts list (typo in name)
2. Token not properly passed
3. Wrong namespace format in exclusion

**Solution**:
```bash
# Verify SA exists
kubectl get sa deployment-job -n ci-cd

# Check exclusion format (must be full path)
kubectl get clusterpolicy block-workload-modifications -o yaml | \
  grep "system:serviceaccount:ci-cd:deployment-job"

# Test token validity
kubectl --token=$DEPLOY_TOKEN auth can-i create deployments -n test-app
```

### Issue: RBAC prevents testing

**Symptoms**: Permission denied errors instead of Kyverno blocks

**Possible causes**:
1. Current user lacks RBAC permissions
2. ServiceAccount RBAC not configured

**Solution**:
```bash
# Test as cluster-admin (if available)
kubectl create deployment test --image=nginx -n test-app \
  --as=cluster-admin

# If still blocked, it's Kyverno (good!)
# If allowed, add cluster-admin to excludeUsers for testing

# Grant temporary RBAC to your user
kubectl create clusterrolebinding test-admin \
  --clusterrole=cluster-admin \
  --user=$(kubectl config view -o jsonpath='{.contexts[?(@.name=="'$(kubectl config current-context)'")].context.user}')
```

### Issue: Policy blocks Helm operations

**Symptoms**: Helm install/upgrade fails

**Possible causes**:
1. Helm's ServiceAccount not excluded
2. Background scanning interfering

**Solution**:
```bash
# Identify Helm's ServiceAccount
helm list -A

# Add Helm SA to exclusions if needed
# Or use --wait flag to ensure atomic operations
```

## Real-World Scenarios

### Scenario 1: CI/CD Pipeline Deployment

```bash
# In CI/CD pipeline (GitHub Actions, GitLab CI, etc.)

# 1. Get deployment-job token (from secret)
DEPLOY_TOKEN="${DEPLOY_JOB_TOKEN}"

# 2. Deploy application via Helm
helm upgrade --install my-app ./chart \
  --namespace production \
  --set image.tag=$CI_COMMIT_SHA \
  --kube-token=$DEPLOY_TOKEN \
  --wait

# Result: SUCCESS (deployment-job SA is excluded)
```

### Scenario 2: Developer Trying Direct Deployment

```bash
# Developer tries to deploy directly
kubectl apply -f deployment.yaml -n production

# Result: BLOCKED by Kyverno
# Error: "Direct workload modifications are not allowed. Use Helm charts..."

# Developer then uses proper workflow:
# 1. Push code to Git
# 2. CI/CD pipeline deploys via Helm
# 3. deployment-job SA performs actual deployment
# Result: SUCCESS
```

### Scenario 3: Emergency Hotfix (Break-Glass)

```bash
# Option 1: Use deployment-job SA (preferred)
kubectl --as=system:serviceaccount:ci-cd:deployment-job \
  set image deployment/my-app app=my-app:hotfix -n production

# Option 2: Add yourself to excludeUsers temporarily
# Update policy values: excludeUsers: ["admin@company.com"]
# Deploy hotfix
# Remove yourself from exclusions after
```

## Performance Metrics

- **Chart install time**: < 15 seconds
- **Policy enforcement time**: < 100ms per request
- **Cleanup time**: < 10 seconds

## Integration with Other Tools

### ArgoCD Integration

```yaml
# ArgoCD Application ServiceAccount should be excluded
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      excludeServiceAccounts:
        - "system:serviceaccount:argocd:argocd-application-controller"
```

### Flux CD Integration

```yaml
# Flux ServiceAccounts should be excluded
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux-cd"
        - "system:serviceaccount:flux-system:helm-controller"
        - "system:serviceaccount:flux-system:kustomize-controller"
```

## Related Use Cases

- UC-KYVERNO-01: Block kubectl exec (API restrictions)
- UC-KYVERNO-03: Debug Proxy Access
- UC-KYVERNO-04: GitOps Workflow (Full Enforcement - all 5 policies)
- UC-KYVERNO-05: Break-Glass Procedure

## References

- Kyverno Resource Management: https://kyverno.io/docs/
- GitOps Patterns: `charts/common-kyverno/GITOPS-ARCHITECTURE.md`
- Policy Examples: `charts/common-kyverno/examples/gitops-only-production.yaml`
- Deployment Job Example: `charts/common-kyverno/examples/deployment-job-example.yaml`
