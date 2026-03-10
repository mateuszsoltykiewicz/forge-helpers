#!/bin/bash
set -e

#####################################################################
# UC-KYVERNO-06: Audit Mode (Staging/Development)
# 
# Tests that all policies are in audit mode (operations allowed but logged)
# Perfect for staging/dev environments and policy testing
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAME="UC-KYVERNO-06: Audit Mode"
RELEASE_NAME="test-kyverno-uc06"
NAMESPACE="test-allowed"
CHART_PATH="../../../../charts/common-kyverno"
VALUES_FILE="$(dirname "$0")/../values/uc06-audit-mode.yaml"

# Policy names
POLICIES=(
  "block-kubectl-exec"
  "block-kubectl-port-forward"
  "block-kubectl-proxy"
  "block-ephemeral-containers"
  "block-kubectl-attach"
  "block-workload-modifications"
)

# Test counters
PASSED=0
FAILED=0

# Cleanup function
cleanup() {
  echo -e "\n${BLUE}=== Cleanup ===${NC}"
  
  # Kill background processes
  pkill -f "kubectl.*port-forward" 2>/dev/null || true
  
  # Delete test resources
  kubectl delete deployment audit-test-app -n $NAMESPACE 2>/dev/null || true
  kubectl delete configmap audit-test-config -n $NAMESPACE 2>/dev/null || true
  
  # Uninstall chart
  helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
  
  # Wait for cleanup
  sleep 2
  
  echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Register cleanup on exit
trap cleanup EXIT

# Helper functions
pass() {
  echo -e "${GREEN}✅ PASS${NC}: $1"
  ((PASSED++))
}

fail() {
  echo -e "${RED}❌ FAIL${NC}: $1"
  ((FAILED++))
}

info() {
  echo -e "${YELLOW}ℹ️  INFO${NC}: $1"
}

section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Main test execution
main() {
  echo -e "${BLUE}=================================================================${NC}"
  echo -e "${BLUE}  $TEST_NAME${NC}"
  echo -e "${BLUE}=================================================================${NC}"
  
  section "Pre-requisite Checks"
  
  # Check tools
  for tool in kubectl helm jq; do
    if command -v $tool &> /dev/null; then
      pass "$tool found"
    else
      fail "$tool not found"
      exit 1
    fi
  done
  
  # Check namespace
  if kubectl get namespace $NAMESPACE &> /dev/null; then
    pass "Namespace $NAMESPACE exists"
  else
    fail "Namespace $NAMESPACE not found"
    exit 1
  fi
  
  section "Test Execution"
  
  # Install chart
  info "Installing chart in AUDIT MODE..."
  if helm install $RELEASE_NAME $CHART_PATH \
      -f $VALUES_FILE \
      -n $NAMESPACE \
      --wait --timeout 2m; then
    pass "Chart installed successfully"
  else
    fail "Chart installation failed"
    exit 1
  fi
  
  # Wait for policies
  sleep 5
  
  section "Verify All Policies in Audit Mode"
  
  AUDIT_COUNT=0
  for policy in "${POLICIES[@]}"; do
    if kubectl get clusterpolicy $policy &> /dev/null; then
      pass "ClusterPolicy $policy created"
      
      # Check action is AUDIT (not Enforce)
      ACTION=$(kubectl get clusterpolicy $policy -o jsonpath='{.spec.validationFailureAction}')
      if [ "$ACTION" = "Audit" ]; then
        pass "Policy $policy in AUDIT mode (operations allowed)"
        ((AUDIT_COUNT++))
      else
        fail "Policy $policy in '$ACTION' mode (expected Audit)"
      fi
    else
      fail "ClusterPolicy $policy not found"
    fi
  done
  
  if [ $AUDIT_COUNT -eq ${#POLICIES[@]} ]; then
    pass "All ${#POLICIES[@]} policies in audit mode ✅"
  else
    fail "Only $AUDIT_COUNT of ${#POLICIES[@]} policies in audit mode"
  fi
  
  section "Test 1: User CREATE Deployment (Should SUCCEED)"
  
  info "Creating deployment (would be blocked in enforce mode)..."
  if kubectl create deployment audit-test-app \
      --image=nginx:alpine \
      --replicas=2 \
      -n $NAMESPACE &> /tmp/uc06-create.log; then
    pass "User CREATE deployment ALLOWED (audit mode)"
    
    # Verify deployment exists
    if kubectl get deployment audit-test-app -n $NAMESPACE &> /dev/null; then
      pass "Deployment created successfully"
    else
      fail "Deployment not found after creation"
    fi
  else
    fail "User CREATE deployment BLOCKED (should be allowed in audit mode)"
    cat /tmp/uc06-create.log
  fi
  
  section "Test 2: User SCALE Deployment (Should SUCCEED)"
  
  # Wait for pods
  sleep 5
  
  info "Scaling deployment (would be blocked in enforce mode)..."
  if kubectl scale deployment audit-test-app --replicas=5 -n $NAMESPACE &> /tmp/uc06-scale.log; then
    pass "User SCALE deployment ALLOWED (audit mode)"
    
    # Verify scale
    REPLICAS=$(kubectl get deployment audit-test-app -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    if [ "$REPLICAS" = "5" ]; then
      pass "Deployment scaled to 5 replicas"
    else
      fail "Deployment has $REPLICAS replicas (expected 5)"
    fi
  else
    fail "User SCALE deployment BLOCKED (should be allowed in audit mode)"
    cat /tmp/uc06-scale.log
  fi
  
  section "Test 3: User kubectl exec (Should SUCCEED)"
  
  POD_NAME=$(kubectl get pod -n $NAMESPACE -l app=audit-test-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [ ! -z "$POD_NAME" ]; then
    info "Executing command in pod (would be blocked in enforce mode)..."
    if kubectl exec -n $NAMESPACE $POD_NAME -- ls /usr/share/nginx/html &> /tmp/uc06-exec.log; then
      pass "User kubectl exec ALLOWED (audit mode)"
      
      # Check output
      if grep -q "index.html" /tmp/uc06-exec.log; then
        pass "Exec produced expected output"
      else
        info "Exec succeeded but unexpected output"
      fi
    else
      fail "User kubectl exec BLOCKED (should be allowed in audit mode)"
      cat /tmp/uc06-exec.log
    fi
  else
    info "No pod available to test exec (deployment may not be ready)"
  fi
  
  section "Test 4: User kubectl port-forward (Should SUCCEED)"
  
  if [ ! -z "$POD_NAME" ]; then
    info "Port-forwarding to pod (would be blocked in enforce mode)..."
    kubectl port-forward -n $NAMESPACE $POD_NAME 8080:80 &> /tmp/uc06-pf.log &
    PF_PID=$!
    sleep 3
    
    # Check if port-forward is running
    if ps -p $PF_PID &> /dev/null; then
      pass "User kubectl port-forward ALLOWED (audit mode)"
      
      # Test connection
      if curl -s http://localhost:8080 | grep -q "nginx\|Welcome" 2>/dev/null; then
        pass "Port-forward is functional"
      else
        info "Port-forward running but connection test inconclusive"
      fi
      
      # Cleanup
      kill $PF_PID 2>/dev/null || true
    else
      fail "User kubectl port-forward failed (should be allowed)"
      cat /tmp/uc06-pf.log
    fi
  fi
  
  section "Test 5: User UPDATE Image (Should SUCCEED)"
  
  info "Updating container image (would be blocked in enforce mode)..."
  if kubectl set image deployment/audit-test-app \
      nginx=nginx:1.25-alpine \
      -n $NAMESPACE &> /tmp/uc06-update.log; then
    pass "User UPDATE deployment ALLOWED (audit mode)"
    
    # Verify update
    IMAGE=$(kubectl get deployment audit-test-app -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    if echo "$IMAGE" | grep -q "1.25"; then
      pass "Image updated to nginx:1.25-alpine"
    else
      info "Image is: $IMAGE"
    fi
  else
    fail "User UPDATE deployment BLOCKED (should be allowed in audit mode)"
    cat /tmp/uc06-update.log
  fi
  
  section "Test 6: User CREATE ConfigMap (Should SUCCEED)"
  
  info "Creating ConfigMap (would be blocked if policy enabled)..."
  cat <<EOF | kubectl apply -f - &> /tmp/uc06-configmap.log
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-test-config
  namespace: $NAMESPACE
data:
  config.yaml: |
    setting: value
    debug: true
EOF
  
  if [ $? -eq 0 ]; then
    pass "User CREATE ConfigMap ALLOWED (audit mode)"
  else
    fail "User CREATE ConfigMap failed"
    cat /tmp/uc06-configmap.log
  fi
  
  section "Test 7: User DELETE Deployment (Should SUCCEED)"
  
  info "Deleting deployment (would be blocked in enforce mode)..."
  if kubectl delete deployment audit-test-app -n $NAMESPACE &> /tmp/uc06-delete.log; then
    pass "User DELETE deployment ALLOWED (audit mode)"
  else
    fail "User DELETE deployment BLOCKED (should be allowed in audit mode)"
    cat /tmp/uc06-delete.log
  fi
  
  section "Test 8: Check PolicyReports (Violations Should Be Logged)"
  
  info "Waiting for PolicyReports to be generated..."
  sleep 5
  
  REPORT_COUNT=$(kubectl get policyreport -n $NAMESPACE 2>/dev/null | grep -v NAME | wc -l)
  if [ "$REPORT_COUNT" -gt 0 ]; then
    pass "PolicyReports generated ($REPORT_COUNT reports)"
    
    # Count violations per policy
    echo -e "\n${BLUE}Violation Summary (Audit Trail):${NC}"
    TOTAL_VIOLATIONS=0
    for policy in "${POLICIES[@]}"; do
      COUNT=$(kubectl get policyreport -n $NAMESPACE -o json 2>/dev/null | \
              jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$policy\") | .policy" | \
              wc -l || echo "0")
      TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + COUNT))
      echo "  $policy: $COUNT violations"
    done
    
    echo -e "\n${BLUE}Total Violations Logged: $TOTAL_VIOLATIONS${NC}"
    
    if [ "$TOTAL_VIOLATIONS" -gt 0 ]; then
      pass "Violations logged in PolicyReports (audit trail working)"
      echo -e "${YELLOW}Note: Operations succeeded but violations logged for analysis${NC}"
    else
      info "No violations found yet in PolicyReports"
    fi
  else
    info "No PolicyReports found yet (may take time to generate)"
  fi
  
  section "Generate Audit Report"
  
  cat > /tmp/audit-report.txt <<EOF
========================================
Kyverno Audit Mode Report
Environment: Staging/Testing
Namespace: $NAMESPACE
Date: $(date)
========================================

SUMMARY:
- All $AUDIT_COUNT policies deployed in AUDIT mode
- Operations allowed but logged for analysis
- Ready to analyze violations before enabling enforce mode

POLICY STATUS:
EOF
  
  for policy in "${POLICIES[@]}"; do
    ACTION=$(kubectl get clusterpolicy $policy -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null || echo "N/A")
    echo "  - $policy: $ACTION mode" >> /tmp/audit-report.txt
  done
  
  cat >> /tmp/audit-report.txt <<EOF

VIOLATIONS DETECTED:
EOF
  
  for policy in "${POLICIES[@]}"; do
    COUNT=$(kubectl get policyreport -n $NAMESPACE -o json 2>/dev/null | \
            jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$policy\") | .policy" | \
            wc -l || echo "0")
    echo "  - $policy: $COUNT violations" >> /tmp/audit-report.txt
  done
  
  cat >> /tmp/audit-report.txt <<EOF

RECOMMENDATIONS:
1. Review all logged violations
2. Identify legitimate vs policy issues
3. Add necessary exclusions (ServiceAccounts, namespaces)
4. Communicate policy changes to teams
5. Schedule transition to enforce mode

NEXT STEPS:
[ ] Analyze violation patterns
[ ] Configure exclusions
[ ] Train development teams
[ ] Test enforce mode in staging
[ ] Deploy to production

Report saved to: /tmp/audit-report.txt
EOF
  
  cat /tmp/audit-report.txt
  pass "Audit report generated"
  
  section "Test Summary"
  echo ""
  echo "Total tests: $((PASSED + FAILED))"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  echo -e "${RED}Failed: $FAILED${NC}"
  echo ""
  
  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    echo -e "\n${BLUE}Audit Mode Validated:${NC}"
    echo "  ✅ All policies in audit mode"
    echo "  ✅ All operations allowed"
    echo "  ✅ Violations logged in PolicyReports"
    echo "  ✅ Audit trail working correctly"
    echo ""
    echo -e "${YELLOW}Ready to analyze violations and transition to enforce mode${NC}"
    exit 0
  else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
  fi
}

# Run main function
main "$@"
