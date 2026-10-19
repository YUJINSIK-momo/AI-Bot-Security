# Netlify — 앞단 대응

Netlify 의 방화벽 · 속도 제한 기능은 플랜에 따라 다르다. 제안하기 전에 그 팀의 플랜과 공식 문서(https://docs.netlify.com/)에서 「rate limiting」 · 「traffic rules」 · 「firewall」 을 확인한다. 확실하지 않으면 「확인 필요」라고 적는다.

## 플랜과 상관없이 할 수 있는 것

- robots.txt(정적 파일)로 AI 봇 금지 — `references/ai-user-agents.md`.
- Edge Functions 에서 User-Agent · 경로로 AI 봇을 거절(403). 이름만 보는 것이라 T1 · T2 용이다.
- 서버리스 함수(API) 안에서 IP · 계정 상한. 함수는 여러 개가 따로 뜨므로 메모리 상한은 부정확하다 — 공유 저장소(예: Upstash Redis)로 센다.
- 비싼 경로(LLM)는 로그인 뒤로, 새로 만들 때만 상한.

## 공식 기능이 있으면

- 속도 제한 · 트래픽 규칙이 플랜에 있으면 `/api/` 에 먼저 둔다.
- 그 밖의 앞단 방어가 필요하면 Cloudflare 같은 CDN 을 앞에 두는 방법도 있다(원 서버 잠금과 함께).
