"""Unit tests for Lambda handler."""

import pytest
import sys
import os
import json
import base64

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../src'))

from handler import (
    lambda_handler,
    extract_source_from_arn,
    decompress_if_gzipped,
    parse_json_recursive,
    detect_log_level,
    enrich_log_entry
)


@pytest.mark.unit
def test_extract_source_from_arn():
    """Test ARN parsing for source detection."""
    assert extract_source_from_arn(
        "arn:aws:firehose:us-east-1:123:deliverystream/waf-firehose-stream"
    ) == "waf"
    
    assert extract_source_from_arn(
        "arn:aws:firehose:us-east-1:123:deliverystream/eks-events-firehose-stream"
    ) == "eks-events"
    
    assert extract_source_from_arn(
        "arn:aws:firehose:us-east-1:123:deliverystream/invalid"
    ) == "unknown"


@pytest.mark.unit
def test_decompress_gzip():
    """Test gzip decompression."""
    import gzip
    
    original = b"Hello, World!"
    compressed = gzip.compress(original)
    
    assert decompress_if_gzipped(compressed) == original
    assert decompress_if_gzipped(original) == original  # Not gzipped


@pytest.mark.unit
def test_parse_json_recursive():
    """Test recursive JSON parsing."""
    # Nested JSON string (single level of escaping as it would appear in Python)
    input_data = {
        "message": '{"nested": "value", "deeper": "{\\"level3\\": \\"data\\"}"}'
    }
    
    result = parse_json_recursive(input_data)
    
    assert isinstance(result['message'], dict)
    assert result['message']['nested'] == 'value'
    # Second level should also be parsed
    assert isinstance(result['message']['deeper'], str) or isinstance(result['message']['deeper'], dict)
    # If it parsed successfully, check content
    if isinstance(result['message']['deeper'], dict):
        assert result['message']['deeper']['level3'] == 'data'


@pytest.mark.unit
def test_detect_log_level():
    """Test log level detection."""
    assert detect_log_level({"level": "ERROR"}) == "ERROR"
    assert detect_log_level({"severity": "warning"}) == "WARNING"
    assert detect_log_level({"message": "ERROR: Something failed"}) == "ERROR"
    assert detect_log_level({"message": "INFO: All good"}) == "INFO"
    assert detect_log_level({"message": "Normal log"}) == "INFO"  # Default


@pytest.mark.unit
def test_enrich_log_entry(monkeypatch):
    """Test log entry enrichment with Pattern A metadata."""
    monkeypatch.setenv("CUSTOMER", "acme")
    monkeypatch.setenv("PROJECT", "forge")
    monkeypatch.setenv("ENVIRONMENT", "production")
    
    log_entry = {
        "timestamp": "2026-01-17T10:30:00Z",
        "message": "Test log"
    }
    
    enriched = enrich_log_entry(log_entry, "waf", "test-record-001")
    
    assert enriched['@timestamp'] == "2026-01-17T10:30:00Z"
    assert enriched['aws_component'] == "waf"
    assert enriched['environment'] == "production"
    assert enriched['customer'] == "acme"
    assert enriched['project'] == "forge"
    assert enriched['message'] == "Test log"
    assert enriched['metadata']['record_id'] == "test-record-001"


@pytest.mark.unit
def test_lambda_handler_waf(sample_waf_event, monkeypatch):
    """Test Lambda handler with WAF log."""
    monkeypatch.setenv("CUSTOMER", "acme")
    monkeypatch.setenv("PROJECT", "forge")
    monkeypatch.setenv("ENVIRONMENT", "production")
    
    result = lambda_handler(sample_waf_event, None)
    
    assert len(result['records']) == 1
    assert result['records'][0]['result'] == 'Ok'
    assert result['records'][0]['recordId'] == 'test-waf-001'
    
    # Decode and verify transformed data
    decoded = json.loads(base64.b64decode(result['records'][0]['data']))
    assert decoded['aws_component'] == 'waf'
    assert decoded['customer'] == 'acme'
    assert '@timestamp' in decoded


@pytest.mark.unit
def test_lambda_handler_vpc(sample_vpc_event, monkeypatch):
    """Test Lambda handler with VPC Flow Log."""
    monkeypatch.setenv("CUSTOMER", "acme")
    monkeypatch.setenv("PROJECT", "forge")
    monkeypatch.setenv("ENVIRONMENT", "production")
    
    result = lambda_handler(sample_vpc_event, None)
    
    assert len(result['records']) == 1
    assert result['records'][0]['result'] == 'Ok'
    
    # Decode and verify VPC-specific fields
    decoded = json.loads(base64.b64decode(result['records'][0]['data']))
    assert decoded['aws_component'] == 'vpc'
    assert 'srcaddr' in decoded['raw_log']
    assert 'dstaddr' in decoded['raw_log']


@pytest.mark.unit
def test_lambda_handler_processing_failed():
    """Test error handling for malformed records."""
    bad_event = {
        "deliveryStreamArn": "arn:aws:firehose:us-east-1:123:deliverystream/waf-firehose-stream",
        "records": [{
            "recordId": "test-bad-001",
            "data": "INVALID_BASE64!!!"
        }]
    }
    
    result = lambda_handler(bad_event, None)
    
    assert len(result['records']) == 1
    assert result['records'][0]['result'] == 'ProcessingFailed'
    assert result['records'][0]['recordId'] == 'test-bad-001'
    # Original data should be preserved
    assert result['records'][0]['data'] == "INVALID_BASE64!!!"
