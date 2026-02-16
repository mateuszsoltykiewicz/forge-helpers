# Forge Operator: Hybrid Architecture (KOPF + Job-Based Execution)

**Breaking the Traditional Operator Pattern**

---

## 🎯 The Paradigm Shift

### Traditional Operator Architecture ❌

```
┌──────────────────────────────────────────────────┐
│         Monolithic Operator Pod                  │
│                                                  │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   │
│  │  Watch   │ → │Reconcile │ → │  Apply   │   │
│  │Resources │   │  Logic   │   │ Changes  │   │
│  └──────────┘   └──────────┘   └──────────┘   │
│                                                  │
│  • Heavy runtime (Go/Python)                    │
│  • All logic in one pod                         │
│  • Hard to scale                                │
│  • No parallel reconciliation                   │
└──────────────────────────────────────────────────┘
```

**Problems:**
- 🐌 Slow startup (runtime initialization)
- 📦 Large container images (500MB+)
- ⚠️ Single point of failure (one pod does everything)
- 🚫 Cannot parallelize (reconciliation is serial)
- 💸 Expensive (always running, even when idle)

---

### Forge Operator: Hybrid Architecture ✅

```
┌─────────────────────────────────────────────────────────────────┐
│                    KOPF Orchestrator Pod                        │
│                    (Lightweight, Always Running)                │
│                                                                 │
│  ┌──────────┐   ┌──────────────┐   ┌───────────────────┐     │
│  │  Watch   │ → │Event Handler │ → │ Create K8s Job    │     │
│  │Resources │   │ (KOPF)       │   │ (Delegate Work)   │     │
│  └──────────┘   └──────────────┘   └───────────────────┘     │
│                                              │                  │
│  • Python (KOPF framework)                   │                  │
│  • Webhooks (validation/mutation)            │                  │
│  • Database connections (state tracking)     │                  │
│  • Job orchestration ONLY                    ▼                  │
└──────────────────────────────────────────────┬──────────────────┘
                                               │
        ┌──────────────────────────────────────┴──────────────────────┐
        │                                                              │
        ▼                              ▼                              ▼
┌───────────────────┐        ┌───────────────────┐        ┌───────────────────┐
│  Kubernetes Job   │        │  Kubernetes Job   │        │  Kubernetes Job   │
│  (Bash Worker)    │        │  (Bash Worker)    │        │  (Bash Worker)    │
│                   │        │                   │        │                   │
│  • Bash scripts   │        │  • Bash scripts   │        │  • Bash scripts   │
│  • kubectl        │        │  • kubectl        │        │  • kubectl        │
│  • Fast startup   │        │  • Fast startup   │        │  • Fast startup   │
│  • ~50MB image    │        │  • ~50MB image    │        │  • ~50MB image    │
│  • Parallel exec  │        │  • Parallel exec  │        │  • Parallel exec  │
│                   │        │                   │        │                   │
│  Task: Harden     │        │  Task: Verify     │        │  Task: Delete     │
│  namespace-1      │        │  namespace-2      │        │  namespace-3      │
└───────────────────┘        └───────────────────┘        └───────────────────┘
   (Completes, exits)          (Completes, exits)          (Completes, exits)
```

**Advantages:**
- ⚡ **Fast**: Bash jobs start in <1s
- 📦 **Lightweight**: 50MB job images vs 500MB operator
- 🔄 **Parallel**: Multiple jobs run simultaneously
- 💰 **Cost-efficient**: Jobs only run when needed (no idle resource consumption)
- 🛡️ **Resilient**: Job failures don't crash orchestrator
- 🔌 **Best of both worlds**: KOPF features + Bash performance

---

## 🏗️ Architecture Components

### 1. KOPF Orchestrator (Always Running)

**Purpose:** Event-driven orchestration only

**Technology:**
- Python + KOPF framework
- Small footprint (~100MB container)
- Handles webhooks, watches, event routing

**Responsibilities:**
- ✅ Watch Kubernetes resources (Namespaces, custom CRDs)
- ✅ Validate resource changes (admission webhooks)
- ✅ Mutate resources (defaulting, labeling)
- ✅ Database connections (state tracking, audit logs)
- ✅ Job creation and monitoring
- ✅ Prometheus metrics exposure
- ❌ **NOT** doing actual work (hardening, verification, etc.)

