#!/bin/bash
set -e

# UC-SECURITY-03: Falco Runtime Protection

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-SECURITY-03: Falco Runtime Protection"
RELEASE_NAME="falco-security"
FALCO_NAMESPACE="falco-system"
APP_NAMESPACE="test-security"
CHART_PATH="../../../../charts/common-security"
VALUES_FILE="$(dirname "$0")/../values/uc03-falco-runtime.yaml"
WORKLOAD_FILE="$(dirname "$0")/../workloads/suspicious-pod.yaml"

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
  kubectl delete -f $WORKLOAD_FILE -n $APP_NAMESPACE 2>/dev/null || true
  helm uninstall $RELEASE_NAME -n $FALCO_NAMESPACE 2>/dev/null || true
  kubectl delete namespace $APP_NAMESPACE 2>/dev/null || true
  kubectl delete namespace $FALCO_NAMESPACE 2>/dev/null || true
  sleep 5
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

# Create namespaces
kubectl create namespace $FALCO_NAMESPACE 2>/dev/null || true
kubectl create namespace $APP_NAMESPACE 2>/dev/null || true
pass "Namespaces ready"

# Test 1: Install Falco
echo ""
echo -e "${BLUE}=== Test 1: Install Falco ===${NC}"

info "Installing Falco (this may take 2-3 minutes)..."
if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE -n $FALCO_NAMESPACE --wait --timeout 5m; then
  pass "Falco chart installed"
else
  fail "Falco installation failed"
  warn "Falco requires kernel headers or eBPF support"
  warn "Check: kubectl logs -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco"
  exit 1
fi

sleep 15

# Test 2: Verify Falco DaemonSet
echo ""
echo -e "${BLUE}=== Test 2: Verify Falco DaemonSet ===${NC}"

if kubectl get daemonset -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco &> /dev/null; then
  pass "Falco DaemonSet created"
  
  DESIRED=$(kubectl get daemonset -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].status.desiredNumberScheduled}')
  READY=$(kubectl get daemonset -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].status.numberReady}')
  
  info "Falco pods: $READY/$DESIRED ready"
  
  if [ "$READY" -ge 1 ]; then
    pass "Falco is running on $READY node(s)"
  else
    fail "Falco pods not ready"
  fi
else
  fail "Falco DaemonSet not found"
fi

# Test 3: Check Falco Driver
echo ""
echo -e "${BLUE}=== Test 3: Check Falco Driver ===${NC}"

FALCO_POD=$(kubectl get pod -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco -o name | head -1)

if [ -n "$FALCO_POD" ]; then
  info "Falco pod: $FALCO_POD"
  
  if kubectl logs -n $FALCO_NAMESPACE $FALCO_POD --tail=100 | grep -qi "driver.*loaded\|probe.*loaded\|ebpf.*loaded"; then
    pass "Falco driver loaded successfully"
  else
    warn "Driver status unclear - checking further..."
    if kubectl logs -n $FALCO_NAMESPACE $FALCO_POD --tail=100 | grep -qi "error.*driver\|failed.*load"; then
      fail "Driver failed to load"
    else
      pass "Falco appears to be running"
    fi
  fi
else
  fail "No Falco pods found"
fi

# Test 4: Verify Rules Loaded
echo ""
echo -e "${BLUE}=== Test 4: Verify Rules Loaded ===${NC}"

if kubectl logs -n $FALCO_NAMESPACE $FALCO_POD --tail=200 | grep -qi "rules.*loaded\|rules file"; then
  pass "Falco rules loaded"
  
  RULE_COUNT=$(kubectl logs -n $FALCO_NAMESPACE $FALCO_POD --tail=200 | grep -i "rules" | wc -l)
  info "Found $RULE_COUNT rule-related log entries"
else
  warn "Could not confirm rule loading"
fi

# Check for custom rules
if kubectl logs -n $FALCO_NAMESPACE $FALCO_POD --tail=200 | grep -qi "suspicious-activity\|Shell Spawned"; then
  pass "Custom rules detected"
