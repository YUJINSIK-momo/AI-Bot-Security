#!/usr/bin/env bash
# CloudWatch Logs Insights 쿼리 하나를 돌리고 결과를 JSON 배열로 낸다 — 읽기만 한다.
#
# 쓰는 법: insights-query.sh --log-group 이름 [--log-group 이름2] --since 15m|2h|1d
#                            (--query-file 파일 | --query '쿼리') [--profile 이름] [--region 리전] [--limit 100]
#   쿼리 예시는 references/aws/insights-queries.md 에 있다.
#   결과는 {query_id, status, window, rows:[{필드: 값}], statistics} 다. 60초 안에 안 끝나면 쿼리를 멈춘다.
set -o pipefail

usage() { sed -n '2,8p' "$0" | sed -E 's/^# ?//'; }

profile=""
region=""
since="15m"
query=""
limit=100
groups_file="$(mktemp)"
trap 'rm -f "$groups_file"' EXIT
while [ $# -gt 0 ]; do
  case "$1" in
    --log-group) printf '%s\n' "${2:-}" >> "$groups_file"; shift 2 ;;
    --since) since="${2:-15m}"; shift 2 ;;
    --query) query="${2:-}"; shift 2 ;;
    --query-file) query="$(cat "${2:-/dev/null}")"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --region) region="${2:-}"; shift 2 ;;
    --limit) limit="${2:-100}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "모르는 인자: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq 가 필요합니다"}'; exit 1; }
[ -s "$groups_file" ] || { echo '{"error":"--log-group 이 필요합니다"}'; exit 2; }
[ -n "$query" ] || { echo '{"error":"--query 나 --query-file 이 필요합니다"}'; exit 2; }

awsc() {
  set -- "$@" --output json
  [ -n "$region" ] && set -- "$@" --region "$region"
  if [ -n "$profile" ]; then aws --profile "$profile" "$@"; else aws "$@"; fi
}

case "$since" in
  *m) secs=$(( ${since%m} * 60 )) ;;
  *h) secs=$(( ${since%h} * 3600 )) ;;
  *d) secs=$(( ${since%d} * 86400 )) ;;
  *) echo '{"error":"--since 는 15m · 2h · 1d 꼴입니다"}'; exit 2 ;;
esac
end="$(date +%s)"
start=$(( end - secs ))

# --log-group-names 뒤에 이름들을 하나씩 넘긴다(공백이 든 이름도 안전하게)
set --
while IFS= read -r g; do [ -n "$g" ] && set -- "$@" "$g"; done < "$groups_file"

if ! started="$(awsc logs start-query --log-group-names "$@" --start-time "$start" --end-time "$end" --limit "$limit" --query-string "$query" 2>&1)"; then
  jq -n --arg e "$started" '{error: "쿼리를 시작하지 못했습니다", detail: $e}'
  exit 1
fi
qid="$(printf '%s' "$started" | jq -r .queryId)"

waited=0
while :; do
  result="$(awsc logs get-query-results --query-id "$qid" 2>&1)" || { jq -n --arg e "$result" '{error: "결과를 읽지 못했습니다", detail: $e}'; exit 1; }
  status="$(printf '%s' "$result" | jq -r .status)"
  case "$status" in
    Complete|Failed|Cancelled|Timeout|Unknown) break ;;
  esac
  if [ "$waited" -ge 60 ]; then
    awsc logs stop-query --query-id "$qid" >/dev/null 2>&1
    status="StoppedAfter60s"
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

printf '%s' "$result" | jq --arg qid "$qid" --arg status "$status" --argjson start "$start" --argjson end "$end" '
  {query_id: $qid, status: $status,
   window: {start: ($start | todate), end: ($end | todate)},
   rows: [(.results // [])[] | map(select(.field != "@ptr") | {(.field): .value}) | add],
   statistics: .statistics}'
