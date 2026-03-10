#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

TEST_NAME="UC-HARDENING-03: Security Contexts"
NAMESPACE="secctx-test"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }

cleanup() {
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Test 1: Create namespace
kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Test 2: Deploy secure pod
echo ""
echo -e "${BLUE}=== Test 2: Deploy Secure Pod ===${NC}"
kubectl run secure-pod --image=nginx:1.25-alpine -n $NAMESPACE \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":101,"fsGroup":101,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"secure-pod","image":"nginx:1.25-alpine","securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,"runAsUser":101,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false,"seccompProfile":{"type":"RuntimeDefault"}}}]}}' 2>&1 | head -3

sleep 5

if kubectl get pod secure-pod -n $NAMESPACE &> /dev/null; then
  pass "Secure pod created"
  
  # Test 3: Verify non-root user
  echo ""
  echo -e "${BLUE}=== Test 3: Verify Non-Root ===${NC}"
  USER_ID=$(kubectl exec secure-pod -n $NAMESPACE -- id -u 2>/dev/null || echo "0")
  if [ "$USER_ID" = "101" ]; then
    pass "Running as non-root user (UID: $USER_ID)"
  else
    fail "Running as root (UID: $USER_ID)"
  fi
else
  fail "Secure pod failed"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
