# Forge Common Library - common-kubernetes

Comprehensive Kubernetes resource templates library with full Vault Agent Injector integration, security contexts, health probes, autoscaling, and monitoring support.

## Overview

`common-kubernetes` provides production-ready Helm templates for all major Kubernetes resource types, following best practices from the Forge platform's video-calling-service reference implementation. This library integrates seamlessly with `common-forge` (naming, validation, labels) and `common-vault` (secret management).

### Key Features

- **Workload Resources**: Deployment, StatefulSet, DaemonSet, Job, CronJob
- **Service & Networking**: Service (ClusterIP/NodePort/LoadBalancer), Ingress, NetworkPolicy
- **Config & Storage**: ConfigMap, Secret, PVC, ServiceAccount, RBAC
- **Autoscaling**: HPA (v2), VPA, PodDisruptionBudget
- **Monitoring**: PodMonitor, ServiceMonitor (Prometheus Operator)
- **Vault Integration**: Full Agent Injector support with sections pattern
- **Security**: Pod Security contexts (baseline/restricted), health probes, resource limits
- **Cloud Support**: AWS IRSA, Azure Workload Identity, GCP Workload Identity annotations

## Installation

### As Dependency

Add to your `Chart.yaml`:

```yaml
dependencies:
  - name: common-kubernetes
    version: ~0.1.0
    repository: file://../common-kubernetes
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
  - name: common-vault
    version: ~0.1.0
    repository: file://../common-vault
```

Then run:

```bash
helm dependency update
```

## Usage

### Basic Deployment

```yaml
# values.yaml
deployment:
  enabled: true
  replicas: 3
  
  ports:
    - name: http
      containerPort: 8080
  
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  livenessProbe:
    httpGet:
      path: /health
      port: http
    initialDelaySeconds: 30
  
  readinessProbe:
    httpGet:
      path: /ready
      port: http
    initialDelaySeconds: 5

service:
  enabled: true
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 8080

image:
  registry: docker.io
  repository: myapp
  tag: "1.0.0"
```

```helm
{{/* templates/deployment.yaml */}}
{{- include "k8s.deployment" . }}
{{- include "k8s.service" . }}
```

### Deployment with Vault Secrets

```yaml
# values.yaml
deployment:
  enabled: true
  
  # Use Vault sections for secret sourcing
  command: ["/bin/sh", "-c"]
  args:
    - |
      {{- include "vault.sections.source" . | nindent 6 }}
      {{- include "vault.verification.check" . | nindent 6 }}
      exec /app/start.sh
  
  env:
    - name: PORT
      value: "8080"

vault:
  enabled: true
  agent:
    role: myapp-prod
  
  sections:
    - app: "secret/data/customer/project/myapp/config"
    - database: "secret/data/customer/project/myapp/database"
  
  verification:
    enabled: true
    mode: verbose
    required:
      - APP_NAME
      - DATABASE_URL
      - API_KEY
    optional:
      - DEBUG_MODE
```

### StatefulSet with Persistent Storage

```yaml
statefulset:
  enabled: true
  serviceName: myapp-headless
  replicas: 3
  
  volumeClaimTemplates:
    - name: data
      accessModes:
        - ReadWriteOnce
      storageClassName: gp3
      size: 10Gi
  
  volumeMounts:
    - name: data
      mountPath: /var/lib/myapp

service:
  headless:
    enabled: true
    publishNotReadyAddresses: true
    ports:
      - name: peer
        port: 2380
```

### CronJob with Vault Pre-Populate

```yaml
cronjob:
  enabled: true
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  ttlSecondsAfterFinished: 86400
  
  command: ["/bin/sh", "-c"]
  args:
    - |
      source /vault/secrets/app
      /app/backup.sh

vault:
  enabled: true
  agent:
    prePopulateOnly: true  # No sidecar for jobs
  sections:
    - app: "secret/data/customer/project/myapp/backup"
```

### Autoscaling Configuration

```yaml
deployment:
  enabled: true
  # Don't set replicas when using HPA

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
  
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60

pdb:
  enabled: true
  minAvailable: 1
```

### Ingress with TLS

```yaml
ingress:
  enabled: true
  ingressClassName: nginx
  
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
  
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  
  rules:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: 80
```

### NetworkPolicy

```yaml
networkPolicy:
  enabled: true
  
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: production
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
  
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443  # Allow HTTPS egress
    - to:
        - podSelector:
            matchLabels:
              app: database
      ports:
        - protocol: TCP
          port: 5432
```

### RBAC Configuration

```yaml
rbac:
  create: true
  
  roles:
    - name: myapp-reader
      rules:
        - apiGroups: [""]
          resources: ["configmaps", "secrets"]
          verbs: ["get", "list"]
  
  roleBindings:
    - name: myapp-reader-binding
      roleName: myapp-reader
      subjects:
        - kind: ServiceAccount
          name: myapp
```

### Monitoring with Prometheus

