# UC-KYVERNO-05: Break-Glass Procedure (Emergency Access)

## Description
Test break-glass (emergency access) procedure for production incidents when normal GitOps workflow is too slow or unavailable. This UC demonstrates how to temporarily grant a user direct access to production while maintaining audit trail.

**Break-Glass Scenarios**:
1. Critical production incident requiring immediate hotfix
2. GitOps pipeline failure preventing deployments
3. Emergency rollback needed
4. Critical security patch deployment

## Prerequisites
- Kyverno installed ✅
- test-blocked namespace created (simulating production)
- All policies installed from UC04 (full enforcement)
- CI/CD ServiceAccounts configured
- Platform team ready to grant/revoke access

## Test Scenario

### Normal State (Before Break-Glass)
1. All policies enforced (UC04 configuration)
2. User cannot perform any direct operations
3. Only CI/CD ServiceAccounts can deploy

### Break-Glass Procedure
1. Incident occurs - immediate action required
2. Platform team grants temporary access by adding user to excludeUsers
3. User performs emergency operation
4. Platform team revokes access
5. User returns to normal restricted state
6. All actions logged for audit

### Expected Results
- ✅ Initial state: User **BLOCKED** from all operations
- ✅ After break-glass grant: User **ALLOWED** to perform operations
- ✅ After revocation: User **BLOCKED** again
- ✅ All operations logged in PolicyReports
- ✅ Time-limited access (manual revocation required)
- ✅ Audit trail of break-glass usage

## Values Configuration

### Initial State: Full Enforcement

File: `values/uc05-breakglass-before.yaml`

```yaml
# Same as UC04 - full enforcement
forge:
  customer: "test"
  project: "kyverno"
  environment: "production"
  application: "breakglass-test"

kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: "enforce"
      excludeUsers: []  # No user exclusions initially
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
    
    blockPortForward:
      enabled: true
      action: "enforce"
      excludeUsers: []
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
  
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      excludeUsers: []  # No user exclusions initially
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
        - "system:serviceaccount:flux-system:flux-cd"
      excludeNamespaces:
        - "kube-system"
```

### Break-Glass Active: User Granted Access

File: `values/uc05-breakglass-active.yaml`

```yaml
forge:
  customer: "test"
  project: "kyverno"
  environment: "production"
  application: "breakglass-test"

kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: "enforce"
      excludeUsers:
        - "system:serviceaccount:kube-system:admin"  # Break-glass user
        # Or: "admin@company.com" for real user
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      annotations:
        break-glass: "active"
        granted-at: "2026-02-21T10:30:00Z"
        granted-by: "platform-team"
        reason: "Production incident #1234"
    
    blockPortForward:
      enabled: true
      action: "enforce"
      excludeUsers:
        - "system:serviceaccount:kube-system:admin"
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
  
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      excludeUsers:
        - "system:serviceaccount:kube-system:admin"  # Break-glass user
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
        - "system:serviceaccount:flux-system:flux-cd"
      excludeNamespaces:
        - "kube-system"
      annotations:
        break-glass: "active"
        incident-id: "INC-1234"
```

### After Revocation: Return to Full Enforcement

File: `values/uc05-breakglass-after.yaml`

```yaml
# Same as uc05-breakglass-before.yaml
# User removed from excludeUsers lists
# Annotations updated to record revocation

forge:
  customer: "test"
  project: "kyverno"
  environment: "production"
  application: "breakglass-test"

kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: "enforce"
      excludeUsers: []  # Break-glass revoked
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      annotations:
        break-glass: "revoked"
        revoked-at: "2026-02-21T11:00:00Z"
        revoked-by: "platform-team"
        duration: "30 minutes"
  
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      excludeUsers: []  # Break-glass revoked
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
      annotations:
        break-glass: "revoked"
```

## Test Steps

### Phase 1: Initial State (Full Enforcement)

```bash
# Install chart with full enforcement
helm install test-kyverno-uc05 \
  ../../../../charts/common-kyverno \
  -f values/uc05-breakglass-before.yaml \
  --namespace test-blocked \
  --wait
```

