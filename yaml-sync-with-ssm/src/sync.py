#!/usr/bin/env python3
"""
YAML-SSM Sync - Synchronize YAML files with AWS SSM Parameter Store

Features:
- Upload YAML to SSM (with validation)
- Download YAML from SSM
- Bi-directional sync
- Compare and detect changes
"""

import argparse
import sys
import os
from typing import Optional

from config_manager import SSMConfigManager
from validator import YAMLValidator, ChainsConfigSchema


def upload_to_ssm(
    yaml_path: str,
    parameter_name: str,
    region: str,
    description: str,
    validate: bool,
    force: bool
) -> int:
    """Upload YAML file to SSM Parameter Store."""
    try:
        print(f"📤 Uploading YAML to SSM")
        print(f"   Source: {yaml_path}")
        print(f"   Destination: {parameter_name}")
        print(f"   Region: {region}")
        
        # Validate YAML if requested
        if validate:
            print(f"   🔍 Validating YAML structure...")
            try:
                YAMLValidator.validate_file(yaml_path, ChainsConfigSchema)
                print(f"   ✅ YAML validation passed")
            except Exception as e:
                print(f"   ❌ YAML validation failed: {e}")
                return 1
        
        # Sync to SSM
        manager = SSMConfigManager(region=region)
        result = manager.sync_from_yaml_file(
            yaml_path=yaml_path,
            parameter_name=parameter_name,
            description=description,
            force=force
        )
        
        if result['status'] == 'updated':
            print(f"   ✅ Successfully uploaded to SSM")
            print(f"      Version: {result['version']}")
            print(f"      Tier: {result['tier']}")
        elif result['status'] == 'skipped':
            print(f"   ⏭️  Skipped: {result['reason']}")
        
        return 0
        
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        return 1
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


def download_from_ssm(
    parameter_name: str,
    yaml_path: str,
    region: str,
    force: bool
) -> int:
    """Download YAML from SSM Parameter Store to file."""
    try:
        print(f"📥 Downloading YAML from SSM")
        print(f"   Source: {parameter_name}")
        print(f"   Destination: {yaml_path}")
        print(f"   Region: {region}")
        
        # Sync from SSM
        manager = SSMConfigManager(region=region)
        result = manager.sync_to_yaml_file(
            parameter_name=parameter_name,
            yaml_path=yaml_path,
            force=force
        )
        
        if result['status'] == 'updated':
            print(f"   ✅ Successfully downloaded from SSM")
        elif result['status'] == 'skipped':
            print(f"   ⏭️  Skipped: {result['reason']}")
        
        return 0
        
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        return 1
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


def compare_yaml_ssm(
    yaml_path: str,
    parameter_name: str,
    region: str
) -> int:
    """Compare local YAML with SSM parameter."""
    try:
        print(f"🔍 Comparing YAML with SSM")
        print(f"   Local: {yaml_path}")
        print(f"   SSM: {parameter_name}")
        print(f"   Region: {region}")
        
        # Read local YAML
        with open(yaml_path, 'r') as f:
            local_content = f.read()
        
        # Compare
        manager = SSMConfigManager(region=region)
        identical = manager.compare_with_local(parameter_name, local_content)
        
        if identical:
            print(f"   ✅ Files are identical")
            return 0
        else:
            print(f"   ⚠️  Files differ")
            return 1
        
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        return 1
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return 1


def validate_yaml(yaml_path: str) -> int:
    """Validate YAML file structure."""
    try:
        print(f"🔍 Validating YAML file: {yaml_path}")
        
        YAMLValidator.validate_file(yaml_path, ChainsConfigSchema)
        
        print(f"   ✅ YAML validation passed")
        return 0
        
    except Exception as e:
        print(f"   ❌ YAML validation failed: {e}")
        return 1


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='YAML-SSM Sync - Synchronize YAML files with AWS SSM Parameter Store'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Upload command
    upload_parser = subparsers.add_parser('upload', help='Upload YAML to SSM')
    upload_parser.add_argument('yaml_file', help='Path to YAML file')
    upload_parser.add_argument('--parameter', required=True, help='SSM parameter name')
    upload_parser.add_argument('--region', default='us-east-1', help='AWS region')
    upload_parser.add_argument('--description', default='Uploaded from YAML file', help='Parameter description')
    upload_parser.add_argument('--validate', action='store_true', help='Validate YAML before upload')
    upload_parser.add_argument('--force', action='store_true', help='Force upload even if identical')
    
    # Download command
    download_parser = subparsers.add_parser('download', help='Download YAML from SSM')
    download_parser.add_argument('yaml_file', help='Path to save YAML file')
    download_parser.add_argument('--parameter', required=True, help='SSM parameter name')
    download_parser.add_argument('--region', default='us-east-1', help='AWS region')
    download_parser.add_argument('--force', action='store_true', help='Force download even if identical')
    
    # Compare command
    compare_parser = subparsers.add_parser('compare', help='Compare local YAML with SSM')
    compare_parser.add_argument('yaml_file', help='Path to YAML file')
    compare_parser.add_argument('--parameter', required=True, help='SSM parameter name')
    compare_parser.add_argument('--region', default='us-east-1', help='AWS region')
    
    # Validate command
    validate_parser = subparsers.add_parser('validate', help='Validate YAML file')
    validate_parser.add_argument('yaml_file', help='Path to YAML file')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # Execute command
    if args.command == 'upload':
        return upload_to_ssm(
            args.yaml_file,
            args.parameter,
            args.region,
            args.description,
            args.validate,
            args.force
        )
    elif args.command == 'download':
        return download_from_ssm(
            args.parameter,
            args.yaml_file,
            args.region,
            args.force
        )
    elif args.command == 'compare':
        return compare_yaml_ssm(
            args.yaml_file,
            args.parameter,
            args.region
        )
    elif args.command == 'validate':
        return validate_yaml(args.yaml_file)
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
