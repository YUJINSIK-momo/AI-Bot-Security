#!/usr/bin/env bash
# 저장소 점검 — 플러그인 검증 · 셸 린트 · JSON · Terraform 형식 · 스크립트 시험(네트워크 · AWS 없이).
# 쓰는 법: tools/check.sh   (저장소 루트에서)
set -o pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$root/plugins/bot-defense"
scripts="$plugin/scripts"
fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

echo "1. 플러그인 · 마켓플레이스 검증"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$root" --strict >/dev/null 2>&1 && ok "marketplace" || bad "marketplace (claude plugin validate . --strict)"
  claude plugin validate "$plugin" --strict >/dev/null 2>&1 && ok "plugin" || bad "plugin (claude plugin validate plugins/bot-defense --strict)"
else
  echo "  skip claude CLI 없음"
fi

echo "2. 셸 린트"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$scripts"/*.sh "$root"/tools/*.sh && ok "shellcheck" || bad "shellcheck"
else
  echo "  skip shellcheck 없음"
fi

echo "3. JSON"
while IFS= read -r f; do
  jq empty "$f" 2>/dev/null && ok "${f#"$root"/}" || bad "${f#"$root"/}"
done < <(find "$root" -name '*.json' -not -path '*/node_modules/*' -not -path '*/.git/*')

echo "4. Terraform 형식"
if command -v terraform >/dev/null 2>&1; then
  terraform fmt -check -recursive "$plugin/templates" >/dev/null && ok "terraform fmt" || bad "terraform fmt"
else
  echo "  skip terraform 없음"
fi

echo "5. 스크립트 시험"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 5-1. detect-stack: 가짜 저장소
fx="$tmp/repo"
mkdir -p "$fx/infra" "$fx/web/app" "$fx/api"
printf 'resource "aws_lb" "this" {}\nresource "aws_cloudfront_distribution" "cdn" {}\n' > "$fx/infra/main.tf"
printf '{"dependencies":{"next":"16.0.0","openai":"5.0.0"}}' > "$fx/web/package.json"
printf '{"dependencies":{"@nestjs/core":"11.0.0","@nestjs/throttler":"6.0.0"}}' > "$fx/api/package.json"
printf 'export const k = process.env.NEXT_PUBLIC_MAP_KEY;\n' > "$fx/web/app/page.tsx"
printf 'export default {}\n' > "$fx/web/app/robots.ts"
printf 'module.exports = { productionBrowserSourceMaps: true }\n' > "$fx/web/next.config.js"
out="$("$scripts/detect-stack.sh" "$fx")"
for want in 'hosting:aws-alb' 'edge:aws-cloudfront' 'framework:nextjs' 'framework:nestjs' 'defense:rate-limit-lib' 'defense:robots' 'risk:llm-sdk' 'risk:source-maps-on' 'risk:public-env-names'; do
  cat="${want%%:*}"; id="${want#*:}"
  printf '%s' "$out" | jq -e --arg c "$cat" --arg i "$id" '.summary[$c] | index($i) != null' >/dev/null && ok "detect $want" || bad "detect $want"
done
printf '%s' "$out" | jq -e '.playbooks | index("references/hosting/aws.md") != null' >/dev/null && ok "detect playbook aws" || bad "detect playbook aws"
for p in $(printf '%s' "$out" | jq -r '.playbooks[]'); do
  [ -f "$plugin/$p" ] && ok "playbook 파일 $p" || bad "playbook 파일 없음 $p"
done

