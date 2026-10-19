# Next.js

## 할 것

| 항목 | 어떻게 |
|---|---|
| robots.txt | `app/robots.ts`(`MetadataRoute.Robots`) — `templates/nextjs/robots.ts` |
| 소스맵 | `next.config` 의 `productionBrowserSourceMaps` 를 켜지 않는다(기본 꺼짐). 운영에서 `.map` 이 404 인지 `probe-site.sh` 로 확인 |
| 공개 환경 변수 | `NEXT_PUBLIC_*` 는 번들에 그대로 실린다. 키라면 발급처에서 도메인(리퍼러) 제한을 건다. secret 은 절대 `NEXT_PUBLIC_` 로 두지 않는다 |
| API 의 색인 막기 | `next.config` `headers()` 로 `/api/:path*` 에 `X-Robots-Tag: noindex` |
| `X-Powered-By` | `poweredByHeader: false` |

## 공개 경로 찾기(감사할 때)

- `app/**/route.ts`(Route Handler), `pages/api/**`.
- **Server Actions:** `"use server"` 함수는 직접 부를 수 있는 POST 경로다. 화면 버튼 뒤에 있어도 인증 · 상한을 서버 함수 안에서 본다.
- `middleware.ts`(Next 16 부터 `proxy.ts`)의 `matcher`.
- 앞단(ALB · CDN)이 `/api` 를 다른 백엔드로 보내면, Next 의 미들웨어는 그 요청을 못 본다. 상한은 그 백엔드에 둔다.

## 미들웨어(proxy)에서 할 수 있는 것과 없는 것

- AI 봇 이름으로 403 — T1 · T2 용. 이름은 위조된다.
- 속도 제한은 미들웨어 메모리로 하지 않는다(인스턴스 · 엣지마다 따로). 플랫폼 방화벽(Vercel · Cloudflare)이나 공유 저장소(Upstash Redis 등)를 쓴다.
- 로그인 확인은 화면이 아니라 데이터를 주는 서버 경로에서 한다.
