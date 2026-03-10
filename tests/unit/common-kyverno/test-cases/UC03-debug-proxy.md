# UC-KYVERNO-03: Debug Proxy Access (Controlled API Access)

## Description
Test controlled access pattern where debug-proxy ServiceAccount can bypass API restrictions while other ServiceAccounts cannot. This demonstrates how to provide emergency/debugging access without opening security holes.

## Prerequisites
- Kyverno installed ✅
- test-app namespace created
- kube-system namespace exists
- debug-proxy ServiceAccount created in kube-system
- test-nginx deployment running in test-app

## Test Scenario

### Setup
1. Install common-kyverno with multiple API restrictions enabled
2. Install debugProxy helper (optional - creates debug-proxy pod)
3. Test that regular users are blocked from all API operations
4. Test that debug-proxy SA can perform all operations
5. Verify audit logs capture all actions

### Expected Results
- ✅ Regular user **kubectl exec** is **BLOCKED**
- ✅ Regular user **kubectl port-forward** is **BLOCKED**
- ✅ Regular user **kubectl proxy** is **BLOCKED**
- ✅ Regular user **kubectl debug** (ephemeral containers) is **BLOCKED**
- ✅ debug-proxy SA **exec** is **ALLOWED**
- ✅ debug-proxy SA **port-forward** is **ALLOWED**
- ✅ debug-proxy SA **proxy** is **ALLOWED**
- ✅ debug-proxy SA **debug** is **ALLOWED**
- ✅ All operations logged in PolicyReports
- ✅ Debug-proxy pod (if enabled) can proxy requests

## Values Configuration

File: `values/uc03-debug-proxy.yaml`

```yaml
forge:
  customer: "test"
  project: "kyverno"
  environment: "test"
  application: "debug-test"

kyverno:
  # API Restrictions - all enabled for comprehensive testing
  apiRestrictions:
    blockExec:
      enabled: true
      action: "enforce"
      severity: "medium"
      message: "kubectl exec blocked. Use debug-proxy ServiceAccount."
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
    
    blockPortForward:
      enabled: true
      action: "enforce"
      severity: "low"
      message: "kubectl port-forward blocked. Use debug-proxy ServiceAccount."
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
    
    blockProxy:
      enabled: true
      action: "enforce"
      severity: "low"
      message: "kubectl proxy blocked. Use debug-proxy ServiceAccount."
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
    
    blockEphemeralContainers:
      enabled: true
      action: "enforce"
      severity: "medium"
      message: "kubectl debug (ephemeral containers) blocked. Use debug-proxy."
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
    
    blockAttach:
      enabled: true
      action: "enforce"
      severity: "low"
      message: "kubectl attach blocked. Use debug-proxy ServiceAccount."
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
  
  # Disable resource management for this test
  resourceManagement:
    blockWorkloadModifications:
      enabled: false
    blockNetworkingModifications:
      enabled: false
    blockConfigModifications:
      enabled: false
    blockStorageModifications:
      enabled: false
    blockRBACModifications:
      enabled: false
  
  # Enable debug proxy helper (optional - creates debug-proxy pod)
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
      description: "Emergency debug proxy with controlled API access"
```

## Test Steps

### 1. Install Chart

```bash
# From tests/unit/common-kyverno
helm install test-kyverno-uc03 \
  ../../../../charts/common-kyverno \
  -f values/uc03-debug-proxy.yaml \
  --namespace test-app \
  --create-namespace \
  --wait
```

### 2. Verify Policies Created

```bash
# Check all 5 ClusterPolicies exist
kubectl get clusterpolicy | grep block

# Expected output:
# block-kubectl-exec
# block-kubectl-port-forward
# block-kubectl-proxy
# block-ephemeral-containers
# block-kubectl-attach
```

Verify policy details:
```bash
for policy in block-kubectl-exec block-kubectl-port-forward block-kubectl-proxy \
              block-ephemeral-containers block-kubectl-attach; do
  echo "=== $policy ==="
  kubectl get clusterpolicy $policy -o jsonpath='{.spec.validationFailureAction}'
  echo ""
done

# All should return: Enforce
```

### 3. Verify Debug-Proxy Pod (Optional)

