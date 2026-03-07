#!/bin/bash
set -euo pipefail

# Karpenter v1 설치 및 구성 스크립트
# EKS 클러스터에 Karpenter를 배포하고 NodePool + EC2NodeClass를 생성합니다.
#
# 사전 요구사항:
#   - EKS 클러스터가 ACTIVE 상태
#   - kubectl이 클러스터에 연결된 상태
#   - Helm 3 설치됨
#   - eksctl 설치됨
#
# 사용법: ./deploy-karpenter.sh

source ~/.bash_profile 2>/dev/null || true

CLUSTER_NAME="${EKSCLUSTER_NAME:-eksworkshop}"
REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
KARPENTER_VERSION="1.9.0"
KARPENTER_NAMESPACE="kube-system"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Karpenter ${KARPENTER_VERSION} 배포"
echo "============================================"
echo ""
echo "  Cluster:  ${CLUSTER_NAME}"
echo "  Region:   ${REGION}"
echo "  Account:  ${ACCOUNT_ID}"
echo ""

# ─────────────────────────────────────────────
# 0. 사전 조건 확인
# ─────────────────────────────────────────────
echo "▶ [0/6] 사전 조건 확인..."

if ! kubectl cluster-info &>/dev/null; then
  echo "  ❌ kubectl이 클러스터에 연결되지 않았습니다."
  exit 1
fi

OIDC_ENDPOINT=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query "cluster.identity.oidc.issuer" --output text --region "${REGION}")
OIDC_ID=$(echo "${OIDC_ENDPOINT}" | cut -d'/' -f5)

if [ -z "$OIDC_ID" ]; then
  echo "  ❌ OIDC Provider가 설정되지 않았습니다."
  exit 1
fi

echo "  ✅ OIDC Provider: ${OIDC_ID}"

# ─────────────────────────────────────────────
# 1. Karpenter IAM Role 생성 (IRSA)
# ─────────────────────────────────────────────
echo ""
echo "▶ [1/6] Karpenter Controller IAM Role 생성..."

KARPENTER_ROLE_NAME="KarpenterControllerRole-${CLUSTER_NAME}"

# Trust policy for Karpenter IRSA
cat > /tmp/karpenter-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:${KARPENTER_NAMESPACE}:karpenter"
        }
      }
    }
  ]
}
EOF

if aws iam get-role --role-name "${KARPENTER_ROLE_NAME}" &>/dev/null; then
  echo "  ✅ IAM Role 이미 존재 — 업데이트"
  aws iam update-assume-role-policy --role-name "${KARPENTER_ROLE_NAME}" \
    --policy-document file:///tmp/karpenter-trust-policy.json
else
  aws iam create-role --role-name "${KARPENTER_ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/karpenter-trust-policy.json > /dev/null
  echo "  ✅ IAM Role 생성 완료"
fi

# Karpenter Controller Policy
cat > /tmp/karpenter-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Karpenter",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ec2:DescribeImages",
        "ec2:RunInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeAvailabilityZones",
        "ec2:DeleteLaunchTemplate",
        "ec2:CreateTags",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateFleet",
        "ec2:DescribeSpotPriceHistory",
        "pricing:GetProducts"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ConditionalEC2Termination",
      "Effect": "Allow",
      "Action": "ec2:TerminateInstances",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "ec2:ResourceTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "PassNodeRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
    },
    {
      "Sid": "EKSClusterAccess",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster"
      ],
      "Resource": "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"
    },
    {
      "Sid": "AllowScopedInstanceProfileActions",
      "Effect": "Allow",
      "Action": [
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteInstanceProfile"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
          "aws:ResourceTag/topology.kubernetes.io/region": "${REGION}"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileCreation",
      "Effect": "Allow",
      "Action": "iam:CreateInstanceProfile",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
          "aws:RequestTag/topology.kubernetes.io/region": "${REGION}"
        },
        "StringLike": {
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowInstanceProfileTagActions",
      "Effect": "Allow",
      "Action": "iam:TagInstanceProfile",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
          "aws:ResourceTag/topology.kubernetes.io/region": "${REGION}"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowGetInstanceProfile",
      "Effect": "Allow",
      "Action": "iam:GetInstanceProfile",
      "Resource": "*"
    },
    {
      "Sid": "AllowInterruptionQueueActions",
      "Effect": "Allow",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ],
      "Resource": "arn:aws:sqs:${REGION}:${ACCOUNT_ID}:${CLUSTER_NAME}"
    }
  ]
}
EOF

POLICY_NAME="KarpenterControllerPolicy-${CLUSTER_NAME}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
  # 기존 정책 버전 삭제 후 업데이트
  VERSIONS=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
    --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
  for V in $VERSIONS; do
    aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "$V" 2>/dev/null || true
  done
  aws iam create-policy-version --policy-arn "${POLICY_ARN}" \
    --policy-document file:///tmp/karpenter-policy.json --set-as-default > /dev/null
