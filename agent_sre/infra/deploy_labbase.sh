#!/bin/bash
###############################################################################
# LAB BASE 배포 (각 수강생이 자기 환경에 1회 실행).
# injector Lambda(자기 RDS 대상) + 에이전트 IAM 역할 + 세션 버킷 + 의존성 레이어를
# 만듭니다. 핵심 실습(S3 Vectors / KB / 에이전트 Lambda)은 이후 콘솔에서 직접.
#
# 사전: coffee-serverless 스택이 같은 환경에 배포돼 있어야 합니다.
# 사용: ./infra/deploy_labbase.sh [region]
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT="$(cd "$HERE/.." && pwd)"
COFFEE_STACK="coffee-serverless"
STACK="copilot-labbase"
CODE_BUCKET="coffee-lambda-code-${ACCOUNT}-apne2"   # 정규 coffee 빌드가 있는 버킷 재사용

echo ">> [1/4] injector Lambda 패키징 (Node)"
INJ="$(mktemp -d)"
cp -r "$COPILOT/faults/injector_lambda/." "$INJ/"
( cd "$INJ" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 && zip -qr /tmp/injector.zip . )
aws s3 cp /tmp/injector.zip "s3://$CODE_BUCKET/copilot/injector.zip" --region "$REGION"

echo ">> [2/4] 의존성 레이어 빌드 (Python, linux wheels)"
LYR="$(mktemp -d)"; mkdir -p "$LYR/python"
python3 -m pip install -r "$COPILOT/requirements.txt" -t "$LYR/python" \
  --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all: --quiet
rm -rf "$LYR/python"/boto3 "$LYR/python"/botocore "$LYR/python"/boto3-* "$LYR/python"/botocore-*
( cd "$LYR" && zip -qr /tmp/layer.zip . -x "*.pyc" "*/__pycache__/*" )
aws s3 cp /tmp/layer.zip "s3://$CODE_BUCKET/copilot/layer.zip" --region "$REGION"

echo ">> [3/4] coffee-serverless 배선 읽기"
out() { aws cloudformation describe-stacks --stack-name "$COFFEE_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
res() { aws cloudformation describe-stack-resources --stack-name "$COFFEE_STACK" --region "$REGION" \
  --logical-resource-id "$1" --query "StackResources[0].PhysicalResourceId" --output text; }
DB_HOST="$(out DBInstanceEndpoint)"
SUBNET1="$(res PrivateSubnet1)"; SUBNET2="$(res PrivateSubnet2)"
LAMBDA_SG="$(res LambdaSecurityGroup)"

echo ">> [4/4] $STACK 배포"
aws cloudformation deploy \
  --template-file "$COPILOT/infra/LabBase_CF.yaml" \
  --stack-name "$STACK" --capabilities CAPABILITY_NAMED_IAM --region "$REGION" \
  --parameter-overrides \
    "PrivateSubnetIds=${SUBNET1},${SUBNET2}" \
    "LambdaSecurityGroupId=${LAMBDA_SG}" \
    "DbHost=${DB_HOST}" \
    "CodeBucket=${CODE_BUCKET}"

# 같은 S3 키로 다시 올려도 CFN이 코드를 안 끌어오므로 injector는 강제 갱신.
aws lambda update-function-code --function-name coffee-fault-injector --region "$REGION" \
  --s3-bucket "$CODE_BUCKET" --s3-key copilot/injector.zip --query LastModified --output text >/dev/null 2>&1 || true
aws lambda wait function-updated --function-name coffee-fault-injector --region "$REGION" 2>/dev/null || true

rm -rf "$INJ" "$LYR" /tmp/injector.zip /tmp/layer.zip
echo ">> 완료. 아래 출력값을 에이전트 Lambda 만들 때 사용하세요:"
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs" --output table