### Phase 2: Verify User is Blocked

```bash
# Test deployment (should FAIL)
kubectl create deployment test-app --image=nginx -n test-blocked

# Expected: BLOCKED
# Error: "Direct workload modifications are blocked in production..."

# Create deployment using CI/CD (for later testing)
DEPLOY_TOKEN=$(kubectl create token deployment-job -n ci-cd --duration=1h)
kubectl --token=$DEPLOY_TOKEN create deployment breakglass-app \
  --image=nginx:alpine \
  --replicas=2 \
  -n test-blocked

# Wait for pod
sleep 5
POD_NAME=$(kubectl get pod -n test-blocked -l app=breakglass-app -o jsonpath='{.items[0].metadata.name}')

# Test exec (should FAIL)
kubectl exec -n test-blocked $POD_NAME -- ls

# Expected: BLOCKED
# Error: "kubectl exec is blocked in production..."
```

### Phase 3: Incident Occurs - Break-Glass Needed

```bash
# Scenario: Critical production bug detected
# Normal GitOps workflow takes 15 minutes
# Hotfix needs to be deployed immediately

echo "🚨 INCIDENT: Critical bug in production"
echo "   User needs emergency access to deploy hotfix"
echo "   Initiating break-glass procedure..."
```

### Phase 4: Grant Break-Glass Access

```bash
# Platform team upgrades Helm release with user in excludeUsers

helm upgrade test-kyverno-uc05 \
  ../../../../charts/common-kyverno \
  -f values/uc05-breakglass-active.yaml \
  --namespace test-blocked \
  --wait

# Wait for policy update
sleep 5

echo "✅ Break-glass access granted"
```

### Phase 5: Verify User Can Now Operate

```bash
# Test exec (should NOW SUCCEED)
echo "Testing kubectl exec with break-glass access..."
kubectl exec -n test-blocked $POD_NAME -- ls /usr/share/nginx/html

# Expected: SUCCESS
# Output: index.html (or similar)

# Test deployment modification (should NOW SUCCEED)
echo "Testing deployment modification with break-glass access..."
kubectl scale deployment breakglass-app --replicas=3 -n test-blocked

# Expected: SUCCESS
# Output: deployment.apps/breakglass-app scaled

# Verify scale worked
kubectl get deployment breakglass-app -n test-blocked
# Should show 3 replicas

# Deploy emergency hotfix
echo "Deploying emergency hotfix..."
kubectl set image deployment/breakglass-app \
  nginx=nginx:1.25-alpine \
  -n test-blocked

# Expected: SUCCESS
# Output: deployment.apps/breakglass-app image updated
```

### Phase 6: User Performs Emergency Actions

```bash
# Scenario: User performs necessary emergency operations

# 1. Check logs
kubectl logs -n test-blocked $POD_NAME --tail=50

# 2. Debug issue
kubectl exec -n test-blocked $POD_NAME -- cat /etc/nginx/nginx.conf

# 3. Apply hotfix configmap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: hotfix-config
  namespace: test-blocked
data:
  fix: "emergency-patch-1234"
EOF

# 4. Verify fix
kubectl get deployment breakglass-app -n test-blocked -o yaml | grep image
```

### Phase 7: Revoke Break-Glass Access

```bash
# Platform team revokes access after incident resolved

echo "✅ Incident resolved - revoking break-glass access..."

helm upgrade test-kyverno-uc05 \
  ../../../../charts/common-kyverno \
  -f values/uc05-breakglass-after.yaml \
  --namespace test-blocked \
  --wait

# Wait for policy update
sleep 5

echo "🔒 Break-glass access revoked - returning to full enforcement"
```

### Phase 8: Verify User is Blocked Again

