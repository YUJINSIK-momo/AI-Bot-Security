# AI-Bot-Security

AI 봇 · 크롤러 · AI 에이전트 · 리버스 엔지니어링 에이전트로부터 **내 웹서비스**를 지키는 Claude Code 플러그인 마켓플레이스입니다.

다른 저장소에서 플러그인을 켜면, 에이전트가 그 저장소와 운영 사이트를 읽고 다음을 해 줍니다.
1. 어떤 호스팅 · 서비스를 쓰는지 판별합니다(AWS · Cloudflare · Vercel · Netlify …, Next.js · NestJS · Express · Django …).
2. 공격자 시점의 노출을 점검합니다.
3. 그 스택에 맞는 대응안(코드 · Terraform PR, 체크리스트)을 냅니다.
4. 로그로 지금 봇 트래픽을 확인합니다.

> 완전히 막을 수는 없습니다. 브라우저로 내려간 것은 누구든 가져갈 수 있습니다. 이 플러그인의 목표는 넷입니다. **대량 복제를 느리고 비싸게** 만들고, **비용이 새는 길**(공개 경로의 LLM 호출)을 막고, **탐지**하고, **다툴 근거**를 남깁니다.

## 들어 있는 것 — `bot-defense` 플러그인

| 종류 | 이름 | 하는 일 |
|---|---|---|
| 스킬 | `/bot-defense:bot-defense` | 처음부터 끝까지: 판별 → 점검 → 호스팅별 대응 → 보고서 |
| 스킬 | `/bot-defense:stack-detect` | 호스팅 · 앞단(CDN · WAF) · 프레임워크 · 이미 있는 방어 · 위험 신호 판별 |
| 스킬 | `/bot-defense:exposure-audit` | 공개 API 경로의 인증 · 상한 · 비싼 호출. 운영 사이트의 robots.txt · 소스맵 · 번들에 보이는 API · 번들의 키 |
| 스킬 | `/bot-defense:aws-bot-defense` | AWS 를 읽기 전용으로 점검(ALB · CloudFront · WAF · Bot Control · 로그 · 경보)하고 Terraform 변경안을 낸다 |
| 스킬 | `/bot-defense:log-watch` | CloudWatch Logs Insights 로 AI 봇 · 열거 패턴 · 상한 수를 요약한다(`/loop` 로 반복) |
| 에이전트 | `bot-defense-auditor` | 읽기 전용 감사 — 큰 저장소의 공개 경로를 따로 훑는다 |
| 훅 | PreToolUse(Bash) | 클라우드 · 배포를 **바꾸는** 명령(`aws … update-*`, `terraform apply`, `kubectl apply` 등)이면 사람에게 묻는다 |

위협 모델(T1 학습 크롤러 ~ T6 비용 고갈)과 층별 대응은 [`references/threats.md`](plugins/bot-defense/references/threats.md)에 있습니다.

## 설치

### 나만 쓸 때

Claude Code 안에서:

```
/plugin marketplace add YUJINSIK-momo/AI-Bot-Security
/plugin install bot-defense@ai-bot-security
```

### 팀 저장소에서 다 같이 쓸 때

그 저장소의 `.claude/settings.json` 에 넣고 커밋합니다. 폴더를 신뢰한 팀원에게 자동으로 켜집니다.

```json
{
  "extraKnownMarketplaces": {
    "ai-bot-security": {
      "source": { "source": "github", "repo": "YUJINSIK-momo/AI-Bot-Security" }
    }
  },
  "enabledPlugins": {
    "bot-defense@ai-bot-security": true
  }
}
```

버전을 고정하려면 `source` 에 `"ref": "<태그>"` 를 더합니다.

### 설정

