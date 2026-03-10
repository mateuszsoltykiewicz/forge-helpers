# UC-KYVERNO-06: Audit Mode (Staging/Development)

## Description
Test audit mode configuration where all policies are enabled but set to "audit" action instead of "enforce". This allows operations to proceed while still logging policy violations. Perfect for:
- Staging/QA environments
- Development clusters
- Pre-production validation
- Policy testing before production deployment
- Compliance monitoring without blocking operations

## Prerequisites
- Kyverno installed ✅
- test-allowed namespace created (simulating staging/dev)
- test-app namespace available
- Test workloads available

## Test Scenario

### Setup
1. Install common-kyverno with ALL policies in audit mode
2. Perform operations that would be blocked in enforce mode
3. Verify all operations SUCCEED
4. Verify PolicyReports show violations (audit trail)
5. Analyze violations to prepare for enforce mode

### Expected Results
- ✅ User CREATE deployment is **ALLOWED** (but logged)
- ✅ User UPDATE deployment is **ALLOWED** (but logged)
- ✅ User DELETE deployment is **ALLOWED** (but logged)
- ✅ User kubectl exec is **ALLOWED** (but logged)
- ✅ User kubectl port-forward is **ALLOWED** (but logged)
- ✅ All operations succeed
- ✅ PolicyReports show all violations
- ✅ Violations categorized by severity
- ✅ Ready to analyze for enforce mode transition

## Values Configuration

File: `values/uc06-audit-mode.yaml`

```yaml
forge:
  customer: "test"
  project: "kyverno"
  environment: "staging"
  application: "audit-test"

kyverno:
  # ======================================================
  # API RESTRICTIONS - All in AUDIT mode
  # ======================================================
  apiRestrictions:
    # kubectl exec - audit only (allow but log)
    blockExec:
      enabled: true
      action: "audit"  # Changed from "enforce" to "audit"
      severity: "medium"
      message: >-
        kubectl exec detected in staging environment.
        This operation is logged for audit purposes.
        In production, this would be blocked.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
      excludeUsers: []
      annotations:
        audit-mode: "enabled"
        environment: "staging"
    
    # kubectl port-forward - audit only
    blockPortForward:
      enabled: true
      action: "audit"
      severity: "low"
      message: >-
        kubectl port-forward detected in staging.
        This operation is logged for audit purposes.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
      annotations:
        audit-mode: "enabled"
    
    # kubectl proxy - audit only
    blockProxy:
      enabled: true
      action: "audit"
      severity: "low"
      message: >-
        kubectl proxy detected in staging.
        This operation is logged for audit purposes.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
      annotations:
        audit-mode: "enabled"
    
    # Ephemeral containers - audit only
    blockEphemeralContainers:
      enabled: true
      action: "audit"
      severity: "medium"
      message: >-
        kubectl debug (ephemeral containers) detected in staging.
        This operation is logged for audit purposes.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
      annotations:
        audit-mode: "enabled"
    
    # kubectl attach - audit only
    blockAttach:
      enabled: true
      action: "audit"
      severity: "low"
      message: >-
        kubectl attach detected in staging.
        This operation is logged for audit purposes.
      excludeServiceAccounts:
        - "system:serviceaccount:kube-system:debug-proxy"
      excludeNamespaces:
        - "kube-system"
      excludeUsers: []
      annotations:
        audit-mode: "enabled"
  
  # ======================================================
  # RESOURCE MANAGEMENT - All in AUDIT mode
  # ======================================================
  resourceManagement:
    # Workload modifications - audit only
    blockWorkloadModifications:
      enabled: true
      action: "audit"  # Changed from "enforce" to "audit"
      severity: "high"
      message: >-
        Direct workload modification detected in staging.
        This operation is logged for audit purposes.
        In production, GitOps workflow would be enforced.
      excludeNamespaces:
        - "kube-system"
        - "kube-public"
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
        - "system:serviceaccount:flux-system:flux-cd"
      excludeUsers: []
      annotations:
        audit-mode: "enabled"
        environment: "staging"
        gitops-policy: "audit-only"
    
    # Additional policies (optional - can enable for more audit data)
    blockNetworkingModifications:
      enabled: false
    
    blockConfigModifications:
      enabled: false
    
    blockStorageModifications:
      enabled: false
    
    blockRBACModifications:
      enabled: false
  
  # ======================================================
  # DEBUG PROXY - Can be disabled in audit mode
  # ======================================================
  debugProxy:
    enabled: false  # Not needed in audit mode (all operations allowed)
```

