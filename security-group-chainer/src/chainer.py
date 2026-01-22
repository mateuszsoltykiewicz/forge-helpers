#!/usr/bin/env python3
"""
Security Group Chainer - Main Orchestrator

Automatically creates security group rules between tiers based on FirewallTier tags.
Uses async monitoring to handle circular dependencies.
"""

import asyncio
import os
import sys
import time
import argparse
import yaml
import boto3
from typing import List, Dict, Any

from aws_client import AWSSecurityGroupClient
from chain_monitor import ChainMonitor
from circuit_breaker import CircuitBreaker
from reporter import Reporter


def load_config_from_ssm(ssm_parameter: str, region: str) -> Dict[str, Any]:
    """Load configuration from AWS SSM Parameter Store."""
    print(f"📥 Loading configuration from SSM: {ssm_parameter}")
    
    ssm = boto3.client('ssm', region_name=region)
    
    try:
        response = ssm.get_parameter(Name=ssm_parameter, WithDecryption=True)
        config_yaml = response['Parameter']['Value']
        config = yaml.safe_load(config_yaml)
        print(f"✅ Configuration loaded from SSM")
        return config
    except ssm.exceptions.ParameterNotFound:
        raise FileNotFoundError(f"SSM parameter not found: {ssm_parameter}")
    except Exception as e:
        raise Exception(f"Failed to load from SSM: {e}")


def load_config_from_yaml(yaml_path: str) -> Dict[str, Any]:
    """Load configuration from local YAML file."""
    print(f"📂 Loading configuration from YAML: {yaml_path}")
    
    with open(yaml_path, 'r') as f:
        config = yaml.safe_load(f)
    
    print(f"✅ Configuration loaded from YAML")
    return config


def load_config(ssm_parameter: str = None, yaml_path: str = None, region: str = "us-east-1") -> Dict[str, Any]:
    """
    Load configuration (prefer SSM, fallback to YAML).
    
    Priority:
    1. SSM Parameter Store
    2. Local YAML file
    """
    # Try SSM first
    if ssm_parameter:
        try:
            return load_config_from_ssm(ssm_parameter, region)
        except Exception as e:
            print(f"⚠️  Failed to load from SSM: {e}")
            if yaml_path:
                print(f"🔄 Falling back to local YAML")
                return load_config_from_yaml(yaml_path)
            raise
    
    # Fallback to YAML
    if yaml_path:
        return load_config_from_yaml(yaml_path)
    
    raise ValueError("No configuration source provided (SSM or YAML)")


async def wait_for_vpc(
    aws_client: AWSSecurityGroupClient,
    customer: str,
    project: str,
    region: str,
    environment: str,
    current_deployment: str = None,
    timeout: float = 1800.0,
    polling_interval: float = 15.0
) -> tuple[str | None, Dict[str, Any]]:
    """
    Wait for VPC to be created and discoverable by tags.
    
    Args:
        aws_client: AWS client for VPC discovery
        customer: Customer tag value
        project: Project tag value
        region: Region tag value
        environment: Environment tag value
        current_deployment: Optional CurrentDeployment tag for fallback
        timeout: Max time to wait (seconds)
        polling_interval: Time between polling attempts (seconds)
    
    Returns:
        Tuple of (vpc_id, metadata_dict):
            - vpc_id: VPC ID if found, None if timeout
            - metadata: Dict with discovery info (duration, tags_used, error)
    """
    start_time = time.time()
    attempts = 0
    
    tags_used = {
        'Customer': customer,
        'Project': project,
        'Region': region,
        'Environment': environment
    }
    if current_deployment:
        tags_used['CurrentDeployment'] = current_deployment
    
    print(f"\n🔍 VPC Auto-Discovery started...")
    print(f"   Tags: {tags_used}")
    print(f"   Timeout: {timeout}s, Polling interval: {polling_interval}s")
    
    while time.time() - start_time < timeout:
        attempts += 1
        elapsed = time.time() - start_time
        
        try:
            vpc_id = aws_client.discover_vpc_by_tags(
                customer=customer,
                project=project,
                region=region,
                environment=environment,
                current_deployment=current_deployment
            )
            
            if vpc_id:
                duration = time.time() - start_time
                print(f"✅ VPC discovered: {vpc_id} (took {duration:.1f}s, {attempts} attempts)")
                
                metadata = {
                    'method': 'auto-discovery',
                    'vpc_id': vpc_id,
                    'duration_seconds': round(duration, 2),
                    'attempts': attempts,
                    'tags_used': tags_used
                }
                return vpc_id, metadata
        
        except ValueError as e:
            # Multiple VPCs found - ambiguous
            duration = time.time() - start_time
            error_msg = str(e)
            print(f"❌ VPC discovery error: {error_msg}")
            
            metadata = {
                'method': 'auto-discovery',
                'vpc_id': None,
                'duration_seconds': round(duration, 2),
                'attempts': attempts,
                'tags_used': tags_used,
                'error': error_msg
            }
            return None, metadata
        
        except Exception as e:
            # Unexpected error
            print(f"⚠️  VPC discovery attempt {attempts} failed: {e}")
        
        # Wait before next attempt
        remaining = timeout - (time.time() - start_time)
        if remaining > 0:
            sleep_time = min(polling_interval, remaining)
            print(f"   Retry in {sleep_time:.0f}s... (attempt {attempts}, elapsed {elapsed:.0f}s)")
            await asyncio.sleep(sleep_time)
    
    # Timeout reached
    duration = time.time() - start_time
    print(f"⏱️  VPC discovery timeout after {duration:.1f}s ({attempts} attempts)")
    
    metadata = {
        'method': 'auto-discovery',
        'vpc_id': None,
        'duration_seconds': round(duration, 2),
        'attempts': attempts,
        'tags_used': tags_used,
        'error': f'VPC not found after {timeout}s timeout ({attempts} attempts)'
    }
    return None, metadata


