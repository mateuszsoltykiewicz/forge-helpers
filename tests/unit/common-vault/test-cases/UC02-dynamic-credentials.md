# UC02: Dynamic Database Credentials from Vault

## Overview
Tests Vault's database secrets engine for generating short-lived, dynamically created database credentials. This pattern eliminates static database passwords and provides automatic credential rotation.

## Vault Database Secrets Engine
The database secrets engine generates database credentials on-demand with configurable TTL (time-to-live). When credentials expire, Vault automatically revokes them from the database, reducing the risk of credential leakage.

## Use Cases
- **Dynamic Credentials**: Generate unique database credentials per application instance
- **Automatic Rotation**: Credentials expire and rotate automatically
- **Audit Trail**: Track which application accessed which database and when
- **Least Privilege**: Grant minimal permissions with short-lived credentials

## Supported Databases
- PostgreSQL, MySQL, Oracle, MSSQL, MongoDB, Cassandra, Elasticsearch, and more

## Prerequisites
- Vault installed with database secrets engine enabled
- Database connection configured in Vault:
  ```bash
  vault write database/config/mydb \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb" \
    allowed_roles="db-user"
  ```
- Database role configured with SQL statements for user creation
- Vault policy granting access to `database/creds/db-user`

## Test Objectives
1. Deploy pod with database credentials injection
2. Verify Vault Agent retrieves dynamic credentials
3. Validate credentials written to `/vault/secrets/db-creds`
4. Confirm credentials contain `username` and `password`
5. Test credential expiration and renewal

## Credential Lifecycle
1. **Request**: Application pod starts, Vault Agent requests credentials
2. **Generate**: Vault creates new database user with random username/password
3. **Grant**: Vault executes SQL to grant permissions to new user
4. **Return**: Credentials injected into pod at `/vault/secrets/db-creds`
5. **Renew**: Vault Agent renews lease before TTL expiration
6. **Revoke**: When pod terminates or TTL expires, Vault deletes database user

## References
- [Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [PostgreSQL Plugin](https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql)
- [Dynamic Secrets Guide](https://developer.hashicorp.com/vault/tutorials/db-credentials)