## Test Steps

### 1. Install Chart in Audit Mode

```bash
# From tests/unit/common-kyverno
helm install test-kyverno-uc06 \
  ../../../../charts/common-kyverno \
  -f values/uc06-audit-mode.yaml \
  --namespace test-allowed \
  --create-namespace \
  --wait
```

### 2. Verify Policies Created in Audit Mode

```bash
# List all policies
kubectl get clusterpolicy | grep block

# Expected: 6 policies created

# Verify all are in AUDIT mode (not enforce)
for policy in block-kubectl-exec block-kubectl-port-forward block-kubectl-proxy \
              block-ephemeral-containers block-kubectl-attach block-workload-modifications; do
  echo "=== $policy ==="
  ACTION=$(kubectl get clusterpolicy $policy -o jsonpath='{.spec.validationFailureAction}')
  echo "Action: $ACTION"
  
  if [ "$ACTION" = "Audit" ]; then
    echo "✅ Correct: Audit mode"
  else
    echo "❌ Wrong: Should be Audit, got $ACTION"
  fi
  echo ""
done

# All should show: Action: Audit
```

### 3. Test User Operations - All Should SUCCEED

#### Test 1: Create Deployment (Should SUCCEED)

```bash
echo "Test 1: User creating deployment..."
kubectl create deployment audit-test-app --image=nginx:alpine --replicas=2 -n test-allowed

# Expected: SUCCESS
# Output: deployment.apps/audit-test-app created

# Verify deployment created
kubectl get deployment audit-test-app -n test-allowed
```

#### Test 2: Update Deployment (Should SUCCEED)

```bash
echo "Test 2: User scaling deployment..."
kubectl scale deployment audit-test-app --replicas=5 -n test-allowed

# Expected: SUCCESS
# Output: deployment.apps/audit-test-app scaled

# Verify scale worked
kubectl get deployment audit-test-app -n test-allowed
# Should show 5 replicas
```

#### Test 3: kubectl exec (Should SUCCEED)

```bash
echo "Test 3: User executing command in pod..."

# Wait for pod to be ready
sleep 5
POD_NAME=$(kubectl get pod -n test-allowed -l app=audit-test-app -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n test-allowed $POD_NAME -- ls /usr/share/nginx/html

# Expected: SUCCESS
# Output: index.html (or similar)
```

#### Test 4: kubectl port-forward (Should SUCCEED)

```bash
echo "Test 4: User port-forwarding to pod..."

kubectl port-forward -n test-allowed $POD_NAME 8080:80 &
PF_PID=$!
sleep 2

# Test the connection
curl -s http://localhost:8080 | head -n 5

# Expected: SUCCESS - nginx welcome page

# Cleanup
kill $PF_PID 2>/dev/null || true
```

#### Test 5: Update Container Image (Should SUCCEED)

```bash
echo "Test 5: User updating container image..."

kubectl set image deployment/audit-test-app \
  nginx=nginx:1.25-alpine \
  -n test-allowed

# Expected: SUCCESS
# Output: deployment.apps/audit-test-app image updated

# Verify update
kubectl get deployment audit-test-app -n test-allowed -o jsonpath='{.spec.template.spec.containers[0].image}'
# Should show: nginx:1.25-alpine
```

#### Test 6: Create ConfigMap (Should SUCCEED)

```bash
echo "Test 6: User creating ConfigMap..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-test-config
  namespace: test-allowed
data:
  config.yaml: |
    setting: value
    debug: true
EOF

# Expected: SUCCESS
# Output: configmap/audit-test-config created
```

