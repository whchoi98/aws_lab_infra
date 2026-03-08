#!/bin/bash
set -euo pipefail

# EKS ALB에 CloudFront 보안 보호를 설정합니다.
# CloudFront → ALB (Prefix List + X-Lab-Secret Custom Header)
#
# 사용법: ./deploy-cloudfront-protection.sh [kube-context] [aws-profile]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX=${1:-}
PROFILE=${2:-}
REGION=${AWS_REGION:-ap-northeast-2}
STACK_NAME="lab-shop-cloudfront"

echo "============================================"
echo "  CloudFront → ALB 보안 설정"
echo "============================================"
echo ""

# Profile/Context 확인
PROFILE_OPT=""
[ -n "${PROFILE}" ] && PROFILE_OPT="--profile ${PROFILE}"
CTX_OPT=""
[ -n "${CTX}" ] && CTX_OPT="--context ${CTX}"

# 1. ALB 정보 추출
echo "▶ [1/4] ALB 정보 추출"
ALB_DNS=$(kubectl get ingress -n ui ${CTX_OPT} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -z "${ALB_DNS}" ]; then
  echo "  ❌ ALB를 찾을 수 없습니다. 먼저 앱을 배포하세요."
  exit 1
fi
echo "  ALB DNS: ${ALB_DNS}"

# ALB ARN에서 SG 추출
ALB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='${ALB_DNS}'].LoadBalancerArn" \
  --output text --region ${REGION} ${PROFILE_OPT} 2>/dev/null)
ALB_SG=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='${ALB_DNS}'].SecurityGroups[0]" \
  --output text --region ${REGION} ${PROFILE_OPT} 2>/dev/null)
echo "  ALB SG: ${ALB_SG}"

# 2. CloudFront Prefix List
echo ""
echo "▶ [2/4] CloudFront Prefix List"
CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text --region ${REGION} ${PROFILE_OPT} 2>/dev/null)
echo "  Prefix List: ${CF_PREFIX_LIST_ID}"

# 3. 기존 ALB SG에서 0.0.0.0/0 규칙 제거 + CloudFront Prefix List만 허용
echo ""
echo "▶ [3/4] ALB SG 보안 강화"

# 기존 0.0.0.0/0 인바운드 제거
aws ec2 revoke-security-group-ingress --group-id ${ALB_SG} \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
  --region ${REGION} ${PROFILE_OPT} 2>/dev/null && echo "  ✅ 0.0.0.0/0 규칙 제거" || echo "  ⏭  이미 제거됨"

# CloudFront Prefix List 허용
aws ec2 authorize-security-group-ingress --group-id ${ALB_SG} \
  --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"PrefixListIds\":[{\"PrefixListId\":\"${CF_PREFIX_LIST_ID}\",\"Description\":\"HTTP from CloudFront only\"}]}]" \
  --region ${REGION} ${PROFILE_OPT} 2>/dev/null && echo "  ✅ CloudFront Prefix List 허용" || echo "  ⏭  이미 설정됨"

# 4. CloudFront 배포
echo ""
echo "▶ [4/4] CloudFront 배포"
aws cloudformation deploy \
  --stack-name ${STACK_NAME} \
  --template-file "${SCRIPT_DIR}/cloudfront-alb-protection.yaml" \
  --parameter-overrides \
    ALBDnsName="${ALB_DNS}" \
    ALBSecurityGroupId="${ALB_SG}" \
    CloudFrontPrefixListId="${CF_PREFIX_LIST_ID}" \
  --region ${REGION} ${PROFILE_OPT} 2>&1

# 결과 출력
echo ""
echo "============================================"
echo "  ✅ CloudFront 보안 설정 완료!"
echo "============================================"

CF_URL=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text --region ${REGION} ${PROFILE_OPT} 2>/dev/null)

echo ""
echo "  🌐 Shop URL: ${CF_URL}"
echo "  🔒 보안:"
echo "     - CloudFront (HTTPS) → ALB (HTTP:80)"
echo "     - ALB SG: CloudFront Prefix List만 허용"
echo "     - Custom Header: X-Lab-Secret"
echo "     - 직접 ALB 접근: 차단됨"
echo ""
echo "  ⚠️  CloudFront 배포 완료까지 5-10분 소요될 수 있습니다."
echo "============================================"
