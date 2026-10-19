#!/usr/bin/env bash
# AWS 계정에서 봇 방어와 관련된 것을 읽기만 해서 JSON 으로 낸다 — describe · list · get 만 부르고 아무것도 바꾸지 않는다.
#
# 쓰는 법: aws-inventory.sh [--profile 이름] [--region ap-northeast-2] [--region us-west-2 ...]
#   리전을 안 주면 AWS_REGION → 프로필의 region 순서로 하나를 쓴다. CloudFront 와 그 WAF 는 늘 us-east-1 에서 본다.
# 보는 것: 계정(끝 4자리만) · 인터넷에 열린 ALB 와 붙은 WAF · ALB 접근 로그 · CloudFront 와 붙은 WAF ·
#          WAF 규칙(관리형 그룹 · Bot Control 단계 · 속도 규칙 · Count/Block) · WAF 로그 설정 · API Gateway 수 ·
#          WAF 로그 그룹 · ALB · WAF · CloudFront CloudWatch 경보 · Shield Advanced 구독.
# 권한: references/aws/iam-readonly-policy.json. 못 읽은 것은 errors 에 남기고 나머지는 계속 본다.
set -o pipefail

usage() { sed -n '2,11p' "$0" | sed -E 's/^# ?//'; }

profile=""
regions=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) profile="${2:-}"; shift 2 ;;
    --region) regions="$regions ${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "모르는 인자: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq 가 필요합니다"}'; exit 1; }
command -v aws >/dev/null 2>&1 || { echo '{"error":"aws CLI 가 필요합니다"}'; exit 1; }

awsc() { if [ -n "$profile" ]; then aws --profile "$profile" "$@"; else aws "$@"; fi; }

if [ -z "${regions// /}" ]; then
  regions="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(awsc configure get region 2>/dev/null)}}"
