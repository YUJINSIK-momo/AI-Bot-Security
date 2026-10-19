#!/usr/bin/env bash
# 로그 줄을 원문 없이 「종류별 수」로만 센다 — CloudWatch Logs filter-log-events(읽기)를 쓴다.
# Logs Insights(start-query)를 못 쓰거나 저장소 규칙이 막을 때 log-watch 가 대신 쓴다.
#
# 쓰는 법: log-count.sh --log-group 이름 --since 1h --pattern '?limited ?busy' [--profile 이름] [--region 리전] [--max 10000]
#   --pattern 은 CloudWatch 필터 패턴이다(예: '?limited ?busy', '"429"', '{ $.status = 429 }').
#   JSON 한 줄 로그면 msg · outcome(또는 message.msg · message.outcome)으로 묶고, 아니면 「non-json」 으로 센다.
#   원문 줄은 출력하지 않는다. 묶음 이름은 앞 80자까지만 낸다.
set -o pipefail

usage() { sed -n '2,9p' "$0" | sed -E 's/^# ?//'; }

group=""
since="1h"
pattern=""
profile=""
region=""
max=10000
while [ $# -gt 0 ]; do
  case "$1" in
    --log-group) group="${2:-}"; shift 2 ;;
    --since) since="${2:-1h}"; shift 2 ;;
    --pattern) pattern="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --region) region="${2:-}"; shift 2 ;;
    --max) max="${2:-10000}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "모르는 인자: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq 가 필요합니다"}'; exit 1; }
[ -n "$group" ] || { echo '{"error":"--log-group 이 필요합니다"}'; exit 2; }
case "$max" in ''|*[!0-9]*) max=10000 ;; esac

case "$since" in
  *m) secs=$(( ${since%m} * 60 )) ;;
  *h) secs=$(( ${since%h} * 3600 )) ;;
  *d) secs=$(( ${since%d} * 86400 )) ;;
  *) echo '{"error":"--since 는 15m · 2h · 1d 꼴입니다"}'; exit 2 ;;
esac
end_ms=$(( $(date +%s) * 1000 ))
start_ms=$(( end_ms - secs * 1000 ))

set -- logs filter-log-events --log-group-name "$group" --start-time "$start_ms" --end-time "$end_ms" --max-items "$max" --output json
[ -n "$pattern" ] && set -- "$@" --filter-pattern "$pattern"
[ -n "$region" ] && set -- "$@" --region "$region"
[ -n "$profile" ] && set -- --profile "$profile" "$@"

if ! raw="$(aws "$@" 2>&1)"; then
  jq -n --arg e "$(printf '%s' "$raw" | head -c 300)" '{error: "로그를 읽지 못했습니다", detail: $e}'
  exit 1
fi

printf '%s' "$raw" | jq --arg group "$group" --arg since "$since" --arg pattern "$pattern" --argjson max "$max" '
  [(.events // [])[] | .message | (try fromjson catch null) as $j
    | if ($j | type) != "object" then "non-json"
      else ([($j.msg // $j.message.msg // ($j.message | strings) // "-"), ($j.outcome // $j.message.outcome // "-")]
            | map(tostring | .[0:80]) | join(" / ")) end] as $kinds
  | {log_group: $group, since: $since, pattern: $pattern, matched: ($kinds | length),
     capped: (($kinds | length) >= $max),
     kinds: ($kinds | group_by(.) | map({kind: .[0], n: length}) | sort_by(-.n))}'
