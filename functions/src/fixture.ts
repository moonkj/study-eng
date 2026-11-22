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
    { en: "Free refills here.", ko: "여기 리필 무료예요.", focus: "refill" },
  ],
  quiz: [
    {
      prompt: "아이스 라떼 주시겠어요?",
      choices: ["Could I get an iced latte?", "Can I getting an iced latte?", "Could get I an iced latte?"],
      answer_index: 0,
      explanation: "Could I get ~? 은 정중한 주문 표현이에요.",
      review_of: "",
      tests: "Could I get ~?",
    },
    {
      prompt: "사실 나 조금 피곤해.",
      choices: ["Actual, I'm tired.", "Actually, I'm a little tired.", "In actually I tired."],
      answer_index: 1,
      explanation: "actually 는 문장 앞에서 '사실은'.",
      review_of: "w-actually",
      tests: "",
    },
  ],
};

writeFileSync(process.argv[2] ?? "server_pack.json", JSON.stringify(toAppPack(pack, req), null, 2));
