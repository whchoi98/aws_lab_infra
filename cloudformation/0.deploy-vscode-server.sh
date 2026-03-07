#!/bin/bash
set -euo pipefail

# VSCode Server 배포 스크립트
# CloudFront -> ALB -> EC2 (Private) 구성으로 VSCode Server를 배포합니다.
# 사용법: ./0.deploy-vscode-server.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="mgmt-vpc"
TEMPLATE_FILE="${SCRIPT_DIR}/vscode_server_secure.yaml"

echo "============================================"
echo "  VSCode Server 배포"
echo "============================================"
echo ""

# 1. 리전 선택
echo "▶ [1/4] AWS 리전 선택"
echo ""
echo "  사용 가능한 리전:"
echo "  1) ap-northeast-2 (서울) [기본값]"
echo "  2) ap-northeast-1 (도쿄)"
echo "  3) us-east-1 (버지니아)"
echo "  4) us-west-2 (오레곤)"
echo "  5) eu-west-1 (아일랜드)"
echo "  6) 직접 입력"
echo ""
read -p "  리전 번호를 선택하세요 [1]: " REGION_CHOICE
REGION_CHOICE=${REGION_CHOICE:-1}

case "$REGION_CHOICE" in
  1) AWS_REGION="ap-northeast-2" ;;
  2) AWS_REGION="ap-northeast-1" ;;
  3) AWS_REGION="us-east-1" ;;
  4) AWS_REGION="us-west-2" ;;
  5) AWS_REGION="eu-west-1" ;;
  6)
    read -p "  리전 코드를 입력하세요 (예: ap-southeast-1): " AWS_REGION
    if [ -z "$AWS_REGION" ]; then
      echo "  ❌ 리전이 입력되지 않았습니다."
      exit 1
    fi
    ;;
  *)
    echo "  ❌ 잘못된 선택입니다."
    exit 1
    ;;
esac

echo "  ✅ 선택된 리전: ${AWS_REGION}"
echo ""

# 2. VSCode 패스워드 입력
echo "▶ [2/4] VSCode Server 패스워드 설정"
echo ""
while true; do
  read -s -p "  VSCode 패스워드 (8자 이상): " VSCODE_PASSWORD
  echo ""
  if [ ${#VSCODE_PASSWORD} -lt 8 ]; then
    echo "  ❌ 패스워드는 8자 이상이어야 합니다. 다시 입력하세요."
    continue
  fi
  read -s -p "  패스워드 확인: " VSCODE_PASSWORD_CONFIRM
  echo ""
  if [ "$VSCODE_PASSWORD" != "$VSCODE_PASSWORD_CONFIRM" ]; then
    echo "  ❌ 패스워드가 일치하지 않습니다. 다시 입력하세요."
    continue
  fi
  break
done
echo "  ✅ 패스워드 설정 완료"
echo ""

# 3. CloudFront Prefix List ID 조회
echo "▶ [3/4] CloudFront Prefix List ID 조회"
CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${AWS_REGION}")

if [ -z "$CF_PREFIX_LIST_ID" ] || [ "$CF_PREFIX_LIST_ID" = "None" ]; then
  echo "  ❌ CloudFront Prefix List ID를 찾을 수 없습니다."
  echo "  리전(${AWS_REGION})에서 CloudFront 서비스가 지원되는지 확인하세요."
  exit 1
fi
echo "  ✅ CloudFront Prefix List ID: ${CF_PREFIX_LIST_ID}"
echo ""

# 4. CloudFormation 배포
echo "▶ [4/4] CloudFormation 스택 배포"
echo ""
echo "  스택 이름:    ${STACK_NAME}"
echo "  리전:         ${AWS_REGION}"
echo "  템플릿:       ${TEMPLATE_FILE}"
echo ""
echo "  배포를 시작합니다..."
echo ""

aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    CloudFrontPrefixListId="${CF_PREFIX_LIST_ID}" \
    VSCodePassword="${VSCODE_PASSWORD}" \
    InstanceType="m7g.xlarge" \
  --region "${AWS_REGION}"

echo ""
echo "============================================"
echo "  ✅ VSCode Server 배포 완료!"
echo "============================================"
echo ""

# 스택 출력 정보 표시
echo "📋 접속 정보:"
CF_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text --region "${AWS_REGION}")

INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query 'Stacks[0].Outputs[?OutputKey==`VSCodeServerInstanceId`].OutputValue' \
  --output text --region "${AWS_REGION}")

echo ""
echo "  🌐 VSCode URL: ${CF_URL}"
echo "  🔑 패스워드:    [입력한 패스워드]"
echo "  🖥️  인스턴스 ID: ${INSTANCE_ID}"
echo ""
echo "  📌 SSM 접속:   aws ssm start-session --target ${INSTANCE_ID} --region ${AWS_REGION}"
echo ""
echo "  ⚠️  CloudFront 배포 완료까지 5-10분 소요될 수 있습니다."
echo "============================================"
