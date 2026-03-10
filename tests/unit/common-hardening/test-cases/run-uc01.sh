#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

TEST_NAME="UC-HARDENING-01: Pod Security Standards"
NAMESPACE="pss-test"
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

# Test 1: Create namespace with PSS labels
echo ""
echo -e "${BLUE}=== Test 1: Apply PSS Labels ===${NC}"
kubectl create namespace $NAMESPACE 2>/dev/null || true
kubectl label namespace $NAMESPACE pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label namespace $NAMESPACE pod-security.kubernetes.io/audit=restricted --overwrite
kubectl label namespace $NAMESPACE pod-security.kubernetes.io/warn=restricted --overwrite
pass "PSS labels applied"

# Test 2: Deploy compliant pod
echo ""
echo -e "${BLUE}=== Test 2: Deploy Compliant Pod ===${NC}"
kubectl run compliant-pod --image=nginx:1.25-alpine --namespace=$NAMESPACE \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":101,"fsGroup":101,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"compliant-pod","image":"nginx:1.25-alpine","securityContext":{"allowPrivilegeEscalation":false,"runAsNonRoot":true,"runAsUser":101,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' 2>&1 | head -3

if kubectl get pod compliant-pod -n $NAMESPACE &> /dev/null; then
  pass "Compliant pod created"
else
  fail "Compliant pod failed"
fi

# Test 3: Attempt non-compliant pod
echo ""
echo -e "${BLUE}=== Test 3: Test Non-Compliant Pod ===${NC}"
if kubectl run non-compliant --image=nginx --namespace=$NAMESPACE --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}' 2>&1 | grep -qi "forbidden\|violates\|denied"; then
  pass "Non-compliant pod rejected (correct)"
else
  fail "Non-compliant pod allowed (should be rejected)"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
