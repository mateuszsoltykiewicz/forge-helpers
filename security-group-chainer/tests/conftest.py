"""
Pytest configuration and shared fixtures for security-group-chainer tests.
"""

import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, List
from unittest.mock import Mock, MagicMock

import pytest
import yaml


# ==============================================================================
# Test Configuration
# ==============================================================================

@pytest.fixture(scope="session")
def test_config() -> Dict[str, Any]:
    """Global test configuration."""
    return {
        "aws_region": os.getenv("AWS_REGION", "us-east-1"),
        "test_vpc_id": os.getenv("TEST_VPC_ID", "vpc-12345678"),
        "timeout": 300,
        "max_retries": 3,
    }


# ==============================================================================
# Sample Chains Configuration Fixtures
# ==============================================================================

@pytest.fixture
def sample_chain_config() -> Dict[str, Any]:
    """Single chain configuration for testing."""
    return {
        "name": "test-chain",
        "master_tier": "ALB",
        "slave_tier": "EKS",
        "protocol": "tcp",
        "ports": [80, 443],
        "bidirectional": False,
    }


@pytest.fixture
def sample_chains_yaml() -> Dict[str, Any]:
    """Complete chains YAML configuration."""
    return {
        "version": "1.0",
        "timeout_seconds": 7200,
        "polling_interval_seconds": 15,
        "circuit_breaker_threshold": 10,
        "chains": [
            {
                "name": "alb-to-eks",
                "master_tier": "ALB",
                "slave_tier": "EKSNodes",
                "protocol": "tcp",
                "ports": [80, 443],
                "bidirectional": False,
            },
            {
                "name": "eks-to-rds",
                "master_tier": "EKSNodes",
                "slave_tier": "RDS",
                "protocol": "tcp",
                "ports": [5432],
                "bidirectional": False,
            },
            {
                "name": "eks-cluster-nodes",
                "master_tier": "EKSCluster",
                "slave_tier": "EKSNodes",
                "protocol": "tcp",
                "ports": [443, 10250],
                "bidirectional": True,
            },
        ],
    }


@pytest.fixture
def chains_yaml_file(sample_chains_yaml, tmp_path) -> Path:
    """Create temporary chains YAML file."""
    yaml_file = tmp_path / "chains.yaml"
    with open(yaml_file, "w") as f:
        yaml.dump(sample_chains_yaml, f)
    return yaml_file


# ==============================================================================
# AWS Mock Fixtures
# ==============================================================================

@pytest.fixture
def mock_ec2_client():
    """Mock boto3 EC2 client."""
    client = MagicMock()
    
    # Mock describe_security_groups response
    client.describe_security_groups.return_value = {
        "SecurityGroups": [
            {
                "GroupId": "sg-alb123",
                "GroupName": "ALB-sg",
                "VpcId": "vpc-12345678",
                "Tags": [
                    {"Key": "FirewallTier", "Value": "ALB"},
                    {"Key": "FirewallType", "Value": "master"},
                ],
            },
            {
                "GroupId": "sg-eks456",
                "GroupName": "EKSNodes-sg",
                "VpcId": "vpc-12345678",
                "Tags": [
                    {"Key": "FirewallTier", "Value": "EKSNodes"},
                    {"Key": "FirewallType", "Value": "slave"},
                ],
            },
        ]
    }
    
    # Mock authorize_security_group_ingress/egress
    client.authorize_security_group_ingress.return_value = {}
    client.authorize_security_group_egress.return_value = {}
    
    return client


@pytest.fixture
def mock_ssm_client():
    """Mock boto3 SSM client."""
    client = MagicMock()
    
    # Mock get_parameter response
    sample_yaml = yaml.dump({
        "version": "1.0",
        "chains": [{"name": "test", "master_tier": "ALB", "slave_tier": "EKS"}]
    })
    
    client.get_parameter.return_value = {
        "Parameter": {
            "Name": "/forge/security-group-chains",
            "Type": "String",
            "Value": sample_yaml,
        }
    }
    
    return client


