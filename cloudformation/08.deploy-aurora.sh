#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  Aurora MySQL 클러스터 배포"
echo "============================================"
echo ""

read -p "  DB 이름 [appdb]: " DB_NAME
DB_NAME=${DB_NAME:-appdb}

read -p "  마스터 사용자명 [admin]: " DB_USER
DB_USER=${DB_USER:-admin}

read -s -p "  마스터 패스워드 (8자 이상): " DB_PASS
echo ""

if [ ${#DB_PASS} -lt 8 ]; then
  echo "  ❌ 패스워드는 8자 이상이어야 합니다."
  exit 1
fi

echo ""
aws cloudformation deploy \
  --stack-name Aurora \
  --template-file "${SCRIPT_DIR}/templates/aurora-mysql-stack.yaml" \
  --parameter-overrides \
    DBName="${DB_NAME}" \
    DBMasterUsername="${DB_USER}" \
    DBMasterPassword="${DB_PASS}" \
  --region "${AWS_REGION}"

echo ""
echo "  ✅ Aurora MySQL 배포 완료!"
echo "  Writer Endpoint:"
aws cloudformation describe-stacks --stack-name Aurora \
  --query 'Stacks[0].Outputs[?OutputKey==`ClusterEndpoint`].OutputValue' \
  --output text --region "${AWS_REGION}"
