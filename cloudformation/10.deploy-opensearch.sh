#!/bin/bash
set -e

# Amazon OpenSearch Service 배포 스크립트
# DMZ VPC Data Subnet에 OpenSearch 도메인을 생성합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  Amazon OpenSearch Service 배포"
echo "============================================"
echo ""

read -p "  마스터 사용자명 [admin]: " OS_USER
OS_USER=${OS_USER:-admin}

read -s -p "  마스터 패스워드 (8자 이상, 대소문자+숫자+특수문자): " OS_PASS
echo ""

if [ ${#OS_PASS} -lt 8 ]; then
  echo "  ❌ 패스워드는 8자 이상이어야 합니다."
  exit 1
fi

# OpenSearch VPC 배포에 필요한 Service-Linked Role 자동 생성
aws iam create-service-linked-role --aws-service-name es.amazonaws.com 2>/dev/null || true

echo ""
aws cloudformation deploy \
  --stack-name OpenSearch \
  --template-file "${SCRIPT_DIR}/templates/opensearch-stack.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    MasterUserName="${OS_USER}" \
    MasterUserPassword="${OS_PASS}" \
  --region "${AWS_REGION}"

echo ""
echo "  ✅ OpenSearch 배포 완료!"
ENDPOINT=$(aws cloudformation describe-stacks --stack-name OpenSearch \
  --query 'Stacks[0].Outputs[?OutputKey==`DomainEndpoint`].OutputValue' \
  --output text --region "${AWS_REGION}")
echo "  Endpoint: ${ENDPOINT}"
echo "  Dashboards: https://${ENDPOINT}/_dashboards"
