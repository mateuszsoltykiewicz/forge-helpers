#!/bin/bash
# ==============================================================================
# Debug Proxy - Quick Access Script
# ==============================================================================
#
# This script creates a debug job to access a pod via the proxy mechanism.
#
# Usage:
#   ./create-debug-job.sh <namespace> <pod-name> [command]
#
# Examples:
#   ./create-debug-job.sh production myapp-abc123
#   ./create-debug-job.sh production myapp-abc123 "ps aux; df -h"
#   ./create-debug-job.sh production myapp-abc123 "/bin/bash"
#
# ==============================================================================

set -euo pipefail

# Configuration
DEBUG_SERVICE_ACCOUNT="${DEBUG_SERVICE_ACCOUNT:-debug-proxy}"
DEBUG_NAMESPACE="${DEBUG_NAMESPACE:-kube-system}"
DEBUG_IMAGE="${DEBUG_IMAGE:-bitnami/kubectl:1.29}"
DEBUG_TTL="${DEBUG_TTL:-3600}"  # 1 hour

# Parse arguments
if [ $# -lt 2 ]; then
  echo "Usage: $0 <namespace> <pod-name> [command]"
  echo ""
  echo "Examples:"
  echo "  $0 production myapp-abc123"
  echo "  $0 production myapp-abc123 'ps aux'"
  echo "  $0 production myapp-abc123 '/bin/bash'"
  exit 1
fi

TARGET_NAMESPACE="$1"
TARGET_POD="$2"
COMMAND="${3:-/bin/sh}"

# Generate unique job name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JOB_NAME="debug-${TARGET_POD}-${TIMESTAMP}"

# Get current user
CURRENT_USER="${USER}@$(hostname)"

# Prompt for reason
echo "=============================================="
echo "Debug Proxy - Pod Access Request"
echo "=============================================="
echo "Target: ${TARGET_NAMESPACE}/${TARGET_POD}"
echo "Command: ${COMMAND}"
echo "User: ${CURRENT_USER}"
echo ""
read -p "Reason for access: " REASON
read -p "Incident ticket (optional): " INCIDENT

echo ""
echo "Creating debug job: ${JOB_NAME}"
echo ""

# Create the debug job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${DEBUG_NAMESPACE}
  labels:
    app.kubernetes.io/name: debug-proxy-job
    debug.forge.io/target-pod: ${TARGET_POD}
    debug.forge.io/target-namespace: ${TARGET_NAMESPACE}
    debug.forge.io/created-by: ${CURRENT_USER}
  annotations:
    description: "Controlled pod access via debug proxy"
    debug.forge.io/reason: "${REASON}"
    debug.forge.io/incident: "${INCIDENT:-none}"
    debug.forge.io/timestamp: "${TIMESTAMP}"
spec:
  ttlSecondsAfterFinished: ${DEBUG_TTL}
  activeDeadlineSeconds: 600
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: debug-proxy-job
    spec:
      serviceAccountName: ${DEBUG_SERVICE_ACCOUNT}
      restartPolicy: Never
      
      containers:
        - name: debug-exec
          image: ${DEBUG_IMAGE}
          
          command:
            - /bin/bash
            - -c
            - |
              set -euo pipefail
              
              echo "=============================================="
              echo "Debug Proxy Job"
              echo "=============================================="
              echo "Target: ${TARGET_NAMESPACE}/${TARGET_POD}"
              echo "Command: ${COMMAND}"
              echo "User: ${CURRENT_USER}"
              echo "Reason: ${REASON}"
              echo "Incident: ${INCIDENT:-none}"
              echo "Time: \$(date -u +%Y-%m-%dT%H:%M:%SZ)"
              echo "=============================================="
              echo ""
              
              # Verify target pod exists
              if ! kubectl get pod "${TARGET_POD}" -n "${TARGET_NAMESPACE}" &>/dev/null; then
                echo "ERROR: Pod ${TARGET_POD} not found in namespace ${TARGET_NAMESPACE}"
                exit 1
              fi
              
              # Get pod info
              echo "Pod Status:"
              kubectl get pod "${TARGET_POD}" -n "${TARGET_NAMESPACE}"
              echo ""
              
              # Execute command
              echo "Executing command..."
              echo ""
              
              kubectl exec -n "${TARGET_NAMESPACE}" "${TARGET_POD}" -- ${COMMAND}
              
              EXIT_CODE=\$?
              
              echo ""
              echo "=============================================="
              echo "Exit code: \$EXIT_CODE"
              echo "Completed: \$(date -u +%Y-%m-%dT%H:%M:%SZ)"
              echo "=============================================="
              
              exit \$EXIT_CODE
          
          resources:
            limits:
              cpu: 500m
              memory: 256Mi
            requests:
              cpu: 100m
              memory: 128Mi
          
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 1000
EOF

echo ""
echo "✅ Debug job created: ${JOB_NAME}"
echo ""
echo "View logs with:"
echo "  kubectl logs -f job/${JOB_NAME} -n ${DEBUG_NAMESPACE}"
echo ""
echo "Delete job when done:"
echo "  kubectl delete job ${JOB_NAME} -n ${DEBUG_NAMESPACE}"
echo ""

# Auto-follow logs
echo "Following logs..."
echo ""
kubectl logs -f job/${JOB_NAME} -n ${DEBUG_NAMESPACE}
