# Quick Start: Block kubectl exec in Production

This guide shows how to quickly block `kubectl exec`, `kubectl attach`, and other dangerous operations in your Kubernetes cluster.

## 5-Minute Setup

### Step 1: Add to your Helm chart

```yaml
# Chart.yaml
dependencies:
  - name: common-kyverno
    version: ~0.1.0
    repository: file://../common-kyverno
```

### Step 2: Enable API restrictions

```yaml
# values.yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
    blockAttach:
      enabled: true
      action: enforce
    blockPortForward:
      enabled: true
      action: enforce
```

### Step 3: Add to your templates

```yaml
# templates/security-policies.yaml
{{- include "kyverno.apiRestrictions.blockAll" . }}
```

### Step 4: Deploy

```bash
helm upgrade myapp . --install
```

## Test It

Try to exec into a pod:

```bash
$ kubectl exec -it my-pod -- /bin/bash
Error from server: admission webhook "validate.kyverno.svc" denied the request:
kubectl exec is not allowed in this cluster. Use proper debugging tools instead.
```

✅ **Success!** kubectl exec is now blocked.

## Common Configurations

### Production (Strict)

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce  # Block immediately
      includeNamespaces:
        - production
        - prod-*
```

### Staging (Audit Mode)

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: audit  # Log only, don't block
      includeNamespaces:
        - staging
```

### With Exceptions

```yaml
kyverno:
  apiRestrictions:
    blockExec:
      enabled: true
      action: enforce
      excludeUsers:
        - cluster-admin  # Allow admins
      excludeNamespaces:
        - kube-system    # Allow system namespaces
        - development    # Allow dev environments
```

## What Gets Blocked?

| Command | Blocked | Alternative |
|---------|---------|-------------|
| `kubectl exec` | ✅ | `kubectl logs`, Telepresence |
| `kubectl attach` | ✅ | `kubectl logs -f` |
| `kubectl port-forward` | ✅ | Ingress, LoadBalancer |
| `kubectl debug` | ✅ | Proper logging, tracing |

## Monitoring

View blocked attempts:

```bash
# List policy reports
kubectl get polr -A

# View details
kubectl describe polr <report-name> -n <namespace>
```

## Need Help?

- Full documentation: `../README.md`
- Production example: `examples/api-restrictions-production.yaml`
- Audit mode example: `examples/api-restrictions-staging-audit.yaml`

## Troubleshooting

**Q: Policy not working?**
```bash
# Check if Kyverno is running
kubectl get pods -n kyverno

# Check if policy is active
kubectl get clusterpolicy
```

**Q: Need emergency access?**
```bash
# Temporarily disable
kubectl patch clusterpolicy block-pod-exec \
  -p '{"spec":{"validationFailureAction":"audit"}}'

# Re-enable after
kubectl patch clusterpolicy block-pod-exec \
  -p '{"spec":{"validationFailureAction":"enforce"}}'
```

**Q: Want to allow specific users?**
```yaml
excludeUsers:
  - my-admin-user
  - sre-team
```

## Next Steps

1. ✅ Start with audit mode
2. ✅ Review PolicyReports for 1-2 weeks
3. ✅ Identify legitimate use cases
4. ✅ Provide alternatives (Telepresence, better logging)
5. ✅ Switch to enforce mode
6. ✅ Monitor and iterate

---

**Security Tip:** Always start with `action: audit` to understand impact before enforcing.
