#!/bin/bash
###############################################################################
# 공유 산출물 발행 (강사 1회).
# 무거운 빌드 산출물(injector.zip / layer.zip)을 강사가 한 번만 빌드해서
# 퍼블릭 읽기 공유 버킷에 올려둡니다. 수강생은 빌드 없이 `aws s3 cp` 로만 가져갑니다.
#   - injector.zip : Node(mysql2) 의존성 포함 장애 주입 Lambda
#   - layer.zip    : Python 의존성 레이어(Strands/fastapi/uvicorn/mcp/awslabs...)
#
# 사용: ./infra/publish_artifacts.sh [region]
# (옵션) SHARED_BUCKET=내-공유버킷 ./infra/publish_artifacts.sh
###############################################################################
set -euo pipefail

REGION="${1:-${AWS_REGION:-ap-northeast-2}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT="$(cd "$HERE/.." && pwd)"
SHARED_BUCKET="${SHARED_BUCKET:-samsung-cloud-architect}"

echo ">> [1/5] 공유 버킷 준비: $SHARED_BUCKET (퍼블릭 읽기)"
if ! aws s3api head-bucket --bucket "$SHARED_BUCKET" --region "$REGION" 2>/dev/null; then
  aws s3api create-bucket --bucket "$SHARED_BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi
# 퍼블릭 읽기 허용 (수강생이 cp 로 가져갈 수 있게)
aws s3api put-public-access-block --bucket "$SHARED_BUCKET" --region "$REGION" \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy --bucket "$SHARED_BUCKET" --region "$REGION" --policy "$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadCopilotArtifacts",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": [
      "arn:aws:s3:::${SHARED_BUCKET}/copilot/*",
      "arn:aws:s3:::${SHARED_BUCKET}/coffee/*"
    ]
  }]
}
JSON
)"

echo ">> [2/5] coffee 마이크로서비스 빌드 (Node) → coffee/customer.zip, coffee/employee.zip"
COFFEE_SRC="$(cd "$COPILOT/.." && pwd)/lambda_code/microservice"
for svc in customer employee; do
  CSV="$(mktemp -d)"
  cp -r "$COFFEE_SRC/$svc/." "$CSV/"
  ( cd "$CSV" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 && zip -qr "/tmp/coffee-$svc.zip" . -x "*.git*" )
  aws s3 cp "/tmp/coffee-$svc.zip" "s3://$SHARED_BUCKET/coffee/$svc.zip" --region "$REGION"
  rm -rf "$CSV" "/tmp/coffee-$svc.zip"
done

echo ">> [3/5] injector.zip 빌드 (Node)"
INJ="$(mktemp -d)"
cp -r "$COPILOT/faults/injector_lambda/." "$INJ/"
( cd "$INJ" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 && zip -qr /tmp/injector.zip . )
aws s3 cp /tmp/injector.zip "s3://$SHARED_BUCKET/copilot/injector.zip" --region "$REGION"

echo ">> [4/5] layer.zip 빌드 (Python, linux wheels)"
LYR="$(mktemp -d)"; mkdir -p "$LYR/python"
python3 -m pip install -r "$COPILOT/requirements.txt" -t "$LYR/python" \
  --platform manylinux2014_x86_64 --python-version 3.14 --only-binary=:all: --quiet
rm -rf "$LYR/python"/boto3 "$LYR/python"/botocore "$LYR/python"/boto3-* "$LYR/python"/botocore-*
( cd "$LYR" && zip -qr /tmp/layer.zip . -x "*.pyc" "*/__pycache__/*" )
aws s3 cp /tmp/layer.zip "s3://$SHARED_BUCKET/copilot/layer.zip" --region "$REGION"

echo ">> [5/5] 정리"
rm -rf "$INJ" "$LYR" /tmp/injector.zip /tmp/layer.zip

cat <<EOF

>> 발행 완료. 공유 버킷($SHARED_BUCKET)에 올라간 것:
   coffee/customer.zip  coffee/employee.zip   (ServerlessApp_CF Lambda 코드)
   copilot/injector.zip                       (LabBase 장애 주입기 코드)
   copilot/layer.zip                          (학생이 콘솔에서 레이어로 생성)

   수강생에게 공유 버킷명을 안내하세요: SHARED_BUCKET = $SHARED_BUCKET
   (기본값과 다르면 ServerlessApp_CF / deploy_labbase 에 CodeBucket·SHARED_BUCKET 로 전달)
EOF
