# Django · FastAPI · Flask

| 프레임워크 | 속도 제한 | 프록시 뒤 IP |
|---|---|---|
| FastAPI | `slowapi`(`Limiter`, 데코레이터 `@limiter.limit("100/minute")`) | uvicorn `--proxy-headers --forwarded-allow-ips <앞단 IP>` |
| Django | `django-ratelimit`(`@ratelimit(key="ip", rate="100/m", block=True)`), DRF 는 `DEFAULT_THROTTLE_RATES` | 앞단이 붙인 값만 믿는 미들웨어로 `REMOTE_ADDR` 를 정한다 |
| Flask | `Flask-Limiter` | `werkzeug.middleware.proxy_fix.ProxyFix(x_for=홉 수)` |

## 공통

- 여러 워커 · 여러 대면 메모리 상한은 나뉜다. Redis 저장소를 쓴다.
- LLM 을 부르는 경로는 새로 만들 때만 상한을 쓰고, 막히면 화면이 감출 수 있는 빈 값을 돌려준다.
- 처음엔 세기만 하고 로그를 본 뒤 막는다.
