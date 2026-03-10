#!/bin/bash
set -e

# UC-KUBERNETES-01: Deployment with Horizontal Pod Autoscaler

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-KUBERNETES-01: Deployment with HPA"
RELEASE_NAME="hpa-test"
NAMESPACE="default"
CHART_PATH="../../../../charts/common-kubernetes"
VALUES_FILE="$(dirname "$0")/../values/uc01-deployment-hpa.yaml"

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
  kubectl delete -f "$(dirname "$0")/../workloads/load-generator.yaml" 2>/dev/null || true
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

# Check metrics-server
if kubectl top nodes &> /dev/null; then
  pass "Metrics server available"
else
  warn "Metrics server not available (HPA will not work properly)"
  info "Install: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# Test 1: Install Chart
echo ""
echo -e "${BLUE}=== Test 1: Install Chart with HPA ===${NC}"

info "Installing chart..."
if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE --wait --timeout 5m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Test 2: Verify Deployment
echo ""
echo -e "${BLUE}=== Test 2: Verify Deployment ===${NC}"

if kubectl get deployment hpa-test-app -n $NAMESPACE &> /dev/null; then
  pass "Deployment created"
  
  REPLICAS=$(kubectl get deployment hpa-test-app -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  if [ "$REPLICAS" -ge 1 ]; then
    pass "Deployment has $REPLICAS ready replica(s)"
  else
    fail "Deployment has 0 ready replicas"
  fi
else
  fail "Deployment not found"
fi

# Test 3: Verify HPA
echo ""
echo -e "${BLUE}=== Test 3: Verify HPA ===${NC}"

if kubectl get hpa hpa-test-app -n $NAMESPACE &> /dev/null; then
  pass "HPA created"
  
  MIN_REPLICAS=$(kubectl get hpa hpa-test-app -n $NAMESPACE -o jsonpath='{.spec.minReplicas}')
  MAX_REPLICAS=$(kubectl get hpa hpa-test-app -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}')
  info "HPA configuration: minReplicas=$MIN_REPLICAS, maxReplicas=$MAX_REPLICAS"
  
  if [ "$MIN_REPLICAS" = "1" ] && [ "$MAX_REPLICAS" = "5" ]; then
    pass "HPA min/max replicas configured correctly"
  else
    warn "Unexpected HPA configuration"
  fi
else
  fail "HPA not found"
fi

# Test 4: Check HPA Metrics
echo ""
echo -e "${BLUE}=== Test 4: Check HPA Metrics ===${NC}"

sleep 10  # Wait for metrics to be available

HPA_OUTPUT=$(kubectl get hpa hpa-test-app -n $NAMESPACE 2>&1)

if echo "$HPA_OUTPUT" | grep -q "<unknown>"; then
  warn "HPA metrics not available (check metrics-server)"
else
  pass "HPA metrics available"
  info "$(kubectl get hpa hpa-test-app -n $NAMESPACE)"
fi

# Test 5: Verify Service
echo ""
echo -e "${BLUE}=== Test 5: Verify Service ===${NC}"

if kubectl get service hpa-test-app-service -n $NAMESPACE &> /dev/null; then
  pass "Service created"
  
  SERVICE_TYPE=$(kubectl get service hpa-test-app-service -n $NAMESPACE -o jsonpath='{.spec.type}')
  SERVICE_PORT=$(kubectl get service hpa-test-app-service -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}')
  info "Service type: $SERVICE_TYPE, port: $SERVICE_PORT"
else
  warn "Service not found"
fi

# Test 6: Check Resource Requests/Limits
echo ""
echo -e "${BLUE}=== Test 6: Verify Resource Configuration ===${NC}"

POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=hpa-test-app -o name | head -1)

