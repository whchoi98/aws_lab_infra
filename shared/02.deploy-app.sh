#!/bin/bash
set -euo pipefail

# 쇼핑몰 앱 배포 스크립트
# 사용법: ./deploy-app.sh [base|bilingual] [kubeconfig-context]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_TYPE=${1:-bilingual}
KUBE_CTX=${2:-}

echo "============================================"
echo "  쇼핑몰 앱 배포"
echo "============================================"
echo ""

case "${APP_TYPE}" in
  base)
    APP_DIR="${SCRIPT_DIR}/base-application"
    echo "  앱: base-application (영어 전용, Retail Store Sample)"
    ;;
  bilingual)
    APP_DIR="${SCRIPT_DIR}/bilingual-app"
    echo "  앱: bilingual-app (한국어/영어, Custom UI)"
    ;;
  *)
    echo "  ❌ 사용법: $0 [base|bilingual] [kube-context]"
    echo "    base      - AWS Retail Store Sample (영어)"
    echo "    bilingual  - Custom bilingual UI (한/영)"
    exit 1
    ;;
esac

if [ ! -d "${APP_DIR}" ]; then
  echo "  ❌ ${APP_DIR} 디렉토리가 없습니다."
  exit 1
fi

CTX_OPT=""
[ -n "${KUBE_CTX}" ] && CTX_OPT="--context ${KUBE_CTX}"

echo "  디렉토리: ${APP_DIR}"
[ -n "${KUBE_CTX}" ] && echo "  Context: ${KUBE_CTX}"
echo ""

# bilingual-app인 경우 Docker 빌드 + ECR push 필요
if [ "${APP_TYPE}" = "bilingual" ] && [ -f "${APP_DIR}/ui/Dockerfile" ]; then
  echo "▶ [1/3] UI Docker 이미지 빌드 + ECR Push"
  
  REGION=${AWS_REGION:-ap-northeast-2}
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  REPO_NAME="lab-shop-ui"
  ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

  # ECR 리포 생성 (없으면)
  aws ecr create-repository --repository-name ${REPO_NAME} --region ${REGION} 2>/dev/null || true

  # Docker 빌드
  docker build -t ${REPO_NAME}:latest ${APP_DIR}/ui/ 2>&1 | tail -3

  # ECR 로그인 + Push
  aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com 2>&1 | tail -1
  docker tag ${REPO_NAME}:latest ${ECR_URI}:latest
  docker push ${ECR_URI}:latest 2>&1 | tail -2
  echo "  ✅ 이미지: ${ECR_URI}:latest"

  # deployment.yaml의 이미지 교체하여 배포
  echo ""
  echo "▶ [2/3] Kustomize 배포 (이미지 교체)"
  TMPDIR=$(mktemp -d)
  cp -r ${APP_DIR}/* ${TMPDIR}/
  sed -i "s|ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/lab-shop-ui:latest|${ECR_URI}:latest|g" ${TMPDIR}/ui/deployment.yaml
  kubectl apply -k ${TMPDIR}/ ${CTX_OPT} 2>&1
  rm -rf ${TMPDIR}

else
  echo "▶ [1/2] Kustomize 배포"
  kubectl apply -k ${APP_DIR}/ ${CTX_OPT} 2>&1
fi

# 배포 상태 확인
echo ""
echo "▶ 배포 상태 확인"
sleep 10
kubectl get pods -A ${CTX_OPT} 2>/dev/null | grep -E "carts|catalog|checkout|orders|ui" | head -15

echo ""
# ALB Ingress 확인
ALB=$(kubectl get ingress -A ${CTX_OPT} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$ALB" ]; then
  echo "  🌐 ALB URL: http://${ALB}"
else
  echo "  ⏳ ALB 프로비저닝 중 (수 분 소요)"
fi

echo ""
echo "============================================"
echo "  ✅ ${APP_TYPE} 앱 배포 완료!"
echo "============================================"