```bash
# Test exec (should FAIL again)
echo "Testing kubectl exec after revocation..."
kubectl exec -n test-blocked $POD_NAME -- ls

# Expected: BLOCKED
# Error: "kubectl exec is blocked in production..."

# Test deployment modification (should FAIL again)
echo "Testing deployment modification after revocation..."
kubectl scale deployment breakglass-app --replicas=1 -n test-blocked

# Expected: BLOCKED
# Error: "Direct workload modifications are blocked in production..."

echo "✅ User access revoked - policies enforced again"
```

### Phase 9: Check Audit Trail

```bash
# Review PolicyReports for break-glass usage
kubectl get policyreport -n test-blocked

# Check for violations during break-glass period
# (should show violations before grant and after revocation, but NOT during active period)

# Get detailed audit trail
kubectl get policyreport -n test-blocked -o json | \
  jq -r '.items[].results[]? | 
         select(.result=="fail") | 
         "\(.timestamp): \(.policy) - \(.resource.kind)/\(.resource.name)"' | \
  sort

# Expected: Violations before and after break-glass, gap during active period
```

### Phase 10: Cleanup

```bash
# Delete test resources
kubectl --token=$DEPLOY_TOKEN delete deployment breakglass-app -n test-blocked
kubectl delete configmap hotfix-config -n test-blocked 2>/dev/null || true

# Uninstall chart
helm uninstall test-kyverno-uc05 -n test-blocked

# Verify policies removed
kubectl get clusterpolicy | grep block
# Should return no results
```

## Validation Criteria

| Phase | Test Case | Expected Result | Actual Result | Status |
|-------|-----------|----------------|---------------|--------|
| Initial | User CREATE deployment | BLOCKED | | |
| Initial | User exec | BLOCKED | | |
| Initial | CI/CD deployment | ALLOWED | | |
| Break-Glass Active | User CREATE deployment | ALLOWED | | |
| Break-Glass Active | User UPDATE deployment | ALLOWED | | |
| Break-Glass Active | User exec | ALLOWED | | |
| Break-Glass Active | User port-forward | ALLOWED | | |
| After Revocation | User CREATE deployment | BLOCKED | | |
| After Revocation | User UPDATE deployment | BLOCKED | | |
| After Revocation | User exec | BLOCKED | | |
| Audit | PolicyReports show violations | ✅ Before/After only | | |
| Audit | Break-glass duration recorded | ✅ Annotated | | |

## Break-Glass Procedure Documentation

### When to Use Break-Glass

✅ **Valid Scenarios**:
- Critical production incident requiring immediate action
- GitOps pipeline failure preventing urgent deployment
- Security vulnerability requiring immediate patch
- Data loss prevention requiring emergency intervention
- Service outage requiring hotfix outside normal hours

❌ **Invalid Scenarios**:
- Convenience (developer wants faster deployment)
- Testing in production
- Bypassing code review
- Regular feature deployment
- Non-urgent bug fixes

### Break-Glass Approval Workflow

```
1. Incident Detected
   ↓
2. On-call Engineer Assesses Severity
   ↓ (If critical)
3. Request Break-Glass Access
   - Incident ID: INC-1234
   - Justification: "Critical bug causing data corruption"
   - Estimated Duration: 30 minutes
   ↓
4. Platform Team Approves
   - Reviews incident
   - Grants access via Helm upgrade
   - Records in audit log
   ↓
5. Engineer Performs Emergency Operations
   - All actions logged
   - Time-boxed access
   ↓
6. Incident Resolved
   ↓
7. Platform Team Revokes Access
   - Helm upgrade with user removed
   - Access automatically revoked
   ↓
8. Post-Incident Review
   - Audit trail reviewed
   - Actions documented
   - Prevention measures identified
```

### Automated Break-Glass Script

