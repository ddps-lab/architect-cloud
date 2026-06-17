#!/bin/bash
###############################################################################
# Inject post-mortem faults (Appendix A) into the deployed coffee-serverless
# microservices. DESTRUCTIVE: edits live Lambda code and the live RDS schema.
# Lab use only — run faults/restore.sh afterwards.
#
# Usage:
#   ./faults/inject.sh <f1|f2|f3|f4|all> [region]
#
# Requires the IncidentCopilot stack (provides the coffee-fault-injector Lambda)
# for F1/F4, and the coffee-serverless stack (coffee-customer/employee) for F2/F3.
###############################################################################
set -euo pipefail

FAULT="${1:?Usage: inject.sh <f1|f2|f3|f4|all> [region]}"
REGION="${2:-${AWS_REGION:-ap-northeast-2}}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_ROOT/lambda_code/microservice"
BROKEN="$REPO_ROOT/agent_sre/faults/broken"
INJECTOR="coffee-fault-injector"

invoke_injector() {
  local action="$1"
  echo ">> injector: $action"
  aws lambda invoke --function-name "$INJECTOR" --region "$REGION" \
    --payload "$(printf '{"action":"%s"}' "$action")" --cli-binary-format raw-in-base64-out \
    /dev/stdout | sed -n '1,40p'
}

# Build a service dir (optionally apply a transform fn) and deploy it.
deploy_service() {
  local svc="$1" transform="$2"
  local fn="coffee-$svc"
  local work; work="$(mktemp -d)"
  cp -r "$SRC/$svc/." "$work/"
  "$transform" "$work"
  ( cd "$work" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 )
  ( cd "$work" && zip -qr /tmp/$svc.broken.zip . )
  aws lambda update-function-code --function-name "$fn" --region "$REGION" \
    --zip-file fileb:///tmp/$svc.broken.zip --query LastModified --output text
  aws lambda wait function-updated --function-name "$fn" --region "$REGION"
  rm -rf "$work" /tmp/$svc.broken.zip
  echo ">> deployed broken $fn"
}

apply_f2() { cp "$BROKEN/supplier.model.f2.js" "$1/app/models/supplier.model.js"; }
apply_f3() {
  # insert the audit middleware right after the cookieParser() line in index.js
  local idx="$1/index.js"
  awk -v snip="$BROKEN/audit-middleware.f3.js" '
    { print }
    /handler.use\(cookieParser\(\)\)/ && !done {
      while ((getline line < snip) > 0) print line; close(snip); done=1
    }' "$idx" > "$idx.tmp" && mv "$idx.tmp" "$idx"
}

inject_f1() { invoke_injector ensure_table; invoke_injector seed_overflow; echo ">> F1 seeded (next INSERT overflows INT32)"; }
inject_f4() { invoke_injector ensure_table; invoke_injector alter_phone_int; echo ">> F4 applied (phone -> INT)"; }
inject_f2() { deploy_service customer apply_f2; deploy_service employee apply_f2; }
inject_f3() { deploy_service customer apply_f3; deploy_service employee apply_f3; }

case "$FAULT" in
  f1) inject_f1 ;;
  f2) inject_f2 ;;
  f3) inject_f3 ;;
  f4) inject_f4 ;;
  all) inject_f2; inject_f3; inject_f1; inject_f4 ;;
  *) echo "unknown fault: $FAULT"; exit 1 ;;
esac
echo ">> inject $FAULT complete."
