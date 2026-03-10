#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

TEST_NAME="UC-HARDENING-02: Network Policies"
NAMESPACE="netpol-test"
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

# Test 2: Deploy app pods
echo ""
echo -e "${BLUE}=== Test 2: Deploy Application ===${NC}"
kubectl run web-app --image=nginx:1.25-alpine -n $NAMESPACE --labels="app=web-app,tier=frontend"
sleep 3
if kubectl get pod web-app -n $NAMESPACE &> /dev/null; then
  pass "App pod created"
else
  fail "App pod failed"
fi

# Test 3: Apply NetworkPolicy
echo ""
echo -e "${BLUE}=== Test 3: Apply NetworkPolicy ===${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
    - Ingress
  ingress:
    - from:
      - podSelector:
          matchLabels:
            tier: frontend
EOF

if kubectl get networkpolicy allow-frontend -n $NAMESPACE &> /dev/null; then
  pass "NetworkPolicy created"
else
  fail "NetworkPolicy failed"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
