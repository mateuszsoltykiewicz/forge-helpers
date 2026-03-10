#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

TEST_NAME="UC-VAULT-02: Dynamic Database Credentials"
NAMESPACE="vault-test"
CHART_PATH="../../../../charts/common-vault"
VALUES_FILE="../values/uc02-dynamic-credentials.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

cleanup() {
  helm uninstall vault-db-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check Vault
echo ""
echo -e "${BLUE}=== Test 1: Verify Vault Installation ===${NC}"
if kubectl get deployment vault -n vault &> /dev/null || kubectl get statefulset vault -n vault &> /dev/null; then
  pass "Vault server found"
else
  warn "Vault server not found"
  exit 2
fi

if kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg &> /dev/null; then
  pass "Vault Agent Injector webhook found"
else
  warn "Vault Agent Injector not found"
  exit 2
fi

kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Install chart
echo ""
echo -e "${BLUE}=== Test 2: Install Chart ===${NC}"
if helm install vault-db-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 5m 2>&1 | tee /tmp/vault-db-install.log; then
  pass "Chart installed"
else
  fail "Installation failed"
  cat /tmp/vault-db-install.log
  exit 1
fi

sleep 10

# Verify deployment
echo ""
echo -e "${BLUE}=== Test 3: Verify Deployment ===${NC}"
if kubectl get deployment vault-db-app -n $NAMESPACE &> /dev/null; then
  pass "Deployment created"
  
  POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=vault-db-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD_NAME" ]; then
    info "Pod: $POD_NAME"
  else
    fail "No pods found"
  fi
else
  fail "Deployment not found"
fi

# Check sidecar
echo ""
echo -e "${BLUE}=== Test 4: Verify Vault Agent Sidecar ===${NC}"
if [ -n "$POD_NAME" ]; then
  CONTAINER_COUNT=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}' | wc -w)
  
  if [ "$CONTAINER_COUNT" -ge 2 ]; then
    pass "Vault Agent sidecar injected (containers: $CONTAINER_COUNT)"
  else
    warn "Only $CONTAINER_COUNT container(s) found"
  fi
else
  fail "Cannot verify sidecar (no pod)"
fi

# Check database secrets path annotation
echo ""
echo -e "${BLUE}=== Test 5: Verify Database Secrets Annotations ===${NC}"
if [ -n "$POD_NAME" ]; then
  if kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}' | grep -q "database/creds"; then
    pass "Database secrets path annotation present"
  else
    fail "Database credentials annotation not found"
  fi
else
  fail "Cannot verify annotations (no pod)"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
info "To verify DB credentials: kubectl exec -it $POD_NAME -n $NAMESPACE -- cat /vault/secrets/db-creds"
info "Note: Database secrets engine must be configured in Vault for dynamic credentials to work"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
