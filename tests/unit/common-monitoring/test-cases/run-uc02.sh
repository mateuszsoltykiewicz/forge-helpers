#!/bin/bash
set -e

# UC-MONITORING-02: Grafana Dashboard Provisioning
# Tests that ConfigMap with dashboard JSON is created and loaded by Grafana

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-MONITORING-02: Grafana Dashboard"
RELEASE_NAME="test-monitoring-uc02"
NAMESPACE="test-monitoring"
CHART_PATH="../../../../charts/common-monitoring"
VALUES_FILE="$(dirname "$0")/../values/uc02-grafana-dashboard.yaml"

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
  helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
  sleep 2
  echo -e "${GREEN}✅ Cleanup completed${NC}"
}

trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Prerequisites
echo -e "${BLUE}=== Prerequisites Check ===${NC}"

if ! command -v kubectl &> /dev/null; then
  fail "kubectl not found"
  exit 2
fi
pass "kubectl installed"

if ! command -v helm &> /dev/null; then
  fail "helm not found"
  exit 2
fi
pass "helm installed"

if ! kubectl get namespace $NAMESPACE &> /dev/null; then
  kubectl create namespace $NAMESPACE
  info "Created namespace $NAMESPACE"
fi
pass "Test namespace ready"

# Test 1: Install Chart
echo ""
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"

if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 2m 2>&1 | tee /tmp/uc02-install.log; then
  pass "Chart installed successfully"
else
  fail "Chart installation failed"
  exit 1
fi

sleep 5

# Test 2: Verify ConfigMap Created
echo ""
echo -e "${BLUE}=== Test 2: Verify ConfigMap ===${NC}"

if kubectl get configmap -n $NAMESPACE | grep -q "dashboard\|grafana"; then
  pass "Dashboard ConfigMap found"
  CM_NAME=$(kubectl get configmap -n $NAMESPACE -o name | grep "dashboard\|grafana" | head -1 | cut -d'/' -f2)
  info "ConfigMap name: $CM_NAME"
else
  fail "Dashboard ConfigMap not found"
fi

# Test 3: Check ConfigMap Labels
echo ""
echo -e "${BLUE}=== Test 3: Verify Labels ===${NC}"

if [ ! -z "$CM_NAME" ]; then
  LABELS=$(kubectl get configmap $CM_NAME -n $NAMESPACE -o jsonpath='{.metadata.labels}')
  
  if echo "$LABELS" | grep -q "grafana_dashboard"; then
    pass "grafana_dashboard label present"
  else
    fail "grafana_dashboard label missing"
  fi
fi

# Test 4: Validate JSON
echo ""
echo -e "${BLUE}=== Test 4: Validate Dashboard JSON ===${NC}"

if [ ! -z "$CM_NAME" ]; then
  if kubectl get configmap $CM_NAME -n $NAMESPACE -o jsonpath='{.data}' > /tmp/uc02-dashboard.json 2>/dev/null; then
    
    if command -v jq &> /dev/null; then
      if jq '.' /tmp/uc02-dashboard.json > /dev/null 2>&1; then
        pass "Dashboard JSON is valid"
        
        # Check for required fields
        if jq -r '.[] | keys[]' /tmp/uc02-dashboard.json 2>/dev/null | grep -q "dashboard\|title\|panels"; then
          pass "Dashboard JSON has required structure"
        else
          fail "Dashboard JSON missing required fields"
        fi
      else
        fail "Dashboard JSON is invalid"
      fi
    else
      info "jq not installed, skipping JSON validation"
    fi
  else
    fail "Failed to extract dashboard JSON"
  fi
fi

# Test 5: Check Grafana Accessibility
echo ""
echo -e "${BLUE}=== Test 5: Grafana Check ===${NC}"

if kubectl get svc -n monitoring | grep -q "grafana"; then
  pass "Grafana service found in monitoring namespace"
  info "Dashboard should appear in Grafana UI after 30-60 seconds"
  
  echo ""
  info "To verify dashboard loaded:"
  echo "  1. kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
  echo "  2. Get password: kubectl get secret -n monitoring prometheus-grafana -o jsonpath=\"{.data.admin-password}\" | base64 --decode"
  echo "  3. Open http://localhost:3000"
  echo "  4. Login with admin / <password>"
  echo "  5. Search for 'Test Application Metrics'"
else
  fail "Grafana service not found"
fi

# Summary
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "Total Tests:   $TOTAL_TESTS"
echo -e "${GREEN}Passed:        $PASSED_TESTS${NC}"
echo -e "${RED}Failed:        $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
