"""
Unit tests for Reporter.
Tests the existing implementation in src/reporter.py
"""

import pytest
import sys
import yaml
import tempfile
from pathlib import Path
from datetime import datetime

# Add src to Python path
src_path = Path(__file__).parent.parent.parent / "src"
sys.path.insert(0, str(src_path))

from reporter import Reporter


class TestReporterGeneration:
    """Test report generation functionality."""
    
    def test_generate_report_success(self):
        """Test generating report for successful chain execution."""
        results = [
            {
                'name': 'public-to-app',
                'status': 'success',
                'master_tier': 'Public',
                'slave_tier': 'Application',
                'master_security_groups': ['sg-111'],
                'slave_security_groups': ['sg-222'],
                'rules_created': ['sg-222: ingress from sg-111'],
                'errors': []
            }
        ]
        
        start_time = 1234567890.0
        end_time = 1234567920.0
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=start_time,
            end_time=end_time,
            vpc_id='vpc-test123',
            region='us-east-1'
        )
        
        # Parse YAML
        report = yaml.safe_load(report_yaml)
        
        # Verify structure
        assert 'security_group_chainer_report' in report
        assert 'metadata' in report['security_group_chainer_report']
        assert 'summary' in report['security_group_chainer_report']
        assert 'chains' in report['security_group_chainer_report']
    
    def test_report_metadata(self):
        """Test that metadata is correct."""
        results = []
        start_time = 1234567890.0
        end_time = 1234567920.0
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='dry-run',
            start_time=start_time,
            end_time=end_time,
            vpc_id='vpc-abc123',
            region='eu-west-1'
        )
        
        report = yaml.safe_load(report_yaml)
        metadata = report['security_group_chainer_report']['metadata']
        
        assert metadata['duration_seconds'] == 30.0
        assert metadata['mode'] == 'dry-run'
        assert metadata['vpc_id'] == 'vpc-abc123'
        assert metadata['region'] == 'eu-west-1'
        assert 'timestamp' in metadata
    
    def test_report_summary_all_successful(self):
        """Test summary when all chains succeed."""
        results = [
            {
                'name': 'chain-1',
                'status': 'success',
                'master_tier': 'Public',
                'slave_tier': 'App',
                'master_security_groups': ['sg-1'],
                'slave_security_groups': ['sg-2'],
                'rules_created': ['rule-1'],
                'errors': []
            },
            {
                'name': 'chain-2',
                'status': 'success',
                'master_tier': 'App',
                'slave_tier': 'Data',
                'master_security_groups': ['sg-2'],
                'slave_security_groups': ['sg-3'],
                'rules_created': ['rule-2'],
                'errors': []
            }
        ]
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=100.0,
            end_time=110.0,
            vpc_id='vpc-test',
            region='us-east-1'
        )
        
        report = yaml.safe_load(report_yaml)
        summary = report['security_group_chainer_report']['summary']
        
        assert summary['total_chains'] == 2
        assert summary['successful'] == 2
        assert summary['partial_success'] == 0
        assert summary['failed'] == 0
        assert summary['overall_status'] == 'success'
    
    def test_report_summary_with_failures(self):
        """Test summary when some chains fail."""
        results = [
            {
                'name': 'chain-1',
                'status': 'success',
                'master_tier': 'Public',
                'slave_tier': 'App',
                'master_security_groups': ['sg-1'],
                'slave_security_groups': ['sg-2'],
                'rules_created': ['rule-1'],
                'errors': []
            },
            {
                'name': 'chain-2',
                'status': 'failed',
                'master_tier': 'App',
                'slave_tier': 'Data',
                'master_security_groups': [],
                'slave_security_groups': [],
                'rules_created': [],
                'errors': ['No security groups found']
            }
        ]
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=100.0,
            end_time=110.0,
            vpc_id='vpc-test',
            region='us-east-1'
        )
        
        report = yaml.safe_load(report_yaml)
        summary = report['security_group_chainer_report']['summary']
        
        assert summary['total_chains'] == 2
        assert summary['successful'] == 1
        assert summary['failed'] == 1
        assert summary['overall_status'] == 'partial'
    
    def test_report_summary_all_failed(self):
        """Test summary when all chains fail."""
        results = [
            {
                'name': 'chain-1',
                'status': 'error',
                'master_tier': 'Public',
                'slave_tier': 'App',
                'master_security_groups': [],
                'slave_security_groups': [],
                'rules_created': [],
                'errors': ['AWS API error']
            }
        ]
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=100.0,
            end_time=105.0,
            vpc_id='vpc-test',
            region='us-east-1'
        )
        
        report = yaml.safe_load(report_yaml)
        summary = report['security_group_chainer_report']['summary']
        
        assert summary['total_chains'] == 1
        assert summary['successful'] == 0
        assert summary['failed'] == 1
        assert summary['overall_status'] == 'failed'
    
    def test_report_chain_details(self):
        """Test that chain details are included correctly."""
        results = [
            {
                'name': 'public-to-app',
                'status': 'success',
                'master_tier': 'Public',
                'slave_tier': 'Application',
                'master_security_groups': ['sg-111', 'sg-112'],
                'slave_security_groups': ['sg-222'],
                'rules_created': [
                    'sg-222: ingress tcp/443 from sg-111',
                    'sg-222: ingress tcp/443 from sg-112'
                ],
                'errors': []
            }
        ]
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=100.0,
            end_time=110.0,
            vpc_id='vpc-test',
            region='us-east-1'
        )
        
        report = yaml.safe_load(report_yaml)
        chains = report['security_group_chainer_report']['chains']
        
        assert len(chains) == 1
        
        chain = chains[0]
        assert chain['name'] == 'public-to-app'
        assert chain['status'] == 'success'
        assert chain['master_tier'] == 'Public'
        assert chain['slave_tier'] == 'Application'
        assert len(chain['master_security_groups']) == 2
        assert len(chain['actions']) == 2
    
    def test_report_with_errors(self):
        """Test that errors are included in report."""
        results = [
            {
                'name': 'failing-chain',
                'status': 'partial_success',
                'master_tier': 'Public',
                'slave_tier': 'App',
                'master_security_groups': ['sg-1'],
                'slave_security_groups': ['sg-2'],
                'rules_created': ['rule-1'],
                'errors': [
                    'Failed to create rule for sg-3',
                    'Timeout waiting for sg-4'
                ]
            }
        ]
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=100.0,
            end_time=110.0,
            vpc_id='vpc-test',
            region='us-east-1'
        )
        
        report = yaml.safe_load(report_yaml)
        chain = report['security_group_chainer_report']['chains'][0]
        
        assert 'errors' in chain
        assert len(chain['errors']) == 2
        assert 'Failed to create rule' in chain['errors'][0]
    
    def test_save_report(self):
        """Test saving report to file."""
        report_yaml = "test: data\n"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.yaml') as f:
            temp_path = f.name
        
        try:
            Reporter.save_report(report_yaml, output_path=temp_path)
            
            # Verify file was created and contains correct data
            with open(temp_path, 'r') as f:
                content = f.read()
            
            assert content == report_yaml
        finally:
            # Cleanup
            Path(temp_path).unlink(missing_ok=True)
    
    def test_partial_success_status(self):
        """Test partial_success status is counted correctly."""
        results = [
            {
                'name': 'chain-1',
                'status': 'partial_success',
                'master_tier': 'Public',
                'slave_tier': 'App',
                'master_security_groups': ['sg-1'],
                'slave_security_groups': ['sg-2'],
                'rules_created': ['rule-1'],
                'errors': ['Some error']
            }
        ]
        
        report_yaml = Reporter.generate_report(
            results=results,
            mode='execute',
            start_time=100.0,
            end_time=110.0,
            vpc_id='vpc-test',
            region='us-east-1'
        )
        
        report = yaml.safe_load(report_yaml)
        summary = report['security_group_chainer_report']['summary']
        
        assert summary['partial_success'] == 1
        assert summary['successful'] == 0
        assert summary['failed'] == 0
