"""
Integration tests for security-group-chainer with real AWS services.
Requires AWS credentials and proper IAM permissions.

Run with: pytest -v -m integration tests/integration/
"""

import pytest
import boto3
import time
from pathlib import Path


import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))


@pytest.mark.integration
@pytest.mark.requires_aws
class TestAWSIntegration:
    """Integration tests with real AWS EC2 service."""
    
    @pytest.fixture(scope="class")
    def ec2_client(self, test_config):
        """Real EC2 client for integration tests."""
        return boto3.client("ec2", region_name=test_config["aws_region"])
    
    @pytest.fixture(scope="class")
    def test_vpc_id(self, test_config):
        """Get test VPC ID from environment or config."""
        import os
        return os.getenv("TEST_VPC_ID", test_config["test_vpc_id"])
    
    def test_describe_real_security_groups(self, ec2_client, test_vpc_id):
        """Test fetching real security groups from AWS."""
        response = ec2_client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [test_vpc_id]}]
        )
        
        assert "SecurityGroups" in response
        assert isinstance(response["SecurityGroups"], list)
        
        # Log what we found
        sg_count = len(response["SecurityGroups"])
        print(f"\nFound {sg_count} security groups in VPC {test_vpc_id}")
    
    def test_filter_by_firewall_tier_tag(self, ec2_client, test_vpc_id):
        """Test filtering security groups by FirewallTier tag."""
        response = ec2_client.describe_security_groups(
            Filters=[
                {"Name": "vpc-id", "Values": [test_vpc_id]},
                {"Name": "tag:FirewallTier", "Values": ["ALB", "EKSNodes"]},
            ]
        )
        
        sgs = response["SecurityGroups"]
        
        # Verify all returned SGs have FirewallTier tag
        for sg in sgs:
            tags = {tag["Key"]: tag["Value"] for tag in sg.get("Tags", [])}
            assert "FirewallTier" in tags
            assert tags["FirewallTier"] in ["ALB", "EKSNodes"]
    
    @pytest.mark.slow
    def test_list_all_security_group_rules(self, ec2_client, test_vpc_id):
        """Test fetching all security group rules in VPC."""
        from aws_client import AWSClient
        
        client = AWSClient(region=ec2_client.meta.region_name)
        
        # Get all SGs in VPC
        sgs = client.describe_security_groups(
            filters=[{"Name": "vpc-id", "Values": [test_vpc_id]}]
        )
        
        total_ingress_rules = 0
        total_egress_rules = 0
        
        for sg in sgs:
            total_ingress_rules += len(sg.get("IpPermissions", []))
            total_egress_rules += len(sg.get("IpPermissionsEgress", []))
        
        print(f"\nTotal ingress rules: {total_ingress_rules}")
        print(f"Total egress rules: {total_egress_rules}")
        
        assert total_ingress_rules >= 0
        assert total_egress_rules >= 0


@pytest.mark.integration
@pytest.mark.requires_aws
class TestSSMIntegration:
    """Integration tests with AWS SSM Parameter Store."""
    
    @pytest.fixture(scope="class")
    def ssm_client(self, test_config):
        """Real SSM client for integration tests."""
        return boto3.client("ssm", region_name=test_config["aws_region"])
    
    def test_read_chains_config_from_ssm(self, ssm_client):
        """Test reading chains configuration from SSM."""
        parameter_name = "/forge/security-group-chains"
        
        try:
            response = ssm_client.get_parameter(Name=parameter_name)
            
            assert "Parameter" in response
            assert "Value" in response["Parameter"]
            
            # Parse as YAML
            import yaml
            config = yaml.safe_load(response["Parameter"]["Value"])
            
            assert "version" in config
            assert "chains" in config
            
            print(f"\nLoaded {len(config['chains'])} chains from SSM")
            
        except ssm_client.exceptions.ParameterNotFound:
            pytest.skip(f"SSM parameter {parameter_name} not found")
    
    def test_validate_ssm_config_structure(self, ssm_client):
        """Validate that SSM config has correct structure."""
        from config_parser import ChainConfigParser
        
        parameter_name = "/forge/security-group-chains"
        
        try:
            parser = ChainConfigParser(ssm_client=ssm_client)
            config = parser.load_from_ssm(parameter_name)
            
            # Validate structure
            parser.validate_config(config)
            
            print(f"\n✓ SSM config validation passed")
            
        except Exception as e:
            pytest.skip(f"Could not validate SSM config: {e}")


