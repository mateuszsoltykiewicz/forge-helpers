# Forge Common Library - ArgoCD

Library chart for ArgoCD GitOps resources.

## Overview

This Helm library provides reusable templates for **ArgoCD Application** and **ApplicationSet** resources, enabling declarative GitOps workflows for Kubernetes deployments.

**Features**:
- **Application**: Single app deployment from Git repository
- **ApplicationSet**: Multi-environment/cluster patterns with generators
- **Sync Policies**: Automated sync, self-heal, prune resources
- **Sync Waves & Hooks**: Resource ordering and lifecycle management
- **Helm Integration**: Parameter overrides, values files
- **Ignore Differences**: Handle dynamic fields (replicas, timestamps)
- **Multiple Generators**: List, Git, Cluster, Matrix, Pull Request, SCM Provider
- **Progressive Rollout**: Staged deployment strategies

**Integrations**:
- **common-forge**: Naming conventions, labels
- **common-kubernetes**: Destination namespaces
- **Multi-cluster**: Supports any cluster registered with ArgoCD

## Installation

Add as a dependency in your `Chart.yaml`:

```yaml
dependencies:
  - name: common-argocd
    version: ~0.1.0
    repository: file://../common-argocd
```

## Usage Examples

### Example 1: Simple Application

Deploy a single application from Git repository with automated sync:

```yaml
# values.yaml
argocd:
  application:
    enabled: true
    name: "my-application"
    
    source:
      repoURL: "https://github.com/myorg/myrepo"
      targetRevision: "main"
      path: "charts/my-app"
    
    destination:
      server: "https://kubernetes.default.svc"
      namespace: "my-app"
    
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
```

In your templates:

```yaml
# templates/argocd.yaml
{{- include "argocd.application" . }}
```

### Example 2: Application with Helm Parameters

Override Helm values in the Application:

```yaml
# values.yaml
argocd:
  application:
    enabled: true
    name: "my-app"
    
    source:
      repoURL: "https://github.com/myorg/myrepo"
      targetRevision: "v1.2.3"
      path: "charts/my-app"
      
      helm:
        releaseName: "my-app"
        parameters:
          - name: "image.tag"
            value: "v1.2.3"
          - name: "replicas"
            value: "3"
          - name: "ingress.enabled"
            value: "true"
        
        values: |
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

### Example 3: Multi-Environment with List Generator

Deploy to dev, staging, and production environments:

```yaml
# values.yaml
argocd:
  applicationset:
    enabled: true
    name: "my-app-environments"
    
    generators:
      list:
        elements:
          - env: dev
            cluster: https://dev-cluster.example.com
            namespace: my-app-dev
            replicas: "1"
          - env: staging
            cluster: https://staging-cluster.example.com
            namespace: my-app-staging
            replicas: "2"
          - env: prod
            cluster: https://prod-cluster.example.com
            namespace: my-app-prod
            replicas: "3"
    
    template:
      metadata:
        name: "my-app-{{env}}"
      
      spec:
        project: "default"
        
        source:
          repoURL: "https://github.com/myorg/myrepo"
          targetRevision: "main"
          path: "charts/my-app"
          
          helm:
            parameters:
              - name: "replicas"
                value: "{{replicas}}"
              - name: "environment"
                value: "{{env}}"
        
        destination:
          server: "{{cluster}}"
          namespace: "{{namespace}}"
        
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
```

In your templates:

```yaml
# templates/argocd.yaml
{{- include "argocd.applicationset" . }}
```

### Example 4: Git Directory Generator

Automatically discover applications from Git directory structure:

```yaml
# values.yaml
argocd:
  applicationset:
    enabled: true
    name: "git-directory-apps"
    
    generators:
      git:
        repoURL: "https://github.com/myorg/apps"
        revision: "main"
        
        directories:
          - path: "apps/*"
            exclude: false
          - path: "apps/deprecated/*"
            exclude: true
    
    template:
      metadata:
        name: "{{path.basename}}"
      
      spec:
        project: "default"
        
        source:
          repoURL: "https://github.com/myorg/apps"
          targetRevision: "main"
          path: "{{path}}"
        
        destination:
          server: "https://kubernetes.default.svc"
          namespace: "{{path.basename}}"
        
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
```

**Git Repository Structure**:
```
apps/
  ├── frontend/
  │   └── Chart.yaml
  ├── backend/
  │   └── Chart.yaml
  ├── database/
  │   └── Chart.yaml
  └── deprecated/
      └── old-app/
