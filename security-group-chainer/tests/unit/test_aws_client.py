"""
Unit tests for AWSSecurityGroupClient.
Tests the existing implementation in src/aws_client.py
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add src to Python path
src_path = Path(__file__).parent.parent.parent / "src"
sys.path.insert(0, str(src_path))

from aws_client import AWSSecurityGroupClient


class TestAWSSecurityGroupClient:
    """Test AWS security group client operations."""
    
    def test_client_initialization(self):
        """Test that client initializes with correct region."""
        client = AWSSecurityGroupClient(region="us-west-2")
        
        assert client.region == "us-west-2"
        assert client.ec2 is not None
    
    def test_default_region(self):
        """Test that default region is us-east-1."""
        client = AWSSecurityGroupClient()
        
        assert client.region == "us-east-1"
    
    @patch('boto3.client')
    def test_find_security_groups_by_tier(self, mock_boto_client):
        """Test finding security groups by FirewallTier tag."""
        # Mock EC2 response
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_security_groups.return_value = {
            'SecurityGroups': [
                {
                    'GroupId': 'sg-111',
                    'GroupName': 'public-lb',
                    'Tags': [
                        {'Key': 'FirewallTier', 'Value': 'Public'},
                        {'Key': 'Name', 'Value': 'public-lb'}
                    ]
                },
                {
                    'GroupId': 'sg-222',
                    'GroupName': 'public-web',
                    'Tags': [
                        {'Key': 'FirewallTier', 'Value': 'Public'},
                        {'Key': 'Name', 'Value': 'public-web'}
                    ]
                }
            ]
        }
        
        client = AWSSecurityGroupClient()
        result = client.find_security_groups_by_tier(
            vpc_id='vpc-test123',
            firewall_tier='Public'
        )
        
        # Verify call
        mock_ec2.describe_security_groups.assert_called_once_with(
            Filters=[
                {'Name': 'vpc-id', 'Values': ['vpc-test123']},
                {'Name': 'tag:FirewallTier', 'Values': ['Public']}
            ]
        )
        
        # Verify result
        assert len(result) == 2
        assert result[0]['GroupId'] == 'sg-111'
        assert result[0]['GroupName'] == 'public-lb'
        assert result[0]['Tags']['FirewallTier'] == 'Public'
        assert result[1]['GroupId'] == 'sg-222'
    
    @patch('boto3.client')
    def test_rule_exists_ingress_security_group(self, mock_boto_client):
        """Test checking if ingress rule exists (security group source)."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_security_groups.return_value = {
            'SecurityGroups': [{
                'GroupId': 'sg-dest',
                'IpPermissions': [
                    {
                        'IpProtocol': 'tcp',
                        'FromPort': 443,
                        'ToPort': 443,
                        'UserIdGroupPairs': [
                            {'GroupId': 'sg-source'}
                        ]
                    }
                ],
                'IpPermissionsEgress': []
            }]
        }
        
        client = AWSSecurityGroupClient()
        
        # Rule should exist
        exists = client.rule_exists(
            group_id='sg-dest',
            direction='ingress',
            protocol='tcp',
            from_port=443,
            to_port=443,
            source_group_id='sg-source'
        )
        
        assert exists is True
    
    @patch('boto3.client')
    def test_rule_not_exists(self, mock_boto_client):
        """Test checking if rule does not exist."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_security_groups.return_value = {
            'SecurityGroups': [{
                'GroupId': 'sg-dest',
                'IpPermissions': [],
                'IpPermissionsEgress': []
            }]
        }
        
        client = AWSSecurityGroupClient()
        
        exists = client.rule_exists(
            group_id='sg-dest',
            direction='ingress',
            protocol='tcp',
            from_port=443,
            to_port=443,
            source_group_id='sg-source'
        )
        
        assert exists is False
    
    @patch('boto3.client')
    def test_rule_exists_all_traffic(self, mock_boto_client):
        """Test checking if 'all traffic' rule exists."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_security_groups.return_value = {
            'SecurityGroups': [{
                'GroupId': 'sg-dest',
                'IpPermissions': [
                    {
                        'IpProtocol': '-1',
                        'UserIdGroupPairs': [
                            {'GroupId': 'sg-source'}
                        ]
                    }
                ],
                'IpPermissionsEgress': []
            }]
        }
        
        client = AWSSecurityGroupClient()
        
        exists = client.rule_exists(
            group_id='sg-dest',
            direction='ingress',
            protocol='-1',
            from_port=-1,
            to_port=-1,
            source_group_id='sg-source'
        )
        
        assert exists is True
    
    @patch('boto3.client')
    def test_create_ingress_rule_tcp(self, mock_boto_client):
        """Test creating TCP ingress rule."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        client = AWSSecurityGroupClient()
        client.create_ingress_rule(
            group_id='sg-dest',
            protocol='tcp',
            from_port=80,
            to_port=80,
            source_group_id='sg-source',
            description='Allow HTTP from source'
        )
        
        # Verify call
        mock_ec2.authorize_security_group_ingress.assert_called_once()
        call_args = mock_ec2.authorize_security_group_ingress.call_args[1]
        
        assert call_args['GroupId'] == 'sg-dest'
        assert call_args['IpPermissions'][0]['IpProtocol'] == 'tcp'
        assert call_args['IpPermissions'][0]['FromPort'] == 80
        assert call_args['IpPermissions'][0]['ToPort'] == 80
        assert call_args['IpPermissions'][0]['UserIdGroupPairs'][0]['GroupId'] == 'sg-source'
        assert call_args['IpPermissions'][0]['UserIdGroupPairs'][0]['Description'] == 'Allow HTTP from source'
    
    @patch('boto3.client')
    def test_create_ingress_rule_all_traffic(self, mock_boto_client):
        """Test creating 'all traffic' ingress rule."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        client = AWSSecurityGroupClient()
        client.create_ingress_rule(
            group_id='sg-dest',
            protocol='-1',
            from_port=-1,
            to_port=-1,
            source_group_id='sg-source'
        )
        
        # Verify call
        call_args = mock_ec2.authorize_security_group_ingress.call_args[1]
        
        assert call_args['IpPermissions'][0]['IpProtocol'] == '-1'
        # Should NOT have FromPort/ToPort for all traffic
        assert 'FromPort' not in call_args['IpPermissions'][0]
        assert 'ToPort' not in call_args['IpPermissions'][0]
    
    @patch('boto3.client')
    def test_create_egress_rule(self, mock_boto_client):
        """Test creating egress rule."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        client = AWSSecurityGroupClient()
        client.create_egress_rule(
            group_id='sg-source',
            protocol='tcp',
            from_port=443,
            to_port=443,
            dest_group_id='sg-dest',
            description='Allow HTTPS to dest'
        )
        
        # Verify call
        mock_ec2.authorize_security_group_egress.assert_called_once()
        call_args = mock_ec2.authorize_security_group_egress.call_args[1]
        
        assert call_args['GroupId'] == 'sg-source'
        assert call_args['IpPermissions'][0]['IpProtocol'] == 'tcp'
        assert call_args['IpPermissions'][0]['FromPort'] == 443
        assert call_args['IpPermissions'][0]['ToPort'] == 443
        assert call_args['IpPermissions'][0]['UserIdGroupPairs'][0]['GroupId'] == 'sg-dest'
    
    @patch('boto3.client')
    def test_delete_ingress_rule(self, mock_boto_client):
        """Test deleting ingress rule."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        client = AWSSecurityGroupClient()
        client.delete_ingress_rule(
            group_id='sg-dest',
            protocol='tcp',
            from_port=80,
            to_port=80,
            source_group_id='sg-source'
        )
        
        # Verify call
        mock_ec2.revoke_security_group_ingress.assert_called_once()
        call_args = mock_ec2.revoke_security_group_ingress.call_args[1]
        
        assert call_args['GroupId'] == 'sg-dest'
        assert call_args['IpPermissions'][0]['IpProtocol'] == 'tcp'
        assert call_args['IpPermissions'][0]['FromPort'] == 80
    
    @patch('boto3.client')
    def test_delete_rule_not_found_ignored(self, mock_boto_client):
        """Test that 'rule not found' error is ignored during delete."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        # Mock ClientError with NotFound
        error_response = {'Error': {'Code': 'InvalidPermission.NotFound'}}
        mock_ec2.revoke_security_group_ingress.side_effect = \
            mock_ec2.exceptions.ClientError(error_response, 'RevokeSecurityGroupIngress')
        
        client = AWSSecurityGroupClient()
        
        # Should not raise exception
        client.delete_ingress_rule(
            group_id='sg-dest',
            protocol='tcp',
            from_port=80,
            to_port=80,
            source_group_id='sg-source'
        )
    
    @patch('boto3.client')
    def test_rule_exists_cidr(self, mock_boto_client):
        """Test checking if rule exists with CIDR source."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_security_groups.return_value = {
            'SecurityGroups': [{
                'GroupId': 'sg-dest',
                'IpPermissions': [
                    {
                        'IpProtocol': 'tcp',
                        'FromPort': 22,
                        'ToPort': 22,
                        'IpRanges': [
                            {'CidrIp': '10.0.0.0/8'}
                        ]
                    }
                ],
                'IpPermissionsEgress': []
            }]
        }
        
        client = AWSSecurityGroupClient()
        
        exists = client.rule_exists(
            group_id='sg-dest',
            direction='ingress',
            protocol='tcp',
            from_port=22,
            to_port=22,
            cidr='10.0.0.0/8'
        )
        
        assert exists is True


