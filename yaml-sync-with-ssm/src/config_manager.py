"""AWS SSM Parameter Store configuration manager."""

import boto3
from typing import Optional, Dict, Any
import yaml


class SSMConfigManager:
    """Manages configuration in AWS SSM Parameter Store."""
    
    def __init__(self, region: str = "us-east-1"):
        self.ssm = boto3.client('ssm', region_name=region)
        self.region = region
    
    def parameter_exists(self, parameter_name: str) -> bool:
        """Check if SSM parameter exists."""
        try:
            self.ssm.get_parameter(Name=parameter_name)
            return True
        except self.ssm.exceptions.ParameterNotFound:
            return False
    
    def get_parameter(self, parameter_name: str, with_decryption: bool = True) -> Optional[str]:
        """
        Get parameter value from SSM.
        
        Returns:
            Parameter value (string)
            
        Raises:
            ParameterNotFound: If parameter doesn't exist
        """
        try:
            response = self.ssm.get_parameter(
                Name=parameter_name,
                WithDecryption=with_decryption
            )
            return response['Parameter']['Value']
        except self.ssm.exceptions.ParameterNotFound:
            raise FileNotFoundError(f"SSM parameter not found: {parameter_name}")
    
    def put_parameter(
        self,
        parameter_name: str,
        value: str,
        description: str = "",
        parameter_type: str = "String",
        overwrite: bool = True,
        tier: str = "Advanced"
    ) -> Dict[str, Any]:
        """
        Put parameter value to SSM.
        
        Args:
            parameter_name: SSM parameter name (e.g., /forge/config)
            value: Parameter value (YAML string)
            description: Parameter description
            parameter_type: String, StringList, or SecureString
            overwrite: Overwrite existing parameter
            tier: Standard (4KB) or Advanced (8KB)
        
        Returns:
            Response dict with Version and Tier
        """
        response = self.ssm.put_parameter(
            Name=parameter_name,
            Description=description,
            Value=value,
            Type=parameter_type,
            Overwrite=overwrite,
            Tier=tier
        )
        
        return {
            'Version': response['Version'],
            'Tier': response.get('Tier', tier)
        }
    
    def delete_parameter(self, parameter_name: str) -> None:
        """Delete parameter from SSM."""
        try:
            self.ssm.delete_parameter(Name=parameter_name)
        except self.ssm.exceptions.ParameterNotFound:
            pass  # Already deleted
    
    def compare_with_local(self, parameter_name: str, local_yaml_content: str) -> bool:
        """
        Compare SSM parameter value with local YAML content.
        
        Returns:
            True if identical, False if different
        """
        try:
            ssm_value = self.get_parameter(parameter_name)
            
            # Normalize YAML (parse and dump both)
            ssm_data = yaml.safe_load(ssm_value)
            local_data = yaml.safe_load(local_yaml_content)
            
            return ssm_data == local_data
            
        except FileNotFoundError:
            # Parameter doesn't exist = different
            return False
    
    def sync_from_yaml_file(
        self,
        yaml_path: str,
        parameter_name: str,
        description: str = "Synchronized from YAML file",
        force: bool = False
    ) -> Dict[str, Any]:
        """
        Synchronize YAML file to SSM Parameter Store.
        
        Args:
            yaml_path: Path to local YAML file
            parameter_name: SSM parameter name
            description: Parameter description
            force: Force update even if content is identical
        
        Returns:
            Sync result dict with status and details
        """
        # Read YAML file
        with open(yaml_path, 'r') as f:
            yaml_content = f.read()
        
        # Check if update is needed
        if not force and self.compare_with_local(parameter_name, yaml_content):
            return {
                'status': 'skipped',
                'reason': 'SSM parameter already up-to-date',
                'parameter': parameter_name
            }
        
        # Put parameter
        response = self.put_parameter(
            parameter_name=parameter_name,
            value=yaml_content,
            description=description,
            parameter_type='String',
            overwrite=True,
            tier='Advanced'
        )
        
        return {
            'status': 'updated',
            'parameter': parameter_name,
            'version': response['Version'],
            'tier': response['Tier']
        }
    
    def sync_to_yaml_file(
        self,
        parameter_name: str,
        yaml_path: str,
        force: bool = False
    ) -> Dict[str, Any]:
        """
        Synchronize SSM Parameter Store to local YAML file.
        
        Args:
            parameter_name: SSM parameter name
            yaml_path: Path to local YAML file
            force: Force overwrite even if content is identical
        
        Returns:
            Sync result dict with status and details
        """
        # Get parameter from SSM
        ssm_value = self.get_parameter(parameter_name)
        
        # Check if update is needed
        if not force:
            try:
                with open(yaml_path, 'r') as f:
                    local_content = f.read()
                
                if self.compare_with_local(parameter_name, local_content):
                    return {
                        'status': 'skipped',
                        'reason': 'Local YAML file already up-to-date',
                        'file': yaml_path
                    }
            except FileNotFoundError:
                pass  # File doesn't exist, will create
        
        # Write to file
        with open(yaml_path, 'w') as f:
            f.write(ssm_value)
        
        return {
            'status': 'updated',
            'file': yaml_path,
            'source': parameter_name
        }
