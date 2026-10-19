#!/usr/bin/env bash
# PreToolUse(Bash) 훅 — 클라우드 · DNS · 배포를 바꾸는 명령이면 사람에게 묻게 한다. 읽는 명령은 그대로 둔다.
#
# 들어오는 것: 표준 입력의 훅 JSON(.tool_input.command). 내는 것: 바꾸는 명령이면 permissionDecision "ask" JSON, 아니면 아무것도.
# 막지는 않는다(묻기만). jq 가 없으면 아무것도 하지 않는다.
set -o pipefail

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# 한 줄로 펴고, aws 전역 옵션(값이 있는 것 · 없는 것)을 지워 「aws 서비스 동작」만 남긴다.
flat="$(printf '%s' "$cmd" | tr '\n\\' '  ' | tr -s ' ' \
  | sed -E 's/--(profile|region|output|endpoint-url|color|ca-bundle|cli-read-timeout|cli-connect-timeout|cli-binary-format)([= ][^ ]+)//g; s/--(no-cli-pager|debug|no-verify-ssl|no-paginate|no-sign-request)( |$)/ /g' \
  | tr -s ' ')"
# git · gh 명령의 따옴표 안(커밋 메시지 · PR 본문)은 명령이 아니다.
case "$flat" in
  git\ *|gh\ *) flat="$(printf '%s' "$flat" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")" ;;
esac

hits=""
note() { hits="${hits:+$hits, }$1"; }

# aws: 동작 이름이 바꾸는 쪽이면(읽기 쿼리 몇 가지는 뺀다)
aws_pairs="$(printf '%s' "$flat" | grep -Eo '(^|[^A-Za-z0-9_./-])aws [a-z0-9-]+ [a-z0-9-]+' | sed -E 's/^[^a]*aws /aws /')"
while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  svc="$(printf '%s' "$pair" | cut -d' ' -f2)"
  op="$(printf '%s' "$pair" | cut -d' ' -f3)"
  case "$svc $op" in
    "logs start-query"|"logs stop-query"|"logs start-live-tail"|"athena start-query-execution"|"athena stop-query-execution") continue ;;
  esac
  # 도움말(aws 서비스 동작 help · --help)은 아무것도 바꾸지 않는다.
  if printf '%s' "$flat" | grep -Eq "$pair( [^;&|]*)? (help|--help)( |;|&|\||$)"; then continue; fi
  if [ "$svc" = "s3" ]; then
    case "$op" in cp|mv|rm|sync|mb|rb) note "$pair" ;; esac
    continue
  fi
  if printf '%s' "$op" | grep -Eq '^(create|put|delete|update|modify|associate|disassociate|attach|detach|tag|untag|register|deregister|set|enable|disable|terminate|run|reboot|restore|revoke|authorize|import|cancel|reset|replace|accept|reject|send|invoke|execute|start|stop|copy|add|remove|apply|publish|purge|rotate|change|allocate|release|assign|unassign|batch-write|batch-delete|deploy|rollback|promote|retry|resume|suspend|upload|link|unlink|subscribe|unsubscribe)(-|$)'; then
    note "$pair"
  fi
done <<EOF
$aws_pairs
EOF

# 그 밖의 도구 — 상태 · 리소스 · 배포를 바꾸는 하위 명령
other="$(printf '%s' "$flat" | grep -Eo \
  -e '(terraform|tofu)( -chdir=[^ ]+)? (apply|destroy|import|taint|untaint|force-unlock|state (rm|mv|push|replace-provider))' \
  -e 'cdk (deploy|destroy|bootstrap)' \
  -e 'sam (deploy|delete|sync)' \
  -e 'pulumi (up|destroy|refresh|import|cancel)' \
  -e '(serverless|sls) (deploy|remove)' \
  -e 'wrangler (deploy|publish|delete|secret|kv|r2|d1|pages deploy|versions deploy)' \
  -e 'vercel( [^ ]+)* (--prod|deploy|env (add|rm)|domains|dns|alias|promote|rollback|remove|rm)' \
  -e 'netlify (deploy|env:set|env:unset|sites:delete|api)' \
  -e 'gcloud( [^ ]+)* (create|delete|update|deploy|patch|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding)' \
  -e 'az( [^ ]+)* (create|delete|update|set)' \
  -e 'kubectl (apply|delete|patch|replace|scale|rollout|edit|create|set|annotate|label|drain|cordon)' \
  -e 'helm (install|upgrade|uninstall|rollback)' \
  -e '(fly|flyctl) (deploy|secrets|scale|destroy|apps destroy)' \
  | sort -u | paste -sd, -)"
[ -n "$other" ] && note "$other"

[ -n "$hits" ] || exit 0

jq -n --arg hits "$hits" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("클라우드 · 배포를 바꾸는 명령입니다: " + $hits + ". 바꾸기 전에 팀의 변경 기록과 사람 확인이 필요합니다(bot-defense).")
  }
}'
exit 0
