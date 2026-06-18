#!/bin/bash
###############################################################################
# 에이전트 Lambda 함수 코드 zip 만들기 (콘솔 업로드용).
# lambda_src 폴더만 압축합니다 — 서드파티 라이브러리는 레이어에 있으므로 제외.
# 결과: function.zip (수십 KB, 콘솔 인라인 편집 가능)
#
# 사용: ./infra/build_function_zip.sh
###############################################################################
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
rm -f function.zip
zip -qr function.zip lambda_src -x "*.pyc" "*/__pycache__/*"
echo "생성: $HERE/function.zip"
echo "Lambda 콘솔 → Code → Upload from → .zip file 로 올리세요."
