#!/bin/bash
set -euo pipefail

# 쇼핑몰 앱 배포 스크립트 (CloudFront 보안 자동 적용)
# 사용법: ./02.deploy-app.sh [base|bilingual] [kubeconfig-context] [aws-profile]
#
# 배포 흐름:
#   1. Docker build + ECR push (bilingual만)
#   2. kubectl apply -k (앱 배포)
#   3. ALB 생성 대기
#   4. ALB SG → CloudFront Prefix List 제한 (자동)
#   5. CloudFront Distribution 생성/업데이트 (자동)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_TYPE=${1:-bilingual}
KUBE_CTX=${2:-}
AWS_PROFILE_ARG=${3:-}
REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  쇼핑몰 앱 배포 + CloudFront 보안"
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
    echo "  ❌ 사용법: $0 [base|bilingual] [kube-context] [aws-profile]"
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
PROFILE_OPT=""
[ -n "${AWS_PROFILE_ARG}" ] && PROFILE_OPT="--profile ${AWS_PROFILE_ARG}"

echo "  디렉토리: ${APP_DIR}"
[ -n "${KUBE_CTX}" ] && echo "  Context: ${KUBE_CTX}"
[ -n "${AWS_PROFILE_ARG}" ] && echo "  Profile: ${AWS_PROFILE_ARG}"
echo ""

