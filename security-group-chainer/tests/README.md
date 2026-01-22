# Security Group Chainer - Test Suite

Comprehensive test suite for the security-group-chainer automation tool.

## Test Structure

```
tests/
├── conftest.py          # Shared fixtures and pytest configuration
├── unit/                # Unit tests (fast, no external dependencies)
│   ├── test_aws_client.py
│   ├── test_circuit_breaker.py
│   └── test_config_parser.py
├── integration/         # Integration tests (require AWS credentials)
│   └── test_aws_integration.py
├── e2e/                 # End-to-end tests (require Terraform)
│   └── test_terraform_workflow.py
├── performance/         # Performance and load tests
│   └── test_performance.py
└── fixtures/            # Test data and fixtures
```

## Running Tests

### All Tests

```bash
pytest -v
```

### Unit Tests Only (Fast)

```bash
pytest -v -m unit tests/unit/
```

### Integration Tests (Require AWS Credentials)

```bash
# Export AWS credentials first
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export AWS_REGION=us-east-1
export TEST_VPC_ID=vpc-xxxxxxxx

pytest -v -m integration tests/integration/
```

### E2E Tests (Require Terraform)

```bash
pytest -v -m e2e tests/e2e/
```

### Performance Tests

```bash
pytest -v -m performance tests/performance/
```

### With Coverage

```bash
pytest --cov=src --cov-report=html --cov-report=term-missing
```

## Test Markers

Tests are categorized using pytest markers:

- `@pytest.mark.unit` - Fast unit tests, no external dependencies
- `@pytest.mark.integration` - Integration tests requiring AWS
- `@pytest.mark.e2e` - End-to-end tests requiring full infrastructure
- `@pytest.mark.performance` - Performance and benchmarking tests
- `@pytest.mark.slow` - Tests that take significant time
- `@pytest.mark.requires_aws` - Tests requiring AWS credentials
- `@pytest.mark.requires_terraform` - Tests requiring Terraform

## Environment Variables

### Required for Integration Tests

- `AWS_REGION` - AWS region (default: us-east-1)
- `TEST_VPC_ID` - VPC ID for testing (default: vpc-12345678)

### Optional

- `AWS_ACCESS_KEY_ID` - AWS access key (or use ~/.aws/credentials)
- `AWS_SECRET_ACCESS_KEY` - AWS secret key
- `PYTEST_TIMEOUT` - Test timeout in seconds (default: 300)

## Writing Tests

### Unit Test Example

```python
import pytest

def test_example(sample_chain_config):
    """Test description."""
    from config_parser import Chain
    
    chain = Chain.from_dict(sample_chain_config)
    
    assert chain.name == "test-chain"
    assert chain.master_tier == "ALB"
```

### Using Fixtures

Common fixtures available in `conftest.py`:

- `sample_chain_config` - Single chain configuration
- `sample_chains_yaml` - Complete chains YAML
- `mock_ec2_client` - Mocked boto3 EC2 client
- `mock_ssm_client` - Mocked boto3 SSM client
- `chains_yaml_file` - Temporary YAML file
- `temp_report_file` - Temporary report file

### Mocking AWS Calls

```python
def test_with_mock_aws(mock_ec2_client):
    """Test using mocked AWS client."""
    from aws_client import AWSClient
    
    client = AWSClient(region="us-east-1")
    client.ec2 = mock_ec2_client
    
    # Your test code here
```

## Test Coverage Goals

- **Unit Tests**: >90% code coverage
- **Integration Tests**: All AWS interactions validated
- **E2E Tests**: Complete workflow from Terraform to execution
- **Performance Tests**: Ensure <100ms per chain processing

## Continuous Integration

Tests run automatically on:
- Pull requests
- Main branch commits
- Release tags

CI configuration: `.github/workflows/test.yml`

## Troubleshooting

### Tests Skip with "AWS credentials not available"

Ensure `~/.aws/credentials` exists or set environment variables:

```bash
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
```

### Tests Skip with "Terraform not available"

Install Terraform:

```bash
brew install terraform  # macOS
```

### Import Errors

Install test dependencies:

```bash
pip install -r requirements-test.txt
```

## Best Practices

1. **Keep unit tests fast** - No network calls, use mocks
2. **Mock AWS calls** - Don't create real resources in unit tests
3. **Clean up after integration tests** - Delete created resources
4. **Use descriptive test names** - Name should describe what's tested
5. **One assertion per test** - Keep tests focused
6. **Use fixtures** - Don't duplicate test data setup
7. **Tag tests properly** - Use markers for categorization

## Contributing

When adding new features:

1. Write unit tests first (TDD)
2. Add integration tests for AWS interactions
3. Update E2E tests for complete workflow
4. Ensure all tests pass: `pytest -v`
5. Check coverage: `pytest --cov=src`
