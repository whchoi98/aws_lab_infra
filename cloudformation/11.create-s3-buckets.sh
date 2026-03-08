#!/bin/bash
set -euo pipefail

# S3 버킷 일괄 생성 스크립트 (Public Access 차단)
# 사용법: ./11.create-s3-buckets.sh [버킷수] [접두사]
#
# 보안 설정:
#   - Public Access Block: 전체 차단
#   - 서버 사이드 암호화: AES-256 (SSE-S3)
#   - 버전 관리: 활성화
#   - 태그: Environment=lab, Project=aws-lab-infra

COUNT=${1:-20}
PREFIX=${2:-lab-bucket}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  S3 버킷 일괄 생성 (Public Access 차단)"
echo "============================================"
echo ""
echo "  개수:       ${COUNT}"
echo "  접두사:     ${PREFIX}-${ACCOUNT_ID}-"
echo "  리전:       ${REGION}"
echo "  암호화:     AES-256 (SSE-S3)"
echo "  버전관리:   활성화"
echo "  Public:     전체 차단"
echo ""
echo "============================================"
echo ""

SUCCESS=0
SKIP=0
FAIL=0

for i in $(seq -w 1 "$COUNT"); do
  BUCKET="${PREFIX}-${ACCOUNT_ID}-${i}"

  # 이미 존재하면 스킵
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "  ⏭  ${BUCKET} (이미 존재)"
    SKIP=$((SKIP+1))
    continue
  fi

  # 버킷 생성
  if ! aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" > /dev/null 2>&1; then
    echo "  ❌ ${BUCKET} (생성 실패)"
    FAIL=$((FAIL+1))
    continue
  fi

  # Public Access Block (전체 차단)
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    2>/dev/null

  # 서버 사이드 암호화 (SSE-S3)
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}' \
    2>/dev/null

  # 버전 관리 활성화
  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled \
    2>/dev/null

  # 태그
  aws s3api put-bucket-tagging --bucket "$BUCKET" \
    --tagging "TagSet=[{Key=Name,Value=${BUCKET}},{Key=Environment,Value=lab},{Key=Project,Value=aws-lab-infra},{Key=ManagedBy,Value=shell}]" \
    2>/dev/null

  echo "  ✅ ${BUCKET}"
  SUCCESS=$((SUCCESS+1))
done

echo ""
echo "============================================"
echo "  결과: 생성 ${SUCCESS} / 스킵 ${SKIP} / 실패 ${FAIL}"
echo "============================================"
echo ""
echo "  보안 설정 (모든 버킷):"
echo "    🔒 Public Access Block: 전체 차단"
echo "    🔐 암호화: AES-256 (SSE-S3 + Bucket Key)"
echo "    📋 버전관리: 활성화"
echo "============================================"