fi
[ -n "${regions// /}" ] || { echo '{"error":"리전을 알 수 없습니다. --region 을 주세요."}'; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/errors.tsv"

# run 이름 aws인자... → 성공하면 JSON, 실패하면 errors 에 한 줄 남기고 "__unreadable__"(못 읽음 — 「없음」과 다르다)
run() {
  local name="$1" out
  shift
  if out="$(awsc "$@" --output json 2>"$tmp/err")"; then
    printf '%s' "${out:-null}"
  else
    printf '%s\t%s\n' "$name" "$(head -c 300 "$tmp/err" | tr '\n\t' '  ')" >> "$tmp/errors.tsv"
    printf '"__unreadable__"'
  fi
}
# jqu 필터 → 못 읽은 값은 "unknown", 아니면 필터를 적용한다
jqu() { jq "if . == \"__unreadable__\" then \"unknown\" else ($1) end"; }

identity="$(run sts sts get-caller-identity | jqu '{account: ("****" + (.Account[-4:])), principal_type: (.Arn | split(":")[5] | split("/")[0])}')"
if [ "$identity" = '"unknown"' ]; then
  jq -n --rawfile e "$tmp/errors.tsv" '{error: "AWS 에 로그인되어 있지 않거나 권한이 없습니다. 사용자가 직접 로그인한 뒤 다시 돌린다(예: aws sso login --profile 이름).", detail: $e}'
  exit 1
fi

# WAF 웹 ACL 하나를 요약한다(get-web-acl 출력 → 짧은 JSON)
WEB_ACL_JQ='
  if . == null then null else .WebACL | {
    name: .Name,
    arn: .ARN,
    default_action: (.DefaultAction | keys[0] | ascii_downcase),
    capacity: .Capacity,
    token_domains: (.TokenDomains // []),
    rules: [ .Rules[] | {
      name: .Name,
      priority: .Priority,
      kind: (if .Statement.ManagedRuleGroupStatement then "managed"
             elif .Statement.RateBasedStatement then "rate"
             elif .Statement.RuleGroupReferenceStatement then "rule-group"
             else (.Statement | keys[0]) end),
      group: (.Statement.ManagedRuleGroupStatement.Name // null),
      bot_control_level: ([(.Statement.ManagedRuleGroupStatement.ManagedRuleGroupConfigs // [])[]
                           | .AWSManagedRulesBotControlRuleSet.InspectionLevel // empty] | first),
      rate_limit: (.Statement.RateBasedStatement.Limit // null),
      rate_window_sec: (.Statement.RateBasedStatement.EvaluationWindowSec // null),
      action: (if .OverrideAction then (if .OverrideAction.Count then "count" else "group-default" end)
               else (.Action | keys[0] | ascii_downcase) end),
      overridden_rules: ((.Statement.ManagedRuleGroupStatement.RuleActionOverrides // []) | length)
    } ]
  } end'

# acl_detail 범위 리전 이름 id → 규칙 요약 + 로그 설정
acl_detail() {
  local scope="$1" region="$2" name="$3" id="$4" acl arn logging
  acl="$(run "wafv2 get-web-acl $name" wafv2 get-web-acl --scope "$scope" --region "$region" --name "$name" --id "$id" \
    | jq --arg name "$name" "if . == \"__unreadable__\" then {name: \$name, unreadable: true, rules: []} else ($WEB_ACL_JQ) end")"
  arn="$(printf '%s' "$acl" | jq -r '.arn // empty')"
  logging='null'
  if [ -n "$arn" ]; then
    logging="$(awsc wafv2 get-logging-configuration --resource-arn "$arn" --region "$region" --output json 2>"$tmp/err" \
      | jq '{destinations: [.LoggingConfiguration.LogDestinationConfigs[] | split(":") | .[2] + ":" + (.[5:] | join(":"))],
             redacted_fields: (.LoggingConfiguration.RedactedFields // [] | length)}')"
    if [ -z "$logging" ]; then
      if grep -q WAFNonexistentItemException "$tmp/err"; then logging='"off"'; else
        printf '%s\t%s\n' "wafv2 get-logging-configuration $name" "$(head -c 300 "$tmp/err" | tr '\n\t' '  ')" >> "$tmp/errors.tsv"
        logging='"unknown"'
      fi
    fi
  fi
  printf '%s' "$acl" | jq --arg scope "$scope" --arg region "$region" --argjson logging "$logging" '. + {scope: $scope, region: $region, logging: $logging} | del(.arn)'
}

# ── 리전마다 ────────────────────────────────────────────────────────────────
: > "$tmp/regions.jsonl"
for region in $regions; do
  # 인터넷에 열린 ALB 와 그 WAF · 속성
  : > "$tmp/albs.jsonl"
  albs="$(run "elbv2 describe-load-balancers $region" elbv2 describe-load-balancers --region "$region" \
    | jqu '[(.LoadBalancers // [])[] | select(.Type == "application") | {arn: .LoadBalancerArn, name: .LoadBalancerName, scheme: .Scheme, dns: .DNSName}]' | jq -c .)"
  printf '%s' "$albs" | jq -c 'arrays | .[]' | while IFS= read -r lb; do
    arn="$(printf '%s' "$lb" | jq -r .arn)"
    waf="$(run "wafv2 get-web-acl-for-resource $region" wafv2 get-web-acl-for-resource --resource-arn "$arn" --region "$region" | jqu '.WebACL.Name // null')"
    attrs="$(run "elbv2 describe-load-balancer-attributes $region" elbv2 describe-load-balancer-attributes --load-balancer-arn "$arn" --region "$region" \
      | jqu '(.Attributes // []) | map({(.Key): .Value}) | add // {}
            | {access_logs: (.["access_logs.s3.enabled"] == "true"), drop_invalid_headers: (.["routing.http.drop_invalid_header_fields.enabled"] == "true")}')"
    printf '%s' "$lb" | jq -c --argjson waf "$waf" --argjson attrs "$attrs" '
      {name, scheme, dns, web_acl: $waf}
      + (if $attrs == "unknown" then {access_logs: "unknown", drop_invalid_headers: "unknown"} else $attrs end)' >> "$tmp/albs.jsonl"
  done

  # 이 리전의 웹 ACL(REGIONAL)
  : > "$tmp/acls.jsonl"
  listing="$(run "wafv2 list-web-acls REGIONAL $region" wafv2 list-web-acls --scope REGIONAL --region "$region")"
  acls_ok=true
  [ "$listing" = '"__unreadable__"' ] && acls_ok=false
  printf '%s' "$listing" | jq -r 'objects | (.WebACLs // [])[] | [.Name, .Id] | @tsv' | while IFS="$(printf '\t')" read -r name id; do
    acl_detail REGIONAL "$region" "$name" "$id" | jq -c . >> "$tmp/acls.jsonl"
  done

  apis="$(run "apigatewayv2 get-apis $region" apigatewayv2 get-apis --region "$region" | jqu '[(.Items // [])[] | {name: .Name, protocol: .ProtocolType}]')"
  rest="$(run "apigateway get-rest-apis $region" apigateway get-rest-apis --region "$region" | jqu '[(.items // [])[] | .name]')"
  waf_logs="$(run "logs describe-log-groups waf $region" logs describe-log-groups --log-group-name-prefix aws-waf-logs- --region "$region" \
    | jqu '[(.logGroups // [])[] | {name: .logGroupName, retention_days: .retentionInDays}]')"
  log_groups="$(run "logs describe-log-groups $region" logs describe-log-groups --region "$region" --max-items 200 \
    | jqu '[(.logGroups // [])[] | .logGroupName]')"
  alarms="$(run "cloudwatch describe-alarms $region" cloudwatch describe-alarms --region "$region" \
    | jqu '[(.MetricAlarms // [])[] | select(.Namespace == "AWS/WAFV2" or .Namespace == "AWS/ApplicationELB" or .Namespace == "AWS/CloudFront")
           | {name: .AlarmName, namespace: .Namespace, metric: .MetricName, state: .StateValue}]')"

  jq -n -c --arg region "$region" --argjson albs_raw "$albs" --argjson acls_ok "$acls_ok" \
    --slurpfile albs "$tmp/albs.jsonl" --slurpfile acls "$tmp/acls.jsonl" \
    --argjson apis "$apis" --argjson rest "$rest" --argjson waf_logs "$waf_logs" \
    --argjson log_groups "$log_groups" --argjson alarms "$alarms" '
    {region: $region,
     albs: (if $albs_raw == "unknown" then "unknown" else $albs end),
     web_acls: (if $acls_ok then $acls else "unknown" end),
     api_gateway: {http_or_ws: $apis, rest: $rest},
     waf_log_groups: $waf_logs, log_groups: $log_groups, alarms: $alarms}' >> "$tmp/regions.jsonl"
done

# ── 전역(us-east-1) — CloudFront 와 그 WAF, Shield ──────────────────────────
distributions="$(run "cloudfront list-distributions" cloudfront list-distributions \
  | jqu '[(.DistributionList.Items // [])[] | {id: .Id, domain: .DomainName, aliases: (.Aliases.Items // []), enabled: .Enabled,
          web_acl: (if (.WebACLId // "") == "" then null else ((.WebACLId | split("/") | .[-2]) // .WebACLId) end)}]')"
: > "$tmp/cf_acls.jsonl"
cf_listing="$(run "wafv2 list-web-acls CLOUDFRONT" wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1)"
cf_ok=true
[ "$cf_listing" = '"__unreadable__"' ] && cf_ok=false
printf '%s' "$cf_listing" | jq -r 'objects | (.WebACLs // [])[] | [.Name, .Id] | @tsv' | while IFS="$(printf '\t')" read -r name id; do
    acl_detail CLOUDFRONT us-east-1 "$name" "$id" | jq -c . >> "$tmp/cf_acls.jsonl"
  done
shield="$(run "shield get-subscription-state" shield get-subscription-state --region us-east-1 | jqu '.SubscriptionState // null')"

# ── 출력 + 바로 보이는 빈 곳 ─────────────────────────────────────────────────
jq -n --argjson identity "$identity" --slurpfile regions "$tmp/regions.jsonl" \
  --argjson distributions "$distributions" --slurpfile cf_acls "$tmp/cf_acls.jsonl" --argjson cf_ok "$cf_ok" \
  --argjson shield "$shield" --rawfile errors "$tmp/errors.tsv" '
  ([$regions[] | .web_acls | arrays[]] + $cf_acls | map(select(.unreadable | not))) as $all_acls
  | {
      identity: $identity,
      regions: $regions,
      cloudfront: {distributions: $distributions, web_acls: (if $cf_ok then $cf_acls else "unknown" end)},
      shield_advanced: $shield,
      gaps: (
        [ $regions[] | .region as $r | .albs | arrays[] | select(.scheme == "internet-facing" and .web_acl == null)
          | "ALB \(.name)(\($r)) 에 WAF 가 없다" ]
        + [ $regions[] | .region as $r | .albs | arrays[] | select(.scheme == "internet-facing" and .access_logs == false)
          | "ALB \(.name)(\($r)) 접근 로그가 꺼져 있다" ]
        + [ $distributions | arrays[] | select(.enabled and .web_acl == null) | "CloudFront \(.id) 에 WAF 가 없다" ]
        + [ $all_acls[] | select(.logging == "off") | "웹 ACL \(.name) 로그가 꺼져 있다" ]
        + [ $all_acls[] | select([.rules[] | select(.group == "AWSManagedRulesBotControlRuleSet")] | length == 0)
          | "웹 ACL \(.name) 에 Bot Control 이 없다" ]
        + [ $all_acls[] | select([.rules[] | select(.kind == "rate")] | length == 0) | "웹 ACL \(.name) 에 속도 규칙이 없다" ]
        + [ $all_acls[] | .name as $n | .rules[] | select(.action == "count") | "웹 ACL \($n) 의 \(.name) 은 아직 Count(세기만)다" ]
      ),
      unknown_note: "값이 \"unknown\" 인 곳은 권한이 없어 못 읽은 것이다 — 「없음」이 아니다. gaps 에 넣지 않았다. 무엇을 못 읽었는지는 errors 에 있다.",
      errors: ($errors | split("\n") | map(select(length > 0) | split("\t") | {call: .[0], error: .[1]}))
    }'
