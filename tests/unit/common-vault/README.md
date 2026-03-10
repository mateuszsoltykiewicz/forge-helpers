# Common-Vault Test Suite

Comprehensive test suite for the `common-vault` Helm chart, which provides HashiCorp Vault integration for Kubernetes workloads using the Vault Agent Injector pattern.

## Overview

HashiCorp Vault is a secrets management solution that provides secure storage, dynamic secrets generation, encryption as a service, and more. The Vault Agent Injector is a Kubernetes mutation webhook that automatically injects secrets into pods via annotations, eliminating the need for applications to directly interact with the Vault API.

## Prerequisites

1. **Kubernetes cluster** (v1.23+)
2. **Helm** (v3.8+)
3. **kubectl** configured for your cluster
4. **HashiCorp Vault** installed with Agent Injector enabled:
   ```bash
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm install vault hashicorp/vault \
     --namespace vault --create-namespace \
     --set "injector.enabled=true" \
     --set "server.dev.enabled=true"
   ```
5. **Vault initialized and unsealed** (if running in production mode)

## Test Cases

### UC01: Secret Injection via Annotations
**File**: `test-cases/UC01-secret-injection.md`

Tests the Vault Agent Injector pattern for automatically injecting static secrets from Vault's KV (Key-Value) secrets engine into Kubernetes pods.

**Key Features**:
- Vault Agent Injector mutation webhook
- Secret injection via pod annotations
- Template rendering (Vault secrets → application config format)
- ServiceAccount-based Kubernetes authentication
- Secrets written to `/vault/secrets/config.txt`

**Use Cases**:
- API keys, passwords, certificates
- Application configuration files
- Zero-code integration (apps read files, not Vault API)

**Run**: `cd test-cases && ./run-uc01.sh`

---

### UC02: Dynamic Database Credentials
**File**: `test-cases/UC02-dynamic-credentials.md`

Tests Vault's database secrets engine for generating short-lived, dynamically created database credentials with automatic rotation.

**Key Features**:
- Database secrets engine (PostgreSQL, MySQL, etc.)
- Dynamic credential generation (unique username/password per request)
- Automatic TTL-based expiration
- Credential renewal via Vault Agent
- Revocation on pod termination

**Use Cases**:
- Eliminate static database passwords
- Automatic credential rotation
- Audit trail of database access
- Least privilege with short-lived credentials

**Run**: `cd test-cases && ./run-uc02.sh`

**Note**: Requires Vault database secrets engine configured with database connection.

---

## Directory Structure

```
common-vault/
├── README.md                              # This file
├── run-all.sh                             # Run all test cases
├── test-cases/
│   ├── UC01-secret-injection.md          # UC01 documentation
│   ├── UC02-dynamic-credentials.md       # UC02 documentation
│   ├── run-uc01.sh                       # UC01 test script
│   └── run-uc02.sh                       # UC02 test script
└── values/
    ├── uc01-secret-injection.yaml        # Static secrets values
    └── uc02-dynamic-credentials.yaml     # Dynamic DB credentials values
```

## Quick Start

### Run All Tests
```bash
./run-all.sh
```

### Run Individual Tests
```bash
cd test-cases
./run-uc01.sh  # Secret Injection
./run-uc02.sh  # Dynamic Database Credentials
```

### Install Vault with Agent Injector
```bash
# Add HashiCorp Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault in dev mode (for testing)
helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "injector.enabled=true" \
  --set "server.dev.enabled=true"

# Verify installation
kubectl get pods -n vault
kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg
```

### Configure Kubernetes Auth in Vault
```bash
# Enable Kubernetes auth
kubectl exec -it vault-0 -n vault -- vault auth enable kubernetes

# Configure Kubernetes auth
kubectl exec -it vault-0 -n vault -- vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

# Create policy
kubectl exec -it vault-0 -n vault -- vault policy write app-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Create role
kubectl exec -it vault-0 -n vault -- vault write auth/kubernetes/role/app-role \
  bound_service_account_names=vault-app-sa \
  bound_service_account_namespaces=vault-test \
  policies=app-policy \
  ttl=24h
```

### Store Test Secrets in Vault
```bash
# Enable KV v2 secrets engine (if not already enabled)
kubectl exec -it vault-0 -n vault -- vault secrets enable -path=secret kv-v2

# Write test secrets
kubectl exec -it vault-0 -n vault -- vault kv put secret/myapp/config \
  database_url="postgresql://user:pass@db:5432/mydb" \
  api_key="test-api-key-12345"

# Verify
kubectl exec -it vault-0 -n vault -- vault kv get secret/myapp/config
```

## Vault Agent Injector Annotations

### Common Annotations

```yaml
# Enable injection
vault.hashicorp.com/agent-inject: "true"

# Specify Vault role (from Kubernetes auth)
vault.hashicorp.com/role: "app-role"

# Inject secret from path
vault.hashicorp.com/agent-inject-secret-<filename>: "secret/path"

# Custom template for secret rendering
vault.hashicorp.com/agent-inject-template-<filename>: |
  {{- with secret "secret/path" -}}
  KEY={{ .Data.data.key }}
  {{- end }}

# Custom destination path (default: /vault/secrets/)
vault.hashicorp.com/secret-volume-path: "/custom/path"

# Agent configuration
vault.hashicorp.com/agent-pre-populate-only: "true"  # Exit after rendering
vault.hashicorp.com/agent-limits-cpu: "100m"
vault.hashicorp.com/agent-limits-mem: "128Mi"
```

### Example: Environment Variables

```yaml
podAnnotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "app-role"
  vault.hashicorp.com/agent-inject-secret-env: "secret/data/myapp/config"
  vault.hashicorp.com/agent-inject-template-env: |
    {{- with secret "secret/data/myapp/config" -}}
    export DATABASE_URL="{{ .Data.data.database_url }}"
    export API_KEY="{{ .Data.data.api_key }}"
    {{- end }}
```

Then in your pod:
```bash
source /vault/secrets/env && ./myapp
```

## Resources

- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Kubernetes Auth Method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases)

## Support

For issues or questions:
1. Check Vault Agent logs: `kubectl logs <pod> -c vault-agent-init`
2. Verify Vault configuration: `vault read auth/kubernetes/role/<role>`
3. Consult [Vault troubleshooting guide](https://developer.hashicorp.com/vault/tutorials/kubernetes/troubleshoot)
