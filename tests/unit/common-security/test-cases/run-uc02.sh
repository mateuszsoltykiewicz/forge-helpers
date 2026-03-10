#!/bin/bash
set -e

# UC-SECURITY-02: Secret Detection

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-SECURITY-02: Secret Detection"
RELEASE_NAME="trivy-security"
TRIVY_NAMESPACE="trivy-system"
APP_NAMESPACE="test-security"
CHART_PATH="../../../../charts/common-security"
VALUES_FILE="$(dirname "$0")/../values/uc02-secret-scan.yaml"
WORKLOAD_FILE="$(dirname "$0")/../workloads/app-with-secrets.yaml"

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

if ! command -v jq &> /dev/null; then
  warn "jq not found - some tests will be skipped"
else
  pass "jq installed"
fi

# Create namespaces
kubectl create namespace $TRIVY_NAMESPACE 2>/dev/null || true
kubectl create namespace $APP_NAMESPACE 2>/dev/null || true
pass "Namespaces ready"

# Test 1: Install Trivy Operator
echo ""
echo -e "${BLUE}=== Test 1: Install Trivy Operator ===${NC}"

if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE -n $TRIVY_NAMESPACE --wait --timeout 5m; then
  pass "Trivy Operator installed"
else
  fail "Chart installation failed"
  exit 1
fi

sleep 10

# Test 2: Verify CRDs
echo ""
echo -e "${BLUE}=== Test 2: Verify Secret Scanning CRDs ===${NC}"

if kubectl get crd configauditreports.aquasecurity.github.io &> /dev/null; then
  pass "ConfigAuditReport CRD installed"
else
  fail "ConfigAuditReport CRD not found"
fi

if kubectl get crd exposedsecretreports.aquasecurity.github.io &> /dev/null; then
  pass "ExposedSecretReport CRD installed"
else
  warn "ExposedSecretReport CRD not found (optional)"
fi

# Test 3: Deploy App with Secrets
echo ""
echo -e "${BLUE}=== Test 3: Deploy Application with Hardcoded Secrets ===${NC}"

if kubectl apply -f $WORKLOAD_FILE -n $APP_NAMESPACE; then
  pass "Application deployed"
else
  fail "Failed to deploy application"
  exit 1
fi

sleep 20

# Test 4: Verify Pod Running
echo ""
echo -e "${BLUE}=== Test 4: Verify Pod Running ===${NC}"

if kubectl get pod -n $APP_NAMESPACE -l app=secret-test | grep -q "Running"; then
  pass "Pod is running"
  POD_NAME=$(kubectl get pod -n $APP_NAMESPACE -l app=secret-test -o jsonpath='{.items[0].metadata.name}')
  info "Pod name: $POD_NAME"
else
  fail "Pod not running"
fi

# Test 5: Wait for ConfigAuditReport
echo ""
echo -e "${BLUE}=== Test 5: Wait for Secret Scan ===${NC}"

info "Waiting for ConfigAuditReport (60-120 seconds)..."
SCAN_TIMEOUT=180
ELAPSED=0

while [ $ELAPSED -lt $SCAN_TIMEOUT ]; do
  if kubectl get configauditreport -n $APP_NAMESPACE 2>/dev/null | grep -q "app-with-secrets"; then
    pass "ConfigAuditReport created"
    break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo -n "."
done

echo ""

if [ $ELAPSED -ge $SCAN_TIMEOUT ]; then
  fail "Scan timeout after ${SCAN_TIMEOUT}s"
  warn "Check operator logs: kubectl logs -n $TRIVY_NAMESPACE -l app.kubernetes.io/name=trivy-operator"
else
  pass "Scan completed in ${ELAPSED}s"
fi

# Test 6: Verify Report Exists
echo ""
echo -e "${BLUE}=== Test 6: Verify ConfigAuditReport ===${NC}"

REPORT_COUNT=$(kubectl get configauditreport -n $APP_NAMESPACE 2>/dev/null | grep -c "app-with-secrets" || echo "0")

