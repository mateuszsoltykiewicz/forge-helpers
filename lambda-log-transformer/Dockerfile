# Use AWS Lambda Python 3.13 base image (Amazon Linux 2023)
FROM public.ecr.aws/lambda/python:3.13

# Copy application code to Lambda task root
COPY src/ ${LAMBDA_TASK_ROOT}/

# No external dependencies needed (using Python stdlib only)
# boto3 is provided by AWS Lambda runtime

# Lambda handler entrypoint
CMD ["handler.lambda_handler"]
