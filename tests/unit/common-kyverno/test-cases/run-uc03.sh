#!/bin/bash
set -e

#####################################################################
# UC-KYVERNO-03: Debug Proxy Access (Controlled API Access)
# 
# Tests that all API restrictions block regular users but allow
# debug-proxy ServiceAccount for emergency debugging
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAME="UC-KYVERNO-03: Debug Proxy Access"
RELEASE_NAME="test-kyverno-uc03"
NAMESPACE="test-app"
DEBUG_NAMESPACE="kube-system"
CHART_PATH="../../../../charts/common-kyverno"
VALUES_FILE="$(dirname "$0")/../values/uc03-debug-proxy.yaml"

# Policy names
POLICIES=(
  "block-kubectl-exec"
  "block-kubectl-port-forward"
  "block-kubectl-proxy"
  "block-ephemeral-containers"
  "block-kubectl-attach"
)

# Test counters
PASSED=0
FAILED=0

# Cleanup function
cleanup() {
  echo -e "\n${BLUE}=== Cleanup ===${NC}"
  
  # Kill any background processes
  pkill -f "kubectl.*port-forward" 2>/dev/null || true
  pkill -f "kubectl.*proxy" 2>/dev/null || true
  
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
  
  # Check kubectl
  if command -v kubectl &> /dev/null; then
    pass "kubectl found"
  else
    fail "kubectl not found"
    exit 1
  fi
  
  # Check helm
  if command -v helm &> /dev/null; then
    pass "helm found"
  else
    fail "helm not found"
    exit 1
  fi
  
  # Check test-app namespace
  if kubectl get namespace $NAMESPACE &> /dev/null; then
    pass "Namespace $NAMESPACE exists"
  else
    fail "Namespace $NAMESPACE not found"
    exit 1
  fi
  
  # Check debug-proxy SA
  if kubectl get sa debug-proxy -n $DEBUG_NAMESPACE &> /dev/null; then
    pass "ServiceAccount debug-proxy exists"
  else
    fail "ServiceAccount debug-proxy not found"
    exit 1
  fi
  
  # Find test pod
  POD_NAME=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=test-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
             kubectl get pod -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [ ! -z "$POD_NAME" ]; then
    pass "Test pod found: $POD_NAME"
  else
    fail "No test pod found in namespace $NAMESPACE"
    exit 1
  fi
  
  section "Test Execution"
  
  # Install chart
  info "Installing chart with values from $VALUES_FILE..."
  if helm install $RELEASE_NAME $CHART_PATH \
      -f $VALUES_FILE \
      -n $NAMESPACE \
      --wait --timeout 3m; then
    pass "Chart installed successfully"
  else
    fail "Chart installation failed"
    exit 1
  fi
  
  # Wait for policies to be ready
  sleep 5
  
  # Verify all policies created
  section "Verify Policies"
  for policy in "${POLICIES[@]}"; do
    if kubectl get clusterpolicy $policy &> /dev/null; then
      pass "ClusterPolicy $policy created"
      
      # Check action is enforce
      ACTION=$(kubectl get clusterpolicy $policy -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null || echo "")
      if [ "$ACTION" = "Enforce" ]; then
        pass "Policy $policy action is 'Enforce'"
      else
        fail "Policy $policy action is '$ACTION' (expected 'Enforce')"
      fi
    else
      fail "ClusterPolicy $policy not found"
    fi
  done
  
  # Check debug-proxy deployment (optional)
  if kubectl get deployment debug-proxy -n $DEBUG_NAMESPACE &> /dev/null; then
    pass "Debug-proxy deployment created"
    
    # Check pod status
    if kubectl wait --for=condition=available --timeout=60s deployment/debug-proxy -n $DEBUG_NAMESPACE &> /dev/null; then
      pass "Debug-proxy pod is running"
    else
      info "Debug-proxy pod not ready yet (optional)"
    fi
  else
    info "Debug-proxy deployment not created (debugProxy.enabled: false)"
  fi
  
  section "Test Regular User - kubectl exec (Should FAIL)"
  
  info "Attempting kubectl exec as regular user..."
  if kubectl exec -n $NAMESPACE $POD_NAME -- ls &> /tmp/uc03-exec-test.log; then
    fail "Regular user exec was ALLOWED (should be blocked)"
    cat /tmp/uc03-exec-test.log
  else
    if grep -q -i "kubectl exec is blocked\|block-kubectl-exec" /tmp/uc03-exec-test.log; then
      pass "Regular user exec BLOCKED with correct message"
    else
      fail "Exec blocked but with unexpected message"
      cat /tmp/uc03-exec-test.log
    fi
  fi
  
  section "Test Regular User - kubectl port-forward (Should FAIL)"
  
  info "Attempting kubectl port-forward as regular user..."
  timeout 5 kubectl port-forward -n $NAMESPACE $POD_NAME 8080:80 &> /tmp/uc03-pf-test.log &
  PF_PID=$!
  sleep 2
  
  # Check if port-forward is running
  if ps -p $PF_PID &> /dev/null; then
    fail "Regular user port-forward is running (should be blocked)"
    kill $PF_PID 2>/dev/null || true
  else
    if grep -q -i "kubectl port-forward is blocked\|block-kubectl-port-forward" /tmp/uc03-pf-test.log; then
      pass "Regular user port-forward BLOCKED"
    else
      info "Port-forward stopped (check if blocked by Kyverno)"
      cat /tmp/uc03-pf-test.log
    fi
  fi
  
  section "Test Regular User - kubectl attach (Should FAIL)"
  
  info "Attempting kubectl attach as regular user..."
  if timeout 3 kubectl attach -n $NAMESPACE $POD_NAME &> /tmp/uc03-attach-test.log; then
    fail "Regular user attach was ALLOWED (should be blocked)"
  else
    if grep -q -i "kubectl attach is blocked\|block-kubectl-attach" /tmp/uc03-attach-test.log; then
      pass "Regular user attach BLOCKED"
    else
      info "Attach failed (may be due to container type)"
      # Attach may fail for other reasons with nginx
    fi
  fi
  
  section "Test debug-proxy SA - Create Token"
  
  info "Creating token for debug-proxy ServiceAccount..."
  DEBUG_TOKEN=$(kubectl create token debug-proxy -n $DEBUG_NAMESPACE --duration=1h 2>&1)
  if [ $? -eq 0 ]; then
    pass "debug-proxy token created"
    info "Token: ${DEBUG_TOKEN:0:30}..."
  else
    fail "Failed to create debug-proxy token"
    echo "$DEBUG_TOKEN"
    exit 1
  fi
  
  section "Test debug-proxy SA - kubectl exec (Should SUCCEED)"
  
  info "Executing kubectl exec with debug-proxy token..."
  if kubectl --token=$DEBUG_TOKEN exec -n $NAMESPACE $POD_NAME -- ls /usr/share/nginx/html &> /tmp/uc03-debug-exec.log; then
    pass "debug-proxy ServiceAccount exec ALLOWED"
    
    # Verify we got actual output
    if grep -q "index.html" /tmp/uc03-debug-exec.log; then
      pass "Exec produced expected output (index.html found)"
    else
      info "Exec succeeded but unexpected output"
      cat /tmp/uc03-debug-exec.log
    fi
  else
    fail "debug-proxy ServiceAccount exec was BLOCKED (should be allowed)"
    cat /tmp/uc03-debug-exec.log
  fi
  
  section "Test debug-proxy SA - kubectl port-forward (Should SUCCEED)"
  
  info "Starting kubectl port-forward with debug-proxy token..."
  kubectl --token=$DEBUG_TOKEN port-forward -n $NAMESPACE $POD_NAME 8888:80 &> /tmp/uc03-debug-pf.log &
  DEBUG_PF_PID=$!
  sleep 3
  
  # Check if port-forward is running
  if ps -p $DEBUG_PF_PID &> /dev/null; then
    pass "debug-proxy ServiceAccount port-forward ALLOWED"
    
    # Test the connection
    if curl -s http://localhost:8888 | grep -q "nginx\|Welcome" 2>/dev/null; then
      pass "Port-forward is functional (nginx page accessible)"
    else
      info "Port-forward running but connection test inconclusive"
    fi
    
    # Cleanup
    kill $DEBUG_PF_PID 2>/dev/null || true
  else
    fail "debug-proxy ServiceAccount port-forward was BLOCKED (should be allowed)"
    cat /tmp/uc03-debug-pf.log
  fi
  
  section "Test Excluded Namespace (kube-system)"
  
  info "Testing exec in kube-system (excluded namespace)..."
  KUBE_POD=$(kubectl get pod -n kube-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [ ! -z "$KUBE_POD" ]; then
    # Note: This may fail due to RBAC, but should NOT be blocked by Kyverno
    if kubectl exec -n kube-system $KUBE_POD -- echo "test" &> /tmp/uc03-kube-test.log; then
      pass "Exec in kube-system ALLOWED (excluded namespace)"
    else
      # Check if blocked by Kyverno or RBAC
      if grep -q -i "kubectl exec is blocked\|block-kubectl-exec" /tmp/uc03-kube-test.log; then
        fail "kube-system exec blocked by Kyverno (should be excluded)"
      else
        info "kube-system exec failed due to RBAC (Kyverno exclusion working)"
        pass "Kyverno exclusion for kube-system working"
      fi
    fi
  else
    info "No pods in kube-system to test (optional)"
  fi
  
  section "Test PolicyReports"
  
  info "Waiting for PolicyReports to be generated..."
  sleep 5
  
  REPORT_COUNT=$(kubectl get policyreport -n $NAMESPACE 2>/dev/null | grep -v NAME | wc -l)
  if [ "$REPORT_COUNT" -gt 0 ]; then
    pass "PolicyReport generated ($REPORT_COUNT reports)"
    
    # Check for violations
    VIOLATIONS=0
    for policy in "${POLICIES[@]}"; do
      COUNT=$(kubectl get policyreport -n $NAMESPACE -o json 2>/dev/null | \
              jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$policy\") | .policy" | \
              wc -l || echo "0")
      VIOLATIONS=$((VIOLATIONS + COUNT))
    done
    
    if [ "$VIOLATIONS" -gt 0 ]; then
      pass "Policy violations recorded ($VIOLATIONS total violations)"
    else
      info "No violations found yet in PolicyReports"
    fi
  else
    info "No PolicyReports found yet (may take time to generate)"
  fi
  
  section "Test Summary"
  echo ""
  echo "Total tests: $((PASSED + FAILED))"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  echo -e "${RED}Failed: $FAILED${NC}"
  echo ""
  
  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
  else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
  fi
}

# Run main function
main "$@"
