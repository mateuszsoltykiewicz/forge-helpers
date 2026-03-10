# UC-KEDA-03: External Scaler (Prometheus)

## Overview

Tests KEDA external scaler with Prometheus metrics for custom application metrics.

**Duration**: ~10 minutes

## Test Objectives

1. ✅ Deploy ScaledObject with Prometheus trigger
2. ✅ Configure Prometheus query
3. ✅ Verify metric collection
4. ✅ Test scaling based on custom metrics
5. ✅ Validate threshold behavior

## Use Cases

- HTTP requests per second
- Queue depth scaling
- Custom business metrics

## References

- [KEDA Prometheus Scaler](https://keda.sh/docs/scalers/prometheus/)