- **팀 공통**(커밋해도 되는 값): 그 저장소 루트의 `.bot-defense.json` — 운영 주소, 볼 리전, 로그 그룹, 변경 규칙, 보고서 위치. 형식은 [`references/config.md`](plugins/bot-defense/references/config.md).
- **개인**: `claude plugin configure bot-defense@ai-bot-security` → `aws_profile`(읽기 전용 권한의 프로필 이름).
- **AWS 권한**: [`references/aws/iam-readonly-policy.json`](plugins/bot-defense/references/aws/iam-readonly-policy.json)(describe · list · get · Logs Insights 조회만).
- **로그인**은 사용자가 자기 터미널에서 합니다(예: `aws sso login --profile 이름`).

필요한 것: `bash`, `jq`, `curl`. DNS 를 보려면 `dig`, AWS 스킬은 AWS CLI v2, 템플릿 검증은 `terraform`(선택).

## 쓰는 법

```
/bot-defense:bot-defense https://example.com
/bot-defense:stack-detect . https://example.com
/bot-defense:exposure-audit
/bot-defense:aws-bot-defense --profile readonly --region ap-northeast-2
/bot-defense:log-watch 1h
/loop 15m /bot-defense:log-watch 15m
```

자연어로 "우리 사이트 크롤링 막을 방법 점검해줘"라고 해도 스킬이 불립니다.

## 안전 원칙

- **내 서비스만** 점검합니다. 운영 사이트 점검(`probe-site.sh`)은 `--authorized` 확인 없이는 요청을 보내지 않습니다.
- **클라우드는 읽기만** 합니다. 바꿀 것은 PR · 체크리스트로 내고, 적용은 사람이 합니다. 훅이 바꾸는 명령을 잡아 사람에게 묻습니다.
- **비밀값을 다루지 않습니다.** 키 · 토큰을 대화에 붙이지 않고, 출력에서 키 값 · IP 원문 · 계정 ID 전체를 가립니다.
- **보고서는 약점 목록**이라 공개 저장소에 올리지 않습니다.

## 「실시간」 감시 구조

```
[늘 돈다]   WAF · 앱 지표 ──▶ CloudWatch 경보 ──▶ SNS ──▶ Slack        (templates/aws/waf-alarms.tf)
[주기 요약] /loop 15m /bot-defense:log-watch ──▶ Logs Insights ──▶ 세 줄 요약 + 막을 후보
[경보 때]   경보 ──▶ 사람이 /bot-defense:log-watch ──▶ 누가 무엇을 부르는지 ──▶ 대응안(PR)
```

LLM 이 로그를 계속 지켜보는 대신, 늘 도는 감시는 클라우드 경보가 맡고 에이전트는 요약과 판단을 맡습니다.

## 저장소 구조

```
.claude-plugin/marketplace.json
plugins/bot-defense/
├── .claude-plugin/plugin.json
├── skills/          bot-defense · stack-detect · exposure-audit · aws-bot-defense · log-watch
├── agents/          bot-defense-auditor.md
├── hooks/           hooks.json(클라우드 변경 명령 확인)
├── scripts/         detect-stack · probe-site · aws-inventory · insights-query · guard-cloud-mutation
├── data/            ai-user-agents.tsv(AI 봇 이름 한 곳)
├── references/      threats · ai-user-agents · config · report-template · hosting/ · frameworks/ · aws/
└── templates/       aws/(WAF Count 모드 · 경보 Terraform) · nextjs/robots.ts
tools/check.sh       검증 · 린트 · 시험
```

## 개발

```
tools/check.sh
```

플러그인 검증(`--strict`), shellcheck, JSON, Terraform 형식, 스크립트 시험을 돌립니다. 시험은 가짜 저장소와 가짜 `aws` 를 써서 네트워크와 AWS 없이 돕니다.

## 다음에 할 것

- Cloudflare · Vercel 설정을 읽는 점검 스크립트(지금은 문서 안내만)
- 세션 없이 도는 주기 점검(GitHub Actions · 사내 러너)과 Slack 요약
- `claude plugin eval` 시험(스킬이 제대로 불리는지)
- 앱 로그 형식 프로필(NestJS · Express JSON 로그)
- GCP Cloud Armor · Azure Front Door 점검

## 라이선스

아직 정하지 않았습니다.