else
  aws iam create-policy --policy-name "${POLICY_NAME}" \
    --policy-document file:///tmp/karpenter-policy.json > /dev/null
fi

aws iam attach-role-policy --role-name "${KARPENTER_ROLE_NAME}" --policy-arn "${POLICY_ARN}"
echo "  ✅ Controller IAM Role + Policy 완료"

# ─────────────────────────────────────────────
# 2. Karpenter Node IAM Role 생성
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/6] Karpenter Node IAM Role 생성..."

NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"

cat > /tmp/karpenter-node-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

if ! aws iam get-role --role-name "${NODE_ROLE_NAME}" &>/dev/null; then
  aws iam create-role --role-name "${NODE_ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/karpenter-node-trust.json > /dev/null
fi

for POLICY in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
  aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/${POLICY}" 2>/dev/null || true
done

echo "  ✅ Node IAM Role 완료"

# ─────────────────────────────────────────────
# 3. EKS Access Entry (Node Role이 클러스터에 조인하도록)
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/6] EKS Access Entry 설정..."

aws eks create-access-entry \
  --cluster-name "${CLUSTER_NAME}" \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:role/${NODE_ROLE_NAME}" \
  --type EC2_LINUX \
  --region "${REGION}" 2>/dev/null && echo "  ✅ Access Entry 생성 완료" || echo "  ✅ Access Entry 이미 존재"

# ─────────────────────────────────────────────
# 4. Private Subnet 태깅 (Karpenter 노드 발견용)
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/6] Private Subnet 태그 추가..."

for SUBNET_ID in ${PRIVATE_SUBNET_A:-} ${PRIVATE_SUBNET_B:-}; do
  if [ -n "$SUBNET_ID" ]; then
    aws ec2 create-tags --resources "${SUBNET_ID}" \
      --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
      --region "${REGION}" 2>/dev/null || true
    echo "  ✅ Tagged: ${SUBNET_ID}"
  fi
done

# EC2 SG도 태깅
CLUSTER_SG=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text --region "${REGION}")

aws ec2 create-tags --resources "${CLUSTER_SG}" \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
  --region "${REGION}" 2>/dev/null || true
echo "  ✅ Cluster SG tagged: ${CLUSTER_SG}"

# ─────────────────────────────────────────────
# 5. Helm으로 Karpenter 설치
# ─────────────────────────────────────────────
echo ""
echo "▶ [5/6] Karpenter Helm 차트 설치..."

helm registry logout public.ecr.aws 2>/dev/null || true

KARPENTER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${KARPENTER_ROLE_NAME}"

HELM_CMD="install"
if helm status karpenter -n "${KARPENTER_NAMESPACE}" &>/dev/null; then
  HELM_CMD="upgrade"
fi

helm ${HELM_CMD} karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query cluster.endpoint --output text --region ${REGION})" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_ROLE_ARN}" \
  --set "controller.resources.requests.cpu=1" \
  --set "controller.resources.requests.memory=1Gi" \
  --set "controller.resources.limits.cpu=1" \
  --set "controller.resources.limits.memory=1Gi" \
  --wait

echo "  ✅ Karpenter ${HELM_CMD} 완료"

# ─────────────────────────────────────────────
# 6. NodePool + EC2NodeClass 생성
# ─────────────────────────────────────────────
echo ""
echo "▶ [6/6] NodePool + EC2NodeClass 생성..."

cat <<EOF | kubectl apply -f -
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        managed-by: karpenter
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t4g.small
            - t4g.medium
            - t4g.large
            - t4g.xlarge
            - t4g.2xlarge
            - m7g.large
            - m7g.xlarge
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: "100"
    memory: 200Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: "${NODE_ROLE_NAME}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
  tags:
    Environment: lab
    Project: aws-lab-infra
    ManagedBy: karpenter
EOF

echo "  ✅ NodePool + EC2NodeClass 생성 완료"

# ─────────────────────────────────────────────
# 확인
# ─────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ Karpenter 배포 완료!"
echo "============================================"
echo ""
echo "  📋 Karpenter Pod 상태:"
kubectl get pods -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter
echo ""
echo "  📋 NodePool:"
kubectl get nodepool
echo ""
echo "  📋 EC2NodeClass:"
kubectl get ec2nodeclass
echo ""
echo "  설정:"
echo "    - Architecture: arm64 (Graviton)"
echo "    - Capacity: On-Demand"
echo "    - 인스턴스: t4g.small ~ t4g.2xlarge, m7g.large ~ m7g.xlarge"
echo "    - Consolidation: WhenEmptyOrUnderutilized (1분 후)"
echo "    - 노드 만료: 30일 (720h)"
echo "    - SSM 접속: ✅ (AmazonSSMManagedInstanceCore)"
echo ""
echo "  다음 단계:"
echo "    kubectl apply -k sample-app/   # 워크로드 배포 시 자동 노드 프로비저닝"
echo "============================================"

rm -f /tmp/karpenter-trust-policy.json /tmp/karpenter-policy.json /tmp/karpenter-node-trust.json
