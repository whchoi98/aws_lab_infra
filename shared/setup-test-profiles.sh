#!/bin/bash
set -euo pipefail

# 3개 테스트 계정의 AWS CLI 프로파일을 설정합니다.
# 계정: lab-cf (CloudFormation), lab-cdk (CDK), lab-terraform (Terraform)

echo "============================================"
echo "  AWS 테스트 계정 프로파일 설정"
echo "============================================"
echo ""
echo "  3개 계정 프로파일을 설정합니다:"
echo "  1) lab-cf        - Shell + CloudFormation 테스트"
echo "  2) lab-cdk       - CDK 테스트"
echo "  3) lab-terraform - Terraform 테스트"
echo ""

DEFAULT_REGION="ap-northeast-2"

# Profile 1: CloudFormation
echo "▶ [1/3] lab-cf 프로파일 설정"
read -p "  Access Key ID: " CF_ACCESS_KEY
read -s -p "  Secret Access Key: " CF_SECRET_KEY
echo ""
read -p "  리전 [${DEFAULT_REGION}]: " CF_REGION
CF_REGION=${CF_REGION:-${DEFAULT_REGION}}

aws configure set aws_access_key_id "${CF_ACCESS_KEY}" --profile lab-cf
aws configure set aws_secret_access_key "${CF_SECRET_KEY}" --profile lab-cf
aws configure set region "${CF_REGION}" --profile lab-cf
aws configure set output json --profile lab-cf

echo "  ✅ lab-cf 프로파일 설정 완료"
echo ""

# Profile 2: CDK
echo "▶ [2/3] lab-cdk 프로파일 설정"
read -p "  Access Key ID: " CDK_ACCESS_KEY
read -s -p "  Secret Access Key: " CDK_SECRET_KEY
echo ""
read -p "  리전 [${DEFAULT_REGION}]: " CDK_REGION
CDK_REGION=${CDK_REGION:-${DEFAULT_REGION}}

aws configure set aws_access_key_id "${CDK_ACCESS_KEY}" --profile lab-cdk
aws configure set aws_secret_access_key "${CDK_SECRET_KEY}" --profile lab-cdk
aws configure set region "${CDK_REGION}" --profile lab-cdk
aws configure set output json --profile lab-cdk

echo "  ✅ lab-cdk 프로파일 설정 완료"
echo ""

# Profile 3: Terraform
echo "▶ [3/3] lab-terraform 프로파일 설정"
read -p "  Access Key ID: " TF_ACCESS_KEY
read -s -p "  Secret Access Key: " TF_SECRET_KEY
echo ""
read -p "  리전 [${DEFAULT_REGION}]: " TF_REGION
TF_REGION=${TF_REGION:-${DEFAULT_REGION}}

aws configure set aws_access_key_id "${TF_ACCESS_KEY}" --profile lab-terraform
aws configure set aws_secret_access_key "${TF_SECRET_KEY}" --profile lab-terraform
aws configure set region "${TF_REGION}" --profile lab-terraform
aws configure set output json --profile lab-terraform

echo "  ✅ lab-terraform 프로파일 설정 완료"
echo ""

# 연결 테스트
echo "============================================"
echo "  연결 테스트"
echo "============================================"
echo ""

for PROFILE in lab-cf lab-cdk lab-terraform; do
  echo -n "  ${PROFILE}: "
  CALLER=$(aws sts get-caller-identity --profile "${PROFILE}" --output json 2>/dev/null || echo "FAILED")
  if [ "$CALLER" = "FAILED" ]; then
    echo "❌ 연결 실패"
  else
    ACCOUNT=$(echo "$CALLER" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])" 2>/dev/null)
    echo "✅ Account ${ACCOUNT}"
  fi
done

echo ""
echo "============================================"
echo "  프로파일 설정 완료!"
echo "============================================"
echo ""
echo "  사용법:"
echo "    CloudFormation: AWS_PROFILE=lab-cf ./cloudformation/1.deploy-all-vpcs.sh"
echo "    CDK:            cd cdk && AWS_PROFILE=lab-cdk npx cdk deploy --all"
echo "    Terraform:      cd terraform && AWS_PROFILE=lab-terraform terraform apply"
echo ""
