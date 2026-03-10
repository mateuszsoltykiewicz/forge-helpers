#!/bin/bash
set -e

# UC-SECURITY-01: Trivy Vulnerability Scanning

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-SECURITY-01: Trivy Vulnerability Scanning"
RELEASE_NAME="trivy-security"
TRIVY_NAMESPACE="trivy-system"
APP_NAMESPACE="test-security"
CHART_PATH="../../../../charts/common-security"
VALUES_FILE="$(dirname "$0")/../values/uc01-trivy-vuln.yaml"
WORKLOAD_FILE="$(dirname "$0")/../workloads/vulnerable-app.yaml"

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
  helm uninstall $RELEASE_NAME -n $TRIVY_NAMESPACE 2>/dev/null || true
  kubectl delete namespace $APP_NAMESPACE 2>/dev/null || true
  kubectl delete namespace $TRIVY_NAMESPACE 2>/dev/null || true
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
if ! kubectl get namespace $TRIVY_NAMESPACE &> /dev/null; then
  kubectl create namespace $TRIVY_NAMESPACE
  info "Created namespace $TRIVY_NAMESPACE"
fi
pass "Trivy namespace ready"

if ! kubectl get namespace $APP_NAMESPACE &> /dev/null; then
  kubectl create namespace $APP_NAMESPACE
  info "Created namespace $APP_NAMESPACE"
fi
pass "Application namespace ready"

# Test 1: Install Trivy Operator
echo ""
echo -e "${BLUE}=== Test 1: Install Trivy Operator ===${NC}"

if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE -n $TRIVY_NAMESPACE --wait --timeout 5m; then
  pass "Trivy Operator chart installed"
else
  fail "Chart installation failed"
  exit 1
fi

sleep 10

# Test 2: Verify Operator Deployment
echo ""
echo -e "${BLUE}=== Test 2: Verify Operator Deployment ===${NC}"

if kubectl get deployment -n $TRIVY_NAMESPACE | grep -q "trivy-operator"; then
  pass "Trivy Operator deployment found"
  
  REPLICAS=$(kubectl get deployment -n $TRIVY_NAMESPACE -l app.kubernetes.io/name=trivy-operator -o jsonpath='{.items[0].status.readyReplicas}')
  if [ "$REPLICAS" -ge 1 ]; then
    pass "Trivy Operator is running ($REPLICAS replicas)"
  else
    fail "Trivy Operator not ready"
  fi
else
  fail "Trivy Operator deployment not found"
fi

# Test 3: Check CRDs Installed
echo ""
echo -e "${BLUE}=== Test 3: Verify Trivy CRDs ===${NC}"

if kubectl get crd vulnerabilityreports.aquasecurity.github.io &> /dev/null; then
  pass "VulnerabilityReport CRD installed"
else
  fail "VulnerabilityReport CRD not found"
fi

if kubectl get crd configauditreports.aquasecurity.github.io &> /dev/null; then
  pass "ConfigAuditReport CRD installed"
else
  warn "ConfigAuditReport CRD not found (optional)"
fi

if kubectl get crd exposedsecretreports.aquasecurity.github.io &> /dev/null; then
  pass "ExposedSecretReport CRD installed"
else
  warn "ExposedSecretReport CRD not found (optional)"
fi

# Test 4: Deploy Vulnerable Application
echo ""
echo -e "${BLUE}=== Test 4: Deploy Vulnerable Application ===${NC}"

if kubectl apply -f $WORKLOAD_FILE -n $APP_NAMESPACE; then
  pass "Vulnerable nginx deployed"
else
  fail "Failed to deploy vulnerable app"
  exit 1
fi

sleep 15

# Test 5: Verify Pod Running
echo ""
echo -e "${BLUE}=== Test 5: Verify Application Running ===${NC}"

if kubectl get pod -n $APP_NAMESPACE -l app=vulnerable-nginx | grep -q "Running"; then
  pass "Vulnerable pod is running"
  
  POD_NAME=$(kubectl get pod -n $APP_NAMESPACE -l app=vulnerable-nginx -o jsonpath='{.items[0].metadata.name}')
  info "Pod name: $POD_NAME"
else
  fail "Pod not running"
fi

# Test 6: Wait for Scan Job
echo ""
echo -e "${BLUE}=== Test 6: Wait for Trivy Scan ===${NC}"

info "Waiting for Trivy scan job to complete (60-120 seconds)..."
SCAN_TIMEOUT=180
ELAPSED=0

while [ $ELAPSED -lt $SCAN_TIMEOUT ]; do
  if kubectl get vulnerabilityreport -n $APP_NAMESPACE 2>/dev/null | grep -q "vulnerable-nginx"; then
    pass "VulnerabilityReport created"
    break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo -n "."
done

echo ""

