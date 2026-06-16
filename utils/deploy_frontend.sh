#!/bin/bash
###############################################################################
# Inject the API URLs into the static HTML and publish both frontends to their
# S3 buckets, then invalidate CloudFront.
#
# Usage:
#   ./utils/deploy_frontend.sh <stack-name>
#
# Reads the CloudFormation stack outputs (API URLs, bucket names, distribution
# ids) so it must be run AFTER the stack has been deployed.
###############################################################################
set -euo pipefail

STACK="${1:?Usage: deploy_frontend.sh <stack-name>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

get_output() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

CUSTOMER_API="$(get_output CustomerApiUrl)"
EMPLOYEE_API="$(get_output EmployeeApiUrl)"
CUSTOMER_BUCKET="$(get_output CustomerBucketName)"
EMPLOYEE_BUCKET="$(get_output EmployeeBucketName)"

echo ">> Customer API : $CUSTOMER_API"
echo ">> Employee API : $EMPLOYEE_API"

publish() {
  local src="$1" api="$2" bucket="$3"
  local work
  work="$(mktemp -d)"
  cp -r "$REPO_ROOT/$src/." "$work/"
  # Replace the API placeholder in every HTML file
  find "$work" -name '*.html' -exec sed -i.bak "s|YOUR_API_URL|$api|g" {} \;
  find "$work" -name '*.bak' -delete
  aws s3 sync "$work" "s3://$bucket" --delete
  rm -rf "$work"
  echo ">> Published $src -> s3://$bucket"
}

publish s3_customer "$CUSTOMER_API" "$CUSTOMER_BUCKET"
publish s3_employee "$EMPLOYEE_API" "$EMPLOYEE_BUCKET"

# Invalidate CloudFront so the new HTML is served immediately
for dist in $(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Origins.Items[?contains(DomainName, '$CUSTOMER_BUCKET') || contains(DomainName, '$EMPLOYEE_BUCKET')]].Id" \
  --output text); do
  echo ">> Invalidating CloudFront $dist"
  aws cloudfront create-invalidation --distribution-id "$dist" --paths "/*" >/dev/null
done

echo ">> Frontend deploy complete."
echo "   Customer site: $(get_output CustomerSiteUrl)"
echo "   Employee site: $(get_output EmployeeSiteUrl)"