#### Test 7: Delete Deployment (Should SUCCEED)

```bash
echo "Test 7: User deleting deployment..."

kubectl delete deployment audit-test-app -n test-allowed

# Expected: SUCCESS
# Output: deployment.apps "audit-test-app" deleted

# Verify deleted
kubectl get deployment audit-test-app -n test-allowed 2>&1 | grep -q "NotFound"
# Should return NotFound
```

### 4. Check PolicyReports - Violations Should Be Logged

```bash
echo "Checking PolicyReports for audit violations..."

# Wait for reports to be generated
sleep 5

# List all policy reports
kubectl get policyreport -n test-allowed

# Expected: Multiple reports showing violations

# Get detailed report
kubectl get policyreport -n test-allowed -o yaml | \
  grep -A 5 "result: fail" | head -30

# Should show violations for:
# - block-workload-modifications (deployment create/update/delete)
# - block-kubectl-exec (exec command)
# - block-kubectl-port-forward (port-forward)
```

### 5. Analyze Violation Summary

```bash
echo "=== Audit Violation Summary ==="

# Count violations per policy
for policy in block-kubectl-exec block-kubectl-port-forward block-kubectl-proxy \
              block-ephemeral-containers block-kubectl-attach block-workload-modifications; do
  COUNT=$(kubectl get policyreport -n test-allowed -o json 2>/dev/null | \
          jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$policy\") | .policy" | \
          wc -l || echo "0")
  
  echo "Policy: $policy"
  echo "  Violations: $COUNT"
  echo ""
done

# Expected output example:
# Policy: block-kubectl-exec
#   Violations: 1
# 
# Policy: block-kubectl-port-forward
#   Violations: 1
#
# Policy: block-workload-modifications
#   Violations: 3 (create, scale, delete)
```

### 6. Generate Audit Report for Analysis

```bash
echo "Generating audit report..."

cat > /tmp/audit-report.txt <<EOF
========================================
Kyverno Audit Mode Report
Environment: Staging
Date: $(date)
========================================

SUMMARY:
EOF

# Add violation counts
echo "" >> /tmp/audit-report.txt
echo "Policy Violations Detected:" >> /tmp/audit-report.txt

for policy in $(kubectl get clusterpolicy -o name | grep block); do
  POLICY_NAME=$(echo $policy | cut -d'/' -f2)
  COUNT=$(kubectl get policyreport -n test-allowed -o json 2>/dev/null | \
          jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$POLICY_NAME\") | .policy" | \
          wc -l || echo "0")
  
  echo "  - $POLICY_NAME: $COUNT violations" >> /tmp/audit-report.txt
done

# Add recommendations
cat >> /tmp/audit-report.txt <<EOF

RECOMMENDATIONS:
1. Review all violations before enabling enforce mode
2. Add necessary exclusions (ServiceAccounts, namespaces, users)
3. Communicate policy changes to development teams
4. Schedule transition to enforce mode during maintenance window
5. Monitor PolicyReports after transition

TRANSITION CHECKLIST:
[ ] All violations reviewed
[ ] Exclusions configured
[ ] Teams notified
[ ] Documentation updated
[ ] Monitoring configured
[ ] Rollback plan prepared
EOF

cat /tmp/audit-report.txt

echo ""
echo "Report saved to: /tmp/audit-report.txt"
```

### 7. Test Transition to Enforce Mode (Optional)

```bash
# This demonstrates how to transition from audit to enforce

echo "Simulating transition to enforce mode..."

# Create enforce mode values (copy uc06-audit-mode.yaml and change action to enforce)
# For this test, we'll just show the command

echo "To transition to enforce mode:"
echo "1. Update values file: change all 'action: audit' to 'action: enforce'"
echo "2. helm upgrade test-kyverno-uc06 ... -f values/uc06-enforce-mode.yaml"
echo "3. Verify policies: kubectl get clusterpolicy -o yaml | grep validationFailureAction"
echo "4. Test operations - should now be BLOCKED"
```

