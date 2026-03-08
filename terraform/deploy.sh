#!/bin/bash
set -euo pipefail
# Terraform 전체 배포 래퍼 스크립트
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

echo "============================================"
echo "  Terraform 전체 배포"
echo "============================================"

# 도구 점검
source "${SHARED_DIR}/00.check-prerequisites.sh"

read -p "AWS 리전 [ap-northeast-2]: " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-northeast-2}

# CloudFront Prefix List
CF_PL=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${AWS_REGION}")

read -s -p "DB 패스워드 (8자 이상): " DB_PASS
echo ""

cd "${SCRIPT_DIR}"
terraform init
terraform plan \
  -var="cloudfront_prefix_list_id=${CF_PL}" \
  -var="db_password=${DB_PASS}"

read -p "적용하시겠습니까? (yes/no): " CONFIRM
if [ "$CONFIRM" = "yes" ]; then
  terraform apply -auto-approve \
    -var="cloudfront_prefix_list_id=${CF_PL}" \
    -var="db_password=${DB_PASS}"
  echo "✅ Terraform 배포 완료!"
  terraform output
fi

echo "다음 단계: EKS(eksctl) → LBC → Karpenter → 앱 배포"
