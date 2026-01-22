"""Test configuration and fixtures."""

import pytest
import json
import base64


@pytest.fixture
def sample_waf_event():
    """Sample WAF log event for Firehose."""
    waf_log = {
        "timestamp": 1576280412771,
        "formatVersion": 1,
        "webaclId": "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/a1b2c3d4",
        "action": "BLOCK",
        "httpRequest": {
            "clientIp": "192.0.2.1",
            "country": "US",
            "uri": "/api/users"
        }
    }
    
    return {
        "deliveryStreamArn": "arn:aws:firehose:us-east-1:123456789012:deliverystream/waf-firehose-stream",
        "records": [{
            "recordId": "test-waf-001",
            "data": base64.b64encode(json.dumps(waf_log).encode('utf-8')).decode('utf-8')
        }]
    }


@pytest.fixture
def sample_vpc_event():
    """Sample VPC Flow Log event."""
    vpc_log = "2 123456789012 eni-1235b8ca123456789 172.31.16.139 172.31.16.21 20641 22 6 20 4249 1418530010 1418530070 ACCEPT OK"
    
    return {
        "deliveryStreamArn": "arn:aws:firehose:us-east-1:123456789012:deliverystream/vpc-firehose-stream",
        "records": [{
            "recordId": "test-vpc-001",
            "data": base64.b64encode(vpc_log.encode('utf-8')).decode('utf-8')
        }]
    }


@pytest.fixture
def sample_rds_event():
    """Sample RDS PostgreSQL log event."""
    rds_log = "2026-01-17 10:30:00 UTC [12345]: [2-1] user=postgres,db=mydb LOG:  connection received: host=10.0.1.5 port=54321"
    
    return {
        "deliveryStreamArn": "arn:aws:firehose:us-east-1:123456789012:deliverystream/rds-firehose-stream",
        "records": [{
            "recordId": "test-rds-001",
            "data": base64.b64encode(rds_log.encode('utf-8')).decode('utf-8')
        }]
    }
