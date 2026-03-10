# Common-ArgoCD Test Suite

Comprehensive test suite for the `common-argocd` Helm chart, which provides GitOps-based continuous delivery using ArgoCD Application and ApplicationSet resources.

## Overview

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. It follows the GitOps pattern of using Git repositories as the source of truth for defining the desired application state. This test suite validates ArgoCD's core CRDs for application deployment.

## Prerequisites

1. **Kubernetes cluster** (v1.23+)
2. **Helm** (v3.8+)
3. **kubectl** configured for your cluster
4. **ArgoCD** installed (v2.8+):
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
5. **Git repository** with application manifests (test uses ArgoCD examples repo)

## Test Cases

### UC01: Application Deployment via ArgoCD CRD
**File**: `test-cases/UC01-application.md`

Tests the ArgoCD Application CRD for declarative application deployment from Git repositories. Application resources define the source (Git), destination (cluster/namespace), and sync policy.

**Key Features**:
- GitOps-based deployment (Git as source of truth)
- Declarative application definition
- Automated sync on Git changes
- Self-healing (revert manual changes)
- Automated pruning (delete removed resources)
- Retry strategies with exponential backoff
- Health status tracking

**Use Cases**:
- Continuous deployment from Git
- Multi-environment deployments (dev/staging/prod)
- Infrastructure as Code
- Automated rollback via Git revert
- Drift detection (manual vs declared state)

**Run**: `cd test-cases && ./run-uc01.sh`

---

### UC02: Multi-Cluster ApplicationSet
**File**: `test-cases/UC02-applicationset.md`

Tests the ArgoCD ApplicationSet CRD for templated, multi-target application deployment. ApplicationSet generates multiple Application resources from generators (list, git, cluster, etc.).

**Key Features**:
- Template-based Application generation
- Multiple generator types (list, git, cluster, PR, matrix)
- Multi-cluster deployment
- Multi-tenant applications
- Monorepo support
- Progressive delivery strategies
- Automatic Application lifecycle management

**Use Cases**:
- Deploy to multiple clusters (dev/staging/prod)
- Multi-tenant SaaS (per-customer namespaces)
- Monorepo (multiple apps from single repo)
- Pull Request environments (ephemeral deployments)
- Canary across clusters

**Run**: `cd test-cases && ./run-uc02.sh`

**Note**: Multi-cluster features require cluster secrets registered in ArgoCD.

---

## Directory Structure

```
common-argocd/
├── README.md                          # This file
├── run-all.sh                         # Run all test cases
├── test-cases/
│   ├── UC01-application.md           # UC01 documentation
│   ├── UC02-applicationset.md        # UC02 documentation
│   ├── run-uc01.sh                   # UC01 test script
│   └── run-uc02.sh                   # UC02 test script
└── values/
    ├── uc01-application.yaml         # Application configuration
    └── uc02-applicationset.yaml      # ApplicationSet configuration
```

## Quick Start

### Run All Tests
```bash
./run-all.sh
```

### Run Individual Tests
```bash
cd test-cases
./run-uc01.sh  # Application
./run-uc02.sh  # ApplicationSet
```

### Install ArgoCD
```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Access ArgoCD UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## ArgoCD Application

### Basic Application Example
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/org/repo.git
    targetRevision: main
    path: k8s/manifests
  
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Sync Policies

**Automated Sync**:
```yaml
syncPolicy:
  automated:
    prune: true       # Delete resources removed from Git
    selfHeal: true    # Revert manual kubectl changes
    allowEmpty: false # Prevent accidental deletion
  syncOptions:
    - CreateNamespace=true
    - PruneLast=true
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

**Manual Sync**:
```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

### Helm Source
```yaml
source:
  repoURL: https://charts.example.com
  chart: myapp
  targetRevision: 1.2.3
  helm:
    parameters:
      - name: replicaCount
        value: "3"
    values: |
      image:
        tag: v2.0.0
