#!/bin/bash
###############################################################################
# 공유 채팅 웹 배포 (루트에서 1회). S3+CloudFront 스택을 만들고 SPA를 올립니다.
# 모든 수강생이 이 한 사이트를 쓰며, 각자 자신의 에이전트 Function URL을 화면
# 설정에 입력합니다.
#
# 사용: ./web-chat/deploy_chat.sh [region]
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="copilot-chat-web"

echo ">> 채팅 웹 스택 배포 ($STACK)"
aws cloudformation deploy --template-file "$HERE/ChatWeb_CF.yaml" \
  --stack-name "$STACK" --region "$REGION"

out() { aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
BUCKET="$(out ChatBucketName)"; SITE="$(out ChatSiteUrl)"

echo ">> SPA 업로드 -> s3://$BUCKET"
aws s3 sync "$HERE" "s3://$BUCKET" --region "$REGION" --delete \
  --exclude "*.sh" --exclude "*.yaml"

DIST="$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Origins.Items[?contains(DomainName, '$BUCKET')]].Id" \
  --output text)"
[ -n "$DIST" ] && aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" >/dev/null && echo ">> CloudFront 무효화: $DIST"

echo ">> 채팅 사이트: $SITE"
echo "   (수강생에게 이 URL을 공유하세요. 각자 ⚙︎설정에 자기 Function URL 입력)"