```bash
# Check if debug-proxy pod was created
kubectl get deployment -n kube-system | grep debug-proxy

# Check pod status
kubectl get pods -n kube-system -l app.kubernetes.io/name=debug-proxy

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=debug-proxy
```

### 4. Test Regular User - kubectl exec (Should FAIL)

```bash
# Get test pod name
POD_NAME=$(kubectl get pod -n test-app -l app.kubernetes.io/name=test-nginx -o jsonpath='{.items[0].metadata.name}')

# Attempt exec
kubectl exec -n test-app $POD_NAME -- ls

# Expected: BLOCKED
# Error: "kubectl exec blocked. Use debug-proxy ServiceAccount."
```

### 5. Test Regular User - kubectl port-forward (Should FAIL)

```bash
# Attempt port-forward
kubectl port-forward -n test-app $POD_NAME 8080:80 &
PORT_FORWARD_PID=$!

# Expected: BLOCKED immediately
# Error: "kubectl port-forward blocked. Use debug-proxy ServiceAccount."

# Kill background process if it started
kill $PORT_FORWARD_PID 2>/dev/null || true
```

### 6. Test Regular User - kubectl proxy (Should FAIL)

```bash
# Attempt proxy
kubectl proxy --port=8001 &
PROXY_PID=$!

# Wait a moment
sleep 2

# Try to access API through proxy
curl http://localhost:8001/api/v1/namespaces/test-app/pods

# Expected: BLOCKED or connection refused
# Error: "kubectl proxy blocked. Use debug-proxy ServiceAccount."

# Kill proxy
kill $PROXY_PID 2>/dev/null || true
```

### 7. Test Regular User - kubectl debug (Should FAIL)

```bash
# Attempt ephemeral container debug
kubectl debug -n test-app $POD_NAME -it --image=busybox --target=$POD_NAME

# Expected: BLOCKED
# Error: "kubectl debug (ephemeral containers) blocked. Use debug-proxy."
```

### 8. Test Regular User - kubectl attach (Should FAIL)

```bash
# Attempt attach
kubectl attach -n test-app $POD_NAME -c nginx

# Expected: BLOCKED
# Error: "kubectl attach blocked. Use debug-proxy ServiceAccount."
```

### 9. Test debug-proxy SA - All Operations (Should SUCCEED)

```bash
# Create token for debug-proxy SA
DEBUG_TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=1h)

echo "Debug token created: ${DEBUG_TOKEN:0:20}..."

# Test 1: exec with debug-proxy
echo "Test 1: kubectl exec"
kubectl --token=$DEBUG_TOKEN exec -n test-app $POD_NAME -- ls /usr/share/nginx/html

# Expected: SUCCESS - should see index.html

# Test 2: port-forward with debug-proxy
echo "Test 2: kubectl port-forward"
kubectl --token=$DEBUG_TOKEN port-forward -n test-app $POD_NAME 8888:80 &
PF_PID=$!
sleep 2

# Test the port-forward
curl -s http://localhost:8888 | head -n 5

# Cleanup
kill $PF_PID 2>/dev/null || true

# Expected: SUCCESS - should see nginx welcome page

# Test 3: attach with debug-proxy (if applicable)
echo "Test 3: kubectl attach"
# Note: attach requires interactive terminal, may not work in script
kubectl --token=$DEBUG_TOKEN attach -n test-app $POD_NAME --timeout=5s || \
  echo "Attach requires interactive terminal (policy allows it)"

# Expected: Policy allows it (even if RBAC/container limits it)
```

### 10. Test Excluded Namespace (kube-system - Should SUCCEED)

```bash
# Get a kube-system pod
KUBE_POD=$(kubectl get pod -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
           kubectl get pod -n kube-system -o jsonpath='{.items[0].metadata.name}')

if [ ! -z "$KUBE_POD" ]; then
  # Try exec in kube-system (excluded namespace)
  kubectl exec -n kube-system $KUBE_POD -- echo "Excluded namespace test"
  
  # Expected: May succeed or fail due to RBAC, but NOT blocked by Kyverno
else
  echo "No pods found in kube-system to test"
fi
```

