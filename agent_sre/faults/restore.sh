#!/bin/bash
###############################################################################
# Restore the coffee-serverless microservices to a healthy state after a lab.
# Redeploys the CLEAN lambda_code source and reverts the RDS schema.
#
# Usage:
#   ./faults/restore.sh [region]
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_ROOT/lambda_code/microservice"
INJECTOR="coffee-fault-injector"

invoke_injector() {
  local action="$1"
  echo ">> injector: $action"
  aws lambda invoke --function-name "$INJECTOR" --region "$REGION" \
    --payload "$(printf '{"action":"%s"}' "$action")" --cli-binary-format raw-in-base64-out \
    /dev/stdout | sed -n '1,40p' || true
}

redeploy_clean() {
  local svc="$1"
  local fn="coffee-$svc"
  local work; work="$(mktemp -d)"
  cp -r "$SRC/$svc/." "$work/"
  ( cd "$work" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 )
  ( cd "$work" && zip -qr /tmp/$svc.clean.zip . )
  aws lambda update-function-code --function-name "$fn" --region "$REGION" \
    --zip-file fileb:///tmp/$svc.clean.zip --query LastModified --output text
  aws lambda wait function-updated --function-name "$fn" --region "$REGION"
  rm -rf "$work" /tmp/$svc.clean.zip
  echo ">> restored clean $fn"
}

# DB schema back to healthy (BIGINT id is the F1 fix; phone back to VARCHAR)
invoke_injector restore_id_bigint
invoke_injector restore_phone_varchar
# Clean code back (clears F2 pool/txn fault and F3 audit-log middleware)
redeploy_clean customer
redeploy_clean employee
echo ">> restore complete (note: /tmp ENOSPC clears on next cold start)."
