"""YAML configuration validator using Pydantic."""

from typing import Any, Dict, Optional
from pydantic import BaseModel, Field, field_validator
import yaml


class YAMLValidator:
    """Validates YAML content structure."""
    
    @staticmethod
    def validate_yaml_syntax(yaml_content: str) -> Dict[str, Any]:
        """
        Validate YAML syntax.
        
        Returns:
            Parsed YAML dict
        
        Raises:
            yaml.YAMLError: If YAML is invalid
        """
        try:
            data = yaml.safe_load(yaml_content)
            return data
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML syntax: {e}")
    
    @staticmethod
    def validate_structure(data: Dict[str, Any], schema: Optional[type] = None) -> bool:
        """
        Validate YAML structure against Pydantic schema.
        
        Args:
            data: Parsed YAML dict
            schema: Optional Pydantic BaseModel class for validation
        
        Returns:
            True if valid
        
        Raises:
            ValidationError: If structure is invalid
        """
        if schema and issubclass(schema, BaseModel):
            # Validate using Pydantic
            schema(**data)
        
        return True
    
    @staticmethod
    def validate_file(yaml_path: str, schema: Optional[type] = None) -> Dict[str, Any]:
        """
        Validate YAML file.
        
        Returns:
            Parsed and validated YAML dict
        """
        with open(yaml_path, 'r') as f:
            yaml_content = f.read()
        
        # Validate syntax
        data = YAMLValidator.validate_yaml_syntax(yaml_content)
        
        # Validate structure
        if schema:
            YAMLValidator.validate_structure(data, schema)
        
        return data


# Example schema for security group chains config
class ChainSchema(BaseModel):
    """Schema for a single chain configuration."""
    name: str
    master_tier: str
    slave_tier: str
    ports: list[int]
    protocol: str = "tcp"
    bidirectional: bool = True
    
    @field_validator('protocol')
    @classmethod
    def validate_protocol(cls, v):
        if v not in ['tcp', 'udp', 'icmp', '-1']:
            raise ValueError(f"Invalid protocol: {v}")
        return v
    
    @field_validator('ports')
    @classmethod
    def validate_ports(cls, v):
        for port in v:
            if not 0 <= port <= 65535:
                raise ValueError(f"Invalid port: {port}")
        return v


class ChainsConfigSchema(BaseModel):
    """Schema for complete chains configuration."""
    version: str = "1.0"
    timeout_seconds: int = Field(ge=60, le=7200)
    polling_interval_seconds: int = Field(ge=5, le=60, default=10)
    circuit_breaker_threshold: int = Field(ge=3, le=20, default=5)
    chains: list[ChainSchema]
    
    @field_validator('chains')
    @classmethod
    def validate_chains_not_empty(cls, v):
        if not v:
            raise ValueError("At least one chain must be defined")
        return v
