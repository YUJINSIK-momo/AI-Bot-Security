#!/usr/bin/env bash
# 저장소와 운영 주소를 읽기만 해서 호스팅 · 앞단(CDN·WAF) · 프레임워크 · 이미 있는 방어 · 위험 신호를 JSON 으로 낸다.
#
# 쓰는 법: detect-stack.sh [저장소 경로] [--url https://example.com]
#   - 저장소는 파일 이름과 내용만 본다(아무것도 실행하지 않는다).
#   - --url 을 주면 그 주소에 GET 두 번(https, http)과 DNS 조회만 한다.
# 필요한 것: bash, jq, curl. dig 가 없으면 DNS 는 건너뛴다.
set -o pipefail

usage() { sed -n '2,8p' "$0" | sed -E 's/^# ?//'; }

repo="."
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) repo="$1"; shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq 가 필요합니다"}'; exit 1; }
[ -d "$repo" ] || { jq -n --arg r "$repo" '{error: ("저장소 경로가 없습니다: " + $r)}'; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
TAB="$(printf '\t')"
signals="$tmp/signals.tsv" # 분류<TAB>id<TAB>출처<TAB>근거
: > "$signals"
add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(printf '%s' "$4" | tr '\t\n' '  ' | cut -c1-160)" >> "$signals"; }

# ── 1. 저장소 ────────────────────────────────────────────────────────────────
# git 저장소면 git 이 아는 파일만(무시 목록을 따른다), 아니면 흔한 산출물 폴더를 뺀다.
files="$tmp/files.txt"
if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo" ls-files --cached --others --exclude-standard > "$files"
else
  (cd "$repo" && find . -type f \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/.next/*' \
    -not -path '*/build/*' -not -path '*/vendor/*' -not -path '*/.venv/*' -not -path '*/.terraform/*' \
    | sed 's#^\./##') > "$files"
fi

# 이름이 $1(정규식)에 맞는 파일 가운데 내용이 $2(정규식)에 맞는 첫 파일
first_match() {
  local f
  while IFS= read -r f; do
    if grep -Eq "$2" "$repo/$f" 2>/dev/null; then printf '%s\n' "$f"; return 0; fi
  done < <(grep -E "$1" "$files")
  return 1
}
# rule 분류 id 이름정규식 내용정규식
rule() { local hit; hit="$(first_match "$3" "$4")" && add "$1" "$2" repo "$hit"; }
# file_rule 분류 id 이름정규식
file_rule() { local hit; hit="$(grep -E "$3" "$files" | head -n 1)"; [ -n "$hit" ] && add "$1" "$2" repo "$hit"; }

TF='\.tf$'
rule hosting aws-alb "$TF" 'resource "aws_(lb|alb)"'
rule edge aws-cloudfront "$TF" 'resource "aws_cloudfront_distribution"'
rule defense aws-waf "$TF" 'resource "aws_wafv2_web_acl"'
rule defense aws-waf-association "$TF" 'resource "aws_wafv2_web_acl_association"'
rule defense aws-waf-logging "$TF" 'resource "aws_wafv2_web_acl_logging_configuration"'
rule defense aws-shield "$TF" 'resource "aws_shield_protection"'
rule hosting aws-apigateway "$TF" 'resource "aws_(api_gateway_rest_api|apigatewayv2_api)"'
rule hosting aws-lambda-url "$TF" 'resource "aws_lambda_function_url"'
rule hosting aws-ecs "$TF" 'resource "aws_ecs_service"'
rule hosting aws-ec2 "$TF" 'resource "aws_(instance|autoscaling_group)"'
rule hosting aws-amplify "$TF" 'resource "aws_amplify_app"'
rule hosting aws-s3-website "$TF" 'resource "aws_s3_bucket_website_configuration"'
rule dns aws-route53 "$TF" 'resource "aws_route53_record"'
rule edge cloudflare "$TF" 'resource "cloudflare_'
rule hosting gcp "$TF" 'resource "google_(cloud_run|compute|app_engine)'
rule hosting azure "$TF" 'resource "azurerm_'

file_rule hosting vercel '(^|/)vercel\.json$|(^|/)\.vercel/project\.json$'
file_rule hosting netlify '(^|/)netlify\.toml$'
file_rule edge cloudflare-workers '(^|/)wrangler\.(toml|json|jsonc)$'
file_rule hosting firebase '(^|/)firebase\.json$'
file_rule hosting fly '(^|/)fly\.toml$'
file_rule hosting render '(^|/)render\.ya?ml$'
file_rule hosting railway '(^|/)railway\.(json|toml)$'
file_rule hosting aws-amplify '(^|/)amplify\.yml$'
file_rule hosting serverless-framework '(^|/)serverless\.ya?ml$'
file_rule hosting aws-cdk '(^|/)cdk\.json$'
file_rule hosting container '(^|/)Dockerfile(\.[A-Za-z0-9_-]+)?$'
rule hosting kubernetes '\.ya?ml$' '^kind:[[:space:]]*Ingress'
rule hosting aws-sam '\.ya?ml$' 'AWS::Serverless'
rule ci aws-deploy '^\.github/workflows/.*\.ya?ml$' 'aws-actions/configure-aws-credentials'

# package.json 의 의존성(여러 앱이면 모두 모은다)
deps="$tmp/deps.tsv"
: > "$deps"
while IFS= read -r f; do
  jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' "$repo/$f" 2>/dev/null \
    | awk -v f="$f" '{print $0 "\t" f}' >> "$deps"
done < <(grep -E '(^|/)package\.json$' "$files")
# dep_rule 분류 id 의존성정규식
dep_rule() { local hit; hit="$(grep -E "^($3)$TAB" "$deps" | head -n 1)"; [ -n "$hit" ] && add "$1" "$2" repo "${hit//$TAB/ in }"; }

dep_rule framework nextjs 'next'
dep_rule framework nestjs '@nestjs/core'
dep_rule framework express 'express'
dep_rule framework fastify 'fastify'
dep_rule framework koa 'koa'
dep_rule framework hono 'hono'
dep_rule framework nuxt 'nuxt'
dep_rule framework remix '@remix-run/node|@remix-run/react|@react-router/node'
dep_rule framework astro 'astro'
dep_rule framework sveltekit '@sveltejs/kit'
dep_rule framework angular '@angular/core'
dep_rule defense rate-limit-lib 'express-rate-limit|@nestjs/throttler|rate-limiter-flexible|@upstash/ratelimit|@fastify/rate-limit|hono-rate-limiter|koa-ratelimit'
dep_rule defense bot-lib 'botid|@arcjet/[a-z-]+'
dep_rule risk llm-sdk 'openai|@anthropic-ai/sdk|@google/generative-ai|@google/genai|ai|@ai-sdk/[a-z-]+|langchain|@langchain/[a-z-]+|@aws-sdk/client-bedrock-runtime|@mistralai/mistralai|cohere-ai|groq-sdk'

PY='(^|/)(requirements[^/]*\.txt|pyproject\.toml|Pipfile)$'
PYEND='([=<>~![:space:]"'"'"',;\[]|$)'
rule framework django "$PY" "^[[:space:]\"']*[Dd]jango$PYEND"
rule framework fastapi "$PY" "^[[:space:]\"']*fastapi$PYEND"
rule framework flask "$PY" "^[[:space:]\"']*[Ff]lask$PYEND"
rule defense rate-limit-lib "$PY" "^[[:space:]\"']*(slowapi|django-ratelimit|[Ff]lask-[Ll]imiter)$PYEND"
rule risk llm-sdk "$PY" "^[[:space:]\"']*(openai|anthropic|google-generativeai|google-genai|langchain|litellm)$PYEND"
rule framework rails '(^|/)Gemfile$' "gem ['\"]rails['\"]"
rule defense rate-limit-lib '(^|/)Gemfile$' "gem ['\"]rack-attack['\"]"
rule framework go-web '(^|/)go\.mod$' 'github\.com/(gin-gonic/gin|labstack/echo|gofiber/fiber)'
rule framework spring '(^|/)(pom\.xml|build\.gradle(\.kts)?)$' 'spring-boot'
rule framework laravel '(^|/)composer\.json$' '"laravel/framework"'

file_rule defense robots '(^|/)robots\.(txt|ts|tsx|js|jsx|mjs)$'
rule risk source-maps-on '(^|/)next\.config\.(js|mjs|cjs|ts)$' 'productionBrowserSourceMaps:[[:space:]]*true'
rule risk source-maps-on '(^|/)vite\.config\.(js|mjs|cjs|ts|mts)$' 'sourcemap:[[:space:]]*(true|["'"'"']inline["'"'"'])'

# 브라우저로 나가는 환경 변수 이름(값은 보지 않는다) — 키라면 도메인 제한이 있는지 따로 확인해야 한다.
public_env="$(grep -E '\.(ts|tsx|js|jsx|mjs|vue|svelte|astro)$|(^|/)\.env\.(example|sample)$' "$files" \
  | while IFS= read -r f; do grep -Eo '(NEXT_PUBLIC|VITE|REACT_APP|NUXT_PUBLIC|EXPO_PUBLIC)_[A-Z0-9_]+' "$repo/$f" 2>/dev/null; done \
  | sort -u | head -n 30 | paste -sd, -)"
[ -n "$public_env" ] && add risk public-env-names repo "$public_env"

# ── 2. 운영 주소 ─────────────────────────────────────────────────────────────
if [ -n "$url" ]; then
  case "$url" in http://*|https://*) ;; *) url="https://$url" ;; esac
  host="$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#:.*$##')"
  UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'
  headers="$tmp/headers.txt"
  {
    curl -sS -o /dev/null -D - --max-time 15 -A "$UA" "$url" 2>/dev/null
    curl -sS -o /dev/null -D - --max-time 15 -A "$UA" "http://$host/" 2>/dev/null
  } | tr -d '\r' | tr 'A-Z' 'a-z' > "$headers"
  if [ ! -s "$headers" ]; then
    add note live-unreachable live "$url 에 닿지 못했다"
  fi
  # head_rule 분류 id 헤더정규식(소문자)
  head_rule() { local hit; hit="$(grep -E "$3" "$headers" | head -n 1)"; [ -n "$hit" ] && add "$1" "$2" live "$hit"; }
  head_rule edge aws-cloudfront '^x-amz-cf-id:|^via:.*cloudfront'
  head_rule hosting aws-alb '^server: awselb'
  head_rule hosting aws-apigateway '^x-amz-apigw-id:'
  head_rule edge cloudflare '^cf-ray:|^server: cloudflare'
  head_rule hosting vercel '^x-vercel-id:|^server: vercel'
  head_rule hosting netlify '^x-nf-request-id:|^server: netlify'
  head_rule edge fastly '^x-fastly-request-id:|^x-served-by: cache-'
  head_rule edge akamai '^server: akamaighost|^x-akamai-'
  head_rule edge azure-front-door '^x-azure-ref:'
  head_rule hosting gcp '^server: google frontend|^via: 1\.1 google'
  head_rule hosting fly '^fly-request-id:|^server: fly'
  head_rule hosting render '^rndr-id:|^x-render-origin-server:'
  head_rule framework nextjs '^x-powered-by: next\.js|^x-nextjs-|^vary:.*(next-router|rsc)'
  head_rule framework express '^x-powered-by: express'

  if command -v dig >/dev/null 2>&1; then
    cname="$(dig +short CNAME "$host" 2>/dev/null | head -n 1)"
    if [ -n "$cname" ]; then
      case "$cname" in
        *cloudfront.net.) add edge aws-cloudfront dns "CNAME $cname" ;;
        *elb.amazonaws.com.) add hosting aws-alb dns "CNAME $cname" ;;
        *execute-api*) add hosting aws-apigateway dns "CNAME $cname" ;;
        *amplifyapp.com.) add hosting aws-amplify dns "CNAME $cname" ;;
        *vercel-dns.com.|*vercel.app.) add hosting vercel dns "CNAME $cname" ;;
        *netlify.app.|*netlifyglobalcdn.com.) add hosting netlify dns "CNAME $cname" ;;
        *pages.dev.) add hosting cloudflare-pages dns "CNAME $cname" ;;
        *azurefd.net.) add edge azure-front-door dns "CNAME $cname" ;;
        *fly.dev.) add hosting fly dns "CNAME $cname" ;;
        *onrender.com.) add hosting render dns "CNAME $cname" ;;
        *web.app.|*firebaseapp.com.) add hosting firebase dns "CNAME $cname" ;;
        *github.io.) add hosting github-pages dns "CNAME $cname" ;;
        *herokudns.com.) add hosting heroku dns "CNAME $cname" ;;
        *) add note cname dns "CNAME $cname" ;;
      esac
    fi
    # 위 단계로 올라가며 처음 답하는 NS
    zone="$host"
    ns=""
    while [ -n "$zone" ] && [ -z "$ns" ]; do
      ns="$(dig +short NS "$zone" 2>/dev/null | grep -Ei '\.$' | head -n 2 | paste -sd' ' -)"
      case "$zone" in *.*.*) zone="${zone#*.}" ;; *) zone="" ;; esac
    done
    case "$ns" in
      *awsdns*) add dns aws-route53 dns "NS $ns" ;;
      *cloudflare.com*) add dns cloudflare-dns dns "NS $ns" ;;
      *vercel-dns*) add dns vercel-dns dns "NS $ns" ;;
      "") ;;
      *) add dns other-dns dns "NS $ns" ;;
    esac
  else
    add note no-dig live "dig 가 없어 DNS 를 보지 않았다"
  fi

  if grep -q $'\tcloudflare-dns\t' "$signals" && ! grep -q $'^edge\tcloudflare\tlive' "$signals"; then
    add note cloudflare-dns-only live "DNS 는 Cloudflare 인데 cf-ray 가 없다 — 프록시(주황 구름)가 꺼져 있으면 Cloudflare 방어가 앞에 없다"
  fi
else
  add note no-url input "운영 주소를 주면(--url) 앞단(CDN·WAF)과 DNS 를 함께 본다"
fi

# ── 3. 출력 ─────────────────────────────────────────────────────────────────
jq -R -s --arg repo "$repo" --arg url "$url" '
  [split("\n")[] | select(length > 0) | split("\t") | {category: .[0], id: .[1], source: .[2], evidence: .[3]}] as $s
  | {
      repo: $repo,
      url: (if $url == "" then null else $url end),
      summary: (reduce $s[] as $x ({}; .[$x.category] += [$x.id]) | map_values(unique)),
      playbooks: (
        [ $s[] | select(.category == "hosting" or .category == "edge" or .category == "dns") | .id
          | if startswith("aws") then "references/hosting/aws.md"
            elif startswith("cloudflare") then "references/hosting/cloudflare.md"
            elif startswith("vercel") then "references/hosting/vercel.md"
            elif . == "netlify" then "references/hosting/netlify.md"
            elif . == "container" or . == "other-dns" then empty
            else "references/hosting/other.md" end ]
        + [ $s[] | select(.category == "framework") | .id
          | if . == "nextjs" then "references/frameworks/nextjs.md"
            elif . == "nestjs" then "references/frameworks/nestjs.md"
            elif . == "express" or . == "fastify" or . == "koa" or . == "hono" then "references/frameworks/node-http.md"
            elif . == "django" or . == "fastapi" or . == "flask" then "references/frameworks/python.md"
            else empty end ]
        | unique),
      signals: $s
    }' "$signals"
