#!/bin/bash
set -e

# EKS 클러스터 생성 스크립트
# 사전 요구사항: source eks-setup-env.sh

source ~/.bash_profile

: "${VPCID:?VPCID 환경변수가 설정되지 않았습니다. source eks-setup-env.sh를 실행하세요.}"
: "${PRIVATE_SUBNET_A:?PRIVATE_SUBNET_A가 설정되지 않았습니다.}"
: "${PRIVATE_SUBNET_B:?PRIVATE_SUBNET_B가 설정되지 않았습니다.}"
: "${EKSCLUSTER_NAME:=eksworkshop}"
: "${EKS_VERSION:=1.33}"
: "${INSTANCE_TYPE:=t4g.xlarge}"
: "${PRIVATE_MGMD_NODE:=managed-backend-workloads}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_CONFIG="${SCRIPT_DIR}/eksworkshop.yaml"

echo "============================================"
echo "  EKS 클러스터 생성"
echo "============================================"
echo ""
echo "  클러스터: ${EKSCLUSTER_NAME}"
echo "  버전:     ${EKS_VERSION}"
echo "  VPC:      ${VPCID}"
echo "  Subnets:  ${PRIVATE_SUBNET_A}, ${PRIVATE_SUBNET_B}"
echo "  노드:     ${INSTANCE_TYPE} x 4-8"
echo ""

# KMS Key ARN
MASTER_ARN=$(aws kms describe-key --key-id alias/eksworkshop \
  --query 'KeyMetadata.Arn' --output text 2>/dev/null || echo "")

# eksctl config 생성
cat > "${CLUSTER_CONFIG}" <<YAML_EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${EKSCLUSTER_NAME}
  region: ${AWS_REGION:-ap-northeast-2}
  version: "${EKS_VERSION}"

vpc:
  id: "${VPCID}"
  subnets:
    private:
      private-subnet-a:
        id: "${PRIVATE_SUBNET_A}"
      private-subnet-b:
        id: "${PRIVATE_SUBNET_B}"

$([ -n "$MASTER_ARN" ] && echo "secretsEncryption:
  keyARN: ${MASTER_ARN}")

managedNodeGroups:
  - name: ${PRIVATE_MGMD_NODE}
    instanceType: ${INSTANCE_TYPE}
    desiredCapacity: 4
    minSize: 2
    maxSize: 8
    volumeSize: 50
    volumeType: gp3
    volumeEncrypted: true
    amiFamily: AmazonLinux2023
    labels:
      nodegroup-type: "${PRIVATE_MGMD_NODE}"
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
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]

iam:
  withOIDC: true

addons:
  - name: vpc-cni
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    wellKnownPolicies:
      ebsCSIController: true
YAML_EOF

echo "  ✅ eksctl 설정 파일 생성: ${CLUSTER_CONFIG}"
echo ""
echo "  dry-run으로 확인..."
eksctl create cluster --config-file="${CLUSTER_CONFIG}" --dry-run 2>&1 | head -20
echo ""
echo "  클러스터를 생성하려면:"
echo "    eksctl create cluster --config-file=${CLUSTER_CONFIG}"
echo ""
echo "============================================"
