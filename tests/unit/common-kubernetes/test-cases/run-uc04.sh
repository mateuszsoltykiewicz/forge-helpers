#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-KUBERNETES-04: RBAC"
RELEASE_NAME="rbac-test"
NAMESPACE="default"
CHART_PATH="../../../../charts/common-kubernetes"
VALUES_FILE="$(dirname "$0")/../values/uc04-rbac.yaml"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

pass() {
  echo -e "${GREEN}✅ PASS${NC}: $1"
  PASSED_TESTS=$((PASSED_TESTS + 1))
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail() {
  echo -e "${RED}❌ FAIL${NC}: $1"
  FAILED_TESTS=$((FAILED_TESTS + 1))
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

info() {
  echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

cleanup() {
  echo ""
  echo -e "${BLUE}=== Cleanup ===${NC}"
  kubectl delete -f "$(dirname "$0")/../workloads/rbac-tester.yaml" 2>/dev/null || true
  helm uninstall $RELEASE_NAME 2>/dev/null || true
  kubectl delete clusterrole rbac-test-clusterrole 2>/dev/null || true
  kubectl delete clusterrolebinding rbac-test-cluster-binding 2>/dev/null || true
  sleep 3
  echo -e "${GREEN}✅ Cleanup completed${NC}"
}

trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Prerequisites
echo -e "${BLUE}=== Prerequisites ===${NC}"
if ! command -v kubectl &> /dev/null; then
  fail "kubectl not found"
  exit 2
fi
pass "kubectl installed"

# Test 1: Install
echo ""
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"
if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE --wait --timeout 3m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 3

# Test 2: Verify ServiceAccount
echo ""
echo -e "${BLUE}=== Test 2: Verify ServiceAccount ===${NC}"
if kubectl get serviceaccount rbac-test-sa -n $NAMESPACE &> /dev/null; then
  pass "ServiceAccount created"
else
  fail "ServiceAccount not found"
fi

# Test 3: Verify Role
echo ""
echo -e "${BLUE}=== Test 3: Verify Role ===${NC}"
if kubectl get role rbac-test-role -n $NAMESPACE &> /dev/null; then
  pass "Role created"
  RULE_COUNT=$(kubectl get role rbac-test-role -n $NAMESPACE -o jsonpath='{.rules}' | jq 'length')
  info "Role has $RULE_COUNT rule(s)"
else
  fail "Role not found"
fi

# Test 4: Verify RoleBinding
echo ""
echo -e "${BLUE}=== Test 4: Verify RoleBinding ===${NC}"
if kubectl get rolebinding rbac-test-binding -n $NAMESPACE &> /dev/null; then
  pass "RoleBinding created"
else
  fail "RoleBinding not found"
fi

# Test 5: Verify ClusterRole
echo ""
echo -e "${BLUE}=== Test 5: Verify ClusterRole ===${NC}"
if kubectl get clusterrole rbac-test-clusterrole &> /dev/null; then
  pass "ClusterRole created"
else
  fail "ClusterRole not found"
fi

# Test 6: Verify ClusterRoleBinding
echo ""
echo -e "${BLUE}=== Test 6: Verify ClusterRoleBinding ===${NC}"
if kubectl get clusterrolebinding rbac-test-cluster-binding &> /dev/null; then
  pass "ClusterRoleBinding created"
else
  fail "ClusterRoleBinding not found"
fi

# Test 7: Test Permissions
echo ""
echo -e "${BLUE}=== Test 7: Test Allowed Permissions ===${NC}"

CAN_LIST_PODS=$(kubectl auth can-i list pods --as=system:serviceaccount:${NAMESPACE}:rbac-test-sa)
if [ "$CAN_LIST_PODS" = "yes" ]; then
  pass "Can list pods (Role permission)"
else
  fail "Cannot list pods"
fi

CAN_LIST_NODES=$(kubectl auth can-i list nodes --as=system:serviceaccount:${NAMESPACE}:rbac-test-sa)
if [ "$CAN_LIST_NODES" = "yes" ]; then
  pass "Can list nodes (ClusterRole permission)"
else
  fail "Cannot list nodes"
fi

# Test 8: Test Denied Permissions
echo ""
echo -e "${BLUE}=== Test 8: Test Denied Permissions ===${NC}"

CAN_DELETE_PODS=$(kubectl auth can-i delete pods --as=system:serviceaccount:${NAMESPACE}:rbac-test-sa)
if [ "$CAN_DELETE_PODS" = "no" ]; then
  pass "Cannot delete pods (correctly denied)"
else
  fail "Can delete pods (should be denied)"
fi

# Test 9: Deploy RBAC Tester
echo ""
echo -e "${BLUE}=== Test 9: Run RBAC Tester ===${NC}"
kubectl apply -f "$(dirname "$0")/../workloads/rbac-tester.yaml" 2>&1 | head -3
sleep 5

if kubectl get pod rbac-tester -n $NAMESPACE &> /dev/null; then
  kubectl wait --for=condition=ready --timeout=30s pod/rbac-tester -n $NAMESPACE 2>/dev/null || true
  sleep 2
  TESTER_LOGS=$(kubectl logs rbac-tester -n $NAMESPACE 2>/dev/null || echo "")
  if echo "$TESTER_LOGS" | grep -q "passed"; then
    pass "RBAC tests passed"
  else
    fail "RBAC tests failed"
  fi
else
  fail "Tester pod not created"
fi

# Summary
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "Total Tests:   $TOTAL_TESTS"
echo -e "${GREEN}Passed:        $PASSED_TESTS${NC}"
echo -e "${RED}Failed:        $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
