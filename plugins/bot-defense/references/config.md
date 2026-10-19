# 설정 — 어디에 무엇을 두나

## 프로젝트 설정 `.bot-defense.json`(소비 저장소 루트, 선택)

팀이 같이 쓰는 값만 둔다. 비밀값(키 · 토큰)은 두지 않는다. 저장소에 커밋해도 되는 값이다.

```json
{
  "site_url": "https://example.com",
  "aws": { "regions": ["ap-northeast-2"] },
  "logs": {
    "waf": ["aws-waf-logs-example"],
    "app": ["/ecs/example-api"]
  },
  "internal_clients": "서버 PDF 렌더러가 /api 를 부른다 — 상한에서 빼야 한다",
  "change_policy": "AWS 를 바꾸기 전에 팀 변경 기록에 먼저 적고 확인받는다",
  "report_dir": "~/security-reports/example"
}
```

| 키 | 뜻 |
|---|---|
| `site_url` | 지킬 운영 주소 |
| `aws.regions` | 볼 리전. CloudFront 는 늘 us-east-1 을 함께 본다 |
| `logs.waf` · `logs.app` | `log-watch` 가 볼 로그 그룹 |
| `internal_clients` | 공개 경로를 부르는 서버 내부 클라이언트 설명 |
| `change_policy` | 클라우드를 바꾸기 전에 지킬 팀 규칙 — 스킬이 제안 끝에 적는다 |
| `report_dir` | 보고서를 둘 곳. 없으면 매번 묻는다. 저장소 안 · 공개 저장소에는 두지 않는다 |

## 개인 설정(플러그인 옵션)

`claude plugin configure bot-defense@ai-bot-security` 로 넣는다. 사람마다 다른 값이다.

| 옵션 | 뜻 |
|---|---|
| `aws_profile` | 읽기 전용 AWS CLI 프로필 이름(`references/aws/iam-readonly-policy.json` 권한) |

AWS 로그인은 사용자가 자기 터미널에서 한다(예: `aws sso login --profile 이름`). 키를 대화에 붙여 달라고 하지 않는다.

## 값을 찾는 순서

1. 사용자가 이번 대화에서 준 값
2. `.bot-defense.json`
3. 플러그인 옵션
4. 그래도 없으면 묻는다
