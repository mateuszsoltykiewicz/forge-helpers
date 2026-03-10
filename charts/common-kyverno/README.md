# Common Kyverno - Policy Governance Library

**Forge Common Library** for Kyverno policy governance.

This library provides reusable Helm templates for Kubernetes policy management:
- **ClusterPolicy** - cluster-wide policy enforcement
- **Policy** - namespace-scoped policy enforcement
- **Pre-configured security policies** - Pod Security Standards (PSS Baseline/Restricted)
- **Best practice policies** - required labels, resource limits, image tags
- **Mutation policies** - auto-inject annotations, set defaults
- **Generation policies** - auto-create NetworkPolicies, RBAC

---

## 🚀 Features

- **Security Policies** - enforce Pod Security Standards (no privileged containers, non-root users)
- **Best Practices** - require resource limits, proper labels, versioned images
- **Compliance** - regulatory requirements, audit logging
- **Mutation** - auto-inject monitoring annotations, set defaults
- **Generation** - auto-create NetworkPolicies for new namespaces
- **Environment-Specific** - different policies for dev/staging/production

---

## 📦 Installation

Add as a dependency to your Helm chart:

```yaml
# Chart.yaml
dependencies:
  - name: common-kyverno
    version: ~0.1.0
    repository: file://../common-kyverno
  - name: common-forge
    version: ~0.1.0
    repository: file://../common-forge
```

Update dependencies:
```bash
helm dependency update
```

---

## 📖 Usage

### Pre-configured Security Policies

Enable built-in security policies:

```yaml
# values.yaml
kyverno:
  policies:
    # Require non-root containers (PSS Restricted)
    requireNonRoot:
      enabled: true
      action: audit  # or enforce
    
    # Disallow privileged containers (PSS Baseline)
    disallowPrivileged:
      enabled: true
      action: enforce
    
    # Require resource limits (Best Practice)
    requireResourceLimits:
      enabled: true
      action: audit
    
    # Require read-only root filesystem (PSS Restricted)
    requireReadOnlyRoot:
      enabled: true
      action: audit
    
    # Disallow :latest image tag (Best Practice)
    disallowLatestTag:
      enabled: true
      action: audit
    
    # Require Forge labels (Forge Best Practice)
    requireForgeLabels:
      enabled: true
      action: audit

# templates/policies.yaml
{{- include "kyverno.clusterpolicy.requireNonRoot" . }}
{{- include "kyverno.clusterpolicy.disallowPrivileged" . }}
{{- include "kyverno.clusterpolicy.requireResourceLimits" . }}
{{- include "kyverno.clusterpolicy.requireReadOnlyRoot" . }}
{{- include "kyverno.clusterpolicy.disallowLatestTag" . }}
{{- include "kyverno.clusterpolicy.requireForgeLabels" . }}
```

### Custom ClusterPolicy

Create custom cluster-wide policies:

```yaml
kyverno:
  clusterpolicy:
    enabled: true
    name: custom-security
    title: "Custom Security Policy"
    category: "Security"
    severity: "high"
    validationFailureAction: enforce
    rules:
      - name: require-team-label
        match:
          any:
            - resources:
                kinds:
                  - Deployment
                  - StatefulSet
        validate:
          message: "All workloads must have a 'team' label"
          pattern:
            metadata:
              labels:
                team: "?*"
      
      - name: disallow-host-network
        match:
          any:
            - resources:
                kinds:
                  - Pod
        validate:
          message: "Host network is not allowed"
          pattern:
            spec:
              =(hostNetwork): false

# templates/clusterpolicy.yaml
{{- include "kyverno.clusterpolicy" . }}
```

### Namespace-Scoped Policy

Create policies for specific namespaces:

```yaml
kyverno:
  policy:
    enabled: true
    name: production-policy
    title: "Production Environment Policy"
    category: "Environment"
    severity: "high"
    validationFailureAction: enforce
    rules:
      - name: require-high-availability
        match:
          any:
            - resources:
                kinds:
                  - Deployment
        validate:
          message: "Production Deployments must have at least 2 replicas"
          pattern:
            spec:
              replicas: ">=2"
      
      - name: require-health-checks
        match:
          any:
            - resources:
                kinds:
                  - Pod
        validate:
          message: "Containers must have liveness and readiness probes"
          pattern:
            spec:
              containers:
                - livenessProbe: {}
                  readinessProbe: {}

# templates/policy.yaml
{{- include "kyverno.policy" . }}
```

