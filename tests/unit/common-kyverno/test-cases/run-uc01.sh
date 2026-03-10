#!/bin/bash

##############################################################################
# UC-KYVERNO-01: Block kubectl exec - Automated Test
#
# This script automatically tests the kubectl exec blocking policy
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-KYVERNO-01: Block kubectl exec"
RELEASE_NAME="test-kyverno-uc01"
NAMESPACE="test-app"
CHART_PATH="../../../../charts/common-kyverno"
VALUES_FILE="./values/uc01-block-exec.yaml"

PASSED=0
FAILED=0

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

##############################################################################
# Helper Functions
##############################################################################

pass() {
  echo -e "${GREEN}✅ PASS: $1${NC}"
  ((PASSED++))
}

fail() {
  echo -e "${RED}❌ FAIL: $1${NC}"
  ((FAILED++))
}

info() {
  echo -e "${YELLOW}ℹ️  $1${NC}"
}

##############################################################################
# Cleanup Function
##############################################################################

cleanup() {
  info "Cleaning up test resources..."
  helm uninstall $RELEASE_NAME -n $NAMESPACE --wait 2>/dev/null || true
  kubectl delete pod test-exec-target -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true
  echo ""
}

# Trap cleanup on exit
trap cleanup EXIT

##############################################################################
# Pre-requisite Checks
##############################################################################

echo -e "${BLUE}=== Pre-requisite Checks ===${NC}"
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  fail "kubectl not found"
  exit 1
fi
pass "kubectl found"

# Check helm
if ! command -v helm &> /dev/null; then
  fail "helm not found"
  exit 1
fi
pass "helm found"

# Check namespace
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
  fail "Namespace $NAMESPACE not found"
  info "Run: kubectl create namespace $NAMESPACE"
  exit 1
fi
pass "Namespace $NAMESPACE exists"

# Check test-nginx deployment
if ! kubectl get deployment test-nginx -n $NAMESPACE &> /dev/null; then
  info "test-nginx deployment not found, deploying..."
  kubectl run test-exec-target --image=nginx:alpine -n $NAMESPACE
  kubectl wait --for=condition=ready pod/test-exec-target -n $NAMESPACE --timeout=60s
fi
pass "Test pod available"

# Check debug-proxy ServiceAccount
if ! kubectl get sa debug-proxy -n kube-system &> /dev/null; then
  fail "debug-proxy ServiceAccount not found"
  info "Run: kubectl apply -f ../../prerequisites/test-serviceaccounts.yaml"
  exit 1
fi
pass "debug-proxy ServiceAccount exists"

echo ""

##############################################################################
# Test Execution
##############################################################################

echo -e "${BLUE}=== Test Execution ===${NC}"
echo ""

# Step 1: Install Chart
info "Installing chart with values from $VALUES_FILE..."
if helm install $RELEASE_NAME $CHART_PATH \
  -f $VALUES_FILE \
  -n $NAMESPACE \
  --wait \
  --timeout 2m &> /tmp/helm-install.log; then
  pass "Chart installed successfully"
else
  fail "Chart installation failed"
  cat /tmp/helm-install.log
  exit 1
fi
echo ""

# Wait for policy to be ready
info "Waiting for Kyverno policy to be active..."
sleep 5

# Step 2: Verify Policy Created
info "Verifying ClusterPolicy 'block-kubectl-exec' exists..."
if kubectl get clusterpolicy block-kubectl-exec &> /dev/null; then
  pass "ClusterPolicy created"
  
  # Check policy details
  ACTION=$(kubectl get clusterpolicy block-kubectl-exec -o jsonpath='{.spec.validationFailureAction}')
  if [ "$ACTION" = "Enforce" ] || [ "$ACTION" = "enforce" ]; then
    pass "Policy action is 'enforce'"
  else
    fail "Policy action is '$ACTION' (expected 'enforce')"
  fi
else
  fail "ClusterPolicy not found"
  exit 1
fi
echo ""

# Step 3: Test Regular User (Should FAIL)
info "Test 1: Regular user exec (should be BLOCKED)..."
POD_NAME=$(kubectl get pod -n $NAMESPACE -l run=test-exec-target -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "test-exec-target")

if kubectl exec -n $NAMESPACE $POD_NAME -- ls &> /tmp/exec-test.log; then
  fail "Regular user exec was ALLOWED (should be blocked)"
  cat /tmp/exec-test.log
else
  # Check error message
  if grep -q "kubectl exec is not allowed" /tmp/exec-test.log || \
     grep -q "admission webhook.*denied" /tmp/exec-test.log; then
    pass "Regular user exec BLOCKED with correct message"
  else
    fail "Regular user exec blocked but with unexpected error"
    cat /tmp/exec-test.log
  fi
fi
echo ""

# Step 4: Test Debug-Proxy ServiceAccount (Should SUCCEED)
info "Test 2: Debug-proxy ServiceAccount exec (should be ALLOWED)..."

# Create token for debug-proxy SA
DEBUG_TOKEN=$(kubectl create token debug-proxy -n kube-system --duration=1h 2>/dev/null)

if [ -z "$DEBUG_TOKEN" ]; then
  fail "Failed to create debug-proxy token"
else
  pass "Debug-proxy token created"
  
  # Test exec with debug-proxy identity
  if kubectl --token=$DEBUG_TOKEN exec -n $NAMESPACE $POD_NAME -- ls &> /tmp/exec-debug.log; then
    pass "Debug-proxy ServiceAccount exec ALLOWED"
  else
    fail "Debug-proxy ServiceAccount exec BLOCKED (should be allowed)"
    cat /tmp/exec-debug.log
  fi
fi
echo ""

# Step 5: Test Excluded Namespace (Should SUCCEED)
info "Test 3: Exec in excluded namespace (should be ALLOWED)..."

# Find a pod in kube-system
KUBE_SYSTEM_POD=$(kubectl get pod -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$KUBE_SYSTEM_POD" ]; then
  info "No suitable pod in kube-system, skipping test"
else
  if kubectl exec -n kube-system $KUBE_SYSTEM_POD -- ls &> /dev/null; then
    pass "Exec in kube-system (excluded namespace) ALLOWED"
  else
    fail "Exec in kube-system BLOCKED (should be allowed)"
  fi
fi
echo ""

# Step 6: Check PolicyReport
info "Test 4: Checking PolicyReport for violations..."
sleep 3  # Wait for report to be generated

if kubectl get policyreport -n $NAMESPACE &> /dev/null; then
  REPORT_COUNT=$(kubectl get policyreport -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
  if [ "$REPORT_COUNT" -gt 0 ]; then
    pass "PolicyReport generated ($REPORT_COUNT reports)"
    
    # Check for violations
    VIOLATIONS=$(kubectl get policyreport -n $NAMESPACE -o json 2>/dev/null | \
                 jq -r '.items[].results[] | select(.result=="fail") | .message' 2>/dev/null || echo "")
    
    if [ -n "$VIOLATIONS" ]; then
      pass "Policy violations recorded in report"
    else
      info "No violations in current report (may take a moment to appear)"
    fi
  else
    info "PolicyReport not yet generated (this is normal)"
  fi
else
  info "PolicyReport CRD not available (Kyverno reports controller may not be running)"
fi
echo ""

##############################################################################
# Summary
##############################################################################

echo -e "${BLUE}=== Test Summary ===${NC}"
echo ""

TOTAL=$((PASSED + FAILED))
echo "Total tests: $TOTAL"
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
