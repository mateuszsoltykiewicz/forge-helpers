# UC-KEDA-02: Cron-based ScaledObject

## Overview

Tests KEDA cron scaler for schedule-based autoscaling (e.g., scale up during business hours).

**Duration**: ~8 minutes

## Test Objectives

1. ✅ Deploy ScaledObject with cron trigger
2. ✅ Verify cron schedule configuration
3. ✅ Test scale-up at specified time
4. ✅ Test scale-down at end time
5. ✅ Validate timezone handling

## Use Cases

- Business hours scaling (8 AM - 6 PM)
- Weekend vs weekday capacity
- Batch job scheduling

## References

- [KEDA Cron Scaler](https://keda.sh/docs/scalers/cron/)
