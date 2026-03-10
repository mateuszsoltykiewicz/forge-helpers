#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Running All Vault Tests${NC}"
echo -e "${BLUE}=================================================================${NC}"

TOTAL_PASSED=0
TOTAL_FAILED=0

cd test-cases

# UC01: Secret Injection
echo ""
echo -e "${BLUE}=== Running UC01: Secret Injection ===${NC}"
if ./run-uc01.sh; then
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

# UC02: Dynamic Database Credentials
echo ""
echo -e "${BLUE}=== Running UC02: Dynamic Database Credentials ===${NC}"
if ./run-uc02.sh; then
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

# Final summary
echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Final Test Summary${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "Passed: ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Failed: ${RED}$TOTAL_FAILED${NC}"

if [ $TOTAL_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All Vault tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some Vault tests failed${NC}"
  exit 1
fi
