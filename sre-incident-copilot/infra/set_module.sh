#!/bin/bash
###############################################################################
# Flip the agent Lambda to a lab module level (m1..m5) by updating its MODULE
# environment variable. The web chat immediately reflects the new behaviour.
#
# Usage:
#   ./infra/set_module.sh <m1|m2|m3|m4|m5> [region]
###############################################################################
set -euo pipefail

MODULE="${1:?Usage: set_module.sh <m1|m2|m3|m4|m5> [region]}"
REGION="${2:-${AWS_REGION:-ap-northeast-2}}"
FN="strands-incident-copilot"

echo ">> setting $FN MODULE=$MODULE"
CURRENT="$(aws lambda get-function-configuration --function-name "$FN" --region "$REGION" \
  --query "Environment.Variables" --output json)"
NEW="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); d['MODULE']=sys.argv[2]; print(json.dumps({'Variables':d}))" "$CURRENT" "$MODULE")"

aws lambda update-function-configuration --function-name "$FN" --region "$REGION" \
  --environment "$NEW" --query "LastModified" --output text
aws lambda wait function-updated --function-name "$FN" --region "$REGION"
echo ">> done. agent now running module $MODULE"
