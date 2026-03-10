# UC02: Multi-Cluster ApplicationSet

## Overview
Tests ArgoCD ApplicationSet CRD for templated, multi-target application deployment. ApplicationSet generates multiple Application resources from generators (list, git, cluster, etc.).

## ArgoCD ApplicationSet
ApplicationSet is a meta-controller that:
- **Generates** multiple Applications from templates
- **Targets** multiple clusters, namespaces, or environments
- **Automates** application lifecycle across environments
- **Supports** various generators (list, git, cluster, PR, matrix)

## Use Cases
- **Multi-Cluster**: Deploy to dev/staging/prod clusters
- **Multi-Tenant**: Deploy per-tenant applications
- **Monorepo**: Deploy multiple apps from single repo
- **Pull Requests**: Auto-deploy PR environments
- **Progressive Delivery**: Canary across clusters

## Prerequisites
- Kubernetes cluster with ArgoCD installed
- ArgoCD ApplicationSet controller enabled (default in v2.6+)
- Multiple cluster secrets registered in ArgoCD (for multi-cluster)
- Git repository with application templates

## Test Objectives
1. Create ApplicationSet with list generator
2. Verify multiple Applications generated
3. Check each Application synced to target cluster/namespace
4. Test generator updates (add/remove clusters)
5. Validate template parameter substitution
6. Verify Applications auto-pruned when removed from generator

## Generators

### List Generator
```yaml
generators:
  - list:
      elements:
        - cluster: dev
          url: https://dev-cluster
          replicas: "1"
        - cluster: prod
          url: https://prod-cluster
          replicas: "3"
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
```

### Matrix Generator (Combination)
```yaml
generators:
  - matrix:
      generators:
        - git: { ... }
        - cluster: { ... }
```

## Template Parameters
Template uses Go template syntax with generator fields:
- `{{cluster}}` - Cluster name from generator
- `{{url}}` - Cluster URL
- `{{namespace}}` - Target namespace
- `{{replicas}}` - Custom parameter

## ApplicationSet Strategies
- **AllAtOnce**: Apply to all targets simultaneously (default)
- **RollingSync**: Apply progressively with rollback on failure
- **Progressive**: Canary deployment across targets

## References
- [ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Generators](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/)
- [Progressive Sync](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Progressive-Syncs/)
