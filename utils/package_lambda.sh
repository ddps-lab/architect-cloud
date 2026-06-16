#!/bin/bash
###############################################################################
# Build & upload the Lambda packages used by cloudformation/ServerlessApp_CF.yaml
#
# Usage:
#   ./utils/package_lambda.sh <code-bucket-name> [aws-region]
#
# Creates <code-bucket> if needed, runs `npm install --omit=dev` for each
# microservice, zips the code, and uploads to:
#   s3://<code-bucket>/lambda/customer.zip
#   s3://<code-bucket>/lambda/employee.zip
###############################################################################
set -euo pipefail

CODE_BUCKET="${1:?Usage: package_lambda.sh <code-bucket-name> [region]}"
REGION="${2:-$(aws configure get region)}"
REGION="${REGION:-us-east-1}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/lambda_code/microservice"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo ">> Code bucket : $CODE_BUCKET"
echo ">> Region      : $REGION"

# Create the code bucket if it does not exist
if ! aws s3api head-bucket --bucket "$CODE_BUCKET" 2>/dev/null; then
  echo ">> Creating bucket $CODE_BUCKET"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$CODE_BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$CODE_BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

for svc in customer employee; do
  echo ">> Packaging $svc"
  pkg_dir="$BUILD_DIR/$svc"
  cp -r "$SRC_DIR/$svc" "$pkg_dir"
  ( cd "$pkg_dir" && npm install --omit=dev --no-audit --no-fund )
  ( cd "$pkg_dir" && zip -qr "$BUILD_DIR/$svc.zip" . -x "*.git*" )
  aws s3 cp "$BUILD_DIR/$svc.zip" "s3://$CODE_BUCKET/lambda/$svc.zip"
  echo ">> Uploaded s3://$CODE_BUCKET/lambda/$svc.zip"
done

echo ">> Done. Deploy with:"
echo "   aws cloudformation deploy \\"
echo "     --template-file cloudformation/ServerlessApp_CF.yaml \\"
echo "     --stack-name coffee-serverless \\"
echo "     --capabilities CAPABILITY_IAM \\"
echo "     --parameter-overrides CodeBucket=$CODE_BUCKET"
