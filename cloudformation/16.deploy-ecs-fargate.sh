#!/bin/bash
set -eo pipefail

# ECS Fargate (Graviton ARM64) bilingual 쇼핑몰 배포 + CloudFront 보안
# bilingual-app: Docker build → ECR push → ECS Fargate 배포
# 사용법: ./16.deploy-ecs-fargate.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"
AWS_REGION=${AWS_REGION:-ap-northeast-2}
STACK_NAME="ECS-Fargate-Shop"
CF_STACK_NAME="lab-ecs-fargate-cloudfront"

echo "============================================"
echo "  ECS Fargate (ARM64) bilingual 쇼핑몰 배포"
echo "============================================"
echo ""
echo "  스택: ${STACK_NAME}"
echo "  Launch Type: Fargate (Graviton ARM64)"
echo "  앱: bilingual-app (한국어/영어)"
echo ""

# ─────────────────────────────────────────────
# Step 1: Docker build + ECR push
# ─────────────────────────────────────────────
echo "▶ [1/4] UI Docker 이미지 빌드 + ECR Push"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="lab-shop-ui"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"

aws ecr create-repository --repository-name ${REPO_NAME} --region ${AWS_REGION} 2>/dev/null || true
docker build -t ${REPO_NAME}:latest ${SHARED_DIR}/bilingual-app/ui/ 2>&1 | tail -3
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com 2>&1 | tail -1
docker tag ${REPO_NAME}:latest ${ECR_URI}:latest
docker push ${ECR_URI}:latest 2>&1 | tail -2
echo "  ✅ 이미지: ${ECR_URI}:latest"

# ─────────────────────────────────────────────
# Step 2: CloudFormation 배포
# ─────────────────────────────────────────────
echo ""
# ECS Service-Linked Role 자동 생성 (새 계정용)
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com 2>/dev/null || true

echo "▶ [2/4] ECS Fargate 스택 배포..."
aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${SCRIPT_DIR}/templates/ecs-shop-stack.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    AppImage=bilingual \
    BillingualEcrUri="${ECR_URI}:latest" \
  --region "${AWS_REGION}" 2>&1

echo "  ✅ ECS Fargate 스택 배포 완료"

# ─────────────────────────────────────────────
# Step 3: ALB SG → CloudFront Prefix List
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/4] ALB SG 보안 강화 (CloudFront Prefix List)"

ALB=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[?OutputKey==`ALBDnsName`].OutputValue' \
  --output text --region "${AWS_REGION}")

ALB_SG=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[?OutputKey==`ALBSecurityGroupId`].OutputValue' \
  --output text --region "${AWS_REGION}")

CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${AWS_REGION}")

if [ -n "${ALB_SG}" ] && [ "${ALB_SG}" != "None" ]; then
  aws ec2 revoke-security-group-ingress --group-id ${ALB_SG} \
    --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
    --region "${AWS_REGION}" 2>/dev/null && echo "  ✅ 0.0.0.0/0 제거" || echo "  ⏭  이미 제거됨"

  aws ec2 authorize-security-group-ingress --group-id ${ALB_SG} \
    --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"PrefixListIds\":[{\"PrefixListId\":\"${CF_PREFIX_LIST_ID}\",\"Description\":\"HTTP from CloudFront only\"}]}]" \
    --region "${AWS_REGION}" 2>/dev/null && echo "  ✅ CloudFront Prefix List 허용" || echo "  ⏭  이미 설정됨"
fi

# ─────────────────────────────────────────────
# Step 4: CloudFront Distribution
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/4] CloudFront Distribution"

STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${CF_STACK_NAME} \
  --query 'Stacks[0].StackStatus' --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")

if [ "${STACK_STATUS}" = "NOT_FOUND" ] || [[ "${STACK_STATUS}" == *"ROLLBACK"* ]]; then
  [[ "${STACK_STATUS}" == *"ROLLBACK"* ]] && \
    aws cloudformation delete-stack --stack-name ${CF_STACK_NAME} --region "${AWS_REGION}" 2>/dev/null && \
    aws cloudformation wait stack-delete-complete --stack-name ${CF_STACK_NAME} --region "${AWS_REGION}" 2>/dev/null

  aws cloudformation deploy \
    --stack-name ${CF_STACK_NAME} \
    --template-file "${SHARED_DIR}/cloudfront-alb-protection.yaml" \
    --parameter-overrides \
      ALBDnsName="${ALB}" \
      ALBSecurityGroupId="${ALB_SG}" \
      CloudFrontPrefixListId="${CF_PREFIX_LIST_ID}" \
    --region "${AWS_REGION}" 2>&1 | tail -3
  echo "  ✅ CloudFront 생성 완료"
else
  echo "  ✅ CloudFront 이미 존재"
fi

CF_URL=$(aws cloudformation describe-stacks --stack-name ${CF_STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text --region "${AWS_REGION}" 2>/dev/null)

echo ""
echo "============================================"
echo "  ✅ ECS Fargate bilingual 쇼핑몰 배포 완료!"
echo "============================================"
echo ""
echo "  🌐 Shop URL (한/영): ${CF_URL}"
echo "  📦 ALB: ${ALB}"
echo "  🔒 CloudFront → ALB (CF Prefix List)"
echo "============================================"
