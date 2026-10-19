---
name: stack-detect
description: 저장소와 운영 주소를 읽기만 해서 호스팅(AWS ALB · CloudFront · Vercel · Netlify · Cloudflare 등), 프레임워크(Next.js · NestJS · Express · Django 등), 이미 있는 봇 방어, 위험 신호(LLM SDK · 소스맵 · 공개 환경 변수)를 판별한다. 봇 방어 점검의 첫 단계로, 또는 "어떤 호스팅 · 서비스를 쓰는지 알아봐" 같은 요청에 쓴다.
argument-hint: "[저장소 경로] [운영 주소]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh *)
---

# 스택 판별

1. 저장소 경로(기본: 지금 폴더)와 운영 주소를 정한다. 주소는 `.bot-defense.json` 의 `site_url` 이나 사용자에게서. 주소가 없어도 돌릴 수 있다(저장소만 본다).
2. 돌린다:

   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh <저장소 경로> --url <운영 주소>
   ```

   저장소는 읽기만 하고, 운영 주소에는 GET 두 번(https · http)과 DNS 조회만 보낸다.
3. 결과 JSON 을 읽는다.
   - `summary`: 분류별 id(hosting · edge · dns · framework · defense · risk · ci · note)
   - `signals`: 각 판단의 근거(파일 또는 응답 머리 · DNS)
   - `playbooks`: 다음에 읽을 문서(`${CLAUDE_PLUGIN_ROOT}/` 기준 경로)
4. 사람에게 표로 짧게 보여 준다: 입구(사용자가 처음 닿는 곳) → 앞단(CDN · WAF) → 앱(프레임워크) → 이미 있는 방어 → 위험 신호.
5. 애매하면 확인받는다. 예:
   - 저장소에는 ALB 가 있는데 운영 응답에 CloudFront 머리가 있다 → 앞에 CloudFront 가 하나 더 있는지
   - DNS 는 Cloudflare 인데 `cf-ray` 가 없다 → 프록시가 꺼져 있는지(`note` 에 적힌다)
   - Terraform 이 없는데 AWS 신호가 있다 → 콘솔로 관리하는지

## 한계

- 파일 이름 · 내용의 흔적으로 판단한다. 모노레포 · 여러 앱이면 앱별로 다시 확인한다.
- 앞단의 WAF 규칙 내용은 여기서 못 본다. AWS 면 `aws-bot-defense` 스킬로 본다.