**Container:**
```dockerfile
FROM python:3.11-slim

# Install KOPF and dependencies
RUN pip install --no-cache-dir \
    kopf==1.36.2 \
    kubernetes==28.1.0 \
    psycopg2-binary==2.9.9 \
    prometheus-client==0.19.0

# Copy orchestrator code
COPY orchestrator/main.py /app/
COPY orchestrator/handlers.py /app/
COPY orchestrator/jobs.py /app/

WORKDIR /app

# Non-root user
RUN useradd -m -u 1000 forge && chown -R forge:forge /app
USER forge

# Health check
HEALTHCHECK --interval=30s --timeout=5s \
  CMD python -c "import requests; requests.get('http://localhost:8080/healthz')"

ENTRYPOINT ["kopf", "run", "main.py", "--verbose"]
```

**Image Size:** ~150MB (Python + KOPF + dependencies)

---

### 2. Bash Worker Jobs (On-Demand)

**Purpose:** Execute actual operations

**Technology:**
- Alpine Linux + Bash + kubectl
- Ultra-lightweight (~50MB)
- Fast startup (<1 second)

**Responsibilities:**
- ✅ Namespace hardening (measure resources, apply quotas)
- ✅ Namespace verification (compliance checks)
- ✅ Namespace deletion (cleanup)
- ✅ Emergency quota updates
- ✅ VPA/HPA/Goldilocks detection
- ✅ Vault bundle creation

**Container:**
```dockerfile
FROM alpine:3.19

# Install minimal dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    bc \
    coreutils \
    && rm -rf /var/cache/apk/*

# Install kubectl
ARG KUBECTL_VERSION=v1.29.1
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Copy all Forge scripts and libraries
COPY scripts/ /opt/forge/scripts/
COPY lib/ /opt/forge/lib/

WORKDIR /opt/forge

# Non-root user
RUN addgroup -g 1000 forge && \
    adduser -D -u 1000 -G forge forge && \
    chown -R forge:forge /opt/forge
USER forge

# Jobs will use this as entrypoint
ENTRYPOINT ["/bin/bash"]
```

**Image Size:** ~48MB (Alpine + kubectl + scripts)

---

## 🔄 How It Works

### Reconciliation Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         1. Event Triggers                               │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
    ┌────────────────────────────────┼────────────────────────────────┐
    │                                │                                │
    ▼                                ▼                                ▼
Namespace          ResourceQuota              ConfigMap
Created            Deleted (drift!)           Updated

                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    2. KOPF Handler (Orchestrator)                       │
│                                                                         │
│  @kopf.on.create('namespaces')                                         │
│  def namespace_created(spec, name, **kwargs):                          │
│      # Validate: Check if managed by Forge                             │
│      if spec.get('labels', {}).get('moai.forge.io/managed') != 'true': │
│          return  # Ignore non-managed namespaces                       │
│                                                                         │
│      # Log to database                                                 │
│      db.insert_event(name, 'created', timestamp=now())                 │
│                                                                         │
│      # Delegate to Job                                                 │
│      create_hardening_job(namespace=name, grace_period='4h')           │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    3. Kubernetes Job Creation                           │
│                                                                         │
│  apiVersion: batch/v1                                                  │
│  kind: Job                                                             │
│  metadata:                                                             │
│    name: harden-my-app-abc123                                          │
│    namespace: forge-system                                             │
│  spec:                                                                 │
│    ttlSecondsAfterFinished: 3600  # Auto-cleanup after 1 hour         │
│    template:                                                           │
│      spec:                                                             │
│        restartPolicy: OnFailure                                        │
│        containers:                                                     │
│        - name: worker                                                  │
│          image: forge-worker:v2.0.0                                    │
│          command:                                                      │
│          - /opt/forge/scripts/namespace-hardening.sh                   │
│          args:                                                         │
│          - --name=my-app                                               │
│          - --grace-period=4h                                           │
│          env:                                                          │
│          - name: LOG_LEVEL                                             │
│            value: "info"                                               │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    4. Job Executes (Bash Script)                        │
│                                                                         │
│  #!/bin/bash                                                           │
│  set -euo pipefail                                                     │
│                                                                         │
│  source /opt/forge/lib/forge-namespace-hardening.sh                    │
│                                                                         │
│  namespace="$1"                                                        │
│                                                                         │
│  # Measure resources                                                   │
│  measure_namespace_resources "$namespace"                              │
│                                                                         │
│  # Apply hardening                                                     │
│  apply_resource_quota "$namespace" "$cpu" "$memory" "$pods"            │
│  apply_network_policy "$namespace"                                     │
│                                                                         │
│  # Update labels                                                       │
│  kubectl label namespace "$namespace" \                                │
│    moai.forge.io/hardened=true \                                       │
│    moai.forge.io/hardened-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"          │
│                                                                         │
│  exit 0  # Job completes, pod terminates                               │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    5. Orchestrator Monitors Job                         │
│                                                                         │
│  @kopf.on.update('jobs', namespace='forge-system')                     │
│  def job_status_changed(name, status, **kwargs):                      │
│      if status.get('succeeded') == 1:                                  │
│          # Job succeeded                                               │
│          db.update_event(name, status='completed')                     │
│          emit_metric('forge_job_success', labels={'job': name})        │
│      elif status.get('failed') > 0:                                    │
│          # Job failed                                                  │
│          db.update_event(name, status='failed')                        │
│          emit_metric('forge_job_failure', labels={'job': name})        │
│          # Create alert                                                │
│          send_alert(f"Job {name} failed!")                             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 💡 KOPF Orchestrator Implementation

