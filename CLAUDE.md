# 이 저장소에서 일할 때

Claude Code 플러그인 마켓플레이스다. 플러그인은 `plugins/bot-defense/` 하나다.

## 공개 저장소다

- 특정 회사 · 서비스의 이름, 도메인, 계정 ID, 내부 구조, 실제 점검 결과를 넣지 않는다. 예시는 `example.com` 과 일반적인 이름으로 쓴다.
- 키 · 토큰 · 로그 원문을 넣지 않는다.

## 쓰는 법

- 문서와 스킬은 한국어로 쓴다. 짧은 문장, 표, 「무엇을 · 왜」 순서.
- 사람 이름 대신 역할(개발자 · 기획자 · 운영자)을 쓴다.
- 커밋 메시지와 PR 은 한국어로 쓴다.

## 스크립트(`plugins/bot-defense/scripts/`)

- macOS 기본 bash 3.2 에서 돈다. 연관 배열 · `mapfile` · `${var,,}` 를 쓰지 않는다.
- 필요한 것은 bash · jq · curl(+ 선택: dig · aws · terraform)로 묶는다.
- 출력은 JSON 하나다. 실패도 `{"error": …}` JSON 으로 낸다.
- 클라우드 · 외부 사이트에는 **읽기만** 한다. 바꾸는 명령을 스크립트에 넣지 않는다.
- 키 값 · IP 원문 · 계정 ID 전체를 출력하지 않는다.

## 함께 고칠 것

- AI 봇 이름: `data/ai-user-agents.tsv` 가 한 곳이다. 고치면 `templates/nextjs/robots.ts` 의 목록도 맞춘다.
- 버전: `plugins/bot-defense/.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 `version` 을 같이 올린다.
- 요금 · 기능 이름을 적을 때는 확인한 날짜와 공식 링크를 함께 둔다.

## 바꾼 뒤

`tools/check.sh` 가 모두 통과해야 한다.