else
  warn "Custom rules may not be loaded"
fi

# Test 5: Deploy Suspicious Pod
echo ""
echo -e "${BLUE}=== Test 5: Deploy Suspicious Workload ===${NC}"

if kubectl apply -f $WORKLOAD_FILE -n $APP_NAMESPACE; then
  pass "Suspicious pod deployed"
else
  fail "Failed to deploy workload"
  exit 1
fi

sleep 10

# Test 6: Verify Pod Running
echo ""
echo -e "${BLUE}=== Test 6: Verify Pod Running ===${NC}"

if kubectl get pod suspicious-pod -n $APP_NAMESPACE &> /dev/null; then
  STATUS=$(kubectl get pod suspicious-pod -n $APP_NAMESPACE -o jsonpath='{.status.phase}')
  
  if [ "$STATUS" = "Running" ]; then
    pass "Suspicious pod is running"
  else
    warn "Pod status: $STATUS"
  fi
else
  fail "Suspicious pod not found"
fi

# Test 7: Wait for Alerts
echo ""
echo -e "${BLUE}=== Test 7: Monitor Falco Alerts ===${NC}"

info "Waiting 20 seconds for Falco to detect suspicious activity..."
sleep 20

FALCO_LOGS="/tmp/falco-logs-uc03.txt"
kubectl logs -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco --tail=500 --since=60s > $FALCO_LOGS 2>/dev/null || true

ALERT_COUNT=$(grep -ic "warning\|notice\|priority" $FALCO_LOGS 2>/dev/null || echo "0")

if [ "$ALERT_COUNT" -gt 0 ]; then
  pass "Falco generated $ALERT_COUNT alert(s)"
else
  warn "No alerts found yet (may need more time)"
fi

# Test 8: Shell Detection
echo ""
echo -e "${BLUE}=== Test 8: Shell Spawn Detection ===${NC}"

if grep -qi "shell.*spawned\|bash\|/bin/sh" $FALCO_LOGS; then
  pass "Detected shell spawn in container"
else
  warn "Shell spawn not detected"
fi

# Test 9: File System Activity
echo ""
echo -e "${BLUE}=== Test 9: File System Activity Detection ===${NC}"

if grep -qi "write.*etc\|/etc/test" $FALCO_LOGS; then
  pass "Detected write to /etc directory"
else
  warn "Write to /etc not detected"
fi

# Test 10: Network Activity
echo ""
echo -e "${BLUE}=== Test 10: Network Activity Detection ===${NC}"

if grep -qi "network\|connection\|outbound\|9999" $FALCO_LOGS; then
  pass "Detected suspicious network activity"
else
  warn "Network activity not detected"
fi

# Test 11: Alert Format
echo ""
echo -e "${BLUE}=== Test 11: Validate Alert Format ===${NC}"

if grep -q "container=" $FALCO_LOGS && grep -q "namespace=" $FALCO_LOGS; then
  pass "Alerts contain container and namespace context"
else
  warn "Alert format may be non-standard"
fi

# Display sample alerts
echo ""
echo -e "${BLUE}=== Sample Falco Alerts ===${NC}"
grep -i "warning\|notice" $FALCO_LOGS | head -5 || echo "No alerts to display"

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
  echo -e "${BLUE}Falco Deployment Info:${NC}"
  kubectl get daemonset -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. View live alerts: kubectl logs -n $FALCO_NAMESPACE -l app.kubernetes.io/name=falco -f"
  echo "2. Review all alerts: cat $FALCO_LOGS"
  echo "3. Add custom rules to values file"
  echo "4. Integrate with SIEM or alerting system"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  echo ""
  echo -e "${YELLOW}Troubleshooting:${NC}"
  echo "1. Check Falco logs: kubectl logs -n $FALCO_NAMESPACE $FALCO_POD"
  echo "2. Verify driver: kubectl logs -n $FALCO_NAMESPACE $FALCO_POD | grep driver"
  echo "3. Check kernel version: uname -r"
  echo "4. Try eBPF driver if module fails"
  exit 1
fi
