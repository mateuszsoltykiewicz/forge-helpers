# Test Prerequisites

This directory contains Kubernetes resources required for running tests.

## Installation Order

1. `test-namespaces.yaml` - Create test namespaces
2. `test-serviceaccounts.yaml` - Create test ServiceAccounts with RBAC
3. `test-workloads.yaml` - Deploy basic test applications

## Apply All Prerequisites

```bash
kubectl apply -f test-namespaces.yaml
kubectl apply -f test-serviceaccounts.yaml
kubectl apply -f test-workloads.yaml
```

## Cleanup

```bash
kubectl delete -f test-workloads.yaml
kubectl delete -f test-serviceaccounts.yaml
kubectl delete -f test-namespaces.yaml
```

## Namespaces Created

- `test-app` - Main test application namespace
- `test-blocked` - Namespace where policies are fully enforced
- `test-allowed` - Namespace with policy exclusions
- `ci-cd` - CI/CD ServiceAccounts namespace

## ServiceAccounts Created

- `deployment-job` (ci-cd namespace) - For automated deployments
- `debug-proxy` (kube-system namespace) - For controlled API access
- `flux-cd` (flux-system namespace) - Simulated Flux GitOps
