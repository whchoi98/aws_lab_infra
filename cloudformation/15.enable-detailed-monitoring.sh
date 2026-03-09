#!/bin/bash
set -euo pipefail

# EC2 상세 모니터링 (Detailed Monitoring) 일괄 활성화
# 기본 모니터링: 5분 간격 → 상세 모니터링: 1분 간격
#
# 사용법: ./15.enable-detailed-monitoring.sh

REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  EC2 상세 모니터링 활성화"
echo "============================================"
echo ""
echo "  기본 → 상세: 5분 간격 → 1분 간격"
echo "  대상: 모든 running EC2 인스턴스"
echo ""

INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text \
  --region "${REGION}" 2>/dev/null)

ENABLED=0
ALREADY=0
TOTAL=0

for INST in ${INSTANCES}; do
  TOTAL=$((TOTAL+1))
  NAME=$(aws ec2 describe-instances --instance-ids ${INST} \
    --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value|[0]' \
    --output text --region "${REGION}" 2>/dev/null)

  CURRENT=$(aws ec2 describe-instances --instance-ids ${INST} \
    --query 'Reservations[0].Instances[0].Monitoring.State' --output text \
    --region "${REGION}" 2>/dev/null)

  if [ "${CURRENT}" = "enabled" ]; then
    echo "  ⏭  ${NAME} (${INST}): 이미 활성"
    ALREADY=$((ALREADY+1))
  else
    aws ec2 monitor-instances --instance-ids ${INST} \
      --region "${REGION}" > /dev/null 2>&1
    echo "  ✅ ${NAME} (${INST}): 활성화"
    ENABLED=$((ENABLED+1))
  fi
done

echo ""
echo "============================================"
echo "  결과: 총 ${TOTAL}대"
echo "    활성화: ${ENABLED}대"
echo "    이미 활성: ${ALREADY}대"
echo "============================================"
echo ""
echo "  상세 모니터링 메트릭 (1분 간격):"
echo "    CPUUtilization, DiskReadOps, DiskWriteOps"
echo "    DiskReadBytes, DiskWriteBytes"
echo "    NetworkIn, NetworkOut, NetworkPacketsIn"
echo "    NetworkPacketsOut, StatusCheckFailed"
echo "============================================"
