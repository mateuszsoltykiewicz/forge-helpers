#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; NC='\033[0m'

TEST_NAME="UC-AWS-02: ALB Ingress with Load Balancer Controller"
NAMESPACE="aws-test"
CHART_PATH="../../../../charts/common-aws"
VALUES_FILE="../values/uc02-alb-ingress.yaml"
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASSED_TESTS=$((PASSED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILED_TESTS=$((FAILED_TESTS + 1)); TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

cleanup() {
  helm uninstall alb-test -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"

# Check EKS
echo ""
echo -e "${BLUE}=== Test 1: Verify EKS and Load Balancer Controller ===${NC}"
if kubectl get nodes -o json | grep -q "eks.amazonaws.com"; then
  pass "Running on EKS cluster"
else
  warn "Not running on EKS"
  info "ALB Ingress requires AWS EKS cluster"
  exit 2
fi

# Check AWS Load Balancer Controller
if kubectl get deployment aws-load-balancer-controller -n kube-system &> /dev/null; then
  pass "AWS Load Balancer Controller installed"
elif kubectl get deployment aws-load-balancer-webhook -n kube-system &> /dev/null; then
  pass "AWS Load Balancer Controller webhook found"
else
  warn "AWS Load Balancer Controller not found in kube-system namespace"
  info "Install: helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system"
  exit 2
fi

kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace created"

# Install chart
echo ""
echo -e "${BLUE}=== Test 2: Install Chart ===${NC}"
if helm install alb-test $CHART_PATH -f $VALUES_FILE -n $NAMESPACE --wait --timeout 5m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 10

# Verify Service
echo ""
echo -e "${BLUE}=== Test 3: Verify Service ===${NC}"
if kubectl get service alb-test-service -n $NAMESPACE &> /dev/null; then
  pass "Service created"
  
  SVC_TYPE=$(kubectl get service alb-test-service -n $NAMESPACE -o jsonpath='{.spec.type}')
  if [ "$SVC_TYPE" = "ClusterIP" ]; then
    pass "Service type is ClusterIP (required for ALB)"
  else
    warn "Service type is $SVC_TYPE (expected ClusterIP for ALB target-type: ip)"
  fi
else
  fail "Service not found"
fi

# Verify Ingress
echo ""
echo -e "${BLUE}=== Test 4: Verify Ingress ===${NC}"
if kubectl get ingress -n $NAMESPACE &> /dev/null; then
  pass "Ingress created"
  
  INGRESS_CLASS=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].spec.ingressClassName}')
  if [ "$INGRESS_CLASS" = "alb" ]; then
    pass "Ingress class is 'alb'"
  else
    warn "Ingress class is '$INGRESS_CLASS' (expected 'alb')"
  fi
else
  fail "Ingress not found"
fi

# Check ALB annotations
echo ""
echo -e "${BLUE}=== Test 5: Verify ALB Annotations ===${NC}"
SCHEME=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].metadata.annotations.alb\.ingress\.kubernetes\.io/scheme}')
if [ -n "$SCHEME" ]; then
  pass "ALB scheme annotation present: $SCHEME"
else
  fail "ALB scheme annotation not found"
fi

TARGET_TYPE=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].metadata.annotations.alb\.ingress\.kubernetes\.io/target-type}')
if [ -n "$TARGET_TYPE" ]; then
  pass "ALB target-type annotation present: $TARGET_TYPE"
else
  fail "ALB target-type annotation not found"
fi

# Check ALB provisioning
echo ""
echo -e "${BLUE}=== Test 6: Check ALB Provisioning ===${NC}"
info "Waiting for ALB to be provisioned (this may take 2-3 minutes)..."
for i in {1..30}; do
  ALB_ADDRESS=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$ALB_ADDRESS" ]; then
    pass "ALB provisioned successfully"
    info "ALB Address: $ALB_ADDRESS"
    break
  fi
  sleep 10
done

if [ -z "$ALB_ADDRESS" ]; then
  warn "ALB not provisioned yet (check Load Balancer Controller logs)"
  info "kubectl logs -n kube-system deployment/aws-load-balancer-controller"
fi

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Passed: $PASSED_TESTS, Failed: $FAILED_TESTS"
if [ -n "$ALB_ADDRESS" ]; then
  info "Test ALB: curl http://$ALB_ADDRESS/"
fi
[ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}✅ All tests passed${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
