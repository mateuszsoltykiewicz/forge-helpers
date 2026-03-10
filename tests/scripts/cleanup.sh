#!/bin/bash

##############################################################################
# Forge Helpers - Test Environment Cleanup Script
#
# This script removes all test resources from the cluster:
# 1. Test workloads
# 2. Test ServiceAccounts and RBAC
# 3. Test namespaces
# 4. Optionally: Trivy and Falco operators
#
# Usage: ./cleanup.sh [--remove-operators] [--force]
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
REMOVE_OPERATORS=false
FORCE=false

for arg in "$@"; do
  case $arg in
    --remove-operators)
      REMOVE_OPERATORS=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --remove-operators Remove Trivy and Falco operators"
      echo "  --force            Skip confirmation prompts"
      echo "  --help             Show this help message"
      exit 0
      ;;
  esac
done

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Forge Helpers - Test Environment Cleanup${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Confirmation
if [ "$FORCE" = false ]; then
  echo -e "${YELLOW}⚠️  This will delete all test resources from the cluster${NC}"
  echo ""
  echo "Resources to be deleted:"
  echo "  - Test workloads (test-nginx, crashloop-test, etc.)"
  echo "  - Test ServiceAccounts and RBAC"
  echo "  - Test namespaces (test-app, test-blocked, test-allowed, ci-cd)"
  
  if [ "$REMOVE_OPERATORS" = true ]; then
    echo "  - Trivy Operator"
    echo "  - Falco"
  fi
  
  echo ""
  read -p "Are you sure you want to continue? (yes/no): " -r
  echo ""
  
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
  fi
fi

##############################################################################
# 1. Delete Test Workloads
##############################################################################

echo -e "${BLUE}=== Step 1: Deleting Test Workloads ===${NC}"
echo ""

if kubectl get namespace test-app &> /dev/null; then
  echo -e "${YELLOW}Deleting workloads from test-app namespace...${NC}"
  kubectl delete -f ../prerequisites/test-workloads.yaml --ignore-not-found=true
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Test workloads deleted${NC}"
  else
    echo -e "${RED}❌ Failed to delete some test workloads${NC}"
  fi
else
  echo -e "${YELLOW}⏭️  test-app namespace not found, skipping workload deletion${NC}"
fi
echo ""

##############################################################################
# 2. Delete Test ServiceAccounts and RBAC
##############################################################################

echo -e "${BLUE}=== Step 2: Deleting Test ServiceAccounts and RBAC ===${NC}"
echo ""

echo -e "${YELLOW}Deleting ServiceAccounts and RBAC resources...${NC}"
kubectl delete -f ../prerequisites/test-serviceaccounts.yaml --ignore-not-found=true

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ ServiceAccounts and RBAC deleted${NC}"
else
  echo -e "${RED}❌ Failed to delete some RBAC resources${NC}"
fi
echo ""

##############################################################################
# 3. Delete Test Namespaces
##############################################################################

echo -e "${BLUE}=== Step 3: Deleting Test Namespaces ===${NC}"
echo ""

echo -e "${YELLOW}Deleting test namespaces (this may take a moment)...${NC}"
kubectl delete -f ../prerequisites/test-namespaces.yaml --ignore-not-found=true

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Test namespaces deleted${NC}"
  
  # Wait for namespaces to be fully terminated
  echo -e "${YELLOW}Waiting for namespaces to terminate...${NC}"
  for ns in test-app test-blocked test-allowed ci-cd; do
    kubectl wait --for=delete namespace/$ns --timeout=120s 2>/dev/null || true
  done
  echo -e "${GREEN}✅ Namespaces terminated${NC}"
else
  echo -e "${RED}❌ Failed to delete some namespaces${NC}"
fi
echo ""

##############################################################################
# 4. Remove Operators (Optional)
##############################################################################

if [ "$REMOVE_OPERATORS" = true ]; then
  echo -e "${BLUE}=== Step 4: Removing Operators ===${NC}"
  echo ""
  
  # Remove Trivy Operator
  echo -e "${YELLOW}Uninstalling Trivy Operator...${NC}"
  helm uninstall trivy-operator -n trivy-system --wait 2>/dev/null || true
  kubectl delete namespace trivy-system --ignore-not-found=true
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Trivy Operator removed${NC}"
  else
    echo -e "${YELLOW}⚠️  Trivy Operator may not have been installed${NC}"
  fi
  echo ""
  
  # Remove Falco
  echo -e "${YELLOW}Uninstalling Falco...${NC}"
  helm uninstall falco -n falco --wait 2>/dev/null || true
  kubectl delete namespace falco --ignore-not-found=true
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Falco removed${NC}"
  else
    echo -e "${YELLOW}⚠️  Falco may not have been installed${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Skipping operator removal (use --remove-operators to remove)${NC}"
  echo ""
fi

##############################################################################
# 5. Clean up Helm test releases (if any)
##############################################################################

echo -e "${BLUE}=== Step 5: Cleaning up Helm test releases ===${NC}"
echo ""

echo -e "${YELLOW}Checking for test Helm releases...${NC}"
test_releases=$(helm list -A | grep -E "test-|forge-helpers-test" | awk '{print $1 " -n " $2}' || true)

if [ -z "$test_releases" ]; then
  echo -e "${GREEN}✅ No test Helm releases found${NC}"
else
  echo "Found test releases:"
  echo "$test_releases"
  echo ""
  
  if [ "$FORCE" = false ]; then
    read -p "Delete these Helm releases? (yes/no): " -r
    echo ""
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
      echo "$test_releases" | while read -r release; do
        helm uninstall $release --wait || true
      done
      echo -e "${GREEN}✅ Test Helm releases removed${NC}"
    else
      echo -e "${YELLOW}⏭️  Skipping Helm release removal${NC}"
    fi
  else
    echo "$test_releases" | while read -r release; do
      helm uninstall $release --wait || true
    done
    echo -e "${GREEN}✅ Test Helm releases removed${NC}"
  fi
fi
echo ""

##############################################################################
# 6. Verification
##############################################################################

echo -e "${BLUE}=== Step 6: Verification ===${NC}"
echo ""

echo -e "${YELLOW}Checking remaining test resources...${NC}"

remaining_ns=$(kubectl get namespaces | grep -E "test-app|test-blocked|test-allowed" | wc -l || echo "0")
remaining_sa=$(kubectl get clusterrolebindings | grep -E "deployment-job|debug-proxy|flux-cd" | wc -l || echo "0")

if [ "$remaining_ns" -eq 0 ] && [ "$remaining_sa" -eq 0 ]; then
  echo -e "${GREEN}✅ All test resources removed${NC}"
else
  echo -e "${YELLOW}⚠️  Some resources may still be terminating:${NC}"
  echo "  Namespaces: $remaining_ns"
  echo "  ClusterRoleBindings: $remaining_sa"
  echo ""
  echo "Run 'kubectl get all -A | grep test' to check remaining resources"
fi
echo ""

##############################################################################
# Summary
##############################################################################

echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

if [ "$REMOVE_OPERATORS" = false ]; then
  echo -e "${YELLOW}Note: Operators (Trivy, Falco) were not removed${NC}"
  echo "To remove operators, run: $0 --remove-operators"
  echo ""
fi

echo "Cleaned up:"
echo "  ✅ Test workloads"
echo "  ✅ Test ServiceAccounts and RBAC"
echo "  ✅ Test namespaces"

if [ "$REMOVE_OPERATORS" = true ]; then
  echo "  ✅ Trivy Operator"
  echo "  ✅ Falco"
fi

echo ""
echo "To set up the test environment again, run:"
echo "  ./setup-cluster.sh"
echo ""
