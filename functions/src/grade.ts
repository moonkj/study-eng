import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";

import { PackGenerationError, type Usage } from "./pack.js";
import { GeneratedGrade, GradeRequest, type ToeicTarget, type ToeicTask } from "./schema.js";

/** 채점은 자주 돌아가니 Sonnet 으로 빠르고 싸게 */
export const GRADE_MODEL = "claude-sonnet-5-5";

/** 문항별 ETS 점수 상한 */
export const MAX_SCORES: Record<ToeicTask, number> = {
  read_aloud: 3,
  picture: 3,
  respond: 3,
  info: 3,
  opinion: 5,
};

const TASK_LABELS: Record<ToeicTask, string> = {
  read_aloud: "Read a text aloud (지문 읽기)",
  picture: "Describe a picture (사진 묘사)",
  respond: "Respond to questions (질문에 답하기)",
  info: "Respond to questions using information provided (표 보고 답하기)",
  opinion: "Express an opinion (의견 말하기)",
};

/** 목표 레벨별 공식 점수 구간 */
const TARGET_DESC: Record<ToeicTarget, string> = {
  IM1: "110~120점",
  IM2: "130점",
  IM3: "140~150점",
  IH: "160~170점",
  AL: "180~200점",
};

export const GRADE_SYSTEM_PROMPT = `당신은 ETS 공식 채점 기준을 잘 아는 TOEIC Speaking 채점관이자, 한국인 성인 학습자를 돕는 친절한 코치입니다.
학습자의 답변은 음성 인식(STT) 결과(transcript)로만 주어집니다. 문항 유형별 공식 기준으로 채점합니다.

문항별 기준 (점수 범위)
- read_aloud (0~3): 발음·억양·강세. 소리는 들을 수 없으니 지문과 비교해 빠지거나 잘못 인식된 단어, 끝까지 읽었는지로 판단합니다. 대부분 정확하고 완주했으면 3, 군데군데 빠지거나 틀리면 2, 많이 빠지거나 절반 이하면 1, 거의 없으면 0.
- picture (0~3): 사진의 핵심 요소(장소·인물·행동·사물) 묘사, 문법, 어휘, 문장 연결. 핵심을 여러 문장으로 정확히 묘사하면 3, 묘사는 되지만 오류·빈약함이 있으면 2, 단편적이면 1.
- respond (0~3): 질문과의 관련성, 완결성, 문법·어휘. 질문에 맞게 완전한 문장으로 답하면 3, 관련은 있지만 불완전·오류가 많으면 2, 관련이 약하거나 아주 짧으면 1.
- info (0~3): 표 정보를 정확히 전달했는지, 질문에 맞는지, 완결성. 정보가 틀리면 크게 감점합니다.
- opinion (0~5): 분명한 의견, 이유와 구체적 예시, 구성(서론·이유·예시·마무리), 충분한 길이, 문법·어휘. 의견과 이유·예시가 잘 짜여 있으면 4~5, 의견은 있지만 근거가 약하면 3, 짧고 단편적이면 1~2.
- 무응답·질문과 무관·영어가 아님은 0.

채점 원칙
- 음성 인식 오류를 감안합니다. 동음이의어·비슷한 소리로 잘못 인식된 것(예: their/there, to/two, 사람 이름)이 분명하면 감점하지 않고 fixes 에도 넣지 않습니다.
- 말한 시간(seconds)이 제한 시간(limitSeconds)에 비해 많이 짧으면(대략 절반 미만) 감점합니다. read_aloud 는 지문을 끝까지 읽었는지가 기준입니다.
- target_met 은 이 답변이 이 문항에서 목표 레벨에 기대되는 수준을 충족하는지입니다.
- level 은 이 답변 하나가 보여 주는 대략적인 TOEIC Speaking 레벨입니다 (NL < NM < NH < IL < IM1 < IM2 < IM3 < IH < AL).
- 한국어는 짧고 자연스러운 존댓말로 씁니다. summary_ko 는 1~2문장, 격려하되 솔직하게.
- good_ko 는 잘한 점 최대 2개, fixes 는 transcript 에서 고칠 영어 최대 3개 (from 은 transcript 에 있는 그대로).
- improved 는 학습자의 생각을 살려 목표 레벨에 맞게 다시 쓴 답변으로, 제한 시간 안에 말할 수 있는 길이로 씁니다.
  · IM1~IM3: 쉽고 외우기 좋은 짧고 완결된 문장 (IM1 은 더 짧고 단순하게)
  · IH: 이유·세부 내용을 덧붙이고 연결어(because, for example, also, so)로 이어서
  · AL: 풍부한 어휘와 다양한 문장 구조, 짜임새 있는 구성
  next_tip_ko 도 목표 레벨에 맞춥니다. read_aloud 는 지문을 그대로 둡니다. transcript 가 비었으면 모범 답안 수준의 쉬운 답변을 씁니다.
- next_tip_ko 는 다음에 바로 해 볼 수 있는 구체적인 팁 하나입니다.`;

