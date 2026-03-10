#!/bin/bash
set -e

# Run all common-monitoring Use Cases

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_DIR="$(dirname "$0")"
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_UCS=4

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  common-monitoring: Full Test Suite${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# UC01: Pod Crash Alerts
echo -e "${BLUE}[1/4] Running UC01: Pod Crash Alerts${NC}"
if "$TEST_DIR/run-uc01.sh"; then
  echo -e "${GREEN}✅ UC01 PASSED${NC}"
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  echo -e "${RED}❌ UC01 FAILED${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""
echo "---"
echo ""

# UC02: Grafana Dashboard
echo -e "${BLUE}[2/4] Running UC02: Grafana Dashboard${NC}"
if "$TEST_DIR/run-uc02.sh"; then
  echo -e "${GREEN}✅ UC02 PASSED${NC}"
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  echo -e "${RED}❌ UC02 FAILED${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""
echo "---"
echo ""

# UC03: SLO Latency
echo -e "${BLUE}[3/4] Running UC03: SLO Latency${NC}"
if "$TEST_DIR/run-uc03.sh"; then
  echo -e "${GREEN}✅ UC03 PASSED${NC}"
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  echo -e "${RED}❌ UC03 FAILED${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""
echo "---"
echo ""

# UC04: Multi-Environment Alerting
echo -e "${BLUE}[4/4] Running UC04: Multi-Environment Alerting${NC}"
if "$TEST_DIR/run-uc04.sh"; then
  echo -e "${GREEN}✅ UC04 PASSED${NC}"
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  echo -e "${RED}❌ UC04 FAILED${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""

# Final Summary
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Final Summary${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo "Total Use Cases:     $TOTAL_UCS"
echo -e "${GREEN}Passed:              $TOTAL_PASSED${NC}"
echo -e "${RED}Failed:              $TOTAL_FAILED${NC}"
echo ""

if [ $TOTAL_FAILED -eq 0 ]; then
  echo -e "${GREEN}🎉 All common-monitoring tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed. Check logs above.${NC}"
  exit 1
fi
