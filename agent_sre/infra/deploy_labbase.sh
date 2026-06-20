#!/bin/bash
###############################################################################
# LAB BASE 배포 (선택: CLI 를 선호할 때만. 콘솔 배포가 기본 — STUDENT_GUIDE 참고).
# 장애 주입 Lambda(자기 RDS 대상) + 에이전트 IAM 역할/관리형 정책 + 세션 버킷을 만듭니다.
#
# ※ VPC/RDS 배선(서브넷·SG·DB엔드포인트)은 coffee-serverless 스택의 Export 에서
#   ImportValue 로 자동으로 가져옵니다. 입력이 필요 없습니다.
# ※ 무거운 산출물(injector.zip / layer.zip / coffee zip)은 강사가 공유 버킷
#   (samsung-cloud-architect)에 미리 발행 — 빌드/복사 없음.
#
# 사전: coffee-serverless 스택이 같은 환경에 배포돼 있어야 합니다.
# 사용: ./infra/deploy_labbase.sh [region]
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT="$(cd "$HERE/.." && pwd)"
STACK="copilot-labbase"

echo ">> $STACK 배포 (VPC 배선은 coffee-serverless Export 에서 자동 import)"
aws cloudformation deploy \
  --template-file "$COPILOT/infra/LabBase_CF.yaml" \
  --stack-name "$STACK" --capabilities CAPABILITY_NAMED_IAM --region "$REGION"

echo ">> 완료. 아래 출력값을 에이전트 Lambda 만들 때 사용하세요:"
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs" --output table

cat <<EOF

>> [레이어는 직접 만듭니다] 공유 버킷의 layer.zip 으로 Lambda 레이어를 콘솔에서 생성:
   Lambda → Layers → Create layer → Upload a file from Amazon S3

   Amazon S3 링크 URL : https://samsung-cloud-architect.s3.${REGION}.amazonaws.com/copilot/layer.zip
   호환 런타임         : Python 3.14

   만든 레이어의 ARN(=DepsLayerArn)을 에이전트 Lambda 에 추가하세요.
EOF
