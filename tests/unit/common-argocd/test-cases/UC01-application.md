# UC01: Application Deployment via ArgoCD CRD

## Overview
Tests ArgoCD Application CRD (Custom Resource Definition) for declarative GitOps-based application deployment. An Application resource represents a deployed application instance in a target cluster.

## ArgoCD Application
An Application is ArgoCD's primary CRD that defines:
- **Source**: Git repository, Helm chart, or Kustomize app
- **Destination**: Target cluster and namespace
- **Sync Policy**: Automated vs manual, pruning, self-healing
- **Project**: RBAC and security boundaries

## Use Cases
- **GitOps**: Git as single source of truth
- **Declarative Deployment**: Infrastructure as Code
- **Continuous Deployment**: Auto-sync on Git changes
- **Multi-Environment**: Deploy same app to dev/staging/prod
- **Rollback**: Git revert for instant rollback
- **Drift Detection**: Detect manual cluster changes

## Prerequisites
- Kubernetes cluster (v1.23+)
- ArgoCD installed (v2.8+):
  ```bash
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  ```
- Git repository with application manifests
- ArgoCD CLI (optional, for troubleshooting)

## Test Objectives
1. Create ArgoCD Application resource
2. Verify Application synced successfully
3. Check deployed resources in target namespace
4. Test automated sync (modify Git repo)
5. Verify self-healing (manual kubectl changes reverted)
6. Test prune (remove resources from Git)

## Sync Policies

### Automated Sync
```yaml
syncPolicy:
  automated:
    prune: true       # Delete resources removed from Git
    selfHeal: true    # Revert manual changes
    allowEmpty: false # Prevent empty sync
```

### Manual Sync
```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

### Retry Strategy
```yaml
syncPolicy:
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2       # Exponential backoff
      maxDuration: 3m
```

## Application Health Status
- **Healthy**: All resources deployed and healthy
- **Progressing**: Sync in progress
- **Degraded**: Resources unhealthy (pods crashing)
- **Suspended**: Application suspended
- **Missing**: Resources not found

## References
- [ArgoCD Application CRD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications)
- [Sync Strategies](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
- [Health Assessment](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)
