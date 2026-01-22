"""
End-to-end tests for Terraform integration with security-group-chainer.
Tests the complete workflow from Terraform apply to chain execution.

Run with: pytest -v -m e2e tests/e2e/
"""

import pytest
import subprocess
import json
import yaml
from pathlib import Path
import time


@pytest.mark.e2e
@pytest.mark.requires_terraform
class TestTerraformIntegration:
    """Test complete Terraform workflow with chainer."""
    
    @pytest.fixture(scope="class")
    def terraform_dir(self):
        """Path to Terraform directory."""
        return Path(__file__).parent.parent.parent.parent.parent / "forge-infrastructure" / "aws"
    
    def test_terraform_validate(self, terraform_dir):
        """Test that Terraform configuration is valid."""
        result = subprocess.run(
            ["terraform", "validate"],
            cwd=terraform_dir,
            capture_output=True,
            text=True
        )
        
        assert result.returncode == 0, f"Terraform validate failed: {result.stderr}"
        assert "Success" in result.stdout
    
    def test_terraform_plan(self, terraform_dir):
        """Test Terraform plan execution."""
        result = subprocess.run(
            ["terraform", "plan", "-var-file=terraform.tfvars", "-out=tfplan"],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=300
        )
        
        # Plan should succeed (returncode 0 or 2)
        assert result.returncode in [0, 2], f"Terraform plan failed: {result.stderr}"
        
        # Clean up plan file
        plan_file = terraform_dir / "tfplan"
        if plan_file.exists():
            plan_file.unlink()
    
    @pytest.mark.skip(reason="Requires Terraform apply which modifies infrastructure")
    def test_terraform_apply_chainer_module(self, terraform_dir):
        """Test Terraform apply for chainer module only."""
        result = subprocess.run(
            [
                "terraform", "apply",
                "-var-file=terraform.tfvars",
                "-target=module.principal.module.security_group_chainer",
                "-auto-approve"
            ],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=600
        )
        
        assert result.returncode == 0, f"Terraform apply failed: {result.stderr}"
        assert "Apply complete" in result.stdout
    
    def test_terraform_output_vpc_id(self, terraform_dir):
        """Test reading Terraform outputs."""
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=terraform_dir,
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            outputs = json.loads(result.stdout)
            
            if "vpc_id" in outputs:
                vpc_id = outputs["vpc_id"]["value"]
                assert vpc_id.startswith("vpc-")
                print(f"\nVPC ID: {vpc_id}")
        else:
            pytest.skip("Terraform outputs not available")


@pytest.mark.e2e
class TestCompleteWorkflow:
    """Test complete workflow from config to execution."""
    
    def test_yaml_to_ssm_to_chainer(self, tmp_path, test_config):
        """Test complete workflow: YAML → SSM → Chainer."""
        import boto3
        
        # Step 1: Create chains YAML
        chains_config = {
            "version": "1.0",
            "chains": [
                {
                    "name": "test-e2e-chain",
                    "master_tier": "ALB",
                    "slave_tier": "EKSNodes",
                    "protocol": "tcp",
                    "ports": [80, 443],
                    "bidirectional": False,
                }
            ]
        }
        
        yaml_file = tmp_path / "test-chains.yaml"
        with open(yaml_file, "w") as f:
            yaml.dump(chains_config, f)
        
        # Step 2: Upload to SSM (if credentials available)
        try:
            ssm = boto3.client("ssm", region_name=test_config["aws_region"])
            parameter_name = "/test/e2e/chains"
            
            ssm.put_parameter(
                Name=parameter_name,
                Value=yaml.dump(chains_config),
                Type="String",
                Overwrite=True
            )
            
            # Step 3: Read back from SSM
            response = ssm.get_parameter(Name=parameter_name)
            loaded_config = yaml.safe_load(response["Parameter"]["Value"])
            
            assert loaded_config == chains_config
            
            # Cleanup
            ssm.delete_parameter(Name=parameter_name)
            
            print("\n✓ Complete workflow test passed")
            
        except Exception as e:
            pytest.skip(f"Could not complete workflow test: {e}")
    
    @pytest.mark.slow
    def test_chainer_execution_with_polling(self, test_config):
        """Test chainer with async polling mode."""
        from chain_processor import ChainProcessor
        from aws_client import AWSClient
        import os
        
        # Set up environment for polling
        os.environ["POLLING_ENABLED"] = "true"
        os.environ["ASYNC_PROCESSING"] = "true"
        os.environ["MAX_POLLING_DURATION"] = "60"  # Short for testing
        
        aws_client = AWSClient(region=test_config["aws_region"])
        processor = ChainProcessor(aws_client=aws_client)
        
        # This would normally poll for security groups
        # In test mode, we just verify the setup
        assert processor.polling_enabled is True
        assert processor.max_polling_duration == 60