### Main Orchestrator (`orchestrator/main.py`)

```python
#!/usr/bin/env python3
"""
Forge Operator Orchestrator
Lightweight event handler that delegates work to Kubernetes Jobs
"""

import kopf
import kubernetes
import logging
from datetime import datetime, timedelta
from jobs import create_hardening_job, create_verification_job, create_deletion_job
from database import DB

# Initialize
logging.basicConfig(level=logging.INFO)
db = DB()
k8s_batch = kubernetes.client.BatchV1Api()
k8s_core = kubernetes.client.CoreV1Api()

# Operator configuration
FORGE_NAMESPACE = "forge-system"
WORKER_IMAGE = "forge-worker:v2.0.0"
GRACE_PERIOD_HOURS = 4


@kopf.on.startup()
def configure(settings: kopf.OperatorSettings, **_):
    """Configure KOPF operator settings"""
    settings.persistence.finalizer = 'moai.forge.io/finalizer'
    settings.persistence.progress_storage = kopf.AnnotationsProgressStorage()
    settings.posting.level = logging.INFO
    
    logging.info("Forge Operator started")
    logging.info(f"Worker image: {WORKER_IMAGE}")
    logging.info(f"Grace period: {GRACE_PERIOD_HOURS}h")


@kopf.on.create('namespaces')
def namespace_created(spec, name, labels, meta, **kwargs):
    """
    Handle namespace creation events
    Schedules hardening job after grace period
    """
    # Only process managed namespaces
    if labels.get('moai.forge.io/managed') != 'true':
        logging.debug(f"Ignoring unmanaged namespace: {name}")
        return
    
    namespace_type = labels.get('moai.forge.io/type', 'application')
    
    logging.info(f"Namespace created: {name} (type: {namespace_type})")
    
    # Log to database
    db.insert_event(
        namespace=name,
        event_type='created',
        timestamp=datetime.utcnow(),
        metadata={'type': namespace_type}
    )
    
    # Schedule hardening job (delayed by grace period)
    grace_seconds = GRACE_PERIOD_HOURS * 3600
    
    job_name = create_hardening_job(
        namespace=name,
        grace_period_seconds=grace_seconds,
        worker_image=WORKER_IMAGE
    )
    
    logging.info(f"Scheduled hardening job: {job_name} (in {GRACE_PERIOD_HOURS}h)")
    
    return {'job': job_name, 'grace_period': f'{GRACE_PERIOD_HOURS}h'}


@kopf.on.field('namespaces', field='metadata.labels', 
               labels={'moai.forge.io/hardened': 'false'})
def namespace_unhardened_for_too_long(**kwargs):
    """
    Watch for namespaces that remain unhardened beyond grace period
    Trigger immediate hardening
    """
    name = kwargs['name']
    meta = kwargs['meta']
    
    creation_time = datetime.fromisoformat(
        meta['creationTimestamp'].replace('Z', '+00:00')
    )
    
    age = datetime.now(creation_time.tzinfo) - creation_time
    grace_period = timedelta(hours=GRACE_PERIOD_HOURS)
    
    if age > grace_period:
        logging.warning(
            f"Namespace {name} unhardened for {age.total_seconds()/3600:.1f}h "
            f"(grace period: {GRACE_PERIOD_HOURS}h)"
        )
        
        # Create immediate hardening job
        job_name = create_hardening_job(
            namespace=name,
            grace_period_seconds=0,  # Immediate
            worker_image=WORKER_IMAGE
        )
        
        logging.info(f"Created emergency hardening job: {job_name}")


@kopf.on.delete('v1', 'resourcequotas', 
                labels={'moai.forge.io/managed': 'true'})
def quota_deleted(namespace, name, **kwargs):
    """
    Handle ResourceQuota deletion (drift detection)
    Immediately recreate quota
    """
    logging.error(f"ResourceQuota deleted in {namespace}: {name} (DRIFT DETECTED!)")
    
    # Log to database
    db.insert_event(
        namespace=namespace,
        event_type='quota_deleted',
        timestamp=datetime.utcnow(),
        metadata={'quota_name': name, 'severity': 'critical'}
    )
    
    # Create remediation job (immediate)
    job_name = create_hardening_job(
        namespace=namespace,
        grace_period_seconds=0,
        worker_image=WORKER_IMAGE,
        reason='remediation'
    )
    
    logging.info(f"Created remediation job: {job_name}")
    
    # Send alert
    send_alert(
        severity='critical',
        message=f"ResourceQuota deleted in namespace {namespace}, auto-remediation triggered"
    )


@kopf.timer('namespaces', interval=3600.0, 
            labels={'moai.forge.io/managed': 'true', 'moai.forge.io/hardened': 'true'})
def verify_namespace_compliance(name, **kwargs):
    """
    Periodic compliance verification (every hour)
    Creates verification job
    """
    logging.debug(f"Scheduling compliance check for namespace: {name}")
    
    job_name = create_verification_job(
        namespace=name,
        worker_image=WORKER_IMAGE
    )
    
    logging.debug(f"Created verification job: {job_name}")


@kopf.on.update('batch', 'v1', 'jobs', namespace=FORGE_NAMESPACE,
                labels={'moai.forge.io/managed': 'true'})
def job_status_updated(name, status, labels, **kwargs):
    """
    Monitor job completion
    Update database, emit metrics, handle failures
    """
    job_type = labels.get('moai.forge.io/job-type', 'unknown')
    target_namespace = labels.get('moai.forge.io/target-namespace', 'unknown')
    
    succeeded = status.get('succeeded', 0)
    failed = status.get('failed', 0)
    
    if succeeded > 0:
        logging.info(f"Job completed successfully: {name} ({job_type} on {target_namespace})")
        
        db.update_job_status(
            job_name=name,
            status='completed',
            completed_at=datetime.utcnow()
        )
        
        # Emit Prometheus metric
        emit_metric('forge_job_success_total', labels={'type': job_type})
        
    elif failed > 0:
        logging.error(f"Job failed: {name} ({job_type} on {target_namespace})")
        
        # Get failure logs
        try:
            pod_name = get_job_pod_name(name)
            logs = k8s_core.read_namespaced_pod_log(
                name=pod_name,
                namespace=FORGE_NAMESPACE,
                tail_lines=50
            )
            
            db.update_job_status(
                job_name=name,
                status='failed',
                failed_at=datetime.utcnow(),
                logs=logs
            )
            
            # Send alert with logs
            send_alert(
                severity='error',
                message=f"Job {name} failed in namespace {target_namespace}",
                logs=logs
            )
            
        except Exception as e:
            logging.error(f"Failed to retrieve logs for {name}: {e}")
        
        # Emit metric
        emit_metric('forge_job_failure_total', labels={'type': job_type})


@kopf.on.validate('namespaces')
def validate_namespace(spec, name, operation, **kwargs):
    """
    Admission webhook: Validate namespace creation/updates
    """
    if operation == 'CREATE':
        labels = spec.get('labels', {})
        
        # Require namespace type if managed
        if labels.get('moai.forge.io/managed') == 'true':
            if 'moai.forge.io/type' not in labels:
                raise kopf.AdmissionError(
                    "Managed namespaces must have 'moai.forge.io/type' label"
                )
            
            namespace_type = labels['moai.forge.io/type']
            valid_types = [
                'application', 'middleware', 'forge-operator', 'forge-jobs',
                'keda', 'kyverno', 'vault', 'system', 'monitoring', 'logging',
                'ingress', 'storage', 'default', 'kube-system', 'argocd',
                'cert-manager', 'privileged'
            ]
            
            if namespace_type not in valid_types:
                raise kopf.AdmissionError(
                    f"Invalid namespace type: {namespace_type}. "
                    f"Must be one of: {', '.join(valid_types)}"
                )
    
    logging.debug(f"Validated namespace: {name}")


@kopf.on.mutate('namespaces')
def mutate_namespace(spec, name, operation, **kwargs):
    """
    Admission webhook: Mutate namespace (set defaults)
    """
    if operation == 'CREATE':
        labels = spec.get('labels', {})
        
        # Auto-label managed namespaces
        if labels.get('moai.forge.io/managed') == 'true':
            # Set hardened=false initially
            if 'moai.forge.io/hardened' not in labels:
                spec.setdefault('labels', {})['moai.forge.io/hardened'] = 'false'
            
            # Set default type
            if 'moai.forge.io/type' not in labels:
                spec['labels']['moai.forge.io/type'] = 'application'
            
            logging.info(f"Mutated namespace {name}: added default labels")


def send_alert(severity, message, logs=None):
    """Send alert via configured channels (Slack, PagerDuty, etc.)"""
    # Implementation depends on your alerting infrastructure
    logging.warning(f"ALERT [{severity}]: {message}")
    
    # Example: Send to Slack
    # slack_client.send_message(channel='#forge-alerts', text=message)


def emit_metric(metric_name, labels=None):
    """Emit Prometheus metric"""
    from prometheus_client import Counter, Gauge
    
    # Example: Increment counter
    counter = Counter(metric_name, 'Forge operator metric', labelnames=labels.keys())
    counter.labels(**labels).inc()


def get_job_pod_name(job_name):
    """Get pod name for a job"""
    pods = k8s_core.list_namespaced_pod(
        namespace=FORGE_NAMESPACE,
        label_selector=f'job-name={job_name}'
    )
    
    if pods.items:
        return pods.items[0].metadata.name
    
    raise Exception(f"No pod found for job {job_name}")
```

