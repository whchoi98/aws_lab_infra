#!/bin/bash
set -e

# EKS 클러스터 및 관련 리소스 정리

EKSCLUSTER_NAME=${EKSCLUSTER_NAME:-eksworkshop}
AWS_REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  EKS 클러스터 정리"
echo "============================================"
echo ""
echo "  클러스터: ${EKSCLUSTER_NAME}"
echo "  리전: ${AWS_REGION}"
echo ""
read -p "  정말 삭제하시겠습니까? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "  취소되었습니다."
  exit 0
fi

echo ""
echo "▶ [1/3] Kubernetes 리소스 정리..."
kubectl delete -k ~/my-project/aws_lab_infra/cloudformation/sample-app/ 2>/dev/null || true
kubectl delete svc --all -A 2>/dev/null || true

echo ""
echo "▶ [2/3] Load Balancer Controller 제거..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

echo ""
echo "▶ [3/3] EKS 클러스터 삭제..."
eksctl delete cluster --name "${EKSCLUSTER_NAME}" --region "${AWS_REGION}" --wait

echo ""
echo "============================================"
echo "  ✅ EKS 클러스터 삭제 완료"
echo "============================================"