@pytest.fixture
def mock_boto3_session(mock_ec2_client, mock_ssm_client, monkeypatch):
    """Mock boto3 session with EC2 and SSM clients."""
    
    def mock_client(service_name, **kwargs):
        if service_name == "ec2":
            return mock_ec2_client
        elif service_name == "ssm":
            return mock_ssm_client
        raise ValueError(f"Unknown service: {service_name}")
    
    mock_session = MagicMock()
    mock_session.client.side_effect = mock_client
    
    import boto3
    monkeypatch.setattr(boto3, "Session", lambda **kwargs: mock_session)
    
    return mock_session


# ==============================================================================
# Security Group Fixtures
# ==============================================================================

@pytest.fixture
def sample_security_groups() -> List[Dict[str, Any]]:
    """Sample security groups for testing."""
    return [
        {
            "GroupId": "sg-alb123",
            "GroupName": "forge-prod-alb-sg",
            "VpcId": "vpc-12345678",
            "Tags": [
                {"Key": "FirewallTier", "Value": "ALB"},
                {"Key": "FirewallType", "Value": "master"},
                {"Key": "Environment", "Value": "production"},
            ],
            "IpPermissions": [],
            "IpPermissionsEgress": [
                {
                    "IpProtocol": "-1",
                    "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
                }
            ],
        },
        {
            "GroupId": "sg-eks456",
            "GroupName": "forge-prod-eks-nodes-sg",
            "VpcId": "vpc-12345678",
            "Tags": [
                {"Key": "FirewallTier", "Value": "EKSNodes"},
                {"Key": "FirewallType", "Value": "slave"},
                {"Key": "Environment", "Value": "production"},
            ],
            "IpPermissions": [],
            "IpPermissionsEgress": [],
        },
    ]


# ==============================================================================
# File System Fixtures
# ==============================================================================

@pytest.fixture
def temp_report_file(tmp_path) -> Path:
    """Temporary file for test reports."""
    return tmp_path / "test-report.yaml"


@pytest.fixture
def test_workspace(tmp_path) -> Path:
    """Create a test workspace directory."""
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "reports").mkdir()
    (workspace / "config").mkdir()
    return workspace


# ==============================================================================
# Environment Fixtures
# ==============================================================================

@pytest.fixture
def clean_environment(monkeypatch):
    """Clean environment variables for testing."""
    env_vars = [
        "AWS_REGION",
        "POLLING_ENABLED",
        "ASYNC_PROCESSING",
        "MAX_PARALLEL_CHAINS",
        "POLLING_INTERVAL_SECONDS",
        "MAX_POLLING_DURATION",
    ]
    
    for var in env_vars:
        monkeypatch.delenv(var, raising=False)
    
    yield
    
    # Cleanup happens automatically via monkeypatch


@pytest.fixture
def mock_environment(monkeypatch):
    """Set up mock environment variables."""
    env = {
        "AWS_REGION": "us-east-1",
        "POLLING_ENABLED": "true",
        "ASYNC_PROCESSING": "true",
        "MAX_PARALLEL_CHAINS": "5",
        "POLLING_INTERVAL_SECONDS": "15",
        "MAX_POLLING_DURATION": "7200",
    }
    
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    
    return env


# ==============================================================================
# Utility Fixtures
# ==============================================================================

@pytest.fixture
def capture_logs(caplog):
    """Fixture to capture and return logs."""
    import logging
    caplog.set_level(logging.DEBUG)
    return caplog


# ==============================================================================
# Skip Markers for Integration Tests
# ==============================================================================

def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers", "requires_aws: mark test as requiring AWS credentials"
    )
    config.addinivalue_line(
        "markers", "requires_terraform: mark test as requiring Terraform"
    )


def pytest_collection_modifyitems(config, items):
    """Modify test collection to skip integration tests if credentials not available."""
    skip_aws = pytest.mark.skip(reason="AWS credentials not available")
    skip_terraform = pytest.mark.skip(reason="Terraform not available")
    
    # Check if AWS credentials are available
    has_aws_creds = (
        os.getenv("AWS_ACCESS_KEY_ID") is not None
        or Path.home().joinpath(".aws/credentials").exists()
    )
    
    # Check if terraform is available
    import shutil
    has_terraform = shutil.which("terraform") is not None
    
    for item in items:
        if "requires_aws" in item.keywords and not has_aws_creds:
            item.add_marker(skip_aws)
        
        if "requires_terraform" in item.keywords and not has_terraform:
            item.add_marker(skip_terraform)