async def run_chains(
    chains_config: List[Dict[str, Any]],
    vpc_id: str,
    aws_client: AWSSecurityGroupClient,
    circuit_breaker: CircuitBreaker,
    timeout: float,
    polling_interval: float,
    mode: str
) -> List[Dict[str, Any]]:
    """Run all chain monitors concurrently."""
    monitors = []
    
    for chain_cfg in chains_config:
        monitor = ChainMonitor(
            name=chain_cfg['name'],
            master_tier=chain_cfg['master_tier'],
            slave_tier=chain_cfg['slave_tier'],
            ports=chain_cfg['ports'],
            protocol=chain_cfg.get('protocol', 'tcp'),
            bidirectional=chain_cfg.get('bidirectional', True),
            vpc_id=vpc_id,
            aws_client=aws_client,
            circuit_breaker=circuit_breaker,
            timeout=timeout,
            polling_interval=polling_interval,
            master_purpose=chain_cfg.get('master_purpose_filter'),
            slave_purpose=chain_cfg.get('slave_purpose_filter')
        )
        monitors.append(monitor)
    
    # Run all monitors concurrently
    results = await asyncio.gather(*[m.run(mode) for m in monitors])
    
    return results


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Security Group Chainer')
    parser.add_argument('--mode', choices=['apply', 'destroy'], default='apply',
                        help='Operation mode: apply (create rules) or destroy (delete rules)')
    parser.add_argument('--ssm-parameter', help='SSM parameter name for config')
    parser.add_argument('--yaml-config', help='Local YAML config file path')
    parser.add_argument('--vpc-id', help='VPC ID (overrides env var)')
    parser.add_argument('--region', help='AWS region (overrides env var)')
    parser.add_argument('--output', default='/tmp/chainer-report.yaml',
                        help='Output path for YAML report')
    
    args = parser.parse_args()
    
    # Get region first (needed for loading config)
    region = args.region or os.environ.get('AWS_REGION', 'us-east-1')
    
    # Get configuration sources
    ssm_parameter = args.ssm_parameter or os.environ.get('SSM_PARAMETER')
    yaml_config = args.yaml_config or os.environ.get('YAML_CONFIG')
    
    print("=" * 80)
    print("🔐 SECURITY GROUP CHAINER")
    print("=" * 80)
    print(f"Mode: {args.mode}")
    print(f"Region: {region}")
    print(f"SSM Parameter: {ssm_parameter or 'Not configured'}")
    print(f"YAML Config: {yaml_config or 'Not configured'}")
    print("=" * 80)
    
    start_time = time.time()
    vpc_discovery_metadata = None
    
    try:
        # Load configuration
        config = load_config(ssm_parameter, yaml_config, region)
        
        # Extract settings
        timeout = config.get('timeout_seconds', 1800)
        polling_interval = config.get('polling_interval_seconds', 10)
        circuit_breaker_threshold = config.get('circuit_breaker_threshold', 5)
        chains = config.get('chains', [])
        
        # VPC ID - either from CLI/env or auto-discovery
        vpc_id = args.vpc_id or os.environ.get('VPC_ID') or config.get('vpc_id')
        
        # Initialize AWS client
        aws_client = AWSSecurityGroupClient(region=region)
        
        # VPC Auto-Discovery if vpc_id not provided
        if not vpc_id:
            print(f"\n🔍 VPC ID not provided - starting auto-discovery...")
            
            # Get VPC discovery settings
            vpc_discovery_config = config.get('vpc_discovery', {})
            vpc_timeout = vpc_discovery_config.get('timeout_seconds', 1800)
            vpc_polling = vpc_discovery_config.get('polling_interval_seconds', 15)
            
            # Get tags for discovery
            customer = config.get('customer_name')
            project = config.get('project_name')
            environment = config.get('environment')
            current_deployment = config.get('current_deployment')
            
            if not all([customer, project, region, environment]):
                print("❌ Error: VPC auto-discovery requires customer_name, project_name, region, and environment in config")
                sys.exit(1)
            
            # Wait for VPC
            vpc_id, vpc_discovery_metadata = asyncio.run(wait_for_vpc(
                aws_client=aws_client,
                customer=customer,
                project=project,
                region=region,
                environment=environment,
                current_deployment=current_deployment,
                timeout=vpc_timeout,
                polling_interval=vpc_polling
            ))
            
            if not vpc_id:
                print(f"\n❌ VPC auto-discovery failed: {vpc_discovery_metadata.get('error', 'Unknown error')}")
                print(f"⚠️  Exiting with code 0 (graceful failure)")
                
                # Generate failure report
                report_yaml = Reporter.generate_report(
                    results=[],
                    mode=args.mode,
                    start_time=start_time,
                    end_time=time.time(),
                    vpc_id=None,
                    region=region,
                    vpc_discovery_metadata=vpc_discovery_metadata
                )
                Reporter.save_report(report_yaml, args.output)
                sys.exit(0)
        else:
            # VPC ID provided explicitly
            vpc_discovery_metadata = {
                'method': 'explicit',
                'vpc_id': vpc_id,
                'source': 'CLI argument or environment variable'
            }
            print(f"VPC ID: {vpc_id} (provided explicitly)")
        
        print(f"\n📋 Configuration:")
        print(f"   VPC ID: {vpc_id}")
        print(f"   Timeout: {timeout}s")
        print(f"   Polling interval: {polling_interval}s")
        print(f"   Circuit breaker threshold: {circuit_breaker_threshold}")
        print(f"   Total chains: {len(chains)}")
        
        # Initialize circuit breaker
        circuit_breaker = CircuitBreaker(
            failure_threshold=circuit_breaker_threshold,
            recovery_timeout=60.0,
            success_threshold=2
        )
        
        # Run chains
        print(f"\n🚀 Starting chain execution...")
        results = asyncio.run(run_chains(
            chains,
            vpc_id,
            aws_client,
            circuit_breaker,
            timeout,
            polling_interval,
            args.mode
        ))
        
        end_time = time.time()
        
        # Generate report with VPC discovery metadata
        report_yaml = Reporter.generate_report(
            results,
            args.mode,
            start_time,
            end_time,
            vpc_id,
            region,
            vpc_discovery_metadata=vpc_discovery_metadata
        )
        
        # Print report
        print("\n" + "=" * 80)
        print("📊 EXECUTION REPORT")
        print("=" * 80)
        print(report_yaml)
        
        # Save report
        Reporter.save_report(report_yaml, args.output)
        
        # Determine exit code (always 0 for graceful failure)
        failed_count = sum(1 for r in results if r['status'] in ['failed', 'timeout', 'error'])
        
        if failed_count > 0:
            print(f"\n⚠️  Warning: {failed_count} chain(s) failed, but exiting successfully (graceful failure)")
        else:
            print(f"\n✅ All chains completed successfully!")
        
        sys.exit(0)
        
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        
        # Still exit 0 to not fail terraform apply
        print(f"\n⚠️  Exiting with code 0 (graceful failure)")
        sys.exit(0)


if __name__ == '__main__':
    main()
