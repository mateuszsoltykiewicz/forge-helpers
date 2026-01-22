#!/usr/bin/env python3
"""
Lambda Log Transformer for Kinesis Firehose
Handles logs from: CloudWatch, EKS Events, EKS Pods, CloudWatch Metrics
"""

import base64
import gzip
import json
import logging
import os
import re
from datetime import datetime
from typing import Dict, List, Any, Optional

# Import source-specific parsers
from formats import (
    parse_waf_log,
    parse_vpc_flow_log,
    parse_rds_log,
    parse_eks_event,
    parse_eks_pod_log,
    parse_cloudwatch_metric
)

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Pattern A metadata from environment
CUSTOMER = os.getenv('CUSTOMER', 'unknown')
PROJECT = os.getenv('PROJECT', 'unknown')
ENVIRONMENT = os.getenv('ENVIRONMENT', 'unknown')
ENABLE_METRICS_PARQUET = os.getenv('ENABLE_METRICS_PARQUET', 'true').lower() == 'true'
MAX_NESTING_DEPTH = int(os.getenv('MAX_NESTING_DEPTH', '3'))


def extract_source_from_arn(delivery_stream_arn: str) -> str:
    """
    Extract source component from Firehose delivery stream ARN.
    
    Examples:
      arn:aws:firehose:us-east-1:123456789012:deliverystream/waf-firehose-stream
      → 'waf'
      
      arn:aws:firehose:us-east-1:123456789012:deliverystream/aws-waf-logs-san-cro-p-use2-shared
      → 'waf'
      
      arn:aws:firehose:us-east-1:123456789012:deliverystream/eks-events-firehose-stream
      → 'eks-events'
    """
    # Check for AWS WAF naming convention (aws-waf-logs-*)
    if 'aws-waf-logs-' in delivery_stream_arn:
        return 'waf'
    
    # Check for standard naming convention (*-firehose-stream-*)
    match = re.search(r'/([^/]+)-firehose-stream', delivery_stream_arn)
    if match:
        return match.group(1)
    
    # Fallback: try to extract from log group (if in metadata)
    return 'unknown'


def decompress_if_gzipped(data: bytes) -> bytes:
    """Decompress data if it's gzip-compressed (magic number 0x1f8b)."""
    if data[:2] == b'\x1f\x8b':
        try:
            return gzip.decompress(data)
        except Exception as e:
            logger.warning(f"Gzip decompression failed: {e}")
            return data
    return data


def parse_json_recursive(data: Any, depth: int = 0) -> Any:
    """
    Recursively parse JSON strings embedded in log data.
    
    Example:
      {"message": "{\"nested\": \"value\"}"}
      → {"message": {"nested": "value"}}
    
    Args:
        data: Input data (dict, list, str, etc.)
        depth: Current recursion depth (stops at MAX_NESTING_DEPTH)
    
    Returns:
        Parsed data with embedded JSON strings converted to objects
    """
    if depth >= MAX_NESTING_DEPTH:
        return data
    
    if isinstance(data, dict):
        return {k: parse_json_recursive(v, depth + 1) for k, v in data.items()}
    
    elif isinstance(data, list):
        return [parse_json_recursive(item, depth + 1) for item in data]
    
    elif isinstance(data, str):
        # Try to parse as JSON
        try:
            parsed = json.loads(data)
            # Recurse if we successfully parsed an object/array
            if isinstance(parsed, (dict, list)):
                return parse_json_recursive(parsed, depth + 1)
            return parsed
        except (json.JSONDecodeError, ValueError):
            return data
    
    return data


def detect_log_level(log_entry: Dict[str, Any]) -> str:
    """
    Auto-detect log level from log entry.
    
    Checks: level, severity, log_level fields, or searches message for keywords.
    """
    # Check explicit fields
    for field in ['level', 'severity', 'log_level', 'logLevel']:
        if field in log_entry:
            level = str(log_entry[field]).upper()
            if level in ['ERROR', 'WARN', 'WARNING', 'INFO', 'DEBUG', 'TRACE', 'FATAL']:
                return level
    
    # Search message for keywords
    message = str(log_entry.get('message', '')).upper()
    if 'ERROR' in message or 'FATAL' in message:
        return 'ERROR'
    elif 'WARN' in message:
        return 'WARN'
    elif 'INFO' in message:
        return 'INFO'
    elif 'DEBUG' in message:
        return 'DEBUG'
    
    return 'INFO'  # Default