```

## ArgoCD ApplicationSet

### List Generator
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-env
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: dev
            url: https://dev-cluster
            replicas: "1"
          - cluster: prod
            url: https://prod-cluster
            replicas: "5"
  
  template:
    metadata:
      name: "myapp-{{cluster}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/org/myapp.git
        targetRevision: HEAD
        path: k8s
      destination:
        server: "{{url}}"
        namespace: "myapp-{{cluster}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Git Generator (Directories)
```yaml
generators:
  - git:
      repoURL: https://github.com/org/apps.git
      revision: HEAD
      directories:
        - path: apps/*
```

### Cluster Generator
```yaml
generators:
  - cluster:
      selector:
        matchLabels:
          environment: production
      values:
        replicas: "3"
```

### Matrix Generator (Combination)
```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: https://github.com/org/apps.git
            directories:
              - path: apps/*
        - cluster:
            selector:
              matchLabels:
                environment: production
```

## Multi-Cluster Setup

### Register External Cluster
```bash
# Get cluster context name
kubectl config get-contexts

# Add cluster to ArgoCD
argocd cluster add <context-name>

# Verify
argocd cluster list
```

### Create Cluster Secret Manually
```bash
kubectl create secret generic staging-cluster \
  -n argocd \
  --from-literal=name=staging \
  --from-literal=server=https://staging.k8s.example.com \
  --from-literal=config='{"bearerToken":"<token>","tlsClientConfig":{"insecure":false}}'
```

## ArgoCD CLI

### Install ArgoCD CLI
```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### Login to ArgoCD
```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login
argocd login localhost:8080
```

### Common CLI Commands
```bash
# List applications
argocd app list

# Get application details
argocd app get myapp

# Sync application
argocd app sync myapp

# Sync and wait
argocd app sync myapp --async=false

# Get sync status
argocd app wait myapp

# Diff with Git
argocd app diff myapp

# Rollback
argocd app history myapp
argocd app rollback myapp <revision>

# Delete application
argocd app delete myapp
```

## Troubleshooting

### Application Not Syncing
```bash
# Check Application status
kubectl describe application <app-name> -n argocd

# Check ArgoCD application controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check sync status
argocd app get <app-name>

# View sync details
kubectl get application <app-name> -n argocd -o yaml
```

### Authentication Errors (Private Repos)
```bash
# Add Git credentials
argocd repo add https://github.com/org/repo.git --username <user> --password <token>

# Using SSH
argocd repo add git@github.com:org/repo.git --ssh-private-key-path ~/.ssh/id_rsa

# Verify
argocd repo list
```

### ApplicationSet Not Generating Applications
```bash
# Check ApplicationSet status
kubectl describe applicationset <appset-name> -n argocd

# Check ApplicationSet controller logs
kubectl logs -n argocd deployment/argocd-applicationset-controller

# Verify generators
kubectl get applicationset <appset-name> -n argocd -o yaml
```

### Health Check Failing
```bash
# Check resource health
argocd app get <app-name> --show-params

# View resource details
kubectl get <resource> -n <namespace>
kubectl describe <resource> -n <namespace>

# Custom health check (if needed)
# Define in argocd-cm ConfigMap
```

## Best Practices

### Application Management
1. **Use Projects**: Organize apps with ArgoCD Projects for RBAC
2. **Automated Sync**: Enable for dev/staging, consider manual for production
3. **Self-Healing**: Use cautiously (can revert emergency patches)
4. **Prune**: Enable to keep cluster clean
5. **Sync Waves**: Use annotations for ordered resource creation
6. **Resource Hooks**: Pre/post-sync hooks for migrations, notifications

### ApplicationSet
1. **Generator Selection**: Choose appropriate generator for use case
2. **Template Testing**: Test templates before production
3. **Progressive Sync**: Use for production rollouts
4. **Labeling**: Add labels for organization and filtering
5. **Matrix Generator**: Combine generators for complex scenarios

### Git Repository Structure
```
repo/
├── base/                    # Base manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/                # Dev environment
│   │   └── kustomization.yaml
│   ├── staging/            # Staging environment
│   │   └── kustomization.yaml
│   └── prod/               # Production environment
│       └── kustomization.yaml
└── argocd/
    └── applications/       # ArgoCD Application definitions
        ├── app-dev.yaml
        ├── app-staging.yaml
        └── app-prod.yaml
```

## Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Application CRD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications)
- [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Sync Strategies](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
- [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

## Support

For issues or questions:
1. Check Application/ApplicationSet status with `kubectl describe`
2. Review ArgoCD controller logs
3. Verify Git repository access and credentials
4. Consult [ArgoCD troubleshooting guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/)
