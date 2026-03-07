#!/bin/bash
set -e

# EKS 클러스터 및 관련 리소스를 안전하게 정리합니다.
# eksctl delete cluster를 사용하여 CloudFormation 스택까지 완전 삭제합니다.
#
# 정리 순서:
#   1. Kubernetes 리소스 (Ingress, Service 등 AWS 리소스를 생성하는 것들)
#   2. AWS Load Balancer Controller (Helm)
#   3. IRSA ServiceAccount (eksctl)
#   4. EKS 클러스터 (eksctl)
#   5. 환경변수 정리

source ~/.bash_profile 2>/dev/null || true

EKSCLUSTER_NAME=${EKSCLUSTER_NAME:-eksworkshop}
AWS_REGION=${AWS_REGION:-ap-northeast-2}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  EKS 클러스터 정리"
echo "============================================"
echo ""
echo "  클러스터: ${EKSCLUSTER_NAME}"
echo "  리전:     ${AWS_REGION}"
echo ""

# 클러스터 존재 확인
CLUSTER_STATUS=$(aws eks describe-cluster --name "${EKSCLUSTER_NAME}" \
  --query 'cluster.status' --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" = "NOT_FOUND" ]; then
  echo "  ⚠️  클러스터 '${EKSCLUSTER_NAME}'이(가) 존재하지 않습니다."
  exit 0
fi

echo "  클러스터 상태: ${CLUSTER_STATUS}"
echo ""
echo "  ⚠️  이 작업은 되돌릴 수 없습니다!"
echo "  다음 리소스가 삭제됩니다:"
echo "    - EKS 클러스터 및 모든 노드그룹"
echo "    - IRSA ServiceAccount"
echo "    - 관련 CloudFormation 스택"
echo "    - Kubernetes에서 생성된 AWS 리소스 (ELB, ENI 등)"
echo ""
read -p "  정말 삭제하시겠습니까? 'yes'를 입력하세요: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "  취소되었습니다."
  exit 0
fi

# ─────────────────────────────────────────────
# 1. Kubernetes 리소스 정리
# ─────────────────────────────────────────────
echo ""
echo "▶ [1/4] Kubernetes 리소스 정리..."

# Ingress 삭제 (ALB가 먼저 삭제되어야 VPC 리소스 정리 가능)
echo "  Ingress 리소스 삭제..."
kubectl delete ingress --all -A 2>/dev/null || true

# 샘플 앱 삭제
echo "  샘플 애플리케이션 삭제..."
kubectl delete -k "${SCRIPT_DIR}/sample-app/" 2>/dev/null || true

# LoadBalancer 타입 서비스 삭제 (ELB 정리)
echo "  LoadBalancer 서비스 삭제..."
for NS in $(kubectl get svc --all-namespaces -o json 2>/dev/null | \
  python3 -c "import sys,json; [print(s['metadata']['namespace']+'/'+s['metadata']['name']) for s in json.load(sys.stdin).get('items',[]) if s['spec'].get('type')=='LoadBalancer']" 2>/dev/null); do
  NS_NAME=$(echo "$NS" | cut -d'/' -f1)
  SVC_NAME=$(echo "$NS" | cut -d'/' -f2)
  echo "    삭제: ${NS_NAME}/${SVC_NAME}"
  kubectl delete svc "${SVC_NAME}" -n "${NS_NAME}" 2>/dev/null || true
done

echo "  ✅ Kubernetes 리소스 정리 완료"
echo "  AWS 리소스 정리 대기 (30초)..."
sleep 30

# ─────────────────────────────────────────────
# 2. Load Balancer Controller 제거
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/4] AWS Load Balancer Controller 제거..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null && \
  echo "  ✅ LBC Helm 릴리스 삭제 완료" || \
  echo "  ⏭  LBC가 설치되어 있지 않음 — 스킵"

# ─────────────────────────────────────────────
# 3. IRSA ServiceAccount 정리
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/4] IRSA ServiceAccount 정리..."
eksctl delete iamserviceaccount \
  --cluster="${EKSCLUSTER_NAME}" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region="${AWS_REGION}" 2>/dev/null && \
  echo "  ✅ IRSA 삭제 완료" || \
  echo "  ⏭  IRSA가 없음 — 스킵"

# ─────────────────────────────────────────────
# 4. EKS 클러스터 삭제
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/4] EKS 클러스터 삭제..."
echo "  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  이 작업은 10-15분 소요됩니다..."
echo ""

eksctl delete cluster \
  --name "${EKSCLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --wait

echo ""
echo "  완료 시간: $(date '+%Y-%m-%d %H:%M:%S')"

# 환경변수 정리 (bash_profile에서 EKS 관련 변수 제거)
for VAR in EKSCLUSTER_NAME EKS_VERSION INSTANCE_TYPE PRIVATE_MGMD_NODE MASTER_ARN; do
  sed -i "/^export ${VAR}=/d" ~/.bash_profile 2>/dev/null || true
done

echo ""
echo "============================================"
echo "  ✅ EKS 클러스터 삭제 완료"
echo "============================================"
echo ""
echo "  삭제된 리소스:"
echo "    - EKS 클러스터: ${EKSCLUSTER_NAME}"
echo "    - 관리형 노드그룹"
echo "    - IRSA ServiceAccount"
echo "    - 관련 IAM Role/Policy"
echo "    - 관련 CloudFormation 스택"
echo ""
echo "  VPC 인프라(DMZVPC, VPC01, VPC02, TGW)는 그대로 유지됩니다."
echo "============================================"
