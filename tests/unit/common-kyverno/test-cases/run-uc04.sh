#!/bin/bash
set -e

#####################################################################
# UC-KYVERNO-04: GitOps Workflow (Full Enforcement)
# 
# Tests complete production GitOps setup with all 6 policies enabled
# Validates proper workflow: Git → CI/CD → Kubernetes
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAME="UC-KYVERNO-04: GitOps Workflow (Full Enforcement)"
RELEASE_NAME="test-kyverno-uc04"
NAMESPACE="test-blocked"
CI_CD_NAMESPACE="ci-cd"
FLUX_NAMESPACE="flux-system"
DEBUG_NAMESPACE="kube-system"
CHART_PATH="../../../../charts/common-kyverno"
VALUES_FILE="$(dirname "$0")/../values/uc04-gitops-full.yaml"

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
  
  # Delete deployments (using tokens if available)
  if [ ! -z "$DEPLOY_TOKEN" ]; then
    kubectl --token=$DEPLOY_TOKEN delete deployment gitops-app -n $NAMESPACE 2>/dev/null || true
  fi
  if [ ! -z "$FLUX_TOKEN" ]; then
    kubectl --token=$FLUX_TOKEN delete deployment flux-app -n $NAMESPACE 2>/dev/null || true
  fi
  
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
  
  # Check namespaces
  for ns in $NAMESPACE $CI_CD_NAMESPACE $DEBUG_NAMESPACE; do
    if kubectl get namespace $ns &> /dev/null; then
      pass "Namespace $ns exists"
    else
      fail "Namespace $ns not found"
      exit 1
    fi
  done
  
  # Check ServiceAccounts
  if kubectl get sa deployment-job -n $CI_CD_NAMESPACE &> /dev/null; then
    pass "ServiceAccount deployment-job exists"
  else
    fail "ServiceAccount deployment-job not found"
    exit 1
  fi
  
  if kubectl get sa debug-proxy -n $DEBUG_NAMESPACE &> /dev/null; then
    pass "ServiceAccount debug-proxy exists"
  else
    fail "ServiceAccount debug-proxy not found"
    exit 1
  fi
  
  # Check flux-system (optional)
  if kubectl get namespace $FLUX_NAMESPACE &> /dev/null; then
    FLUX_AVAILABLE=true
    pass "Namespace $FLUX_NAMESPACE exists (optional)"
  else
    FLUX_AVAILABLE=false
    info "Namespace $FLUX_NAMESPACE not found (optional)"
  fi
  
  section "Test Execution"
  
  # Install chart
  info "Installing chart with all policies enabled..."
  if helm install $RELEASE_NAME $CHART_PATH \
      -f $VALUES_FILE \
      -n $NAMESPACE \
      --wait --timeout 3m; then
    pass "Chart installed successfully"
  else
    fail "Chart installation failed"
    exit 1
  fi
  
  # Wait for policies
  sleep 5
  
  section "Verify All Policies"
  
  POLICY_COUNT=0
  for policy in "${POLICIES[@]}"; do
    if kubectl get clusterpolicy $policy &> /dev/null; then
      pass "ClusterPolicy $policy created"
      ((POLICY_COUNT++))
      
      # Check action
      ACTION=$(kubectl get clusterpolicy $policy -o jsonpath='{.spec.validationFailureAction}')
      if [ "$ACTION" = "Enforce" ]; then
        pass "Policy $policy in enforce mode"
      else
        fail "Policy $policy in '$ACTION' mode (expected Enforce)"
      fi
    else
      fail "ClusterPolicy $policy not found"
    fi
  done
  
  if [ $POLICY_COUNT -eq ${#POLICIES[@]} ]; then
    pass "All ${#POLICIES[@]} policies created"
  else
    fail "Only $POLICY_COUNT of ${#POLICIES[@]} policies created"
  fi
  
  section "Test User Workflow - Manual Deployment (Should FAIL)"
  
  info "User attempting manual deployment..."
  if kubectl create deployment manual-app --image=nginx:alpine -n $NAMESPACE &> /tmp/uc04-manual.log; then
    fail "User manual deployment ALLOWED (should be blocked)"
  else
    if grep -q -i "direct workload modifications are blocked\|block-workload-modifications" /tmp/uc04-manual.log; then
      pass "User manual deployment BLOCKED by GitOps policy"
    else
      fail "Deployment blocked but unexpected message"
      cat /tmp/uc04-manual.log
    fi
  fi
  
  section "Test GitOps Workflow - CI/CD Deployment (Should SUCCEED)"
  
  info "Creating token for deployment-job..."
  DEPLOY_TOKEN=$(kubectl create token deployment-job -n $CI_CD_NAMESPACE --duration=1h 2>&1)
  if [ $? -eq 0 ]; then
    pass "deployment-job token created"
  else
    fail "Failed to create deployment-job token"
    exit 1
  fi
  
  info "CI/CD deploying application via GitOps..."
  if kubectl --token=$DEPLOY_TOKEN create deployment gitops-app \
      --image=nginx:alpine \
      --replicas=2 \
      -n $NAMESPACE &> /tmp/uc04-gitops.log; then
    pass "CI/CD deployment ALLOWED (GitOps workflow)"
    
    # Wait for pod
    sleep 5
    
    # Verify deployment
    if kubectl get deployment gitops-app -n $NAMESPACE &> /dev/null; then
      pass "Deployment gitops-app created successfully"
    else
      fail "Deployment gitops-app not found"
    fi
  else
    fail "CI/CD deployment BLOCKED (should be allowed)"
    cat /tmp/uc04-gitops.log
  fi
  
  section "Test User Workflow - Scale Attempt (Should FAIL)"
  
  info "User attempting to scale deployment..."
  if kubectl scale deployment gitops-app --replicas=5 -n $NAMESPACE &> /tmp/uc04-scale.log; then
    fail "User scale operation ALLOWED (should be blocked)"
  else
    if grep -q -i "direct workload modifications are blocked\|block-workload-modifications" /tmp/uc04-scale.log; then
      pass "User scale operation BLOCKED by GitOps policy"
    else
      fail "Scale blocked but unexpected message"
    fi
  fi
  
  section "Test User Workflow - kubectl exec (Should FAIL)"
  
  POD_NAME=$(kubectl get pod -n $NAMESPACE -l app=gitops-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [ ! -z "$POD_NAME" ]; then
    info "User attempting kubectl exec..."
    if kubectl exec -n $NAMESPACE $POD_NAME -- ls &> /tmp/uc04-exec.log; then
      fail "User kubectl exec ALLOWED (should be blocked)"
    else
      if grep -q -i "kubectl exec is blocked\|block-kubectl-exec" /tmp/uc04-exec.log; then
        pass "User kubectl exec BLOCKED by API restriction"
      else
        fail "Exec blocked but unexpected message"
      fi
    fi
  else
    info "No pod available to test exec (deployment may not be ready)"
  fi
  
  section "Test Debug-Proxy - Emergency Access (Should SUCCEED)"
  
  if [ ! -z "$POD_NAME" ]; then
    info "Creating debug-proxy token..."
    DEBUG_TOKEN=$(kubectl create token debug-proxy -n $DEBUG_NAMESPACE --duration=30m 2>&1)
    if [ $? -eq 0 ]; then
      pass "debug-proxy token created"
      
      info "Emergency debugging with debug-proxy..."
      if kubectl --token=$DEBUG_TOKEN exec -n $NAMESPACE $POD_NAME -- ls /usr/share/nginx/html &> /tmp/uc04-debug.log; then
        pass "debug-proxy kubectl exec ALLOWED (emergency access)"
      else
        fail "debug-proxy kubectl exec BLOCKED (should be allowed)"
        cat /tmp/uc04-debug.log
      fi
    else
      fail "Failed to create debug-proxy token"
    fi
  fi
  
  section "Test flux-cd - GitOps Operator (Should SUCCEED - Optional)"
  
  if [ "$FLUX_AVAILABLE" = true ] && kubectl get sa flux-cd -n $FLUX_NAMESPACE &> /dev/null; then
    info "Creating flux-cd token..."
    FLUX_TOKEN=$(kubectl create token flux-cd -n $FLUX_NAMESPACE --duration=1h 2>&1)
    if [ $? -eq 0 ]; then
      pass "flux-cd token created"
      
      info "Flux CD deploying application..."
      if kubectl --token=$FLUX_TOKEN create deployment flux-app \
          --image=nginx:alpine \
          -n $NAMESPACE &> /tmp/uc04-flux.log; then
        pass "flux-cd deployment ALLOWED (GitOps operator)"
      else
        fail "flux-cd deployment BLOCKED (should be allowed)"
        cat /tmp/uc04-flux.log
      fi
    else
      info "Failed to create flux-cd token (optional)"
    fi
  else
    info "flux-cd not available (optional test skipped)"
  fi
  
  section "Test User Workflow - Delete Attempt (Should FAIL)"
  
  info "User attempting to delete deployment..."
  if kubectl delete deployment gitops-app -n $NAMESPACE --timeout=5s &> /tmp/uc04-delete.log; then
    fail "User delete operation ALLOWED (should be blocked)"
  else
    if grep -q -i "direct workload modifications are blocked\|block-workload-modifications" /tmp/uc04-delete.log; then
      pass "User delete operation BLOCKED by GitOps policy"
    else
      fail "Delete blocked but unexpected message"
    fi
  fi
  
  section "Test CI/CD Cleanup (Should SUCCEED)"
  
  info "CI/CD cleaning up deployment..."
  if kubectl --token=$DEPLOY_TOKEN delete deployment gitops-app -n $NAMESPACE &> /tmp/uc04-cleanup.log; then
    pass "CI/CD delete operation ALLOWED (GitOps workflow)"
  else
    fail "CI/CD delete operation BLOCKED (should be allowed)"
    cat /tmp/uc04-cleanup.log
  fi
  
  section "Test PolicyReports"
  
  info "Checking PolicyReports..."
  sleep 3
  
  REPORT_COUNT=$(kubectl get policyreport -n $NAMESPACE 2>/dev/null | grep -v NAME | wc -l)
  if [ "$REPORT_COUNT" -gt 0 ]; then
    pass "PolicyReports generated ($REPORT_COUNT reports)"
    
    # Count violations per policy
    echo -e "\n${BLUE}Violation Summary:${NC}"
    for policy in "${POLICIES[@]}"; do
      COUNT=$(kubectl get policyreport -n $NAMESPACE -o json 2>/dev/null | \
              jq -r ".items[].results[]? | select(.result==\"fail\" and .policy==\"$policy\") | .policy" | \
              wc -l || echo "0")
      echo "  $policy: $COUNT violations"
    done
  else
    info "No PolicyReports found yet"
  fi
  
  section "Test Summary"
  echo ""
  echo "Total tests: $((PASSED + FAILED))"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  echo -e "${RED}Failed: $FAILED${NC}"
  echo ""
  
  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    echo -e "\n${BLUE}GitOps Workflow Validated:${NC}"
    echo "  ✅ Users blocked from manual operations"
    echo "  ✅ CI/CD pipeline can deploy via GitOps"
    echo "  ✅ Debug-proxy provides emergency access"
    echo "  ✅ All policies enforced correctly"
    exit 0
  else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
  fi
}

# Run main function
main "$@"
