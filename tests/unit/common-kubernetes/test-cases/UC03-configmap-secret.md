# UC-KUBERNETES-03: ConfigMap and Secret Management

## Overview

Tests ConfigMap and Secret creation, mounting as files, and injection as environment variables.

**Duration**: ~8 minutes

## Test Objectives

1. ✅ Create ConfigMap with multiple keys
2. ✅ Create Secret with sensitive data
3. ✅ Inject ConfigMap/Secret as env vars
4. ✅ Mount ConfigMap/Secret as files
5. ✅ Verify data accessibility in pods
6. ✅ Test file permissions on secrets

## Best Practices

- Use Secrets for credentials (base64 encoded)
- Mount secrets as read-only volumes
- Use ConfigMaps for non-sensitive config
- Avoid hardcoding secrets in images
- Consider Vault/External Secrets for production

## References

- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
