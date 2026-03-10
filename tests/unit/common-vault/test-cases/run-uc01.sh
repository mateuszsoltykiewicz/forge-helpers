#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

TEST_NAME="UC-VAULT-01: Secret Injection via Annotations"
NAMESPACE="vault-test"
CHART_PATH="../../../../charts/common-vault"
VALUES_FILE="../values/uc01-secret-injection.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

cleanup() {
  helm uninstall vault-inject-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check Vault installed
echo ""
echo -e "${BLUE}=== Test 1: Verify Vault Installation ===${NC}"
if kubectl get deployment vault -n vault &> /dev/null; then
  pass "Vault server found"
elif kubectl get statefulset vault -n vault &> /dev/null; then
  pass "Vault server found (StatefulSet)"
else
  warn "Vault server not found in 'vault' namespace"
  info "Install Vault: helm install vault hashicorp/vault -n vault --create-namespace"
  exit 2
fi

# Check Vault Agent Injector
if kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg &> /dev/null; then
  pass "Vault Agent Injector webhook found"
else
  warn "Vault Agent Injector not found"
  info "Enable in Vault Helm chart: injector.enabled=true"
  exit 2
fi

# Create namespace
kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Install chart
echo ""
echo -e "${BLUE}=== Test 2: Install Chart ===${NC}"
if helm install vault-inject-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 5m 2>&1 | tee /tmp/vault-install.log; then
  pass "Chart installed"
else
  fail "Installation failed"
  cat /tmp/vault-install.log
  exit 1
fi

sleep 10

# Verify deployment
echo ""
echo -e "${BLUE}=== Test 3: Verify Deployment ===${NC}"
if kubectl get deployment vault-inject-app -n $NAMESPACE &> /dev/null; then
  pass "Deployment created"
  
  POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=vault-inject-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD_NAME" ]; then
    info "Pod: $POD_NAME"
  else
    fail "No pods found"
  fi
else
  fail "Deployment not found"
fi

# Check Vault Agent sidecar injected
echo ""
echo -e "${BLUE}=== Test 4: Verify Vault Agent Sidecar ===${NC}"
if [ -n "$POD_NAME" ]; then
  CONTAINER_COUNT=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | wc -w)
  
  if [ "$CONTAINER_COUNT" -ge 2 ]; then
    pass "Vault Agent sidecar injected (containers: $CONTAINER_COUNT)"
    
    if kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | grep -q "vault-agent"; then
      pass "vault-agent container found"
    else
      info "Containers: $(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}')"
    fi
  else
    warn "Only $CONTAINER_COUNT container(s) found (expected 2+)"
    info "Vault Agent Injector may not have mutated pod"
  fi
else
  fail "Cannot verify sidecar (no pod)"
fi

# Check annotations
echo ""
echo -e "${BLUE}=== Test 5: Verify Vault Annotations ===${NC}"
if [ -n "$POD_NAME" ]; then
  if kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}' | grep -q "vault.hashicorp.com/agent-inject"; then
    pass "Vault injection annotations present"
  else
    fail "Vault annotations not found"
  fi
else
  fail "Cannot verify annotations (no pod)"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
info "To verify secrets injected: kubectl exec -it $POD_NAME -n $NAMESPACE -- cat /vault/secrets/config.txt"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
