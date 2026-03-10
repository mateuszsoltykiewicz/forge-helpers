# common-kubernetes Test Suite

Comprehensive test coverage for the `common-kubernetes` Helm chart, validating core Kubernetes resources: Deployments, Services, Ingress, ConfigMaps, Secrets, and RBAC.

## 📋 Overview

This test suite provides **Type 1 (Isolated Chart Testing)** for common-kubernetes, covering:

- **UC01**: Deployment with Horizontal Pod Autoscaler (HPA)
- **UC02**: Service + Ingress Configuration
- **UC03**: ConfigMap and Secret Management
- **UC04**: RBAC (Role-Based Access Control)

## 🎯 Use Cases

### UC01: Deployment with Horizontal Pod Autoscaler

**Purpose**: Validate automatic pod scaling based on CPU/memory metrics

**Key Features**:
- HPA configuration (min/max replicas, target utilization)
- Scale-up/scale-down behavior
- Metrics server integration
- Resource requests/limits validation

**Test Duration**: ~15 minutes (includes scaling observation)

**Run Test**:
```bash
cd test-cases
./run-uc01.sh
```

---

### UC02: Service + Ingress Configuration

**Purpose**: Test service exposure and ingress routing

**Key Features**:
- ClusterIP service creation
- Internal DNS resolution
- Service endpoints validation
- Ingress routing rules
- Load balancing across pods

**Test Duration**: ~10 minutes

**Run Test**:
```bash
cd test-cases
./run-uc02.sh
```

---

### UC03: ConfigMap and Secret Management

**Purpose**: Validate configuration and secret injection into pods

**Key Features**:
- ConfigMap creation with multiple keys
- Secret creation (base64 encoded)
- Environment variable injection
- Volume mounts (files from ConfigMap/Secret)
- File permissions validation

**Test Duration**: ~8 minutes

**Run Test**:
```bash
cd test-cases
./run-uc03.sh
```

---

### UC04: RBAC (Role-Based Access Control)

**Purpose**: Test ServiceAccount, Role, and permission enforcement

**Key Features**:
- ServiceAccount creation
- Role (namespace-scoped permissions)
- RoleBinding
- ClusterRole (cluster-wide permissions)
- ClusterRoleBinding
- Permission testing (allowed/denied operations)

**Test Duration**: ~8 minutes

**Run Test**:
```bash
cd test-cases
./run-uc04.sh
```

---

## 🚀 Quick Start

### Prerequisites

```bash
# Verify tools
kubectl version --client
helm version

# Check cluster access
kubectl cluster-info
kubectl get nodes

# For UC01 (HPA), ensure metrics-server is installed
kubectl get deployment metrics-server -n kube-system

# For UC02 (Ingress), ensure ingress controller is installed
kubectl get pods -n ingress-nginx
```

### Run All Tests

```bash
# From common-kubernetes directory
./run-all.sh
```

### Run Individual Tests

```bash
cd test-cases

# UC01: HPA deployment
./run-uc01.sh

# UC02: Service + Ingress
./run-uc02.sh

# UC03: ConfigMap/Secret
./run-uc03.sh

# UC04: RBAC
./run-uc04.sh
```

## 📁 Directory Structure

```
common-kubernetes/
├── README.md                           # This file
├── run-all.sh                          # Execute all UCs
├── test-cases/
│   ├── run-uc01.sh                    # HPA tests
│   ├── run-uc02.sh                    # Service/Ingress tests
│   ├── run-uc03.sh                    # ConfigMap/Secret tests
│   ├── run-uc04.sh                    # RBAC tests
│   ├── UC01-deployment-hpa.md         # HPA documentation
│   ├── UC02-service-ingress.md        # Service documentation
│   ├── UC03-configmap-secret.md       # ConfigMap documentation
│   └── UC04-rbac.md                   # RBAC documentation
├── values/
│   ├── uc01-deployment-hpa.yaml       # HPA configuration
│   ├── uc02-service-ingress.yaml      # Service/Ingress config
│   ├── uc03-configmap-secret.yaml     # ConfigMap/Secret config
│   └── uc04-rbac.yaml                 # RBAC configuration
└── workloads/
    ├── load-generator.yaml            # HPA load testing
    ├── test-client.yaml               # Service connectivity tests
    ├── config-validator.yaml          # ConfigMap/Secret validation
    └── rbac-tester.yaml               # RBAC permission tests
```

## 📊 Expected Test Results

### Passing Test Output

```
=================================================================
  common-kubernetes Test Suite - All Use Cases
=================================================================

╔════════════════════════════════════════════════════════════════╗
║  UC01: Deployment with HPA
╚════════════════════════════════════════════════════════════════╝

✅ PASS: kubectl installed
✅ PASS: helm installed
✅ PASS: Metrics server available
✅ PASS: Chart installed
✅ PASS: Deployment created
✅ PASS: HPA created
✅ PASS: HPA metrics available
✅ PASS: Service created
✅ PASS: Resource requests configured
✅ PASS: HPA scaled up

Total Tests:   11
Passed:        11
Failed:        0

✅ UC01 PASSED

[... similar output for UC02, UC03, UC04 ...]

=================================================================
  Final Summary
=================================================================

Total Use Cases:   4
Passed:            4
Failed:            0
Duration:          340s

✅ All common-kubernetes use cases passed!
```

