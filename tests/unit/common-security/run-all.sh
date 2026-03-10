#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  common-security Test Suite - All Use Cases${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

START_TIME=$(date +%s)
TESTS_DIR="$(dirname "$0")/test-cases"

UC_TOTAL=4
UC_PASSED=0
UC_FAILED=0

run_test() {
  local UC_NUM=$1
  local UC_NAME=$2
  local UC_SCRIPT="${TESTS_DIR}/run-uc0${UC_NUM}.sh"
  
  echo ""
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  UC0${UC_NUM}: ${UC_NAME}${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  if [ ! -f "$UC_SCRIPT" ]; then
    echo -e "${RED}❌ Script not found: $UC_SCRIPT${NC}"
    UC_FAILED=$((UC_FAILED + 1))
    return 1
  fi
  
  if bash "$UC_SCRIPT"; then
    echo -e "${GREEN}✅ UC0${UC_NUM} PASSED${NC}"
    UC_PASSED=$((UC_PASSED + 1))
    return 0
  else
    echo -e "${RED}❌ UC0${UC_NUM} FAILED${NC}"
    UC_FAILED=$((UC_FAILED + 1))
    return 1
  fi
}

# Run all test cases
run_test 1 "Trivy Vulnerability Scanning"
sleep 5

run_test 2 "Secret Detection"
sleep 5

run_test 3 "Falco Runtime Protection"
sleep 5

run_test 4 "Scheduled Security Scans"

# Summary
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Final Summary${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo "Total Use Cases:   $UC_TOTAL"
echo -e "${GREEN}Passed:            $UC_PASSED${NC}"
echo -e "${RED}Failed:            $UC_FAILED${NC}"
echo "Duration:          ${DURATION}s"
echo ""

if [ $UC_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All common-security use cases passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some use cases failed${NC}"
  exit 1
fi