if [ -n "$POD_NAME" ]; then
  CPU_REQUEST=$(kubectl get $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
  MEM_REQUEST=$(kubectl get $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.requests.memory}')
  
  if [ -n "$CPU_REQUEST" ] && [ -n "$MEM_REQUEST" ]; then
    pass "Resource requests configured (CPU: $CPU_REQUEST, Memory: $MEM_REQUEST)"
  else
    fail "Resource requests missing (HPA requires them)"
  fi
  
  CPU_LIMIT=$(kubectl get $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
  MEM_LIMIT=$(kubectl get $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[0].resources.limits.memory}')
  
  if [ -n "$CPU_LIMIT" ] && [ -n "$MEM_LIMIT" ]; then
    pass "Resource limits configured (CPU: $CPU_LIMIT, Memory: $MEM_LIMIT)"
  else
    warn "Resource limits not set"
  fi
else
  fail "No pods found"
fi

# Test 7: Deploy Load Generator
echo ""
echo -e "${BLUE}=== Test 7: Deploy Load Generator ===${NC}"

info "Deploying load generator (will run for 5 minutes)..."

LOAD_GEN_FILE="$(dirname "$0")/../workloads/load-generator.yaml"

if [ -f "$LOAD_GEN_FILE" ]; then
  # Only deploy the Pod (first resource in file)
  kubectl apply -f $LOAD_GEN_FILE --dry-run=client -o yaml | \
    sed -n '/^apiVersion: v1$/,/^---$/p' | \
    head -n -1 | \
    kubectl apply -f - 2>&1 | head -5
  
  if kubectl get pod load-generator -n $NAMESPACE &> /dev/null; then
    pass "Load generator deployed"
  else
    warn "Load generator not deployed (manual load test required)"
  fi
else
  warn "Load generator file not found"
fi

# Test 8: Monitor Initial Scaling (30s)
echo ""
echo -e "${BLUE}=== Test 8: Monitor Initial HPA State ===${NC}"

info "Waiting 30 seconds for initial metrics..."
sleep 30

CURRENT_REPLICAS=$(kubectl get hpa hpa-test-app -n $NAMESPACE -o jsonpath='{.status.currentReplicas}')
info "Current replicas: $CURRENT_REPLICAS"

if kubectl get hpa hpa-test-app -n $NAMESPACE -o jsonpath='{.status.currentMetrics}' | grep -q "value"; then
  pass "HPA collecting metrics"
else
  warn "HPA metrics may not be ready"
fi

# Test 9: Wait for Scale-Up (90s)
echo ""
echo -e "${BLUE}=== Test 9: Monitor Scale-Up (90 seconds) ===${NC}"

info "Waiting for load to trigger scaling..."
info "Use 'kubectl get hpa hpa-test-app -w' in another terminal to watch live"

sleep 90

SCALED_REPLICAS=$(kubectl get hpa hpa-test-app -n $NAMESPACE -o jsonpath='{.status.currentReplicas}')

if [ "$SCALED_REPLICAS" -gt "$CURRENT_REPLICAS" ]; then
  pass "HPA scaled up (from $CURRENT_REPLICAS to $SCALED_REPLICAS replicas)"
else
  warn "HPA did not scale up yet (current: $SCALED_REPLICAS, may need more time/load)"
fi

# Test 10: Check HPA Events
echo ""
echo -e "${BLUE}=== Test 10: Check HPA Events ===${NC}"

HPA_EVENTS=$(kubectl describe hpa hpa-test-app -n $NAMESPACE | grep -A 10 "Events:" | tail -5)

if echo "$HPA_EVENTS" | grep -q "SuccessfulRescale\|Rescale"; then
  pass "HPA scaling events found"
  info "$HPA_EVENTS"
else
  warn "No scaling events yet (HPA may still be stabilizing)"
fi

# Test 11: Verify Pod Distribution
echo ""
echo -e "${BLUE}=== Test 11: Check Pod Distribution ===${NC}"

info "Current pod status:"
kubectl get pods -n $NAMESPACE -l app=hpa-test-app -o wide

POD_COUNT=$(kubectl get pods -n $NAMESPACE -l app=hpa-test-app --field-selector=status.phase=Running -o name | wc -l | tr -d ' ')

if [ "$POD_COUNT" -ge 1 ]; then
  pass "$POD_COUNT pod(s) running"
else
  fail "No running pods"
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
  echo -e "${BLUE}HPA Status:${NC}"
  kubectl get hpa hpa-test-app -n $NAMESPACE
  echo ""
  echo -e "${BLUE}Current Pods:${NC}"
  kubectl get pods -n $NAMESPACE -l app=hpa-test-app -o wide
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Watch scaling: kubectl get hpa hpa-test-app -w"
  echo "2. Monitor pods: kubectl get pods -l app=hpa-test-app -w"
  echo "3. Check metrics: kubectl top pods -l app=hpa-test-app"
  echo "4. View events: kubectl describe hpa hpa-test-app"
  echo "5. Wait 5-10 minutes to observe scale-down after load ends"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
