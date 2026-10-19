# AWS — 앞단 대응

먼저 `scripts/aws-inventory.sh` 로 지금 상태를 읽는다. 이 문서는 그 결과를 보고 무엇을 할지 고르는 데 쓴다.

## 입구별로 WAF 를 어디에 붙이나

| 입구 | WAF 범위 · 리전 | 메모 |
|---|---|---|
| ALB(인터넷에 열림) | `REGIONAL`, ALB 와 같은 리전 | 가장 흔하다. ALB 가 맨 앞이면 WAF 가 보는 IP 가 곧 실제 IP 다 |
| CloudFront | `CLOUDFRONT`, us-east-1 | CloudFront 뒤 ALB 에도 붙이면 두 번 낸다. 앞단 하나에 둔다 |
| API Gateway(REST) | `REGIONAL` | HTTP API(v2)에는 WAF 를 직접 못 붙인다 — 앞에 CloudFront 를 두거나 스로틀링으로 대신 |
| App Runner · Cognito · AppSync · Verified Access | `REGIONAL` | WAF 를 붙일 수 있다 |
| Amplify Hosting | Amplify 의 방화벽 설정 | 콘솔에서 확인 |
| Lambda 함수 URL(인증 NONE) | 직접 못 붙인다 | 앞에 CloudFront + WAF 를 둔다 |

CloudFront 가 앞에 있으면 속도 규칙의 IP 를 `X-Forwarded-For` 기준(`FORWARDED_IP`)으로 볼지 확인한다.

## 단계 — 늘 「세기만」 먼저

1. **웹 ACL 을 Count 모드로 붙인다** — `templates/aws/waf-alb-count.tf`.
   - IP 평판(`AWSManagedRulesAmazonIpReputationList`)
   - `/api/` 경로 속도 규칙(IP 당 5분)
   - Bot Control 일반 단계(`AWSManagedRulesBotControlRuleSet`, `COMMON`) — 이름을 밝히는 봇과 AI 범주를 라벨로 붙인다
   - 로그를 CloudWatch Logs(`aws-waf-logs-*`)로 보낸다. `authorization` · `cookie` 머리는 가린다.
2. **1~2주 본다** — `log-watch` 스킬, WAF 콘솔의 봇 · AI 트래픽 화면(추가 비용 없음). 실제 사용자가 걸리는 규칙이 있는지 본다.
3. **규칙별로 Block 으로 바꾼다** — 사람 결정. 예: AI 범주 봇 차단, 속도 규칙 차단. 한 번에 하나씩 바꾼다.
4. **스크립트 재호출(T5)이 남으면** 브라우저 확인을 더한다.
   - `Challenge` 동작은 브라우저가 풀어야 하는 확인이다. **HTML 이 아닌 요청(fetch · XHR)에는 화면을 띄울 수 없다.** API 에 걸려면 페이지에 WAF 애플리케이션 통합(JS SDK)을 넣어 토큰을 먼저 받게 해야 한다.
   - Bot Control 표적(`TARGETED`) 단계는 브라우저 지문 · 행동으로 자동화 도구를 찾는다. 비싸다(아래).

## 비용(2026-10 확인 — 바뀔 수 있다, https://aws.amazon.com/waf/pricing/)

| 항목 | 값 |
|---|---|
| 웹 ACL | 월 $5 |
| 규칙 | 하나당 월 $1 |
| 요청 | 100만 건당 $0.60 |
| Bot Control 일반(Common) | 월 $10, 월 1천만 요청 포함, 넘으면 100만 건당 $1 |
| Bot Control 표적(Targeted) | 월 $10, 월 100만 요청 포함, 넘으면 100만 건당 $10 |
| 로그 | CloudWatch Logs 적재 · 보관 요금 따로 |

월 1천만 요청 아래면 1단계는 대략 월 $20 안팎이다. Bot Control 은 범위 축소(scope-down)로 정적 파일을 빼면 요청 비용이 준다.

CloudFront 정액 요금제는 CDN · WAF · DDoS · Route 53 을 묶는다. 봇 관리는 Business(월 $200)부터이고 표적 봇 탐지는 정액제에 없다(https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html).

## 바꾸는 법 — 사람이 적용한다

- 이 플러그인은 AWS 를 바꾸지 않는다. Terraform(또는 그 저장소가 쓰는 IaC) 변경을 PR 로 내고, `plan` 결과를 사람에게 보여 준다. `apply` 는 사람이 한다.
- 콘솔로만 관리하는 계정이면, 무엇을 어떤 순서로 누를지 적은 체크리스트를 낸다.
- 그 팀에 변경 기록 규칙이 있으면(프로젝트 설정의 `change_policy`) 기록을 먼저 쓴다.

## 상시 감시(사람이 안 봐도 도는 것)

- CloudWatch 경보: `templates/aws/waf-alarms.tf` — 속도 규칙에 걸린 수가 기준을 넘으면 SNS 로 알린다.
- SNS → Slack 은 「Amazon Q Developer in chat applications」(옛 AWS Chatbot)로 잇는다.
- ALB 접근 로그(S3)는 Athena 로 본다. 실시간은 아니다.

## 공식 문서

- Bot Control: https://docs.aws.amazon.com/waf/latest/developerguide/waf-bot-control.html
- 속도 규칙: https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html
- Challenge · CAPTCHA: https://docs.aws.amazon.com/waf/latest/developerguide/waf-captcha-and-challenge.html
- 애플리케이션 통합(토큰): https://docs.aws.amazon.com/waf/latest/developerguide/waf-application-integration.html
- 로그: https://docs.aws.amazon.com/waf/latest/developerguide/logging.html
- AI 봇 다루기(블로그): https://aws.amazon.com/blogs/networking-and-content-delivery/how-to-manage-ai-bots-with-aws-waf-and-enhance-security/
