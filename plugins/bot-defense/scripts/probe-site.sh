#!/usr/bin/env bash
# 운영 사이트를 공격자 시점으로 가볍게 본다 — 읽기만 하고, 요청은 30번 안팎이다(--burst 를 주면 그만큼 더).
#
# 쓰는 법: probe-site.sh --url https://example.com --authorized [--burst /api/some/path [--count 30]]
#   --authorized  내 사이트이거나 점검 권한이 있다는 확인. 없으면 아무 요청도 보내지 않는다.
#   --burst PATH  (선택) 그 경로에 GET 을 차례로 보내 429·403 이 몇 번째에 나오는지 본다. --count 는 최대 60(기본 30).
# 보는 것: robots.txt 의 AI 봇 규칙 · AI 봇 이름으로 보낸 요청이 막히는지 · JS 번들의 소스맵 ·
#          JS 번들에 보이는 API 경로(REA 같은 분석 도구가 바로 찾는 것) · 번들에 실린 키의 종류(값은 가린다).
set -o pipefail

usage() { sed -n '2,10p' "$0" | sed -E 's/^# ?//'; }

url=""
authorized=0
burst=""
count=30
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url="${2:-}"; shift 2 ;;
    --authorized) authorized=1; shift ;;
    --burst) burst="${2:-}"; shift 2 ;;
    --count) count="${2:-30}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "모르는 인자: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq 가 필요합니다"}'; exit 1; }
[ -n "$url" ] || { echo '{"error":"--url 이 필요합니다"}'; exit 2; }
if [ "$authorized" -ne 1 ]; then
  echo '{"error":"--authorized 가 없습니다. 내 사이트이거나 점검 권한이 있는 사이트에만 씁니다."}'
  exit 2
fi
case "$count" in ''|*[!0-9]*) count=30 ;; esac
[ "$count" -gt 60 ] && count=60

case "$url" in http://*|https://*) ;; *) url="https://$url" ;; esac
origin="$(printf '%s' "$url" | sed -E 's#^([a-zA-Z]+://[^/]+).*#\1#')"
host="$(printf '%s' "$origin" | sed -E 's#^[a-zA-Z]+://##; s#:.*$##')"
here="$(cd "$(dirname "$0")" && pwd)"
agents_tsv="$here/../data/ai-user-agents.tsv"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
BROWSER='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'
status_of() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 -A "$1" "$2" 2>/dev/null || echo 000; }

