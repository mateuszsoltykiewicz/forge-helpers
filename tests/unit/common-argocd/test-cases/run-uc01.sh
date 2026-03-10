#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

TEST_NAME="UC-ARGOCD-01: Application Deployment"
NAMESPACE="argocd"
CHART_PATH="../../../../charts/common-argocd"
VALUES_FILE="../values/uc01-application.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

cleanup() {
  helm uninstall argocd-app-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete application test-app -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace guestbook 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check ArgoCD installed
echo ""
echo -e "${BLUE}=== Test 1: Verify ArgoCD Installation ===${NC}"
if kubectl get namespace argocd &> /dev/null; then
  pass "ArgoCD namespace exists"
else
  warn "ArgoCD namespace not found"
  info "Install ArgoCD: kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  exit 2
fi

if kubectl get deployment argocd-server -n argocd &> /dev/null; then
  pass "ArgoCD server installed"
else
  fail "ArgoCD server not found"
  exit 2
fi

# Check Application CRD
if kubectl get crd applications.argoproj.io &> /dev/null; then
  pass "ArgoCD Application CRD exists"
else
  fail "Application CRD not found"
  exit 2
fi

# Install chart
echo ""
echo -e "${BLUE}=== Test 2: Create Application ===${NC}"
if helm install argocd-app-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 5m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Verify Application resource
echo ""
echo -e "${BLUE}=== Test 3: Verify Application Resource ===${NC}"
if kubectl get application test-app -n $NAMESPACE &> /dev/null; then
  pass "Application resource created"
  
  SYNC_STATUS=$(kubectl get application test-app -n $NAMESPACE -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  info "Sync Status: $SYNC_STATUS"
  
  HEALTH_STATUS=$(kubectl get application test-app -n $NAMESPACE -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  info "Health Status: $HEALTH_STATUS"
else
  fail "Application resource not found"
fi

# Wait for sync
echo ""
echo -e "${BLUE}=== Test 4: Wait for Application Sync ===${NC}"
info "Waiting for Application to sync (max 3 minutes)..."
for i in {1..36}; do
  SYNC_STATUS=$(kubectl get application test-app -n $NAMESPACE -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  if [ "$SYNC_STATUS" = "Synced" ]; then
    pass "Application synced successfully"
    break
  fi
  sleep 5
done

if [ "$SYNC_STATUS" != "Synced" ]; then
  warn "Application not synced yet (status: $SYNC_STATUS)"
  info "Check ArgoCD UI or: kubectl describe application test-app -n argocd"
fi

# Check deployed resources
echo ""
echo -e "${BLUE}=== Test 5: Verify Deployed Resources ===${NC}"
if kubectl get namespace guestbook &> /dev/null; then
  pass "Target namespace 'guestbook' created"
  
  DEPLOY_COUNT=$(kubectl get deployments -n guestbook --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$DEPLOY_COUNT" -gt 0 ]; then
    pass "Deployments created in guestbook namespace ($DEPLOY_COUNT)"
  else
    warn "No deployments found in guestbook namespace"
  fi
else
  fail "Target namespace 'guestbook' not found"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
kubectl get application test-app -n argocd 2>/dev/null || true
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
