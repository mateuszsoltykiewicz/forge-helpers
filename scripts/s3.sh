#!/bin/bash
set -e

ACCOUNT_ID="398456183268"
REGION="eu-central-1"
ENVIRONMENTS=("dev" "staging" "prod")

for ENV in "${ENVIRONMENTS[@]}"; do
  BUCKET_NAME="customer-project-${ENV}-application-recordings"
  USER_NAME="customerproject${ENV}VideoCallingRecordingsRole"  # IAM user (naming convention with "Role")
  POLICY_NAME="${USER_NAME}Policy"

  echo "=== Processing environment: $ENV ==="
  echo "Bucket: $BUCKET_NAME"
  echo "IAM User: $USER_NAME"
  echo "Policy: $POLICY_NAME"

  # Create S3 bucket
  echo "Creating S3 bucket: $BUCKET_NAME"
  aws s3 mb "s3://${BUCKET_NAME}" --region "$REGION"

  # Create IAM policy for full S3 access to the bucket (LiveKit requirements: PutObject, GetObject, etc.)
  POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF
  )

  echo "Creating IAM policy: $POLICY_NAME"
  POLICY_ARN=$(aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "$POLICY_DOCUMENT" --query 'Policy.Arn' --output text)

  # Create IAM user
  echo "Creating IAM user: $USER_NAME"
  aws iam create-user --user-name "$USER_NAME"

  # Attach policy to user
  echo "Attaching policy to user: $USER_NAME"
  aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN"

  # Create access keys for the user
  echo "Creating access keys for user: $USER_NAME"
  KEYS=$(aws iam create-access-key --user-name "$USER_NAME")
  ACCESS_KEY=$(echo "$KEYS" | jq -r '.AccessKey.AccessKeyId')
  SECRET_KEY=$(echo "$KEYS" | jq -r '.AccessKey.SecretAccessKey')

  # Print summary
  echo "Summary for $ENV:"
  echo "  - S3 Bucket: $BUCKET_NAME"
  echo "  - S3 Endpoint: https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com"
  echo "  - IAM User: $USER_NAME"
  echo "  - IAM Policy: $POLICY_ARN"
  echo "  - Access Key: $ACCESS_KEY"
  echo "  - Secret Key: $SECRET_KEY"
  echo "  - Access: Full S3 access to bucket (PutObject, GetObject, DeleteObject, ListBucket) for LiveKit Cloud recording uploads."
  echo ""

  # Note: In production, store keys securely (e.g., AWS Secrets Manager) and rotate them.
done

echo "All buckets, users, policies, and keys created successfully."
