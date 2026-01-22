# Lambda Log Transformer for Kinesis Firehose

Universal log transformation Lambda for Forge Platform log aggregation.

## Overview

This Lambda function transforms logs from multiple sources (AWS CloudWatch, Kubernetes, CloudWatch Metrics) before delivery to S3 via Kinesis Firehose. It enriches logs with Pattern A metadata (customer, project, environment) for compliance and observability.

## Supported Sources

| Source | Format | Example Stream Name | S3 Prefix |
|--------|--------|---------------------|-----------|
| AWS WAF | JSON | `waf-firehose-stream` | `logs/cloudwatch/waf/` |
| VPC Flow Logs | Space-delimited | `vpc-firehose-stream` | `logs/cloudwatch/vpc/` |
| RDS PostgreSQL | Mixed JSON/text | `rds-firehose-stream` | `logs/cloudwatch/rds/` |
| EKS Events | JSON | `eks-events-firehose-stream` | `logs/kubernetes/events/` |
| EKS Pod Logs | JSON | `eks-pods-firehose-stream` | `logs/kubernetes/pods/` |
| CloudWatch Metrics | JSON (Metric Streams) | `metrics-firehose-stream` | `metrics/cloudwatch/` |

## Output Schema

### Logs
```json
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
    "record_id": "49546986683135544286507457936321625675700192471156785154",
    "ingestion_time": "2026-01-17T10:30:01.000Z"
  }
}
```

### Metrics (Parquet-ready)
```json
{
  "@timestamp": "2026-01-17T10:30:00.000Z",
  "aws_component": "metrics",
  "environment": "production",
  "customer": "acme",
  "project": "forge",
  "namespace": "AWS/EC2",
  "metric_name": "CPUUtilization",
  "dimensions": {"InstanceId": "i-123"},
  "value_max": 45.5,
  "value_min": 12.3,
  "value_sum": 123.4,
  "value_count": 10,
  "unit": "Percent"
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CUSTOMER` | `unknown` | Customer name (from Pattern A common_tags) |
| `PROJECT` | `unknown` | Project name (from Pattern A common_tags) |
| `ENVIRONMENT` | `unknown` | Environment (production, staging, development) |
| `LOG_LEVEL` | `INFO` | Lambda logging level (DEBUG, INFO, WARN, ERROR) |
| `ENABLE_METRICS_PARQUET` | `true` | Enable Parquet-friendly metric output |
| `MAX_NESTING_DEPTH` | `3` | Max depth for recursive JSON parsing |

## Features

### Auto-Detection
Automatically detects log source from Firehose delivery stream ARN:
- `waf-firehose-stream` → WAF parser
- `vpc-firehose-stream` → VPC Flow Logs parser
- `eks-pods-firehose-stream` → Kubernetes pod logs parser

### Recursive JSON Parsing
Handles nested JSON strings up to 3 levels deep:
```json
{"message": "{\"level\":\"info\",\"msg\":\"Server started\"}"}
```
→ Flattened to:
```json
{"message": {"level": "info", "msg": "Server started"}}
```

### Graceful Error Handling
Failed transformations return `ProcessingFailed` status:
- Original record preserved
- Delivered to S3 `processing-failed/` prefix
- SNS alert triggered for investigation

## Performance

- **Timeout**: 180s (handles large batches + metrics processing)
- **Memory**: 1024 MB (for Parquet serialization)
- **Concurrency**: Unreserved (autoscales to 1000)
- **Expected Load**: ~30 pods × 10 logs/s = 300 records/s → ~5 concurrent executions

## Testing Locally

### Build Docker image
```bash
docker build -t lambda-log-transformer:latest .
```

### Run with test WAF log
```bash
docker run --rm \
  -e CUSTOMER=acme \
  -e PROJECT=forge \
  -e ENVIRONMENT=production \
  lambda-log-transformer:latest \
  '{"deliveryStreamArn":"arn:aws:firehose:us-east-1:123:deliverystream/waf-firehose-stream","records":[{"recordId":"test-001","data":"eyJ0aW1lc3RhbXAiOjE1NzYyODA0MTI3NzEsImFjdGlvbiI6IkJMT0NLIn0="}]}'
```

### Run unit tests
```bash
make install-test
make test
```

### Run with coverage
```bash
make coverage
```

## Deployment

### Via docker-builder
```bash
cd forge-helpers/docker-builder
./build.sh ecr lambda-log-transformer
```

This will:
1. Build Docker image
2. Create ECR repository `lambda-log-transformer` (if not exists)
3. Tag as `latest`
4. Push to ECR with vulnerability scanning enabled

### Via Terraform
```hcl
module "lambda_transformer" {
  source = "../../compute/lambda-log-transformer"
  
  common_prefix = local.common_prefix
  common_tags   = local.merged_tags
  environment   = "production"
  
  image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/lambda-log-transformer:latest"
}
```

## ELK/Elasticsearch Integration

### Recommended Index Template
```json
{
  "index_patterns": ["forge-logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1
    },
    "mappings": {
      "properties": {
        "@timestamp": {"type": "date"},
        "aws_component": {"type": "keyword"},
        "environment": {"type": "keyword"},
        "customer": {"type": "keyword"},
        "project": {"type": "keyword"},
        "log_level": {"type": "keyword"},
        "message": {"type": "text"},
        "raw_log": {"type": "object", "enabled": false},
        "metadata": {
          "properties": {
            "source_log_group": {"type": "keyword"},
            "record_id": {"type": "keyword"},
            "ingestion_time": {"type": "date"}
          }
        }
      }
    }
  }
}
```

### Sample Kibana Queries
```
# All ERROR logs in production
log_level:"ERROR" AND environment:"production"

# WAF blocked requests
aws_component:"waf" AND raw_log.action:"BLOCK"

# High CPU metrics
aws_component:"metrics" AND metric_name:"CPUUtilization" AND value_max:>80
```

## Architecture

```
┌─────────────────┐
│  CloudWatch     │
│  Logs (WAF/VPC) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Kinesis        │─────▶│  Lambda Log      │─────▶│  S3 Bucket      │
│  Firehose       │      │  Transformer     │      │  (HIPAA 7-year) │
│  Stream         │      │  (This Lambda)   │      │                 │
└─────────────────┘      └──────────────────┘      └─────────────────┘
         ▲                        │
         │                        │ (ProcessingFailed)
         │                        ▼
┌─────────────────┐      ┌──────────────────┐
│  EKS Pod Logs   │      │  S3 processing-  │
│  (FluentBit)    │      │  failed/ + SNS   │
└─────────────────┘      └──────────────────┘
```

## Troubleshooting

### Lambda timeout errors
- **Symptom**: ProcessingFailed with timeout
- **Solution**: Increase `timeout` to 300s in Terraform module

### Recursive parsing infinite loop
- **Symptom**: Lambda crashes with memory error
- **Solution**: Lower `MAX_NESTING_DEPTH` to 2 or 1

### High cost
- **Symptom**: Lambda duration > 30s per invocation
- **Solution**: Increase `memory_size` to 2048 MB (faster CPU)

### ProcessingFailed rate > 1%
- **Symptom**: Many records in `processing-failed/` prefix
- **Solution**: Check CloudWatch Logs for Lambda errors, fix parser bugs

## License

MIT

## Maintenance

- **Owner**: Platform Team
- **Repo**: `forge-helpers/lambda-log-transformer`
- **CI/CD**: GitHub Actions → ECR
- **Monitoring**: CloudWatch Dashboard `lambda-log-transformer-metrics`