### Environment-Specific Policies

Use pre-configured environment policies:

**Development (Relaxed):**
```yaml
kyverno:
  environments:
    development:
      enabled: true

# templates/policies.yaml
{{- include "kyverno.policy.development" . }}
```

**Production (Strict):**
```yaml
kyverno:
  environments:
    production:
      enabled: true

# templates/policies.yaml
{{- include "kyverno.policy.production" . }}
```

### Mutation Policy - Auto-Add Annotations

Automatically inject Prometheus monitoring annotations:

```yaml
kyverno:
  mutations:
    addMonitoringAnnotations:
      enabled: true

# templates/mutations.yaml
{{- include "kyverno.policy.addMonitoringAnnotations" . }}
```

Result: All Services automatically get:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

### Generation Policy - Auto-Create NetworkPolicy

Automatically create default deny NetworkPolicy for new namespaces:

```yaml
kyverno:
  policies:
    addDefaultNetworkPolicy:
      enabled: true

# templates/generation.yaml
{{- include "kyverno.clusterpolicy.addDefaultNetworkPolicy" . }}
```

Result: When a new namespace is created, Kyverno automatically generates:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: my-new-namespace
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

---

## 📚 Templates Reference

### ClusterPolicy Templates

#### Main Template
```yaml
{{- include "kyverno.clusterpolicy" . }}
```
Generate custom ClusterPolicy with validation/mutation/generation rules.

#### Pre-configured Security Policies
```yaml
{{- include "kyverno.clusterpolicy.requireNonRoot" . }}
{{- include "kyverno.clusterpolicy.disallowPrivileged" . }}
{{- include "kyverno.clusterpolicy.requireResourceLimits" . }}
{{- include "kyverno.clusterpolicy.requireReadOnlyRoot" . }}
{{- include "kyverno.clusterpolicy.requireForgeLabels" . }}
{{- include "kyverno.clusterpolicy.disallowLatestTag" . }}
{{- include "kyverno.clusterpolicy.addDefaultNetworkPolicy" . }}
```

### Policy Templates (Namespace-Scoped)

#### Main Template
```yaml
{{- include "kyverno.policy" . }}
```
Generate custom namespace-scoped Policy.

#### Environment-Specific Templates
```yaml
{{- include "kyverno.policy.development" . }}
{{- include "kyverno.policy.production" . }}
```

#### Mutation Templates
```yaml
{{- include "kyverno.policy.addMonitoringAnnotations" . }}
```

---

## 🔧 Configuration

See [`values.yaml`](./values.yaml) for all configuration options.

### Key Configuration Sections

- **kyverno.clusterpolicy**: Custom ClusterPolicy configuration
  - name, title, category, severity, description
  - validationFailureAction (audit or enforce)
  - background, failurePolicy, webhookTimeoutSeconds
  - rules (array of policy rules)

- **kyverno.policy**: Custom Policy configuration (namespace-scoped)
  - Same structure as ClusterPolicy

- **kyverno.policies**: Pre-configured security policies
  - requireNonRoot, disallowPrivileged, requireResourceLimits
  - requireReadOnlyRoot, requireForgeLabels, disallowLatestTag
  - addDefaultNetworkPolicy

- **kyverno.environments**: Environment-specific policies
  - development (relaxed), production (strict)

- **kyverno.mutations**: Mutation policies
  - addMonitoringAnnotations

---

## 🎯 Policy Categories

### Security Policies (Pod Security Standards)

**Baseline Level:**
- Disallow privileged containers
- Restrict host namespaces (hostNetwork, hostPID, hostIPC)
- Restrict hostPath volumes
- Disallow capabilities (beyond allowed list)

**Restricted Level:**
- Require non-root containers
- Require read-only root filesystem
- Drop ALL capabilities
- No privilege escalation

### Best Practice Policies

- Require resource limits (CPU, memory)
- Require resource requests
- Disallow :latest image tag
- Require proper labels (app, instance, component)
- Require liveness and readiness probes
- Require PodDisruptionBudget for HA

### Compliance Policies

- Audit logging enabled
- Immutable tags required
- Signed images only (image verification)
- Regulatory labels (PCI, HIPAA, SOC2)

