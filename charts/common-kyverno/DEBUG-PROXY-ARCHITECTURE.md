# Debug Proxy Architecture Diagram

## High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────┐                                                        │
│  │   User   │                                                        │
│  │ (Alice)  │                                                        │
│  └────┬─────┘                                                        │
│       │                                                              │
│       │ (1) kubectl exec myapp-pod -- /bin/sh                       │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │ Kyverno         │                                                │
│  │ Admission       │  ❌ BLOCKED                                    │
│  │ Webhook         │  "kubectl exec not allowed"                    │
│  └─────────────────┘                                                │
│                                                                       │
│  ┌──────────┐                                                        │
│  │   User   │                                                        │
│  │ (Alice)  │                                                        │
│  └────┬─────┘                                                        │
│       │                                                              │
│       │ (2) debug-pod production myapp-pod "/bin/sh"                │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │ kubectl apply   │                                                │
│  │ Job manifest    │                                                │
│  └────┬────────────┘                                                │
│       │                                                              │
│       │ (3) RBAC check: Can Alice create Jobs?                      │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │ RBAC            │  ✅ ALLOWED (RoleBinding: sre-team)           │
│  │ Authorization   │                                                │
│  └────┬────────────┘                                                │
│       │                                                              │
│       │ (4) Job created                                             │
│       ▼                                                              │
│  ┌─────────────────────────────────────────────────────┐            │
│  │ Debug Job (Pod)                                     │            │
│  │                                                     │            │
│  │ ServiceAccount: debug-proxy                         │            │
│  │ Labels:                                             │            │
│  │   - created-by: alice@company.com                   │            │
│  │   - target-pod: myapp-pod                           │            │
│  │ Annotations:                                        │            │
│  │   - reason: "investigating memory leak"             │            │
│  │   - incident: "INC-12345"                           │            │
│  │                                                     │            │
│  │ Command:                                            │            │
│  │   kubectl exec myapp-pod -- /bin/sh                 │            │
│  └────┬────────────────────────────────────────────────┘            │
│       │                                                              │
│       │ (5) RBAC check: Can debug-proxy SA exec into pods?          │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │ RBAC            │  ✅ ALLOWED (ClusterRole: pods/exec)          │
│  │ Authorization   │                                                │
│  └────┬────────────┘                                                │
│       │                                                              │
│       │ (6) Check Kyverno: Is debug-proxy excluded?                 │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │ Kyverno         │  ✅ ALLOWED (excludeServiceAccounts)          │
│  │ Webhook         │                                                │
│  └────┬────────────┘                                                │
│       │                                                              │
│       │ (7) exec into target pod                                    │
│       ▼                                                              │
│  ┌─────────────────┐                                                │
│  │  Target Pod     │  ✅ EXEC SUCCESSFUL                           │
│  │  (myapp-pod)    │                                                │
│  └─────────────────┘                                                │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      Security Layers                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Layer 1: Kyverno Admission Control                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ClusterPolicy: block-pod-exec                              │  │
│  │                                                            │  │
│  │ Rules:                                                     │  │
│  │   - Block: pods/exec for all users                        │  │
│  │   - Except: ServiceAccount debug-proxy                    │  │
│  │   - Except: cluster-admin (break-glass)                   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  Layer 2: RBAC Authorization                                      │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ClusterRole: debug-proxy-exec                              │  │
│  │   - pods/exec: create                                      │  │
│  │   - pods: get, list                                        │  │
│  │   - pods/log: get                                          │  │
│  │                                                            │  │
│  │ ClusterRoleBinding:                                        │  │
│  │   ServiceAccount: debug-proxy → ClusterRole: debug-proxy  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Role: debug-job-creator                                    │  │
│  │   - jobs: create, get, list, delete                        │  │
│  │   - pods, pods/log: get, list                              │  │
│  │                                                            │  │
│  │ RoleBinding:                                               │  │
│  │   Group: sre-team → Role: debug-job-creator               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  Layer 3: Audit Trail                                             │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Job Metadata (Kubernetes audit logs)                       │  │
│  │   - metadata.labels:                                       │  │
│  │       debug.forge.io/created-by: user                      │  │
│  │       debug.forge.io/target-pod: pod-name                  │  │
│  │   - metadata.annotations:                                  │  │
│  │       debug.forge.io/reason: justification                 │  │
│  │       debug.forge.io/incident: ticket-number               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

## Sequence Diagram

```
User          kubectl      RBAC       Kyverno      Job         SA          Target
                                                             debug-proxy     Pod
│                │           │           │          │            │           │
│ exec pod ─────>│           │           │          │            │           │
│                │           │           │          │            │           │
│                │──────────────────────>│          │            │           │
│                │       (webhook)       │          │            │           │
│                │                       │          │            │           │
│                │<──────────────────────│          │            │           │
│<───────────────│    ❌ BLOCKED        │          │            │           │
│                │                       │          │            │           │
│ debug-pod ────>│                       │          │            │           │
│  production    │                       │          │            │           │
│  myapp-pod     │                       │          │            │           │
│                │                       │          │            │           │
│                │───────────>│          │          │            │           │
│                │  (RBAC)    │          │          │            │           │
│                │            │          │          │            │           │
│                │<───────────│          │          │            │           │
│                │ ✅ create  │          │          │            │           │
│                │    Job     │          │          │            │           │
│                │            │          │          │            │           │
│                │─────────────────────────────────>│            │           │
│                │       Job created                │            │           │
│                │                                  │            │           │
│                │                                  │────────────>│           │
│                │                                  │  exec cmd  │           │
│                │                                  │            │           │
│                │                                  │            │──────────>│
│                │                                  │            │  (RBAC)   │
│                │                                  │            │           │
│                │                                  │            │──────────>│
│                │                                  │            │ (Kyverno) │
│                │                                  │            │  check SA │
│                │                                  │            │           │
│                │                                  │            │           │
│                │                                  │            │  ✅ exec  │
│                │                                  │            │───────────>│
│                │                                  │            │           │
│                │                                  │            │<───────────│
│                │                                  │            │  output   │
│                │                                  │<────────────│           │
│                │<─────────────────────────────────│            │           │
│<───────────────│          logs                   │            │           │
│   output       │                                  │            │           │
│                │                                  │            │           │
```

