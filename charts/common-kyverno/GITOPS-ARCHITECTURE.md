# GitOps-Only Architecture Diagram

## High-Level Flow: User Cannot Deploy Directly

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────┐                                                        │
│  │   User   │                                                        │
│  │ (Alice)  │                                                        │
│  └────┬─────┘                                                        │
│       │                                                              │
│       │ (1) kubectl create deployment myapp --image=nginx           │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │ Kyverno         │                                                │
│  │ Admission       │  ❌ BLOCKED                                    │
│  │ Webhook         │  "Direct workload modifications not allowed"   │
│  └─────────────────┘  "Use Helm charts via operators"               │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Correct Flow: GitOps Deployment

```
┌──────────┐                                                              
│   User   │                                                              
│ (Alice)  │                                                              
└────┬─────┘                                                              
     │                                                                     
     │ (1) git commit -m "Deploy myapp v2.0"                              
     │     git push origin main                                           
     ▼                                                                     
┌─────────────────┐                                                       
│  Git Repository │                                                       
│  (GitHub/GitLab)│                                                       
└────┬────────────┘                                                       
     │                                                                     
     │ (2) Webhook notification                                           
     ▼                                                                     
┌─────────────────────────────────────────────────────────────┐          
│                    Kubernetes Cluster                        │          
├─────────────────────────────────────────────────────────────┤          
│                                                              │          
│  ┌─────────────────┐                                        │          
│  │ Flux CD /       │                                        │          
│  │ ArgoCD          │                                        │          
│  │ (Operator)      │                                        │          
│  └────┬────────────┘                                        │          
│       │                                                     │          
│       │ (3) Pull latest from Git                           │          
│       │                                                     │          
│       ▼                                                     │          
│  ┌─────────────────┐                                       │          
│  │ Helm Controller │                                       │          
│  │                 │                                       │          
│  │ ServiceAccount: │                                       │          
│  │   flux / argocd │                                       │          
│  └────┬────────────┘                                       │          
│       │                                                     │          
│       │ (4) helm upgrade --install myapp                   │          
│       │                                                     │          
│       ▼                                                     │          
│  ┌─────────────────┐                                       │          
│  │ Kyverno         │                                       │          
│  │ Webhook         │  ✅ ALLOWED                           │          
│  └────┬────────────┘  (flux SA is excluded)                │          
│       │                                                     │          
│       │ (5) CREATE Deployment                              │          
│       ▼                                                     │          
│  ┌─────────────────┐                                       │          
│  │  Deployment     │  ✅ Created                           │          
│  │  myapp          │                                       │          
│  └─────────────────┘                                       │          
│                                                              │          
└──────────────────────────────────────────────────────────────┘          
```

## Architecture: Defense in Depth

