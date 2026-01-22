# Security Group Chainer - Testing Guide

## 📋 Test Suite Overview

Comprehensive test suite with **2,256 lines** of test code covering:

- ✅ Unit Tests (3 files, ~750 lines)
- ✅ Integration Tests (1 file, ~350 lines)  
- ✅ End-to-End Tests (1 file, ~400 lines)
- ✅ Performance Tests (1 file, ~550 lines)
- ✅ Shared Fixtures (conftest.py, ~320 lines)

## 🎯 Test Coverage

### Unit Tests (`tests/unit/`)

**test_aws_client.py** (~350 lines)
- AWS EC2 client operations
- Security group filtering
- Permission building
- Error handling (duplicate rules, not found, etc.)
- Tag-based filtering

**test_circuit_breaker.py** (~250 lines)
- Circuit breaker state machine (CLOSED → OPEN → HALF_OPEN)
- Failure threshold detection
- Timeout and recovery
- Decorator pattern
- Per-chain isolation

**test_config_parser.py** (~350 lines)
- YAML parsing and validation
- Chain object creation
- SSM parameter loading
- Schema validation
- Duplicate detection

### Integration Tests (`tests/integration/`)

**test_aws_integration.py** (~350 lines)
- Real AWS EC2 API calls
- SSM Parameter Store operations
- Security group rule management
- Report generation
- Dry-run validation

### End-to-End Tests (`tests/e2e/`)

**test_terraform_workflow.py** (~400 lines)
- Terraform validate/plan/apply
- Complete workflow (YAML → SSM → Chainer)
- Docker container execution
- Report validation
- Output verification

### Performance Tests (`tests/performance/`)

**test_performance.py** (~550 lines)
- Concurrent chain processing
- Polling efficiency
- Memory usage tracking
- Stress tests (100+ chains, 200+ SGs)
- Benchmarking (parsing, filtering)

## 🚀 Quick Start

### 1. Install Test Dependencies

```bash
make install-test
# or
pip install -r requirements-test.txt
```

### 2. Run Unit Tests (Fast)

```bash
make test-unit
# or
pytest -v -m unit tests/unit/
```

### 3. Run All Tests

```bash
make test-all
```

### 4. Generate Coverage Report

```bash
make coverage
make coverage-report  # Opens in browser
```

## 📊 Test Execution Matrix

| Command | Tests Run | AWS Required | Terraform Required | Duration |
|---------|-----------|--------------|-------------------|----------|
| `make test-unit` | Unit only | ❌ No | ❌ No | ~5s |
| `make test-integration` | Integration | ✅ Yes | ❌ No | ~30s |
| `make test-e2e` | E2E | ✅ Yes | ✅ Yes | ~2m |
| `make test-performance` | Performance | ❌ No | ❌ No | ~15s |
| `make test-all` | All tests | ✅ Yes | ✅ Yes | ~3m |
| `make ci` | CI pipeline | ❌ No | ❌ No | ~10s |

## 🔧 Configuration

### Environment Variables

```bash
# Required for integration tests
export AWS_REGION=us-east-1
export TEST_VPC_ID=vpc-xxxxxxxx

# Optional AWS credentials (or use ~/.aws/credentials)
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_SESSION_TOKEN=xxx
```

### pytest.ini

```ini
[pytest]
markers =
    unit: Unit tests (fast, no external dependencies)
    integration: Integration tests (require AWS)
    e2e: End-to-end tests (require Terraform)
    performance: Performance tests
    slow: Slow-running tests
```

## 📝 Test Examples

### Unit Test Example

```python
def test_circuit_breaker_opens_on_threshold(mock_ec2_client):
    """Circuit should open when failures reach threshold."""
    from circuit_breaker import CircuitBreaker
    
    cb = CircuitBreaker(threshold=3)
    
    # Trigger 3 failures
    for _ in range(3):
        try:
            with cb:
                raise Exception("Simulated failure")
        except Exception:
            pass
    
    assert cb.state == "OPEN"
```

### Integration Test Example

```python
@pytest.mark.integration
@pytest.mark.requires_aws
def test_real_aws_security_groups(ec2_client, test_vpc_id):
    """Test fetching real security groups from AWS."""
    response = ec2_client.describe_security_groups(
        Filters=[{"Name": "vpc-id", "Values": [test_vpc_id]}]
    )
    
    assert "SecurityGroups" in response
    assert len(response["SecurityGroups"]) > 0
```

## 🎭 Mocking and Fixtures

### Available Fixtures (conftest.py)

```python
# Configuration
test_config               # Global test configuration
clean_environment        # Clean env vars
mock_environment         # Mock env vars

# Sample Data
sample_chain_config      # Single chain config
sample_chains_yaml       # Complete chains YAML
sample_security_groups   # Sample SG data

# AWS Mocks
mock_ec2_client          # Mocked EC2 client
mock_ssm_client          # Mocked SSM client
mock_boto3_session       # Complete mocked session

# Files
chains_yaml_file         # Temporary YAML file
temp_report_file         # Temporary report file
test_workspace           # Test workspace directory
```

### Using Mocks

```python
def test_with_mocks(mock_ec2_client, mock_ssm_client):
    """Example using multiple mocks."""
    # EC2 client already configured with sample responses
    response = mock_ec2_client.describe_security_groups()
    assert len(response["SecurityGroups"]) == 2
    
    # SSM client returns sample YAML
    param = mock_ssm_client.get_parameter(Name="/test")
    assert "chains" in yaml.safe_load(param["Parameter"]["Value"])
```

## 🐛 Debugging Tests

### Run Single Test

```bash
pytest -v tests/unit/test_aws_client.py::TestAWSClient::test_describe_security_groups_by_tier
```

### Debug with PDB

```bash
pytest --pdb tests/unit/test_aws_client.py
```

### Verbose Output

```bash
pytest -vv -s tests/unit/
```

### Show Print Statements

```bash
pytest -s tests/unit/test_circuit_breaker.py
```

## 📈 Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| aws_client.py | >90% | TBD |
| config_parser.py | >90% | TBD |
| circuit_breaker.py | >95% | TBD |
| chain_processor.py | >85% | TBD |
| **Overall** | **>90%** | **TBD** |

## 🔄 CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: make install-test
      - run: make ci  # Fast unit tests + lint
      - run: make coverage
      - uses: codecov/codecov-action@v3
```

### Local Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash
make check || exit 1
```

## 📚 Best Practices

### ✅ DO

- Write tests before code (TDD)
- Keep unit tests fast (<100ms each)
- Mock all external dependencies
- Use descriptive test names
- One assertion per test (when possible)
- Clean up resources in fixtures
- Use markers to categorize tests

### ❌ DON'T

- Create real AWS resources in unit tests
- Skip cleanup after integration tests
- Hardcode AWS credentials
- Use time.sleep() in tests (use mocks)
- Write tests without markers
- Duplicate fixture code

## 🎓 Learning Resources

- [pytest documentation](https://docs.pytest.org/)
- [boto3 mocking with moto](https://github.com/spulec/moto)
- [Test-Driven Development with Python](https://www.obeythetestinggoat.com/)
- [Python Testing with pytest (Book)](https://pragprog.com/titles/bopytest/)

## 📞 Support

Issues with tests? Check:

1. **Import errors**: Run `make install-test`
2. **AWS errors**: Check credentials and VPC ID
3. **Terraform errors**: Verify `terraform` is in PATH
4. **Timeout errors**: Increase timeout in pytest.ini

Still stuck? Open an issue on GitHub!

---

**Last Updated**: 2026-01-15  
**Test Suite Version**: 1.0.0  
**Total Lines of Test Code**: 2,256