---

### Job Creation (`orchestrator/jobs.py`)

```python
"""
Job creation utilities
Generates Kubernetes Job manifests for worker tasks
"""

import kubernetes
from kubernetes.client import V1Job, V1JobSpec, V1PodTemplateSpec, V1PodSpec
from kubernetes.client import V1Container, V1EnvVar, V1ObjectMeta
from datetime import datetime
import hashlib

k8s_batch = kubernetes.client.BatchV1Api()

FORGE_NAMESPACE = "forge-system"


def create_hardening_job(namespace, grace_period_seconds, worker_image, reason='scheduled'):
    """
    Create a Kubernetes Job to harden a namespace
    
    Args:
        namespace: Target namespace to harden
        grace_period_seconds: Delay before execution (use 0 for immediate)
        worker_image: Docker image for worker container
        reason: 'scheduled', 'manual', or 'remediation'
    
    Returns:
        str: Job name
    """
    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    job_name = f"harden-{namespace}-{timestamp}"
    
    job = V1Job(
        api_version="batch/v1",
        kind="Job",
        metadata=V1ObjectMeta(
            name=job_name,
            namespace=FORGE_NAMESPACE,
            labels={
                'moai.forge.io/managed': 'true',
                'moai.forge.io/job-type': 'hardening',
                'moai.forge.io/target-namespace': namespace,
                'moai.forge.io/reason': reason
            },
            annotations={
                'moai.forge.io/created-at': datetime.utcnow().isoformat() + 'Z',
                'moai.forge.io/grace-period': str(grace_period_seconds)
            }
        ),
        spec=V1JobSpec(
            ttl_seconds_after_finished=3600,  # Auto-cleanup after 1 hour
            backoff_limit=3,  # Retry up to 3 times
            template=V1PodTemplateSpec(
                metadata=V1ObjectMeta(
                    labels={
                        'moai.forge.io/job-type': 'hardening',
                        'moai.forge.io/target-namespace': namespace
                    }
                ),
                spec=V1PodSpec(
                    restart_policy="OnFailure",
                    service_account_name="forge-worker",
                    containers=[
                        V1Container(
                            name="worker",
                            image=worker_image,
                            command=["/bin/bash"],
                            args=[
                                "-c",
                                f"sleep {grace_period_seconds} && "
                                f"/opt/forge/scripts/namespace-hardening.sh --name {namespace}"
                            ],
                            env=[
                                V1EnvVar(name="LOG_LEVEL", value="info"),
                                V1EnvVar(name="TARGET_NAMESPACE", value=namespace),
                                V1EnvVar(name="REASON", value=reason)
                            ]
                        )
                    ]
                )
            )
        )
    )
    
    k8s_batch.create_namespaced_job(namespace=FORGE_NAMESPACE, body=job)
    
    return job_name


def create_verification_job(namespace, worker_image):
    """
    Create a Kubernetes Job to verify namespace compliance
    """
    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    job_name = f"verify-{namespace}-{timestamp}"
    
    job = V1Job(
        api_version="batch/v1",
        kind="Job",
        metadata=V1ObjectMeta(
            name=job_name,
            namespace=FORGE_NAMESPACE,
            labels={
                'moai.forge.io/managed': 'true',
                'moai.forge.io/job-type': 'verification',
                'moai.forge.io/target-namespace': namespace
            }
        ),
        spec=V1JobSpec(
            ttl_seconds_after_finished=1800,  # Cleanup after 30 minutes
            template=V1PodTemplateSpec(
                spec=V1PodSpec(
                    restart_policy="Never",
                    service_account_name="forge-worker",
                    containers=[
                        V1Container(
                            name="worker",
                            image=worker_image,
                            command=["/bin/bash"],
                            args=[
                                "/opt/forge/scripts/namespace-verify.sh",
                                "--name", namespace
                            ],
                            env=[
                                V1EnvVar(name="LOG_LEVEL", value="info")
                            ]
                        )
                    ]
                )
            )
        )
    )
    
    k8s_batch.create_namespaced_job(namespace=FORGE_NAMESPACE, body=job)
    
    return job_name


def create_deletion_job(namespace, worker_image):
    """
    Create a Kubernetes Job to delete a namespace
    """
    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    job_name = f"delete-{namespace}-{timestamp}"
    
    job = V1Job(
        api_version="batch/v1",
        kind="Job",
        metadata=V1ObjectMeta(
            name=job_name,
            namespace=FORGE_NAMESPACE,
            labels={
                'moai.forge.io/managed': 'true',
                'moai.forge.io/job-type': 'deletion',
                'moai.forge.io/target-namespace': namespace
            }
        ),
        spec=V1JobSpec(
            ttl_seconds_after_finished=3600,
            template=V1PodTemplateSpec(
                spec=V1PodSpec(
                    restart_policy="Never",
                    service_account_name="forge-worker",
                    containers=[
                        V1Container(
                            name="worker",
                            image=worker_image,
                            command=["/bin/bash"],
                            args=[
                                "/opt/forge/scripts/namespace-delete.sh",
                                "--name", namespace,
                                "--force"
                            ],
                            env=[
                                V1EnvVar(name="LOG_LEVEL", value="info")
                            ]
                        )
                    ]
                )
            )
        )
    )
    
    k8s_batch.create_namespaced_job(namespace=FORGE_NAMESPACE, body=job)
    
    return job_name
```

