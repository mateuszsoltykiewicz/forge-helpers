# UC-HARDENING-01: Pod Security Standards

## Overview

Tests Pod Security Standards (PSS) enforcement at namespace level (privileged, baseline, restricted).

**Duration**: ~8 minutes

## Test Objectives

1. ✅ Apply PSS labels to namespace
2. ✅ Deploy compliant pod (passes restricted)
3. ✅ Attempt non-compliant pod (should fail)
4. ✅ Verify audit/warn modes
5. ✅ Test different PSS levels

## References

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
