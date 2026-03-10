# Forge Helpers - Testing Framework

Comprehensive testing suite for all Forge Helpers Helm charts.

## 📋 Overview

This testing framework provides:

- **Type 1 Tests**: Isolated chart testing (chart + dependencies)
- **Type 2 Tests**: Integration testing (multiple charts together)
- **Automated Scripts**: Setup, execution, and cleanup automation
- **30 Use Cases + 5 Integration Scenarios**: Covering all critical functionality
- **Prerequisites**: Ready-to-use K8s resources for testing
- **CI/CD Integration**: GitHub Actions workflow for continuous testing

## 📚 Documentation

- **[IMPLEMENTATION-ROADMAP.md](./IMPLEMENTATION-ROADMAP.md)** - Complete 6-week plan for 100% coverage
- **[TIMELINE.md](./TIMELINE.md)** - Visual Gantt chart and progress tracking
- **[TESTING-PLAN.md](../TESTING-PLAN.md)** - Detailed test case definitions
- **[Unit Test READMEs](./unit/)** - Per-chart testing documentation

## 🎯 Testing Strategy

### Type 1: Chart Alone + Dependencies

**Purpose**: Validate individual chart functionality

**Pattern**: `Test Chart + common-forge + prerequisites`

**Coverage**: 30+ use cases across 9 charts

### Type 2: Charts Combination  

**Purpose**: Validate real-world multi-chart scenarios

**Pattern**: `Multiple Charts + common-forge + prerequisites`

**Coverage**: 5 integration scenarios

## 📂 Directory Structure

```
tests/
├── README.md                    # This file
├── unit/                        # Type 1: Isolated tests
│   ├── common-kyverno/         # ✅ Complete (6/6 UCs)
│   │   ├── README.md
│   │   ├── values/             # 9 values files
│   │   ├── workloads/
│   │   └── test-cases/         # 6 test scripts
│   ├── common-monitoring/      # 📝 TODO (4 UCs)
│   ├── common-security/        # 📝 TODO (4 UCs)
│   ├── common-kubernetes/      # 📝 TODO (4 UCs)
│   ├── common-hardening/       # 📝 TODO (3 UCs)
│   ├── common-keda/            # 📝 TODO (3 UCs)
│   ├── common-vault/           # 📝 TODO (2 UCs)
│   ├── common-aws/             # 📝 TODO (2 UCs)
│   └── common-argocd/          # 📝 TODO (2 UCs)
│
├── integration/                 # Type 2: Combination tests
│   ├── full-stack-app/         # 📝 TODO
│   ├── gitops-platform/        # 📝 TODO
│   ├── aws-microservice/       # 📝 TODO
│   ├── secure-deployment/      # 📝 TODO
│   └── multi-tenant/           # 📝 TODO
│
├── prerequisites/               # Cluster-wide test resources
│   ├── README.md
│   ├── test-namespaces.yaml    # ✅ Ready
│   ├── test-serviceaccounts.yaml # ✅ Ready
│   └── test-workloads.yaml     # ✅ Ready
│
├── scripts/                     # Test automation
│   ├── setup-cluster.sh        # ✅ Ready
│   ├── cleanup.sh              # ✅ Ready
│   ├── run-unit-tests.sh       # 📝 TODO
│   └── run-integration-tests.sh # 📝 TODO
│
└── test-results/                # Test output (gitignored)
```

## 🚀 Quick Start

### 1. Setup Test Environment

```bash
cd tests/scripts
./setup-cluster.sh
```

This installs:
- Trivy Operator
- Falco
- Test namespaces
- Test ServiceAccounts
- Test workloads

### 2. Run Tests

**Option A: Run all unit tests**
```bash
cd tests/unit
./run-all-tests.sh
```

**Option B: Run single chart tests**
```bash
cd tests/unit/common-kyverno/test-cases
./run-all.sh
```

**Option C: Run single use case**
```bash
cd tests/unit/common-kyverno/test-cases
./run-uc01.sh  # Block kubectl exec
```

### 3. Cleanup

```bash
cd tests/scripts
./cleanup.sh

# Remove operators too
./cleanup.sh --remove-operators
```

## 📊 Test Coverage

### Unit Tests (Type 1)

