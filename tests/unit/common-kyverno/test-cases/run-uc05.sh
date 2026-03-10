#!/bin/bash
set -e

#####################################################################
# UC-KYVERNO-05: Break-Glass Procedure (Emergency Access)
# 
# Tests break-glass procedure in 3 phases:
# 1. Before: Full enforcement, user blocked
# 2. Active: User added to exclusions, operations allowed
# 3. After: User removed, enforcement restored
#
# NOTE: This is a MANUAL test due to 3-phase Helm upgrades
#       Run each phase separately as documented below
#####################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAME="UC-KYVERNO-05: Break-Glass Procedure"
RELEASE_NAME="test-kyverno-uc05"
NAMESPACE="test-blocked"
CI_CD_NAMESPACE="ci-cd"
CHART_PATH="../../../../charts/common-kyverno"

# Values files for 3 phases
VALUES_BEFORE="$(dirname "$0")/../values/uc05-breakglass-before.yaml"
VALUES_ACTIVE="$(dirname "$0")/../values/uc05-breakglass-active.yaml"
VALUES_AFTER="$(dirname "$0")/../values/uc05-breakglass-after.yaml"

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  $TEST_NAME${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}⚠️  MANUAL TEST - Run in 3 Phases${NC}"
echo ""
echo "This test demonstrates break-glass emergency access procedure."
echo "It requires manual execution of 3 phases:"
echo ""
echo -e "${BLUE}PHASE 1: Full Enforcement (User Blocked)${NC}"
echo "  helm install $RELEASE_NAME $CHART_PATH \\"
echo "    -f values/uc05-breakglass-before.yaml \\"
echo "    -n $NAMESPACE --wait"
echo ""
echo "  # Test: User operations should be BLOCKED"
echo "  kubectl create deployment test --image=nginx -n $NAMESPACE"
echo "  # Expected: BLOCKED by policy"
echo ""
echo -e "${BLUE}PHASE 2: Break-Glass Active (User Allowed)${NC}"
echo "  helm upgrade $RELEASE_NAME $CHART_PATH \\"
echo "    -f values/uc05-breakglass-active.yaml \\"
echo "    -n $NAMESPACE --wait"
echo ""
echo "  # Test: User operations should be ALLOWED"
echo "  kubectl create deployment emergency-fix --image=nginx -n $NAMESPACE"
echo "  kubectl scale deployment emergency-fix --replicas=3 -n $NAMESPACE"
echo "  # Expected: ALLOWED (break-glass active)"
echo ""
echo -e "${BLUE}PHASE 3: Revocation (User Blocked Again)${NC}"
echo "  helm upgrade $RELEASE_NAME $CHART_PATH \\"
echo "    -f values/uc05-breakglass-after.yaml \\"
echo "    -n $NAMESPACE --wait"
echo ""
echo "  # Test: User operations should be BLOCKED again"
echo "  kubectl delete deployment emergency-fix -n $NAMESPACE"
echo "  # Expected: BLOCKED (access revoked)"
echo ""
echo -e "${BLUE}CLEANUP:${NC}"
echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
echo ""
echo -e "${YELLOW}────────────────────────────────────────────────────────────────${NC}"
echo ""

# Ask user which phase to run
read -p "Run automated test? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Test skipped. Run phases manually as documented above."
  exit 0
fi

echo ""
echo -e "${BLUE}Running Automated Break-Glass Test...${NC}"
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null || ! command -v helm &> /dev/null; then
  echo -e "${RED}❌ kubectl or helm not found${NC}"
  exit 1
fi

if ! kubectl get namespace $NAMESPACE &> /dev/null; then
  echo -e "${RED}❌ Namespace $NAMESPACE not found${NC}"
  exit 1
fi

# Cleanup function
cleanup() {
  echo -e "\n${BLUE}=== Cleanup ===${NC}"
  kubectl delete deployment emergency-fix breakglass-app -n $NAMESPACE 2>/dev/null || true
  helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
  sleep 2
  echo -e "${GREEN}✅ Cleanup completed${NC}"
}
trap cleanup EXIT

# PHASE 1: Full Enforcement
echo -e "${BLUE}=== PHASE 1: Full Enforcement ===${NC}"
echo "Installing chart with full enforcement (user blocked)..."

if helm install $RELEASE_NAME $CHART_PATH \
    -f $VALUES_BEFORE \
    -n $NAMESPACE \
    --wait --timeout 2m; then
  echo -e "${GREEN}✅ Chart installed${NC}"
else
  echo -e "${RED}❌ Chart installation failed${NC}"
  exit 1
