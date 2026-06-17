#!/bin/bash
###############################################################################
# Create the S3 Vectors vector bucket + index used as the Bedrock Knowledge Base
# vector store. Run BEFORE deploying infra/IncidentCopilot_CF.yaml; pass the
# printed ARNs as VectorBucketArn / VectorIndexArn parameters.
#
# Dimension 1024 + cosine match amazon.titan-embed-text-v2:0. The Bedrock chunk
# text key is registered as non-filterable metadata (Bedrock convention).
#
# Usage:
#   ./kb/setup_s3vectors.sh [bucket-name] [index-name] [region]
###############################################################################
set -euo pipefail

REGION="${3:-${AWS_REGION:-ap-northeast-2}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${1:-copilot-vectors-${ACCOUNT}-${REGION}}"
INDEX="${2:-postmortems}"

echo ">> region : $REGION"
echo ">> bucket : $BUCKET"
echo ">> index  : $INDEX"

if ! aws s3vectors get-vector-bucket --vector-bucket-name "$BUCKET" --region "$REGION" >/dev/null 2>&1; then
  echo ">> creating vector bucket"
  aws s3vectors create-vector-bucket --vector-bucket-name "$BUCKET" --region "$REGION"
fi

if ! aws s3vectors get-index --vector-bucket-name "$BUCKET" --index-name "$INDEX" --region "$REGION" >/dev/null 2>&1; then
  echo ">> creating vector index (dim=1024, cosine)"
  aws s3vectors create-index \
    --vector-bucket-name "$BUCKET" \
    --index-name "$INDEX" \
    --data-type float32 \
    --dimension 1024 \
    --distance-metric cosine \
    --metadata-configuration nonFilterableMetadataKeys=AMAZON_BEDROCK_TEXT \
    --region "$REGION"
fi

BUCKET_ARN="arn:aws:s3vectors:${REGION}:${ACCOUNT}:bucket/${BUCKET}"
INDEX_ARN="${BUCKET_ARN}/index/${INDEX}"

echo ""
echo "VectorBucketArn = $BUCKET_ARN"
echo "VectorIndexArn  = $INDEX_ARN"
echo ""
echo "Pass these to the CloudFormation stack:"
echo "  --parameter-overrides VectorBucketArn=$BUCKET_ARN VectorIndexArn=$INDEX_ARN"
