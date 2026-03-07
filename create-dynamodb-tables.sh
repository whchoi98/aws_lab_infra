#!/bin/bash
set -euo pipefail

# DynamoDB 테이블 일괄 생성 스크립트
# 사용법: ./create-dynamodb-tables.sh [테이블수] [접두사]

COUNT=${1:-20}
PREFIX=${2:-lab-table}
REGION=${AWS_DEFAULT_REGION:-ap-northeast-2}

echo "============================================"
echo "DynamoDB 테이블 일괄 생성"
echo "============================================"
echo "개수:   ${COUNT}"
echo "접두사: ${PREFIX}-"
echo "리전:   ${REGION}"
echo "============================================"
echo ""

SUCCESS=0
SKIP=0
FAIL=0

for i in $(seq -w 1 "$COUNT"); do
  TABLE_NAME="${PREFIX}-${i}"

  if aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
    echo "⏭  ${TABLE_NAME} (이미 존재)"
    SKIP=$((SKIP+1))
  elif aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=PK,AttributeType=S AttributeName=SK,AttributeType=S \
    --key-schema AttributeName=PK,KeyType=HASH AttributeName=SK,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Environment,Value=lab \
    >/dev/null 2>&1; then
    echo "✅ ${TABLE_NAME}"
    SUCCESS=$((SUCCESS+1))
  else
    echo "❌ ${TABLE_NAME}"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "============================================"
echo "결과: 생성 ${SUCCESS} / 스킵 ${SKIP} / 실패 ${FAIL}"
echo "============================================"
