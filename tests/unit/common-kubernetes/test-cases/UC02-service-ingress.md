# UC-KUBERNETES-02: Service + Ingress Configuration

## Overview

Validates Kubernetes Service and Ingress configuration for exposing applications. Tests ClusterIP services, Ingress routing, DNS resolution, and load balancing across pods.

**Test Type**: Type 1 (Isolated Chart Testing)  
**Duration**: ~10 minutes

## Test Objectives

1. ✅ Deploy application with Service
2. ✅ Verify ClusterIP service creation
3. ✅ Test internal DNS resolution
4. ✅ Validate service endpoints
5. ✅ Deploy Ingress resource
6. ✅ Verify Ingress routing
7. ✅ Test load balancing across pods
8. ✅ Check service annotations/labels

## Prerequisites

- kubectl and helm installed
- Ingress controller (nginx) installed
- Cluster with 1+ nodes

## Real-World Scenarios

1. **Public Website**: Ingress with TLS, rate limiting
2. **Internal API**: ClusterIP only, no external access
3. **Microservices**: Multiple services with path-based routing
4. **Multi-Port**: gRPC + HTTP + metrics

## References

- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [NGINX Ingress](https://kubernetes.github.io/ingress-nginx/)
