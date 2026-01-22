"""
Source-specific log parsers for different AWS services and Kubernetes.
"""

import re
from datetime import datetime
from typing import Dict, Any


def parse_waf_log(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse AWS WAF log (already JSON format from CloudWatch).
    
    Example input:
    {
      "timestamp": 1576280412771,
      "formatVersion": 1,
      "webaclId": "arn:aws:wafv2:...",
      "action": "BLOCK",
      "httpRequest": {...}
    }
    """
    # WAF logs are already well-structured JSON
    # Just normalize timestamp
    if 'timestamp' in log_entry and isinstance(log_entry['timestamp'], int):
        # Convert epoch millis to ISO8601
        log_entry['@timestamp'] = datetime.utcfromtimestamp(
            log_entry['timestamp'] / 1000
        ).isoformat() + 'Z'
    
    return log_entry


def parse_vpc_flow_log(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse VPC Flow Log (space-delimited format).
    
    Example input (plain text):
    "2 123456789012 eni-1235b8ca123456789 - - - - - - - 1431280876 1431280934 - NODATA"
    
    Format:
    version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
    """
    message = log_entry.get('message', '')
    
    # If already parsed, return as-is
    if isinstance(log_entry, dict) and 'srcaddr' in log_entry:
        return log_entry
    
    # Parse space-delimited format
    fields = message.split()
    if len(fields) >= 14:
        log_entry = {
            'version': fields[0],
            'account_id': fields[1],
            'interface_id': fields[2],
            'srcaddr': fields[3],
            'dstaddr': fields[4],
            'srcport': fields[5],
            'dstport': fields[6],
            'protocol': fields[7],
            'packets': fields[8],
            'bytes': fields[9],
            'start': fields[10],
            'end': fields[11],
            'action': fields[12],
            'log_status': fields[13],
            'message': message  # Keep original
        }
        
        # Add timestamp from start field (epoch seconds)
        try:
            log_entry['@timestamp'] = datetime.utcfromtimestamp(
                int(fields[10])
            ).isoformat() + 'Z'
        except (ValueError, IndexError):
            pass
    
    return log_entry


def parse_rds_log(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse RDS PostgreSQL log (mixed JSON + plain text).
    
    Example inputs:
    1) Plain text: "2026-01-17 10:30:00 UTC [12345]: [2-1] user=postgres,db=mydb LOG:  connection received: host=10.0.1.5 port=54321"
    2) JSON: {"timestamp":"2026-01-17 10:30:00 UTC","message":"SELECT * FROM users"}
    """
    message = log_entry.get('message', '')
    
    # Try to extract timestamp from plain text format
    timestamp_match = re.match(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC)', message)
    if timestamp_match:
        # Convert to ISO8601
        timestamp_str = timestamp_match.group(1).replace(' UTC', '')
        log_entry['@timestamp'] = timestamp_str.replace(' ', 'T') + 'Z'
        
        # Extract log level (LOG, ERROR, WARNING, etc.)
        level_match = re.search(r'\s+(LOG|ERROR|WARNING|FATAL|PANIC|DEBUG):\s+', message)
        if level_match:
            log_entry['level'] = level_match.group(1)
    
    return log_entry


def parse_eks_event(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse Kubernetes Event (JSON from EKS).
    
    Example:
    {
      "kind": "Event",
      "apiVersion": "v1",
      "metadata": {...},
      "involvedObject": {...},
      "reason": "FailedScheduling",
      "message": "0/3 nodes are available...",
      "type": "Warning"
    }
    """
    # Events are already JSON, just normalize fields
    if 'metadata' in log_entry and 'creationTimestamp' in log_entry['metadata']:
        log_entry['@timestamp'] = log_entry['metadata']['creationTimestamp']
    
    # Extract severity from type
    event_type = log_entry.get('type', 'Normal')
    if event_type == 'Warning':
        log_entry['level'] = 'WARN'
    elif event_type == 'Error':
        log_entry['level'] = 'ERROR'
    else:
        log_entry['level'] = 'INFO'
    
    # Add namespace for partitioning
    if 'metadata' in log_entry and 'namespace' in log_entry['metadata']:
        log_entry['namespace'] = log_entry['metadata']['namespace']
    
    return log_entry


def parse_eks_pod_log(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse EKS Pod log (application logs from containers).
    
    Example:
    {
      "log": "{\"level\":\"info\",\"msg\":\"Server started\",\"time\":\"2026-01-17T10:30:00Z\"}",
      "stream": "stdout",
      "time": "2026-01-17T10:30:00.123456789Z",
      "kubernetes": {
        "namespace_name": "default",
        "pod_name": "api-server-abc123",
        "container_name": "api"
      }
    }
    """
    # Try to parse nested log field
    if 'log' in log_entry and isinstance(log_entry['log'], str):
        try:
            import json
            nested = json.loads(log_entry['log'])
            # Merge nested fields into top level
            log_entry.update(nested)
        except json.JSONDecodeError:
            pass  # Keep as plain text
    
    # Use time field as timestamp
    if 'time' in log_entry:
        log_entry['@timestamp'] = log_entry['time']
    
    # Extract namespace and pod name for partitioning
    if 'kubernetes' in log_entry:
        k8s = log_entry['kubernetes']
        log_entry['namespace'] = k8s.get('namespace_name', 'default')
        log_entry['pod_name'] = k8s.get('pod_name', 'unknown')
        log_entry['container_name'] = k8s.get('container_name', 'unknown')
    
    return log_entry


def parse_cloudwatch_metric(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse CloudWatch Metric (from Metric Streams).
    
    Example:
    {
      "metric_stream_name": "...",
      "account_id": "123456789012",
      "region": "us-east-1",
      "namespace": "AWS/EC2",
      "metric_name": "CPUUtilization",
      "dimensions": {"InstanceId": "i-1234567890abcdef0"},
      "timestamp": 1642424400000,
      "value": {
        "max": 45.5,
        "min": 12.3,
        "sum": 123.4,
        "count": 10
      },
      "unit": "Percent"
    }
    """
    # Normalize timestamp (epoch millis → ISO8601)
    if 'timestamp' in log_entry and isinstance(log_entry['timestamp'], int):
        log_entry['@timestamp'] = datetime.utcfromtimestamp(
            log_entry['timestamp'] / 1000
        ).isoformat() + 'Z'
    
    # Prepare for Parquet-friendly schema
    # Flatten value object for better columnar storage
    if 'value' in log_entry and isinstance(log_entry['value'], dict):
        for stat, val in log_entry['value'].items():
            log_entry[f'value_{stat}'] = val
        # Keep original value object too
        log_entry['value_raw'] = log_entry['value']
    
    return log_entry