def enrich_log_entry(
    log_entry: Dict[str, Any],
    source: str,
    record_id: str,
    source_log_group: Optional[str] = None
) -> Dict[str, Any]:
    """
    Enrich log entry with Pattern A metadata.
    
    Output schema:
    {
      "@timestamp": "2026-01-17T10:30:00.000Z",
      "aws_component": "waf",
      "environment": "production",
      "customer": "acme",
      "project": "forge",
      "log_level": "INFO",
      "message": "...",
      "raw_log": {...},
      "metadata": {
        "source_log_group": "/aws/waf/...",
        "record_id": "...",
        "ingestion_time": "2026-01-17T10:30:01.000Z"
      }
    }
    """
    # Extract timestamp (try multiple formats)
    timestamp = log_entry.get('@timestamp') or log_entry.get('timestamp') or datetime.utcnow().isoformat() + 'Z'
    
    # Ensure ISO8601 format
    if not timestamp.endswith('Z') and '+' not in timestamp:
        timestamp += 'Z'
    
    # Extract message
    message = log_entry.get('message', json.dumps(log_entry))
    
    # Detect log level
    log_level = detect_log_level(log_entry)
    
    # Build enriched entry
    enriched = {
        '@timestamp': timestamp,
        'aws_component': source,
        'environment': ENVIRONMENT,
        'customer': CUSTOMER,
        'project': PROJECT,
        'log_level': log_level,
        'message': message,
        'raw_log': log_entry,
        'metadata': {
            'record_id': record_id,
            'ingestion_time': datetime.utcnow().isoformat() + 'Z'
        }
    }
    
    # Add log group if available
    if source_log_group:
        enriched['metadata']['source_log_group'] = source_log_group
    
    return enriched


def transform_log_record(
    record: Dict[str, Any],
    source: str
) -> Dict[str, Any]:
    """
    Transform a single Firehose record.
    
    Args:
        record: Firehose record with base64-encoded data
        source: Detected source (waf, vpc, rds, eks-events, eks-pods, metrics)
    
    Returns:
        {
          "recordId": "...",
          "result": "Ok" | "Dropped" | "ProcessingFailed",
          "data": "<base64 encoded transformed data>"
        }
    """
    record_id = record['recordId']
    
    try:
        # Step 1: Decode base64
        payload = base64.b64decode(record['data'])
        
        # Step 2: Decompress if gzipped
        payload = decompress_if_gzipped(payload)
        
        # Step 3: Parse as JSON (or plain text)
        try:
            log_entry = json.loads(payload.decode('utf-8'))
        except json.JSONDecodeError:
            # Plain text log (e.g., VPC Flow Logs)
            log_entry = {'message': payload.decode('utf-8', errors='replace')}
        
        # Step 4: Recursive JSON parsing (for embedded JSON strings)
        log_entry = parse_json_recursive(log_entry)
        
        # Step 5: Source-specific parsing
        if source == 'waf':
            log_entry = parse_waf_log(log_entry)
        elif source == 'vpc':
            log_entry = parse_vpc_flow_log(log_entry)
        elif source == 'rds':
            log_entry = parse_rds_log(log_entry)
        elif source == 'eks-events':
            log_entry = parse_eks_event(log_entry)
        elif source == 'eks-pods':
            log_entry = parse_eks_pod_log(log_entry)
        elif source == 'metrics':
            log_entry = parse_cloudwatch_metric(log_entry)
        
        # Step 6: Enrich with Pattern A metadata
        source_log_group = log_entry.get('logGroup') or log_entry.get('log_group')
        enriched = enrich_log_entry(log_entry, source, record_id, source_log_group)
        
        # Step 7: Re-encode as base64
        output_data = base64.b64encode(
            json.dumps(enriched).encode('utf-8')
        ).decode('utf-8')
        
        return {
            'recordId': record_id,
            'result': 'Ok',
            'data': output_data
        }
    
    except Exception as e:
        logger.error(f"Error processing record {record_id}: {e}", exc_info=True)
        
        # Return original record with ProcessingFailed status
        return {
            'recordId': record_id,
            'result': 'ProcessingFailed',
            'data': record['data']  # Original base64 data
        }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, List[Dict[str, Any]]]:
    """
    AWS Lambda handler for Kinesis Firehose transformation.
    
    Input event structure:
    {
      "invocationId": "...",
      "deliveryStreamArn": "arn:aws:firehose:us-east-1:123456789012:deliverystream/waf-firehose-stream",
      "region": "us-east-1",
      "records": [
        {
          "recordId": "...",
          "approximateArrivalTimestamp": 1495072949453,
          "data": "SGVsbG8sIHRoaXMgaXMgYSB0ZXN0IDEyMy4="
        }
      ]
    }
    
    Output structure:
    {
      "records": [
        {
          "recordId": "...",
          "result": "Ok",
          "data": "<base64 encoded transformed data>"
        }
      ]
    }
    """
    logger.info(f"Processing {len(event['records'])} records")
    
    # Extract source from delivery stream ARN
    delivery_stream_arn = event.get('deliveryStreamArn', '')
    source = extract_source_from_arn(delivery_stream_arn)
    logger.info(f"Detected source: {source}")
    
    # Transform all records
    output_records = []
    for record in event['records']:
        transformed = transform_log_record(record, source)
        output_records.append(transformed)
    
    # Summary statistics
    ok_count = sum(1 for r in output_records if r['result'] == 'Ok')
    failed_count = sum(1 for r in output_records if r['result'] == 'ProcessingFailed')
    
    logger.info(f"Transformation complete: {ok_count} OK, {failed_count} failed")
    
    return {'records': output_records}