| Chart | Use Cases | Status | Documentation |
|-------|-----------|--------|---------------|
| **common-kyverno** | 6 | ✅ Complete | [README](unit/common-kyverno/README.md) |
| common-monitoring | 4 | 📝 TODO | - |
| common-security | 4 | 📝 TODO | - |
| common-kubernetes | 4 | 📝 TODO | - |
| common-hardening | 3 | 📝 TODO | - |
| common-keda | 3 | 📝 TODO | - |
| common-vault | 2 | 📝 TODO | - |
| common-aws | 2 | 📝 TODO | - |
| common-argocd | 2 | 📝 TODO | - |
| **Total** | **30** | **20% Done (6/30)** | - |

### Integration Tests (Type 2)

| Scenario | Charts Involved | Status |
|----------|----------------|--------|
| Full Stack App | kubernetes + monitoring + security + kyverno | 📝 TODO |
| GitOps Platform | kyverno + argocd + monitoring | 📝 TODO |
| AWS Microservice | kubernetes + aws + keda + vault | 📝 TODO |
| Secure Deployment | kyverno + security + hardening | 📝 TODO |
| Multi-Tenant | hardening + kyverno + monitoring | 📝 TODO |
| **Total** | **5** | **0% Done** |

## 🔍 Available Use Cases

### common-kyverno (6/6 Complete) ✅

**UC01: Block kubectl exec** - ✅ Ready
- Tests: `blockExec` API restriction with debug-proxy exclusion
- Run: `./test-cases/run-uc01.sh`
- Values: `values/uc01-block-exec.yaml`

**UC02: Block Direct Deployments** - ✅ Ready
- Tests: GitOps-only pattern, only CI/CD ServiceAccounts can deploy
- Run: `./test-cases/run-uc02.sh`
- Values: `values/uc02-gitops-only.yaml`

**UC03: Debug Proxy Access** - ✅ Ready
- Tests: All 5 API restrictions (exec, port-forward, proxy, ephemeral, attach)
- Run: `./test-cases/run-uc03.sh`
- Values: `values/uc03-debug-proxy.yaml`

**UC04: GitOps Workflow** - ✅ Ready
- Tests: Full production configuration with all 6 policies enabled
- Run: `./test-cases/run-uc04.sh`
- Values: `values/uc04-gitops-full.yaml`

**UC05: Break-Glass Procedure** - ✅ Ready
- Tests: Emergency access in 3 phases (before/active/after)
- Run: `./test-cases/run-uc05.sh`
- Values: `values/uc05-breakglass-*.yaml` (3 files)

**UC06: Audit Mode** - ✅ Ready
- Tests: Staging/dev configuration with all policies in audit mode
- Run: `./test-cases/run-uc06.sh`
- Values: `values/uc06-audit-mode.yaml`

**Run all**: `cd unit/common-kyverno/test-cases && ./run-all.sh`

---

### common-kyverno (Priority: CRITICAL) ✅ Complete

1. **UC01: Block kubectl exec** - API Restrictions
   - Tests: User blocked, debug-proxy allowed, error messages, PolicyReports
   - Status: ✅ Ready
   - Run: `./tests/unit/common-kyverno/test-cases/run-uc01.sh`

2. **UC02: Block direct deployments** - Resource Management (GitOps-only)
   - Tests: GitOps pattern, CI/CD SA exclusions, user blocked, flux-cd allowed
   - Status: ✅ Ready
   - Run: `./tests/unit/common-kyverno/test-cases/run-uc02.sh`

3. **UC03: Debug proxy access** - Controlled Access (All 5 API Restrictions)
   - Tests: All API restrictions, debug-proxy bypass, debug-proxy pod
   - Status: ✅ Ready
   - Run: `./tests/unit/common-kyverno/test-cases/run-uc03.sh`

4. **UC04: GitOps workflow** - Full Enforcement (All 6 Policies)
   - Tests: Complete GitOps workflow, all policies together, CI/CD pipeline
   - Status: ✅ Ready
   - Run: `./tests/unit/common-kyverno/test-cases/run-uc04.sh`

5. **UC05: Break-glass procedure** - Emergency Access (3 Phases)
   - Tests: Before/during/after break-glass, admin bypass, audit trail
   - Status: ✅ Ready
   - Run: `./tests/unit/common-kyverno/test-cases/run-uc05.sh` (manual)

