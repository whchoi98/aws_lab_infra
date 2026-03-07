#!/bin/bash
set -e

# DMZVPC 스택에서 EKS에 필요한 VPC/Subnet 정보를 추출하여 환경변수로 설정합니다.
# eksctl로 클러스터를 생성하기 전에 반드시 source로 실행하세요.
#
# 사용법: source ./eks-setup-env.sh [DMZVPC_STACK_NAME]

DMZVPC_STACK=${1:-DMZVPC}
AWS_REGION=${AWS_REGION:-ap-northeast-2}

append_to_bash_profile() {
  local var_name="$1" var_value="$2"
  sed -i "/^export ${var_name}=/d" ~/.bash_profile 2>/dev/null || true
  echo "export ${var_name}=\"${var_value}\"" >> ~/.bash_profile
  export "${var_name}=${var_value}"
}

echo "============================================"
echo "  EKS 환경변수 설정 (from ${DMZVPC_STACK})"
echo "============================================"
echo ""

# ─────────────────────────────────────────────
# 1. DMZVPC CloudFormation 스택에서 정보 추출
# ─────────────────────────────────────────────
echo "▶ [1/4] DMZVPC 스택 상태 확인..."

STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "${DMZVPC_STACK}" \
  --query 'Stacks[0].StackStatus' --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")

if [[ "$STACK_STATUS" != "CREATE_COMPLETE" && "$STACK_STATUS" != "UPDATE_COMPLETE" ]]; then
  echo "  ❌ ${DMZVPC_STACK} 스택이 준비되지 않았습니다. 상태: ${STACK_STATUS}"
  echo "  먼저 VPC를 배포하세요: ./1.deploy-all-vpcs.sh"
  return 1 2>/dev/null || exit 1
fi
echo "  ✅ ${DMZVPC_STACK} 스택 상태: ${STACK_STATUS}"

echo ""
echo "▶ [2/4] VPC/Subnet 정보 추출..."

# 모든 Output을 한 번에 가져오기
OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "${DMZVPC_STACK}" \
  --query 'Stacks[0].Outputs' --output json \
  --region "${AWS_REGION}")

get_output() {
  echo "$OUTPUTS" | python3 -c "
import sys, json
outputs = json.load(sys.stdin)
for o in outputs:
    if o['OutputKey'] == '$1':
        print(o['OutputValue'])
        break
" 2>/dev/null
}

VPCID=$(get_output "VPCId")
PUBLIC_SUBNET_A=$(get_output "PublicSubnetAId")
PUBLIC_SUBNET_B=$(get_output "PublicSubnetBId")
PRIVATE_SUBNET_A=$(get_output "PrivateSubnetAId")
PRIVATE_SUBNET_B=$(get_output "PrivateSubnetBId")

# 값 검증
for VAR_NAME in VPCID PUBLIC_SUBNET_A PUBLIC_SUBNET_B PRIVATE_SUBNET_A PRIVATE_SUBNET_B; do
  VAR_VALUE="${!VAR_NAME}"
  if [ -z "$VAR_VALUE" ]; then
    echo "  ❌ ${VAR_NAME}을(를) 가져올 수 없습니다."
    echo "  DMZVPC 스택 Outputs을 확인하세요."
    return 1 2>/dev/null || exit 1
  fi
  echo "  ✅ ${VAR_NAME}: ${VAR_VALUE}"
done

# ─────────────────────────────────────────────
# 3. EKS 기본 설정값
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/4] EKS 설정값..."

EKSCLUSTER_NAME="eksworkshop"
EKS_VERSION="1.33"
INSTANCE_TYPE="t4g.xlarge"
PRIVATE_MGMD_NODE="managed-backend-workloads"

echo "  클러스터 이름:  ${EKSCLUSTER_NAME}"
echo "  EKS 버전:       ${EKS_VERSION}"
echo "  인스턴스 타입:  ${INSTANCE_TYPE}"
echo "  노드그룹 이름:  ${PRIVATE_MGMD_NODE}"

# ─────────────────────────────────────────────
# 4. KMS 키 확인/생성
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/4] KMS 키 확인..."

MASTER_ARN=$(aws kms describe-key --key-id alias/eksworkshop \
  --query 'KeyMetadata.Arn' --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "")

if [ -z "$MASTER_ARN" ] || [ "$MASTER_ARN" = "None" ]; then
  echo "  KMS 키가 없습니다. 새로 생성합니다..."
  MASTER_ARN=$(aws kms create-key \
    --description "EKS eksworkshop secrets encryption key" \
    --query 'KeyMetadata.Arn' --output text \
    --region "${AWS_REGION}")
  aws kms create-alias \
    --alias-name alias/eksworkshop \
    --target-key-id "${MASTER_ARN}" \
    --region "${AWS_REGION}"
  echo "  ✅ KMS 키 생성 완료: ${MASTER_ARN}"
else
  echo "  ✅ KMS 키 존재: ${MASTER_ARN}"
fi

# ─────────────────────────────────────────────
# bash_profile에 모든 환경변수 저장
# ─────────────────────────────────────────────
append_to_bash_profile "AWS_REGION" "$AWS_REGION"
append_to_bash_profile "VPCID" "$VPCID"
append_to_bash_profile "PUBLIC_SUBNET_A" "$PUBLIC_SUBNET_A"
append_to_bash_profile "PUBLIC_SUBNET_B" "$PUBLIC_SUBNET_B"
append_to_bash_profile "PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_A"
append_to_bash_profile "PRIVATE_SUBNET_B" "$PRIVATE_SUBNET_B"
append_to_bash_profile "EKSCLUSTER_NAME" "$EKSCLUSTER_NAME"
append_to_bash_profile "EKS_VERSION" "$EKS_VERSION"
append_to_bash_profile "INSTANCE_TYPE" "$INSTANCE_TYPE"
append_to_bash_profile "PRIVATE_MGMD_NODE" "$PRIVATE_MGMD_NODE"
append_to_bash_profile "MASTER_ARN" "$MASTER_ARN"

source ~/.bash_profile

echo ""
echo "============================================"
echo "  ✅ EKS 환경변수 설정 완료"
echo "============================================"
echo ""
echo "  저장된 환경변수:"
echo "    VPCID=${VPCID}"
echo "    PUBLIC_SUBNET_A=${PUBLIC_SUBNET_A}"
echo "    PUBLIC_SUBNET_B=${PUBLIC_SUBNET_B}"
echo "    PRIVATE_SUBNET_A=${PRIVATE_SUBNET_A}"
echo "    PRIVATE_SUBNET_B=${PRIVATE_SUBNET_B}"
echo "    EKSCLUSTER_NAME=${EKSCLUSTER_NAME}"
echo "    EKS_VERSION=${EKS_VERSION}"
echo "    MASTER_ARN=${MASTER_ARN}"
echo ""
echo "  다음 단계: ./eks-create-cluster.sh"
echo "============================================"
