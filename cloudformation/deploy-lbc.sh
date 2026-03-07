#!/bin/bash
set -euo pipefail

# AWS Load Balancer Controller 배포 스크립트

CLUSTER_NAME="${EKSCLUSTER_NAME:-eksworkshop}"
REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "============================================"
echo "  AWS Load Balancer Controller 배포"
echo "============================================"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Region:  ${REGION}"
echo ""

# 1. IAM Policy
echo "▶ [1/4] IAM Policy 생성"
if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
  echo "  ✅ IAM Policy 이미 존재"
else
  curl -so /tmp/iam_policy.json \
    "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json"
  aws iam create-policy --policy-name "${POLICY_NAME}" \
    --policy-document file:///tmp/iam_policy.json > /dev/null
  echo "  ✅ IAM Policy 생성 완료"
fi

# 2. IRSA ServiceAccount
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

# 3. Helm 설치
echo ""
echo "▶ [3/4] Helm 차트 설치"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks

VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)

HELM_CMD="install"
helm status aws-load-balancer-controller -n kube-system &>/dev/null && HELM_CMD="upgrade"

helm ${HELM_CMD} aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}"
echo "  ✅ Helm ${HELM_CMD} 완료"

# 4. 확인
echo ""
echo "▶ [4/4] 배포 상태 확인"
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

echo ""
echo "============================================"
echo "  ✅ AWS Load Balancer Controller 배포 완료!"
echo "============================================"