# 5-2. guard 훅
guard() {
  local out
  out="$(jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | "$scripts/guard-cloud-mutation.sh")"
  if [ -z "$out" ]; then echo none; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
expect() { local got; got="$(guard "$2")"; [ "$got" = "$1" ] && ok "guard $1: $2" || bad "guard $1 (got $got): $2"; }
expect ask 'aws --profile p --region r wafv2 update-web-acl --name x'
expect ask 'cd infra && terraform -chdir=. apply -auto-approve'
expect ask 'aws s3 cp a s3://b/'
expect ask 'kubectl apply -f x.yaml'
expect none 'aws wafv2 list-web-acls --scope REGIONAL'
expect none 'aws logs start-query --log-group-names g --query-string "fields @message"'
expect none 'terraform plan'
expect none 'git commit -m "aws wafv2 update-web-acl 문서"'
expect none 'aws wafv2 update-web-acl --help'
expect ask 'aws wafv2 update-web-acl --name help-desk --scope REGIONAL'

# 5-3. aws-inventory · insights-query: 가짜 aws
mkdir -p "$tmp/bin"
cat > "$tmp/bin/aws" <<'FAKE'
#!/usr/bin/env bash
# 시험용 가짜 aws — 받은 인자로 정해 둔 JSON 을 낸다.
args="$*"
if [ -n "${FAKE_DENY:-}" ] && printf '%s' "$args" | grep -Eq "$FAKE_DENY"; then
  echo "An error occurred (AccessDeniedException) when calling the operation" >&2
  exit 254
fi
case "$args" in
  *"sts get-caller-identity"*) echo '{"Account":"123456789012","Arn":"arn:aws:sts::123456789012:assumed-role/ReadOnly/me"}' ;;
  *"elbv2 describe-load-balancers"*) echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:alb/1","LoadBalancerName":"web","Scheme":"internet-facing","DNSName":"web.elb","Type":"application"}]}' ;;
  *"wafv2 get-web-acl-for-resource"*) echo '{}' ;;
  *"elbv2 describe-load-balancer-attributes"*) echo '{"Attributes":[{"Key":"access_logs.s3.enabled","Value":"false"}]}' ;;
  *"wafv2 list-web-acls --scope REGIONAL"*) echo '{"WebACLs":[{"Name":"acl1","Id":"id1"}]}' ;;
  *"wafv2 get-web-acl "*) echo '{"WebACL":{"Name":"acl1","ARN":"arn:acl1","DefaultAction":{"Allow":{}},"Capacity":10,"Rules":[{"Name":"r1","Priority":1,"OverrideAction":{"Count":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesAmazonIpReputationList"}}}]}}' ;;
  *"wafv2 get-logging-configuration"*) echo "An error occurred (WAFNonexistentItemException)" >&2; exit 254 ;;
  *"apigatewayv2 get-apis"*) echo '{"Items":[]}' ;;
  *"apigateway get-rest-apis"*) echo '{"items":[]}' ;;
  *"logs describe-log-groups --log-group-name-prefix"*) echo '{"logGroups":[]}' ;;
  *"logs describe-log-groups"*) echo '{"logGroups":[{"logGroupName":"/ecs/api"}]}' ;;
  *"cloudwatch describe-alarms"*) echo '{"MetricAlarms":[]}' ;;
  *"cloudfront list-distributions"*) echo '{"DistributionList":{"Items":[]}}' ;;
  *"wafv2 list-web-acls --scope CLOUDFRONT"*) echo '{"WebACLs":[]}' ;;
  *"shield get-subscription-state"*) echo '{"SubscriptionState":"INACTIVE"}' ;;
  *"logs start-query"*) echo '{"queryId":"q1"}' ;;
  *"logs filter-log-events"*) echo '{"events":[{"message":"{\"level\":\"info\",\"message\":{\"msg\":\"chat-ai\",\"outcome\":\"limited\"}}"},{"message":"{\"msg\":\"pdf\",\"outcome\":\"busy\"}"},{"message":"{\"msg\":\"pdf\",\"outcome\":\"busy\"}"},{"message":"plain text"}]}' ;;
  *"logs get-query-results"*) echo '{"status":"Complete","results":[[{"field":"action","value":"COUNT"},{"field":"requests","value":"7"},{"field":"@ptr","value":"x"}]],"statistics":{"recordsMatched":7}}' ;;
  *) echo "{}" ;;
esac
FAKE
chmod +x "$tmp/bin/aws"
inv="$(PATH="$tmp/bin:$PATH" "$scripts/aws-inventory.sh" --region ap-northeast-2)"
printf '%s' "$inv" | jq -e '.identity.account == "****9012"' >/dev/null && ok "inventory 계정 가림" || bad "inventory 계정 가림"
printf '%s' "$inv" | jq -e '[.gaps[] | select(test("WAF 가 없다"))] | length == 1' >/dev/null && ok "inventory ALB WAF 빈 곳" || bad "inventory ALB WAF 빈 곳"
printf '%s' "$inv" | jq -e '[.gaps[] | select(test("Bot Control 이 없다"))] | length == 1' >/dev/null && ok "inventory Bot Control 빈 곳" || bad "inventory Bot Control 빈 곳"
printf '%s' "$inv" | jq -e '.regions[0].web_acls[0].logging == "off"' >/dev/null && ok "inventory 로그 꺼짐" || bad "inventory 로그 꺼짐"
deny="$(PATH="$tmp/bin:$PATH" FAKE_DENY='get-web-acl-for-resource|describe-load-balancer-attributes|list-web-acls' "$scripts/aws-inventory.sh" --region ap-northeast-2)"
printf '%s' "$deny" | jq -e '.regions[0].albs[0].web_acl == "unknown" and .regions[0].albs[0].access_logs == "unknown" and .regions[0].web_acls == "unknown"' >/dev/null && ok "inventory 권한 없음은 unknown" || bad "inventory 권한 없음은 unknown"
printf '%s' "$deny" | jq -e '(.gaps | length) == 0 and (.errors | length) >= 3' >/dev/null && ok "inventory 권한 없음을 빈 곳으로 적지 않음" || bad "inventory 권한 없음을 빈 곳으로 적지 않음"
lc="$(PATH="$tmp/bin:$PATH" "$scripts/log-count.sh" --log-group g --since 1h --pattern '?limited ?busy')"
printf '%s' "$lc" | jq -e '.matched == 4 and (.kinds[0] == {kind: "pdf / busy", n: 2}) and ([.kinds[].kind] | index("non-json") != null) and (tostring | test("plain text") | not)' >/dev/null && ok "log-count 종류별 수 · 원문 없음" || bad "log-count 종류별 수 · 원문 없음"
q="$(PATH="$tmp/bin:$PATH" "$scripts/insights-query.sh" --log-group g --since 15m --query 'stats count(*)')"
printf '%s' "$q" | jq -e '.status == "Complete" and .rows[0].requests == "7" and (.rows[0] | has("@ptr") | not)' >/dev/null && ok "insights 결과 모양" || bad "insights 결과 모양"

# 5-4. probe-site 는 확인 없이 아무것도 보내지 않는다
probe_out="$("$scripts/probe-site.sh" --url https://example.invalid)"
printf '%s' "$probe_out" | jq -e '.error' >/dev/null && ok "probe --authorized 없으면 멈춤" || bad "probe --authorized"

echo
[ "$fail" -eq 0 ] && echo "모두 통과" || { echo "실패가 있다"; exit 1; }
