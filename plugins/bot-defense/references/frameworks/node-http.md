# Express · Fastify · Koa · Hono

| 프레임워크 | 속도 제한 | 프록시 뒤 IP |
|---|---|---|
| Express | `express-rate-limit`(`windowMs`, `limit`, `standardHeaders`), 여러 대면 `rate-limit-redis` | `app.set('trust proxy', 홉 수)` |
| Fastify | `@fastify/rate-limit`(`max`, `timeWindow`), Redis 저장소 옵션 | Fastify 옵션 `trustProxy` |
| Koa | `koa-ratelimit` | `app.proxy = true` |
| Hono | `hono-rate-limiter` | 런타임별 접속 정보 도우미 |

## 공통

- `trust proxy` 를 `true`(전부 신뢰)로 두지 않는다. 앞단 홉 수만큼만 믿는다. 그렇지 않으면 `X-Forwarded-For` 를 위조해 상한을 비켜 간다.
- 경로 묶음별로 상한을 다르게 둔다(목록 · 상세 · 일괄 · LLM).
- 처음엔 세기만 하고 로그를 본 뒤 막는다.
- 429 에는 `Retry-After` 를 준다.