```

This will automatically create Applications for `frontend`, `backend`, and `database` (excluding `deprecated`).

### Example 5: Cluster Generator

Deploy to all production clusters:

```yaml
# values.yaml
argocd:
  applicationset:
    enabled: true
    name: "multi-cluster-app"
    
    generators:
      cluster:
        selector:
          matchLabels:
            environment: production
        
        values:
          app: my-app
    
    template:
      metadata:
        name: "my-app-{{name}}"
      
      spec:
        project: "default"
        
        source:
          repoURL: "https://github.com/myorg/myrepo"
          targetRevision: "main"
          path: "charts/my-app"
        
        destination:
          server: "{{server}}"
          namespace: "my-app"
        
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
```

### Example 6: Matrix Generator (Environment × App)

Deploy multiple apps to multiple environments:

```yaml
# values.yaml
argocd:
  applicationset:
    enabled: true
    name: "matrix-apps"
    
    generators:
      matrix:
        generators:
          # List of environments
          - list:
              elements:
                - env: dev
                  cluster: https://dev-cluster.example.com
                - env: prod
                  cluster: https://prod-cluster.example.com
          
          # List of applications
          - list:
              elements:
                - app: frontend
                  port: "3000"
                - app: backend
                  port: "8080"
                - app: database
                  port: "5432"
    
    template:
      metadata:
        name: "{{app}}-{{env}}"
      
      spec:
        project: "default"
        
        source:
          repoURL: "https://github.com/myorg/apps"
          targetRevision: "main"
          path: "charts/{{app}}"
          
          helm:
            parameters:
              - name: "service.port"
                value: "{{port}}"
        
        destination:
          server: "{{cluster}}"
          namespace: "{{app}}-{{env}}"
        
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
```

This creates 6 Applications: `frontend-dev`, `frontend-prod`, `backend-dev`, `backend-prod`, `database-dev`, `database-prod`.

### Example 7: Ignore Differences

Handle dynamic fields that change at runtime:

```yaml
# values.yaml
argocd:
  application:
    enabled: true
    name: "my-app"
    
    source:
      repoURL: "https://github.com/myorg/myrepo"
      targetRevision: "main"
      path: "charts/my-app"
    
    destination:
      server: "https://kubernetes.default.svc"
      namespace: "my-app"
    
    ignoreDifferences:
      # Ignore replicas (managed by HPA)
      - group: apps
        kind: Deployment
        jsonPointers:
          - /spec/replicas
      
      # Ignore timestamps
      - group: ""
        kind: ConfigMap
        jqPathExpressions:
          - .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"
      
      # Ignore specific Secret
      - group: ""
        kind: Secret
        name: auto-generated-secret
        jsonPointers:
          - /data
```

### Example 8: Sync Waves and Hooks

Order resource creation with sync waves:

```yaml
# templates/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  annotations:
    {{- include "argocd.syncWave" -5 | nindent 4 }}

---
# templates/database.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database
  annotations:
    {{- include "argocd.syncWave" 0 | nindent 4 }}

---
# templates/backend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  annotations:
    {{- include "argocd.syncWave" 1 | nindent 4 }}

---
# templates/frontend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  annotations:
    {{- include "argocd.syncWave" 2 | nindent 4 }}
```

**Sync Hooks** (for jobs that run during sync):

```yaml
# templates/db-migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    {{- include "argocd.syncHook" "PreSync" | nindent 4 }}
    {{- include "argocd.hookDeletePolicy" "HookSucceeded" | nindent 4 }}
```

### Example 9: Progressive Rollout Strategy

Deploy to environments in stages:

```yaml
# values.yaml
argocd:
  applicationset:
    enabled: true
    name: "progressive-rollout"
    
    generators:
      list:
        elements:
          - env: dev
            cluster: https://dev-cluster.example.com
          - env: staging1
            cluster: https://staging1-cluster.example.com
          - env: staging2
            cluster: https://staging2-cluster.example.com
          - env: prod1
            cluster: https://prod1-cluster.example.com
          - env: prod2
            cluster: https://prod2-cluster.example.com
    
    template:
      metadata:
        name: "my-app-{{env}}"
      
      spec:
        source:
          repoURL: "https://github.com/myorg/myrepo"
          targetRevision: "main"
          path: "charts/my-app"
        
        destination:
          server: "{{cluster}}"
          namespace: "my-app"
    
    # Progressive rollout strategy
    strategy:
      type: RollingSync
      rollingSync:
        steps:
          # Step 1: Deploy to dev first
          - matchExpressions:
              - key: env
                operator: In
                values: [dev]
          
          # Step 2: Deploy to both staging clusters (max 2 at once)
          - matchExpressions:
              - key: env
                operator: In
                values: [staging1, staging2]
            maxUpdate: 2
          
          # Step 3: Deploy to prod clusters one at a time
          - matchExpressions:
              - key: env
                operator: In
                values: [prod1, prod2]
            maxUpdate: 1
