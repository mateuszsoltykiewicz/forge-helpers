#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  common-hardening Test Suite - All Use Cases${NC}"
echo -e "${BLUE}=================================================================${NC}"

START_TIME=$(date +%s)
UC_TOTAL=3; UC_PASSED=0; UC_FAILED=0

run_test() {
  echo ""
  echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  UC0$1: $2${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
  
  if bash "test-cases/run-uc0$1.sh"; then
    echo -e "${GREEN}✅ UC0$1 PASSED${NC}"
    UC_PASSED=$((UC_PASSED + 1))
  else
    echo -e "${RED}❌ UC0$1 FAILED${NC}"
    UC_FAILED=$((UC_FAILED + 1))
  fi
}

run_test 1 "Pod Security Standards"
sleep 3
run_test 2 "Network Policies"
sleep 3
run_test 3 "Security Contexts"

END_TIME=$(date +%s); DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Final Summary${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo "Total: $UC_TOTAL, Passed: $UC_PASSED, Failed: $UC_FAILED, Duration: ${DURATION}s"

[ $UC_FAILED -eq 0 ] && echo -e "${GREEN}✅ All tests passed!${NC}" && exit 0
echo -e "${RED}❌ Some tests failed${NC}" && exit 1
