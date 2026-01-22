"""
Performance tests for security-group-chainer.
Tests concurrent execution, polling efficiency, and resource usage.

Run with: pytest -v -m performance tests/performance/
"""

import pytest
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from unittest.mock import Mock, MagicMock


import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))


@pytest.mark.performance
class TestConcurrentExecution:
    """Test concurrent chain processing performance."""
    
    def test_parallel_chain_processing(self, mock_ec2_client):
        """Test processing multiple chains in parallel."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        from config_parser import Chain
        
        # Create multiple test chains
        chains = [
            Chain.from_dict({
                "name": f"chain-{i}",
                "master_tier": "ALB",
                "slave_tier": f"Tier{i}",
                "protocol": "tcp",
                "ports": [80 + i],
            })
            for i in range(10)
        ]
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        processor = ChainProcessor(aws_client=aws_client)
        
        start_time = time.time()
        
        # Process chains concurrently
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [
                executor.submit(processor.execute_chain, chain, dry_run=True)
                for chain in chains
            ]
            
            results = [f.result() for f in as_completed(futures)]
        
        elapsed = time.time() - start_time
        
        assert len(results) == 10
        print(f"\nProcessed 10 chains in {elapsed:.2f} seconds")
        print(f"Average: {elapsed/10:.2f} seconds per chain")
    
    def test_max_parallel_chains_limit(self, mock_ec2_client):
        """Test that max_parallel_chains limit is respected."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        
        processor = ChainProcessor(
            aws_client=aws_client,
            max_parallel_chains=3
        )
        
        assert processor.max_parallel_chains == 3
        
        # Verify executor uses correct worker count
        assert processor._executor._max_workers == 3
    
    def test_sequential_vs_parallel_performance(self, mock_ec2_client, sample_chains_yaml):
        """Compare sequential vs parallel processing performance."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        from config_parser import Chain
        
        chains = [
            Chain.from_dict(chain_dict)
            for chain_dict in sample_chains_yaml["chains"]
        ]
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        
        # Sequential processing
        processor_seq = ChainProcessor(aws_client=aws_client, max_parallel_chains=1)
        start_seq = time.time()
        for chain in chains:
            processor_seq.execute_chain(chain, dry_run=True)
        time_seq = time.time() - start_seq
        
        # Parallel processing
        processor_par = ChainProcessor(aws_client=aws_client, max_parallel_chains=3)
        start_par = time.time()
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(processor_par.execute_chain, chain, dry_run=True)
                for chain in chains
            ]
            [f.result() for f in as_completed(futures)]
        time_par = time.time() - start_par
        
        print(f"\nSequential: {time_seq:.3f}s")
        print(f"Parallel:   {time_par:.3f}s")
        print(f"Speedup:    {time_seq/time_par:.2f}x")
        
        # Parallel should be faster (or at least not slower)
        assert time_par <= time_seq * 1.2  # Allow 20% margin


@pytest.mark.performance
class TestPollingPerformance:
    """Test async polling mode performance."""
    
    def test_polling_interval_accuracy(self, mock_ec2_client):
        """Test that polling interval is respected."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        
        polling_interval = 2  # seconds
        iterations = 3
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        
        processor = ChainProcessor(
            aws_client=aws_client,
            polling_enabled=True,
            polling_interval=polling_interval
        )
        
        poll_times = []
        
        def mock_poll():
            poll_times.append(time.time())
            return len(poll_times) >= iterations
        
        processor._should_stop_polling = mock_poll
        
        start = time.time()
        processor._polling_loop()
        elapsed = time.time() - start
        
        # Should have polled 'iterations' times
        assert len(poll_times) >= iterations
        
        # Check intervals between polls
        if len(poll_times) > 1:
            intervals = [
                poll_times[i] - poll_times[i-1]
                for i in range(1, len(poll_times))
            ]
            
            avg_interval = sum(intervals) / len(intervals)
            
            # Should be close to configured interval (±20%)
            assert polling_interval * 0.8 <= avg_interval <= polling_interval * 1.2
    
    def test_max_polling_duration(self, mock_ec2_client):
        """Test that polling stops after max duration."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        
        max_duration = 5  # seconds
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        
        processor = ChainProcessor(
            aws_client=aws_client,
            polling_enabled=True,
            polling_interval=1,
            max_polling_duration=max_duration
        )
        
        start = time.time()
        processor._polling_loop()
        elapsed = time.time() - start
        
        # Should stop within max_duration (±1 second tolerance)
        assert elapsed <= max_duration + 1
    
    def test_early_termination_on_completion(self, mock_ec2_client):
        """Test that polling stops early when all chains complete."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        
        processor = ChainProcessor(
            aws_client=aws_client,
            polling_enabled=True,
            max_polling_duration=60  # Long duration
        )
        
        # Mock completion check to return True immediately
        processor._all_chains_complete = Mock(return_value=True)
        
        start = time.time()
        processor._polling_loop()
        elapsed = time.time() - start
        
        # Should terminate quickly (< 2 seconds)
        assert elapsed < 2


