#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

TEST_NAME="UC-KEDA-03: External Scaler (Prometheus)"
NAMESPACE="keda-test"
CHART_PATH="../../../../charts/common-keda"
VALUES_FILE="../values/uc03-external-scaler.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

cleanup() {
  helm uninstall keda-prom-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check KEDA
if ! kubectl get deployment keda-operator -n keda &> /dev/null; then
  info "KEDA operator not found"
  exit 2
fi
pass "KEDA operator installed"

kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Install
echo ""
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"
if helm install keda-prom-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 3m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Verify ScaledObject
echo ""
echo -e "${BLUE}=== Test 2: Verify Prometheus ScaledObject ===${NC}"
if kubectl get scaledobject prometheus-scaler -n $NAMESPACE &> /dev/null; then
  pass "Prometheus ScaledObject created"
  
  TRIGGER_TYPE=$(kubectl get scaledobject prometheus-scaler -n $NAMESPACE -o jsonpath='{.spec.triggers[0].type}')
  if [ "$TRIGGER_TYPE" = "prometheus" ]; then
    pass "Prometheus trigger configured"
  else
    fail "Wrong trigger type: $TRIGGER_TYPE"
  fi
else
  fail "ScaledObject not found"
fi

# Check Prometheus query
echo ""
echo -e "${BLUE}=== Test 3: Verify Prometheus Query ===${NC}"
QUERY=$(kubectl get scaledobject prometheus-scaler -n $NAMESPACE -o jsonpath='{.spec.triggers[0].metadata.query}' 2>/dev/null)
if [ -n "$QUERY" ]; then
  pass "Prometheus query configured"
  info "Query: $QUERY"
else
  fail "Query not found"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
kubectl get scaledobject -n $NAMESPACE 2>/dev/null || true
info "Note: Prometheus server must be available for scaling to work"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
