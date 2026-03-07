#!/bin/bash
set -euo pipefail
# CDK 전체 배포 래퍼 스크립트
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

echo "============================================"
echo "  AWS CDK 전체 배포"
echo "============================================"

# 도구 점검
source "${SHARED_DIR}/check-prerequisites.sh"

# npm install
cd "${SCRIPT_DIR}"
npm install --silent 2>&1 | tail -3

read -p "AWS 리전 [ap-northeast-2]: " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-northeast-2}

# CloudFront Prefix List
CF_PL=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${AWS_REGION}")

# CDK Bootstrap
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
npx cdk bootstrap aws://${ACCOUNT_ID}/${AWS_REGION}

# CDK Deploy
npx cdk deploy --all --require-approval never \
  --context cloudFrontPrefixListId="${CF_PL}"

echo "✅ CDK 배포 완료!"
echo "다음 단계: EKS(eksctl) → LBC → Karpenter → 앱 배포"
