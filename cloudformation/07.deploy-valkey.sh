#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION=${AWS_REGION:-ap-northeast-2}

echo "============================================"
echo "  Valkey (ElastiCache) 클러스터 배포"
echo "============================================"

aws cloudformation deploy \
  --stack-name Valkey \
  --template-file "${SCRIPT_DIR}/templates/valkey-cluster-stack.yaml" \
  --region "${AWS_REGION}"

echo ""
echo "  ✅ Valkey 배포 완료!"
echo "  Endpoint:"
aws cloudformation describe-stacks --stack-name Valkey \
  --query 'Stacks[0].Outputs[?OutputKey==`ValkeyConfigurationEndpoint`].OutputValue' \
  --output text --region "${AWS_REGION}"
