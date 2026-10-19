// Next.js App Router 의 robots.txt — `app/robots.ts` 로 복사한다(bot-defense 템플릿).
// 봇 이름은 플러그인의 data/ai-user-agents.tsv 와 맞춘다. 묶음별로 나눠 두어 줄 하나로 되돌릴 수 있게 한다.
// 막을 경로(PRIVATE_PATHS)는 서비스에 맞게 고친다. 검색엔진은 막지 않는다.
import type { MetadataRoute } from "next";

/** 모든 봇에게 막는 경로 — API · 인쇄 · 로그인 같은 내부 화면. */
const PRIVATE_PATHS = ["/api/"];

/** 모델 학습용 수집. */
const AI_TRAINING = [
  "GPTBot", "ClaudeBot", "anthropic-ai", "CCBot", "Google-Extended", "Applebot-Extended", "Bytespider",
  "meta-externalagent", "cohere-ai", "Amazonbot", "Diffbot", "Omgilibot", "Timpibot", "ImagesiftBot",
];

/** AI 검색 색인 — 막으면 AI 검색에서 덜 보인다(기획 결정). */
const AI_SEARCH = ["OAI-SearchBot", "Claude-SearchBot", "PerplexityBot", "YouBot", "DuckAssistBot"];

/** 사용자가 시킨 페이지 읽기 — 막으면 사람이 AI 에게 이 페이지를 읽혀도 못 읽는다(기획 결정). */
const AI_USER = ["ChatGPT-User", "Claude-User", "Perplexity-User", "MistralAI-User", "meta-externalfetcher"];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/", disallow: PRIVATE_PATHS },
      { userAgent: AI_TRAINING, disallow: "/" },
      { userAgent: AI_SEARCH, disallow: "/" },
      { userAgent: AI_USER, disallow: "/" },
    ],
  };
}