### 8. Cleanup

```bash
# Delete test resources
kubectl delete configmap audit-test-config -n test-allowed 2>/dev/null || true
kubectl delete deployment audit-test-app -n test-allowed 2>/dev/null || true

# Uninstall chart
helm uninstall test-kyverno-uc06 -n test-allowed

# Verify policies removed
kubectl get clusterpolicy | grep block
# Should return no results
```

## Validation Criteria

| Test Case | Expected Result | Actual Result | Status |
|-----------|----------------|---------------|--------|
| Policies created | ✅ 6 policies | | |
| All in Audit mode | ✅ action=Audit | | |
| User CREATE deployment | ✅ ALLOWED | | |
| User UPDATE deployment | ✅ ALLOWED | | |
| User DELETE deployment | ✅ ALLOWED | | |
| User kubectl exec | ✅ ALLOWED | | |
| User port-forward | ✅ ALLOWED | | |
| PolicyReports generated | ✅ Created | | |
| Violations logged | ✅ Recorded | | |
| CREATE violation logged | ✅ In report | | |
| EXEC violation logged | ✅ In report | | |
| Port-forward violation logged | ✅ In report | | |

## Audit Mode Benefits

### 1. **Policy Testing**
- Test policies before production deployment
- Validate exclusions are correct
- Identify false positives
- No disruption to workflows

### 2. **Compliance Monitoring**
- Log all policy violations
- Generate audit trails
- Identify non-compliant behavior
- Prepare compliance reports

### 3. **Gradual Rollout**
```
Development → Audit Mode → Enforce Mode → Production

Week 1: Deploy in audit mode to dev
Week 2: Review violations, adjust exclusions
Week 3: Deploy in audit mode to staging
Week 4: Review violations, finalize configuration
Week 5: Deploy in enforce mode to staging
Week 6: Monitor, verify no issues
Week 7: Deploy in enforce mode to production
```

### 4. **Team Education**
- Developers see violations without being blocked
- Learn proper workflows before enforcement
- Understand security requirements
- Time to update scripts/tooling

## Transition Plan: Audit → Enforce

### Phase 1: Audit Mode (2-4 weeks)

```bash
# Deploy with audit mode
helm install kyverno-policies charts/common-kyverno \
  -f values/audit-mode.yaml \
  -n staging

# Monitor violations
kubectl get policyreport -n staging --watch

# Generate weekly reports
./scripts/generate-audit-report.sh > audit-week1.txt
```

### Phase 2: Analysis (1 week)

```bash
# Analyze violations
cat audit-week*.txt | grep "Violations:" | sort | uniq -c

# Identify patterns
# - Which users/teams causing most violations?
# - Which policies need exclusions?
# - Are violations legitimate or policy issues?

# Update exclusions
vim values/production.yaml
# Add necessary excludeUsers, excludeServiceAccounts
```

### Phase 3: Enforce Mode Staging (2 weeks)

```bash
# Upgrade to enforce mode in staging
helm upgrade kyverno-policies charts/common-kyverno \
  -f values/enforce-mode-staging.yaml \
  -n staging

# Monitor for issues
kubectl get policyreport -n staging
kubectl get events -n staging | grep -i deny

# Verify GitOps workflows still work
# Test emergency break-glass procedure
```

### Phase 4: Production Deployment (1 week)

```bash
# Deploy to production with enforce mode
helm install kyverno-policies charts/common-kyverno \
  -f values/enforce-mode-production.yaml \
  -n production \
  --wait

# Verify all policies active
kubectl get clusterpolicy | grep block

# Monitor closely for 48 hours
# Keep break-glass procedure ready
```

## Audit Report Analysis Example

