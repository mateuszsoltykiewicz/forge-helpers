# UC-KYVERNO-01: Block kubectl exec (API Restrictions)

## Description
Test that Kyverno blocks `kubectl exec` commands for regular users while allowing access for excluded ServiceAccounts (debug-proxy).

## Prerequisites
- Kyverno installed ✅
- test-app namespace created
- debug-proxy ServiceAccount created
- test-nginx deployment running

## Test Scenario

### Setup
1. Install common-kyverno with blockExec policy enabled
2. Deploy test workload (nginx pod)
3. Attempt exec as regular user (should be blocked)
4. Attempt exec as debug-proxy ServiceAccount (should be allowed)

### Expected Results
- ✅ Regular user exec is **BLOCKED**
- ✅ Debug-proxy ServiceAccount exec is **ALLOWED**
- ✅ Kyverno returns clear error message
- ✅ PolicyReport shows violation

## Values Configuration

File: `values/uc01-block-exec.yaml`

```yaml
forge:
  customer: "test"
  project: "kyverno"
  environment: "test"
  application: "policy-test"

kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: "enforce"
      severity: "medium"
      message: "kubectl exec is not allowed. Use debug proxy ServiceAccount for debugging."
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeUsers: []
      annotations: {}
```

## Test Steps

### 1. Install Chart

```bash
# From tests/unit/common-kyverno
helm install test-kyverno-uc01 \
  ../../../../charts/common-kyverno \
  -f values/uc01-block-exec.yaml \
  --namespace test-app \
  --create-namespace \
  --wait
```

### 2. Verify Policy Created

```bash
# Check ClusterPolicy exists
kubectl get clusterpolicy block-kubectl-exec

# Verify policy details
kubectl describe clusterpolicy block-kubectl-exec
```

Expected output:
```
Name:         block-kubectl-exec
Namespace:    
Labels:       app.kubernetes.io/managed-by=Helm
              ...
Annotations:  policies.kyverno.io/category: Security, API Restrictions
              policies.kyverno.io/severity: medium
              policies.kyverno.io/title: Block kubectl exec
Spec:
  Background:                  false
  Failure Policy:              Fail
  Validation Failure Action:   enforce
  Rules:
    Name:  block-exec-create
    Match:
      Any:
        Resources:
          Kinds:
            pods/exec
          Operations:
            CREATE
    ...
```

### 3. Test Regular User (Should FAIL)

```bash
# Attempt to exec into test pod as regular user
kubectl exec -n test-app test-nginx-xxxx -- ls

# Expected: BLOCKED
# Error message should contain: "kubectl exec is not allowed"
```

Expected error:
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 

policy ClusterPolicy/block-kubectl-exec for resource violation:

block-exec-create:
  kubectl exec is not allowed. Use debug proxy ServiceAccount for debugging.
```

### 4. Test Debug-Proxy ServiceAccount (Should SUCCEED)

```bash
# Get debug-proxy token
DEBUG_TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=1h)

# Exec using debug-proxy identity
kubectl --token=$DEBUG_TOKEN exec -n test-app test-nginx-xxxx -- ls

# Expected: SUCCESS
# Should see output: bin  boot  dev  etc  home  ...
```

### 5. Test Excluded Namespace (Should SUCCEED)

```bash
# Exec into kube-system pod (excluded namespace)
kubectl exec -n kube-system coredns-xxxx -- ls

# Expected: SUCCESS (namespace excluded from policy)
```

### 6. Check PolicyReport

```bash
# Check for policy violations in test-app namespace
kubectl get policyreport -n test-app

# Describe the report
kubectl describe policyreport -n test-app

# Should show violations for failed exec attempts
```

Expected PolicyReport:
```yaml
apiVersion: wgpolicyk8s.io/v1alpha2
kind: PolicyReport
metadata:
  name: cpol-block-kubectl-exec
  namespace: test-app
results:
  - message: "kubectl exec is not allowed. Use debug proxy ServiceAccount for debugging."
    policy: block-kubectl-exec
    result: fail
    scored: true
    source: kyverno
    timestamp:
      seconds: 1708531200
```

## Validation Criteria

| Test Case | Expected Result | Actual Result | Status |
|-----------|----------------|---------------|--------|
| Regular user exec | BLOCKED | | |
| Debug-proxy SA exec | ALLOWED | | |
| kube-system exec | ALLOWED | | |
| Policy created | ✅ Created | | |
| PolicyReport shows violation | ✅ Recorded | | |
| Clear error message | ✅ Descriptive | | |

## Cleanup

```bash
# Uninstall chart
helm uninstall test-kyverno-uc01 -n test-app

# Verify policy removed
kubectl get clusterpolicy block-kubectl-exec
# Should return: NotFound
```

## Troubleshooting

### Issue: Policy not blocking exec

**Symptoms**: kubectl exec succeeds for regular users

**Possible causes**:
1. Policy `action` set to "audit" instead of "enforce"
2. User is in excludeUsers list
3. Kyverno webhooks not running

**Solution**:
```bash
# Check policy action
kubectl get clusterpolicy block-kubectl-exec -o yaml | grep validationFailureAction

# Check Kyverno admission controller
kubectl get deploy -n kyverno kyverno-admission-controller

# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50
```

### Issue: Debug-proxy SA also blocked

**Symptoms**: Debug-proxy ServiceAccount cannot exec

**Possible causes**:
1. ServiceAccount not in excludeServiceAccounts list
2. Token not properly passed to kubectl

**Solution**:
```bash
# Verify exclusion in policy
kubectl get clusterpolicy block-kubectl-exec -o yaml | grep -A 5 "excludeServiceAccounts"

# Verify token is valid
kubectl --token=$DEBUG_TOKEN auth can-i get pods -n test-app
```

### Issue: PolicyReport not showing violations

**Symptoms**: No PolicyReport created

**Possible causes**:
1. Kyverno reports controller not running
2. Background scanning disabled

**Solution**:
```bash
# Check reports controller
kubectl get deploy -n kyverno kyverno-reports-controller

# Trigger manual report generation
kubectl annotate clusterpolicy block-kubectl-exec policies.kyverno.io/scored=true
```

## Performance Metrics

- **Chart install time**: < 10 seconds
- **Policy enforcement time**: < 100ms per request
- **Cleanup time**: < 5 seconds

## Related Use Cases

- UC-KYVERNO-02: Block Direct Deployments
- UC-KYVERNO-03: Debug Proxy Access (comprehensive test)
- UC-KYVERNO-04: GitOps Workflow

## References

- Kyverno API Restrictions: https://kyverno.io/policies/
- Debug Proxy Pattern: `charts/common-kyverno/README.md#debug-proxy`
- Policy Testing: https://kyverno.io/docs/testing-policies/