```bash
#!/bin/bash
# break-glass.sh - Manage break-glass access

NAMESPACE="production"
RELEASE="kyverno-policies"
VALUES_BASE="values/production.yaml"
BREAKGLASS_USER="${1:-admin@company.com}"
ACTION="${2:-grant}"  # grant or revoke

if [ "$ACTION" = "grant" ]; then
  echo "🚨 Granting break-glass access to: $BREAKGLASS_USER"
  
  # Create temporary values file with user added
  yq eval ".kyverno.apiRestrictions.blockExec.excludeUsers += [\"$BREAKGLASS_USER\"]" \
    $VALUES_BASE > /tmp/breakglass-values.yaml
  
  yq eval ".kyverno.resourceManagement.blockWorkloadModifications.excludeUsers += [\"$BREAKGLASS_USER\"]" \
    /tmp/breakglass-values.yaml > /tmp/breakglass-values-final.yaml
  
  # Upgrade with break-glass access
  helm upgrade $RELEASE charts/common-kyverno \
    -f /tmp/breakglass-values-final.yaml \
    -n $NAMESPACE \
    --wait
  
  echo "✅ Break-glass access granted"
  echo "   User: $BREAKGLASS_USER"
  echo "   Time: $(date)"
  echo "   Remember to REVOKE access after incident!"
  
elif [ "$ACTION" = "revoke" ]; then
  echo "🔒 Revoking break-glass access..."
  
  # Restore original values (without user)
  helm upgrade $RELEASE charts/common-kyverno \
    -f $VALUES_BASE \
    -n $NAMESPACE \
    --wait
  
  echo "✅ Break-glass access revoked"
  echo "   User: $BREAKGLASS_USER"
  echo "   Time: $(date)"
else
  echo "Usage: $0 <user> <grant|revoke>"
  exit 1
fi
```

## Real-World Example

### Incident: Database Connection Pool Exhausted

```bash
# 10:30 AM - Alert: API returning 500 errors
# Root cause: Connection pool exhausted due to leak

# 10:35 AM - Platform team grants break-glass
./break-glass.sh admin@company.com grant

# 10:36 AM - Engineer deploys hotfix
kubectl set env deployment/api-server \
  DB_POOL_SIZE=50 \
  DB_MAX_WAIT_MS=5000 \
  -n production

# 10:37 AM - Engineer restarts pods
kubectl rollout restart deployment/api-server -n production

# 10:40 AM - Service recovered, errors stopped

# 10:45 AM - Platform team revokes access
./break-glass.sh admin@company.com revoke

# Post-incident:
# - Audit log shows 10-minute break-glass window
# - All actions recorded in PolicyReports
# - RCA: Add DB pool monitoring alerts
# - Prevention: Add DB pool size validation in CI/CD
```

## Security Considerations

1. **Time-Limited Access**: Break-glass should be time-boxed (15-30 min typical)
2. **Audit Trail**: All actions logged in PolicyReports and Kubernetes audit logs
3. **Notification**: Alert security team when break-glass granted
4. **Review**: Post-incident review of all break-glass actions
5. **Automation**: Consider automated revocation after time limit

## Integration with Incident Management

```yaml
# PagerDuty/Opsgenie Integration
# When incident escalated to "critical":
# 1. Notify platform team
# 2. Auto-grant break-glass to on-call engineer
# 3. Set timer for auto-revocation (30 min)
# 4. Create audit trail ticket
# 5. Alert security team
```

## Performance Metrics

- **Break-glass grant time**: < 30 seconds (Helm upgrade)
- **Break-glass revoke time**: < 30 seconds (Helm upgrade)
- **Policy enforcement delay**: < 5 seconds after upgrade
- **Typical break-glass duration**: 10-30 minutes

## Related Use Cases

- UC-KYVERNO-04: GitOps Workflow (normal state before break-glass)
- UC-KYVERNO-03: Debug Proxy Access (alternative to break-glass)
- UC-MONITORING-01: Alert on Policy Violations (detect break-glass usage)
- UC-SECURITY-03: Audit Log Analysis (review break-glass actions)

## References

- Break-Glass Pattern: https://en.wikipedia.org/wiki/Break_glass_(access_control)
- Kubernetes Audit: https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/
- Incident Response: `docs/incident-response-playbook.md`
- Common-Kyverno Emergency Access: `charts/common-kyverno/BREAK-GLASS.md`
