#!/bin/bash
set -euo pipefail

# Lambda 함수 일괄 생성 스크립트
# 사용법: ./create-lambda-functions.sh [함수수] [접두사]

COUNT=${1:-20}
PREFIX=${2:-lab-func}
REGION=${AWS_DEFAULT_REGION:-ap-northeast-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME="lab-lambda-basic-role"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "============================================"
echo "Lambda 함수 일괄 생성"
echo "============================================"
echo "개수:   ${COUNT}"
echo "접두사: ${PREFIX}-"
echo "리전:   ${REGION}"
echo "============================================"
echo ""

# 1. IAM Role 생성 (없으면)
echo "▶ [1/3] IAM Role 확인"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "  ⏭  ${ROLE_NAME} 이미 존재"
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  echo "  ✅ ${ROLE_NAME} 생성 완료"
  echo "  ⏳ IAM Role 전파 대기 (10초)..."
  sleep 10
fi

# 2. Lambda 코드 패키징
echo ""
echo "▶ [2/3] Lambda 코드 패키징"
TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/index.py" <<'PYEOF'
import json, os, datetime
def handler(event, context):
    return {
        "statusCode": 200,
        "body": json.dumps({
            "function": os.environ.get("AWS_LAMBDA_FUNCTION_NAME"),
            "message": "Hello from lab function!",
            "timestamp": datetime.datetime.now().isoformat()
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

RUNTIMES=("python3.12" "python3.13" "nodejs22.x" "nodejs20.x")

for i in $(seq -w 1 "$COUNT"); do
  FUNC_NAME="${PREFIX}-${i}"
  RUNTIME=${RUNTIMES[$(( (10#$i - 1) % ${#RUNTIMES[@]} ))]}

  if aws lambda get-function --function-name "$FUNC_NAME" &>/dev/null; then
    echo "  ⏭  ${FUNC_NAME} (이미 존재)"
    SKIP=$((SKIP+1))
  elif aws lambda create-function \
    --function-name "$FUNC_NAME" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler index.handler \
    --zip-file "fileb://${TMPDIR}/function.zip" \
    --timeout 10 \
    --memory-size 128 \
    --description "Lab test function ${i} (${RUNTIME})" \
    >/dev/null 2>&1; then
    echo "  ✅ ${FUNC_NAME} (${RUNTIME})"
    SUCCESS=$((SUCCESS+1))
  else
    echo "  ❌ ${FUNC_NAME}"
    FAIL=$((FAIL+1))
  fi
done

rm -rf "$TMPDIR"

echo ""
echo "============================================"
echo "결과: 생성 ${SUCCESS} / 스킵 ${SKIP} / 실패 ${FAIL}"
echo "============================================"
