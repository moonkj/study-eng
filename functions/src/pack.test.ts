import assert from "node:assert/strict";
import Anthropic from "@anthropic-ai/sdk";
import { test } from "node:test";

import { handleDailyPack } from "./handler.js";
import { buildUserPrompt, containsWord, generatePack, slug, toAppPack, validatePack } from "./pack.js";
import type { GeneratedPack, PackRequest } from "./schema.js";

const req: PackRequest = {
  date: "2026-11-23",
  level: "B1.2",
  contentLevel: "B1.3",
  skills: { vocabulary: "B2.1", grammar: "B1.2", listening: "B1.2", speaking: "A2.2" },
  focusSkill: "speaking",
  speakingSentences: 10,
  avoid: { expressions: ["I'm running late."], words: ["commute"] },
  review: [{ id: "w-actually", kind: "word", text: "actually", meaning: "사실은" }],
};

function goodPack(): GeneratedPack {
  const words = ["grab", "rush", "nearby", "spill", "line", "order", "seat", "receipt", "refill", "warm"];
  return {
    topic: "카페 · 아침",
    expressions: [0, 1, 2].map((i) => ({
      pattern: `Could I get a ~ ${i}`,
      highlight: "Could I get",
      meaning: "~ 주시겠어요?",
      usage: "주문할 때",
      examples: [
        { en: "Could I get a latte?", ko: "라떼 주시겠어요?" },
        { en: "Could I get a receipt?", ko: "영수증 주시겠어요?" },
      ],
      compare_en: "I want ~",
      compare_ko: "는 조금 직설적이에요.",
      pron_ko: i === 2 ? "" : "쿠다이 [겟]",
      linking: "could 의 d 와 I 가 이어져요.",
    })),
    words: words.map((w, i) => ({
      word: w,
      pos_en: ["verb", "noun", "adjective"][i % 3],
      pos_ko: "동사",
      meaning: "뜻",
      ipa: "/x/",
      pron_ko: "발음",
      example: { en: `I ${w} it every day.`, ko: "예문" },
      level: "B1",
    })),
    sentences: words.map((w) => ({ en: `Let's ${w} now.`, ko: "번역", focus: w })),
    quiz: [
      ...[1, 2, 3, 4, 5, 6].map((i) => ({
        prompt: `문제 ${i}`,
        choices: [`A${i}`, `B${i}`, `C${i}`],
        answer_index: 1,
        explanation: "해설",
        review_of: "",
        tests: i === 1 ? "grab" : "",
      })),
      { prompt: "사실 나 피곤해.", choices: ["Actually, I'm tired.", "Actual I tired.", "In fact tired I."], answer_index: 0, explanation: "해설", review_of: "w-actually", tests: "" },
    ],
  };
}

test("규칙을 지킨 팩은 문제가 없다", () => {
  assert.deepEqual(validatePack(goodPack(), req), []);
});

test("개수, 단어 포함 여부, 중복, 복습 누락을 잡아낸다", () => {
  const p = goodPack();
  p.words.pop();
  p.words[0].example.en = "No target here.";
  p.words[1].word = "commute";
  p.quiz = p.quiz.filter((q) => !q.review_of);
  p.quiz[0].answer_index = 5;
  const problems = validatePack(p, req).join("\n");
  assert.match(problems, /words 는 10개/);
  assert.match(problems, /예문에 단어가 들어있지 않습니다/);
  assert.match(problems, /최근에 배운 단어를 다시 냈습니다: commute/);
  assert.match(problems, /복습 항목 w-actually 의 퀴즈가 없습니다/);
  assert.match(problems, /answer_index 가 범위를 벗어났습니다/);
});

test("따라 말하기가 예문 복사, 같은 품사 과다, 퀴즈가 예문 번역 그대로면 잡아낸다", () => {
  const p = goodPack();
  p.sentences[0].en = p.words[0].example.en;
  p.words.forEach((w) => (w.pos_en = "adverb"));
  p.quiz[0].prompt = p.expressions[0].examples[0].ko;
  const problems = validatePack(p, req).join("\n");
  assert.match(problems, /단어 예문과 똑같습니다/);
  assert.match(problems, /같은 품사\(adverb\) 단어가 10개/);
  assert.match(problems, /예문 번역과 똑같습니다/);
});

test("앱 형식으로 바꿀 때 내용 기반 id 를 만든다", () => {
  const app = toAppPack(goodPack(), req);
  assert.equal(app.words[0].id, "w-grab");
  assert.equal(app.expressions[0].id, `exp-${slug("Could I get a ~ 0")}`);
  assert.equal(app.quiz.at(-1)!.id, "q-w-actually");
  assert.equal(app.quiz.at(-1)!.reviewOf, "w-actually");
  assert.equal(app.quiz[0].reviewOf, null);
  assert.equal(app.quiz[0].itemId, "w-grab");
  assert.equal(app.quiz[1].itemId, null);
  assert.equal(app.quiz.at(-1)!.itemId, "w-actually");
  assert.equal(slug("I've been meaning to ~"), "ive-been-meaning-to");
});

test("프롬프트에 레벨, 약점, 중복 방지, 복습 항목이 들어간다", () => {
  const p = buildUserPrompt(req);
  assert.match(p, /오늘 콘텐츠 난이도: B1\.3/);
  assert.match(p, /약한 영역: 말하기/);
  assert.match(p, /commute/);
  assert.match(p, /id=w-actually/);
});