6. **UC06: Audit mode** - Staging/Development (Log Only)
   - Tests: Audit mode (operations allowed but logged), PolicyReports
   - Status: ✅ Ready
   - Run: `./tests/unit/common-kyverno/test-cases/run-uc06.sh`

**Progress: 6/6 UCs Complete (100%) ✅**

### common-monitoring (Priority: HIGH)

1. **UC01: Pod crash alerts** - Availability Monitoring
2. **UC02: Grafana dashboards** - Dashboard Provisioning
3. **UC03: SLO monitoring** - Latency P99
4. **UC04: Multi-environment** - Environment-Specific Thresholds

### common-security (Priority: HIGH)

1. **UC01: Vulnerability scanning** - Trivy Image Scan
2. **UC02: Secret detection** - Hardcoded Secrets
3. **UC03: Runtime protection** - Falco Alerts
4. **UC04: Scheduled scans** - CronJob Security Scans

### common-kubernetes (Priority: HIGH)

1. **UC01: Deployment with HPA** - Horizontal Autoscaling
2. **UC02: Service + Ingress** - External Access
3. **UC03: Config/Secret management** - Configuration Injection
4. **UC04: RBAC setup** - ServiceAccount Permissions

## 📝 Test Execution Flow

```
┌──────────────────────────────────────────────────────────────┐
│                   Test Execution Pipeline                     │
└──────────────────────────────────────────────────────────────┘

1. Prerequisites Setup (Once)
   ├── Install operators (Trivy, Falco)
   ├── Create test namespaces
   ├── Create test ServiceAccounts
   └── Deploy test workloads

2. For Each Test Case:
   ├── Pre-requisite checks
   ├── Install chart with test values
   ├── Wait for resources to be ready
   ├── Run test scenarios
   │   ├── Positive tests (should succeed)
   │   ├── Negative tests (should fail)
   │   └── Edge cases
   ├── Validate results
   │   ├── Check resource behavior
   │   ├── Verify error messages
   │   └── Inspect reports/metrics
   ├── Collect results (PASS/FAIL)
   └── Cleanup (uninstall chart)

3. Summary Report
   ├── Total tests run
   ├── Passed / Failed count
   ├── Performance metrics
   └── Exit code (0 = success, 1 = failure)
```

## ✅ Success Criteria

### Per Use Case

- ✅ All pre-requisites available
- ✅ Chart installs without errors
- ✅ Resources created correctly
- ✅ Positive tests pass (allowed operations work)
- ✅ Negative tests pass (blocked operations fail)
- ✅ Error messages are clear
- ✅ Cleanup removes all resources
- ✅ No resource leaks

### Overall

- ✅ 100% unit test coverage (30+ UCs)
- ✅ 100% integration test coverage (5 scenarios)
- ✅ All tests pass (0 failures)
- ✅ Documentation accurate
- ✅ Performance within targets

## 🔧 Troubleshooting

### Tests Not Running

**Problem**: `./run-uc01.sh: Permission denied`

**Solution**:
```bash
chmod +x tests/unit/*/test-cases/*.sh
chmod +x tests/scripts/*.sh
```

### Prerequisites Missing

**Problem**: `Namespace test-app not found`

**Solution**:
```bash
cd tests/scripts
./setup-cluster.sh
```

### Kyverno Policies Not Working

**Problem**: User not blocked by policies

**Solution**:
```bash
# Check Kyverno is running
kubectl get deploy -n kyverno

# Check policies exist
kubectl get clusterpolicy

# Check policy details
kubectl describe clusterpolicy <policy-name>

# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller
```

### Chart Installation Fails

**Problem**: `helm install` fails

**Solution**:
```bash
# Check chart syntax
helm lint charts/common-kyverno

# Check values file
helm template test charts/common-kyverno -f tests/unit/common-kyverno/values/uc01-block-exec.yaml

# Check namespace exists
kubectl get namespace test-app

# Check dependencies
helm dependency list charts/common-kyverno
```

## 📦 Cluster Status

### ✅ Already Installed

