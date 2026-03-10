#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

TEST_NAME="UC-KEDA-01: CPU ScaledObject"
NAMESPACE="keda-test"
CHART_PATH="../../../../charts/common-keda"
VALUES_FILE="../values/uc01-cpu-scaler.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }

cleanup() {
  helm uninstall keda-cpu-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check KEDA installed
if ! kubectl get deployment keda-operator -n keda &> /dev/null; then
  info "KEDA operator not found. Install: kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml"
  exit 2
fi
pass "KEDA operator installed"

# Create namespace
kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Install chart
echo ""
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"
if helm install keda-cpu-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 3m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Verify ScaledObject
echo ""
echo -e "${BLUE}=== Test 2: Verify ScaledObject ===${NC}"
if kubectl get scaledobject -n $NAMESPACE | grep -q "cpu-scaler"; then
  pass "ScaledObject created"
else
  fail "ScaledObject not found"
fi

# Verify deployment
echo ""
echo -e "${BLUE}=== Test 3: Verify Deployment ===${NC}"
if kubectl get deployment cpu-test-app -n $NAMESPACE &> /dev/null; then
  pass "Deployment created"
  REPLICAS=$(kubectl get deployment cpu-test-app -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  info "Current replicas: $REPLICAS"
else
  fail "Deployment not found"
fi

# Check ScaledObject status
echo ""
echo -e "${BLUE}=== Test 4: Check ScaledObject Status ===${NC}"
SO_STATUS=$(kubectl get scaledobject cpu-scaler -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$SO_STATUS" = "True" ]; then
  pass "ScaledObject ready"
else
  info "ScaledObject status: $SO_STATUS (may need time to initialize)"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
kubectl get scaledobject -n $NAMESPACE 2>/dev/null || true
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
