#!/bin/bash
set -eo pipefail

# ECS EC2 (Graviton ARM64) 쇼핑몰 배포 + CloudFront 보안
# base-application 이미지 사용 (public ECR)
# 사용법: ./17.deploy-ecs-ec2.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"
AWS_REGION=${AWS_REGION:-ap-northeast-2}
STACK_NAME="ECS-EC2-Shop"
CF_STACK_NAME="lab-ecs-ec2-cloudfront"

echo "============================================"
echo "  ECS EC2 (Graviton ARM64) 쇼핑몰 배포"
echo "============================================"
echo ""
echo "  스택: ${STACK_NAME}"
echo "  Launch Type: EC2 (t4g.large, ASG 3대)"
echo "  앱: base-application (영어)"
echo ""

# ─────────────────────────────────────────────
# Step 1: CloudFormation 배포
# ─────────────────────────────────────────────
# ECS Service-Linked Role 자동 생성 (새 계정용)
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com 2>/dev/null || true

echo "▶ [1/3] ECS EC2 스택 배포..."
aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${SCRIPT_DIR}/templates/ecs-ec2-shop-stack.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AppImage=base \
  --region "${AWS_REGION}" 2>&1

echo "  ✅ ECS EC2 스택 배포 완료"

# ─────────────────────────────────────────────
# Step 2: ALB SG → CloudFront Prefix List
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/3] ALB SG 보안 강화 (CloudFront Prefix List)"

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
# Step 3: CloudFront Distribution
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/3] CloudFront Distribution"

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
echo "  ✅ ECS EC2 쇼핑몰 배포 완료!"
echo "============================================"
echo ""
echo "  🌐 Shop URL: ${CF_URL}"
echo "  📦 ALB: ${ALB}"
echo "  🔒 CloudFront → ALB (CF Prefix List)"
echo "============================================"
