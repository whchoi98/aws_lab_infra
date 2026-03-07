#!/bin/bash
set -euo pipefail

# AWS Load Balancer Controller를 EKS 클러스터에 배포합니다.
# eksctl IRSA + Helm 차트 기반 설치.
#
# 사전 요구사항:
#   - EKS 클러스터가 ACTIVE 상태
#   - kubectl이 클러스터에 연결된 상태
#   - Helm 3 설치됨
#
# 사용법: ./deploy-lbc.sh

source ~/.bash_profile 2>/dev/null || true

CLUSTER_NAME="${EKSCLUSTER_NAME:-eksworkshop}"
REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
LBC_VERSION="v2.11.0"

echo "============================================"
echo "  AWS Load Balancer Controller 배포"
echo "============================================"
echo ""
echo "  Cluster:  ${CLUSTER_NAME}"
echo "  Region:   ${REGION}"
echo "  Account:  ${ACCOUNT_ID}"
echo "  LBC 버전: ${LBC_VERSION}"
echo ""

# ─────────────────────────────────────────────
# 0. 사전 조건 확인
# ─────────────────────────────────────────────
echo "▶ [0/5] 사전 조건 확인..."

# kubectl 연결 확인
if ! kubectl cluster-info &>/dev/null; then
  echo "  ❌ kubectl이 클러스터에 연결되지 않았습니다."
  echo "  먼저 kubeconfig를 업데이트하세요:"
  echo "    aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}"
  exit 1
fi

# EKS 클러스터 상태 확인
EKS_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query 'cluster.status' --output text \
  --region "${REGION}" 2>/dev/null || echo "NOT_FOUND")

if [ "$EKS_STATUS" != "ACTIVE" ]; then
  echo "  ❌ EKS 클러스터가 ACTIVE 상태가 아닙니다: ${EKS_STATUS}"
  exit 1
fi

# OIDC Provider 확인
OIDC_ISSUER=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query 'cluster.identity.oidc.issuer' --output text \
  --region "${REGION}" 2>/dev/null || echo "")

if [ -z "$OIDC_ISSUER" ]; then
  echo "  ⚠️  OIDC Provider가 설정되지 않았습니다. 생성합니다..."
  eksctl utils associate-iam-oidc-provider \
    --cluster="${CLUSTER_NAME}" \
    --region="${REGION}" \
    --approve
fi

echo "  ✅ 사전 조건 확인 완료"

# ─────────────────────────────────────────────
# 1. IAM Policy 생성
# ─────────────────────────────────────────────
echo ""
echo "▶ [1/5] IAM Policy 생성"
if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
  echo "  ✅ IAM Policy 이미 존재 — 스킵"
else
  echo "  IAM Policy 다운로드 및 생성..."
  curl -so /tmp/iam_policy.json \
    "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json"
  aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file:///tmp/iam_policy.json > /dev/null
  rm -f /tmp/iam_policy.json
  echo "  ✅ IAM Policy 생성 완료"
fi

# ─────────────────────────────────────────────
# 2. Pod Identity 설정 (IRSA 대체)
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/5] Pod Identity IAM Role + Association"
LBC_ROLE_NAME="AmazonEKSLoadBalancerControllerRole"

# Pod Identity Agent addon
aws eks create-addon --cluster-name "${CLUSTER_NAME}" --addon-name eks-pod-identity-agent \
  --region "${REGION}" 2>/dev/null || true

# IAM Role (trust: pods.eks.amazonaws.com)
if ! aws iam get-role --role-name "${LBC_ROLE_NAME}" &>/dev/null; then
  aws iam create-role --role-name "${LBC_ROLE_NAME}" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}' > /dev/null
fi
aws iam attach-role-policy --role-name "${LBC_ROLE_NAME}" --policy-arn "${POLICY_ARN}" 2>/dev/null || true

# Pod Identity Association
LBC_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${LBC_ROLE_NAME}"
aws eks create-pod-identity-association \
  --cluster-name "${CLUSTER_NAME}" \
  --namespace kube-system \
  --service-account aws-load-balancer-controller \
  --role-arn "${LBC_ROLE_ARN}" \
  --region "${REGION}" 2>/dev/null || echo "  Association 이미 존재"

echo "  ✅ Pod Identity 설정 완료"

# ─────────────────────────────────────────────
# 3. Helm 리포지토리 설정
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/5] Helm 리포지토리 설정"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks
echo "  ✅ Helm 리포 업데이트 완료"

# ─────────────────────────────────────────────
# 4. Helm 차트 설치/업그레이드
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/5] Helm 차트 설치"

VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text \
  --region "${REGION}")

HELM_CMD="install"
if helm status aws-load-balancer-controller -n kube-system &>/dev/null; then
  echo "  기존 설치 감지 — upgrade 실행"
  HELM_CMD="upgrade"
fi

helm ${HELM_CMD} aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait
echo "  ✅ Helm ${HELM_CMD} 완료"

# ─────────────────────────────────────────────
# 5. 배포 상태 확인
# ─────────────────────────────────────────────
echo ""
echo "▶ [5/5] 배포 상태 확인"
kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system --timeout=120s

echo ""
echo "  📋 LBC Pod 상태:"
kubectl get pods -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  -o wide

echo ""
echo "  📋 LBC 버전:"
kubectl get deployment aws-load-balancer-controller -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
echo ""

echo ""
echo "============================================"
echo "  ✅ AWS Load Balancer Controller 배포 완료!"
echo "============================================"
echo ""
echo "  이제 Ingress 리소스를 생성하면 ALB가 자동으로 프로비저닝됩니다."
echo ""
echo "  다음 단계:"
echo "    kubectl apply -k sample-app/   # 샘플 애플리케이션 배포"
echo "============================================"