---

## 🧪 Examples

### Complete Production Setup

```yaml
kyverno:
  # Enable all security policies
  policies:
    requireNonRoot:
      enabled: true
      action: enforce
    disallowPrivileged:
      enabled: true
      action: enforce
    requireResourceLimits:
      enabled: true
      action: enforce
    requireReadOnlyRoot:
      enabled: true
      action: audit
    disallowLatestTag:
      enabled: true
      action: enforce
    requireForgeLabels:
      enabled: true
      action: audit
    addDefaultNetworkPolicy:
      enabled: true
  
  # Production-specific strict policies
  environments:
    production:
      enabled: true
  
  # Auto-add monitoring annotations
  mutations:
    addMonitoringAnnotations:
      enabled: true
```

### Audit Mode (Report Only)

Test policies without blocking resources:

```yaml
kyverno:
  policies:
    requireNonRoot:
      enabled: true
      action: audit  # Log violations, don't block
    disallowPrivileged:
      enabled: true
      action: audit
    requireResourceLimits:
      enabled: true
      action: audit
```

### Gradual Enforcement

Start with audit, then enforce:

**Week 1-2: Audit**
```yaml
action: audit
```

**Week 3-4: Warn**
```yaml
validationFailureAction: audit
# Review PolicyReports
```

**Week 5+: Enforce**
```yaml
action: enforce
```

---

## � API Restrictions (Block kubectl exec, attach, port-forward)

Block dangerous Kubernetes API operations for enhanced security.

### Block All Dangerous Operations

Block all dangerous operations with a single template:

```yaml
# values.yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce  # or audit
    blockAttach:
      enabled: true
      action: enforce
    blockPortForward:
      enabled: true
      action: enforce
    blockProxy:
      enabled: true
      action: enforce
    blockEphemeralContainers:
      enabled: true
      action: enforce

# templates/api-restrictions.yaml
{{- include "kyverno.apiRestrictions.blockAll" . }}
```

This blocks:
- ❌ `kubectl exec` - Execute commands in containers
- ❌ `kubectl attach` - Attach to running containers
- ❌ `kubectl port-forward` - Create port forwarding tunnels
- ❌ `kubectl proxy` - Create proxy connections
- ❌ `kubectl debug` - Create ephemeral debug containers

### Block kubectl exec Only (Production Clusters)

```yaml
# values.yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
      severity: high
      message: "kubectl exec is not allowed in production. Use proper debugging tools (Telepresence, kubectl logs)."
      
      # Only block in production namespaces
      includeNamespaces:
        - production
        - prod-*
      
      # Allow for specific admins
      excludeUsers:
        - cluster-admin
        - sre-team-lead
      
      # Allow for specific service accounts
      excludeServiceAccounts:
        - system:serviceaccount:kube-system:kubernetes-dashboard
        - system:serviceaccount:monitoring:prometheus-operator

# templates/api-restrictions.yaml
{{- include "kyverno.apiRestrictions.blockExec" . }}
```

### Block port-forward (Enforce Network Policies)

```yaml
# values.yaml
kyverno:
  apiRestrictions:
    blockPortForward:
      enabled: true
      action: enforce
      severity: medium
      message: "kubectl port-forward bypasses network policies. Use proper Ingress or Service resources."
      
      # Exclude development namespaces
      excludeNamespaces:
        - development
        - dev-*
        - staging

# templates/api-restrictions.yaml
{{- include "kyverno.apiRestrictions.blockPortForward" . }}
```

### Audit Mode (Report Violations Without Blocking)

Test restrictions without blocking users:

```yaml
# values.yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: audit  # Log violations, don't block
      severity: high
    
    blockAttach:
      enabled: true
      action: audit
    
    blockPortForward:
      enabled: true
      action: audit

# Review PolicyReports to see who is using these operations:
# kubectl get polr -A
# kubectl describe polr <policy-report-name> -n <namespace>
```

### Per-Operation Control

Enable restrictions individually:

```yaml
# Block exec and attach (security critical)
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
    blockAttach:
      enabled: true
      action: enforce
    
    # Allow port-forward for development
    blockPortForward:
      enabled: false
    
    # Block ephemeral containers (kubectl debug)
    blockEphemeralContainers:
      enabled: true
      action: enforce
```