if [ $ELAPSED -ge $SCAN_TIMEOUT ]; then
  fail "Scan timeout after ${SCAN_TIMEOUT}s"
  warn "Check Trivy Operator logs:"
  echo "   kubectl logs -n $TRIVY_NAMESPACE -l app.kubernetes.io/name=trivy-operator"
else
  pass "Scan completed in ${ELAPSED}s"
fi

# Test 7: Verify VulnerabilityReport Exists
echo ""
echo -e "${BLUE}=== Test 7: Check VulnerabilityReport ===${NC}"

REPORT_COUNT=$(kubectl get vulnerabilityreport -n $APP_NAMESPACE 2>/dev/null | grep -c "vulnerable-nginx" || echo "0")

if [ "$REPORT_COUNT" -gt 0 ]; then
  pass "Found $REPORT_COUNT vulnerability report(s)"
  
  REPORT_NAME=$(kubectl get vulnerabilityreport -n $APP_NAMESPACE -o name | head -1 | cut -d'/' -f2)
  info "Report name: $REPORT_NAME"
else
  fail "No vulnerability reports found"
fi

# Test 8: Check for Critical Vulnerabilities
echo ""
echo -e "${BLUE}=== Test 8: Analyze Vulnerability Severity ===${NC}"

if kubectl get vulnerabilityreport -n $APP_NAMESPACE -o json &> /dev/null; then
  CRITICAL=$(kubectl get vulnerabilityreport -n $APP_NAMESPACE -o json | jq -r '.items[0].report.summary.criticalCount // 0' 2>/dev/null)
  HIGH=$(kubectl get vulnerabilityreport -n $APP_NAMESPACE -o json | jq -r '.items[0].report.summary.highCount // 0' 2>/dev/null)
  MEDIUM=$(kubectl get vulnerabilityreport -n $APP_NAMESPACE -o json | jq -r '.items[0].report.summary.mediumCount // 0' 2>/dev/null)
  
  info "Vulnerability counts:"
  echo "   CRITICAL: $CRITICAL"
  echo "   HIGH:     $HIGH"
  echo "   MEDIUM:   $MEDIUM"
  
  if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
    pass "Detected vulnerabilities (CRITICAL: $CRITICAL, HIGH: $HIGH)"
  else
    warn "No high/critical vulnerabilities found (unexpected for nginx:1.14.0)"
  fi
else
  warn "Could not analyze vulnerability severity"
fi

# Test 9: Check for Known CVEs
echo ""
echo -e "${BLUE}=== Test 9: Search for Known CVEs ===${NC}"

REPORT_YAML="/tmp/vuln-report-uc01.yaml"
kubectl get vulnerabilityreport -n $APP_NAMESPACE -o yaml > $REPORT_YAML 2>/dev/null

# Check for CVE-2018-16843 (nginx CRITICAL vulnerability)
if grep -q "CVE-2018-16843" $REPORT_YAML; then
  pass "Found CVE-2018-16843 (nginx CPU exhaustion DoS)"
else
  warn "CVE-2018-16843 not found (may be patched in DB)"
fi

# Check for any CVE
CVE_COUNT=$(grep -c "CVE-" $REPORT_YAML || echo "0")
if [ "$CVE_COUNT" -gt 0 ]; then
  pass "Found $CVE_COUNT CVE entries in report"
else
  warn "No CVE entries found"
fi

# Test 10: Verify Report Structure
echo ""
echo -e "${BLUE}=== Test 10: Validate Report Structure ===${NC}"

if grep -q "aquasecurity.github.io/v1alpha1" $REPORT_YAML; then
  pass "Report has correct API version"
else
  fail "Report API version incorrect"
fi

if grep -q "artifact:" $REPORT_YAML && grep -q "scanner:" $REPORT_YAML; then
  pass "Report contains artifact and scanner info"
else
  fail "Report missing required fields"
fi

if grep -q "nginx" $REPORT_YAML && grep -q "1.14.0" $REPORT_YAML; then
  pass "Report identifies nginx:1.14.0 image"
else
  fail "Report doesn't identify target image"
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
  echo -e "${BLUE}Sample Vulnerabilities Found:${NC}"
  kubectl get vulnerabilityreport -n $APP_NAMESPACE -o json 2>/dev/null | \
    jq -r '.items[0].report.vulnerabilities[:3] | .[] | "- \(.vulnerabilityID): \(.severity) - \(.title)"' 2>/dev/null || true
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Review full report: kubectl get vulnerabilityreport -n $APP_NAMESPACE -o yaml"
  echo "2. Generate HTML report: trivy image nginx:1.14.0 --format template --template '@contrib/html.tpl'"
  echo "3. Upgrade nginx to latest: kubectl set image deployment/vulnerable-nginx nginx=nginx:latest -n $APP_NAMESPACE"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
