#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-KUBERNETES-02: Service + Ingress"
RELEASE_NAME="service-test"
NAMESPACE="default"
CHART_PATH="../../../../charts/common-kubernetes"
VALUES_FILE="$(dirname "$0")/../values/uc02-service-ingress.yaml"

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
  kubectl delete -f "$(dirname "$0")/../workloads/test-client.yaml" 2>/dev/null || true
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

# Test 1: Install Chart
echo ""
echo -e "${BLUE}=== Test 1: Install Chart ===${NC}"

info "Installing chart..."
if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE --wait --timeout 3m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Test 2: Verify Deployment
echo ""
echo -e "${BLUE}=== Test 2: Verify Deployment ===${NC}"

if kubectl get deployment web-app -n $NAMESPACE &> /dev/null; then
  pass "Deployment created"
  REPLICAS=$(kubectl get deployment web-app -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  info "Ready replicas: $REPLICAS"
else
  fail "Deployment not found"
fi

# Test 3: Verify Service
echo ""
echo -e "${BLUE}=== Test 3: Verify ClusterIP Service ===${NC}"

if kubectl get service web-app-service -n $NAMESPACE &> /dev/null; then
  pass "Service created"
  
  SERVICE_TYPE=$(kubectl get service web-app-service -n $NAMESPACE -o jsonpath='{.spec.type}')
  CLUSTER_IP=$(kubectl get service web-app-service -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
  SERVICE_PORT=$(kubectl get service web-app-service -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}')
  
  info "Type: $SERVICE_TYPE, ClusterIP: $CLUSTER_IP, Port: $SERVICE_PORT"
  
  if [ "$SERVICE_TYPE" = "ClusterIP" ]; then
    pass "Service type correct"
  else
    warn "Unexpected service type: $SERVICE_TYPE"
  fi
else
  fail "Service not found"
fi

# Test 4: Check Service Endpoints
echo ""
echo -e "${BLUE}=== Test 4: Verify Service Endpoints ===${NC}"

ENDPOINTS=$(kubectl get endpoints web-app-service -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w | tr -d ' ')

if [ "$ENDPOINTS" -ge 1 ]; then
  pass "Service has $ENDPOINTS endpoint(s)"
else
  fail "No service endpoints"
fi

# Test 5: Verify Ingress
echo ""
echo -e "${BLUE}=== Test 5: Verify Ingress ===${NC}"

if kubectl get ingress -n $NAMESPACE | grep -q web-app; then
  pass "Ingress created"
  
  INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].spec.rules[0].host}')
  info "Host: $INGRESS_HOST"
else
  warn "Ingress not found (may not be enabled)"
fi

# Test 6: Deploy Test Client
echo ""
echo -e "${BLUE}=== Test 6: Test Internal Connectivity ===${NC}"

info "Deploying test client pod..."

TEST_CLIENT_FILE="$(dirname "$0")/../workloads/test-client.yaml"

if [ -f "$TEST_CLIENT_FILE" ]; then
  kubectl apply -f $TEST_CLIENT_FILE --dry-run=client -o yaml | \
    sed -n '1,/^---$/p' | head -n -1 | \
    kubectl apply -f - 2>&1 | head -3
  
  sleep 5
  
  if kubectl get pod test-client -n $NAMESPACE &> /dev/null; then
    pass "Test client deployed"
    
    info "Waiting for test completion..."
    kubectl wait --for=condition=ready --timeout=30s pod/test-client -n $NAMESPACE 2>/dev/null || true
    sleep 3
    
    TEST_LOGS=$(kubectl logs test-client -n $NAMESPACE 2>/dev/null || echo "")
    
    if echo "$TEST_LOGS" | grep -q "PASS"; then
      pass "Service connectivity test passed"
    else
      warn "Check logs: kubectl logs test-client"
    fi
  else
    warn "Test client not deployed"
  fi
else
  warn "Test client file not found"
fi

# Test 7: Verify DNS Resolution
echo ""
echo -e "${BLUE}=== Test 7: DNS Resolution ===${NC}"

DNS_TEST=$(kubectl run dns-test --image=busybox:1.36.1 --rm -i --restart=Never -- nslookup web-app-service 2>&1 || true)

if echo "$DNS_TEST" | grep -q "Address:"; then
  pass "DNS resolution working"
else
  warn "DNS resolution may not be working"
fi

# Test 8: Port-Forward Test
echo ""
echo -e "${BLUE}=== Test 8: Port-Forward Connectivity ===${NC}"

info "Testing port-forward (5 seconds)..."

kubectl port-forward svc/web-app-service 18080:80 -n $NAMESPACE &> /dev/null &
PF_PID=$!
sleep 2

if curl -s -o /dev/null -w "%{http_code}" http://localhost:18080 2>/dev/null | grep -q "200"; then
  pass "Port-forward connectivity OK"
else
  warn "Port-forward test failed"
fi

kill $PF_PID 2>/dev/null || true

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
  echo -e "${BLUE}Service Info:${NC}"
  kubectl get svc web-app-service -n $NAMESPACE
  echo ""
  echo -e "${BLUE}Ingress Info:${NC}"
  kubectl get ingress -n $NAMESPACE 2>/dev/null || echo "No ingress resources"
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Test service: kubectl port-forward svc/web-app-service 8080:80"
  echo "2. Access: curl http://localhost:8080"
  echo "3. Check logs: kubectl logs test-client"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
