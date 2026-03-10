# UC-SECURITY-04: Scheduled Security Scans

## Overview

This Use Case validates automated, periodic security scanning using Kubernetes CronJobs with Trivy CLI. Enables continuous security monitoring without manual intervention.

## Test Objectives

1. **CronJob Deployment**: Create scheduled scan job
2. **Job Execution**: Verify scan job runs successfully  
3. **Report Generation**: Validate scan reports created
4. **Multi-Namespace**: Scan images across namespaces
5. **History Management**: Verify job history retention

## Quick Start

```bash
# Install with test schedule (every 5 minutes)
helm install security-scans charts/common-security \
  -f values/uc04-scheduled-scan.yaml \
  --set scheduledScans.cronjob.schedule="*/5 * * * *" \
  -n security-system \
  --create-namespace
  
# Wait for first job
kubectl wait --for=condition=complete --timeout=600s \
  job/security-scan-$(date +%s) -n security-system
  
# View report
kubectl get configmap security-scan-report -n security-system -o yaml
```

## Real-World Schedules

```yaml
# Production: Daily at 2 AM
schedule: "0 2 * * *"

# Staging: Twice daily (2 AM, 2 PM)
schedule: "0 2,14 * * *"

# Development: Weekly on Sunday at 3 AM
schedule: "0 3 * * 0"

# High-security: Every 4 hours
schedule: "0 */4 * * *"
```

## References

- [Trivy CLI Documentation](https://aquasecurity.github.io/trivy/)
- [Kubernetes CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
