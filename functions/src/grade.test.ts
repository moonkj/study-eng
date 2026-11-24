import assert from "node:assert/strict";
import Anthropic from "@anthropic-ai/sdk";
import { test } from "node:test";

import { buildGradePrompt, generateGrade, toAppGrade } from "./grade.js";
import { handleGrade } from "./handler.js";
import type { GeneratedGrade, GradeRequest } from "./schema.js";

const req: GradeRequest = {
  task: "opinion",
  target: "IM3",
  prompt: "Do you agree or disagree: It is better to work from home than at the office?",
  reference: "I agree. First, I can save commuting time. For example, ...",
  transcript: "I agree work from home. Because I can save time. For example I don't need take a bus.",
  seconds: 28,
  limitSeconds: 60,
};

const graded: GeneratedGrade = {
  score: 3,
  level: "IM2",
  target_met: false,
  summary_ko: "의견과 이유는 분명해요. 예시를 조금 더 길게 말하면 좋아요.",
  good_ko: ["의견을 처음에 분명히 말했어요.", "예시를 들었어요.", "세 번째는 잘린다"],
  fixes: [
    { from: "I agree work from home", to: "I agree that working from home is better", why_ko: "agree 뒤에는 that 절이 와요." },
    { from: "don't need take", to: "don't need to take", why_ko: "need 뒤에는 to 부정사가 와요." },
    { from: "same", to: "same", why_ko: "바뀐 게 없으면 뺀다" },
    { from: "a", to: "b", why_ko: "1" },
    { from: "c", to: "d", why_ko: "2" },
  ],
  improved: "I agree that working from home is better. First, I can save a lot of time because I don't need to take a bus.",
  next_tip_ko: "이유 하나에 예시 하나를 붙여 45초 이상 말해 보세요.",
};

function fakeClient(r: Partial<{ parsed_output: GeneratedGrade | null; stop_reason: string }>) {
  const calls: Array<Record<string, unknown>> = [];
  return {
    calls,
    beta: {
      messages: {
        parse: async (params: Record<string, unknown>) => {
          calls.push(params);
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

const call = (body: unknown, client: unknown, authorization = "Bearer t") =>
  handleGrade({ method: "POST", appToken: "t", authorization, body, client: client as never });

test("채점: 점수·레벨·피드백을 앱 형식으로 돌려준다 (잘한 점 2개, 교정 3개까지)", async () => {
  const client = fakeClient({ parsed_output: graded });
  const r = await call(req, client);
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, {
    score: 3,
    maxScore: 5,
    level: "IM2",
    targetMet: false,
    summaryKo: graded.summary_ko,
    goodKo: ["의견을 처음에 분명히 말했어요.", "예시를 들었어요."],
    fixes: [
      { from: "I agree work from home", to: "I agree that working from home is better", whyKo: "agree 뒤에는 that 절이 와요." },
      { from: "don't need take", to: "don't need to take", whyKo: "need 뒤에는 to 부정사가 와요." },
      { from: "a", to: "b", whyKo: "1" },
    ],
    improved: graded.improved,
    nextTipKo: graded.next_tip_ko,
  });
  // 자주 돌아가니 Sonnet, 작은 max_tokens, 낮은 effort, 거절 대비
  const params = client.calls[0] as { max_tokens: number; output_config: { effort: string }; model: string; fallbacks: string };
  assert.equal(params.model, "claude-sonnet-5-5");
  assert.ok(params.max_tokens <= 3000);
  assert.equal(params.output_config.effort, "low");
  assert.equal(params.fallbacks, "default");
});

test("채점: 점수는 문항 범위로 자른다 (opinion 0~5, 나머지 0~3)", () => {
  assert.equal(toAppGrade({ ...graded, score: 9 }, req).score, 5);
  assert.equal(toAppGrade({ ...graded, score: -2 }, req).score, 0);
  const picture: GradeRequest = { ...req, task: "picture" };
  const out = toAppGrade({ ...graded, score: 5 }, picture);
  assert.equal(out.score, 3);
  assert.equal(out.maxScore, 3);
  assert.equal(toAppGrade({ ...graded, score: Number.NaN }, picture).score, 0);
});

test("채점: 형식 오류는 400, 토큰이 틀리면 401, GET 은 405", async () => {
  const client = fakeClient({ parsed_output: graded });
  assert.equal((await call({ ...req, task: "essay" }, client)).status, 400);
  assert.equal((await call({ ...req, target: "NL" }, client)).status, 400);
  assert.equal((await call({ ...req, prompt: "  " }, client)).status, 400);
  assert.equal((await call({ ...req, prompt: "a".repeat(3001) }, client)).status, 400);
  assert.equal((await call({ ...req, transcript: "a".repeat(2001) }, client)).status, 400);
  assert.equal((await call({ ...req, seconds: -1 }, client)).status, 400);
  assert.equal((await call({ ...req, limitSeconds: 0 }, client)).status, 400);
  const { transcript: _t, ...noTranscript } = req;
  assert.equal((await call(noTranscript, client)).status, 400);
  assert.equal((await call(req, client, "Bearer nope")).status, 401);
  const get = await handleGrade({ method: "GET", appToken: "t", authorization: "Bearer t", body: req, client: client as never });
  assert.equal(get.status, 405);
  // 빈 답변·참고 답안 없음·목표 레벨 없음(IM3 로)은 받는다
  const { reference: _r, target: _g, ...minimal } = req;
  assert.equal((await call({ ...minimal, transcript: "" }, client)).status, 200);
  assert.match((client.calls.at(-1)!.messages as Array<{ content: string }>)[0].content, /목표 레벨: IM3/);
  for (const target of ["IM1", "IM2", "IH", "AL"]) assert.equal((await call({ ...req, target }, client)).status, 200);
});

test("채점: 거절·읽기 실패는 502, 요청 한도는 503", async () => {
  assert.equal((await call(req, fakeClient({ stop_reason: "refusal" }))).status, 502);
  assert.equal((await call(req, fakeClient({ parsed_output: null }))).status, 502);
  assert.equal((await call(req, fakeClient({ stop_reason: "max_tokens", parsed_output: graded }))).status, 502);
  const truncated = {
    beta: { messages: { parse: async () => { throw new Anthropic.AnthropicError("Failed to parse structured output"); } } },
  };
  assert.equal((await call(req, truncated)).status, 502);
  const limited = {
    beta: {
      messages: {
        parse: async () => {
          throw new Anthropic.RateLimitError(429, undefined, "rate limited", new Headers());
        },
      },
    },
  };
  assert.equal((await call(req, limited)).status, 503);
});

test("채점 프롬프트에 유형·목표·문제·답안·시간·답변이 들어간다", async () => {
  const p = buildGradePrompt(req);
  assert.match(p, /문항 유형: opinion .*0~5점/);
  assert.match(p, /목표 레벨: IM3 \(140~150점\)/);
  assert.match(p, /work from home than at the office/);
  assert.match(p, /모범 답안:\nI agree\. First/);
  assert.match(p, /말한 시간: 28초 \/ 제한 시간 60초/);
  assert.match(p, /I don't need take a bus/);
  const read = buildGradePrompt({ ...req, task: "read_aloud", transcript: "  " });
  assert.match(read, /지문:/);
  assert.match(read, /\(인식된 말 없음\)/);
  const { grade } = await generateGrade(fakeClient({ parsed_output: graded }) as never, req);
  assert.equal(grade.maxScore, 5);
});
