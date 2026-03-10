# UC01: Vault Secret Injection via Annotations

## Overview
Tests the Vault Agent Injector pattern for automatically injecting secrets from HashiCorp Vault into Kubernetes pods using annotations. This approach eliminates the need for applications to directly interact with the Vault API.

## Vault Agent Injector
The Vault Agent Injector is a Kubernetes mutation webhook that intercepts pod creation requests and injects a Vault Agent sidecar container. The sidecar authenticates to Vault, retrieves secrets, and writes them to a shared volume accessible by the application container.

## Use Cases
- **Secret Management**: Store sensitive data (API keys, passwords, certificates) in Vault
- **Zero-Code Integration**: Applications read secrets from files without Vault SDK
- **Automatic Renewal**: Vault Agent automatically renews leases for dynamic secrets
- **Template Rendering**: Transform Vault secrets into application-specific formats

## Prerequisites
- HashiCorp Vault installed in cluster (namespace: `vault`)
- Vault Agent Injector webhook enabled
- Kubernetes authentication method configured in Vault
- Vault policy granting access to `secret/data/myapp/config`

## Test Objectives
1. Deploy pod with Vault injection annotations
2. Verify Vault Agent sidecar injected into pod
3. Validate secrets written to `/vault/secrets/config.txt`
4. Confirm application container can read secrets
5. Test secret template rendering

## Values Configuration
- **Vault Address**: `http://vault.vault.svc.cluster.local:8200`
- **Vault Role**: `app-role` (Kubernetes auth)
- **Secret Path**: `secret/data/myapp/config`
- **Injected File**: `/vault/secrets/config.txt`

## References
- [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Vault Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Annotation Reference](https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations)