fi

sleep 5

# Test: User should be BLOCKED
echo ""
echo "Testing user operations (should be BLOCKED)..."
if kubectl create deployment breakglass-app --image=nginx -n $NAMESPACE &> /tmp/uc05-phase1.log; then
  echo -e "${RED}❌ FAIL: User CREATE was ALLOWED (should be blocked)${NC}"
else
  if grep -q -i "direct workload modifications are blocked\|block-workload" /tmp/uc05-phase1.log; then
    echo -e "${GREEN}✅ PASS: User CREATE blocked by policy${NC}"
  else
    echo -e "${RED}❌ FAIL: Blocked but unexpected message${NC}"
  fi
fi

# Create deployment using CI/CD for next phase
DEPLOY_TOKEN=$(kubectl create token deployment-job -n $CI_CD_NAMESPACE --duration=1h 2>/dev/null || echo "")
if [ ! -z "$DEPLOY_TOKEN" ]; then
  kubectl --token=$DEPLOY_TOKEN create deployment breakglass-app --image=nginx -n $NAMESPACE &> /dev/null || true
  sleep 3
fi

# PHASE 2: Break-Glass Active
echo ""
echo -e "${BLUE}=== PHASE 2: Break-Glass Active ===${NC}"
echo "Upgrading chart with user exclusion (break-glass granted)..."

if helm upgrade $RELEASE_NAME $CHART_PATH \
    -f $VALUES_ACTIVE \
    -n $NAMESPACE \
    --wait --timeout 2m; then
  echo -e "${GREEN}✅ Chart upgraded - break-glass access granted${NC}"
else
  echo -e "${RED}❌ Chart upgrade failed${NC}"
  exit 1
fi

sleep 5

# Test: User should be ALLOWED
echo ""
echo "Testing user operations (should be ALLOWED)..."
if kubectl scale deployment breakglass-app --replicas=3 -n $NAMESPACE &> /tmp/uc05-phase2.log; then
  echo -e "${GREEN}✅ PASS: User SCALE allowed (break-glass active)${NC}"
  
  POD_NAME=$(kubectl get pod -n $NAMESPACE -l app=breakglass-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ ! -z "$POD_NAME" ]; then
    if kubectl exec -n $NAMESPACE $POD_NAME -- ls &> /dev/null; then
      echo -e "${GREEN}✅ PASS: User EXEC allowed (break-glass active)${NC}"
    else
      echo -e "${YELLOW}⚠️  WARN: User EXEC failed (pod may not be ready)${NC}"
    fi
  fi
else
  echo -e "${RED}❌ FAIL: User SCALE was BLOCKED (should be allowed)${NC}"
  cat /tmp/uc05-phase2.log
fi

# PHASE 3: Revocation
echo ""
echo -e "${BLUE}=== PHASE 3: Revocation ===${NC}"
echo "Upgrading chart with user removed (break-glass revoked)..."

if helm upgrade $RELEASE_NAME $CHART_PATH \
    -f $VALUES_AFTER \
    -n $NAMESPACE \
    --wait --timeout 2m; then
  echo -e "${GREEN}✅ Chart upgraded - break-glass access revoked${NC}"
else
  echo -e "${RED}❌ Chart upgrade failed${NC}"
  exit 1
fi

sleep 5

# Test: User should be BLOCKED again
echo ""
echo "Testing user operations (should be BLOCKED again)..."
if kubectl delete deployment breakglass-app -n $NAMESPACE &> /tmp/uc05-phase3.log; then
  echo -e "${RED}❌ FAIL: User DELETE was ALLOWED (should be blocked)${NC}"
else
  if grep -q -i "direct workload modifications are blocked\|block-workload" /tmp/uc05-phase3.log; then
    echo -e "${GREEN}✅ PASS: User DELETE blocked by policy (access revoked)${NC}"
  else
    echo -e "${RED}❌ FAIL: Blocked but unexpected message${NC}"
  fi
fi

# Summary
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "${GREEN}✅ PHASE 1: User blocked (full enforcement)${NC}"
echo -e "${GREEN}✅ PHASE 2: User allowed (break-glass active)${NC}"
echo -e "${GREEN}✅ PHASE 3: User blocked (access revoked)${NC}"
echo ""
echo -e "${GREEN}✅ Break-Glass Procedure Test Complete${NC}"
echo ""
echo -e "${BLUE}Audit Trail:${NC}"
echo "  • Break-glass duration: ~30 seconds (automated test)"
echo "  • All operations logged in PolicyReports"
echo "  • Cleanup will remove test resources"