```
┌──────────────────────────────────────────────────────────────┐
│                     Security Layers                           │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Layer 1: Kyverno Admission Control                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ ClusterPolicy: block-workload-modifications            │  │
│  │                                                        │  │
│  │ Rules:                                                 │  │
│  │   - Block: Deployment CREATE/UPDATE/DELETE            │  │
│  │   - Block: StatefulSet CREATE/UPDATE/DELETE           │  │
│  │   - Block: DaemonSet CREATE/UPDATE/DELETE             │  │
│  │                                                        │  │
│  │ Except:                                                │  │
│  │   - ServiceAccount: flux, argocd, helm-operator       │  │
│  │   - ServiceAccount: deployment-job (CI/CD)            │  │
│  │   - User: cluster-admin (break-glass)                 │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Layer 2: RBAC Authorization                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ ClusterRole: flux-controller                           │  │
│  │   - apps/deployments: create, update, delete           │  │
│  │   - apps/statefulsets: create, update, delete          │  │
│  │                                                        │  │
│  │ ClusterRoleBinding:                                    │  │
│  │   ServiceAccount: flux → ClusterRole: flux-controller │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Layer 3: Git Audit Trail                                   │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ All changes recorded in Git:                           │  │
│  │   - Who: Git commit author                             │  │
│  │   - When: Git commit timestamp                         │  │
│  │   - What: Git diff                                     │  │
│  │   - Why: Git commit message                            │  │
│  │   - Review: PR approval history                        │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Component Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                     GitOps Ecosystem                            │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Git Repository (Source of Truth)                        │  │
│  │                                                         │  │
│  │  infrastructure/                                        │  │
│  │    apps/                                                │  │
│  │      myapp/                                             │  │
│  │        Chart.yaml                                       │  │
│  │        values.yaml                                      │  │
│  │        templates/                                       │  │
│  │          deployment.yaml                                │  │
│  │          service.yaml                                   │  │
│  │                                                         │  │
│  │    helmreleases/                                        │  │
│  │      myapp.yaml  ← Flux HelmRelease CR                 │  │
│  └─────────────────────────────────────────────────────────┘  │
│                              │                                 │
│                              │ git pull                        │
│                              ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Flux CD / ArgoCD (Operators)                            │  │
│  │                                                         │  │
│  │  Components:                                            │  │
│  │    - Source Controller (sync Git repo)                 │  │
│  │    - Helm Controller (render & apply charts)           │  │
│  │    - Kustomize Controller (apply manifests)            │  │
│  │                                                         │  │
│  │  ServiceAccount: flux / argocd                          │  │
│  │  Permissions: ClusterRole (deploy resources)            │  │
│  └─────────────────────────────────────────────────────────┘  │
│                              │                                 │
│                              │ helm upgrade --install          │
│                              ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Kyverno Admission Control                               │  │
│  │                                                         │  │
│  │  ✅ Allow: flux/argocd ServiceAccount                   │  │
│  │  ✅ Allow: deployment-job ServiceAccount (CI/CD)        │  │
│  │  ✅ Allow: cluster-admin User (break-glass)             │  │
│  │  ❌ Block: All other users/ServiceAccounts              │  │
│  └─────────────────────────────────────────────────────────┘  │
│                              │                                 │
│                              │ CREATE resources                │
│                              ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Kubernetes Resources                                    │  │
│  │                                                         │  │
│  │  ✅ Deployment: myapp                                   │  │
│  │  ✅ Service: myapp                                      │  │
│  │  ✅ Ingress: myapp                                      │  │
│  │  ✅ ConfigMap: myapp-config                             │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Access Control Matrix

```
┌──────────────────────┬─────────────┬─────────────┬─────────────┐
│ Actor                │ Deployment  │ Service     │ ConfigMap   │
├──────────────────────┼─────────────┼─────────────┼─────────────┤
│ User (direct kubectl)│ ❌ Blocked  │ ❌ Blocked  │ ❌ Blocked  │
│                      │ (Kyverno)   │ (Kyverno)   │ (Kyverno)   │
├──────────────────────┼─────────────┼─────────────┼─────────────┤
│ Flux CD              │ ✅ Allowed  │ ✅ Allowed  │ ✅ Allowed  │
│ (ServiceAccount)     │ (excluded)  │ (excluded)  │ (excluded)  │
├──────────────────────┼─────────────┼─────────────┼─────────────┤
│ ArgoCD               │ ✅ Allowed  │ ✅ Allowed  │ ✅ Allowed  │
│ (ServiceAccount)     │ (excluded)  │ (excluded)  │ (excluded)  │
├──────────────────────┼─────────────┼─────────────┼─────────────┤
│ CI/CD Deployment Job │ ✅ Allowed  │ ✅ Allowed  │ ✅ Allowed  │
│ (ServiceAccount)     │ (excluded)  │ (excluded)  │ (excluded)  │
├──────────────────────┼─────────────┼─────────────┼─────────────┤
│ cluster-admin        │ ✅ Allowed  │ ✅ Allowed  │ ✅ Allowed  │
│ (break-glass)        │ (excluded)  │ (excluded)  │ (excluded)  │
└──────────────────────┴─────────────┴─────────────┴─────────────┘
```

## Sequence Diagram: GitOps Deployment

```
User    Git      Flux       Kyverno    K8s API    Deployment
│       │        │          │          │          │
│──────>│        │          │          │          │
│ push  │        │          │          │          │
│       │        │          │          │          │
│       │───────>│          │          │          │
│       │webhook │          │          │          │
│       │        │          │          │          │
│       │<───────│          │          │          │
│       │ pull   │          │          │          │
│       │        │          │          │          │
│       │        │─────────────────────>│          │
│       │        │  CREATE Deployment  │          │
│       │        │  (as flux SA)       │          │
│       │        │          │          │          │
│       │        │          │<─────────│          │
│       │        │          │ validate │          │
│       │        │          │          │          │
│       │        │          │──────────>│          │
│       │        │          │  ✅ allow │          │
│       │        │          │  (flux SA)│          │
│       │        │          │          │          │
│       │        │<─────────────────────│          │
│       │        │   Deployment created │          │
│       │        │          │          │          │
│       │        │          │          │─────────>│
│       │        │          │          │  create  │
│       │        │          │          │          │
│       │<───────│          │          │          │
│ slack │  notify│          │          │          │
│notification    │          │          │          │
│                │          │          │          │
```

## Deployment Flow Comparison

### ❌ Old Way (Blocked)

```
Developer → kubectl apply → Kubernetes API → ❌ BLOCKED by Kyverno
```

### ✅ New Way (Allowed)

```
Developer → Git Push → Flux/ArgoCD → Kubernetes API → ✅ ALLOWED by Kyverno → Deployed
```

## Benefits Visualization

```
┌────────────────────────────────────────────────────────────────┐
│                        Benefits                                 │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ✅ Compliance                                                  │
│     All changes tracked in Git (audit trail)                   │
│     Who, when, what, why documented                            │
│                                                                 │
│  ✅ Consistency                                                 │
│     No manual modifications                                    │
│     Infrastructure as Code                                     │
│     Reproducible deployments                                   │
│                                                                 │
│  ✅ Security                                                    │
│     Reduced attack surface                                     │
│     Controlled access via ServiceAccounts                      │
│     RBAC + Kyverno = defense in depth                          │
│                                                                 │
│  ✅ Reliability                                                 │
│     Peer review via Pull Requests                              │
│     Automated testing before deploy                            │
│     Rollback via git revert                                    │
│                                                                 │
│  ✅ Disaster Recovery                                           │
│     Git history = full change log                              │
│     Easy to restore to any previous state                      │
│     git revert → automatic rollback                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