if [ "$REPORT_COUNT" -gt 0 ]; then
  pass "Found $REPORT_COUNT config audit report(s)"
  
  REPORT_NAME=$(kubectl get configauditreport -n $APP_NAMESPACE -o name | head -1 | cut -d'/' -f2)
  info "Report name: $REPORT_NAME"
else
  fail "No config audit reports found"
fi

# Test 7: Check for Secret Findings
echo ""
echo -e "${BLUE}=== Test 7: Analyze Secret Findings ===${NC}"

REPORT_YAML="/tmp/config-audit-uc02.yaml"
kubectl get configauditreport -n $APP_NAMESPACE -o yaml > $REPORT_YAML 2>/dev/null

if grep -qi "secret\|password\|key\|token" $REPORT_YAML; then
  pass "Found secret-related findings in report"
else
  warn "No secret-related findings (unexpected)"
fi

# Test 8: Check Severity Counts
echo ""
echo -e "${BLUE}=== Test 8: Check Finding Severity ===${NC}"

if command -v jq &> /dev/null; then
  CRITICAL=$(kubectl get configauditreport -n $APP_NAMESPACE -o json | jq -r '.items[0].report.summary.criticalCount // 0' 2>/dev/null)
  HIGH=$(kubectl get configauditreport -n $APP_NAMESPACE -o json | jq -r '.items[0].report.summary.highCount // 0' 2>/dev/null)
  MEDIUM=$(kubectl get configauditreport -n $APP_NAMESPACE -o json | jq -r '.items[0].report.summary.mediumCount // 0' 2>/dev/null)
  
  info "Finding counts:"
  echo "   CRITICAL: $CRITICAL"
  echo "   HIGH:     $HIGH"
  echo "   MEDIUM:   $MEDIUM"
  
  if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
    pass "Detected security issues (CRITICAL: $CRITICAL, HIGH: $HIGH)"
  else
    warn "No high/critical findings (unexpected for app with secrets)"
  fi
else
  warn "jq not installed - skipping severity analysis"
fi

# Test 9: AWS Credential Detection
echo ""
echo -e "${BLUE}=== Test 9: Specific Secret Detection ===${NC}"

if grep -q "AWS_ACCESS_KEY\|AKIA" $REPORT_YAML; then
  pass "Detected AWS credentials"
else
  warn "AWS credentials not detected"
fi

if grep -qi "password" $REPORT_YAML; then
  pass "Detected password"
else
  warn "Password not detected"
fi

if grep -q "GITHUB_TOKEN\|ghp_" $REPORT_YAML; then
  pass "Detected GitHub token"
else
  warn "GitHub token not detected"
fi

if grep -q "API_KEY\|sk-" $REPORT_YAML; then
  pass "Detected API key"
else
  warn "API key not detected"
fi

# Test 10: Remediation Guidance
echo ""
echo -e "${BLUE}=== Test 10: Check Remediation Info ===${NC}"

if grep -qi "remediation\|fix\|use.*secret" $REPORT_YAML; then
  pass "Report includes remediation guidance"
else
  warn "No remediation guidance found"
fi

if grep -qi "kubernetes.*secret\|vault\|external.*secret" $REPORT_YAML; then
  pass "Report suggests proper secret management"
else
  warn "No secret management suggestions"
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
  echo -e "${BLUE}Hardcoded Secrets Found:${NC}"
  if command -v jq &> /dev/null; then
    kubectl get configauditreport -n $APP_NAMESPACE -o json 2>/dev/null | \
      jq -r '.items[0].report.checks[] | select(.category == "Secret") | "- \(.checkID): \(.severity) - \(.title)"' 2>/dev/null | head -5 || true
  else
    grep -i "secret\|password\|key" $REPORT_YAML | head -10 || true
  fi
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Review full report: kubectl get configauditreport -n $APP_NAMESPACE -o yaml"
  echo "2. Migrate to Kubernetes Secrets: kubectl create secret generic my-secret --from-literal=key=value"
  echo "3. Use external secret managers: Vault, AWS Secrets Manager, Azure Key Vault"
  echo "4. Implement secret rotation policies"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
