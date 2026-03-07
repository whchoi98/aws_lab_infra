#!/bin/bash
set -euo pipefail

# S3 버킷 일괄 생성 스크립트
# 사용법: ./create-s3-buckets.sh [버킷수] [접두사]

COUNT=${1:-20}
PREFIX=${2:-lab-bucket}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_DEFAULT_REGION:-ap-northeast-2}

echo "============================================"
echo "S3 버킷 일괄 생성"
echo "============================================"
echo "개수:   ${COUNT}"
echo "접두사: ${PREFIX}-${ACCOUNT_ID}-"
echo "리전:   ${REGION}"
echo "============================================"
echo ""

SUCCESS=0
SKIP=0
FAIL=0

for i in $(seq -w 1 "$COUNT"); do
  BUCKET="${PREFIX}-${ACCOUNT_ID}-${i}"
  if aws s3api head-bucket --bucket "$BUCKET" &>/dev/null; then
    echo "⏭  ${BUCKET} (이미 존재)"
    SKIP=$((SKIP+1))
  elif aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null 2>&1; then
    echo "✅ ${BUCKET}"
    SUCCESS=$((SUCCESS+1))
  else
    echo "❌ ${BUCKET}"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "============================================"
echo "결과: 생성 ${SUCCESS} / 스킵 ${SKIP} / 실패 ${FAIL}"
echo "============================================"
