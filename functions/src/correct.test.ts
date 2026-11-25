import assert from "node:assert/strict";
import Anthropic from "@anthropic-ai/sdk";
import { test } from "node:test";

import { buildCorrectPrompt, generateCorrection, toAppCorrection } from "./correct.js";
import { handleCorrect } from "./handler.js";
import type { CorrectRequest, GeneratedCorrection } from "./schema.js";

const req: CorrectRequest = {
  expression: { pattern: "I've been meaning to ~", highlight: "been meaning to", meaning: "계속 ~하려고 했어" },
  situationKo: "친구에게 연락 못 한 걸 사과할 때",
  sentence: "I've been meaning to calling you.",
  level: "B1.2",
};

const fixed: GeneratedCorrection = {
  ok: false,
  corrected: "I've been meaning to call you.",
  notes: "to 뒤에는 동사원형이 와요. meaning to call (O) / meaning to calling (X)",
  error_type: "grammar_form",
  used_expression: true,
};

function fakeClient(r: Partial<{ parsed_output: GeneratedCorrection | null; stop_reason: string }>) {
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
  handleCorrect({ method: "POST", appToken: "t", authorization, body, client: client as never });

test("교정: 고친 문장·해설·오답 유형·표현 사용 여부를 앱 형식으로 돌려준다", async () => {
  const client = fakeClient({ parsed_output: fixed });
  const r = await call(req, client);
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, {
    ok: false,
    corrected: "I've been meaning to call you.",
    notes: fixed.notes,
    errorType: "grammar_form",
    usedExpression: true,
  });
  // 짧고 싸게: 작은 max_tokens, 낮은 effort, 같은 모델·거절 대비
  const params = client.calls[0] as { max_tokens: number; output_config: { effort: string }; model: string; fallbacks: string };
  assert.ok(params.max_tokens <= 2000);
  assert.equal(params.output_config.effort, "low");
  assert.equal(params.model, "claude-sonnet-5-5");
  assert.equal(params.fallbacks, "default");
});

test("교정: 문제가 없으면 원문 유지, 오답 유형은 null", () => {
  const out = toAppCorrection(
    { ok: true, corrected: "I've been meaning to call you!", notes: "  자연스러워요. ", error_type: "none", used_expression: true },
    { ...req, sentence: "  I've been meaning to call you.  " },
  );
  assert.deepEqual(out, { ok: true, corrected: "I've been meaning to call you.", notes: "자연스러워요.", errorType: null, usedExpression: true });
  // 틀렸는데 none 이면 null, 교정문이 비면 원문
  const odd = toAppCorrection({ ...fixed, error_type: "none", corrected: " " }, req);
  assert.equal(odd.errorType, null);
  assert.equal(odd.corrected, req.sentence);
});

test("교정: 빈 문장·너무 긴 문장·형식 오류는 400, 토큰이 틀리면 401, GET 은 405", async () => {
  const client = fakeClient({ parsed_output: fixed });
  assert.equal((await call({ ...req, sentence: "   " }, client)).status, 400);
  assert.equal((await call({ ...req, sentence: "a".repeat(301) }, client)).status, 400);
  assert.equal((await call({ ...req, sentence: "a".repeat(300) }, client)).status, 200);
  assert.equal((await call({ sentence: "Hi" }, client)).status, 400);
  assert.equal((await call(req, client, "Bearer nope")).status, 401);
  assert.equal((await call(req, client, "")).status, 401);
  const get = await handleCorrect({ method: "GET", appToken: "t", authorization: "Bearer t", body: req, client: client as never });
  assert.equal(get.status, 405);
  // 상황은 없어도 된다
  const { situationKo: _, ...noSituation } = req;
  assert.equal((await call(noSituation, client)).status, 200);
});

test("교정: 거절·읽기 실패는 502, 요청 한도는 503", async () => {
  assert.equal((await call(req, fakeClient({ stop_reason: "refusal" }))).status, 502);
  assert.equal((await call(req, fakeClient({ parsed_output: null }))).status, 502);
  assert.equal((await call(req, fakeClient({ stop_reason: "max_tokens", parsed_output: fixed }))).status, 502);
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

test("교정 프롬프트에 표현·상황·문장·레벨이 들어간다", async () => {
  const p = buildCorrectPrompt(req);
  assert.match(p, /I've been meaning to ~ \(핵심: been meaning to\) = 계속 ~하려고 했어/);
  assert.match(p, /상황: 친구에게 연락 못 한 걸 사과할 때/);
  assert.match(p, /학습자 문장: I've been meaning to calling you\./);
  assert.match(p, /레벨: B1\.2/);
  const { correction } = await generateCorrection(fakeClient({ parsed_output: fixed }) as never, req);
  assert.equal(correction.errorType, "grammar_form");
});
