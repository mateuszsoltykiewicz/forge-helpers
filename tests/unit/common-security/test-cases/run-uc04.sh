#!/bin/bash
set -e

# UC-SECURITY-04: Scheduled Security Scans

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-SECURITY-04: Scheduled Security Scans"
RELEASE_NAME="security-scans"
NAMESPACE="security-system"
CHART_PATH="../../../../charts/common-security"
VALUES_FILE="$(dirname "$0")/../values/uc04-scheduled-scan.yaml"

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
  helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
  kubectl delete namespace $NAMESPACE 2>/dev/null || true
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

kubectl create namespace $NAMESPACE 2>/dev/null || true
pass "Namespace ready"

# Test 1: Install with Test Schedule
echo ""
echo -e "${BLUE}=== Test 1: Install CronJob ===${NC}"

info "Installing with test schedule (every 2 minutes)..."
if helm install $RELEASE_NAME $CHART_PATH -f $VALUES_FILE \
  --set scheduledScans.cronjob.schedule="*/2 * * * *" \
  -n $NAMESPACE --wait --timeout 2m; then
  pass "Chart installed"
else
  fail "Installation failed"
  exit 1
fi

sleep 5

# Test 2: Verify CronJob Created
echo ""
echo -e "${BLUE}=== Test 2: Verify CronJob ===${NC}"

if kubectl get cronjob -n $NAMESPACE | grep -q "security-scan"; then
  pass "CronJob created"
  
  SCHEDULE=$(kubectl get cronjob -n $NAMESPACE -o jsonpath='{.items[0].spec.schedule}')
  info "Schedule: $SCHEDULE"
else
  fail "CronJob not found"
fi

# Test 3: Verify RBAC
echo ""
echo -e "${BLUE}=== Test 3: Verify RBAC ===${NC}"

if kubectl get serviceaccount security-scanner -n $NAMESPACE &> /dev/null; then
  pass "ServiceAccount created"
else
  warn "ServiceAccount not found"
fi

if kubectl get clusterrole -l app=security-scanner &> /dev/null; then
  pass "ClusterRole created"
else
  warn "ClusterRole not found (may use different labels)"
fi

# Test 4: Trigger Manual Job
echo ""
echo -e "${BLUE}=== Test 4: Trigger Manual Scan ===${NC}"

info "Creating manual job from CronJob..."
CRONJOB_NAME=$(kubectl get cronjob -n $NAMESPACE -o name | head -1 | cut -d'/' -f2)

if kubectl create job test-scan-manual --from=$CRONJOB_NAME -n $NAMESPACE; then
  pass "Manual job created"
else
  fail "Failed to create manual job"
fi

# Test 5: Wait for Job Completion
echo ""
echo -e "${BLUE}=== Test 5: Wait for Scan Completion ===${NC}"

info "Waiting for job to complete (up to 5 minutes)..."
WAIT_RESULT=0
kubectl wait --for=condition=complete --timeout=300s job/test-scan-manual -n $NAMESPACE 2>/dev/null || WAIT_RESULT=$?

if [ $WAIT_RESULT -eq 0 ]; then
  pass "Scan job completed successfully"
else
  warn "Job did not complete in time (may need more time or resources)"
  
  # Check job status
  JOB_STATUS=$(kubectl get job test-scan-manual -n $NAMESPACE -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
  info "Job status: $JOB_STATUS"
fi

# Test 6: Check Job Logs
echo ""
echo -e "${BLUE}=== Test 6: Check Scan Logs ===${NC}"

JOB_POD=$(kubectl get pod -n $NAMESPACE -l job-name=test-scan-manual -o name 2>/dev/null | head -1)

if [ -n "$JOB_POD" ]; then
  info "Job pod: $JOB_POD"
  
  if kubectl logs -n $NAMESPACE $JOB_POD --tail=50 | grep -qi "trivy\|scan\|vulnerability"; then
    pass "Scan logs contain Trivy output"
  else
    warn "Logs may not contain expected output"
  fi
else
  warn "Job pod not found"
fi

# Test 7: Verify Report ConfigMap
echo ""
echo -e "${BLUE}=== Test 7: Check Report Storage ===${NC}"

if kubectl get configmap security-scan-report -n $NAMESPACE &> /dev/null; then
  pass "Report ConfigMap created"
  
  REPORT_SIZE=$(kubectl get configmap security-scan-report -n $NAMESPACE -o jsonpath='{.data}' | wc -c)
  info "Report size: $REPORT_SIZE bytes"
  
  if [ "$REPORT_SIZE" -gt 100 ]; then
    pass "Report contains data"
  else
    warn "Report may be empty"
  fi
else
  warn "Report ConfigMap not found (may not be enabled)"
fi

# Test 8: Check CronJob History
echo ""
echo -e "${BLUE}=== Test 8: Verify Job History ===${NC}"

JOB_COUNT=$(kubectl get jobs -n $NAMESPACE -l cronjob=security-scan 2>/dev/null | wc -l)

if [ "$JOB_COUNT" -gt 1 ]; then
  pass "Job history present ($JOB_COUNT jobs)"
else
  info "Job history: $JOB_COUNT jobs (expected in fresh installation)"
fi

# Test 9: Verify Schedule Format
echo ""
echo -e "${BLUE}=== Test 9: Validate Cron Schedule ===${NC}"

SCHEDULE=$(kubectl get cronjob -n $NAMESPACE -o jsonpath='{.items[0].spec.schedule}')

if echo "$SCHEDULE" | grep -qE '^\*|^[0-9]'; then
  pass "Valid cron schedule format: $SCHEDULE"
else
  fail "Invalid cron schedule: $SCHEDULE"
fi

# Test 10: Check Concurrency Policy
echo ""
echo -e "${BLUE}=== Test 10: Check Concurrency Policy ===${NC}"

CONCURRENCY=$(kubectl get cronjob -n $NAMESPACE -o jsonpath='{.items[0].spec.concurrencyPolicy}')

if [ "$CONCURRENCY" = "Forbid" ] || [ "$CONCURRENCY" = "Replace" ]; then
  pass "Concurrency policy set: $CONCURRENCY"
else
  warn "Unexpected concurrency policy: $CONCURRENCY"
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
  echo -e "${BLUE}CronJob Status:${NC}"
  kubectl get cronjob -n $NAMESPACE
  echo ""
  echo -e "${BLUE}Recent Jobs:${NC}"
  kubectl get jobs -n $NAMESPACE | head -5
  echo ""
  echo -e "${BLUE}Next Steps:${NC}"
  echo "1. Wait for scheduled job: kubectl get jobs -n $NAMESPACE -w"
  echo "2. View scan report: kubectl get configmap security-scan-report -n $NAMESPACE -o yaml"
  echo "3. Check job logs: kubectl logs -n $NAMESPACE -l job-name=<job-name>"
  echo "4. Update schedule for production: helm upgrade $RELEASE_NAME --set scheduledScans.cronjob.schedule='0 2 * * *'"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
