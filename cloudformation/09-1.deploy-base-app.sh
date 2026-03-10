#!/bin/bash
set -eo pipefail

# Base Application (영어) 별도 배포
# bilingual-app과 병렬 운영 (별도 namespace + ALB + CloudFront)
# 사용법: ./09-1.deploy-base-app.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

if [ ! -f "${SHARED_DIR}/05.deploy-base-app.sh" ]; then
  echo "  ❌ ${SHARED_DIR}/05.deploy-base-app.sh 없음"
  exit 1
fi

exec "${SHARED_DIR}/05.deploy-base-app.sh" "$@"