---

## 🎯 Key Advantages

### 1. **Scalability Through Parallelization**

**Traditional Operator:**
```python
# Serial reconciliation
for namespace in namespaces:
    reconcile_namespace(namespace)  # Takes 30 seconds each
    # Total time for 100 namespaces: 50 minutes!
```

**Hybrid Operator:**
```python
# Parallel execution via Jobs
for namespace in namespaces:
    create_hardening_job(namespace)  # Creates job immediately
    # Jobs run in parallel
    # Total time for 100 namespaces: ~30 seconds (limited by K8s scheduler)
```

**Result:** 100× faster for bulk operations!

---

### 2. **Resource Efficiency (Pay-Per-Use)**

**Cost Comparison (100 namespaces/day):**

| Component | Traditional Operator | Hybrid Operator | Savings |
|-----------|---------------------|-----------------|---------|
| **Orchestrator** | N/A (monolithic) | 100MB, 50m CPU, 128Mi RAM | - |
| **Workers** | N/A | 100 jobs × 50MB × 30s each | - |
| **Total Running Time** | 24 hours/day | 1 hour orchestrator + 50 minutes jobs | - |
| **CPU Cost/Month** | 500m × 730h × $0.04 = **$14.60** | 50m × 730h × $0.04 = **$1.46** | **90% less** |
| **Memory Cost/Month** | 512Mi × 730h × $0.004 = **$1.50** | 128Mi × 730h × $0.004 = **$0.37** | **75% less** |
| **Total Cost/Month** | **$16.10** | **$1.83** | **$14.27 saved** |

