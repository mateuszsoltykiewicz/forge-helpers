#!/bin/bash
# ==============================================================================
# Interactive Debug Session via Proxy
# ==============================================================================
#
# Creates an interactive debug pod with kubectl access to target namespace.
# User can exec into multiple pods during the session.
#
# Usage:
#   ./create-debug-session.sh <target-namespace>
#
# Example:
#   ./create-debug-session.sh production
#
# Once inside the session:
#   kubectl get pods
#   kubectl exec -it <pod-name> -- /bin/sh
#   kubectl logs <pod-name>
#
# ==============================================================================

set -euo pipefail

# Configuration
DEBUG_SERVICE_ACCOUNT="${DEBUG_SERVICE_ACCOUNT:-debug-proxy}"
DEBUG_NAMESPACE="${DEBUG_NAMESPACE:-kube-system}"
DEBUG_IMAGE="${DEBUG_IMAGE:-nicolaka/netshoot:latest}"
DEBUG_TIMEOUT="${DEBUG_TIMEOUT:-1800}"  # 30 minutes

# Parse arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <target-namespace>"
  echo ""
  echo "Example:"
  echo "  $0 production"
  echo ""
  echo "This creates an interactive session where you can:"
  echo "  - List pods: kubectl get pods -n <namespace>"
  echo "  - Exec into pods: kubectl exec -it <pod> -- /bin/sh"
  echo "  - View logs: kubectl logs <pod>"
  exit 1
fi

TARGET_NAMESPACE="$1"

# Generate unique session name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SESSION_NAME="debug-session-${TIMESTAMP}"

# Get current user
CURRENT_USER="${USER}@$(hostname)"

# Prompt for reason
echo "=============================================="
echo "Debug Proxy - Interactive Session"
echo "=============================================="
echo "Target Namespace: ${TARGET_NAMESPACE}"
echo "User: ${CURRENT_USER}"
echo "Session timeout: ${DEBUG_TIMEOUT}s ($(($DEBUG_TIMEOUT / 60)) minutes)"
echo ""
read -p "Reason for access: " REASON
read -p "Incident ticket (optional): " INCIDENT

echo ""
echo "Creating debug session: ${SESSION_NAME}"
echo ""

# Create the debug pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${SESSION_NAME}
  namespace: ${DEBUG_NAMESPACE}
  labels:
    app.kubernetes.io/name: debug-proxy-pod
    debug.forge.io/target-namespace: ${TARGET_NAMESPACE}
    debug.forge.io/created-by: ${CURRENT_USER}
    debug.forge.io/session-type: interactive
  annotations:
    description: "Interactive debug session via proxy"
    debug.forge.io/reason: "${REASON}"
    debug.forge.io/incident: "${INCIDENT:-none}"
    debug.forge.io/timestamp: "${TIMESTAMP}"
spec:
  serviceAccountName: ${DEBUG_SERVICE_ACCOUNT}
  restartPolicy: Never
  activeDeadlineSeconds: ${DEBUG_TIMEOUT}
  
  containers:
    - name: debug-shell
      image: ${DEBUG_IMAGE}
      
      command:
        - /bin/bash
        - -c
        - |
          cat <<'BANNER'
          ============================================
          Debug Proxy - Interactive Session
          ============================================
          Target Namespace: ${TARGET_NAMESPACE}
          User: ${CURRENT_USER}
          Reason: ${REASON}
          Incident: ${INCIDENT:-none}
          Session expires in: ${DEBUG_TIMEOUT}s
          ============================================
          
          Available commands:
            kubectl get pods -n ${TARGET_NAMESPACE}
            kubectl exec -n ${TARGET_NAMESPACE} <pod> -- /bin/sh
            kubectl logs -n ${TARGET_NAMESPACE} <pod>
            kubectl describe pod -n ${TARGET_NAMESPACE} <pod>
          
          Tip: Use 'exit' to end the session
          ============================================
          BANNER
          
          export PS1="debug-proxy [${TARGET_NAMESPACE}]> "
          export TARGET_NS="${TARGET_NAMESPACE}"
          
          # Start bash session
          exec /bin/bash --norc --noprofile
      
      stdin: true
      tty: true
      
      env:
        - name: TARGET_NAMESPACE
          value: "${TARGET_NAMESPACE}"
        - name: DEBUG_USER
          value: "${CURRENT_USER}"
        - name: KUBECONFIG
          value: /var/run/secrets/kubernetes.io/serviceaccount/config
      
      resources:
        limits:
          cpu: 500m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 128Mi
      
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsNonRoot: true
        runAsUser: 1000
EOF

echo ""
echo "✅ Debug session created: ${SESSION_NAME}"
echo ""
echo "Waiting for pod to be ready..."

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/${SESSION_NAME} -n ${DEBUG_NAMESPACE} --timeout=60s

echo ""
echo "Attaching to session..."
echo "Press Ctrl+D or type 'exit' to end the session"
echo ""

# Attach to the pod
kubectl attach -it ${SESSION_NAME} -n ${DEBUG_NAMESPACE}

echo ""
echo "=============================================="
echo "Session ended"
echo "=============================================="
echo ""
echo "Session pod will auto-delete after timeout."
echo "To delete immediately:"
echo "  kubectl delete pod ${SESSION_NAME} -n ${DEBUG_NAMESPACE}"
echo ""
