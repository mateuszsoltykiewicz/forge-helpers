"""Simplified AWS client for security group operations."""

import boto3
from typing import List, Optional, Dict, Any


class AWSSecurityGroupClient:
    """Wrapper around boto3 for security group operations."""
    
    def __init__(self, region: str = "us-east-1"):
        self.ec2 = boto3.client('ec2', region_name=region)
        self.region = region
    
    def find_security_groups_by_tier(
        self,
        vpc_id: str,
        firewall_tier: str,
        purpose: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Find all security groups with specific FirewallTier tag.
        
        Args:
            vpc_id: VPC ID to search within
            firewall_tier: FirewallTier tag value (e.g., 'EKSNodes', 'VPCEndpoints')
            purpose: Optional Purpose tag value for granular filtering (e.g., 'worker-nodes', 'logs', 'kms')
        
        Returns:
            List of security group dicts with 'GroupId', 'GroupName', and 'Tags'
        """
        filters = [
            {'Name': 'vpc-id', 'Values': [vpc_id]},
            {'Name': 'tag:FirewallTier', 'Values': [firewall_tier]}
        ]
        
        # Add purpose filter if specified for granular identification
        if purpose:
            filters.append({'Name': 'tag:Purpose', 'Values': [purpose]})
        
        response = self.ec2.describe_security_groups(Filters=filters)
        
        return [
            {
                'GroupId': sg['GroupId'],
                'GroupName': sg['GroupName'],
                'Tags': {tag['Key']: tag['Value'] for tag in sg.get('Tags', [])}
            }
            for sg in response['SecurityGroups']
        ]
    
    def rule_exists(
        self,
        group_id: str,
        direction: str,  # 'ingress' or 'egress'
        protocol: str,
        from_port: int,
        to_port: int,
        source_group_id: Optional[str] = None,
        cidr: Optional[str] = None
    ) -> bool:
        """Check if a specific rule already exists."""
        response = self.ec2.describe_security_groups(GroupIds=[group_id])
        sg = response['SecurityGroups'][0]
        
        rules = sg['IpPermissions'] if direction == 'ingress' else sg['IpPermissionsEgress']
        
        for rule in rules:
            # Check protocol and ports
            rule_protocol = rule.get('IpProtocol', '')
            if protocol == '-1':  # All traffic
                protocol_match = rule_protocol == '-1'
            else:
                protocol_match = rule_protocol == protocol
            
            if not protocol_match:
                continue
            
            # Check port range
            if protocol != '-1':
                rule_from = rule.get('FromPort')
                rule_to = rule.get('ToPort')
                if rule_from != from_port or rule_to != to_port:
                    continue
            
            # Check source (security group or CIDR)
            if source_group_id:
                for user_id_group_pair in rule.get('UserIdGroupPairs', []):
                    if user_id_group_pair['GroupId'] == source_group_id:
                        return True
            elif cidr:
                for ip_range in rule.get('IpRanges', []):
                    if ip_range['CidrIp'] == cidr:
                        return True
        
        return False
    
    def create_ingress_rule(
        self,
        group_id: str,
        protocol: str,
        from_port: int,
        to_port: int,
        source_group_id: str,
        description: str = ""
    ) -> None:
        """Create ingress rule allowing traffic from source security group."""
        ip_permissions = [{
            'IpProtocol': protocol,
            'UserIdGroupPairs': [{
                'GroupId': source_group_id,
                'Description': description
            }]
        }]
        
        # Add port range if not all traffic
        if protocol != '-1':
            ip_permissions[0]['FromPort'] = from_port
            ip_permissions[0]['ToPort'] = to_port
        
        self.ec2.authorize_security_group_ingress(
            GroupId=group_id,
            IpPermissions=ip_permissions
        )
    
    def create_egress_rule(
        self,
        group_id: str,
        protocol: str,
        from_port: int,
        to_port: int,
        dest_group_id: str,
        description: str = ""
    ) -> None:
        """Create egress rule allowing traffic to destination security group."""
        ip_permissions = [{
            'IpProtocol': protocol,
            'UserIdGroupPairs': [{
                'GroupId': dest_group_id,
                'Description': description
            }]
        }]
        
        # Add port range if not all traffic
        if protocol != '-1':
            ip_permissions[0]['FromPort'] = from_port
            ip_permissions[0]['ToPort'] = to_port
        
        self.ec2.authorize_security_group_egress(
            GroupId=group_id,
            IpPermissions=ip_permissions
        )
    
    def delete_ingress_rule(
        self,
        group_id: str,
        protocol: str,
        from_port: int,
        to_port: int,
        source_group_id: str
    ) -> None:
        """Delete ingress rule."""
        ip_permissions = [{
            'IpProtocol': protocol,
            'UserIdGroupPairs': [{'GroupId': source_group_id}]
        }]
        
        if protocol != '-1':
            ip_permissions[0]['FromPort'] = from_port
            ip_permissions[0]['ToPort'] = to_port
        
        try:
            self.ec2.revoke_security_group_ingress(
                GroupId=group_id,
                IpPermissions=ip_permissions
            )
        except self.ec2.exceptions.ClientError as e:
            if 'InvalidPermission.NotFound' not in str(e):
                raise
    
    def delete_egress_rule(
        self,
        group_id: str,
        protocol: str,
        from_port: int,
        to_port: int,
        dest_group_id: str
    ) -> None:
        """Delete egress rule."""
        ip_permissions = [{
            'IpProtocol': protocol,
            'UserIdGroupPairs': [{'GroupId': dest_group_id}]
        }]
        
        if protocol != '-1':
            ip_permissions[0]['FromPort'] = from_port
            ip_permissions[0]['ToPort'] = to_port
        
        try:
            self.ec2.revoke_security_group_egress(
                GroupId=group_id,
                IpPermissions=ip_permissions
            )
        except self.ec2.exceptions.ClientError as e:
            if 'InvalidPermission.NotFound' not in str(e):
                raise
    
    def discover_vpc_by_tags(
        self,
        customer: str,
        project: str,
        region: str,
        environment: str,
        current_deployment: Optional[str] = None
    ) -> Optional[str]:
        """
        Discover VPC ID by tags (Customer, Project, Region, Environment).
        
        Args:
            customer: Customer tag value (e.g., 'Sanofi')
            project: Project tag value (e.g., 'Cronus')
            region: Region tag value (e.g., 'us-east-2')
            environment: Environment tag value (e.g., 'shared', 'production')
            current_deployment: Optional CurrentDeployment tag for fallback filtering (e.g., 'Primary')
        
        Returns:
            VPC ID (string) if found, None otherwise
        
        Raises:
            ValueError: If multiple VPCs found with same tags (ambiguous)
        """
        filters = [
            {'Name': 'tag:Customer', 'Values': [customer]},
            {'Name': 'tag:Project', 'Values': [project]},
            {'Name': 'tag:Region', 'Values': [region]},
            {'Name': 'tag:Environment', 'Values': [environment]}
        ]
        
        try:
            response = self.ec2.describe_vpcs(Filters=filters)
            vpcs = response.get('Vpcs', [])
            
            # No VPC found
            if not vpcs:
                return None
            
            # Single VPC found - perfect
            if len(vpcs) == 1:
                return vpcs[0]['VpcId']
            
            # Multiple VPCs found - try fallback on CurrentDeployment tag
            if current_deployment:
                filtered_vpcs = [
                    vpc for vpc in vpcs
                    if any(
                        tag['Key'] == 'CurrentDeployment' and tag['Value'] == current_deployment
                        for tag in vpc.get('Tags', [])
                    )
                ]
                
                if len(filtered_vpcs) == 1:
                    return filtered_vpcs[0]['VpcId']
                
                if len(filtered_vpcs) > 1:
                    vpc_ids = [vpc['VpcId'] for vpc in filtered_vpcs]
                    raise ValueError(
                        f"Multiple VPCs found with tags Customer={customer}, Project={project}, "
                        f"Region={region}, Environment={environment}, CurrentDeployment={current_deployment}: "
                        f"{vpc_ids}. Please specify vpc_id explicitly."
                    )
            
            # Multiple VPCs without CurrentDeployment fallback
            vpc_ids = [vpc['VpcId'] for vpc in vpcs]
            raise ValueError(
                f"Multiple VPCs found with tags Customer={customer}, Project={project}, "
                f"Region={region}, Environment={environment}: {vpc_ids}. "
                f"Please specify vpc_id explicitly or provide current_deployment for filtering."
            )
        
        except self.ec2.exceptions.ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', '')
            if error_code in ['RequestLimitExceeded', 'Throttling']:
                # Rate limiting - return None and let polling retry
                return None
            raise
