#!/bin/bash
###############################################################################
# Package the agent + injector Lambdas, upload them, gather wiring from the
# existing coffee-serverless stack, and deploy the IncidentCopilot stack.
#
# Prereqs:
#   - coffee-serverless stack deployed (provides VPC/RDS/API + clean code zips)
#   - S3 Vectors created: run kb/setup_s3vectors.sh first and export the ARNs:
#       export VECTOR_BUCKET_ARN=... VECTOR_INDEX_ARN=...
#
# Usage:
#   ./infra/package_and_deploy.sh [region]
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COPILOT="$REPO_ROOT/sre-incident-copilot"
COFFEE_STACK="coffee-serverless"
STACK="incident-copilot"
CODE_BUCKET="coffee-lambda-code-${ACCOUNT}-apne2"   # reused: holds clean coffee zips
AGENT_CODE_BUCKET="$CODE_BUCKET"
EMB_ARN="arn:aws:bedrock:${REGION}::foundation-model/amazon.titan-embed-text-v2:0"

: "${VECTOR_BUCKET_ARN:?run kb/setup_s3vectors.sh and export VECTOR_BUCKET_ARN}"
: "${VECTOR_INDEX_ARN:?run kb/setup_s3vectors.sh and export VECTOR_INDEX_ARN}"

echo ">> packaging injector Lambda (Node)"
INJ="$(mktemp -d)"
cp -r "$COPILOT/faults/injector_lambda/." "$INJ/"
( cd "$INJ" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 && zip -qr /tmp/injector.zip . )
aws s3 cp /tmp/injector.zip "s3://$AGENT_CODE_BUCKET/copilot/injector.zip" --region "$REGION"

echo ">> packaging agent Lambda (Python, linux wheels)"
AG="$(mktemp -d)"
cp -r "$COPILOT/agent" "$AG/agent"
cp "$COPILOT/run.sh" "$AG/run.sh"
chmod +x "$AG/run.sh"
python3 -m pip install -r "$COPILOT/requirements.txt" -t "$AG" \
  --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all: --quiet
( cd "$AG" && zip -qr /tmp/agent.zip . -x "*.pyc" "*/__pycache__/*" )
aws s3 cp /tmp/agent.zip "s3://$AGENT_CODE_BUCKET/copilot/agent.zip" --region "$REGION"

echo ">> reading wiring from $COFFEE_STACK"
out() { aws cloudformation describe-stacks --stack-name "$COFFEE_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
res() { aws cloudformation describe-stack-resources --stack-name "$COFFEE_STACK" --region "$REGION" \
  --logical-resource-id "$1" --query "StackResources[0].PhysicalResourceId" --output text; }

DB_HOST="$(out DBInstanceEndpoint)"
CUST_API="$(out CustomerApiUrl)"
EMP_API="$(out EmployeeApiUrl)"
SUBNET1="$(res PrivateSubnet1)"
SUBNET2="$(res PrivateSubnet2)"
LAMBDA_SG="$(res LambdaSecurityGroup)"

echo "   DB_HOST=$DB_HOST  SG=$LAMBDA_SG  subnets=$SUBNET1,$SUBNET2"

echo ">> deploying $STACK"
aws cloudformation deploy \
  --template-file "$COPILOT/infra/IncidentCopilot_CF.yaml" \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --parameter-overrides \
    "PrivateSubnetIds=${SUBNET1},${SUBNET2}" \
    "LambdaSecurityGroupId=${LAMBDA_SG}" \
    "DbHost=${DB_HOST}" \
    "CustomerApi=${CUST_API}" \
    "EmployeeApi=${EMP_API}" \
    "CodeBucket=${CODE_BUCKET}" \
    "AgentCodeBucket=${AGENT_CODE_BUCKET}" \
    "EmbeddingModelArn=${EMB_ARN}" \
    "VectorBucketArn=${VECTOR_BUCKET_ARN}" \
    "VectorIndexArn=${VECTOR_INDEX_ARN}"

rm -rf "$INJ" "$AG" /tmp/injector.zip /tmp/agent.zip
# CloudFormation does NOT re-pull Lambda code when the S3 key is unchanged, so
# force both functions to the freshly uploaded zips.
echo ">> forcing latest code onto the functions"
aws lambda update-function-code --function-name coffee-fault-injector --region "$REGION" \
  --s3-bucket "$AGENT_CODE_BUCKET" --s3-key "copilot/injector.zip" --query LastModified --output text
aws lambda wait function-updated --function-name coffee-fault-injector --region "$REGION"
aws lambda update-function-code --function-name strands-incident-copilot --region "$REGION" \
  --s3-bucket "$AGENT_CODE_BUCKET" --s3-key "copilot/agent.zip" --query LastModified --output text
aws lambda wait function-updated --function-name strands-incident-copilot --region "$REGION"
echo ">> deploy complete. Outputs:"
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs" --output table
