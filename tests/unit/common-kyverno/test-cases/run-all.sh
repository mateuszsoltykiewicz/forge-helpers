#!/bin/bash
set -e

#####################################################################
# RUN ALL KYVERNO USE CASES
# 
# Executes all 6 common-kyverno use case tests sequentially.
# Each test cleans up after itself to avoid conflicts.
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  COMMON-KYVERNO: All Use Cases${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo "Running all 6 common-kyverno use case tests..."
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}❌ kubectl not found${NC}"
  exit 1
fi

if ! command -v helm &> /dev/null; then
  echo -e "${RED}❌ helm not found${NC}"
  exit 1
fi

# Check if Kyverno is installed
if ! kubectl get namespace kyverno &> /dev/null; then
  echo -e "${RED}❌ Kyverno namespace not found${NC}"
  echo "Please install Kyverno first: cd tests/scripts && ./install-kyverno.sh"
  exit 1
fi

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

declare -a TEST_RESULTS

# Function to run a test
run_test() {
  local test_script="$1"
  local test_name="$2"
  
  echo ""
  echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
  echo -e "${BLUE}Running: $test_name${NC}"
  echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  
  if [ ! -f "$test_script" ]; then
    echo -e "${RED}❌ Test script not found: $test_script${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TEST_RESULTS+=("❌ $test_name - SCRIPT NOT FOUND")
    return 1
  fi
  
  if [ ! -x "$test_script" ]; then
    echo -e "${YELLOW}⚠️  Making test script executable...${NC}"
    chmod +x "$test_script"
  fi
  
  # Run test and capture exit code
  if "$test_script"; then
    echo -e "${GREEN}✅ $test_name - PASSED${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TEST_RESULTS+=("✅ $test_name - PASSED")
  else
    local exit_code=$?
    if [ $exit_code -eq 2 ]; then
      echo -e "${YELLOW}⚠️  $test_name - SKIPPED${NC}"
      SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
      TEST_RESULTS+=("⚠️  $test_name - SKIPPED")
    else
      echo -e "${RED}❌ $test_name - FAILED${NC}"
      FAILED_TESTS=$((FAILED_TESTS + 1))
      TEST_RESULTS+=("❌ $test_name - FAILED")
    fi
  fi
  
  # Wait between tests to allow cleanup
  sleep 5
}

# Run all tests
run_test "$SCRIPT_DIR/run-uc01.sh" "UC01: Block kubectl exec"
run_test "$SCRIPT_DIR/run-uc02.sh" "UC02: Block Direct Deployments (GitOps-only)"
run_test "$SCRIPT_DIR/run-uc03.sh" "UC03: Debug Proxy Access"
run_test "$SCRIPT_DIR/run-uc04.sh" "UC04: GitOps Workflow (Full)"
run_test "$SCRIPT_DIR/run-uc05.sh" "UC05: Break-Glass Procedure"
run_test "$SCRIPT_DIR/run-uc06.sh" "UC06: Audit Mode"

# Summary
echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  TEST SUMMARY${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo "Total Tests:   $TOTAL_TESTS"
echo -e "${GREEN}Passed:        $PASSED_TESTS${NC}"
echo -e "${RED}Failed:        $FAILED_TESTS${NC}"
echo -e "${YELLOW}Skipped:       $SKIPPED_TESTS${NC}"
echo ""

# Print individual results
echo -e "${BLUE}Individual Results:${NC}"
for result in "${TEST_RESULTS[@]}"; do
  echo "  $result"
done

echo ""
if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
  exit 0
elif [ $PASSED_TESTS -gt 0 ]; then
  echo -e "${YELLOW}⚠️  SOME TESTS FAILED${NC}"
  exit 1
else
  echo -e "${RED}❌ ALL TESTS FAILED${NC}"
  exit 1
fi
