#!/bin/bash

##############################################################################
# Forge Helpers - Test Environment Setup Script
# 
# This script prepares the Kubernetes cluster for testing by:
# 1. Installing missing operators (Trivy, Falco)
# 2. Creating test namespaces
# 3. Creating test ServiceAccounts with RBAC
# 4. Deploying test workloads
#
# Usage: ./setup-cluster.sh [--skip-operators] [--skip-workloads]
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_OPERATORS=false
SKIP_WORKLOADS=false

for arg in "$@"; do
  case $arg in
    --skip-operators)
      SKIP_OPERATORS=true
      shift
      ;;
    --skip-workloads)
      SKIP_WORKLOADS=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --skip-operators   Skip installation of Trivy and Falco operators"
      echo "  --skip-workloads   Skip deployment of test workloads"
      echo "  --help             Show this help message"
      exit 0
      ;;
  esac
done

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}  Forge Helpers - Test Environment Setup${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Check cluster connectivity
echo -e "${YELLOW}Checking Kubernetes cluster connectivity...${NC}"
if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
  echo "Please ensure kubectl is configured and cluster is accessible"
  exit 1
fi
echo -e "${GREEN}✅ Cluster accessible${NC}"
echo ""

# Check if running in correct directory
if [ ! -f "../prerequisites/test-namespaces.yaml" ]; then
  echo -e "${RED}❌ Error: Script must be run from tests/scripts/ directory${NC}"
  exit 1
fi

##############################################################################
# 1. Install Missing Operators
##############################################################################

if [ "$SKIP_OPERATORS" = false ]; then
  echo -e "${BLUE}=== Step 1: Installing Missing Operators ===${NC}"
  echo ""
  
  # Check if Trivy Operator is installed
  echo -e "${YELLOW}Checking Trivy Operator...${NC}"
  if kubectl get deployment -n trivy-system trivy-operator &> /dev/null; then
    echo -e "${GREEN}✅ Trivy Operator already installed${NC}"
  else
    echo -e "${YELLOW}Installing Trivy Operator...${NC}"
    helm repo add aqua https://aquasecurity.github.io/helm-charts/ || true
    helm repo update
    
    helm install trivy-operator aqua/trivy-operator \
      --namespace trivy-system \
      --create-namespace \
      --set="trivy.ignoreUnfixed=true" \
      --set="trivy.severity=CRITICAL,HIGH" \
      --wait \
      --timeout 5m
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ Trivy Operator installed successfully${NC}"
    else
      echo -e "${RED}❌ Failed to install Trivy Operator${NC}"
      exit 1
    fi
  fi
  echo ""
  
  # Check if Falco is installed
  echo -e "${YELLOW}Checking Falco...${NC}"
  if kubectl get daemonset -n falco falco &> /dev/null; then
    echo -e "${GREEN}✅ Falco already installed${NC}"
  else
    echo -e "${YELLOW}Installing Falco...${NC}"
    helm repo add falcosecurity https://falcosecurity.github.io/charts || true
    helm repo update
    
    helm install falco falcosecurity/falco \
      --namespace falco \
      --create-namespace \
      --set tty=true \
      --set falco.json_output=true \
      --set falco.log_stderr=true \
      --set falco.log_syslog=false \
      --wait \
      --timeout 5m
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ Falco installed successfully${NC}"
    else
      echo -e "${RED}❌ Failed to install Falco${NC}"
      exit 1
    fi
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Skipping operator installation${NC}"
  echo ""
fi

##############################################################################
# 2. Create Test Namespaces
##############################################################################

echo -e "${BLUE}=== Step 2: Creating Test Namespaces ===${NC}"
echo ""

echo -e "${YELLOW}Applying test-namespaces.yaml...${NC}"
kubectl apply -f ../prerequisites/test-namespaces.yaml

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Test namespaces created${NC}"
  kubectl get namespaces | grep -E "test-app|test-blocked|test-allowed|ci-cd|flux-system"
else
  echo -e "${RED}❌ Failed to create test namespaces${NC}"
  exit 1
fi
echo ""

##############################################################################
# 3. Create Test ServiceAccounts
##############################################################################

echo -e "${BLUE}=== Step 3: Creating Test ServiceAccounts ===${NC}"
echo ""

echo -e "${YELLOW}Applying test-serviceaccounts.yaml...${NC}"
kubectl apply -f ../prerequisites/test-serviceaccounts.yaml

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Test ServiceAccounts created${NC}"
  echo ""
  echo "ServiceAccounts:"
  kubectl get sa -n ci-cd deployment-job
  kubectl get sa -n kube-system debug-proxy
  kubectl get sa -n flux-system flux-cd
  kubectl get sa -n test-app test-user
  echo ""
  echo "ClusterRoles:"
  kubectl get clusterrole | grep -E "deployment-job|debug-proxy|flux-cd"
else
  echo -e "${RED}❌ Failed to create test ServiceAccounts${NC}"
  exit 1
fi
echo ""

##############################################################################
# 4. Deploy Test Workloads
##############################################################################

if [ "$SKIP_WORKLOADS" = false ]; then
  echo -e "${BLUE}=== Step 4: Deploying Test Workloads ===${NC}"
  echo ""
  
  echo -e "${YELLOW}Applying test-workloads.yaml...${NC}"
  kubectl apply -f ../prerequisites/test-workloads.yaml
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Test workloads deployed${NC}"
    echo ""
    echo "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=120s \
      deployment/test-nginx -n test-app || true
    kubectl wait --for=condition=available --timeout=120s \
      deployment/slow-app -n test-app || true
    
    echo ""
    echo "Deployed workloads:"
    kubectl get all -n test-app
  else
    echo -e "${RED}❌ Failed to deploy test workloads${NC}"
    exit 1
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Skipping test workload deployment${NC}"
  echo ""
fi

##############################################################################
# 5. Verification
##############################################################################

echo -e "${BLUE}=== Step 5: Verification ===${NC}"
echo ""

echo -e "${YELLOW}Checking CRDs...${NC}"
echo "Kyverno CRDs:"
kubectl get crd | grep kyverno | wc -l | xargs echo "  Count:"
echo "Prometheus CRDs:"
kubectl get crd | grep monitoring.coreos.com | wc -l | xargs echo "  Count:"
echo "KEDA CRDs:"
kubectl get crd | grep keda.sh | wc -l | xargs echo "  Count:"

if [ "$SKIP_OPERATORS" = false ]; then
  echo "Trivy CRDs:"
  kubectl get crd | grep aquasecurity.github.io | wc -l | xargs echo "  Count:" || echo "  Count: 0 (may take a moment to appear)"
fi

echo ""
echo -e "${YELLOW}Checking Operators...${NC}"
echo "Kyverno Controllers:"
kubectl get deploy -n kyverno | grep -c kyverno || echo "  0"
echo "Prometheus Operator:"
kubectl get deploy -n monitoring prometheus-grafana-kube-pr-operator &> /dev/null && echo "  ✅ Running" || echo "  ❌ Not found"
echo "KEDA Operator:"
kubectl get deploy -n keda keda-operator &> /dev/null && echo "  ✅ Running" || echo "  ❌ Not found"

if [ "$SKIP_OPERATORS" = false ]; then
  echo "Trivy Operator:"
  kubectl get deploy -n trivy-system trivy-operator &> /dev/null && echo "  ✅ Running" || echo "  ❌ Not found"
  echo "Falco:"
  kubectl get daemonset -n falco falco &> /dev/null && echo "  ✅ Running" || echo "  ❌ Not found"
fi

echo ""

##############################################################################
# Summary
##############################################################################

echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}✅ Test Environment Setup Complete!${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Run unit tests: cd ../unit/common-kyverno && ./test-cases/run-all.sh"
echo "  2. Run integration tests: cd ../integration && ./run-all.sh"
echo "  3. Cleanup: ./cleanup.sh"
echo ""
echo "Test namespaces created:"
echo "  - test-app (main test applications)"
echo "  - test-blocked (fully enforced policies)"
echo "  - test-allowed (policy exclusions)"
echo "  - ci-cd (deployment ServiceAccounts)"
echo "  - flux-system (GitOps simulation)"
echo ""
echo "ServiceAccounts created:"
echo "  - deployment-job (ci-cd namespace)"
echo "  - debug-proxy (kube-system namespace)"
echo "  - flux-cd (flux-system namespace)"
echo "  - test-user (test-app namespace)"
echo ""

if [ "$SKIP_WORKLOADS" = false ]; then
  echo "Test workloads deployed:"
  echo "  - test-nginx (basic web server)"
  echo "  - crashloop-test (monitoring alerts)"
  echo "  - slow-app (SLO testing)"
  echo "  - cpu-stress (autoscaling)"
  echo "  - vulnerable-app (security scanning)"
  echo "  - secret-leak-test (secret detection)"
  echo ""
fi

echo -e "${YELLOW}Important:${NC} Some resources may take a few minutes to fully initialize"
echo ""
