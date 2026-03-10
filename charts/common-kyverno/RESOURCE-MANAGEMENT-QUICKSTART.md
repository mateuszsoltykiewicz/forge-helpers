# Resource Management Restrictions - Quick Start

**Block direct kubectl modifications, enforce GitOps-only deployments**

---

## 🎯 Goal

Prevent users from using `kubectl apply/create/delete` directly.  
All changes must go through **Git → Flux/ArgoCD → Kubernetes**.

---

## ⚡ 5-Minute Setup

### 1. Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace
```

### 2. Install Resource Management Policies

```bash
helm install common-kyverno ./charts/common-kyverno \
  --namespace kyverno \
  --set kyverno.resourceManagement.blockWorkloadModifications.enabled=true \
  --set kyverno.resourceManagement.blockNetworkingModifications.enabled=true \
  --set kyverno.resourceManagement.blockConfigModifications.enabled=true \
  --set kyverno.resourceManagement.blockStorageModifications.enabled=true \
  --set kyverno.resourceManagement.blockRBACModifications.enabled=true
```

### 3. Configure Operator Exclusions

```yaml
# values.yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"
      
      # Allow your GitOps operator
      excludeServiceAccounts:
        - "system:serviceaccount:flux-system:flux"  # Flux CD
        - "system:serviceaccount:argocd:argocd-application-controller"  # ArgoCD
        - "system:serviceaccount:ci-cd:deployment-job"  # CI/CD pipeline
      
      # Break-glass for emergencies
      excludeUsers:
        - "cluster-admin"
```

```bash
helm upgrade common-kyverno ./charts/common-kyverno \
  --namespace kyverno \
  -f values.yaml
```

---

## ✅ Test

### Users blocked (expected ❌):

```bash
kubectl create deployment test --image=nginx
# Error: Direct workload modifications are not allowed...
```

### Operators allowed (expected ✅):

```bash
# Flux deploys
kubectl apply -f deployment.yaml \
  --as=system:serviceaccount:flux-system:flux
# ✅ Created
```

### Break-glass (expected ✅):

```bash
kubectl create deployment emergency --image=nginx \
  --as=cluster-admin
# ✅ Created (cluster-admin excluded)
```

---

## 📋 What Gets Blocked

| Resource Type | Examples | User Access | Operator Access |
|--------------|----------|-------------|-----------------|
| **Workloads** | Deployment, StatefulSet, DaemonSet | ❌ Blocked | ✅ Allowed |
| **Networking** | Service, Ingress, NetworkPolicy | ❌ Blocked | ✅ Allowed |
| **Configuration** | ConfigMap, Secret | ❌ Blocked | ✅ Allowed |
| **Storage** | PVC, PV | ❌ Blocked | ✅ Allowed |
| **RBAC** | Role, RoleBinding | ❌ Blocked | ✅ Allowed (admin only) |

---

## 🔧 Common Configurations

### Production (Strict)

```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "enforce"  # Block immediately
    blockNetworkingModifications:
      enabled: true
      action: "enforce"
    blockConfigModifications:
      enabled: true
      action: "enforce"
    blockStorageModifications:
      enabled: true
      action: "enforce"
    blockRBACModifications:
      enabled: true
      action: "enforce"
```

### Staging (Audit First)

```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: true
      action: "audit"  # Log only, don't block yet
    blockNetworkingModifications:
      enabled: true
      action: "audit"
    # ... all policies in audit mode
```

### Development (Disabled)

```yaml
kyverno:
  resourceManagement:
    blockWorkloadModifications:
      enabled: false  # Allow direct modifications in dev
```

---

## 🚨 Break-Glass Procedure

**Emergency access when operator is broken:**

```bash
# 1. Authenticate as admin
kubectl config use-context production-admin

# 2. Make emergency change
kubectl scale deployment critical-app --replicas=10

# 3. Document in incident ticket
# INC-12345: Emergency scaling due to traffic spike

# 4. Sync back to Git (important!)
# Update Helm chart with new replica count
cd infrastructure/apps/critical-app/
vim values.yaml  # Set replicaCount: 10
git commit -m "INC-12345: Emergency scale to 10 replicas"
git push origin main

# 5. Verify Flux/ArgoCD syncs the change
flux reconcile helmrelease critical-app
```

---

## 📊 Monitoring

### Check Policy Status

```bash
kubectl get clusterpolicies
```

### View Violations (PolicyReports)

```bash
kubectl get policyreports -A
kubectl get policyreport -n production -o yaml
```

### Prometheus Metrics

```promql
# Total violations
kyverno_policy_results_total{result="fail"}

# Violations by policy
sum by (policy) (
  kyverno_policy_results_total{result="fail"}
)

# Violations by user
sum by (user) (
  kyverno_policy_results_total{result="fail"}
)
```

---

## 🎓 User Training

### ❌ Don't Do This

```bash
kubectl apply -f deployment.yaml
kubectl create deployment myapp --image=nginx
kubectl edit deployment myapp
kubectl delete deployment myapp
kubectl scale deployment myapp --replicas=5
```

### ✅ Do This Instead

```bash
# 1. Update Helm chart in Git
cd infrastructure/apps/myapp/
vim values.yaml
git add .
git commit -m "Update myapp to v2.0"
git push origin main

# 2. Wait for Flux/ArgoCD to deploy (~1 minute)
flux get helmreleases
argocd app sync myapp

# 3. Verify deployment
kubectl get deployment myapp -n production
```

---

## 🐛 Troubleshooting

### Q: Policy blocks legitimate operator?

**A:** Add ServiceAccount to `excludeServiceAccounts`:

```yaml
excludeServiceAccounts:
  - "system:serviceaccount:my-namespace:my-operator"
```

### Q: Need to allow specific user to deploy?

**A:** Create deployment-job ServiceAccount (see `examples/deployment-job-example.yaml`)

### Q: Policy not working?

**A:** Check Kyverno is running:

```bash
kubectl get pods -n kyverno
kubectl get validatingwebhookconfigurations
```

### Q: Too strict for development cluster?

**A:** Use `action: "audit"` (log only):

```yaml
action: "audit"  # Don't block, just log violations
```

---

## 📚 Next Steps

1. **Read full documentation**: `README.md` - Resource Management Restrictions section
2. **Review production example**: `examples/gitops-only-production.yaml`
3. **Set up deployment job**: `examples/deployment-job-example.yaml`
4. **Configure monitoring**: Set up Prometheus alerts for violations
5. **Train users**: Share GitOps workflow documentation

---

## 🔗 Templates Available

```yaml
# Individual restrictions
{{- include "kyverno.resourceManagement.blockWorkloadModifications" . }}
{{- include "kyverno.resourceManagement.blockNetworkingModifications" . }}
{{- include "kyverno.resourceManagement.blockConfigModifications" . }}
{{- include "kyverno.resourceManagement.blockStorageModifications" . }}
{{- include "kyverno.resourceManagement.blockRBACModifications" . }}

# All restrictions at once
{{- include "kyverno.resourceManagement.blockAll" . }}
```

---

**Need help?** Check `examples/` directory for complete configurations.
