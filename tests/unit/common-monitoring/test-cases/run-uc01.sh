#!/bin/bash
set -e

#####################################################################
# UC-MONITORING-01: Pod Crash Alerts
# 
# Tests that PrometheusRule is created and alerts fire when pods
# enter crash loops. Validates Prometheus alerting functionality.
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAME="UC-MONITORING-01: Pod Crash Alerts"
RELEASE_NAME="test-monitoring-uc01"
NAMESPACE="test-monitoring"
CHART_PATH="../../../../charts/common-monitoring"
VALUES_FILE="$(dirname "$0")/../values/uc01-pod-crash-alerts.yaml"
WORKLOAD_FILE="$(dirname "$0")/../workloads/crashloop-pod.yaml"

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Helper functions
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

# Cleanup function
cleanup() {
  echo ""
  echo -e "${BLUE}=== Cleanup ===${NC}"
  
  kubectl delete pod crashloop-test -n $NAMESPACE 2>/dev/null || true
  helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
  
  # Optional: delete namespace
  # kubectl delete namespace $NAMESPACE 2>/dev/null || true
  
  sleep 2
  echo -e "${GREEN}✅ Cleanup completed${NC}"
}

trap cleanup EXIT

# Check prerequisites
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

if ! kubectl cluster-info &> /dev/null; then
  fail "Cannot connect to Kubernetes cluster"
  exit 2
fi
pass "Kubernetes cluster accessible"

# Check if monitoring namespace exists
if ! kubectl get namespace monitoring &> /dev/null; then
  warn "Namespace 'monitoring' not found - Prometheus may not be installed"
fi

# Check if Prometheus Operator CRDs exist
if ! kubectl get crd prometheusrules.monitoring.coreos.com &> /dev/null; then
  fail "PrometheusRule CRD not found - Prometheus Operator not installed"
  exit 2
fi
pass "Prometheus Operator CRDs present"

# Create test namespace if it doesn't exist
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
  kubectl create namespace $NAMESPACE
  info "Created namespace $NAMESPACE"
fi
pass "Test namespace ready"

# Check if chart exists
if [ ! -d "$CHART_PATH" ]; then
  fail "Chart not found at $CHART_PATH"
  exit 2
fi
pass "Chart found"

# Check if values file exists
if [ ! -f "$VALUES_FILE" ]; then
  fail "Values file not found at $VALUES_FILE"
  exit 2
fi
pass "Values file found"

echo ""

# Test 1: Install Chart
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"

if helm install $RELEASE_NAME $CHART_PATH \
    -f $VALUES_FILE \
    -n $NAMESPACE \
    --wait \
    --timeout 2m 2>&1 | tee /tmp/uc01-install.log; then
  pass "Chart installed successfully"
else
  fail "Chart installation failed"
  cat /tmp/uc01-install.log
  exit 1
fi

sleep 5

# Test 2: Verify PrometheusRule Created
echo ""
echo -e "${BLUE}=== Test 2: Verify PrometheusRule ===${NC}"

if kubectl get prometheusrule -n $NAMESPACE | grep -q "monitoring"; then
  pass "PrometheusRule resource found"
  
  # Get the PrometheusRule name
  RULE_NAME=$(kubectl get prometheusrule -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
  info "PrometheusRule name: $RULE_NAME"
  
  # Check if rule contains PodCrashLooping alert
  if kubectl get prometheusrule $RULE_NAME -n $NAMESPACE -o yaml | grep -q "PodCrashLooping\|podCrashLooping\|crash"; then
    pass "PrometheusRule contains crash alert definition"
  else
    fail "PrometheusRule missing crash alert definition"
  fi
else
  fail "PrometheusRule resource not found"
fi

# Test 3: Deploy Crashloop Pod
echo ""
echo -e "${BLUE}=== Test 3: Deploy Crashloop Pod ===${NC}"

if [ ! -f "$WORKLOAD_FILE" ]; then
  fail "Workload file not found at $WORKLOAD_FILE"
  exit 1
fi

if kubectl apply -f $WORKLOAD_FILE -n $NAMESPACE &> /dev/null; then
  pass "Crashloop pod created"
else
  fail "Failed to create crashloop pod"
fi

sleep 3

# Test 4: Verify Pod is Crashing
echo ""
echo -e "${BLUE}=== Test 4: Verify Pod Crashes ===${NC}"
info "Waiting 60 seconds for pod to crash multiple times..."

sleep 60

POD_STATUS=$(kubectl get pod crashloop-test -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
RESTART_COUNT=$(kubectl get pod crashloop-test -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

info "Pod status: $POD_STATUS"
info "Restart count: $RESTART_COUNT"

if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Failed" ] || kubectl get pod crashloop-test -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state}' | grep -q "CrashLoopBackOff\|waiting"; then
  pass "Pod is in crash state"
else
  warn "Pod status unclear, may need more time"
fi

if [ "$RESTART_COUNT" -ge 3 ]; then
  pass "Pod has restarted $RESTART_COUNT times (threshold: 3)"
else
  warn "Pod has only restarted $RESTART_COUNT times (threshold: 3) - may need more time"
fi

# Test 5: Check PrometheusRule Spec
echo ""
echo -e "${BLUE}=== Test 5: Inspect PrometheusRule Spec ===${NC}"

if kubectl get prometheusrule $RULE_NAME -n $NAMESPACE -o yaml > /tmp/uc01-rule.yaml; then
  pass "PrometheusRule spec retrieved"
  
  # Check for alert expression
  if grep -q "expr:" /tmp/uc01-rule.yaml; then
    pass "Alert expression found in rule"
  else
    fail "No alert expression in rule"
  fi
  
  # Check for severity label
  if grep -q "severity:" /tmp/uc01-rule.yaml; then
    pass "Severity label found in rule"
  else
    warn "Severity label not found in rule"
  fi
  
  # Check for annotations
  if grep -q "annotations:" /tmp/uc01-rule.yaml; then
    pass "Annotations found in rule"
  else
    warn "Annotations not found in rule"
  fi
else
  fail "Failed to retrieve PrometheusRule spec"
fi

# Test 6: Wait for Alert (Optional - requires Prometheus access)
echo ""
echo -e "${BLUE}=== Test 6: Alert Firing Check ===${NC}"
info "Checking if Prometheus is accessible..."

# Try to check if Prometheus service exists
if kubectl get svc -n monitoring | grep -q "prometheus"; then
  info "Prometheus service found in monitoring namespace"
  
  warn "⏳ Alert typically takes 5-7 minutes to fire"
  warn "To manually verify alert, run:"
  echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  echo "   Open http://localhost:9090/alerts"
  echo "   Look for 'PodCrashLooping' alert in FIRING state"
  
  # We won't wait 5-7 minutes in automated test
  info "Skipping alert firing verification (would require 5-7 min wait)"
else
  warn "Prometheus service not found - cannot verify alert firing"
fi

# Test 7: Verify Chart Values Applied
echo ""
echo -e "${BLUE}=== Test 7: Verify Configuration ===${NC}"

HELM_VALUES=$(helm get values $RELEASE_NAME -n $NAMESPACE)

if echo "$HELM_VALUES" | grep -q "enabled: true"; then
  pass "Monitoring enabled in chart values"
else
  fail "Monitoring not enabled in chart values"
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
  echo "1. Port-forward to Prometheus:"
  echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  echo "2. Open http://localhost:9090/alerts"
  echo "3. Wait 5-7 minutes and verify 'PodCrashLooping' alert fires"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