```

### Example 10: Complete Production Setup

Production-ready configuration with all features:

```yaml
# values.yaml
argocd:
  application:
    enabled: true
    name: "production-app"
    namespace: "argocd"
    project: "production"
    
    source:
      repoURL: "https://github.com/myorg/production-apps"
      targetRevision: "release-v1.5"
      path: "charts/my-app"
      
      helm:
        releaseName: "my-app"
        
        parameters:
          - name: "image.tag"
            value: "v1.5.0"
          - name: "replicas"
            value: "3"
          - name: "resources.limits.cpu"
            value: "1000m"
          - name: "resources.limits.memory"
            value: "1Gi"
        
        values: |
          ingress:
            enabled: true
            className: "alb"
            hosts:
              - host: app.example.com
                paths:
                  - path: /
                    pathType: Prefix
          
          autoscaling:
            enabled: true
            minReplicas: 3
            maxReplicas: 10
    
    destination:
      server: "https://prod-cluster.example.com"
      namespace: "my-app-prod"
    
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
        allowEmpty: false
      
      syncOptions:
        - CreateNamespace=true
        - PrunePropagationPolicy=foreground
        - PruneLast=true
        - RespectIgnoreDifferences=true
        - ApplyOutOfSyncOnly=true
      
      retry:
        limit: 5
        backoff:
          duration: "5s"
          factor: 2
          maxDuration: "3m"
      
      managedNamespaceMetadata:
        labels:
          environment: "production"
          team: "platform"
        annotations:
          moai.forge.io/owner: "platform-team"
    
    ignoreDifferences:
      - group: apps
        kind: Deployment
        jsonPointers:
          - /spec/replicas
      - group: autoscaling
        kind: HorizontalPodAutoscaler
        jsonPointers:
          - /status
    
    info:
      - name: "url"
        value: "https://app.example.com"
      - name: "docs"
        value: "https://docs.example.com"
    
    revisionHistoryLimit: 10
    
    finalizers:
      - resources-finalizer.argocd.argoproj.io
    
    labels:
      environment: "production"
      team: "platform"
    
    annotations:
      notifications.argoproj.io/subscribe.on-sync-succeeded.slack: "platform-team"
      notifications.argoproj.io/subscribe.on-sync-failed.slack: "platform-team"
```

## Templates Reference

### Application Template

**Template**: `argocd.application`

**Usage**:
```yaml
{{- include "argocd.application" . }}
```

**Configuration**:
- `.Values.argocd.application.enabled` - Enable Application resource
- `.Values.argocd.application.source` - Git source configuration
- `.Values.argocd.application.destination` - Target cluster and namespace
- `.Values.argocd.application.syncPolicy` - Automated sync settings

### ApplicationSet Template

**Template**: `argocd.applicationset`

**Usage**:
```yaml
{{- include "argocd.applicationset" . }}
```

**Configuration**:
- `.Values.argocd.applicationset.enabled` - Enable ApplicationSet resource
- `.Values.argocd.applicationset.generators` - Generator configuration
- `.Values.argocd.applicationset.template` - Application template
- `.Values.argocd.applicationset.strategy` - Rollout strategy

### Helper Templates

**Sync Wave**:
```yaml
annotations:
  {{- include "argocd.syncWave" 5 | nindent 4 }}
```

**Sync Hook**:
```yaml
annotations:
  {{- include "argocd.syncHook" "PreSync" | nindent 4 }}
```

**Hook Delete Policy**:
```yaml
annotations:
  {{- include "argocd.hookDeletePolicy" "HookSucceeded" | nindent 4 }}
```

## Configuration

See [values.yaml](values.yaml) for full configuration options.

## Generator Types

### List Generator
Explicit list of environments/clusters. Best for:
- Small number of environments
- Custom per-environment configuration
- Full control over parameters

### Git Generator
Discover from Git repository structure. Best for:
- Monorepo with multiple apps
- Dynamic app discovery
- Directory-based organization

### Cluster Generator
Discover from registered Kubernetes clusters. Best for:
- Multi-cluster deployments
- Cluster label-based selection
- Dynamic cluster discovery

### Matrix Generator
Combine multiple generators (Cartesian product). Best for:
- Multiple apps × multiple environments
- Complex deployment patterns
- Reusable generator combinations

### Merge Generator
Merge parameters from multiple generators. Best for:
- Layered configuration
- Override patterns
- Default + custom values

### Pull Request Generator
Create Applications for pull requests. Best for:
- Preview environments
- PR-based testing
- Temporary deployments

### SCM Provider Generator
Discover repositories from GitHub/GitLab/etc. Best for:
- Organization-wide deployments
- Multi-repository patterns
- Automatic new repo discovery

## Best Practices

### Sync Policies

**Development**:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

**Production**:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: false  # Manual intervention for drift
  retry:
    limit: 5
```

### Sync Options

**Recommended**:
- `CreateNamespace=true` - Auto-create target namespace
- `PrunePropagationPolicy=foreground` - Clean deletion
- `RespectIgnoreDifferences=true` - Honor ignoreDifferences

**Use with Caution**:
- `PruneLast=true` - Delete resources after new ones are healthy
- `Replace=true` - Use replace instead of patch

### Ignore Differences

Always ignore:
- HPA-managed replicas: `/spec/replicas`
- Auto-generated fields: `/status`, `/metadata/generation`
- Timestamps and checksums

### Resource Ordering

Use sync waves:
- `-5 to -1`: Infrastructure (namespaces, CRDs)
- `0`: Core resources (PVCs, Secrets, ConfigMaps)
- `1-5`: Applications (Deployments, StatefulSets)
- `6-10`: Post-deployment (Jobs, Tests)

## Requirements

- **Helm**: 3.0+
- **ArgoCD**: 2.8+ (tested with 2.10.0)
- **Kubernetes**: 1.23-1.29

## License

Part of the Moai Forge platform.
