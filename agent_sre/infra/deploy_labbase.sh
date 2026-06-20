#!/bin/bash
###############################################################################
# LAB BASE 배포 (각 수강생이 자기 환경에 1회 실행).
# 장애 주입 Lambda(자기 RDS 대상) + 에이전트 IAM 역할 + 세션 버킷을 만듭니다.
# 핵심 실습(S3 Vectors / KB / 에이전트 Lambda)과 의존성 레이어는 이후 콘솔에서 직접.
#
# ※ CloudShell 부담을 피하려고 빌드는 하지 않습니다. 무거운 산출물
#   (injector.zip / layer.zip)은 강사가 미리 빌드해 공유 버킷
#   (samsung-cloud-architect)에 올려둡니다.
#     - injector.zip : 이 CF 가 공유 버킷에서 직접 참조해 배포
#     - layer.zip    : 학생이 콘솔에서 그 S3 링크로 레이어를 직접 생성 (아래 안내)
#
# 사전: coffee-serverless 스택이 같은 환경에 배포돼 있어야 합니다.
# 사용: ./infra/deploy_labbase.sh [region]
# (강사 안내가 다르면) SHARED_BUCKET=<강사가 알려준 버킷> ./infra/deploy_labbase.sh
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT="$(cd "$HERE/.." && pwd)"
COFFEE_STACK="coffee-serverless"
STACK="copilot-labbase"
SHARED_BUCKET="${SHARED_BUCKET:-samsung-cloud-architect}"  # 강사 공유 산출물 버킷
                                                           # (injector·layer·깨끗한 coffee zip)

echo ">> [1/3] coffee-serverless 배선 읽기"
out() { aws cloudformation describe-stacks --stack-name "$COFFEE_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
res() { aws cloudformation describe-stack-resources --stack-name "$COFFEE_STACK" --region "$REGION" \
  --logical-resource-id "$1" --query "StackResources[0].PhysicalResourceId" --output text; }
DB_HOST="$(out DBInstanceEndpoint)"
SUBNET1="$(res PrivateSubnet1)"; SUBNET2="$(res PrivateSubnet2)"
LAMBDA_SG="$(res LambdaSecurityGroup)"

echo ">> [2/3] $STACK 배포 (injector 는 공유 버킷에서 직접 참조)"
aws cloudformation deploy \
  --template-file "$COPILOT/infra/LabBase_CF.yaml" \
  --stack-name "$STACK" --capabilities CAPABILITY_NAMED_IAM --region "$REGION" \
  --parameter-overrides \
    "PrivateSubnetIds=${SUBNET1},${SUBNET2}" \
    "LambdaSecurityGroupId=${LAMBDA_SG}" \
    "DbHost=${DB_HOST}" \
    "CodeBucket=${SHARED_BUCKET}" \
    "ArtifactsBucket=${SHARED_BUCKET}"

echo ">> [3/3] 완료. 아래 출력값을 에이전트 Lambda 만들 때 사용하세요:"
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs" --output table

cat <<EOF

>> [레이어는 직접 만듭니다] 공유 버킷의 layer.zip 으로 Lambda 레이어를 콘솔에서 생성:
   Lambda → Layers → Create layer → Upload a file from Amazon S3

   Amazon S3 링크 URL : https://${SHARED_BUCKET}.s3.${REGION}.amazonaws.com/copilot/layer.zip
   호환 런타임         : Python 3.14

   만든 레이어의 ARN(=DepsLayerArn)을 에이전트 Lambda 에 추가하세요.
EOF
