#!/bin/bash
set -euo pipefail

# 앱 배포 스크립트 (CloudFormation 방식)
# 사용법: ./09.deploy-app.sh [base|bilingual]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

APP_TYPE=${1:-}

if [ -z "${APP_TYPE}" ]; then
  echo "============================================"
  echo "  앱 배포 선택"
  echo "============================================"
  echo ""
  echo "  1) base       - AWS Retail Store Sample (영어 전용)"
  echo "  2) bilingual   - Custom 쇼핑몰 (한국어/영어)"
  echo ""
  read -p "  선택 [2]: " CHOICE
  CHOICE=${CHOICE:-2}
  case "${CHOICE}" in
    1|base) APP_TYPE="base" ;;
    *) APP_TYPE="bilingual" ;;
  esac
fi

exec "${SHARED_DIR}/02.deploy-app.sh" "${APP_TYPE}"
