# Vercel — 앞단 대응

기능 이름과 플랜별 제공 범위는 자주 바뀐다. 제안하기 전에 그 팀의 플랜과 공식 문서를 확인한다(2026-10 기준으로 적음).

## 쓸 수 있는 것(층별)

| 위협 | 기능 | 메모 |
|---|---|---|
| T1 · T2 AI 크롤러 | Vercel Firewall 의 관리형 규칙(AI 봇 차단) | 대시보드 Firewall 에서 켠다 |
| T1 ~ T3 | Bot Protection 관리형 규칙, Attack Challenge Mode | 공격 중일 때 모든 방문자에게 확인을 건다 |
| T3 · T5 | Firewall 사용자 규칙의 속도 제한(rate limit), `@vercel/firewall` 로 코드에서 속도 제한 | 경로 · IP · 머리 기준 |
| T5 | BotID(보이지 않는 사람 확인) | 비싼 API · 폼 앞에 둔다. 서버에서 결과를 확인해야 효과가 있다 |
| 탐지 | Firewall 화면 · 로그 드레인 | |

## 단계

1. AI 봇 관리형 규칙을 켠다(먼저 기록만 할 수 있으면 기록).
2. `/api/` 경로에 속도 제한 규칙을 둔다.
3. 비싼 경로(LLM 호출 등)는 BotID 또는 로그인 뒤로 둔다.
4. 공격 중이면 Attack Challenge Mode 를 잠시 켠다.

## 바꾸는 법

- `vercel.json` 이나 Firewall 설정(프로젝트 설정)으로 낸다. 코드로 관리하는 부분은 PR, 대시보드 부분은 체크리스트.
- `vercel --prod` 같은 배포 명령은 사람이 한다(플러그인 훅이 묻는다).

## 공식 문서

- Vercel Firewall: https://vercel.com/docs/vercel-firewall
- BotID: https://vercel.com/docs/botid
