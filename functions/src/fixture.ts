/** 앱 쪽 계약 테스트용: 서버가 실제로 내보내는 JSON 형식 샘플을 만든다. (npm run fixture) */
import { writeFileSync } from "node:fs";

import { toAppPack } from "./pack.js";
import type { GeneratedPack, PackRequest } from "./schema.js";

const req: PackRequest = {
  date: "2026-11-23",
  level: "B1.2",
  contentLevel: "B1.3",
  skills: { vocabulary: "B2.1", grammar: "B1.2", listening: "B1.2", speaking: "A2.2" },
  focusSkill: "speaking",
  speakingSentences: 2,
  avoid: { expressions: [], words: [] },
  review: [{ id: "w-actually", kind: "word", text: "actually", meaning: "사실은" }],
  recentTopics: ["출근길 · 지하철"],
  weakErrorTypes: ["word_order"],
  series: { title: "Coffee Break", episode: 3, cast: ["Mina", "Jake"], lastSummary: "미나가 새 카페를 찾았다." },
};

const pack: GeneratedPack = {
  topic: "카페 · 아침",
  expressions: [
    {
      pattern: "Could I get ~?",
      highlight: "Could I get",
      meaning: "~ 주시겠어요?",
      usage: "카페나 식당에서 정중하게 주문할 때 써요.",
      examples: [
        { en: "Could I get an iced latte?", ko: "아이스 라떼 주시겠어요?" },
        { en: "Could I get the receipt, please?", ko: "영수증 좀 주시겠어요?" },
      ],
      compare_en: "Give me ~",
      compare_ko: "는 명령처럼 들릴 수 있어요.",
      pron_ko: "쿠다이 [겟]",
      linking: "could 의 d 와 I 가 이어져 '쿠다이'처럼 들려요.",
    },
  ],
  words: [
    {
      word: "refill",
      pos_en: "noun",
      pos_ko: "명사",
      meaning: "리필, 다시 채움",
      ipa: "/ˈriː.fɪl/",
      pron_ko: "리필",
      example: { en: "Can I get a refill?", ko: "리필해 주실 수 있어요?" },
      level: "A2",
    },
  ],
  sentences: [
    { en: "Can I get a refill?", ko: "리필해 주실 수 있어요?", focus: "refill" },
    { en: "Could I get a refill, please?", ko: "리필 좀 해 주시겠어요?", focus: "Could I get" },
  ],
  quiz: [
    {
      prompt: "아이스 라떼 주시겠어요?",
      choices: ["Could I get an iced latte?", "Can I getting an iced latte?", "Could get I an iced latte?"],
      answer_index: 0,
      explanation: "Could I get ~? 은 조동사 뒤에 주어, 그다음 동사원형이에요. Could I get (O) / Could get I (X)",
      error_type: "word_order",
      review_of: "",
      tests: "Could I get ~?",
    },
    {
      prompt: "사실 나 조금 피곤해.",
      choices: ["Actual, I'm tired.", "Actually, I'm a little tired.", "In actually I tired."],
      answer_index: 1,
      explanation: "'사실은'은 부사 actually 예요. Actually, I'm tired. (O) / Actual, I'm tired. (X)",
      error_type: "word_choice",
      review_of: "w-actually",
      tests: "",
    },
  ],
  dialogue: {
    title: "Coffee Break",
    summary: "미나가 새 카페에서 주문하고 제이크에게 리필을 권한다.",
    lines: [
      { speaker: "Mina", en: "Could I get an iced latte?", ko: "아이스 라떼 주시겠어요?" },
      { speaker: "Jake", en: "Make it two. I need caffeine.", ko: "두 잔이요. 카페인이 필요해." },
      { speaker: "Mina", en: "They do free refills here.", ko: "여기 리필 무료래." },
      { speaker: "Jake", en: "Could I get a refill, then?", ko: "그럼 리필 좀 받을 수 있을까?" },
    ],
  },
};

writeFileSync(process.argv[2] ?? "server_pack.json", JSON.stringify(toAppPack(pack, req), null, 2));
