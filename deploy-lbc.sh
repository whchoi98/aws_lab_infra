#!/bin/bash
set -euo pipefail

# AWS Load Balancer Controller 설치 스크립트
# 사전 요구사항: EKS 클러스터, OIDC provider, Helm

CLUSTER_NAME="eksworkshop"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
LBC_IAM_POLICY_URL="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json"

echo "============================================"
echo "AWS Load Balancer Controller 설치"
echo "============================================"
echo "Cluster: ${CLUSTER_NAME}"
echo "Region:  ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo "============================================"

# 1. IAM Policy 생성 (이미 존재하면 스킵)
echo ""
echo "▶ [1/4] IAM Policy 생성"
if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
  echo "  ✅ IAM Policy 이미 존재 - 스킵"
else
  curl -so /tmp/iam_policy.json "${LBC_IAM_POLICY_URL}"
  aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file:///tmp/iam_policy.json > /dev/null
  echo "  ✅ IAM Policy 생성 완료"
fi

# 2. IRSA ServiceAccount 생성
echo ""
echo "▶ [2/4] IRSA ServiceAccount 생성"
eksctl create iamserviceaccount \
  --cluster="${CLUSTER_NAME}" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="${POLICY_ARN}" \
  --override-existing-serviceaccounts \
  --approve

echo "  ✅ ServiceAccount 생성 완료"

# 3. Helm 차트 설치
echo ""
echo "▶ [3/4] Helm 차트 설치"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.vpcId" --output text)

if helm status aws-load-balancer-controller -n kube-system &>/dev/null; then
  echo "  ⬆ 기존 설치 감지 - upgrade 실행"
  HELM_CMD="upgrade"
else
  HELM_CMD="install"
fi

helm ${HELM_CMD} aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}"

echo "  ✅ Helm ${HELM_CMD} 완료"

# 4. 배포 확인
echo ""
echo "▶ [4/4] 배포 상태 확인"
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
echo ""
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

echo ""
echo "============================================"
echo "✅ AWS Load Balancer Controller 설치 완료!"
echo "============================================"
