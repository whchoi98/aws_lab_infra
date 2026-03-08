#!/bin/bash
set -e

# eksctl로 EKS 클러스터를 생성합니다.
# 사전 요구사항: source eks-setup-env.sh 실행 완료
#
# 실행 흐름:
#   1. eksctl ClusterConfig YAML 생성
#   2. dry-run으로 검증
#   3. 사용자 확인 후 실제 클러스터 생성
#   4. kubeconfig 업데이트
#   5. 클러스터 상태 확인

source ~/.bash_profile

# ─────────────────────────────────────────────
# 환경변수 검증
# ─────────────────────────────────────────────
: "${VPCID:?VPCID가 설정되지 않았습니다. 먼저 source eks-setup-env.sh를 실행하세요.}"
: "${PUBLIC_SUBNET_A:?PUBLIC_SUBNET_A가 설정되지 않았습니다.}"
: "${PUBLIC_SUBNET_B:?PUBLIC_SUBNET_B가 설정되지 않았습니다.}"
: "${PRIVATE_SUBNET_A:?PRIVATE_SUBNET_A가 설정되지 않았습니다.}"
: "${PRIVATE_SUBNET_B:?PRIVATE_SUBNET_B가 설정되지 않았습니다.}"
: "${EKSCLUSTER_NAME:=eksworkshop}"
: "${EKS_VERSION:=1.33}"
: "${INSTANCE_TYPE:=t4g.2xlarge}"
: "${PRIVATE_MGMD_NODE:=managed-backend-workloads}"
: "${AWS_REGION:=ap-northeast-2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_CONFIG="${SCRIPT_DIR}/eksworkshop.yaml"

echo "============================================"
echo "  EKS 클러스터 생성 (eksctl)"
echo "============================================"
echo ""
echo "  클러스터:      ${EKSCLUSTER_NAME}"
echo "  EKS 버전:      ${EKS_VERSION}"
echo "  리전:          ${AWS_REGION}"
echo "  VPC:           ${VPCID}"
echo "  Public Subnets:  ${PUBLIC_SUBNET_A}, ${PUBLIC_SUBNET_B}"
echo "  Private Subnets: ${PRIVATE_SUBNET_A}, ${PRIVATE_SUBNET_B}"
echo "  노드 타입:     ${INSTANCE_TYPE}"
echo "  노드 수:       desired=4, min=2, max=8"
echo ""

# ─────────────────────────────────────────────
# 1. 기존 클러스터 확인
# ─────────────────────────────────────────────
echo "▶ [1/5] 기존 클러스터 확인..."
EXISTING=$(aws eks describe-cluster --name "${EKSCLUSTER_NAME}" \
  --query 'cluster.status' --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")

if [ "$EXISTING" = "ACTIVE" ]; then
  echo "  ⚠️  클러스터 '${EKSCLUSTER_NAME}'이(가) 이미 존재합니다 (ACTIVE)."
  echo "  kubeconfig만 업데이트합니다."
  aws eks update-kubeconfig \
    --name "${EKSCLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --alias "${EKSCLUSTER_NAME}"
  echo "  ✅ kubeconfig 업데이트 완료"
  kubectl get nodes
  exit 0
elif [ "$EXISTING" != "NOT_FOUND" ]; then
  echo "  ❌ 클러스터가 비정상 상태입니다: ${EXISTING}"
  echo "  수동으로 확인 후 진행하세요."
  exit 1
fi
echo "  ✅ 기존 클러스터 없음 — 새로 생성합니다."

# ─────────────────────────────────────────────
# 2. eksctl ClusterConfig YAML 생성
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/5] eksctl ClusterConfig 생성..."

# KMS 키 확인
MASTER_ARN=${MASTER_ARN:-$(aws kms describe-key --key-id alias/eksworkshop \
  --query 'KeyMetadata.Arn' --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "")}

# secretsEncryption 블록 (KMS가 있을 때만)
SECRETS_BLOCK=""
if [ -n "$MASTER_ARN" ] && [ "$MASTER_ARN" != "None" ]; then
  SECRETS_BLOCK="
secretsEncryption:
  keyARN: ${MASTER_ARN}"
fi

