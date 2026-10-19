---
name: aws-bot-defense
description: AWS 에서 서비스하는 웹앱의 봇 방어 상태를 읽기 전용으로 점검하고(ALB · CloudFront · API Gateway 와 붙은 WAF, Bot Control, 속도 규칙, WAF 로그, 경보), 빈 곳에 맞는 대응(WAF Count 모드 → Block, Challenge · 토큰, 경보)을 Terraform 변경안으로 낸다. AWS 를 직접 바꾸지 않는다. "AWS 에서 봇 막기", "WAF 설정 점검", "Bot Control", "ALB 에 WAF" 같은 요청에 쓴다.
argument-hint: "[--profile 이름] [--region 리전]"
---

# AWS 봇 방어

## 0. 준비

- **계정을 확인받는다:** 어느 계정 · 리전을 볼지, 그 계정이 사용자 서비스인지.
- **프로필:** 사용자가 준 값 → 플러그인 옵션 `${user_config.aws_profile}`(비었거나 `${…}` 그대로면 없는 것) → 묻는다. 권한은 `${CLAUDE_PLUGIN_ROOT}/references/aws/iam-readonly-policy.json`(읽기 전용).
- **로그인은 사용자가 한다.** 만료되었으면 사용자에게 자기 터미널에서 `aws sso login --profile <이름>` 처럼 로그인하라고 말한다. 키를 대화에 붙여 달라고 하지 않는다.

## 1. 읽기

```
${CLAUDE_PLUGIN_ROOT}/scripts/aws-inventory.sh --profile <프로필> --region <리전> [--region <리전2>]
```

describe · list · get 만 부른다. 결과:
- `regions[].albs`: 인터넷용 ALB, 붙은 웹 ACL, 접근 로그
- `regions[].web_acls`, `cloudfront.web_acls`: 규칙(관리형 그룹 · Bot Control 단계 · 속도 규칙 · count/block), 로그 설정
- `regions[].log_groups`, `waf_log_groups`, `alarms`
- `gaps`: 바로 보이는 빈 곳(읽은 값에서만 만든다)
- `errors`: 권한이 없어 못 읽은 것 — 보고서에 「확인 못 함」으로 적는다
- 값이 `"unknown"` 이면 **권한이 없어 못 읽은 것**이다. 「없음 · 꺼짐」으로 적지 않는다. 그 부분은 코드(Terraform)와 운영 응답으로 따로 판단하고, 근거를 그렇게 밝힌다

## 2. 고르기

`${CLAUDE_PLUGIN_ROOT}/references/hosting/aws.md` 의 표로 입구별 WAF 자리와 단계를 고른다. 늘 이 순서다.

1. 웹 ACL 없음 → Count 모드로 붙이기(IP 평판 · `/api/` 속도 규칙 · Bot Control 일반 · 로그)
2. Count 1~2주 → `log-watch` 로 규칙별 수와 걸린 실제 사용자를 본다
3. 사람이 규칙별로 Block 결정
4. 스크립트 재호출이 남으면 Challenge(+ 애플리케이션 통합 토큰) 또는 Bot Control 표적 단계 — 비용 · 화면 영향을 함께 적는다

비용은 문서의 표(확인 날짜 포함)로 어림한다. 바뀌었을 수 있으니 링크를 함께 준다.

## 3. 변경안 만들기 — 적용은 사람이

- 그 저장소가 Terraform 이면 `${CLAUDE_PLUGIN_ROOT}/templates/aws/waf-alb-count.tf` · `waf-alarms.tf` 를 그 저장소의 폴더 · 이름 · 변수 관례에 맞게 옮긴다.
  - `terraform fmt` · `validate` 까지만 한다. `plan` 은 사용자가 원하면 돌리고, `apply` 는 하지 않는다.
  - 속도 규칙 값(`api_rate_limit`)은 재고 정한다: 사람이 많이 쓸 때의 5분 요청 수 × 5 이상. 모르면 「잰 뒤 정함」으로 둔다.
- CloudFront 가 앞에 있으면 웹 ACL 범위는 `CLOUDFRONT`(us-east-1), 속도 규칙 IP 기준을 확인한다.
- 콘솔로만 관리하면 누를 순서를 체크리스트로 낸다.
- 프로젝트 설정의 `change_policy` 가 있으면 제안 끝에 그대로 적는다(예: 「바꾸기 전에 팀 변경 기록」).

## 4. 하지 않는 것

- `aws ... create/update/put/delete`, `terraform apply` 같은 바꾸는 명령. 훅이 묻더라도 이 스킬은 먼저 부르지 않는다.
- 비용이 큰 것(CloudFront 정액 Business, Bot Control 표적)을 기본으로 권하지 않는다. 필요할 때 근거와 함께 「선택」으로.