**Per cluster per year: $171 saved**  
**Enterprise (50 clusters): $8,550/year saved**

---

### 3. **Fault Isolation**

**Traditional Operator:**
```
❌ Operator pod crashes → All reconciliation stops
❌ Bug in hardening logic → Operator crashes → Everything breaks
❌ OOM in one reconciliation → Entire operator dies
```

**Hybrid Operator:**
```
✅ Job fails → Only that namespace affected
✅ Bug in hardening logic → Job fails, orchestrator continues
✅ OOM in one job → Job restarts, others unaffected
✅ Orchestrator crash → Jobs continue running independently
```

---

### 4. **Debugging Simplicity**

**Traditional Operator:**
```bash
# Debugging: Need to attach debugger, read framework code, parse stack traces
kubectl logs -f deploy/operator -n forge-system
# Output: 10,000 lines of framework logs, hard to find actual error
```

**Hybrid Operator:**
```bash
# Debugging: Check individual job logs
kubectl logs -f job/harden-my-app-20260212123456 -n forge-system

# Output: Clean bash script output
# [INFO] Measuring namespace my-app
# [DEBUG] Found 3 VPAs
# [INFO] Total CPU: 15 cores
# [ERROR] VPA data age: 2 days (minimum: 7 days)
# [ERROR] Cannot harden yet, insufficient metrics
```

**Exact error, exact line, no framework noise!**

---

### 5. **KOPF Features (Best of Both Worlds)**

**What KOPF gives us:**

