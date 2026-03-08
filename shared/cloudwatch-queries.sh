#!/bin/bash
set -euo pipefail

# CloudWatch Logs Insights 쿼리 모음
# Container Insights + bilingual-app 로그 분석용
#
# 사용법: ./cloudwatch-queries.sh [query-name] [profile] [minutes]
# 예시:
#   ./cloudwatch-queries.sh error-logs lab-cf 60
#   ./cloudwatch-queries.sh slow-requests lab-cf 30
#   ./cloudwatch-queries.sh pod-restarts lab-cf 1440
#   ./cloudwatch-queries.sh list

QUERY_NAME=${1:-list}
PROFILE=${2:-lab-cf}
MINUTES=${3:-60}
REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER="eksworkshop"

APP_LOG="/aws/containerinsights/${CLUSTER}/application"
PERF_LOG="/aws/containerinsights/${CLUSTER}/performance"
DATAPLANE_LOG="/aws/containerinsights/${CLUSTER}/dataplane"
HOST_LOG="/aws/containerinsights/${CLUSTER}/host"

START_TIME=$(date -d "${MINUTES} minutes ago" +%s 2>/dev/null || date -v-${MINUTES}M +%s)
END_TIME=$(date +%s)

run_query() {
  local LOG_GROUP="$1"
  local QUERY="$2"
  local DESC="$3"

  echo "━━━ ${DESC} ━━━"
  echo "  Log Group: ${LOG_GROUP}"
  echo "  Period: last ${MINUTES} minutes"
  echo ""

  QUERY_ID=$(aws logs start-query \
    --log-group-name "${LOG_GROUP}" \
    --start-time ${START_TIME} \
    --end-time ${END_TIME} \
    --query-string "${QUERY}" \
    --query 'queryId' --output text \
    --region ${REGION} --profile ${PROFILE} 2>/dev/null)

  if [ -z "$QUERY_ID" ]; then
    echo "  ❌ 쿼리 실행 실패"
    return
  fi

  sleep 5
  aws logs get-query-results --query-id "${QUERY_ID}" \
    --query 'results[*]' --output json \
    --region ${REGION} --profile ${PROFILE} 2>/dev/null | \
    python3 -c "
import sys, json
results = json.load(sys.stdin)
if not results:
    print('  (결과 없음)')
else:
    for row in results[:20]:
        line = ' | '.join([f['value'] for f in row if f['field'] != '@ptr'])
        print(f'  {line}')
    if len(results) > 20:
        print(f'  ... 외 {len(results)-20}건')
" 2>/dev/null
  echo ""
}

