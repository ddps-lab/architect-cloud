#!/bin/bash
###############################################################################
# LAB BASE 배포 (각 수강생이 자기 환경에 1회 실행).
# injector Lambda(자기 RDS 대상) + 에이전트 IAM 역할 + 세션 버킷 + 의존성 레이어를
# 만듭니다. 핵심 실습(S3 Vectors / KB / 에이전트 Lambda)은 이후 콘솔에서 직접.
#
# ※ CloudShell 사양/용량 부담을 피하려고 무거운 산출물(injector.zip / layer.zip)은
#   강사가 미리 빌드해 공유 버킷에 올려둡니다. 이 스크립트는 빌드 없이 그것을
#   내 CODE_BUCKET 으로 `aws s3 cp` 만 합니다.
#
# 사전: coffee-serverless 스택이 같은 환경에 배포돼 있어야 합니다.
# 사용: ./infra/deploy_labbase.sh [region]
# (강사 안내가 다르면) SHARED_BUCKET=<강사가 알려준 버킷> ./infra/deploy_labbase.sh
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT="$(cd "$HERE/.." && pwd)"
COFFEE_STACK="coffee-serverless"
STACK="copilot-labbase"
CODE_BUCKET="coffee-lambda-code-${ACCOUNT}-apne2"        # 내 정규 coffee 빌드 버킷 재사용
SHARED_BUCKET="${SHARED_BUCKET:-copilot-artifacts-786382940258-apne2}"  # 강사 공유 버킷

echo ">> [1/4] 공유 산출물 가져오기 (빌드 없음, cp 만): $SHARED_BUCKET"
aws s3 cp "s3://$SHARED_BUCKET/copilot/injector.zip" "s3://$CODE_BUCKET/copilot/injector.zip" --region "$REGION"
aws s3 cp "s3://$SHARED_BUCKET/copilot/layer.zip"    "s3://$CODE_BUCKET/copilot/layer.zip"    --region "$REGION"

echo ">> [2/4] coffee-serverless 배선 읽기"
out() { aws cloudformation describe-stacks --stack-name "$COFFEE_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
res() { aws cloudformation describe-stack-resources --stack-name "$COFFEE_STACK" --region "$REGION" \
  --logical-resource-id "$1" --query "StackResources[0].PhysicalResourceId" --output text; }
DB_HOST="$(out DBInstanceEndpoint)"
SUBNET1="$(res PrivateSubnet1)"; SUBNET2="$(res PrivateSubnet2)"
LAMBDA_SG="$(res LambdaSecurityGroup)"

echo ">> [3/4] $STACK 배포"
aws cloudformation deploy \
  --template-file "$COPILOT/infra/LabBase_CF.yaml" \
  --stack-name "$STACK" --capabilities CAPABILITY_NAMED_IAM --region "$REGION" \
  --parameter-overrides \
    "PrivateSubnetIds=${SUBNET1},${SUBNET2}" \
    "LambdaSecurityGroupId=${LAMBDA_SG}" \
    "DbHost=${DB_HOST}" \
    "CodeBucket=${CODE_BUCKET}"

echo ">> [4/4] injector 코드 강제 갱신 (같은 S3 키면 CFN이 안 끌어오므로)"
aws lambda update-function-code --function-name coffee-fault-injector --region "$REGION" \
  --s3-bucket "$CODE_BUCKET" --s3-key copilot/injector.zip --query LastModified --output text >/dev/null 2>&1 || true
aws lambda wait function-updated --function-name coffee-fault-injector --region "$REGION" 2>/dev/null || true

echo ">> 완료. 아래 출력값을 에이전트 Lambda 만들 때 사용하세요:"
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs" --output table