# ─────────────────────────────────────────────
# Step 1: Docker build + ECR push (bilingual만)
# ─────────────────────────────────────────────
if [ "${APP_TYPE}" = "bilingual" ] && [ -f "${APP_DIR}/ui/Dockerfile" ]; then
  echo "▶ [1/5] UI Docker 이미지 빌드 + ECR Push"

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text ${PROFILE_OPT})
  REPO_NAME="lab-shop-ui"
  ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

  aws ecr create-repository --repository-name ${REPO_NAME} --region ${REGION} ${PROFILE_OPT} 2>/dev/null || true
  docker build -t ${REPO_NAME}:latest ${APP_DIR}/ui/ 2>&1 | tail -3
  aws ecr get-login-password --region ${REGION} ${PROFILE_OPT} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com 2>&1 | tail -1
  docker tag ${REPO_NAME}:latest ${ECR_URI}:latest
  docker push ${ECR_URI}:latest 2>&1 | tail -2
  echo "  ✅ 이미지: ${ECR_URI}:latest"

  echo ""
  echo "▶ [2/5] Kustomize 배포 (이미지 교체)"
  TMPDIR=$(mktemp -d)
  cp -r ${APP_DIR}/* ${TMPDIR}/
  sed -i "s|ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/lab-shop-ui:latest|${ECR_URI}:latest|g" ${TMPDIR}/ui/deployment.yaml
  kubectl apply -k ${TMPDIR}/ ${CTX_OPT} 2>&1
  rm -rf ${TMPDIR}
  # Force pull new image (tag is always :latest)
  kubectl rollout restart deployment/ui -n ui ${CTX_OPT} 2>/dev/null || true
else
  echo "▶ [1/5] Kustomize 배포"
  kubectl apply -k ${APP_DIR}/ ${CTX_OPT} 2>&1
fi

# ─────────────────────────────────────────────
# Step 3: ALB 생성 대기
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/5] ALB 생성 대기..."
ALB=""
for i in $(seq 1 30); do
  ALB=$(kubectl get ingress -n ui ${CTX_OPT} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$ALB" ]; then
    echo "  ✅ ALB: ${ALB}"
    break
  fi
  sleep 5
done

if [ -z "$ALB" ]; then
  echo "  ⏳ ALB 아직 프로비저닝 중. CloudFront는 나중에 수동 실행하세요:"
  echo "    ./03.deploy-cloudfront-protection.sh ${KUBE_CTX} ${AWS_PROFILE_ARG}"
  echo ""
  echo "  ✅ 앱 배포 완료 (CloudFront 보안은 ALB 생성 후 적용 필요)"
  exit 0
fi

# ─────────────────────────────────────────────
# Step 4: ALB SG → CloudFront Prefix List 제한
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/5] ALB SG 보안 강화 (CloudFront Prefix List)"

CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

ALB_SG=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='${ALB}'].SecurityGroups[0]" \
  --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

if [ -n "${ALB_SG}" ] && [ "${ALB_SG}" != "None" ]; then
  # 0.0.0.0/0 인바운드 제거
  aws ec2 revoke-security-group-ingress --group-id ${ALB_SG} \
    --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
    --region "${REGION}" ${PROFILE_OPT} 2>/dev/null && echo "  ✅ 0.0.0.0/0 제거" || echo "  ⏭  이미 제거됨"

  # CloudFront Prefix List 허용
  aws ec2 authorize-security-group-ingress --group-id ${ALB_SG} \
    --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"PrefixListIds\":[{\"PrefixListId\":\"${CF_PREFIX_LIST_ID}\",\"Description\":\"HTTP from CloudFront only\"}]}]" \
    --region "${REGION}" ${PROFILE_OPT} 2>/dev/null && echo "  ✅ CloudFront Prefix List 허용" || echo "  ⏭  이미 설정됨"
else
  echo "  ⚠️  ALB SG를 찾을 수 없습니다"
fi

# ─────────────────────────────────────────────
# Step 5: CloudFront Distribution 생성/업데이트
# ─────────────────────────────────────────────
echo ""
echo "▶ [5/5] CloudFront Distribution"

STACK_NAME="lab-shop-cloudfront"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].StackStatus' --output text \
  --region "${REGION}" ${PROFILE_OPT} 2>/dev/null || echo "NOT_FOUND")

if [ "${STACK_STATUS}" = "NOT_FOUND" ] || [[ "${STACK_STATUS}" == *"ROLLBACK"* ]]; then
  # 롤백 스택 삭제
  if [[ "${STACK_STATUS}" == *"ROLLBACK"* ]]; then
    aws cloudformation delete-stack --stack-name ${STACK_NAME} --region "${REGION}" ${PROFILE_OPT} 2>/dev/null
    aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region "${REGION}" ${PROFILE_OPT} 2>/dev/null
  fi

  # 새로 생성
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file "${SCRIPT_DIR}/cloudfront-alb-protection.yaml" \
    --parameter-overrides \
      ALBDnsName="${ALB}" \
      ALBSecurityGroupId="${ALB_SG}" \
      CloudFrontPrefixListId="${CF_PREFIX_LIST_ID}" \
    --region "${REGION}" ${PROFILE_OPT} 2>&1 | tail -3
  echo "  ✅ CloudFront 생성 완료"
else
  # ALB DNS가 변경되었으면 업데이트
  CURRENT_ALB=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
    --query "Stacks[0].Parameters[?ParameterKey=='ALBDnsName'].ParameterValue|[0]" \
    --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

  if [ "${CURRENT_ALB}" != "${ALB}" ]; then
    aws cloudformation deploy \
      --stack-name ${STACK_NAME} \
      --template-file "${SCRIPT_DIR}/cloudfront-alb-protection.yaml" \
      --parameter-overrides \
        ALBDnsName="${ALB}" \
        ALBSecurityGroupId="${ALB_SG}" \
        CloudFrontPrefixListId="${CF_PREFIX_LIST_ID}" \
      --region "${REGION}" ${PROFILE_OPT} 2>&1 | tail -3
    echo "  ✅ CloudFront 업데이트 (ALB 변경 감지)"
  else
    echo "  ✅ CloudFront 이미 존재 (변경 없음)"
  fi
fi

# 결과 출력
CF_URL=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

echo ""
echo "============================================"
echo "  ✅ ${APP_TYPE} 앱 배포 + CloudFront 보안 완료!"
echo "============================================"
echo ""
echo "  🌐 Shop URL: ${CF_URL}"
echo "  🔒 보안:"
echo "     CloudFront (HTTPS) → ALB (CF Prefix List + X-Lab-Secret)"
echo "     직접 ALB 접근: 차단됨"
echo ""
echo "  📦 Pods:"
kubectl get pods -A ${CTX_OPT} 2>/dev/null | grep -E "carts|catalog|checkout|orders|ui" | head -15
echo ""
echo "============================================"
