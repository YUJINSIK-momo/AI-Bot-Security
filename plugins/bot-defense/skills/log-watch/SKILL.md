---
name: log-watch
description: WAF · 앱 로그(CloudWatch Logs Insights)를 읽기 전용으로 조회해 지금 봇 트래픽을 요약한다 — AI 봇 이름, Bot Control 범주, /api 를 많이 부른 IP, 같은 경로를 인자만 바꿔 훑는 열거 패턴, 상한(429) 수, Count 규칙에 걸린 수. 반복 실행(/loop)이나 경보를 받았을 때 쓴다. "봇 트래픽 확인", "로그 봐줘", "크롤링 들어오나", "실시간 감시" 같은 요청에 쓴다.
argument-hint: "[기간 예: 15m · 1h · 1d]"
---

# 로그 보기

## 실시간에 대해 먼저

- **늘 도는 감시는 클라우드 경보가 맡는다.** WAF 지표 → CloudWatch 경보 → SNS → Slack(`${CLAUDE_PLUGIN_ROOT}/templates/aws/waf-alarms.tf`). 사람이 안 봐도 돈다.
- **이 스킬은 주기적 요약과 대응 판단을 맡는다.** 세션이 열려 있는 동안 Claude Code 의 `/loop` 로 반복할 수 있다(예: `/loop 15m /bot-defense:log-watch 15m`). 세션이 닫히면 멈춘다.
- 로그는 들어오기까지 몇 분 늦을 수 있다.

## 1. 무엇을 볼지

- 로그 그룹: `.bot-defense.json` 의 `logs.waf` · `logs.app` → `aws-bot-defense` 결과의 `waf_log_groups` · `log_groups` → 묻는다.
- 기간: 인자(기본 15m). 비교를 위해 같은 길이의 바로 앞 기간도 본다.
- 프로필 · 리전: `aws-bot-defense` 의 0단계와 같다. 로그인은 사용자가 한다.

## 2. 돌리기

**먼저 그 저장소의 규칙을 본다.** CLAUDE.md · `.claude/settings.json` 이 `aws logs start-query`(Logs Insights)를 막거나, 권한이 없어 시작이 거절되면 **2-B** 로 간다.

### 2-A. Logs Insights

쿼리는 `${CLAUDE_PLUGIN_ROOT}/references/aws/insights-queries.md` 에서 고른다. 기본 묶음: W1(한눈에) · W2(/api 상위 IP) · W4(AI 봇 이름) · W5(Bot Control 범주). 앱 로그가 있으면 A1(429 · 403).

```
${CLAUDE_PLUGIN_ROOT}/scripts/insights-query.sh --profile <프로필> --region <리전> \
  --log-group <그룹> --since 15m --query '<쿼리>'
```

쿼리마다 따로 돌린다(한 번에 하나). 60초 안에 안 끝나면 스크립트가 멈춘다.

### 2-B. 수만 세기(Logs Insights 를 못 쓸 때)

```
${CLAUDE_PLUGIN_ROOT}/scripts/log-count.sh --profile <프로필> --region <리전> \
  --log-group <그룹> --since 1h --pattern '?limited ?busy ?429'
```

`filter-log-events`(읽기)로 줄을 받아 원문 없이 종류별 수만 낸다. JSON 로그면 `msg` · `outcome` 으로 묶는다. 패턴은 그 앱이 상한 · 거절 때 남기는 말에 맞춘다(코드에서 로그 문구를 먼저 찾는다). 앱이 요청마다 상태 코드를 남기지 않으면 429 수는 셀 수 없다 — 그 자체를 탐지 공백으로 보고서에 적는다.

## 3. 읽고 판단하기

세 줄 요약을 먼저 쓴다: 「무슨 일이 있나 · 얼마나 · 무엇을 할까(없음 / 지켜봄 / 막을 후보)」.

| 신호 | 뜻 | 할 일 |
|---|---|---|
| W4 · W5 에 AI 봇 · `ai` 범주가 많음 | T1 · T2 | robots.txt 확인, Bot Control AI 범주 Block 후보 |
| W2 의 한 IP 가 `distinct_args` 큼 | 열거(T5) | W3 로 경로 확인 → 속도 규칙 값 · Block 후보, 데이터 경로 로그인 검토 |
| `http_library` · `scraping_framework` 범주 | 스크립트(T5) | 속도 규칙 · Challenge 후보 |
| A1 429 급증 | 상한이 일하는 중이거나 실제 사용자가 걸림 | 같은 시간의 W2 와 맞춰 사람인지 본다 |
| LLM 경로 호출 급증 | T6 | 그 경로의 상한 · 캐시 확인 |

- IP 는 원문을 쓰지 않는다(앞 두 마디나 해시 앞부분).
- 막을 후보는 「규칙 · 값 · 예상 영향」으로 적고, 적용은 사람이 정한다(`aws-bot-defense` 3단계).
- 아무 일 없으면 한 줄로 끝낸다.