export function buildGradePrompt(req: GradeRequest): string {
  const reference = req.reference?.trim();
  return `문항 유형: ${req.task} — ${TASK_LABELS[req.task]} (0~${MAX_SCORES[req.task]}점)
목표 레벨: ${req.target} (${TARGET_DESC[req.target]})
문제(화면에 보인 내용):
${req.prompt.trim()}
${reference ? `\n${req.task === "read_aloud" ? "지문" : "모범 답안"}:\n${reference}\n` : ""}
말한 시간: ${Math.round(req.seconds)}초 / 제한 시간 ${Math.round(req.limitSeconds)}초
학습자 답변(음성 인식):
${req.transcript.trim() || "(인식된 말 없음)"}`;
}

type Client = Pick<Anthropic, "beta">;

/** 앱으로 보내는 채점 결과 */
export interface Grade {
  score: number;
  maxScore: number;
  level: string;
  /** 목표 레벨에 기대되는 수준을 충족했는지 */
  targetMet?: boolean;
  summaryKo: string;
  goodKo: string[];
  fixes: Array<{ from: string; to: string; whyKo: string }>;
  improved: string;
  nextTipKo: string;
}

/** 앱 형식으로 바꾼다: 점수는 문항 범위로 자르고, 목록 개수를 맞추고, 빈 항목은 뺀다 */
export function toAppGrade(out: GeneratedGrade, req: GradeRequest): Grade {
  const maxScore = MAX_SCORES[req.task];
  const score = Math.min(maxScore, Math.max(0, Math.round(Number.isFinite(out.score) ? out.score : 0)));
  return {
    score,
    maxScore,
    level: out.level,
    targetMet: out.target_met,
    summaryKo: out.summary_ko.trim(),
    goodKo: out.good_ko.map((s) => s.trim()).filter(Boolean).slice(0, 2),
    fixes: out.fixes
      .map((f) => ({ from: f.from.trim(), to: f.to.trim(), whyKo: f.why_ko.trim() }))
      .filter((f) => f.from && f.to && f.from !== f.to)
      .slice(0, 3),
    improved: out.improved.trim(),
    nextTipKo: out.next_tip_ko.trim(),
  };
}

/** 한 번만 시도한다 (실패하면 앱이 다시 요청). 형식 오류·거절은 PackGenerationError 로 알린다. */
export async function generateGrade(client: Client, req: GradeRequest) {
  const usage: Usage = [];
  let response;
  try {
    response = await client.beta.messages.parse({
      model: GRADE_MODEL,
      max_tokens: 2000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: [{ type: "text", text: GRADE_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      output_config: { effort: "low", format: betaZodOutputFormat(GeneratedGrade) },
      messages: [{ role: "user", content: buildGradePrompt(req) }],
    });
  } catch (e) {
    // SDK 가 응답을 스키마로 읽다 실패한 경우(출력 잘림 등)
    if (e instanceof Anthropic.AnthropicError && !(e instanceof Anthropic.APIError)) {
      throw new PackGenerationError("채점 결과를 읽지 못했습니다", [], usage);
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
    throw new PackGenerationError("채점 결과를 읽지 못했습니다", [], usage);
  }
  return { grade: toAppGrade(response.parsed_output, req), usage };
}