### 11. Check PolicyReports

```bash
# Check for policy violations in test-app
kubectl get policyreport -n test-app

# Describe to see violations
kubectl describe policyreport -n test-app

# Check cluster-wide reports
kubectl get clusterpolicyreport

# Get violation summary
kubectl get policyreport -A -o json | \
  jq -r '.items[].results[]? | select(.result=="fail") | 
         "\(.policy): \(.resource.kind)/\(.resource.name) - \(.message)"' | \
  head -20
```

Expected PolicyReport violations:
- block-kubectl-exec: Pod/test-nginx (5+ violations)
- block-kubectl-port-forward: Pod/test-nginx (1+ violations)
- block-kubectl-proxy: violations
- block-ephemeral-containers: Pod/test-nginx
- block-kubectl-attach: Pod/test-nginx

### 12. Test Using Debug-Proxy Pod (If Enabled)

```bash
# Get debug-proxy pod name
DEBUG_POD=$(kubectl get pod -n kube-system -l app.kubernetes.io/name=debug-proxy -o jsonpath='{.items[0].metadata.name}')

if [ ! -z "$DEBUG_POD" ]; then
  echo "Testing through debug-proxy pod..."
  
  # Execute commands through debug-proxy pod
  kubectl exec -n kube-system $DEBUG_POD -- \
    kubectl exec -n test-app $POD_NAME -- ls
  
  # Expected: SUCCESS - debug-proxy pod uses debug-proxy SA
else
  echo "Debug-proxy pod not available (debugProxy.enabled: false)"
fi
```

## Validation Criteria

| Test Case | Expected Result | Actual Result | Status |
|-----------|----------------|---------------|--------|
| User exec | BLOCKED | | |
| User port-forward | BLOCKED | | |
| User proxy | BLOCKED | | |
| User debug | BLOCKED | | |
| User attach | BLOCKED | | |
| debug-proxy exec | ALLOWED | | |
| debug-proxy port-forward | ALLOWED | | |
| debug-proxy attach | ALLOWED | | |
| kube-system exec | ALLOWED | | |
| All 5 policies created | ✅ Created | | |
| PolicyReports generated | ✅ Recorded | | |
| Debug-proxy pod running | ✅ (optional) | | |

## Cleanup

```bash
# Uninstall chart (removes policies and debug-proxy pod)
helm uninstall test-kyverno-uc03 -n test-app

# Verify policies removed
kubectl get clusterpolicy | grep block
# Should return no results

# Verify debug-proxy pod removed
kubectl get deployment -n kube-system debug-proxy
# Should return NotFound
```

## Troubleshooting

### Issue: debug-proxy SA still blocked

**Symptoms**: Debug-proxy ServiceAccount cannot exec/port-forward

**Possible causes**:
1. SA not in excludeServiceAccounts list
2. Token not properly created/used
3. RBAC permissions missing

**Solution**:
```bash
# Verify SA in exclusion list
kubectl get clusterpolicy block-kubectl-exec -o yaml | \
  grep "system:serviceaccount:kube-system:debug-proxy"

# Verify RBAC
kubectl auth can-i create pods/exec --as=system:serviceaccount:kube-system:debug-proxy -n test-app

# Re-create token
DEBUG_TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=1h)
kubectl --token=$DEBUG_TOKEN auth whoami
```

### Issue: All operations allowed for regular users

**Symptoms**: Regular users can still exec/port-forward

**Possible causes**:
1. Policies in audit mode instead of enforce
2. User in excludeUsers list
3. Namespace in excludeNamespaces

**Solution**:
```bash
# Check all policy actions
for policy in $(kubectl get clusterpolicy -o name | grep block); do
  echo "$policy:"
  kubectl get $policy -o jsonpath='{.spec.validationFailureAction}'
  echo ""
done

# Check exclusions
kubectl get clusterpolicy block-kubectl-exec -o yaml | grep -A 20 "exclude"
```

### Issue: Debug-proxy pod not created

**Symptoms**: No debug-proxy deployment in kube-system

**Possible causes**:
1. debugProxy.enabled: false
2. Resource creation failed
3. RBAC prevents creation

