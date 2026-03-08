#!/bin/bash
set -euo pipefail

# Lambda 함수 일괄 생성 스크립트 (Graviton ARM64)
# 사용법: ./13.create-lambda-functions.sh [함수수] [접두사]
#
# 설정:
#   - Architecture: arm64 (Graviton)
#   - Runtime: python3.13 / python3.12 / nodejs22.x / nodejs20.x (순환)
#   - 메모리: 256MB
#   - 타임아웃: 30초
#   - X-Ray 추적: Active
#   - CloudWatch Logs: 30일 보존
#   - 태그: Name, Environment, Project, ManagedBy

COUNT=${1:-20}
PREFIX=${2:-lab-func}
REGION=${AWS_REGION:-ap-northeast-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME="lab-lambda-execution-role"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "============================================"
echo "  Lambda 함수 일괄 생성 (Graviton ARM64)"
echo "============================================"
echo ""
echo "  개수:       ${COUNT}"
echo "  접두사:     ${PREFIX}-"
echo "  리전:       ${REGION}"
echo "  아키텍처:   arm64 (Graviton)"
echo "  런타임:     python3.13/3.12, nodejs22.x/20.x (순환)"
echo "  메모리:     256MB"
echo "  타임아웃:   30초"
echo "  X-Ray:      Active"
echo ""
echo "============================================"
echo ""

# 1. IAM Role
echo "▶ [1/3] IAM Role 확인"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "  ✅ ${ROLE_NAME} 이미 존재"
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }' > /dev/null
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
  echo "  ✅ ${ROLE_NAME} 생성 완료"
  echo "  ⏳ IAM Role 전파 대기 (10초)..."
  sleep 10
fi

# 2. Lambda 코드 패키징
echo ""
echo "▶ [2/3] Lambda 코드 패키징"
TMPDIR=$(mktemp -d)

# Python 핸들러
cat > "${TMPDIR}/index.py" <<'PYEOF'
import json
import os
import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    func_name = os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "unknown")
    logger.info(json.dumps({
        "action": "invocation",
        "function": func_name,
        "event_keys": list(event.keys()) if isinstance(event, dict) else str(type(event)),
        "request_id": context.aws_request_id,
    }))

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "function": func_name,
            "runtime": os.environ.get("AWS_EXECUTION_ENV", "unknown"),
            "region": os.environ.get("AWS_REGION", "unknown"),
            "memory": os.environ.get("AWS_LAMBDA_FUNCTION_MEMORY_SIZE", "unknown"),
            "message": "Hello from LAB function!",
            "timestamp": datetime.datetime.now().isoformat(),
            "request_id": context.aws_request_id,
        })
    }
PYEOF
(cd "$TMPDIR" && zip -q function.zip index.py)
echo "  ✅ 패키징 완료"

# 3. Lambda 함수 생성
echo ""
echo "▶ [3/3] Lambda 함수 생성"
SUCCESS=0
SKIP=0
FAIL=0

RUNTIMES=("python3.13" "python3.12" "nodejs22.x" "nodejs20.x")

for i in $(seq -w 1 "$COUNT"); do
  FUNC_NAME="${PREFIX}-${i}"
  RUNTIME=${RUNTIMES[$(( (10#$i - 1) % ${#RUNTIMES[@]} ))]}

  if aws lambda get-function --function-name "$FUNC_NAME" --region "$REGION" &>/dev/null; then
    echo "  ⏭  ${FUNC_NAME} (이미 존재)"
    SKIP=$((SKIP+1))
    continue
  fi

  if aws lambda create-function \
    --function-name "$FUNC_NAME" \
    --runtime "$RUNTIME" \
    --architectures arm64 \
    --role "$ROLE_ARN" \
    --handler index.handler \
    --zip-file "fileb://${TMPDIR}/function.zip" \
    --timeout 30 \
    --memory-size 256 \
    --description "Lab function ${i} (${RUNTIME}, arm64)" \
    --tracing-config Mode=Active \
    --tags "Name=${FUNC_NAME},Environment=lab,Project=aws-lab-infra,ManagedBy=shell" \
    --region "$REGION" > /dev/null 2>&1; then

    # CloudWatch Logs 보존 기간 설정
    aws logs put-retention-policy \
      --log-group-name "/aws/lambda/${FUNC_NAME}" \
      --retention-in-days 30 \
      --region "$REGION" 2>/dev/null || true

    echo "  ✅ ${FUNC_NAME} (${RUNTIME}, arm64)"
    SUCCESS=$((SUCCESS+1))
  else
    echo "  ❌ ${FUNC_NAME}"
    FAIL=$((FAIL+1))
  fi
done

rm -rf "$TMPDIR"

echo ""
echo "============================================"
echo "  결과: 생성 ${SUCCESS} / 스킵 ${SKIP} / 실패 ${FAIL}"
echo "============================================"
echo ""
echo "  설정 (모든 함수):"
echo "    🏗️  아키텍처: arm64 (Graviton)"
echo "    🔄 런타임: python3.13/3.12, nodejs22.x/20.x"
echo "    💾 메모리: 256MB | 타임아웃: 30초"
echo "    📡 X-Ray: Active"
echo "    📋 Logs: 30일 보존"
echo "============================================"