## Access Control Matrix

```
┌─────────────────────┬──────────────┬──────────────┬──────────────┐
│ User/SA             │ Direct Exec  │ Create Job   │ Exec via Job │
├─────────────────────┼──────────────┼──────────────┼──────────────┤
│ Regular User        │ ❌ Blocked   │ ❌ No RBAC   │ ❌ Can't     │
│ (no permissions)    │              │              │              │
├─────────────────────┼──────────────┼──────────────┼──────────────┤
│ Developer           │ ❌ Blocked   │ ✅ RBAC      │ ✅ Via Job   │
│ (sre-team group)    │ (Kyverno)    │ (Role)       │              │
├─────────────────────┼──────────────┼──────────────┼──────────────┤
│ SA: debug-proxy     │ ✅ Allowed   │ N/A          │ ✅ Executes  │
│ (ServiceAccount)    │ (excluded)   │              │              │
├─────────────────────┼──────────────┼──────────────┼──────────────┤
│ cluster-admin       │ ✅ Allowed   │ ✅ Admin     │ ✅ Direct    │
│ (break-glass)       │ (excluded)   │              │              │
└─────────────────────┴──────────────┴──────────────┴──────────────┘
```

## Data Flow

```
1. User Request
   ↓
   User submits: debug-pod production myapp-pod "ps aux"
   ↓
   Script collects:
   - User: alice@company.com
   - Reason: "investigating CPU spike"
   - Incident: "INC-123"
   - Timestamp: 2026-02-21T14:30:22Z

2. Job Creation
   ↓
   kubectl apply Job manifest with:
   - ServiceAccount: debug-proxy
   - Labels: user, target-pod, target-namespace
   - Annotations: reason, incident, timestamp

3. RBAC Check
   ↓
   Can alice@company.com create Jobs?
   - RoleBinding: sre-team → debug-job-creator
   - Alice is in sre-team
   - ✅ Allowed

4. Job Execution
   ↓
   Job pod starts with:
   - ServiceAccount: debug-proxy
   - Command: kubectl exec myapp-pod -- ps aux

5. Nested RBAC Check
   ↓
   Can debug-proxy SA exec into pods?
   - ClusterRoleBinding: debug-proxy → debug-proxy-exec
   - ClusterRole allows: pods/exec
   - ✅ Allowed

6. Kyverno Check
   ↓
   Is debug-proxy SA excluded from exec block?
   - ClusterPolicy: block-pod-exec
   - excludeServiceAccounts: debug-proxy
   - ✅ Allowed

7. Execution
   ↓
   Command runs in target pod
   - Output captured
   - Streamed to user via kubectl logs

8. Audit Trail
   ↓
   Recorded:
   - Kubernetes audit log (Job creation)
   - Job metadata (user, reason, incident)
   - PolicyReport (Kyverno policy evaluation)
   - Prometheus metrics (job created)
```

## Security Boundaries

```
┌────────────────────────────────────────────────────────────┐
│ Security Boundary 1: Admission Control (Kyverno)           │
│                                                            │
│ ┌────────────────────────────────────────────────────┐    │
│ │ All direct kubectl exec attempts BLOCKED            │    │
│ │ Except:                                             │    │
│ │   - ServiceAccount: debug-proxy                     │    │
│ │   - User: cluster-admin                             │    │
│ └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ Security Boundary 2: Authorization (RBAC)                  │
│                                                            │
│ ┌────────────────────────────────────────────────────┐    │
│ │ Who can CREATE debug jobs?                         │    │
│ │   - Role: debug-job-creator                         │    │
│ │   - Bound to: sre-team, oncall-engineer            │    │
│ └────────────────────────────────────────────────────┘    │
│                                                            │
│ ┌────────────────────────────────────────────────────┐    │
│ │ What can debug-proxy SA do?                        │    │
│ │   - ClusterRole: debug-proxy-exec                   │    │
│ │   - Permissions: pods/exec, pods/log, pods get/list │    │
│ └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ Security Boundary 3: Auditability                          │
│                                                            │
│ ┌────────────────────────────────────────────────────┐    │
│ │ Every access recorded:                              │    │
│ │   - WHO: User identity                              │    │
│ │   - WHEN: Timestamp                                 │    │
│ │   - WHERE: Target pod/namespace                     │    │
│ │   - WHY: Business justification                     │    │
│ │   - INCIDENT: Ticket reference                      │    │
│ └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```