**Solution**:
```bash
# Check if debugProxy was enabled
helm get values test-kyverno-uc03 -n test-app | grep -A 10 debugProxy

# Check for events
kubectl get events -n kube-system | grep debug-proxy

# Manual creation (if needed)
kubectl create deployment debug-proxy \
  --image=bitnami/kubectl:latest \
  --namespace=kube-system

kubectl set serviceaccount deployment debug-proxy debug-proxy -n kube-system
```

### Issue: Port-forward/proxy still work despite policy

**Symptoms**: kubectl port-forward succeeds even though blocked

**Possible causes**:
1. Port-forward/proxy happen client-side, not server-side
2. Policy not matching the right API calls
3. Kyverno webhook not intercepting

**Solution**:
```bash
# Check Kyverno webhook configuration
kubectl get validatingwebhookconfigurations | grep kyverno

# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=100

# Verify policy is matching
kubectl get clusterpolicy block-kubectl-port-forward -o yaml | grep -A 20 "match"
```

## Real-World Usage Patterns

### Pattern 1: Emergency Debugging

```bash
# Developer needs to debug production issue

# Step 1: Request debug-proxy access (manual approval)
# Platform team grants temporary access

# Step 2: Use debug-proxy token
DEBUG_TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=1h)

# Step 3: Debug the issue
kubectl --token=$DEBUG_TOKEN exec -n production $POD -- sh

# Step 4: Token expires after 1 hour (automatic revocation)
```

### Pattern 2: Automated Debug Session

```bash
# Platform team provides script for controlled debugging

#!/bin/bash
# debug-session.sh
NAMESPACE=$1
POD=$2

# Create short-lived token
TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=15m)

# Start debug session
kubectl --token=$TOKEN exec -n $NAMESPACE $POD -it -- /bin/sh

# Token auto-expires after 15 minutes
```

### Pattern 3: Debug-Proxy Pod for On-Call Engineers

```bash
# On-call engineer connects through debug-proxy pod
# This pod has the debug-proxy SA attached

# Step 1: Access debug-proxy pod
kubectl exec -n kube-system -it $DEBUG_POD -- bash

# Step 2: From within debug-proxy pod, use kubectl normally
kubectl exec -n test-app $POD -- ls
kubectl logs -n test-app $POD --tail=100
kubectl port-forward -n test-app $POD 8080:80

# All operations use debug-proxy SA (allowed by policy)
```

## Performance Metrics

- **Chart install time**: < 20 seconds (includes 5 policies + optional deployment)
- **Policy enforcement time**: < 100ms per request
- **Token creation time**: < 1 second
- **Cleanup time**: < 15 seconds

## Security Considerations

1. **Token Lifetime**: Keep debug-proxy tokens short-lived (15m-1h)
2. **Audit Logging**: All debug-proxy actions logged in PolicyReports
3. **RBAC**: debug-proxy SA should have minimal required permissions
4. **Network**: Consider NetworkPolicies to limit debug-proxy pod access
5. **Break-Glass**: Document break-glass procedure if debug-proxy unavailable

## Integration with Incident Response

```yaml
# Incident Response Workflow
1. Alert triggered (PagerDuty, Opsgenie)
2. On-call engineer triages issue
3. If debugging needed:
   a. Engineer requests debug-proxy access
   b. Platform team approves (auto or manual)
   c. Engineer receives 30-minute token
   d. Engineer debugs through debug-proxy
   e. Token expires automatically
   f. All actions logged for audit
4. Incident resolved
5. Post-mortem includes debug actions from logs
```

## Related Use Cases

- UC-KYVERNO-01: Block kubectl exec (basic API restriction)
- UC-KYVERNO-05: Break-Glass Procedure (emergency access)
- UC-MONITORING-03: SLO Monitoring (detect when debugging needed)
- UC-SECURITY-03: Falco Runtime Protection (detect suspicious exec patterns)

## References

- Kyverno API Restrictions: https://kyverno.io/docs/
- Debug Proxy Pattern: `charts/common-kyverno/DEBUG-PROXY.md`
- Kubernetes API Audit: https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/
- Break-Glass Procedures: `charts/common-kyverno/examples/break-glass.yaml`