class TestVPCDiscovery:
    """Test VPC auto-discovery functionality."""
    
    @patch('boto3.client')
    def test_discover_vpc_by_tags_success_single_vpc(self, mock_boto_client):
        """Test successful VPC discovery with single VPC matching tags."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_vpcs.return_value = {
            'Vpcs': [
                {
                    'VpcId': 'vpc-12345678',
                    'Tags': [
                        {'Key': 'Customer', 'Value': 'customer'},
                        {'Key': 'Project', 'Value': 'project'},
                        {'Key': 'Region', 'Value': 'us-east-2'},
                        {'Key': 'Environment', 'Value': 'shared'}
                    ]
                }
            ]
        }
        
        client = AWSSecurityGroupClient(region='us-east-2')
        
        vpc_id = client.discover_vpc_by_tags(
            customer='customer',
            project='project',
            region='us-east-2',
            environment='shared'
        )
        
        assert vpc_id == 'vpc-12345678'
        
        # Verify correct filters were used
        mock_ec2.describe_vpcs.assert_called_once_with(
            Filters=[
                {'Name': 'tag:Customer', 'Values': ['customer']},
                {'Name': 'tag:Project', 'Values': ['project']},
                {'Name': 'tag:Region', 'Values': ['us-east-2']},
                {'Name': 'tag:Environment', 'Values': ['shared']}
            ]
        )
    
    @patch('boto3.client')
    def test_discover_vpc_by_tags_not_found(self, mock_boto_client):
        """Test VPC discovery when no VPC matches tags."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_vpcs.return_value = {'Vpcs': []}
        
        client = AWSSecurityGroupClient(region='us-east-2')
        
        vpc_id = client.discover_vpc_by_tags(
            customer='NonExistent',
            project='Project',
            region='us-east-2',
            environment='production'
        )
        
        assert vpc_id is None
    
    @patch('boto3.client')
    def test_discover_vpc_by_tags_multiple_vpcs_with_current_deployment(self, mock_boto_client):
        """Test VPC discovery with multiple VPCs using CurrentDeployment fallback."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_vpcs.return_value = {
            'Vpcs': [
                {
                    'VpcId': 'vpc-primary',
                    'Tags': [
                        {'Key': 'Customer', 'Value': 'customer'},
                        {'Key': 'Project', 'Value': 'project'},
                        {'Key': 'Region', 'Value': 'us-east-2'},
                        {'Key': 'Environment', 'Value': 'shared'},
                        {'Key': 'CurrentDeployment', 'Value': 'Primary'}
                    ]
                },
                {
                    'VpcId': 'vpc-secondary',
                    'Tags': [
                        {'Key': 'Customer', 'Value': 'customer'},
                        {'Key': 'Project', 'Value': 'project'},
                        {'Key': 'Region', 'Value': 'us-east-2'},
                        {'Key': 'Environment', 'Value': 'shared'},
                        {'Key': 'CurrentDeployment', 'Value': 'Secondary'}
                    ]
                }
            ]
        }
        
        client = AWSSecurityGroupClient(region='us-east-2')
        
        vpc_id = client.discover_vpc_by_tags(
            customer='customer',
            project='project',
            region='us-east-2',
            environment='shared',
            current_deployment='Primary'
        )
        
        assert vpc_id == 'vpc-primary'
    
    @patch('boto3.client')
    def test_discover_vpc_by_tags_multiple_vpcs_error(self, mock_boto_client):
        """Test VPC discovery fails when multiple VPCs found without CurrentDeployment."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        mock_ec2.describe_vpcs.return_value = {
            'Vpcs': [
                {'VpcId': 'vpc-111', 'Tags': []},
                {'VpcId': 'vpc-222', 'Tags': []}
            ]
        }
        
        client = AWSSecurityGroupClient(region='us-east-2')
        
        with pytest.raises(ValueError) as exc_info:
            client.discover_vpc_by_tags(
                customer='customer',
                project='project',
                region='us-east-2',
                environment='shared'
            )
        
        assert 'Multiple VPCs found' in str(exc_info.value)
        assert 'vpc-111' in str(exc_info.value)
        assert 'vpc-222' in str(exc_info.value)
    
    @patch('boto3.client')
    def test_discover_vpc_by_tags_rate_limiting(self, mock_boto_client):
        """Test VPC discovery handles rate limiting gracefully."""
        mock_ec2 = Mock()
        mock_boto_client.return_value = mock_ec2
        
        # Simulate rate limiting error
        mock_ec2.describe_vpcs.side_effect = Exception()
        mock_ec2.exceptions.ClientError = Exception
        
        # Create a proper ClientError mock
        error_response = {'Error': {'Code': 'RequestLimitExceeded'}}
        client_error = type('ClientError', (Exception,), {})()
        client_error.response = error_response
        mock_ec2.describe_vpcs.side_effect = client_error
        
        client = AWSSecurityGroupClient(region='us-east-2')
        
        vpc_id = client.discover_vpc_by_tags(
            customer='customer',
            project='project',
            region='us-east-2',
            environment='shared'
        )
        
        # Should return None on rate limiting to allow retry
        assert vpc_id is None

