#!/bin/bash
set -e

#####################################################################
# UC-KYVERNO-02: Block Direct Deployments (GitOps-only pattern)
# 
# Tests that Kyverno blocks direct workload modifications by users
# but allows excluded ServiceAccounts (deployment-job, flux-cd)
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAME="UC-KYVERNO-02: Block Direct Deployments"
RELEASE_NAME="test-kyverno-uc02"
NAMESPACE="test-app"
CI_CD_NAMESPACE="ci-cd"
FLUX_NAMESPACE="flux-system"
CHART_PATH="../../../../charts/common-kyverno"
VALUES_FILE="$(dirname "$0")/../values/uc02-gitops-only.yaml"
POLICY_NAME="block-workload-modifications"

# Test counters
PASSED=0
FAILED=0

# Cleanup function
cleanup() {
  echo -e "\n${BLUE}=== Cleanup ===${NC}"
  
  # Delete test deployments (using SA tokens if available)
  if [ ! -z "$DEPLOY_TOKEN" ]; then
    kubectl --token=$DEPLOY_TOKEN delete deployment allowed-test -n $NAMESPACE 2>/dev/null || true
  fi
  if [ ! -z "$FLUX_TOKEN" ]; then
    kubectl --token=$FLUX_TOKEN delete deployment flux-test -n $NAMESPACE 2>/dev/null || true
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
  
  # Check namespace exists
  if kubectl get namespace $NAMESPACE &> /dev/null; then
    pass "Namespace $NAMESPACE exists"
  else
    fail "Namespace $NAMESPACE not found"
    exit 1
  fi
  
  # Check ci-cd namespace exists
  if kubectl get namespace $CI_CD_NAMESPACE &> /dev/null; then
    pass "Namespace $CI_CD_NAMESPACE exists"
  else
    fail "Namespace $CI_CD_NAMESPACE not found"
    exit 1
  fi
  
  # Check deployment-job SA exists
  if kubectl get sa deployment-job -n $CI_CD_NAMESPACE &> /dev/null; then
    pass "ServiceAccount deployment-job exists"
  else
    fail "ServiceAccount deployment-job not found"
    exit 1
  fi
  
  # Check flux-system namespace exists (optional)
  if kubectl get namespace $FLUX_NAMESPACE &> /dev/null; then
    pass "Namespace $FLUX_NAMESPACE exists"
    FLUX_AVAILABLE=true
  else
    info "Namespace $FLUX_NAMESPACE not found (optional)"
    FLUX_AVAILABLE=false
  fi
  
  section "Test Execution"
  
  # Install chart
  info "Installing chart with values from $VALUES_FILE..."
  if helm install $RELEASE_NAME $CHART_PATH \
      -f $VALUES_FILE \
      -n $NAMESPACE \
      --wait --timeout 2m; then
    pass "Chart installed successfully"
  else
    fail "Chart installation failed"
    exit 1
  fi
  
  # Wait for policy to be ready
  sleep 3
  
  # Verify ClusterPolicy created
  if kubectl get clusterpolicy $POLICY_NAME &> /dev/null; then
    pass "ClusterPolicy $POLICY_NAME created"
  else
    fail "ClusterPolicy $POLICY_NAME not found"
  fi
  
  # Check policy action is enforce
  POLICY_ACTION=$(kubectl get clusterpolicy $POLICY_NAME -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null || echo "")
  if [ "$POLICY_ACTION" = "Enforce" ]; then
    pass "Policy action is 'Enforce' (not audit)"
  else
    fail "Policy action is '$POLICY_ACTION' (expected 'Enforce')"
  fi
  
  section "Test 1: Regular User CREATE Deployment (Should FAIL)"
  
  info "Attempting to create deployment as regular user..."
  if kubectl create deployment blocked-test --image=nginx:alpine -n $NAMESPACE &> /tmp/uc02-create-test.log; then
    fail "Regular user CREATE deployment was ALLOWED (should be blocked)"
    cat /tmp/uc02-create-test.log
  else
    # Check error message contains policy violation
    if grep -q -i "direct workload modifications are not allowed\|block-workload-modifications" /tmp/uc02-create-test.log; then
      pass "Regular user CREATE deployment BLOCKED with correct message"
    else
      fail "Regular user CREATE deployment blocked but with unexpected message"
      cat /tmp/uc02-create-test.log
    fi
  fi
  
  section "Test 2: Regular User CREATE with YAML (Should FAIL)"
  
  info "Attempting to create deployment via YAML..."
  cat <<EOF | kubectl apply -f - -n $NAMESPACE &> /tmp/uc02-yaml-test.log && YAML_RESULT=$? || YAML_RESULT=$?
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blocked-yaml-test
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
  
  if [ $YAML_RESULT -eq 0 ]; then
    fail "Regular user CREATE deployment via YAML was ALLOWED (should be blocked)"
    cat /tmp/uc02-yaml-test.log
  else
    if grep -q -i "direct workload modifications are not allowed\|block-workload-modifications" /tmp/uc02-yaml-test.log; then
      pass "Regular user CREATE deployment via YAML BLOCKED"
    else
      fail "Deployment blocked but with unexpected message"
      cat /tmp/uc02-yaml-test.log
    fi
  fi
  
  section "Test 3: deployment-job SA CREATE (Should SUCCEED)"
  
  info "Creating token for deployment-job ServiceAccount..."
  DEPLOY_TOKEN=$(kubectl create token deployment-job -n $CI_CD_NAMESPACE --duration=1h 2>&1)
  if [ $? -eq 0 ]; then
    pass "deployment-job token created"
  else
    fail "Failed to create deployment-job token"
    echo "$DEPLOY_TOKEN"
  fi
  
  info "Creating deployment using deployment-job identity..."
  if kubectl --token=$DEPLOY_TOKEN create deployment allowed-test --image=nginx:alpine -n $NAMESPACE &> /tmp/uc02-deploy-job-test.log; then
    pass "deployment-job ServiceAccount CREATE deployment ALLOWED"
    
    # Verify deployment exists
    if kubectl get deployment allowed-test -n $NAMESPACE &> /dev/null; then
      pass "Deployment 'allowed-test' created successfully"
    else
      fail "Deployment 'allowed-test' not found after creation"
    fi
  else
    fail "deployment-job ServiceAccount CREATE deployment was BLOCKED (should be allowed)"
    cat /tmp/uc02-deploy-job-test.log
  fi
  
  section "Test 4: Regular User UPDATE (Should FAIL)"
  
  info "Attempting to scale deployment as regular user..."
  if kubectl scale deployment allowed-test --replicas=3 -n $NAMESPACE &> /tmp/uc02-update-test.log; then
    fail "Regular user UPDATE deployment was ALLOWED (should be blocked)"
  else
    if grep -q -i "direct workload modifications are not allowed\|block-workload-modifications" /tmp/uc02-update-test.log; then
      pass "Regular user UPDATE deployment BLOCKED"
    else
      fail "Update blocked but with unexpected message"
      cat /tmp/uc02-update-test.log
    fi
  fi
  
  section "Test 5: Regular User DELETE (Should FAIL)"
  
  info "Attempting to delete deployment as regular user..."
  if kubectl delete deployment allowed-test -n $NAMESPACE --timeout=5s &> /tmp/uc02-delete-test.log; then
    fail "Regular user DELETE deployment was ALLOWED (should be blocked)"
  else
    if grep -q -i "direct workload modifications are not allowed\|block-workload-modifications" /tmp/uc02-delete-test.log; then
      pass "Regular user DELETE deployment BLOCKED"
    else
      fail "Delete blocked but with unexpected message"
      cat /tmp/uc02-delete-test.log
    fi
  fi
  
  section "Test 6: flux-cd SA CREATE (Should SUCCEED - Optional)"
  
  if [ "$FLUX_AVAILABLE" = true ]; then
    # Check flux-cd SA exists
    if kubectl get sa flux-cd -n $FLUX_NAMESPACE &> /dev/null; then
      info "Creating token for flux-cd ServiceAccount..."
      FLUX_TOKEN=$(kubectl create token flux-cd -n $FLUX_NAMESPACE --duration=1h 2>&1)
      if [ $? -eq 0 ]; then
        pass "flux-cd token created"
        
        info "Creating deployment using flux-cd identity..."
        if kubectl --token=$FLUX_TOKEN create deployment flux-test --image=nginx:alpine -n $NAMESPACE &> /tmp/uc02-flux-test.log; then
          pass "flux-cd ServiceAccount CREATE deployment ALLOWED"
        else
          fail "flux-cd ServiceAccount CREATE deployment was BLOCKED (should be allowed)"
          cat /tmp/uc02-flux-test.log
        fi
      else
        info "Failed to create flux-cd token (optional test)"
      fi
    else
      info "ServiceAccount flux-cd not found (optional test skipped)"
    fi
  else
    info "flux-system namespace not available (optional test skipped)"
  fi
  
  section "Test 7: Check PolicyReport"
  
  info "Waiting for PolicyReports to be generated..."
  sleep 3
  
  REPORT_COUNT=$(kubectl get policyreport -n $NAMESPACE 2>/dev/null | grep -v NAME | wc -l)
  if [ "$REPORT_COUNT" -gt 0 ]; then
    pass "PolicyReport generated ($REPORT_COUNT reports)"
    
    # Check for violations
    VIOLATIONS=$(kubectl get policyreport -n $NAMESPACE -o json 2>/dev/null | \
                 jq -r '.items[].results[]? | select(.result=="fail") | .policy' | \
                 grep -c "$POLICY_NAME" || echo "0")
    
    if [ "$VIOLATIONS" -gt 0 ]; then
      pass "Policy violations recorded in report ($VIOLATIONS violations)"
    else
      info "No violations found in PolicyReport (may take time to appear)"
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