```yaml
deployment:
  ports:
    - name: http
      containerPort: 8080
    - name: metrics
      containerPort: 9090

service:
  ports:
    - name: http
      port: 80
      targetPort: 8080
    - name: metrics
      port: 9090
      targetPort: 9090

podMonitor:
  enabled: true
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

## Templates Reference

### Workload Templates

#### `k8s.deployment`

Comprehensive Deployment template with:
- Rolling/Recreate update strategies
- Init containers (built-in PostgreSQL wait + custom)
- Health probes (startup, liveness, readiness)
- Lifecycle hooks
- Sidecars support
- Full Vault integration
- Security contexts
- Resource management
- Node scheduling (affinity, tolerations, topology spread)
- Host networking, DNS configuration
- Process namespace sharing

#### `k8s.statefulset`

StatefulSet template with:
- Ordered/Parallel pod management
- Volume claim templates
- Headless service support
- All Deployment features

#### `k8s.daemonset`

DaemonSet template with:
- Rolling update strategy
- Host networking, PID, IPC support
- Node-level services

#### `k8s.job`

Batch Job template with:
- Completions, parallelism, backoff
- TTL cleanup
- Vault pre-populate only

#### `k8s.cronjob`

Scheduled Job template with:
- Cron schedule, timezone
- Concurrency policy
- History limits

### Service & Networking Templates

#### `k8s.service`

Service template supporting:
- ClusterIP, NodePort, LoadBalancer, ExternalName
- Session affinity
- Load balancer configuration
- External IPs

#### `k8s.service.headless`

Headless service for StatefulSets.

#### `k8s.ingress`

Ingress template with:
- Multiple hosts, paths
- TLS configuration
- Path types (Exact, Prefix, ImplementationSpecific)

#### `k8s.networkpolicy`

NetworkPolicy for pod-level segmentation.

### Config & Storage Templates

#### `k8s.configmap`

ConfigMap with immutability support.

#### `k8s.secret`

Secret template (for non-Vault secrets).

#### `k8s.pvc`

PersistentVolumeClaim with:
- Access modes, storage class
- Volume mode (Filesystem/Block)
- Data sources

#### `k8s.serviceaccount`

ServiceAccount with:
- Image pull secrets
- AWS IRSA annotations
- Azure/GCP Workload Identity

#### RBAC Templates

- `k8s.role`
- `k8s.rolebinding`
- `k8s.clusterrole`
- `k8s.clusterrolebinding`

### Autoscaling Templates

#### `k8s.hpa`

HorizontalPodAutoscaler (v2) with:
- CPU, memory metrics
- Custom metrics support
- Scaling behavior configuration

#### `k8s.vpa`

VerticalPodAutoscaler with:
- Update policy (Auto, Recreate, Initial, Off)
- Resource policy

#### `k8s.pdb`

PodDisruptionBudget with:
- minAvailable, maxUnavailable
- Unhealthy pod eviction policy

### Monitoring Templates

#### `k8s.podmonitor`

Prometheus PodMonitor CRD.

#### `k8s.servicemonitor`

Prometheus ServiceMonitor CRD.

### Helper Functions

#### `k8s.image`

Generate full image path:

```helm
{{- include "k8s.image" . }}
{{/* Output: registry/repository:tag or registry/repository@digest */}}
```

#### `k8s.initContainer.waitForDatabase`

Built-in PostgreSQL readiness check:

```yaml
deployment:
  waitForDatabase:
    enabled: true
    timeout: 60
```

## Security Best Practices

### Pod Security Contexts

```yaml
deployment:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
```

### Resource Limits

Always set resource limits:

```yaml
deployment:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### Health Probes

Configure all three probe types:

```yaml
deployment:
  startupProbe:
    httpGet:
      path: /health
      port: http
    failureThreshold: 30
    periodSeconds: 10
  
  livenessProbe:
    httpGet:
      path: /health
      port: http
    periodSeconds: 10
  
  readinessProbe:
    httpGet:
      path: /ready
      port: http
    periodSeconds: 5
```

## Integration with Other Libraries

### common-forge Integration

Automatic naming and labels:

```helm
{{/* Uses forge.resourceName, forge.labels, forge.selectorLabels */}}
metadata:
  name: {{ include "forge.resourceName" (dict "context" . "type" "deployment") }}
  labels:
    {{- include "forge.labels" . | nindent 4 }}
```

### common-vault Integration

Full Vault Agent Injector support:

```yaml
vault:
  enabled: true
  sections:
    - app: "secret/data/path"
  verification:
    enabled: true
```

## Development

### Testing Templates

```bash
# Render templates
helm template test . -f test-values.yaml

# Validate schema
helm lint .

# Dry-run install
helm install test . --dry-run --debug
```

### Adding New Resources

1. Create template file in `templates/_resource.tpl`
2. Add values schema in `values.yaml`
3. Update JSON schema in `values.schema.json`
4. Document in this README
5. Add usage examples

## License

Copyright © 2024 MOAI Forge Platform. All rights reserved.

## Version

- **Chart Version**: 0.1.0
- **App Version**: 1.29.0 (Kubernetes API)

## Dependencies

- `common-forge` ~0.1.0 (naming, validation, labels)
- `common-vault` ~0.1.0 (Vault integration)