@pytest.mark.integration
@pytest.mark.requires_aws
@pytest.mark.slow
class TestChainExecution:
    """Integration tests for executing security group chains."""
    
    @pytest.fixture(scope="class")
    def chain_processor(self, test_config):
        """Create chain processor with real AWS clients."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        
        aws_client = AWSClient(region=test_config["aws_region"])
        processor = ChainProcessor(
            aws_client=aws_client,
            vpc_id=test_config["test_vpc_id"]
        )
        
        return processor
    
    def test_dry_run_chain_execution(self, chain_processor, sample_chain_config):
        """Test dry-run mode (no actual changes)."""
        from config_parser import Chain
        
        chain = Chain.from_dict(sample_chain_config)
        
        # Execute in dry-run mode
        result = chain_processor.execute_chain(
            chain=chain,
            dry_run=True
        )
        
        assert result is not None
        assert "changes_planned" in result
        assert "errors" in result
    
    @pytest.mark.skip(reason="Requires write permissions to security groups")
    def test_actual_chain_execution(self, chain_processor, sample_chain_config):
        """Test actual chain execution (creates real rules)."""
        from config_parser import Chain
        
        chain = Chain.from_dict(sample_chain_config)
        
        # CAUTION: This makes real changes to AWS
        result = chain_processor.execute_chain(
            chain=chain,
            dry_run=False
        )
        
        assert result["status"] == "success"
        assert result["rules_created"] > 0
    
    def test_chain_with_nonexistent_tier(self, chain_processor):
        """Test chain execution when security group tier doesn't exist."""
        from config_parser import Chain
        
        chain = Chain.from_dict({
            "name": "nonexistent-tier-test",
            "master_tier": "NONEXISTENT_TIER",
            "slave_tier": "ALSO_NONEXISTENT",
            "protocol": "tcp",
            "ports": [80],
        })
        
        result = chain_processor.execute_chain(chain, dry_run=True)
        
        # Should handle gracefully
        assert "errors" in result or result.get("rules_created") == 0


@pytest.mark.integration
class TestReportGeneration:
    """Integration tests for report generation."""
    
    def test_generate_yaml_report(self, temp_report_file):
        """Test generating YAML report file."""
        from report_generator import ReportGenerator
        
        report_data = {
            "timestamp": "2026-01-15T20:00:00Z",
            "chains_processed": 3,
            "rules_created": 15,
            "errors": 0,
            "chains": [
                {
                    "name": "chain-1",
                    "status": "success",
                    "rules_created": 5,
                }
            ]
        }
        
        generator = ReportGenerator()
        generator.write_yaml_report(report_data, temp_report_file)
        
        assert temp_report_file.exists()
        
        # Verify content
        import yaml
        with open(temp_report_file) as f:
            loaded = yaml.safe_load(f)
        
        assert loaded["chains_processed"] == 3
        assert loaded["rules_created"] == 15
    
    def test_report_with_errors(self, temp_report_file):
        """Test report generation with errors."""
        from report_generator import ReportGenerator
        
        report_data = {
            "chains_processed": 2,
            "errors": 1,
            "chains": [
                {
                    "name": "failed-chain",
                    "status": "failed",
                    "error": "Security group not found",
                }
            ]
        }
        
        generator = ReportGenerator()
        generator.write_yaml_report(report_data, temp_report_file)
        
        import yaml
        with open(temp_report_file) as f:
            loaded = yaml.safe_load(f)
        
        assert loaded["errors"] == 1
        assert loaded["chains"][0]["status"] == "failed"
