# UC-KEDA-01: CPU-based ScaledObject

## Overview

Tests KEDA ScaledObject with CPU-based autoscaling trigger. Similar to HPA but managed by KEDA operator.

**Duration**: ~10 minutes

## Test Objectives

1. ✅ Deploy KEDA ScaledObject with CPU trigger
2. ✅ Verify ScaledObject CRD creation
3. ✅ Generate CPU load
4. ✅ Observe automatic scaling
5. ✅ Verify scale-down after load ends

## Prerequisites

- KEDA operator installed: `kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml`
- Metrics server available

## References

- [KEDA Documentation](https://keda.sh/)
- [CPU Scaler](https://keda.sh/docs/scalers/cpu/)
