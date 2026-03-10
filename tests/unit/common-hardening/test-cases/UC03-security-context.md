# UC-HARDENING-03: Security Contexts

## Overview

Tests comprehensive security context configuration including capabilities, seccomp, and filesystem permissions.

**Duration**: ~8 minutes

## Test Objectives

1. ✅ Deploy pod with security context
2. ✅ Verify non-root execution
3. ✅ Validate capability dropping
4. ✅ Test seccomp profile
5. ✅ Verify no privilege escalation

## References

- [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Configure Linux Capabilities](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-capabilities-for-a-container)