function fakeClient(responses: Array<Partial<{ parsed_output: GeneratedPack | null; stop_reason: string }>>) {
  const calls: unknown[] = [];
  return {
    calls,
    beta: {
      messages: {
        parse: async (params: unknown) => {
          calls.push(params);
          const r = responses[Math.min(calls.length - 1, responses.length - 1)];
          return {
            stop_reason: r.stop_reason ?? "end_turn",
            parsed_output: r.parsed_output ?? null,
            content: [],
            usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0 },
          };
        },
      },
    },
  };
}

test("첫 응답이 규칙에 어긋나면 문제를 알려주고 한 번 더 만든다", async () => {
  const bad = goodPack();
  bad.sentences = bad.sentences.slice(0, 5);
  const client = fakeClient([{ parsed_output: bad }, { parsed_output: goodPack() }]);
  const result = await generatePack(client as never, req);
  assert.equal(result.attempts, 2);
  const second = client.calls[1] as { messages: Array<{ content: string }>; model: string; fallbacks: string };
  assert.match(second.messages[0].content, /sentences 는 10개여야/);
  assert.equal(second.model, "claude-opus-5-5");
  assert.equal(second.fallbacks, "default");
});

test("API: 토큰이 없거나 틀리면 401, 형식이 틀리면 400, 성공하면 200", async () => {
  const client = fakeClient([{ parsed_output: goodPack() }]);
  const base = { method: "POST", appToken: "secret", client: client as never };
  assert.equal((await handleDailyPack({ ...base, authorization: undefined, body: req })).status, 401);
  assert.equal((await handleDailyPack({ ...base, authorization: "Bearer nope!!", body: req })).status, 401);
  assert.equal((await handleDailyPack({ ...base, authorization: "Bearer secret", body: { date: "x" } })).status, 400);
  const ok = await handleDailyPack({ ...base, authorization: "Bearer secret", body: req });
  assert.equal(ok.status, 200);
  assert.equal((ok.body as { words: unknown[] }).words.length, 10);
});

test("API: 두 번 다 규칙에 어긋나면 502 와 문제 목록", async () => {
  const bad = goodPack();
  bad.expressions = bad.expressions.slice(0, 1);
  const client = fakeClient([{ parsed_output: bad }]);
  const r = await handleDailyPack({ method: "POST", appToken: "t", authorization: "Bearer t", body: req, client: client as never });
  assert.equal(r.status, 502);
  assert.match(JSON.stringify(r.body), /expressions 는 3개/);
});

test("거절되면 바로 오류로 처리한다", async () => {
  const client = fakeClient([{ stop_reason: "refusal" }]);
  const r = await handleDailyPack({ method: "POST", appToken: "t", authorization: "Bearer t", body: req, client: client as never });
  assert.equal(r.status, 502);
  assert.equal(client.calls.length, 1);
});

test("단어 포함 검사: 활용형과 분리된 구동사를 허용한다", () => {
  assert.ok(containsWord("I took the bus.", "take"));
  assert.ok(containsWord("The trains were so crowded.", "crowded"));
  assert.ok(containsWord("She commutes by bike.", "commute"));
  assert.ok(containsWord("I'll figure it out later.", "figure out"));
  assert.ok(containsWord("We're figuring out the plan.", "figure out"));
  assert.ok(containsWord("I'll definitely go.", "definitely"));
  assert.ok(!containsWord("I'll go later.", "figure out"));
  assert.ok(!containsWord("The cat sat.", "take"));
  assert.ok(containsWord("I'll figure it out later.", "figure out", "phrasal verb"));
  assert.ok(!containsWord("I only had time.", "on time", "phrase"));
  assert.ok(!containsWord("I've been working late a lot lately.".replace("late a lot ", ""), "late"));
  assert.ok(containsWord("It's busier than usual.", "busy", "adjective"));
  assert.ok(containsWord("I forgot my umbrella.", "forget", "verb"));
});

test("퀴즈 tests 가 구두점·활용형이 달라도 오늘 항목 id 를 찾는다", () => {
  const p = goodPack();
  p.quiz[0] = { ...p.quiz[0], tests: "Grabbed", review_of: "" };
  const out = toAppPack(p, req);
  assert.equal(out.quiz[0].itemId, "w-grab");
});

test("SDK 가 응답을 읽다 실패하면(출력 잘림) 짧게 다시 만든다", async () => {
  let n = 0;
  const client = {
    beta: {
      messages: {
        parse: async () => {
          n++;
          if (n === 1) throw new Anthropic.AnthropicError("Failed to parse structured output");
          return { stop_reason: "end_turn", parsed_output: goodPack(), content: [], usage: { input_tokens: 1, output_tokens: 1 } };
        },
      },
    },
  } as unknown as Parameters<typeof generatePack>[0];
  const out = await generatePack(client, req);
  assert.equal(out.attempts, 2);
});

test("표현 발음·연음 안내를 pron 으로 내보내고, 비어 있으면 null 로 둔다", () => {
  const out = toAppPack(goodPack(), req);
  assert.deepEqual(out.expressions[0].pron, { ko: "쿠다이 [겟]", tip: "could 의 d 와 I 가 이어져요." });
  assert.equal(out.expressions[2].pron, null);
});
