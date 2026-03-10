# UC-HARDENING-02: Network Policies

## Overview

Tests NetworkPolicy creation for controlling pod-to-pod network communication.

**Duration**: ~10 minutes

## Test Objectives

1. ✅ Create ingress NetworkPolicy
2. ✅ Create egress NetworkPolicy
3. ✅ Test allowed connections
4. ✅ Test denied connections
5. ✅ Verify DNS still works

## References

- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