## 🛠️ Troubleshooting

### UC01: HPA Issues

**Problem**: HPA shows `<unknown>` metrics

```bash
# Check metrics-server
kubectl get deployment metrics-server -n kube-system
kubectl logs -n kube-system deployment/metrics-server

# For minikube/kind, patch for insecure TLS:
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Wait and verify:
kubectl top nodes
```

**Problem**: HPA not scaling

```bash
# Verify resource requests are set
kubectl get pods -l app=hpa-test-app -o yaml | grep -A 5 resources

# Check CPU usage
kubectl top pods -l app=hpa-test-app

# Generate more load
kubectl scale deployment load-generator-sustained --replicas=5
```

### UC02: Service/Ingress Issues

**Problem**: Service not accessible

```bash
# Check service endpoints
kubectl get endpoints web-app-service

# Verify pod selector matches
kubectl get pods -l app=web-app

# Test port-forward
kubectl port-forward svc/web-app-service 8080:80
curl http://localhost:8080
```

**Problem**: Ingress not working

```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Verify ingress resource
kubectl describe ingress

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### UC03: ConfigMap/Secret Issues

**Problem**: Environment variables not set

```bash
# Check ConfigMap/Secret existence
kubectl get configmap app-config
kubectl get secret app-secrets

# Verify pod environment
kubectl exec config-app-xxx -- env | grep APP_NAME

# Check volume mounts
kubectl describe pod config-app-xxx | grep -A 10 Mounts
```

**Problem**: Files not mounted

```bash
# Verify volumes in pod spec
kubectl get pod config-app-xxx -o yaml | grep -A 20 volumes

# Check mounted files
kubectl exec config-app-xxx -- ls -la /config
kubectl exec config-app-xxx -- cat /config/app.conf
```

### UC04: RBAC Issues

**Problem**: Permissions not working

```bash
# Test permissions manually
kubectl auth can-i list pods --as=system:serviceaccount:default:rbac-test-sa

# Check RoleBinding
kubectl describe rolebinding rbac-test-binding

# Verify ServiceAccount in pod
kubectl get pod rbac-test-app-xxx -o yaml | grep serviceAccount
```

**Problem**: ClusterRole not binding

```bash
# Check ClusterRoleBinding
kubectl get clusterrolebinding rbac-test-cluster-binding

# Verify ClusterRole exists
kubectl get clusterrole rbac-test-clusterrole

# Test cluster-wide permissions
kubectl auth can-i list nodes --as=system:serviceaccount:default:rbac-test-sa
```

## 🎓 Best Practices

### Deployments & HPA

1. **Always Set Resource Requests**: HPA requires CPU/memory requests
2. **Conservative Thresholds**: Start with 70-80% CPU target
3. **Slow Scale-Down**: Use 5-10 minute stabilization windows
4. **Test Under Load**: Verify scaling behavior with realistic traffic

### Services & Ingress

1. **Use ClusterIP for Internal**: Only expose via Ingress when needed
2. **TLS Termination**: Configure TLS at Ingress level
3. **Rate Limiting**: Protect services with ingress annotations
4. **Health Checks**: Configure readiness probes for smooth rolling updates

### ConfigMaps & Secrets

1. **Secrets for Credentials**: Never use ConfigMaps for sensitive data
2. **Immutable ConfigMaps**: Set `immutable: true` for production config
3. **External Secrets**: Use Vault/External Secrets Operator for production
4. **Volume Mounts for Files**: Use volumes instead of env vars for large configs

### RBAC

1. **Principle of Least Privilege**: Grant minimal permissions needed
2. **Namespace-Scoped First**: Use Roles instead of ClusterRoles when possible
3. **Avoid Wildcards**: Specify exact resources and verbs
4. **Regular Audits**: Review RBAC permissions quarterly

## 📚 References

### Kubernetes Documentation
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

### Tools
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Cert-Manager](https://cert-manager.io/) (for TLS)
- [External Secrets Operator](https://external-secrets.io/)

### Best Practices
- [Kubernetes Production Best Practices](https://learnk8s.io/production-best-practices)
- [RBAC Good Practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)
- [Configuration Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

## 📝 License

Part of the forge-helpers common charts testing framework.

## 🤝 Contributing

When adding new test cases:

1. Create values file: `values/ucXX-name.yaml`
2. Write documentation: `test-cases/UCXX-name.md`
3. Add test workload: `workloads/name.yaml` (if needed)
4. Implement test script: `test-cases/run-ucXX.sh`
5. Update `run-all.sh` to include new UC
6. Update this README with UC description
7. Test locally before committing

**Test Script Template**:
```bash
#!/bin/bash
set -e

# UC-KUBERNETES-XX: Description

# Color codes, functions (pass, fail, info, warn)
# Prerequisites check
# Cleanup trap
# Test steps (8-12 tests recommended)
# Summary with pass/fail counts
```

## 🚀 Next Steps

After completing all common-kubernetes tests, proceed to:
- **common-hardening**: Security hardening tests
- **common-keda**: Event-driven autoscaling
- **common-vault**: Secrets management integration

Test all charts together:
```bash
cd ../..
./run-all-charts.sh
```
