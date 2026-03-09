#!/bin/bash
set -e

# Amazon MSK (Managed Streaming for Apache Kafka) 배포 스크립트
# DMZ VPC Data Subnet에 MSK 클러스터를 생성합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  Amazon MSK 클러스터 배포"
echo "============================================"
echo ""

aws cloudformation deploy \
  --stack-name MSK \
  --template-file "${SCRIPT_DIR}/templates/msk-stack.yaml" \
  --region "${AWS_REGION}"

echo ""
echo "  ✅ MSK 배포 완료!"
echo ""
MSK_ARN=$(aws cloudformation describe-stacks --stack-name MSK \
  --query 'Stacks[0].Outputs[?OutputKey==`ClusterArn`].OutputValue' \
  --output text --region "${AWS_REGION}")
echo "  Cluster ARN: ${MSK_ARN}"
echo ""
echo "  Bootstrap Brokers 확인:"
echo "    aws kafka get-bootstrap-brokers --cluster-arn ${MSK_ARN} --region ${AWS_REGION}"
echo "============================================"