case "${QUERY_NAME}" in
  list)
    echo "============================================"
    echo "  CloudWatch Logs Insights 쿼리 목록"
    echo "============================================"
    echo ""
    echo "  앱 로그 분석:"
    echo "    error-logs        에러 로그 (500 응답, 예외)"
    echo "    slow-requests     느린 요청 (> 1초)"
    echo "    request-count     서비스별 요청 수"
    echo "    status-codes      HTTP 상태 코드 분포"
    echo "    backend-latency   백엔드 API 호출 지연 시간"
    echo "    cart-actions      장바구니 활동 (담기/삭제)"
    echo "    order-actions     주문 활동"
    echo ""
    echo "  Container Insights:"
    echo "    pod-restarts      Pod 재시작 횟수"
    echo "    pod-cpu           Pod CPU 사용률 Top 10"
    echo "    pod-memory        Pod 메모리 사용률 Top 10"
    echo "    node-cpu          노드 CPU 사용률"
    echo "    node-network      노드 네트워크 트래픽"
    echo "    container-errors  컨테이너 에러 로그"
    echo ""
    echo "  인프라:"
    echo "    nfw-alerts        Network Firewall 알림"
    echo "    nfw-flow          Network Firewall 플로우"
    echo ""
    echo "  사용법: $0 [query-name] [profile] [minutes]"
    echo "  예시:   $0 error-logs lab-cf 60"
    ;;

  # === 앱 로그 분석 ===
  error-logs)
    run_query "${APP_LOG}" \
      "fields @timestamp, kubernetes.container_name, log | filter log like /error|Error|ERROR|500/ | sort @timestamp desc | limit 20" \
      "에러 로그 (500 응답, 예외)"
    ;;

  slow-requests)
    run_query "${APP_LOG}" \
      "fields @timestamp, kubernetes.container_name, log | filter log like /responseTime/ | parse log '\"responseTime\":*,' as rt | filter rt > 1000 | sort rt desc | limit 20" \
      "느린 요청 (> 1초)"
    ;;

  request-count)
    run_query "${APP_LOG}" \
      "fields kubernetes.container_name | filter log like /GET|POST|PUT|DELETE/ | stats count(*) as cnt by kubernetes.container_name | sort cnt desc" \
      "서비스별 요청 수"
    ;;

  status-codes)
    run_query "${APP_LOG}" \
      "fields log | filter kubernetes.container_name = 'ui' | parse log '\"statusCode\":*,' as status | stats count(*) as cnt by status | sort cnt desc" \
      "HTTP 상태 코드 분포"
    ;;

  backend-latency)
    run_query "${APP_LOG}" \
      "fields log | filter kubernetes.container_name = 'ui' and log like /backend_call/ | parse log '\"duration\":*,' as duration | parse log '\"backend\":\"*\"' as backend | stats avg(duration) as avg_ms, max(duration) as max_ms, count(*) as cnt by backend | sort avg_ms desc" \
      "백엔드 API 호출 지연 시간"
    ;;

  cart-actions)
    run_query "${APP_LOG}" \
      "fields @timestamp, log | filter kubernetes.container_name = 'ui' and log like /cart_action/ | sort @timestamp desc | limit 20" \
      "장바구니 활동 (담기/삭제)"
    ;;

  order-actions)
    run_query "${APP_LOG}" \
      "fields @timestamp, log | filter kubernetes.container_name = 'ui' and log like /order_action|place_order/ | sort @timestamp desc | limit 20" \
      "주문 활동"
    ;;

  # === Container Insights ===
  pod-restarts)
    run_query "${PERF_LOG}" \
      "fields kubernetes.pod_name, kubernetes.namespace_name | filter Type = 'Pod' | stats max(pod_number_of_container_restarts) as restarts by kubernetes.pod_name, kubernetes.namespace_name | filter restarts > 0 | sort restarts desc | limit 20" \
      "Pod 재시작 횟수"
    ;;

  pod-cpu)
    run_query "${PERF_LOG}" \
      "fields kubernetes.pod_name, kubernetes.namespace_name | filter Type = 'Pod' | stats avg(pod_cpu_utilization) as cpu_pct by kubernetes.pod_name, kubernetes.namespace_name | sort cpu_pct desc | limit 10" \
      "Pod CPU 사용률 Top 10"
    ;;

  pod-memory)
    run_query "${PERF_LOG}" \
      "fields kubernetes.pod_name, kubernetes.namespace_name | filter Type = 'Pod' | stats avg(pod_memory_utilization) as mem_pct by kubernetes.pod_name, kubernetes.namespace_name | sort mem_pct desc | limit 10" \
      "Pod 메모리 사용률 Top 10"
    ;;

  node-cpu)
    run_query "${PERF_LOG}" \
      "fields NodeName | filter Type = 'Node' | stats avg(node_cpu_utilization) as cpu_pct, avg(node_memory_utilization) as mem_pct by NodeName" \
      "노드 CPU/메모리 사용률"
    ;;

  node-network)
    run_query "${PERF_LOG}" \
      "fields NodeName | filter Type = 'Node' | stats avg(node_network_total_bytes) as net_bytes by NodeName | sort net_bytes desc" \
      "노드 네트워크 트래픽"
    ;;

  container-errors)
    run_query "${APP_LOG}" \
      "fields @timestamp, kubernetes.container_name, kubernetes.namespace_name, log | filter log like /error|Error|ERROR|panic|FATAL|exception/ | sort @timestamp desc | limit 20" \
      "컨테이너 에러 로그"
    ;;

  # === 인프라 ===
  nfw-alerts)
    run_query "/aws/network-firewall/DMZVPC/alert" \
      "fields @timestamp, event.alert.signature, event.src_ip, event.dest_ip | sort @timestamp desc | limit 20" \
      "Network Firewall 알림"
    ;;

  nfw-flow)
    run_query "/aws/network-firewall/DMZVPC/flow" \
      "fields @timestamp, event.src_ip, event.dest_ip, event.dest_port, event.proto | stats count(*) as cnt by event.dest_port, event.proto | sort cnt desc | limit 20" \
      "Network Firewall 플로우 (포트별)"
    ;;

  *)
    echo "❌ 알 수 없는 쿼리: ${QUERY_NAME}"
    echo "  ./cloudwatch-queries.sh list 로 목록을 확인하세요."
    exit 1
    ;;
esac
