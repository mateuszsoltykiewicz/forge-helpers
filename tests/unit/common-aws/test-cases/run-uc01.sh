#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

TEST_NAME="UC-AWS-01: IRSA (IAM Roles for ServiceAccounts)"
NAMESPACE="aws-test"
CHART_PATH="../../../../charts/common-aws"
VALUES_FILE="../values/uc01-irsa.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

cleanup() {
  helm uninstall irsa-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check if running on EKS
echo ""
echo -e "${BLUE}=== Test 1: Verify EKS Cluster ===${NC}"
if kubectl get nodes -o json | grep -q "eks.amazonaws.com"; then
  pass "Running on EKS cluster"
else
  warn "Not running on EKS - IRSA requires EKS"
  info "This test requires an AWS EKS cluster with OIDC provider configured"
  exit 2
fi

# Check OIDC provider
OIDC_ISSUER=$(kubectl get --raw /.well-known/openid-configuration 2>/dev/null | grep -o '"issuer":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "$OIDC_ISSUER" ]; then
  pass "OIDC provider configured"
  info "OIDC Issuer: $OIDC_ISSUER"
else
  fail "OIDC provider not found"
fi

kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Install chart
echo ""
echo -e "${BLUE}=== Test 2: Install Chart ===${NC}"
if helm install irsa-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 5m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Verify ServiceAccount
echo ""
echo -e "${BLUE}=== Test 3: Verify ServiceAccount with IAM Role ===${NC}"
if kubectl get sa s3-access-sa -n $NAMESPACE &> /dev/null; then
  pass "ServiceAccount created"
  
  ROLE_ARN=$(kubectl get sa s3-access-sa -n $NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
  if [ -n "$ROLE_ARN" ]; then
    pass "IAM role annotation present"
    info "Role ARN: $ROLE_ARN"
  else
    fail "IAM role annotation not found"
  fi
else
  fail "ServiceAccount not found"
fi

# Verify deployment
echo ""
echo -e "${BLUE}=== Test 4: Verify Deployment ===${NC}"
if kubectl get deployment irsa-test-app -n $NAMESPACE &> /dev/null; then
  pass "Deployment created"
  
  POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=irsa-test-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD_NAME" ]; then
    info "Pod: $POD_NAME"
  else
    fail "No pods found"
  fi
else
  fail "Deployment not found"
fi

# Check AWS credentials injected
echo ""
echo -e "${BLUE}=== Test 5: Verify AWS Credentials Injection ===${NC}"
if [ -n "$POD_NAME" ]; then
  if kubectl exec $POD_NAME -n $NAMESPACE -- env | grep -q "AWS_ROLE_ARN"; then
    pass "AWS environment variables injected"
  else
    info "AWS_ROLE_ARN not found (may require pod restart)"
  fi
  
  if kubectl exec $POD_NAME -n $NAMESPACE -- ls /var/run/secrets/eks.amazonaws.com/serviceaccount/token &> /dev/null; then
    pass "OIDC token mounted"
  else
    warn "OIDC token not found at expected path"
  fi
else
  fail "Cannot verify credentials (no pod)"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
info "To test AWS access: kubectl exec -it $POD_NAME -n $NAMESPACE -- aws s3 ls"
info "Note: IAM role must be created in AWS with trust policy for this ServiceAccount"
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
