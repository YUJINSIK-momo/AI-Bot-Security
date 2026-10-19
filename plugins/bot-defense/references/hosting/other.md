# 그 밖의 호스팅 — 공통 대응

앞단에 관리형 봇 방어가 없는 곳(VM 하나, 쿠버네티스, Fly · Render · Railway, GCP · Azure 기본 구성 등)에서 쓰는 것.

## 앞단이 없을 때

| 층 | 할 것 |
|---|---|
| 규칙 | robots.txt(`references/ai-user-agents.md`), 약관 조항 |
| 리버스 프록시 | nginx `limit_req` · `limit_conn`, Caddy rate limit 모듈, Envoy local rate limit — `/api/` 에 IP 당 상한 |
| 앱 | 프레임워크별 상한(`references/frameworks/`), 비싼 경로는 로그인 뒤로 |
| CDN | 필요하면 Cloudflare · CloudFront 같은 관리형 앞단을 둔다. 원 서버는 그 앞단에서만 받게 잠근다 |
| 탐지 | 접근 로그에서 IP · 경로별 수, 열거 패턴 |

## 클라우드별

- **GCP:** Cloud Armor(외부 HTTP(S) 부하 분산기에 붙는다) — 속도 기반 규칙, reCAPTCHA Enterprise 연동, 봇 관리. Cloud Run 을 직접 열어 두었으면 앞에 부하 분산기를 둔다.
- **Azure:** Front Door · Application Gateway 의 WAF — 봇 보호 관리형 규칙, 속도 제한 규칙.
- **쿠버네티스:** Ingress 컨트롤러(예: ingress-nginx 의 `limit-rps` 주석)나 앞단 CDN.

플랜 · 기능 이름은 바뀌므로 각 공식 문서를 확인하고, 확실하지 않으면 「확인 필요」라고 적는다.
