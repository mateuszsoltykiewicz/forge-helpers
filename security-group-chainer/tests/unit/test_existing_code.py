"""
Unit tests for existing security-group-chainer code.
Tests actual implementation in src/ directory.
"""

import pytest
import sys
from pathlib import Path

# Add src to Python path
src_path = Path(__file__).parent.parent.parent / "src"
sys.path.insert(0, str(src_path))


class TestAWSSecurityGroupClient:
    """Test existing AWS client implementation."""
    
    def test_client_initialization(self):
        """Test that client can be initialized."""
        from aws_client import AWSSecurityGroupClient
        
        client = AWSSecurityGroupClient(region="us-east-1")
        assert client.region == "us-east-1"
        assert client.ec2 is not None
    
    def test_find_security_groups_structure(self, mock_ec2_client):
        """Test that find_security_groups_by_tier returns correct structure."""
        from aws_client import AWSSecurityGroupClient
        from unittest.mock import patch
        
        with patch('boto3.client') as mock_boto:
            mock_boto.return_value = mock_ec2_client
            
            client = AWSSecurityGroupClient(region="us-east-1")
            result = client.find_security_groups_by_tier(
                vpc_id="vpc-test123",
                firewall_tier="Public"
            )
            
            # Should call describe_security_groups
            mock_ec2_client.describe_security_groups.assert_called_once()
            assert isinstance(result, list)


class TestCircuitBreaker:
    """Test existing circuit breaker implementation."""
    
    def test_circuit_breaker_initialization(self):
        """Test circuit breaker can be created."""
        from circuit_breaker import CircuitBreaker, CircuitState
        
        cb = CircuitBreaker(
            failure_threshold=5,
            recovery_timeout=60.0,
            success_threshold=2
        )
        
        assert cb.failure_threshold == 5
        assert cb.recovery_timeout == 60.0
        assert cb.success_threshold == 2
        assert cb.state == CircuitState.CLOSED
        assert cb.failure_count == 0
    
    @pytest.mark.asyncio
    async def test_circuit_breaker_closed_state_allows_calls(self):
        """Test that CLOSED state allows function calls."""
        from circuit_breaker import CircuitBreaker, CircuitState
        
        cb = CircuitBreaker()
        
        async def test_func():
            return "success"
        
        result = await cb.call(test_func)
        assert result == "success"
        assert cb.state == CircuitState.CLOSED


class TestChainer:
    """Test main chainer orchestrator."""
    
    def test_load_config_from_yaml(self, chains_yaml_file):
        """Test loading configuration from YAML file."""
        from chainer import load_config_from_yaml
        
        config = load_config_from_yaml(chains_yaml_file)
        
        assert 'chains' in config
        assert isinstance(config['chains'], list)
        assert len(config['chains']) > 0
    
    def test_load_config_structure(self, chains_yaml_file):
        """Test that loaded config has expected structure."""
        from chainer import load_config_from_yaml
        
        config = load_config_from_yaml(chains_yaml_file)
        
        first_chain = config['chains'][0]
        # Note: config uses 'master_tier' and 'slave_tier' not 'source_tier' and 'destination_tier'
        assert 'master_tier' in first_chain
        assert 'slave_tier' in first_chain
        assert 'protocol' in first_chain


class TestReporter:
    """Test report generation."""
    
    def test_reporter_static_methods(self):
        """Test that Reporter has static methods."""
        from reporter import Reporter
        
        # Reporter only has static methods, no initialization
        assert hasattr(Reporter, 'generate_report')
        assert hasattr(Reporter, 'save_report')


class TestChainMonitor:
    """Test chain monitoring."""
    
    def test_monitor_initialization(self):
        """Test that monitor can be created with correct parameters."""
        from chain_monitor import ChainMonitor
        from aws_client import AWSSecurityGroupClient
        from circuit_breaker import CircuitBreaker
        
        # ChainMonitor requires specific parameters
        aws_client = AWSSecurityGroupClient()
        circuit_breaker = CircuitBreaker()
        
        monitor = ChainMonitor(
            name='test-chain',
            master_tier='Public',
            slave_tier='Application',
            ports=[443],
            protocol='tcp',
            bidirectional=False,
            vpc_id='vpc-test',
            aws_client=aws_client,
            circuit_breaker=circuit_breaker,
            timeout=300.0,
            polling_interval=5.0
        )
        
        assert monitor.name == 'test-chain'
        assert monitor.master_tier == 'Public'
        assert monitor.timeout == 300.0
        assert monitor.polling_interval == 5.0


# Integration-style test
class TestEndToEnd:
    """Test complete workflow with mocked AWS."""
    
    def test_imports_work(self):
        """Test that all modules can be imported."""
        import aws_client
        import circuit_breaker
        import chainer
        import reporter
        import chain_monitor
        
        assert aws_client is not None
        assert circuit_breaker is not None
        assert chainer is not None
        assert reporter is not None
        assert chain_monitor is not None