```
========================================
Kyverno Audit Mode Report - Week 1
Environment: Staging
Date: 2026-02-21
========================================

SUMMARY:
Total Operations: 1,247
Policy Violations: 156 (12.5%)

VIOLATIONS BY POLICY:
  - block-workload-modifications: 89 violations (57%)
    * Most violations from developers doing manual deployments
    * Recommendation: Add ci-cd ServiceAccount to exclusions
  
  - block-kubectl-exec: 42 violations (27%)
    * Debugging operations by on-call engineers
    * Recommendation: Enable debug-proxy with proper RBAC
  
  - block-kubectl-port-forward: 25 violations (16%)
    * Developers testing applications
    * Recommendation: Set up Ingress for local testing

VIOLATIONS BY USER:
  - developer1@company.com: 45 violations
  - developer2@company.com: 31 violations
  - ci-cd pipeline: 23 violations (need SA exclusion)
  - sre-team@company.com: 18 violations

RECOMMENDATIONS:
1. Add ci-cd ServiceAccount to blockWorkloadModifications exclusions
2. Deploy debug-proxy for emergency exec access
3. Create Ingress resources to reduce port-forward usage
4. Train developers on GitOps workflow
5. Document break-glass procedure for emergencies

READY FOR ENFORCE MODE: ⚠️  NOT YET
  - Need to add ci-cd SA exclusion
  - Need to deploy debug-proxy
  - Need to create Ingresses
  - Need to train team (scheduled for Week 2)

TARGET: Enable enforce mode in Week 4
```

## Real-World Usage Pattern

### Scenario: New Cluster Setup

```bash
# Day 1: Deploy Kyverno with audit mode
helm install kyverno-policies charts/common-kyverno \
  -f values/audit-mode.yaml \
  -n production

# Day 1-7: Monitor violations
# - Daily review of PolicyReports
# - Identify patterns
# - Communicate findings to teams

# Day 8-14: Adjust policies
# - Add exclusions based on violations
# - Update documentation
# - Train teams on proper workflows

# Day 15-21: Re-deploy with adjustments
helm upgrade kyverno-policies charts/common-kyverno \
  -f values/audit-mode-updated.yaml \
  -n production

# Day 22-28: Verify reduced violations
# - Should see 80%+ reduction in violations
# - Remaining violations should be legitimate

# Day 29: Enable enforce mode
helm upgrade kyverno-policies charts/common-kyverno \
  -f values/enforce-mode.yaml \
  -n production

# Day 30+: Monitor and adjust
# - Break-glass for emergencies
# - Fine-tune exclusions
# - Update policies as needed
```

## Integration with Monitoring

### Prometheus Alerts for Audit Violations

```yaml
# Alert when violation rate is high
- alert: KyvernoHighViolationRate
  expr: |
    rate(kyverno_policy_results_total{result="fail"}[5m]) > 10
  annotations:
    summary: "High Kyverno policy violation rate"
    description: "{{ $value }} violations per second in audit mode"
```

### Grafana Dashboard

```
Panel 1: Total Violations (last 24h)
Panel 2: Violations by Policy
Panel 3: Violations by Namespace
Panel 4: Top Violating Users
Panel 5: Violation Trend (last 7 days)
```

## Performance Metrics

- **Chart install time**: < 20 seconds (6 policies in audit mode)
- **Policy evaluation time**: < 50ms per request (audit mode is faster than enforce)
- **PolicyReport generation time**: 1-5 seconds after operation
- **Cleanup time**: < 15 seconds

## Related Use Cases

- UC-KYVERNO-04: GitOps Workflow (enforce mode equivalent)
- UC-KYVERNO-05: Break-Glass Procedure (emergency override)
- UC-MONITORING-01: Alert on Policy Violations (monitor audit violations)
- UC-SECURITY-03: Audit Log Analysis (review audit trails)

## References

- Kyverno Audit Mode: https://kyverno.io/docs/writing-policies/validate/#audit-mode
- Policy Testing: https://kyverno.io/docs/testing-policies/
- Gradual Rollout: `docs/policy-rollout-strategy.md`
- Common-Kyverno Audit: `charts/common-kyverno/AUDIT-MODE.md`
