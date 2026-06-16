#!/bin/bash
###############################################################################
# Publish the chat SPA to the IncidentCopilot ChatBucket and invalidate
# CloudFront. Run AFTER infra/package_and_deploy.sh.
#
# Usage:
#   ./web-chat/deploy_chat.sh [stack-name] [region]
###############################################################################
set -euo pipefail

STACK="${1:-incident-copilot}"
REGION="${2:-${AWS_REGION:-ap-northeast-2}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

out() { aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

BUCKET="$(out ChatBucketName)"
API="$(out AgentApiUrl)"
SITE="$(out ChatSiteUrl)"

echo ">> uploading chat SPA to s3://$BUCKET"
aws s3 sync "$HERE" "s3://$BUCKET" --region "$REGION" \
  --exclude "deploy_chat.sh" --delete

# Invalidate the chat CloudFront distribution
DIST="$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Origins.Items[?contains(DomainName, '$BUCKET')]].Id" \
  --output text)"
if [ -n "$DIST" ]; then
  echo ">> invalidating CloudFront $DIST"
  aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" >/dev/null
fi

echo ">> chat site : $SITE"
echo ">> agent API : $API   (붙여넣고 ⚙︎설정에서 저장)"
