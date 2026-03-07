#!/bin/bash
set -e

# Transit Gateway 배포 스크립트
# 사전 요구사항: DMZVPC, VPC01, VPC02 스택 배포 완료

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Transit Gateway 배포"
echo "============================================"
echo ""

read -p "AWS 리전 [ap-northeast-2]: " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-northeast-2}
export AWS_REGION

# 사전 조건 확인
echo "▶ [1/2] 사전 조건 확인"
for STACK in DMZVPC VPC01 VPC02; do
  STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK}" \
    --query 'Stacks[0].StackStatus' --output text --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")
  if [[ "$STATUS" != "CREATE_COMPLETE" && "$STATUS" != "UPDATE_COMPLETE" ]]; then
    echo "  ❌ ${STACK} 스택이 준비되지 않았습니다. 상태: ${STATUS}"
    echo "  먼저 ./1.deploy-all-vpcs.sh를 실행하세요."
    exit 1
  fi
  echo "  ✅ ${STACK}: ${STATUS}"
done

# TGW 배포
echo ""
echo "▶ [2/2] Transit Gateway 스택 배포 중..."
echo "  예상 소요 시간: 5-10분"
echo ""

aws cloudformation deploy \
  --stack-name TGW \
  --template-file "${SCRIPT_DIR}/4.TGW.yaml" \
  --capabilities CAPABILITY_IAM \
  --region "${AWS_REGION}"

echo ""
echo "============================================"
echo "  ✅ Transit Gateway 배포 완료!"
echo "============================================"
echo ""
echo "  TGW ID:"
aws cloudformation describe-stacks --stack-name TGW \
  --query 'Stacks[0].Outputs[?OutputKey==`TransitGatewayId`].OutputValue' \
  --output text --region "${AWS_REGION}"
echo ""
echo "  다음 단계: EKS 클러스터 배포"
echo "    source ./eks-setup-env.sh"
echo "    ./eks-create-cluster.sh"
