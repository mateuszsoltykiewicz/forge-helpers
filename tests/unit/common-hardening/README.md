# common-hardening Test Suite

Security hardening test coverage for Kubernetes workloads: Pod Security Standards, Network Policies, and Security Contexts.

## 📋 Overview

**Type 1 Testing** for common-hardening chart:

- **UC01**: Pod Security Standards (PSS) enforcement
- **UC02**: Network Policies for traffic control
- **UC03**: Security Contexts and capabilities

## 🎯 Use Cases

### UC01: Pod Security Standards

Tests namespace-level PSS enforcement (privileged/baseline/restricted levels).

**Run**: `cd test-cases && ./run-uc01.sh`

### UC02: Network Policies

Tests ingress/egress NetworkPolicy creation and enforcement.

**Run**: `cd test-cases && ./run-uc02.sh`

### UC03: Security Contexts

Tests comprehensive security context configuration (non-root, capabilities, seccomp).

**Run**: `cd test-cases && ./run-uc03.sh`

## 🚀 Quick Start

```bash
# Run all tests
./run-all.sh

# Individual tests
cd test-cases
./run-uc01.sh  # PSS
./run-uc02.sh  # NetworkPolicy
./run-uc03.sh  # Security Context
```

## 📁 Structure

```
common-hardening/
├── README.md
├── run-all.sh
├── test-cases/
│   ├── run-uc01.sh
│   ├── run-uc02.sh
│   ├── run-uc03.sh
│   └── UC0*.md (documentation)
└── values/
    ├── uc01-pod-security.yaml
    ├── uc02-network-policy.yaml
    └── uc03-security-context.yaml
```

## 📚 References

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)

## 🎓 Best Practices

1. **Always use restricted PSS** in production
2. **Default deny NetworkPolicies** with explicit allows
3. **Drop ALL capabilities** unless specifically needed
4. **Use seccomp RuntimeDefault** profile
5. **Run as non-root** (runAsNonRoot: true)