### Custom Messages

Provide helpful messages for users:

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
      message: |
        kubectl exec is disabled in this cluster for security reasons.
        
        Alternatives:
        - Use kubectl logs for log viewing
        - Use Telepresence for local debugging
        - Use ephemeral debug containers (if enabled)
        - Contact SRE team for emergency access
        
        Documentation: https://wiki.company.com/kubernetes/debugging
```

### Exceptions for System Namespaces

Allow operations in system namespaces:

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
      
      # Exclude system namespaces
      excludeNamespaces:
        - kube-system
        - kube-public
        - kube-node-lease
        - monitoring
        - logging
```

### Available Templates

```yaml
# Block individual operations
{{- include "kyverno.apiRestrictions.blockExec" . }}
{{- include "kyverno.apiRestrictions.blockAttach" . }}
{{- include "kyverno.apiRestrictions.blockPortForward" . }}
{{- include "kyverno.apiRestrictions.blockProxy" . }}
{{- include "kyverno.apiRestrictions.blockEphemeralContainers" . }}

# Block all operations (convenience)
{{- include "kyverno.apiRestrictions.blockAll" . }}
```

---

## 🔐 Resource Management Restrictions (GitOps-Only Pattern)

Block direct resource modifications by users. Only operators and deployment jobs can manage resources.

### Pattern: GitOps-Only Deployments

Users cannot use `kubectl apply/create/delete` directly. All changes must go through:
1. **Git commits** to infrastructure repository
2. **Flux/ArgoCD** operators deploy automatically
3. **CI/CD deployment jobs** for application releases

### Example 1: Block All Direct Resource Modifications

```yaml
# values.yaml
kyverno:
  resourceManagement:
    # Block Deployments, StatefulSets, DaemonSets
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      
      # Allow operators to deploy
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux"
        - "system:serviceaccount:argocd:argocd-application-controller"
        - "system:serviceaccount:ci-cd:deployment-job"
      
      # Break-glass for emergencies
      excludeUsers:
        - "cluster-admin"
    
    # Block Services, Ingresses, NetworkPolicies
    blockNetworkingModifications:
      enabled: true
      action: "enforce"
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux"
        - "system:serviceaccount:argocd:argocd-application-controller"
      excludeUsers:
        - "cluster-admin"
    
    # Block ConfigMaps, Secrets
    blockConfigModifications:
      enabled: true
      action: "enforce"
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux"
        - "system:serviceaccount:ci-cd:deployment-job"
        - "system:serviceaccount:external-secrets:external-secrets"
      excludeUsers:
        - "cluster-admin"
    
    # Block PVCs, PVs
    blockStorageModifications:
      enabled: true
      action: "enforce"
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux"
      excludeUsers:
        - "cluster-admin"
    
    # Block Roles, RoleBindings (critical)
    blockRBACModifications:
      enabled: true
      action: "enforce"
      severity: "critical"
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux"
      excludeUsers:
        - "cluster-admin"
        - "admin"

# templates/resource-management.yaml
{{- include "kyverno.resourceManagement.blockAll" . }}
```

**What happens:**
```bash
# User tries to deploy
kubectl create deployment myapp --image=nginx
# ❌ Error: Direct workload modifications are not allowed. 
#    Use Helm charts deployed via operators or deployment jobs.

# Flux operator deploys (allowed)
# ✅ Deployment created by flux ServiceAccount

# Break-glass (emergency)
kubectl create deployment myapp --image=nginx --as=cluster-admin
# ✅ Allowed (cluster-admin is excluded)
```

### Example 2: Audit Mode (Staging/Development)

Log violations without blocking (gradual rollout):

```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "audit"  # Log only, don't block
      
    blockNetworkingModifications:
      enabled: true
      action: "audit"
```

Users can still deploy, but violations are logged in PolicyReports.

### Example 3: Custom Error Messages for Users

```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      message: |
        ❌ Direct deployments are not allowed in production.
        
        ✅ How to deploy:
        1. Update Helm chart in Git: infrastructure/apps/myapp/
        2. git commit -m "Update myapp to v2.0"
        3. git push origin main
        4. Flux deploys automatically in ~1 minute
        
        📚 Documentation: https://wiki.company.com/gitops
        🎫 Need help? https://jira.company.com
```

