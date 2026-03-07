#!/bin/bash
set -e

# 모든 VPC 스택을 병렬로 배포하는 스크립트
# DMZVPC, VPC01, VPC02를 동시에 배포합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  VPC 일괄 배포"
echo "============================================"
echo ""

# 리전 선택
read -p "AWS 리전 [ap-northeast-2]: " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-northeast-2}
export AWS_REGION

# CloudFront Prefix List ID (DMZVPC에 필요)
echo ""
echo "▶ CloudFront Prefix List ID 조회 중..."
CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${AWS_REGION}")

if [ -z "$CF_PREFIX_LIST_ID" ] || [ "$CF_PREFIX_LIST_ID" = "None" ]; then
  echo "  ❌ CloudFront Prefix List ID를 찾을 수 없습니다."
  exit 1
fi
echo "  ✅ CF Prefix List ID: ${CF_PREFIX_LIST_ID}"

echo ""
echo "  리전: ${AWS_REGION}"
echo "  스택: DMZVPC, VPC01, VPC02"
echo "  배포 방식: 병렬"
echo ""
echo "============================================"

# DMZVPC 배포 (백그라운드)
echo "▶ [1/3] DMZVPC 배포 시작..."
{
  aws cloudformation deploy \
    --stack-name DMZVPC \
    --template-file "${SCRIPT_DIR}/templates/1.DMZVPC.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      CloudFrontPrefixListId="${CF_PREFIX_LIST_ID}" \
    --region "${AWS_REGION}" 2>&1
  echo "  ✅ DMZVPC 배포 완료"
} &
DMZVPC_PID=$!

# VPC01 배포 (백그라운드)
echo "▶ [2/3] VPC01 배포 시작..."
{
  aws cloudformation deploy \
    --stack-name VPC01 \
    --template-file "${SCRIPT_DIR}/templates/2.VPC01.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${AWS_REGION}" 2>&1
  echo "  ✅ VPC01 배포 완료"
} &
VPC01_PID=$!

# VPC02 배포 (백그라운드)
echo "▶ [3/3] VPC02 배포 시작..."
{
  aws cloudformation deploy \
    --stack-name VPC02 \
    --template-file "${SCRIPT_DIR}/templates/3.VPC02.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${AWS_REGION}" 2>&1
  echo "  ✅ VPC02 배포 완료"
} &
VPC02_PID=$!

echo ""
echo "⏳ 모든 스택이 병렬 배포 중... (약 10-15분 소요)"
echo "  DMZVPC PID: ${DMZVPC_PID}"
echo "  VPC01  PID: ${VPC01_PID}"
echo "  VPC02  PID: ${VPC02_PID}"
echo ""

wait ${DMZVPC_PID}; DMZVPC_STATUS=$?
wait ${VPC01_PID};  VPC01_STATUS=$?
wait ${VPC02_PID};  VPC02_STATUS=$?

echo ""
echo "============================================"
echo "  배포 결과"
echo "============================================"
[ ${DMZVPC_STATUS} -eq 0 ] && echo "  ✅ DMZVPC: 성공" || echo "  ❌ DMZVPC: 실패"
[ ${VPC01_STATUS} -eq 0 ]  && echo "  ✅ VPC01:  성공" || echo "  ❌ VPC01:  실패"
[ ${VPC02_STATUS} -eq 0 ]  && echo "  ✅ VPC02:  성공" || echo "  ❌ VPC02:  실패"
echo ""

if [ ${DMZVPC_STATUS} -eq 0 ] && [ ${VPC01_STATUS} -eq 0 ] && [ ${VPC02_STATUS} -eq 0 ]; then
  echo "  ✅ 모든 VPC 배포 완료!"
  echo ""
  echo "  다음 단계: ./2.deploy-tgw.sh"
  exit 0
else
  echo "  ❌ 일부 스택 배포 실패. CloudFormation 콘솔을 확인하세요."
  exit 1
fi
