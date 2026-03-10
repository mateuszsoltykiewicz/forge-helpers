#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-KUBERNETES-03: ConfigMap/Secret"
RELEASE_NAME="config-test"
NAMESPACE="default"
CHART_PATH="$(cd "$(dirname "$0")/../charts/test-uc03" && pwd)"
VALUES_OVERRIDE="/tmp/uc03_overrides.yaml"

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
  kubectl delete -f "$(dirname "$0")/../workloads/config-validator.yaml" 2>/dev/null || true
  helm uninstall $RELEASE_NAME 2>/dev/null || true
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
echo -e "${BLUE}=== Test 1: Update Dependencies ===${NC}"
cd "$CHART_PATH"
if helm dependency update >/dev/null 2>&1; then
  pass "Dependencies updated (common-forge, common-vault, common-kubernetes)"
else
  fail "Dependency update failed"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Test 2: Install Chart ===${NC}"
if helm install $RELEASE_NAME "$CHART_PATH" -f "$VALUES_OVERRIDE" --wait --timeout 3m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 3

# Test 3: Verify ConfigMap
echo ""
echo -e "${BLUE}=== Test 3: Verify ConfigMap ===${NC}"
if kubectl get configmap app-config -n $NAMESPACE &> /dev/null; then
  pass "ConfigMap created"
  KEY_COUNT=$(kubectl get configmap app-config -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys | length')
  info "ConfigMap has $KEY_COUNT keys"
else
  fail "ConfigMap not found"
fi

# Test 3: Verify Secret
echo ""
echo -e "${BLUE}=== Test 4: Verify Secret ===${NC}"
if kubectl get secret app-secrets -n $NAMESPACE &> /dev/null; then
  pass "Secret created"
  SECRET_TYPE=$(kubectl get secret app-secrets -n $NAMESPACE -o jsonpath='{.type}')
  info "Secret type: $SECRET_TYPE"
else
  fail "Secret not found"
fi

# Test 4: Check Pod Env Vars
echo ""
echo -e "${BLUE}=== Test 5: Check Environment Variables ===${NC}"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=config-app -o name | head -1)
if [ -n "$POD_NAME" ]; then
  pass "Pod found"
  sleep 5
  LOGS=$(kubectl logs $POD_NAME -n $NAMESPACE 2>/dev/null | head -20)
  if echo "$LOGS" | grep -q "APP_NAME"; then
    pass "ConfigMap env vars injected"
  else
    fail "ConfigMap env vars missing"
  fi
  if echo "$LOGS" | grep -q "DATABASE_PASSWORD"; then
    pass "Secret env vars injected"
  else
    fail "Secret env vars missing"
  fi
else
  fail "No pods found"
fi

# Test 5: Deploy Validator
echo ""
echo -e "${BLUE}=== Test 6: Run Config Validator ===${NC}"
kubectl apply -f "$(dirname "$0")/../workloads/config-validator.yaml" 2>&1 | head -3
sleep 5

if kubectl get pod config-validator -n $NAMESPACE &> /dev/null; then
  kubectl wait --for=condition=ready --timeout=30s pod/config-validator -n $NAMESPACE 2>/dev/null || true
  sleep 2
  VALIDATOR_LOGS=$(kubectl logs config-validator -n $NAMESPACE 2>/dev/null || echo "")
  if echo "$VALIDATOR_LOGS" | grep -q "passed"; then
    pass "Validation tests passed"
  else
    fail "Validation tests failed"
  fi
else
  fail "Validator pod not created"
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