cat > "${CLUSTER_CONFIG}" <<YAML_EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${EKSCLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${EKS_VERSION}"
  tags:
    Environment: lab
    Project: aws-lab-infra
    ManagedBy: eksctl

vpc:
  id: "${VPCID}"
  subnets:
    public:
      ${AWS_REGION}a:
        id: "${PUBLIC_SUBNET_A}"
      ${AWS_REGION}b:
        id: "${PUBLIC_SUBNET_B}"
    private:
      ${AWS_REGION}a:
        id: "${PRIVATE_SUBNET_A}"
      ${AWS_REGION}b:
        id: "${PRIVATE_SUBNET_B}"
${SECRETS_BLOCK}

managedNodeGroups:
  - name: ${PRIVATE_MGMD_NODE}
    instanceType: ${INSTANCE_TYPE}
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 50
    volumeType: gp3
    volumeEncrypted: true
    amiFamily: AmazonLinux2023
    labels:
      nodegroup-type: "${PRIVATE_MGMD_NODE}"
    tags:
      Environment: lab
      Project: aws-lab-infra
    privateNetworking: true
    subnets:
      - "${PRIVATE_SUBNET_A}"
      - "${PRIVATE_SUBNET_B}"
    ssh:
      enableSsm: true
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        externalDNS: true
        certManager: true
        ebs: true
        efs: true
        awsLoadBalancerController: true
        cloudWatch: true

cloudWatch:
  clusterLogging:
    enableTypes:
      - api
      - audit
      - authenticator
      - controllerManager
      - scheduler

iam:
  withOIDC: true

addons:
  # Networking
  - name: vpc-cni
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  # Storage
  - name: aws-ebs-csi-driver
    wellKnownPolicies:
      ebsCSIController: true
  - name: aws-efs-csi-driver
    version: latest
  - name: aws-fsx-csi-driver
    version: latest
  - name: aws-mountpoint-s3-csi-driver
    version: latest
  - name: snapshot-controller
    version: latest
  # Observability
  - name: amazon-cloudwatch-observability
    version: latest
  - name: adot
    version: latest
  - name: eks-node-monitoring-agent
    version: latest
  - name: aws-network-flow-monitoring-agent
    version: latest
  # Security
  - name: aws-guardduty-agent
    version: latest
  - name: eks-pod-identity-agent
    version: latest
YAML_EOF

echo "  ✅ 설정 파일 생성: ${CLUSTER_CONFIG}"

# ─────────────────────────────────────────────
# 3. dry-run 검증
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/5] dry-run 검증..."
if ! eksctl create cluster --config-file="${CLUSTER_CONFIG}" --dry-run > /dev/null 2>&1; then
  echo "  ❌ dry-run 실패. 설정 파일을 확인하세요:"
  echo "    ${CLUSTER_CONFIG}"
  eksctl create cluster --config-file="${CLUSTER_CONFIG}" --dry-run 2>&1 | tail -20
  exit 1
fi
echo "  ✅ dry-run 검증 통과"

# ─────────────────────────────────────────────
# 4. 사용자 확인 후 클러스터 생성
# ─────────────────────────────────────────────
echo ""
echo "============================================"
echo "  EKS 클러스터를 생성합니다."
echo "  예상 소요 시간: 15-25분"
echo "============================================"
echo ""
read -p "  계속 진행하시겠습니까? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo ""
  echo "  취소되었습니다."
  echo "  수동으로 생성하려면:"
  echo "    eksctl create cluster --config-file=${CLUSTER_CONFIG}"
  exit 0
fi

echo ""
echo "▶ [4/5] eksctl create cluster 실행..."
echo "  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

eksctl create cluster --config-file="${CLUSTER_CONFIG}"

echo ""
echo "  ✅ 클러스터 생성 완료!"
echo "  완료 시간: $(date '+%Y-%m-%d %H:%M:%S')"

# ─────────────────────────────────────────────
# 5. 클러스터 상태 확인
# ─────────────────────────────────────────────
echo ""
echo "▶ [5/5] 클러스터 상태 확인..."

# kubeconfig 업데이트
aws eks update-kubeconfig \
  --name "${EKSCLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --alias "${EKSCLUSTER_NAME}"

echo ""
echo "  📋 클러스터 정보:"
kubectl cluster-info
echo ""
echo "  📋 노드 목록:"
kubectl get nodes -o wide
echo ""
echo "  📋 시스템 Pod:"
kubectl get pods -n kube-system

echo ""
echo "============================================"
echo "  ✅ EKS 클러스터 생성 및 확인 완료!"
echo "============================================"
echo ""
echo "  클러스터: ${EKSCLUSTER_NAME}"
echo "  리전:     ${AWS_REGION}"
echo "  VPC:      ${VPCID}"
echo ""
echo "  다음 단계:"
echo "    1. ./deploy-lbc.sh            # Load Balancer Controller 배포"
echo "    2. ./deploy-karpenter.sh      # Karpenter 노드 오토스케일러 배포"
echo "    3. kubectl apply -k sample-app/  # 샘플 애플리케이션 배포"
echo "============================================"
