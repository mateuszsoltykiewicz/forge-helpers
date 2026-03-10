#!/bin/bash
set -e

# UC-MONITORING-03: SLO Monitoring (P99 Latency)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-MONITORING-03: SLO Latency"
RELEASE_NAME="test-monitoring-uc03"
NAMESPACE="test-monitoring"
CHART_PATH="../../../../charts/common-monitoring"
VALUES_FILE="$(dirname "$0")/../values/uc03-slo-latency.yaml"
WORKLOAD_FILE="$(dirname "$0")/../workloads/latency-test-app.yaml"

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
  kubectl delete -f $WORKLOAD_FILE -n $NAMESPACE 2>/dev/null || true
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

if ! kubectl get crd prometheusrules.monitoring.coreos.com &> /dev/null; then
  fail "PrometheusRule CRD not found"
  exit 2
fi
pass "Prometheus Operator CRDs present"

if ! kubectl get namespace $NAMESPACE &> /dev/null; then
  kubectl create namespace $NAMESPACE
  info "Created namespace $NAMESPACE"
fi
pass "Test namespace ready"

# Test 1: Install Chart
echo ""
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"

if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 2m; then
  pass "Chart installed successfully"
else
  fail "Chart installation failed"
  exit 1
fi

sleep 5

# Test 2: Verify PrometheusRule
echo ""
echo -e "${BLUE}=== Test 2: Verify PrometheusRule ===${NC}"

if kubectl get prometheusrule -n $NAMESPACE | grep -q "slo\|latency\|monitoring"; then
  pass "PrometheusRule resource found"
  
  RULE_NAME=$(kubectl get prometheusrule -n $NAMESPACE -o name | head -1 | cut -d'/' -f2)
  info "PrometheusRule name: $RULE_NAME"
  
  if kubectl get prometheusrule $RULE_NAME -n $NAMESPACE -o yaml | grep -q "latency\|histogram_quantile\|p99"; then
    pass "PrometheusRule contains SLO latency definition"
  else
    fail "PrometheusRule missing SLO latency definition"
  fi
else
  fail "PrometheusRule resource not found"
fi

# Test 3: Inspect Rule Expression
echo ""
echo -e "${BLUE}=== Test 3: Inspect Rule Expression ===${NC}"

if kubectl get prometheusrule $RULE_NAME -n $NAMESPACE -o yaml > /tmp/uc03-rule.yaml; then
  
  if grep -q "histogram_quantile" /tmp/uc03-rule.yaml; then
    pass "Rule uses histogram_quantile function"
  else
    fail "Rule doesn't use histogram_quantile"
  fi
  
  if grep -q "0.99\|0\.99" /tmp/uc03-rule.yaml; then
    pass "Rule targets P99 percentile"
  else
    warn "Rule may not be targeting P99 percentile"
  fi
  
  if grep -q "> 0.5\|> 500ms\|threshold" /tmp/uc03-rule.yaml; then
    pass "Rule has threshold check"
  else
    warn "Threshold check unclear in rule"
  fi
fi

# Test 4: Deploy Test Application
echo ""
echo -e "${BLUE}=== Test 4: Deploy Test Application ===${NC}"

if kubectl apply -f $WORKLOAD_FILE -n $NAMESPACE; then
  pass "Test application deployed"
else
  fail "Failed to deploy test application"
fi

sleep 10

# Test 5: Verify App is Running
echo ""
echo -e "${BLUE}=== Test 5: Verify Application ===${NC}"

if kubectl get pod -n $NAMESPACE -l app=latency-test | grep -q "Running"; then
  pass "Test application pod is running"
  
  POD_NAME=$(kubectl get pod -n $NAMESPACE -l app=latency-test -o jsonpath='{.items[0].metadata.name}')
  info "Pod name: $POD_NAME"
else
  fail "Test application pod not running"
fi

# Test 6: Check Service
echo ""
echo -e "${BLUE}=== Test 6: Verify Service ===${NC}"

if kubectl get svc latency-test-app -n $NAMESPACE &> /dev/null; then
  pass "Test application service created"
else
  fail "Test application service not found"
fi

# Test 7: Check ServiceMonitor
echo ""
echo -e "${BLUE}=== Test 7: Verify ServiceMonitor ===${NC}"

if kubectl get servicemonitor latency-test-app -n $NAMESPACE &> /dev/null; then
  pass "ServiceMonitor created for metrics scraping"
else
  warn "ServiceMonitor not found - metrics may not be scraped"
fi

# Test 8: Verify Metrics Endpoint
echo ""
echo -e "${BLUE}=== Test 8: Check Metrics Endpoint ===${NC}"

info "Testing metrics endpoint..."
if kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- localhost:9090/metrics 2>/dev/null | grep -q "http_request\|promhttp"; then
  pass "Metrics endpoint responding"
else
  warn "Metrics endpoint may not be properly configured"
fi

# Test 9: Generate Load (Optional)
echo ""
echo -e "${BLUE}=== Test 9: Load Testing ===${NC}"

if command -v hey &> /dev/null; then
  info "Generating test traffic..."
  
  # Port-forward in background
  kubectl port-forward -n $NAMESPACE svc/latency-test-app 18080:8080 &> /dev/null &
  PF_PID=$!
  sleep 3
  
  # Generate some traffic
  hey -n 100 -c 5 -q 10 http://localhost:18080/ &> /dev/null || true
  
  kill $PF_PID 2>/dev/null || true
  
  pass "Test traffic generated"
else
  warn "'hey' tool not installed - skipping load test"
  info "To install: brew install hey (macOS) or go install github.com/rakyll/hey@latest"
fi

# Test 10: Wait for Metrics
echo ""
echo -e "${BLUE}=== Test 10: SLO Alerting ===${NC}"

info "Waiting 30 seconds for metrics to be scraped..."
sleep 30

if kubectl get svc -n monitoring | grep -q "prometheus"; then
  pass "Prometheus service found"
  
  warn "⏳ SLO alert typically takes 5-7 minutes to evaluate"
  warn "To manually verify alert:"
  echo "   1. kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  echo "   2. Open http://localhost:9090/alerts"
  echo "   3. Look for SLO/latency related alert"
  echo ""
  echo "   To test alert firing:"
  echo "   4. Generate slow traffic to increase P99 latency > 500ms"
  echo "   5. Wait 5-7 minutes for alert evaluation"
else
  warn "Prometheus service not found - cannot verify alert"
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
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Wait for Prometheus to scrape metrics (~30-60 seconds)"
  echo "2. Generate varying traffic patterns to test SLO alerting"
  echo "3. Monitor alert status in Prometheus UI"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