# ── 1. robots.txt ──────────────────────────────────────────────────────────
robots_status="$(curl -s -o "$tmp/robots.txt" -w '%{http_code}' --max-time 15 -A "$BROWSER" "$origin/robots.txt" 2>/dev/null || echo 000)"
[ "$robots_status" = "200" ] || : > "$tmp/robots.txt"
# 묶음마다: 봇이름<TAB>전체금지(1/0)<TAB>Disallow 목록
awk '
  { line = $0; sub(/#.*/, "", line); gsub(/\r/, "", line); low = tolower(line) }
  low ~ /^[ \t]*user-agent[ \t]*:/ {
    v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
    if (!collecting) { n++; dis[n] = 0; rules[n] = ""; collecting = 1 }
    agents[n] = agents[n] " " tolower(v); next
  }
  low ~ /^[ \t]*(dis)?allow[ \t]*:/ {
    collecting = 0
    v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
    if (n > 0 && low ~ /^[ \t]*disallow/ && v != "") {
      if (v == "/" || v == "/*") dis[n] = 1
      rules[n] = rules[n] " " v
    }
    next
  }
  line ~ /[^ \t]/ { collecting = 0 }
  END {
    for (i = 1; i <= n; i++) {
      c = split(agents[i], a, " ")
      for (j = 1; j <= c; j++) if (a[j] != "") printf "%s\t%d\t%s\n", a[j], dis[i], rules[i]
    }
  }' "$tmp/robots.txt" > "$tmp/groups.tsv"

robots_json="$(
  grep -v '^#' "$agents_tsv" | grep -v '^[[:space:]]*$' | while IFS="$(printf '\t')" read -r group token _vendor _desc; do
    low="$(printf '%s' "$token" | tr 'A-Z' 'a-z')"
    own="$(awk -F'\t' -v t="$low" '$1 == t' "$tmp/groups.tsv" | head -n 1)"
    star="$(awk -F'\t' '$1 == "*"' "$tmp/groups.tsv" | head -n 1)"
    if [ -n "$own" ]; then
      [ "$(printf '%s' "$own" | cut -f2)" = "1" ] && state="blocked" || state="listed-not-blocked"
    elif [ -n "$star" ] && [ "$(printf '%s' "$star" | cut -f2)" = "1" ]; then
      state="blocked-by-wildcard"
    else
      state="not-blocked"
    fi
    printf '%s\t%s\t%s\n' "$group" "$token" "$state"
  done | jq -R -s --arg status "$robots_status" --rawfile groups "$tmp/groups.tsv" '
    [split("\n")[] | select(length > 0) | split("\t") | {group: .[0], token: .[1], state: .[2]}] as $t
    | {
        status: ($status | tonumber? // $status),
        wildcard_disallows: ($groups | split("\n") | map(split("\t")) | map(select(.[0] == "*")) | (.[0][2] // "") | split(" ") | map(select(length > 0))),
        ai_bots: {
          blocked: [$t[] | select(.state | startswith("blocked")) | .token],
          not_blocked: [$t[] | select(.state == "not-blocked" or .state == "listed-not-blocked") | {group, token}]
        }
      }'
)"

# ── 2. 봇 이름으로 보낸 요청이 앞단에서 막히나 ─────────────────────────────
ua_json="$(
  {
    printf 'browser\t%s\n' "$(status_of "$BROWSER" "$url")"
    printf 'GPTBot\t%s\n' "$(status_of 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)' "$url")"
    printf 'ClaudeBot\t%s\n' "$(status_of 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ClaudeBot/1.0; +claudebot@anthropic.com)' "$url")"
    printf 'curl\t%s\n' "$(status_of 'curl/8.7.1' "$url")"
  } | jq -R -s '
    [split("\n")[] | select(length > 0) | split("\t") | {(.[0]): (.[1] | tonumber? // .[1])}] | add
    | . + {note: "이름만 흉내 낸 요청이다. 「검증된 봇」만 막는 규칙(IP·역방향 DNS 확인)에는 걸리지 않을 수 있다."}'
)"

# ── 3. 첫 화면의 JS 번들 ─────────────────────────────────────────────────────
curl -s -o "$tmp/index.html" --max-time 20 -A "$BROWSER" "$url" 2>/dev/null || : > "$tmp/index.html"
# src 를 모아 같은 출처 주소로 바꾼다(다른 출처는 따로 센다)
grep -Eo '<script[^>]+src=["'"'"'][^"'"'"']+' "$tmp/index.html" | sed -E 's/.*src=["'"'"']//' | sort -u > "$tmp/srcs.txt"
: > "$tmp/scripts.txt"
third_party=0
while IFS= read -r s; do
  case "$s" in
    //*) abs="https:$s" ;;
    http://*|https://*) abs="$s" ;;
    /*) abs="$origin$s" ;;
    *) abs="$origin/$s" ;;
  esac
  case "$abs" in
    "$origin"/*) echo "$abs" >> "$tmp/scripts.txt" ;;
    *) third_party=$((third_party + 1)) ;;
  esac
done < "$tmp/srcs.txt"

: > "$tmp/maps.tsv"
: > "$tmp/all.js"
i=0
while IFS= read -r js; do
  i=$((i + 1))
  [ "$i" -gt 10 ] && break
  curl -s -o "$tmp/one.js" --max-time 20 --max-filesize 8000000 -A "$BROWSER" "$js" 2>/dev/null || continue
  cat "$tmp/one.js" >> "$tmp/all.js"
  printf '\n' >> "$tmp/all.js"
  ref="$(grep -Eo 'sourceMappingURL=[^[:space:]*]+' "$tmp/one.js" | tail -n 1 | sed 's/^sourceMappingURL=//')"
  case "$ref" in
    "") map="$js.map" ;;
    data:*) map="inline" ;;
    http://*|https://*) map="$ref" ;;
    /*) map="$origin$ref" ;;
    *) map="${js%/*}/$ref" ;;
  esac
  if [ "$map" = "inline" ]; then
    code="inline"
  else
    code="$(curl -s -I -o /dev/null -w '%{http_code}' --max-time 15 -A "$BROWSER" "$map" 2>/dev/null || echo 000)"
  fi
  printf '%s\t%s\t%s\n' "${js#"$origin"}" "$( [ -n "$ref" ] && echo yes || echo no )" "$code" >> "$tmp/maps.tsv"
done < "$tmp/scripts.txt"

maps_json="$(jq -R -s '[split("\n")[] | select(length > 0) | split("\t") | {script: .[0], has_sourcemap_comment: (.[1] == "yes"), map_status: (.[2] | tonumber? // .[2])}]
  | {checked: length, exposed: [.[] | select(.map_status == 200 or .map_status == "inline") | .script], scripts: .}' "$tmp/maps.tsv")"

# 번들에 보이는 API 경로 — 화면이 부르는 서버 주소 목록(공격자가 가장 먼저 얻는 것)
grep -Eo '["'"'"'`](/api/[A-Za-z0-9_./:-]*|/graphql[A-Za-z0-9_/-]*|/trpc/[A-Za-z0-9_./-]*)' "$tmp/all.js" 2>/dev/null \
  | cut -c2- | sed -E 's#/+$##' | sort -u | head -n 80 > "$tmp/endpoints.txt"
endpoints_json="$(jq -R -s '[split("\n")[] | select(length > 0)] | {count: length, paths: .}' "$tmp/endpoints.txt")"

# 번들에 실린 키 — 종류와 앞 4자만 남긴다. secret 처럼 보이는 것은 높음.
: > "$tmp/keys.tsv"
key_rule() { # 종류 위험 정규식 [값 앞에서 자를 접두 | - 면 있는지만]
  local hits first sample
  hits="$(grep -Eo "$3" "$tmp/all.js" 2>/dev/null | sort -u)"
  [ -n "$hits" ] || return 0
  first="$(printf '%s\n' "$hits" | head -n 1)"
  if [ "${4:-}" = "-" ]; then
    sample="-"
  else
    [ -n "${4:-}" ] && first="${first#*"$4"}"
    sample="$(printf '%s' "$first" | cut -c1-4)…"
  fi
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(printf '%s\n' "$hits" | wc -l | tr -d ' ')" "$sample" >> "$tmp/keys.tsv"
}
key_rule kakao-maps-js-key check-domain-restriction 'dapi\.kakao\.com/v2/maps/sdk\.js' -
key_rule google-api-key check-referrer-restriction 'AIza[0-9A-Za-z_-]{35}'
key_rule naver-maps-client-id check-domain-restriction 'oapi\.map\.naver\.com/openapi/v3/maps\.js' -
key_rule google-maps-js check-referrer-restriction 'maps\.googleapis\.com/maps/api/js' -
key_rule mapbox-public-token check-url-restriction 'pk\.eyJ[0-9A-Za-z_.-]{20,}'
key_rule stripe-publishable public-by-design 'pk_live_[0-9A-Za-z]{10,}'
key_rule sentry-dsn public-by-design 'https://[0-9a-f]{32}@[a-z0-9.]*sentry\.io'
key_rule supabase check-row-level-security '[a-z0-9]{20}\.supabase\.co'
key_rule stripe-secret HIGH-secret-in-bundle 'sk_live_[0-9A-Za-z]{10,}'
key_rule openai-secret HIGH-secret-in-bundle 'sk-(proj-)?[A-Za-z0-9_-]{32,}'
key_rule anthropic-secret HIGH-secret-in-bundle 'sk-ant-[A-Za-z0-9_-]{20,}'
key_rule aws-access-key-id HIGH-secret-in-bundle 'A(KIA|SIA)[0-9A-Z]{16}'
keys_json="$(jq -R -s '[split("\n")[] | select(length > 0) | split("\t") | {kind: .[0], action: .[1], distinct: (.[2] | tonumber), sample: .[3]}]' "$tmp/keys.tsv")"

# ── 4. (선택) 짧은 연속 요청 ─────────────────────────────────────────────────
burst_json='null'
if [ -n "$burst" ]; then
  case "$burst" in /*) ;; *) burst="/$burst" ;; esac
  : > "$tmp/burst.txt"
  n=0
  while [ "$n" -lt "$count" ]; do
    n=$((n + 1))
    status_of "$BROWSER" "$origin$burst" >> "$tmp/burst.txt"
    echo >> "$tmp/burst.txt"
  done
  burst_json="$(jq -R -s --arg path "$burst" '
    [split("\n")[] | select(length > 0) | tonumber? // .] as $c
    | {path: $path, sent: ($c | length),
       statuses: ($c | group_by(.) | map({key: (.[0] | tostring), value: length}) | from_entries),
       first_limited_at: ([$c | to_entries[] | select(.value == 429 or .value == 403 or .value == 503) | .key + 1] | first),
       note: "앱 안에서 세는 상한은 서버 대수만큼 나뉘어 결과가 흔들릴 수 있다."}' "$tmp/burst.txt")"
fi

jq -n --arg url "$url" --arg host "$host" --argjson robots "$robots_json" --argjson ua "$ua_json" \
  --argjson maps "$maps_json" --argjson endpoints "$endpoints_json" --argjson keys "$keys_json" \
  --argjson burst "$burst_json" --argjson third "$third_party" '
  {url: $url, host: $host, robots: $robots, bot_user_agent_test: $ua,
   bundle: {third_party_scripts: $third, source_maps: $maps, api_paths_visible: $endpoints, keys: $keys},
   burst: $burst,
   limits: ["첫 화면에서 받은 JS 만 본다(나중에 받는 조각은 빠진다).", "요청 수가 적어 속도 제한·봇 탐지의 실제 효과를 증명하지는 않는다."]}'