### Example 4: Allow Specific Deployment Job

Create ServiceAccount for CI/CD pipeline:

```yaml
# ci-cd-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ci-cd
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployment-job
  namespace: ci-cd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deployment-job-role
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["create", "update", "delete", "get", "list"]
  - apiGroups: [""]
    resources: ["services", "configmaps", "secrets"]
    verbs: ["create", "update", "delete", "get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: deployment-job-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deployment-job-role
subjects:
  - kind: ServiceAccount
    name: deployment-job
    namespace: ci-cd
```

Exclude in Kyverno:

```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      excludeServiceAccounts:
        - "system:serviceaccount:ci-cd:deployment-job"
```

Now CI/CD pipeline can deploy:

```bash
# In CI/CD pipeline (GitHub Actions, GitLab CI, etc.)
kubectl create deployment myapp --image=nginx \
  --as=system:serviceaccount:ci-cd:deployment-job
# ✅ Allowed
```

### Example 5: Per-Resource Type Control

Enable only specific restrictions:

```yaml
kyverno:
  resourceManagement:
    # Block workloads (strict)
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
    
    # Block networking (strict)
    blockNetworkingModifications:
      enabled: true
      action: "enforce"
    
    # Allow ConfigMaps/Secrets (more lenient)
    blockConfigModifications:
      enabled: false
    
    # Block storage (strict)
    blockStorageModifications:
      enabled: true
      action: "enforce"
    
    # Block RBAC (critical)
    blockRBACModifications:
      enabled: true
      action: "enforce"
      severity: "critical"
```

### Available Templates

```yaml
# Block individual resource types
{{- include "kyverno.resourceManagement.blockWorkloadModifications" . }}
{{- include "kyverno.resourceManagement.blockNetworkingModifications" . }}
{{- include "kyverno.resourceManagement.blockConfigModifications" . }}
{{- include "kyverno.resourceManagement.blockStorageModifications" . }}
{{- include "kyverno.resourceManagement.blockRBACModifications" . }}

# Block all resource modifications (convenience)
{{- include "kyverno.resourceManagement.blockAll" . }}
```

### Resources Blocked

| Policy | Resources | Operations | Typical Use Case |
|--------|-----------|------------|------------------|
| **blockWorkloadModifications** | Deployment, StatefulSet, DaemonSet, ReplicaSet | CREATE, UPDATE, DELETE | Prevent direct pod deployments |
| **blockNetworkingModifications** | Service, Ingress, NetworkPolicy | CREATE, UPDATE, DELETE | Prevent network exposure changes |
| **blockConfigModifications** | ConfigMap, Secret | CREATE, UPDATE, DELETE | Enforce secret management via operators |
| **blockStorageModifications** | PersistentVolumeClaim, PersistentVolume | CREATE, UPDATE, DELETE | Control storage provisioning |
| **blockRBACModifications** | Role, RoleBinding, ClusterRole, ClusterRoleBinding | CREATE, UPDATE, DELETE | Prevent privilege escalation |

### Benefits

✅ **Compliance**: All changes tracked in Git (audit trail)  
✅ **Consistency**: No manual modifications, infrastructure as code  
✅ **Security**: Reduced attack surface, controlled access  
✅ **Reliability**: Peer review, automated testing before deploy  
✅ **Disaster Recovery**: Git history = full change log

### Break-Glass Procedure

In emergencies, cluster-admin can bypass policies:

```bash
# Authenticate as admin
kubectl config use-context production-admin

# Make emergency change
kubectl scale deployment critical-app --replicas=10

# Document in incident
# INC-12345: Emergency scaling due to traffic spike

# Sync back to Git
# Update Helm chart with new replica count
git commit -m "INC-12345: Scale critical-app to 10 replicas"
git push
```

---

## �🔗 Integration with Other Libraries

This library works seamlessly with:

- **common-forge**: Provides naming conventions and labels
- **common-hardening**: ResourceQuota and NetworkPolicy templates
- **common-kubernetes**: Base Kubernetes resource templates

---

## 🛠️ Dependencies

- **common-forge** (~0.1.0): Naming and validation helpers

---

## 📝 License

Part of the Forge Platform - Internal Use Only

---

## 🤝 Contributing

See main repository contributing guidelines.

---

## 📞 Support

For issues or questions, contact the Platform Engineering team.