✅ **Admission Webhooks** (validate/mutate resources)
```python
@kopf.on.validate('namespaces')
def validate_namespace(spec, name, **kwargs):
    # Reject invalid namespace types
    if spec.get('labels', {}).get('moai.forge.io/type') not in VALID_TYPES:
        raise kopf.AdmissionError("Invalid type!")
```

✅ **Database Integration** (state tracking, audit logs)
```python
@kopf.on.create('namespaces')
def namespace_created(name, **kwargs):
    db.insert_event(name, 'created', timestamp=now())
    create_hardening_job(name)
```

✅ **Timers** (periodic reconciliation)
```python
@kopf.timer('namespaces', interval=3600.0)
def verify_compliance(name, **kwargs):
    create_verification_job(name)
```

✅ **Event Watching** (immediate drift detection)
```python
@kopf.on.delete('resourcequotas')
def quota_deleted(namespace, name, **kwargs):
    create_remediation_job(namespace)  # Immediate fix
```

✅ **Prometheus Metrics** (built-in)
```python
from prometheus_client import Counter
job_counter = Counter('forge_jobs_created', 'Total jobs created')
job_counter.inc()
```

---

## 📊 Performance Comparison

### Scenario: Harden 500 Namespaces

**Traditional Monolithic Operator:**
```
┌─────────────────────────────────────────┐
│  Operator Pod (1 replica)               │
│  ┌───────────────────────────────────┐  │
│  │ Reconcile Loop (serial)           │  │
│  │ for ns in namespaces:             │  │
│  │   harden(ns)  # 30s each          │  │
│  │                                   │  │
│  │ Total time: 500 × 30s = 4.2 hours│  │
│  └───────────────────────────────────┘  │
│  CPU: 500m (constant)                   │
│  Memory: 512Mi (constant)               │
└─────────────────────────────────────────┘
```

**Hybrid KOPF + Job Operator:**
```
┌──────────────────────────────────┐
│  KOPF Orchestrator (1 replica)   │
│  CPU: 50m                        │
│  Memory: 128Mi                   │
│  ┌────────────────────────────┐  │
│  │ Create 500 jobs            │  │
│  │ Time: 30 seconds           │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────┐
│  Kubernetes Job Parallelization                 │
│  (Limited by cluster capacity)                  │
│                                                 │
│  Batch 1 (50 jobs): 0-30s   ██████████         │
│  Batch 2 (50 jobs): 30-60s   ██████████        │
│  Batch 3 (50 jobs): 60-90s    ██████████       │
│  ... (10 batches)                               │
│  Batch 10 (50 jobs): 270-300s  ██████████      │
│                                                 │
│  Total time: ~5 minutes (50× faster!)          │
│  Peak CPU: 50m (orchestrator) + 2.5 cores (50 jobs × 50m)
│  Total CPU-hours: 0.25 cores × 5min = 0.02 core-hours
└─────────────────────────────────────────────────┘
```

**Result:**
- Traditional: **4.2 hours**, 2.1 core-hours consumed
- Hybrid: **5 minutes**, 0.02 core-hours consumed
- **Speedup: 50×**
- **Cost reduction: 100×**

---

## 🔐 RBAC Configuration

### Orchestrator ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: forge-orchestrator
  namespace: forge-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: forge-orchestrator
rules:
# Watch namespaces
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch", "update", "patch"]

# Watch ResourceQuotas (drift detection)
- apiGroups: [""]
  resources: ["resourcequotas"]
  verbs: ["get", "list", "watch"]

# Create/manage Jobs
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "create", "delete", "watch"]

# Read pod logs (for job monitoring)
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list"]

# Emit events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: forge-orchestrator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: forge-orchestrator
subjects:
- kind: ServiceAccount
  name: forge-orchestrator
  namespace: forge-system
```

### Worker ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: forge-worker
  namespace: forge-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: forge-worker
rules:
# Full access to namespaces (for hardening)
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "update", "patch", "delete"]

# Manage ResourceQuotas
- apiGroups: [""]
  resources: ["resourcequotas"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]

# Manage NetworkPolicies
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]

# Read VPAs (for detection)
- apiGroups: ["autoscaling.k8s.io"]
  resources: ["verticalpodautoscalers"]
  verbs: ["get", "list"]

# Read HPAs
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list"]

# Read workloads (Deployments, StatefulSets, DaemonSets)
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets"]
  verbs: ["get", "list"]

# Read pods
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]

# Read nodes (for DaemonSet calculations)
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]

# Read Karpenter NodePools (for max capacity detection)
- apiGroups: ["karpenter.sh"]
  resources: ["nodepools"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: forge-worker
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: forge-worker
subjects:
- kind: ServiceAccount
  name: forge-worker
  namespace: forge-system
```

---

## 🚀 Deployment