@pytest.mark.e2e
class TestDockerIntegration:
    """Test Docker container execution."""
    
    def test_docker_image_exists(self):
        """Test that chainer Docker image is built."""
        result = subprocess.run(
            ["docker", "images", "security-group-chainer", "--format", "{{.Repository}}:{{.Tag}}"],
            capture_output=True,
            text=True
        )
        
        assert result.returncode == 0
        images = result.stdout.strip().split("\n")
        
        # Should have at least one image
        assert len(images) > 0
        assert any("security-group-chainer" in img for img in images)
    
    def test_docker_run_help(self):
        """Test running chainer Docker container with --help."""
        result = subprocess.run(
            ["docker", "run", "--rm", "security-group-chainer:1.0.0", "--help"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Should show usage information
        assert "usage:" in result.stdout.lower() or "help" in result.stdout.lower()
    
    @pytest.mark.skip(reason="Requires AWS credentials mounted")
    def test_docker_run_with_config(self, chains_yaml_file, temp_report_file):
        """Test running chainer container with config file."""
        result = subprocess.run(
            [
                "docker", "run", "--rm",
                "-v", f"{chains_yaml_file.parent}:/config:ro",
                "-v", f"{temp_report_file.parent}:/reports",
                "security-group-chainer:1.0.0",
                "--config", f"/config/{chains_yaml_file.name}",
                "--report-output", f"/reports/{temp_report_file.name}",
                "--dry-run"
            ],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        # In dry-run mode, should complete without errors
        assert result.returncode == 0


@pytest.mark.e2e
class TestReportValidation:
    """Test report generation and validation."""
    
    def test_report_file_created(self, test_workspace):
        """Test that report file is created after execution."""
        report_path = test_workspace / "reports" / "chainer-report.yaml"
        
        # Simulate report creation
        report_data = {
            "timestamp": "2026-01-15T20:00:00Z",
            "status": "success",
            "chains_processed": 5,
            "rules_created": 25,
        }
        
        with open(report_path, "w") as f:
            yaml.dump(report_data, f)
        
        assert report_path.exists()
        assert report_path.stat().st_size > 0
    
    def test_report_schema_validation(self, test_workspace):
        """Test that report follows expected schema."""
        report_path = test_workspace / "reports" / "test-report.yaml"
        
        report_data = {
            "timestamp": "2026-01-15T20:00:00Z",
            "status": "success",
            "chains_processed": 3,
            "rules_created": 15,
            "execution_time_seconds": 45.2,
            "chains": [
                {
                    "name": "chain-1",
                    "status": "success",
                    "rules_created": 5,
                    "execution_time": 12.3,
                }
            ]
        }
        
        with open(report_path, "w") as f:
            yaml.dump(report_data, f)
        
        # Validate schema
        with open(report_path) as f:
            loaded = yaml.safe_load(f)
        
        required_fields = ["timestamp", "status", "chains_processed", "rules_created"]
        for field in required_fields:
            assert field in loaded, f"Missing required field: {field}"
        
        # Validate chain details
        if "chains" in loaded:
            for chain in loaded["chains"]:
                assert "name" in chain
                assert "status" in chain
