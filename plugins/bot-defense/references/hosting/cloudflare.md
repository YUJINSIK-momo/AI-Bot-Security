# Cloudflare — 앞단 대응

기능 이름과 플랜별 제공 범위는 자주 바뀐다. 제안하기 전에 그 계정의 플랜과 공식 문서를 확인한다(2026-10 기준으로 적음).

## 먼저 볼 것

- **프록시가 켜져 있나:** DNS 만 Cloudflare 이고 레코드가 「DNS only」(회색 구름)면 Cloudflare 방어가 앞에 없다. 응답에 `cf-ray` 머리가 있는지로 안다(`detect-stack.sh`).
- **원 서버가 직접 열려 있나:** 원 서버 IP 로 바로 들어오면 Cloudflare 를 비켜 간다. 원 서버는 Cloudflare IP 대역만 받게 하거나 터널(Cloudflare Tunnel)을 쓴다.

## 쓸 수 있는 것(층별)

| 위협 | 기능 | 메모 |
|---|---|---|
| T1 · T2 AI 크롤러 | AI 크롤러 차단(대시보드 한 번 켜기), AI Crawl Control, 관리형 robots.txt | 검증된 AI 봇을 이름 · IP 로 막는다 |
| T1 ~ T3 일반 봇 | Bot Fight Mode(무료) · Super Bot Fight Mode(유료 플랜) · Bot Management(엔터프라이즈) | 봇 점수로 막거나 확인 |
| T3 · T5 | 속도 제한 규칙(Rate limiting rules) | 플랜마다 규칙 수 · 기준(IP · 머리 · 쿠키)이 다르다 |
| T5 | Turnstile(사람 확인) · 관리형 Challenge | 로그인 · 비싼 동작 앞에 둔다. API 는 토큰을 먼저 받게 한다 |
| 탐지 | Security Analytics · 이벤트 로그, Logpush(유료) | |

## 단계

1. 프록시 · 원 서버 잠금부터 확인한다.
2. AI 크롤러 차단을 켜고, `/api/` 에 속도 제한 규칙을 「기록(Log)」 또는 낮은 단계로 먼저 둔다(플랜이 허락하면).
3. 1~2주 본 뒤 차단으로 바꾼다.
4. 스크립트 재호출이 남으면 Turnstile 또는 관리형 Challenge 를 비싼 경로 앞에 둔다.

## 바꾸는 법

- Terraform(cloudflare 프로바이더)을 쓰는 저장소면 PR 로 낸다. 아니면 대시보드에서 누를 체크리스트를 낸다.
- API 토큰을 대화에 붙여 달라고 하지 않는다. 사용자가 자기 터미널에서 환경 변수로 넣는다.

## 공식 문서

- 봇: https://developers.cloudflare.com/bots/
- AI Crawl Control: https://developers.cloudflare.com/ai-crawl-control/
- 속도 제한 규칙: https://developers.cloudflare.com/waf/rate-limiting-rules/
- Turnstile: https://developers.cloudflare.com/turnstile/
