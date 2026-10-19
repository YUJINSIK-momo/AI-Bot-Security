# CloudWatch Logs Insights 쿼리

`scripts/insights-query.sh --log-group <그룹> --since 15m --query '<쿼리>'` 로 돌린다. WAF 로그 그룹은 `aws-waf-logs-` 로 시작한다.

보고서에는 IP 원문을 쓰지 않는다. 같은 IP 인지만 가르면 되므로 앞 두 마디만 남기거나(`203.0.x.x`) 해시 앞부분을 쓴다.

## WAF 로그

### W1. 한눈에 — 동작 · 규칙별 수

```
stats count(*) as requests by action, terminatingRuleId
| sort requests desc
```

### W2. `/api/` 를 가장 많이 부른 IP 와 인자 종류 수(열거 의심)

```
filter httpRequest.uri like /^\/api\//
| stats count(*) as requests, count_distinct(httpRequest.args) as distinct_args by httpRequest.clientIp
| sort requests desc
| limit 20
```

`distinct_args` 가 크면 같은 경로에 인자만 바꿔 훑는 것(동 코드 · ID 순회)이다.

### W3. 한 경로를 인자만 바꿔 훑는 IP

```
filter httpRequest.uri like /^\/api\//
| stats count_distinct(httpRequest.args) as distinct_args, count(*) as requests by httpRequest.clientIp, httpRequest.uri
| filter distinct_args > 50
| sort distinct_args desc
| limit 20
```

### W4. AI 봇 이름(User-Agent)

```
parse @message /"name":"[Uu]ser-[Aa]gent","value":"(?<ua>[^"]*)"/
| filter ua like /(?i)(gptbot|claudebot|ccbot|bytespider|perplexity|chatgpt-user|claude-user|oai-searchbot|meta-external|amazonbot|applebot|diffbot|cohere)/
| stats count(*) as requests by ua, action
| sort requests desc
| limit 30
```

### W5. Bot Control 범주(라벨)

```
filter @message like /awswaf:managed:aws:bot-control:bot:category:/
| parse @message /awswaf:managed:aws:bot-control:bot:category:(?<category>[a-z_]+)/
| stats count(*) as requests by category, action
| sort requests desc
```

`ai` · `http_library` · `scraping_framework` 범주가 크면 막을 후보다. `bot:verified` 라벨로 검증된 봇인지 가른다.

### W6. Count 규칙에 걸린 요청(막기 전 미리 보기)

```
filter @message like /"nonTerminatingMatchingRules":\[\{/
| parse @message /"nonTerminatingMatchingRules":\[\{"ruleId":"(?<countedRule>[^"]+)"/
| stats count(*) as matches by countedRule
| sort matches desc
```

여러 규칙에 걸리면 첫 규칙만 센다. 규칙별 정확한 수는 CloudWatch 지표(아래)로 본다.

## 앱 로그(형식에 맞게 고친다)

### A1. 429 · 403 이 5분마다 몇 번

```
filter status = 429 or statusCode = 429 or status = 403 or statusCode = 403
| stats count(*) as limited by bin(5m)
```

### A2. 상한에 걸렸다는 로그 줄

```
filter @message like /limited|rate.?limit|quota/
| stats count(*) as lines by bin(15m)
```

앱이 JSON 한 줄 로그를 쓰면 필드 이름(예: `msg`, `outcome`, `limit`)으로 바꿔 쓴다. 필드는 `fields @message | limit 5` 로 먼저 본다.

## 지표(로그가 꺼져 있어도 된다)

```
aws cloudwatch get-metric-statistics --namespace AWS/WAFV2 --metric-name CountedRequests \
  --dimensions Name=WebACL,Value=<웹 ACL 이름> Name=Region,Value=<리전> Name=Rule,Value=<규칙 지표 이름> \
  --start-time <ISO 시각> --end-time <ISO 시각> --period 300 --statistics Sum
```

`Rule` 값은 규칙의 `visibility_config.metric_name` 이다. `BlockedRequests` · `AllowedRequests` 도 같은 방식으로 본다.

## 실시간이 아닌 것

- ALB 접근 로그는 S3 에 몇 분 단위로 쌓인다. Athena 로 본다.
- WAF 로그도 CloudWatch 에 들어오기까지 몇 분 걸릴 수 있다.