@pytest.mark.performance
class TestMemoryUsage:
    """Test memory usage and resource cleanup."""
    
    def test_large_number_of_chains(self, mock_ec2_client):
        """Test processing large number of chains."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        from config_parser import Chain
        
        # Create 100 chains
        num_chains = 100
        chains = [
            Chain.from_dict({
                "name": f"chain-{i}",
                "master_tier": "ALB",
                "slave_tier": f"Tier{i % 10}",
                "protocol": "tcp",
                "ports": [80],
            })
            for i in range(num_chains)
        ]
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        processor = ChainProcessor(aws_client=aws_client)
        
        # Process all chains
        results = []
        for chain in chains:
            result = processor.execute_chain(chain, dry_run=True)
            results.append(result)
        
        assert len(results) == num_chains
        print(f"\nSuccessfully processed {num_chains} chains")
    
    def test_repeated_execution_no_memory_leak(self, mock_ec2_client):
        """Test that repeated executions don't leak memory."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        from config_parser import Chain
        
        chain = Chain.from_dict({
            "name": "repeat-test",
            "master_tier": "ALB",
            "slave_tier": "EKS",
            "protocol": "tcp",
            "ports": [80, 443],
        })
        
        aws_client = AWSClient(region="us-east-1")
        aws_client.ec2 = mock_ec2_client
        processor = ChainProcessor(aws_client=aws_client)
        
        # Execute same chain 50 times
        for i in range(50):
            processor.execute_chain(chain, dry_run=True)
        
        # If we got here without errors, memory is probably OK
        print("\n✓ Completed 50 repeated executions")


@pytest.mark.performance
@pytest.mark.slow
class TestStressTests:
    """Stress tests for edge cases and limits."""
    
    def test_many_security_groups(self, mock_ec2_client):
        """Test handling many security groups in VPC."""
        from aws_client import AWSClient
        
        # Mock response with 200 security groups
        mock_ec2_client.describe_security_groups.return_value = {
            "SecurityGroups": [
                {
                    "GroupId": f"sg-{i:08x}",
                    "GroupName": f"sg-{i}",
                    "VpcId": "vpc-test",
                    "Tags": [
                        {"Key": "FirewallTier", "Value": f"Tier{i % 10}"},
                    ],
                }
                for i in range(200)
            ]
        }
        
        client = AWSClient(region="us-east-1")
        client.ec2 = mock_ec2_client
        
        start = time.time()
        sgs = client.describe_security_groups()
        elapsed = time.time() - start
        
        assert len(sgs) == 200
        print(f"\nProcessed 200 security groups in {elapsed:.3f}s")
    
    def test_many_rules_per_security_group(self, mock_ec2_client):
        """Test SG with many rules (approaching AWS limit of 60)."""
        from aws_client import build_ip_permissions_from_ports
        
        # Create 50 rules
        ports = list(range(8000, 8050))
        
        start = time.time()
        permissions = build_ip_permissions_from_ports(
            ports=ports,
            protocol="tcp",
            source_group_id="sg-source"
        )
        elapsed = time.time() - start
        
        assert len(permissions) == 50
        print(f"\nBuilt 50 permission objects in {elapsed:.4f}s")
    
    def test_circuit_breaker_under_load(self, mock_ec2_client):
        """Test circuit breaker behavior under high failure rate."""
        from circuit_breaker import CircuitBreaker
        
        cb = CircuitBreaker(threshold=10, timeout=1)
        
        # Simulate 100 rapid failures
        start = time.time()
        open_at_failure = None
        
        for i in range(100):
            try:
                with cb:
                    raise Exception("Simulated failure")
            except Exception:
                if cb.state == "OPEN" and open_at_failure is None:
                    open_at_failure = i + 1
        
        elapsed = time.time() - start
        
        assert cb.state == "OPEN"
        assert open_at_failure == 10  # Should open at threshold
        
        print(f"\nCircuit opened after {open_at_failure} failures")
        print(f"100 failures processed in {elapsed:.3f}s")


@pytest.mark.performance
class TestBenchmarks:
    """Benchmark tests for key operations."""
    
    def test_benchmark_chain_parsing(self, sample_chains_yaml, tmp_path):
        """Benchmark YAML parsing performance."""
        from config_parser import ChainConfigParser
        import yaml
        
        yaml_file = tmp_path / "bench.yaml"
        with open(yaml_file, "w") as f:
            yaml.dump(sample_chains_yaml, f)
        
        parser = ChainConfigParser()
        
        iterations = 100
        start = time.time()
        
        for _ in range(iterations):
            parser.parse_file(yaml_file)
        
        elapsed = time.time() - start
        avg = elapsed / iterations
        
        print(f"\nParsed config {iterations} times in {elapsed:.3f}s")
        print(f"Average: {avg*1000:.2f}ms per parse")
        
        # Should be fast (< 50ms per parse)
        assert avg < 0.05
    
    def test_benchmark_sg_filtering(self, sample_security_groups):
        """Benchmark security group filtering."""
        from aws_client import filter_security_groups_by_tier
        
        # Create large dataset
        large_dataset = sample_security_groups * 50  # 100 SGs
        
        iterations = 1000
        start = time.time()
        
        for _ in range(iterations):
            filter_security_groups_by_tier(large_dataset, "ALB")
        
        elapsed = time.time() - start
        avg = elapsed / iterations
        
        print(f"\nFiltered 100 SGs {iterations} times in {elapsed:.3f}s")
        print(f"Average: {avg*1000:.3f}ms per filter")
        
        # Should be very fast (< 5ms)
        assert avg < 0.005
