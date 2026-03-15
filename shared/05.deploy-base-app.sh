#!/bin/bash
set -eo pipefail

# base-application (영어) 별도 배포 스크립트
# bilingual-app과 병렬 운영: 별도 namespace(ui-base) + 별도 ALB + 별도 CloudFront
# 백엔드(carts, catalog, checkout, orders)는 bilingual과 공유
#
# 사용법: ./05.deploy-base-app.sh [kubeconfig-context] [aws-profile]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${SCRIPT_DIR}/base-application-standalone"
KUBE_CTX=${1:-}
AWS_PROFILE_ARG=${2:-}
REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  Base Application (영어) 병렬 배포"
echo "============================================"
echo ""
echo "  Namespace: ui-base (bilingual의 ui와 별도)"
echo "  백엔드: carts/catalog/checkout/orders 공유"
echo ""

CTX_OPT=""
[ -n "${KUBE_CTX}" ] && CTX_OPT="--context ${KUBE_CTX}"
PROFILE_OPT=""
[ -n "${AWS_PROFILE_ARG}" ] && PROFILE_OPT="--profile ${AWS_PROFILE_ARG}"

# ─────────────────────────────────────────────
# Step 1: Kustomize 배포
# ─────────────────────────────────────────────
echo "▶ [1/4] Kustomize 배포 (ui-base namespace)"
kubectl apply -k ${APP_DIR}/ ${CTX_OPT} 2>&1

# ─────────────────────────────────────────────
# Step 2: ALB 생성 대기
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/4] ALB 생성 대기..."
ALB=""
for i in $(seq 1 30); do
  ALB=$(kubectl get ingress -n ui-base ${CTX_OPT} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$ALB" ]; then
    echo "  ✅ ALB: ${ALB}"
    break
  fi
  sleep 5
done

if [ -z "$ALB" ]; then
  echo "  ⏳ ALB 아직 프로비저닝 중. CloudFront는 나중에 수동 실행하세요."
  echo "  ✅ 앱 배포 완료 (CloudFront 보안은 ALB 생성 후 적용 필요)"
  exit 0
fi

# ─────────────────────────────────────────────
# Step 3: ALB SG → CloudFront Prefix List 제한
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/4] ALB SG 보안 강화 (CloudFront Prefix List)"

CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

ALB_SG=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='${ALB}'].SecurityGroups[0]" \
  --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

if [ -n "${ALB_SG}" ] && [ "${ALB_SG}" != "None" ]; then
  aws ec2 revoke-security-group-ingress --group-id ${ALB_SG} \
    --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
    --region "${REGION}" ${PROFILE_OPT} 2>/dev/null && echo "  ✅ 0.0.0.0/0 제거" || echo "  ⏭  이미 제거됨"

  aws ec2 authorize-security-group-ingress --group-id ${ALB_SG} \
    --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"PrefixListIds\":[{\"PrefixListId\":\"${CF_PREFIX_LIST_ID}\",\"Description\":\"HTTP from CloudFront only\"}]}]" \
    --region "${REGION}" ${PROFILE_OPT} 2>/dev/null && echo "  ✅ CloudFront Prefix List 허용" || echo "  ⏭  이미 설정됨"
else
  echo "  ⚠️  ALB SG를 찾을 수 없습니다"
fi

# ─────────────────────────────────────────────
# Step 4: CloudFront Distribution (별도 스택)
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/4] CloudFront Distribution (base-app 전용)"

STACK_NAME="lab-base-cloudfront"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].StackStatus' --output text \
  --region "${REGION}" ${PROFILE_OPT} 2>/dev/null || echo "NOT_FOUND")

if [ "${STACK_STATUS}" = "NOT_FOUND" ] || [[ "${STACK_STATUS}" == *"ROLLBACK"* ]]; then
  if [[ "${STACK_STATUS}" == *"ROLLBACK"* ]]; then
    aws cloudformation delete-stack --stack-name ${STACK_NAME} --region "${REGION}" ${PROFILE_OPT} 2>/dev/null
    aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region "${REGION}" ${PROFILE_OPT} 2>/dev/null
  fi

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

CF_URL=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text --region "${REGION}" ${PROFILE_OPT} 2>/dev/null)

echo ""
echo "============================================"
echo "  ✅ Base Application 배포 완료!"
echo "============================================"
echo ""
echo "  🌐 Base App (영어): ${CF_URL}"
echo "  🔒 보안: CloudFront → ALB (CF Prefix List)"
echo ""
echo "  📦 Pods:"
kubectl get pods -n ui-base ${CTX_OPT} 2>/dev/null
echo ""
echo "============================================"
