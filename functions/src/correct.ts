import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";

import { MODEL, PackGenerationError, type Usage } from "./pack.js";
import { CorrectRequest, GeneratedCorrection } from "./schema.js";

/** '내 상황으로 말하기' 교정: 한 문장만 보면 되니 짧은 프롬프트, 작은 출력, 낮은 effort 로 빠르고 싸게 */
export const CORRECT_SYSTEM_PROMPT = `당신은 한국인 성인 학습자의 영어 문장을 고쳐 주는 친절한 회화 선생님입니다.
학습자는 오늘 배운 표현으로 자기 상황을 영어 한 문장(또는 두세 문장)으로 말해 봤습니다.
- 원어민이 실제로 말하는 자연스러운 구어체로 고칩니다. 뜻과 말투는 최대한 그대로 두고, 필요한 곳만 고칩니다.
- 문법·단어 선택이 맞고 자연스러우면 ok=true, corrected 는 원문 그대로 둡니다. 대소문자·끝 구두점 같은 사소한 차이는 문제로 보지 않습니다.
- notes 는 한국어 1~2문장, 친절한 존댓말로 씁니다. 고친 곳이 있으면 "규칙 + 맞는 형태"로 짧게, 없으면 잘한 점을 칭찬합니다.
- error_type 은 가장 큰 실수 하나: word_choice(단어 선택), grammar_form(시제·수 일치·형태), preposition(전치사), word_order(어순), collocation(함께 쓰는 말), meaning(뜻 혼동). 문제가 없으면 none.
- used_expression 은 학습자 원문이 오늘 표현을 알맞게 썼는지입니다.
- 영어 문장이 아니거나 의미를 알 수 없으면 ok=false 로 하고, notes 에 오늘 표현을 넣은 짧은 예시 문장을 권합니다.`;

export function buildCorrectPrompt(req: CorrectRequest): string {
  const e = req.expression;
  return `학습자 레벨: ${req.level}
오늘 표현: ${e.pattern} (핵심: ${e.highlight}) = ${e.meaning}
상황: ${req.situationKo?.trim() || "(자유)"}
학습자 문장: ${req.sentence.trim()}`;
}

type Client = Pick<Anthropic, "beta">;

/** 앱으로 보내는 교정 결과 */
export interface Correction {
  ok: boolean;
  corrected: string;
  notes: string;
  errorType: string | null;
  usedExpression: boolean;
}

/** 앱 형식으로 바꾼다: "none" → null, 문제가 없으면 원문 유지, 빈 교정문은 원문으로 */
export function toAppCorrection(out: GeneratedCorrection, req: CorrectRequest): Correction {
  const sentence = req.sentence.trim();
  const corrected = out.corrected.trim() || sentence;
  return {
    ok: out.ok,
    corrected: out.ok ? sentence : corrected,
    notes: out.notes.trim(),
    errorType: out.ok || out.error_type === "none" ? null : out.error_type,
    usedExpression: out.used_expression,
  };
}

/** 한 번만 시도한다 (실패하면 앱이 다시 요청). 형식 오류·거절은 PackGenerationError 로 알린다. */
export async function generateCorrection(client: Client, req: CorrectRequest) {
  const usage: Usage = [];
  let response;
  try {
    response = await client.beta.messages.parse({
      model: MODEL,
      max_tokens: 1500,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: [{ type: "text", text: CORRECT_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      output_config: { effort: "low", format: betaZodOutputFormat(GeneratedCorrection) },
      messages: [{ role: "user", content: buildCorrectPrompt(req) }],
    });
  } catch (e) {
    // SDK 가 응답을 스키마로 읽다 실패한 경우(출력 잘림 등)
    if (e instanceof Anthropic.AnthropicError && !(e instanceof Anthropic.APIError)) {
      throw new PackGenerationError("교정 결과를 읽지 못했습니다", [], usage);
    }
    throw e;
  }
  usage.push({
    input: response.usage.input_tokens,
    output: response.usage.output_tokens,
    cacheRead: response.usage.cache_read_input_tokens,
    cacheWrite: response.usage.cache_creation_input_tokens,
  });
  if (response.stop_reason === "refusal") throw new PackGenerationError("Claude 가 요청을 거절했습니다", [], usage);
  if (response.stop_reason === "max_tokens" || !response.parsed_output) {
    throw new PackGenerationError("교정 결과를 읽지 못했습니다", [], usage);
  }
  return { correction: toAppCorrection(response.parsed_output, req), usage };
}
