# UC-KUBERNETES-04: RBAC (Role-Based Access Control)

## Overview

Tests ServiceAccount, Role, RoleBinding, ClusterRole, and ClusterRoleBinding creation and permission enforcement.

**Duration**: ~8 minutes

## Test Objectives

1. ✅ Create ServiceAccount
2. ✅ Create Role with namespace permissions
3. ✅ Create RoleBinding
4. ✅ Create ClusterRole with cluster permissions
5. ✅ Create ClusterRoleBinding
6. ✅ Test allowed operations
7. ✅ Test denied operations

## Best Practices

- Principle of least privilege
- Use Roles for namespace-scoped access
- Use ClusterRoles for cluster-wide access
- Avoid binding to default ServiceAccount
- Regularly audit RBAC permissions

## References

- [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [ServiceAccounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