### Helm Chart Structure

```
forge-operator/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── orchestrator/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   └── configmap.yaml
│   ├── worker/
│   │   ├── serviceaccount.yaml
│   │   └── configmap.yaml
│   ├── rbac/
│   │   ├── orchestrator-clusterrole.yaml
│   │   ├── orchestrator-clusterrolebinding.yaml
│   │   ├── worker-clusterrole.yaml
│   │   └── worker-clusterrolebinding.yaml
│   ├── webhooks/
│   │   ├── validatingwebhookconfiguration.yaml
│   │   └── mutatingwebhookconfiguration.yaml
│   └── monitoring/
│       ├── servicemonitor.yaml
│       └── prometheusrule.yaml
```

### Orchestrator Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: forge-orchestrator
  namespace: forge-system
spec:
  replicas: 2  # HA
  selector:
    matchLabels:
      app: forge-orchestrator
  template:
    metadata:
      labels:
        app: forge-orchestrator
    spec:
      serviceAccountName: forge-orchestrator
      containers:
      - name: orchestrator
        image: forge-orchestrator:v2.0.0
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9090
          name: metrics
        env:
        - name: FORGE_NAMESPACE
          value: "forge-system"
        - name: WORKER_IMAGE
          value: "forge-worker:v2.0.0"
        - name: GRACE_PERIOD_HOURS
          value: "4"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: forge-db-credentials
              key: url
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

---

## 📈 Monitoring & Observability

### Prometheus Metrics

**Orchestrator Metrics:**
```
forge_namespaces_total{managed="true"} 450
forge_namespaces_hardened_total 420
forge_namespaces_unhardened_total 30

forge_jobs_created_total{type="hardening"} 1250
forge_jobs_created_total{type="verification"} 8200
forge_jobs_created_total{type="deletion"} 85

forge_jobs_success_total{type="hardening"} 1245
forge_jobs_failure_total{type="hardening"} 5

forge_drift_detected_total{resource="resourcequota"} 12
forge_remediation_triggered_total 12
```

**Grafana Dashboard:**
- Job success rate (last 24h)
- Average job duration by type
- Pending jobs count
- Failed jobs (with namespace drill-down)
- Drift detection events timeline

---

## ✅ Summary: Why This Architecture Wins

| Aspect | Traditional Operator | Bash Operator | **Hybrid (KOPF + Jobs)** |
|--------|---------------------|---------------|--------------------------|
| **Startup Time** | 5-30s | <1s | **Orchestrator: 5s, Jobs: <1s** |
| **Container Size** | 500MB | 50MB | **Orchestrator: 150MB, Jobs: 50MB** |
| **Scalability** | Serial (slow) | Limited | **Parallel (100× faster)** |
| **Resource Cost** | $16/month | $1.60/month | **$1.83/month (Jobs pay-per-use!)** |
| **Fault Isolation** | ❌ Single point of failure | ✅ Per-script | **✅ Per-namespace (job-level)** |
| **Debugging** | Complex (frameworks) | Simple (bash logs) | **Simple (job logs, isolated)** |
| **Webhooks** | ✅ (requires framework) | ❌ (not feasible) | **✅ (KOPF built-in)** |
| **Database Integration** | ✅ (complex) | ❌ (not feasible) | **✅ (KOPF native)** |
| **Timers/Scheduling** | ✅ (framework-dependent) | ❌ (cron jobs?) | **✅ (KOPF decorators)** |
| **Drift Detection** | ✅ (watch events) | ❌ (not real-time) | **✅ (KOPF + immediate job)** |
| **Best For** | Complex state machines | Single-namespace ops | **Multi-namespace orchestration** |

---

## 🎯 Conclusion

**The hybrid architecture combines:**

1. **KOPF's strengths:**
   - Event-driven reconciliation
   - Admission webhooks (validation/mutation)
   - Database connections (audit logs)
   - Prometheus metrics
   - Timer-based scheduling

2. **Bash job's strengths:**
   - Fast startup (<1s)
   - Lightweight (50MB)
   - Parallel execution
   - Fault isolation
   - Pay-per-use efficiency

**Result: The best of both worlds!**

- ⚡ **50× faster** than traditional operators (parallel jobs)
- 💰 **90% cheaper** than monolithic operators (on-demand execution)
- 🛡️ **More resilient** (job failures don't crash orchestrator)
- 🔍 **Easier to debug** (isolated job logs)
- 🚀 **Production-ready** (KOPF is battle-tested)

**This is the future of Kubernetes operators for task-based workflows.**

---

**Document Version:** 2.0.0  
**Last Updated:** 2026-02-12  
**Author:** Forge Platform Team  
**Status:** Architectural Proposal
