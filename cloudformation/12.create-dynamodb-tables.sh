#!/bin/bash
set -euo pipefail

# DynamoDB 테이블 일괄 생성 스크립트
# 사용법: ./12.create-dynamodb-tables.sh [테이블수] [접두사]
#
# 설정:
#   - 과금: PAY_PER_REQUEST (온디맨드)
#   - 키: PK (HASH) + SK (RANGE) — 복합 키
#   - 암호화: AWS 관리형 키 (기본)
#   - 삭제 보호: 활성화
#   - Point-in-Time Recovery: 활성화
#   - 태그: Name, Environment, Project, ManagedBy

COUNT=${1:-20}
PREFIX=${2:-lab-table}
REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  DynamoDB 테이블 일괄 생성"
echo "============================================"
echo ""
echo "  개수:       ${COUNT}"
echo "  접두사:     ${PREFIX}-"
echo "  리전:       ${REGION}"
echo "  과금:       PAY_PER_REQUEST (온디맨드)"
echo "  키:         PK (String, HASH) + SK (String, RANGE)"
echo "  암호화:     AWS 관리형 키"
echo "  PITR:       활성화"
echo "  삭제보호:   활성화"
echo ""
echo "============================================"
echo ""

SUCCESS=0
SKIP=0
FAIL=0

for i in $(seq -w 1 "$COUNT"); do
  TABLE_NAME="${PREFIX}-${i}"

  # 이미 존재하면 스킵
  if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" &>/dev/null; then
    echo "  ⏭  ${TABLE_NAME} (이미 존재)"
    SKIP=$((SKIP+1))
    continue
  fi

  # 테이블 생성
  if aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions \
      AttributeName=PK,AttributeType=S \
      AttributeName=SK,AttributeType=S \
    --key-schema \
      AttributeName=PK,KeyType=HASH \
      AttributeName=SK,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --deletion-protection-enabled \
    --tags \
      Key=Name,Value="${TABLE_NAME}" \
      Key=Environment,Value=lab \
      Key=Project,Value=aws-lab-infra \
      Key=ManagedBy,Value=shell \
    --region "$REGION" > /dev/null 2>&1; then

    # Point-in-Time Recovery 활성화
    aws dynamodb update-continuous-backups \
      --table-name "$TABLE_NAME" \
      --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
      --region "$REGION" > /dev/null 2>&1 || true

    echo "  ✅ ${TABLE_NAME}"
    SUCCESS=$((SUCCESS+1))
  else
    echo "  ❌ ${TABLE_NAME}"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "============================================"
echo "  결과: 생성 ${SUCCESS} / 스킵 ${SKIP} / 실패 ${FAIL}"
echo "============================================"
echo ""
echo "  설정 (모든 테이블):"
echo "    💰 과금: PAY_PER_REQUEST (온디맨드)"
echo "    🔐 암호화: AWS 관리형 키"
echo "    🔄 PITR: 활성화"
echo "    🛡️  삭제보호: 활성화"
echo "============================================"
