"""YAML report generator for chaining results."""

import yaml
from typing import List, Dict, Any
from datetime import datetime


class Reporter:
    """Generates human-readable YAML reports for chain execution."""
    
    @staticmethod
    def generate_report(
        results: List[Dict[str, Any]],
        mode: str,
        start_time: float,
        end_time: float,
        vpc_id: str,
        region: str,
        vpc_discovery_metadata: Dict[str, Any] = None
    ) -> str:
        """
        Generate YAML report from chain execution results.
        
        Args:
            results: List of chain execution results
            mode: Operation mode (apply/destroy)
            start_time: Execution start timestamp
            end_time: Execution end timestamp
            vpc_id: VPC ID used (or None if discovery failed)
            region: AWS region
            vpc_discovery_metadata: Optional VPC discovery metadata
        
        Returns:
            YAML string
        """
        duration = end_time - start_time
        
        # Calculate summary statistics
        total = len(results)
        successful = sum(1 for r in results if r['status'] == 'success')
        partial = sum(1 for r in results if r['status'] == 'partial_success')
        failed = sum(1 for r in results if r['status'] in ['failed', 'timeout', 'error'])
        
        # Build report structure
        report = {
            'security_group_chainer_report': {
                'metadata': {
                    'timestamp': datetime.fromtimestamp(start_time).isoformat(),
                    'duration_seconds': round(duration, 2),
                    'mode': mode,
                    'vpc_id': vpc_id,
                    'region': region
                },
                'summary': {
                    'total_chains': total,
                    'successful': successful,
                    'partial_success': partial,
                    'failed': failed,
                    'overall_status': 'success' if failed == 0 else ('partial' if successful > 0 else 'failed')
                },
                'chains': []
            }
        }
        
        # Add VPC discovery metadata if available
        if vpc_discovery_metadata:
            report['security_group_chainer_report']['vpc_discovery'] = vpc_discovery_metadata
        
        # Add individual chain results
        for result in results:
            chain_report = {
                'name': result['name'],
                'status': result['status'],
                'master_tier': result['master_tier'],
                'slave_tier': result['slave_tier'],
                'master_security_groups': result['master_security_groups'],
                'slave_security_groups': result['slave_security_groups'],
            }
            
            if result['rules_created']:
                chain_report['actions'] = result['rules_created']
            
            if result['errors']:
                chain_report['errors'] = result['errors']
            
            report['security_group_chainer_report']['chains'].append(chain_report)
        
        # Convert to YAML with nice formatting
        return yaml.dump(
            report,
            default_flow_style=False,
            sort_keys=False,
            allow_unicode=True,
            width=120
        )
    
    @staticmethod
    def save_report(report_yaml: str, output_path: str = "/tmp/chainer-report.yaml") -> None:
        """Save report to file."""
        with open(output_path, 'w') as f:
            f.write(report_yaml)
        print(f"\n📄 Report saved to: {output_path}")
