#!/bin/bash
set -e

# DMZVPC 스택에서 VPC/Subnet 정보를 추출하여 EKS 환경변수를 설정합니다.

DMZVPC_STACK=${1:-DMZVPC}
AWS_REGION=${AWS_REGION:-ap-northeast-2}

append_to_bash_profile() {
  local var_name="$1" var_value="$2"
  sed -i "/^export ${var_name}=/d" ~/.bash_profile 2>/dev/null || true
  echo "export ${var_name}=\"${var_value}\"" >> ~/.bash_profile
  export "${var_name}=${var_value}"
}

echo "============================================"
echo "  EKS 환경변수 설정"
echo "============================================"
echo ""

echo "▶ [1/3] DMZVPC 스택에서 정보 추출..."
VPCID=$(aws cloudformation describe-stacks --stack-name "${DMZVPC_STACK}" \
  --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' --output text --region "${AWS_REGION}")
PRIVATE_SUBNET_A=$(aws cloudformation describe-stacks --stack-name "${DMZVPC_STACK}" \
  --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetAId`].OutputValue' --output text --region "${AWS_REGION}")
PRIVATE_SUBNET_B=$(aws cloudformation describe-stacks --stack-name "${DMZVPC_STACK}" \
  --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetBId`].OutputValue' --output text --region "${AWS_REGION}")

if [ -z "$VPCID" ] || [ -z "$PRIVATE_SUBNET_A" ] || [ -z "$PRIVATE_SUBNET_B" ]; then
  echo "  ❌ DMZVPC 스택 정보를 가져올 수 없습니다."
  exit 1
fi

echo "  ✅ VPC ID: ${VPCID}"
echo "  ✅ Private Subnet A: ${PRIVATE_SUBNET_A}"
echo "  ✅ Private Subnet B: ${PRIVATE_SUBNET_B}"

echo ""
echo "▶ [2/3] EKS 환경변수 설정..."
EKSCLUSTER_NAME="eksworkshop"
EKS_VERSION="1.33"
INSTANCE_TYPE="t4g.xlarge"
PRIVATE_MGMD_NODE="managed-backend-workloads"

echo ""
echo "▶ [3/3] bash_profile에 저장..."
append_to_bash_profile "VPCID" "$VPCID"
append_to_bash_profile "PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_A"
append_to_bash_profile "PRIVATE_SUBNET_B" "$PRIVATE_SUBNET_B"
append_to_bash_profile "EKSCLUSTER_NAME" "$EKSCLUSTER_NAME"
append_to_bash_profile "EKS_VERSION" "$EKS_VERSION"
append_to_bash_profile "INSTANCE_TYPE" "$INSTANCE_TYPE"
append_to_bash_profile "PRIVATE_MGMD_NODE" "$PRIVATE_MGMD_NODE"

source ~/.bash_profile

echo ""
echo "============================================"
echo "  ✅ EKS 환경변수 설정 완료"
echo "============================================"
echo "  VPCID=${VPCID}"
echo "  PRIVATE_SUBNET_A=${PRIVATE_SUBNET_A}"
echo "  PRIVATE_SUBNET_B=${PRIVATE_SUBNET_B}"
echo "  EKSCLUSTER_NAME=${EKSCLUSTER_NAME}"
echo ""
echo "  다음 단계: ./eks-create-cluster.sh"
