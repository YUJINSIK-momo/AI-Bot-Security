# AI 봇 이름(User-Agent) 다루기

목록의 한 곳은 `data/ai-user-agents.tsv` 다. robots.txt 를 만들 때와 `scripts/probe-site.sh` 가 함께 쓴다. 이름을 고치면 그 파일만 고친다.

## 묶음

| 묶음 | 뜻 | 막으면 잃는 것 |
|---|---|---|
| `training` | 모델 학습용 수집 | 거의 없음 |
| `search` | AI 검색 색인 | ChatGPT · Perplexity 같은 곳의 검색 노출 |
| `user` | 사용자가 시킨 페이지 읽기 | 사람이 AI 에게 「이 페이지 요약해 줘」 할 때 못 읽음 |

`search` · `user` 를 막을지는 기획(노출 · 유입)과 함께 정한다. 기본 제안은 「셋 다 막고, 묶음별로 따로 적어서 한 줄로 되돌릴 수 있게」다.

## robots.txt 를 만들 때

- 검색엔진(Googlebot · Bingbot · 네이버 Yeti · Daum)은 막지 않는다.
- 모든 봇(`*`)에게 API 경로(`/api/`)와 인쇄 · 내부 화면을 막는다.
- AI 봇은 묶음별로 `Disallow: /` 를 둔다.
- 프레임워크 템플릿: Next.js 는 `templates/nextjs/robots.ts`.

## 한계

- robots.txt 는 규칙을 지키는 봇만 막는다.
- User-Agent 는 아무나 쓸 수 있다. 앞단(WAF · CDN)의 「검증된 봇」 규칙은 IP · 역방향 DNS 로 진짜인지 본다. 이름만 흉내 낸 요청은 「검증 안 된 봇」 으로 따로 다룬다.
- 이름은 바뀐다. 분기마다 각 회사 문서로 확인한다.

## 각 회사 문서

- OpenAI: https://platform.openai.com/docs/bots
- Google(Google-Extended 등): https://developers.google.com/search/docs/crawling-indexing/google-common-crawlers
- Apple(Applebot-Extended): https://support.apple.com/en-us/119829
- Common Crawl(CCBot): https://commoncrawl.org/ccbot
- Perplexity: https://docs.perplexity.ai/guides/bots
- Meta: https://developers.facebook.com/docs/sharing/webmasters/web-crawlers
- Amazon(Amazonbot): https://developer.amazon.com/amazonbot
- Anthropic(ClaudeBot · Claude-User · Claude-SearchBot): Anthropic 지원 문서의 크롤러 안내