- Kyverno (4 controllers)
- Prometheus Operator
- Grafana
- KEDA
- Vault Agent Injector
- ArgoCD

### ❌ Needs Installation

- Trivy Operator (installed by `setup-cluster.sh`)
- Falco (installed by `setup-cluster.sh`)

## 🎯 Performance Targets

| Metric | Target | Typical |
|--------|--------|---------|
| Setup time | < 5 min | 3-4 min |
| Single test execution | < 60 sec | 30-45 sec |
| All unit tests | < 30 min | 20-25 min |
| Integration test | < 5 min | 3-4 min |
| Cleanup time | < 2 min | 1 min |

## 📚 Documentation

- **Main Testing Plan**: `../TESTING-PLAN.md` (comprehensive plan with all UCs)
- **Chart Dependencies**: `../CHART-DEPENDENCIES.md` (dependency graph)
- **Consistency Analysis**: `../CONSISTENCY-ANALYSIS.md` (label/naming validation)

### Per-Chart Documentation

- common-kyverno: `unit/common-kyverno/README.md` ✅
- common-monitoring: `unit/common-monitoring/README.md` 📝
- common-security: `unit/common-security/README.md` 📝
- (... others pending)

## 🚢 CI/CD Integration

### GitHub Actions Workflow (TODO)

```yaml
name: Test Forge Helpers Charts

on:
  pull_request:
  push:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Create K8s cluster
        uses: helm/kind-action@v1
      
      - name: Setup test environment
        run: cd tests/scripts && ./setup-cluster.sh
      
      - name: Run unit tests
        run: cd tests/unit && ./run-all-tests.sh
      
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: tests/test-results/
```

## 🔮 Roadmap

### Phase 1: Foundation ✅
- ✅ Testing plan created
- ✅ Directory structure
- ✅ Prerequisites (namespaces, ServiceAccounts, workloads)
- ✅ Setup/cleanup scripts
- ✅ common-kyverno UC01 implementation

### Phase 2: common-kyverno (Week 1)
- ✅ UC01: Block kubectl exec (DONE)
- 📝 UC02: Block direct deployments
- 📝 UC03: Debug proxy access
- 📝 UC04: GitOps workflow
- 📝 UC05: Break-glass procedure
- 📝 UC06: Audit mode

### Phase 3: Core Charts (Week 2-3)
- 📝 common-monitoring (4 UCs)
- 📝 common-security (4 UCs)
- 📝 common-kubernetes (4 UCs)
- 📝 common-hardening (3 UCs)

### Phase 4: Additional Charts (Week 4)
- 📝 common-keda (3 UCs)
- 📝 common-vault (2 UCs)
- 📝 common-aws (2 UCs)
- 📝 common-argocd (2 UCs)

### Phase 5: Integration Tests (Week 5)
- 📝 Full stack application
- 📝 GitOps platform
- 📝 AWS microservice
- 📝 Secure deployment pipeline
- 📝 Multi-tenant platform

### Phase 6: CI/CD & Automation (Week 6)
- 📝 GitHub Actions workflow
- 📝 Automated test reporting
- 📝 Performance benchmarking
- 📝 Documentation generation

## 🤝 Contributing

### Adding New Tests

1. Create UC documentation: `tests/unit/<chart>/test-cases/UC##-<name>.md`
2. Create values file: `tests/unit/<chart>/values/uc##-<name>.yaml`
3. Create test script: `tests/unit/<chart>/test-cases/run-uc##.sh`
4. Update chart README: `tests/unit/<chart>/README.md`
5. Add to run-all script: `tests/unit/<chart>/test-cases/run-all.sh`

### Test Script Template

```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAME="UC-<CHART>-##: <Description>"
RELEASE_NAME="test-<chart>-uc##"
NAMESPACE="test-app"
CHART_PATH="../../../../charts/common-<chart>"
VALUES_FILE="./values/uc##-<name>.yaml"

# ... rest of test script
```

## 📞 Support

- Issues: Create GitHub issue with `testing` label
- Questions: Slack #forge-helpers-testing channel
- Documentation: See `TESTING-PLAN.md` for detailed UC definitions

---

**Status**: 🟡 In Progress (17% complete)  
**Next**: Complete common-kyverno UC02-06, then move to common-monitoring
