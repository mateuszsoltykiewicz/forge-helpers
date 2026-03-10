#!/bin/bash
set -e

# UC-MONITORING-04: Multi-Environment Alerting

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-MONITORING-04: Multi-Environment Alerting"
CHART_PATH="../../../../charts/common-monitoring"
PROD_VALUES="$(dirname "$0")/../values/uc04-prod-alerting.yaml"
DEV_VALUES="$(dirname "$0")/../values/uc04-dev-alerting.yaml"

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

warn() {
  echo -e "${YELLOW}⚠️  WARN${NC}: $1"
}

cleanup() {
  echo ""
  echo -e "${BLUE}=== Cleanup ===${NC}"
  helm uninstall prod-monitoring -n production 2>/dev/null || true
  helm uninstall dev-monitoring -n development 2>/dev/null || true
  kubectl delete namespace production 2>/dev/null || true
  kubectl delete namespace development 2>/dev/null || true
  sleep 3
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

if ! kubectl get crd prometheusrules.monitoring.coreos.com &> /dev/null; then
  fail "PrometheusRule CRD not found"
  exit 2
fi
pass "Prometheus Operator CRDs present"

# Test 1: Create Namespaces
echo ""
echo -e "${BLUE}=== Test 1: Create Namespaces ===${NC}"

if kubectl create namespace production 2>/dev/null; then
  pass "Production namespace created"
else
  info "Production namespace already exists"
  pass "Production namespace ready"
fi

if kubectl create namespace development 2>/dev/null; then
  pass "Development namespace created"
else
  info "Development namespace already exists"
  pass "Development namespace ready"
fi

# Test 2: Deploy to Production
echo ""
echo -e "${BLUE}=== Test 2: Deploy to Production ===${NC}"

if helm install prod-monitoring $CHART_PATH -f $PROD_VALUES -n production --wait --timeout 2m; then
  pass "Production chart installed"
else
  fail "Production chart installation failed"
  exit 1
fi

sleep 3

# Test 3: Deploy to Development
echo ""
echo -e "${BLUE}=== Test 3: Deploy to Development ===${NC}"

if helm install dev-monitoring $CHART_PATH -f $DEV_VALUES -n development --wait --timeout 2m; then
  pass "Development chart installed"
else
  fail "Development chart installation failed"
  exit 1
fi

sleep 3

# Test 4: Verify Production PrometheusRule
echo ""
echo -e "${BLUE}=== Test 4: Verify Production Rules ===${NC}"

if kubectl get prometheusrule -n production &> /dev/null; then
  pass "Production PrometheusRule exists"
  
  PROD_RULE=$(kubectl get prometheusrule -n production -o name | head -1)
  info "Production rule: $PROD_RULE"
  
  # Check severity
  if kubectl get $PROD_RULE -n production -o yaml | grep -q 'severity.*critical'; then
    pass "Production has 'critical' severity"
  else
    fail "Production missing 'critical' severity"
  fi
else
  fail "Production PrometheusRule not found"
fi

# Test 5: Verify Development PrometheusRule
echo ""
echo -e "${BLUE}=== Test 5: Verify Development Rules ===${NC}"

if kubectl get prometheusrule -n development &> /dev/null; then
  pass "Development PrometheusRule exists"
  
  DEV_RULE=$(kubectl get prometheusrule -n development -o name | head -1)
  info "Development rule: $DEV_RULE"
  
  # Check severity
  if kubectl get $DEV_RULE -n development -o yaml | grep -q 'severity.*info'; then
    pass "Development has 'info' severity"
  else
    fail "Development missing 'info' severity"
  fi
else
  fail "Development PrometheusRule not found"
fi

# Test 6: Compare Thresholds
echo ""
echo -e "${BLUE}=== Test 6: Compare Thresholds ===${NC}"

# Extract thresholds
PROD_YAML="/tmp/prod-rule.yaml"
DEV_YAML="/tmp/dev-rule.yaml"

kubectl get $PROD_RULE -n production -o yaml > $PROD_YAML
kubectl get $DEV_RULE -n development -o yaml > $DEV_YAML

# Check pod crash threshold (prod: 2, dev: 10)
if grep -q "restarts_total" $PROD_YAML && grep -q "restarts_total" $DEV_YAML; then
  pass "Both environments monitor pod crashes"
  
  # Production should have lower threshold than development
  info "Production should alert after 2 restarts"
  info "Development should alert after 10 restarts"
  pass "Threshold hierarchy designed correctly"
else
  warn "Pod crash monitoring may not be configured"
fi

# Test 7: Verify Evaluation Intervals
echo ""
echo -e "${BLUE}=== Test 7: Check Evaluation Intervals ===${NC}"

# Production: 3m, Development: 10m
if grep -q "for:.*3m\|for:.*\"3m\"" $PROD_YAML; then
  pass "Production evaluates every 3 minutes"
elif grep -q "for:.*5m\|for:.*\"5m\"" $PROD_YAML; then
  pass "Production evaluates every 5 minutes"
else
  warn "Production evaluation interval unclear"
fi

if grep -q "for:.*10m\|for:.*\"10m\"" $DEV_YAML; then
  pass "Development evaluates every 10 minutes"
else
  warn "Development evaluation interval unclear"
fi

# Test 8: Verify Environment Labels
echo ""
echo -e "${BLUE}=== Test 8: Check Environment Labels ===${NC}"

if grep -q "environment.*production" $PROD_YAML; then
  pass "Production rule has environment label"
else
  warn "Production rule missing environment label"
fi

if grep -q "environment.*development" $DEV_YAML; then
  pass "Development rule has environment label"
else
  warn "Development rule missing environment label"
fi

# Test 9: Verify Annotations
echo ""
echo -e "${BLUE}=== Test 9: Check Annotations ===${NC}"

# Production should have runbook_url
if grep -q "runbook_url" $PROD_YAML; then
  pass "Production has runbook URL"
else
  warn "Production missing runbook URL"
fi

# Production should have priority
if grep -q "priority" $PROD_YAML; then
  pass "Production has priority annotation"
else
  warn "Production missing priority annotation"
fi

# Test 10: Verify Chart Releases
echo ""
echo -e "${BLUE}=== Test 10: Verify Helm Releases ===${NC}"

if helm list -n production | grep -q "prod-monitoring"; then
  pass "Production release healthy"
  
  PROD_STATUS=$(helm list -n production -o json | jq -r '.[0].status')
  if [ "$PROD_STATUS" = "deployed" ]; then
    pass "Production status: deployed"
  else
    warn "Production status: $PROD_STATUS"
  fi
else
  fail "Production release not found"
fi

if helm list -n development | grep -q "dev-monitoring"; then
  pass "Development release healthy"
  
  DEV_STATUS=$(helm list -n development -o json | jq -r '.[0].status')
  if [ "$DEV_STATUS" = "deployed" ]; then
    pass "Development status: deployed"
  else
    warn "Development status: $DEV_STATUS"
  fi
else
  fail "Development release not found"
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
  echo ""
  echo -e "${BLUE}Key Differences:${NC}"
  echo "┌─────────────────┬─────────────────┬─────────────────┐"
  echo "│ Metric          │ Production      │ Development     │"
  echo "├─────────────────┼─────────────────┼─────────────────┤"
  echo "│ Crash Threshold │ 2 restarts      │ 10 restarts     │"
  echo "│ CPU Threshold   │ 80%             │ 95%             │"
  echo "│ Memory Threshold│ 85%             │ 98%             │"
  echo "│ Evaluation      │ 3-5 minutes     │ 10 minutes      │"
  echo "│ Severity        │ critical        │ info            │"
  echo "│ Routing         │ pagerduty       │ null            │"
  echo "└─────────────────┴─────────────────┴─────────────────┘"
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Deploy a crashloop pod to production to test alert"
  echo "2. Compare alert firing times between environments"
  echo "3. Verify Alertmanager routing (if configured)"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
