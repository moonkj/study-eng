import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";

import { GeneratedPack, PackRequest } from "./schema.js";

export const MODEL = "claude-opus-5-5";

/** 시스템 프롬프트는 매일 같게 유지해 프롬프트 캐시가 잘 맞도록 한다. */
export const SYSTEM_PROMPT = `당신은 한국인 성인 학습자를 위한 실용 영어회화 선생님입니다.
매일 출퇴근길 10~15분 동안 공부할 "오늘의 학습 팩"을 만듭니다.

표현과 문장:
- 교과서체가 아니라 원어민이 실제로 자주 쓰는 구어체를 고릅니다. 축약형(I'm, I'll, don't)을 기본으로 쓰고 "I am going to" 같은 풀어 쓴 형태는 피합니다.
- 요청한 콘텐츠 난이도(CEFR)에 맞춥니다. 너무 쉬우면 지루하고, 너무 어려우면 포기합니다.
- 표현·단어·문장은 하나의 "상황"(예: 출근길 카페)으로 묶되, 같은 품사 단어는 4개 이하로 하고 동의어·반의어 쌍은 넣지 않습니다.
- 단어 예문과 따라 말하기 문장에는 그 단어를 넣습니다. 자연스러우면 활용형(took, crowded, commutes)이나 분리된 구동사(figure it out)도 괜찮습니다.
- 따라 말하기 문장과 퀴즈 문장은 표현·단어 예문을 그대로 쓰지 말고, 같은 상황의 새 문장으로 만듭니다.
- 한국어 번역은 직역하지 말고 자연스러운 말투로 씁니다.

발음 표기:
- IPA 는 미국 일반 발음(General American) 기준으로, 플랩(t→d 소리) 같은 실제 발음을 반영합니다.
- 한글 발음(pron_ko)은 실제 대화 속도 기준으로 쓰고, 강세 음절을 [대괄호]로 표시합니다. 끝소리는 받침으로 적고 '으'를 덧붙이지 않습니다. 강세 괄호에는 강세 음절 전체(받침 포함)를 넣고, /ɑ/ 로 소리 나는 o 는 '아'로 적습니다. (예: actually → [액]슈얼리, crowded → [크라우]딛, commute → 커[뮤웃], on time → 안 [타임], definitely → [데]퍼닛리)

퀴즈 (한국어 문장을 보고 알맞은 영어 고르기, 3지선다):
- 오답은 원어민이 들으면 확실히 틀린 문장이어야 합니다. 뜻만 다른 자연스러운 문장, 원어민도 쓰는 맞는 문장은 오답으로 쓰지 않습니다.
- 오답은 한국인이 실제로 자주 하는 실수로 만듭니다: 한국어 직역(discuss about, reach to, arrive 뒤 전치사 누락), prefer A than B, 관사 누락, 3인칭 -s, 시제 일치, bored/boring 혼동, 어순, 콩글리시.
- 해설에는 정답 이유와 함께 오답이 왜 틀렸는지(어떤 한국인 실수인지)를 씁니다.
- 복습 항목이 주어지면 항목마다 퀴즈 1문항을 만들고 review_of 에 그 id 를 넣습니다.

그 밖에:
- 최근에 배운 표현·단어 목록에 있는 것은 다시 내지 않습니다.
- 차별적이거나 민감한 내용은 넣지 않습니다.`;

const SKILL_KO: Record<string, string> = {
  vocabulary: "어휘",
  grammar: "문장 구성",
  listening: "듣기",
  speaking: "말하기",
};

export function buildUserPrompt(req: PackRequest): string {
  const skills = Object.entries(req.skills)
    .map(([k, v]) => `${SKILL_KO[k] ?? k} ${v}`)
    .join(", ");
  const review = req.review.length
    ? req.review.map((r) => `- id=${r.id} (${r.kind === "word" ? "단어" : "표현"}) ${r.text} = ${r.meaning}`).join("\n")
    : "(없음)";
  const focusHint =
    req.focusSkill === "speaking"
      ? "말하기가 약하니 따라 말하기 문장은 입에 잘 붙는 짧은 리듬의 문장으로 만드세요."
      : req.focusSkill === "vocabulary"
        ? "어휘가 약하니 단어 예문을 특히 쉽고 기억에 남게 만드세요."
        : req.focusSkill === "grammar"
          ? "문장 구성이 약하니 퀴즈 오답을 어순·시제 실수 위주로 만드세요."
          : "듣기가 약하니 연음이 자주 일어나는 자연스러운 문장을 섞으세요.";

  return `날짜: ${req.date}
학습자 전체 레벨: ${req.level} / 영역별: ${skills}
오늘 콘텐츠 난이도: ${req.contentLevel}
약한 영역: ${SKILL_KO[req.focusSkill]} — ${focusHint}
따라 말하기 문장 수: ${req.speakingSentences}

최근에 배운 표현 (다시 내지 마세요): ${req.avoid.expressions.join(" | ") || "(없음)"}
최근에 배운 단어 (다시 내지 마세요): ${req.avoid.words.join(", ") || "(없음)"}

오늘 복습할 항목:
${review}

위 조건으로 오늘의 학습 팩을 만들어 주세요.`;
}

const IRREGULAR: Record<string, string[]> = {
  be: ["am", "is", "are", "was", "were", "been", "being"],
  have: ["has", "had", "having"],
  do: ["does", "did", "done", "doing"],
  go: ["goes", "went", "gone", "going"],
  get: ["gets", "got", "gotten", "getting"],
  take: ["takes", "took", "taken", "taking"],
  make: ["makes", "made", "making"],
  come: ["comes", "came", "coming"],
  run: ["runs", "ran", "running"],
  catch: ["catches", "caught", "catching"],
  buy: ["buys", "bought", "buying"],
  think: ["thinks", "thought", "thinking"],
  keep: ["keeps", "kept", "keeping"],
  leave: ["leaves", "left", "leaving"],
  pay: ["pays", "paid", "paying"],
  say: ["says", "said", "saying"],
  tell: ["tells", "told", "telling"],
  find: ["finds", "found", "finding"],
  bring: ["brings", "brought", "bringing"],
  hold: ["holds", "held", "holding"],
  put: ["puts", "putting"],
  set: ["sets", "setting"],
};

/** 한 단어의 흔한 활용형 (규칙 변화 + 자주 쓰는 불규칙 동사) */
export function wordForms(word: string): string[] {
  const w = word.toLowerCase();
  const forms = new Set([w, `${w}s`, `${w}es`, `${w}ed`, `${w}d`, `${w}ing`, `${w}er`, `${w}ly`]);
  if (w.endsWith("e")) forms.add(`${w.slice(0, -1)}ing`);
  if (w.endsWith("y")) {
    forms.add(`${w.slice(0, -1)}ies`);
    forms.add(`${w.slice(0, -1)}ied`);
  }
  if (/[^aeiou][aeiou][bdgmnprt]$/.test(w)) {
    forms.add(`${w}${w.at(-1)}ed`);
    forms.add(`${w}${w.at(-1)}ing`);
  }
  for (const f of IRREGULAR[w] ?? []) forms.add(f);
  return [...forms];
}

/**
 * 문장에 단어(또는 구동사)가 들어 있는지. 활용형과, 구동사 사이에 목적어가 끼는 경우(figure it out)를 허용한다.
 * 구동사의 첫 단어만 활용하고, 나머지 단어 사이에는 최대 3단어까지 끼어들 수 있다.
 */
export function containsWord(sentence: string, word: string): boolean {
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const parts = word.toLowerCase().trim().split(/\s+/);
  const first = `(?:${wordForms(parts[0]).map(esc).join("|")})`;
  const rest = parts.slice(1).map((p) => `(?:[\\s,]+[\\w']+){0,3}?[\\s,]+${esc(p)}`);
  const re = new RegExp(`\\b${first}${rest.join("")}\\b`, "i");
  return re.test(sentence.replace(/[’]/g, "'"));
}

/** 스키마로는 표현할 수 없는 규칙을 검사한다. 문제가 없으면 빈 배열. */
export function validatePack(pack: GeneratedPack, req: PackRequest): string[] {
  const problems: string[] = [];
  const lower = (s: string) => s.toLowerCase();

  if (pack.expressions.length !== 3) problems.push(`expressions 는 3개여야 합니다 (현재 ${pack.expressions.length}개)`);
  if (pack.words.length !== 10) problems.push(`words 는 10개여야 합니다 (현재 ${pack.words.length}개)`);
  if (pack.sentences.length !== req.speakingSentences)
    problems.push(`sentences 는 ${req.speakingSentences}개여야 합니다 (현재 ${pack.sentences.length}개)`);

  for (const e of pack.expressions) {
    if (!e.pattern.includes(e.highlight)) problems.push(`표현 "${e.pattern}" 의 highlight "${e.highlight}" 가 pattern 안에 없습니다`);
    if (e.examples.length !== 2) problems.push(`표현 "${e.pattern}" 의 예문은 2개여야 합니다`);
  }

  const words = new Set(pack.words.map((w) => lower(w.word)));
  if (words.size !== pack.words.length) problems.push("words 에 중복이 있습니다");
  for (const w of pack.words) {
    if (!containsWord(w.example.en, w.word)) problems.push(`단어 "${w.word}" 의 예문에 단어가 들어있지 않습니다`);
  }
  const wordExamples = new Set(pack.words.map((w) => lower(w.example.en.trim())));
  for (const s of pack.sentences) {
    if (!words.has(lower(s.focus))) problems.push(`문장 "${s.en}" 의 focus "${s.focus}" 가 오늘 단어가 아닙니다`);
    else if (!containsWord(s.en, s.focus)) problems.push(`문장 "${s.en}" 에 "${s.focus}" 가 들어있지 않습니다`);
    if (wordExamples.has(lower(s.en.trim()))) problems.push(`따라 말하기 문장 "${s.en}" 이 단어 예문과 똑같습니다. 새 문장으로 만들어 주세요`);
  }

  const posCount = new Map<string, number>();
  for (const w of pack.words) posCount.set(lower(w.pos_en), (posCount.get(lower(w.pos_en)) ?? 0) + 1);
  for (const [pos, n] of posCount) if (n > 4) problems.push(`같은 품사(${pos}) 단어가 ${n}개입니다. 4개 이하로 해 주세요`);

  // 퀴즈가 방금 본 예문 번역을 그대로 쓰면 '회상'이 아니라 '알아보기'가 된다
  const exampleKo = new Set([
    ...pack.expressions.flatMap((e) => e.examples.map((x) => x.ko.trim())),
    ...pack.words.map((w) => w.example.ko.trim()),
  ]);

  const avoidWords = new Set(req.avoid.words.map(lower));
  const repeated = pack.words.filter((w) => avoidWords.has(lower(w.word))).map((w) => w.word);
  if (repeated.length) problems.push(`최근에 배운 단어를 다시 냈습니다: ${repeated.join(", ")}`);
  const avoidExp = new Set(req.avoid.expressions.map(lower));
  const repeatedExp = pack.expressions.filter((e) => avoidExp.has(lower(e.pattern))).map((e) => e.pattern);
  if (repeatedExp.length) problems.push(`최근에 배운 표현을 다시 냈습니다: ${repeatedExp.join(", ")}`);

  const reviewIds = new Set(req.review.map((r) => r.id));
  for (const q of pack.quiz) {
    if (!q.review_of && exampleKo.has(q.prompt.trim())) problems.push(`퀴즈 "${q.prompt}" 가 예문 번역과 똑같습니다. 새 문장으로 만들어 주세요`);
    if (q.choices.length < 3 || q.choices.length > 4) problems.push(`퀴즈 "${q.prompt}" 의 보기는 3~4개여야 합니다`);
    if (q.answer_index < 0 || q.answer_index >= q.choices.length) problems.push(`퀴즈 "${q.prompt}" 의 answer_index 가 범위를 벗어났습니다`);
    if (new Set(q.choices).size !== q.choices.length) problems.push(`퀴즈 "${q.prompt}" 의 보기에 중복이 있습니다`);
    if (q.review_of && !reviewIds.has(q.review_of)) problems.push(`퀴즈 "${q.prompt}" 의 review_of "${q.review_of}" 는 복습 항목 id 가 아닙니다`);
  }
  const reviewQuizzes = new Set(pack.quiz.map((q) => q.review_of).filter(Boolean));
  for (const id of reviewIds) if (!reviewQuizzes.has(id)) problems.push(`복습 항목 ${id} 의 퀴즈가 없습니다`);
  const todayQuizzes = pack.quiz.filter((q) => !q.review_of).length;
  if (todayQuizzes < 5 || todayQuizzes > 8) problems.push(`오늘 내용 퀴즈는 6문항 정도여야 합니다 (현재 ${todayQuizzes})`);

  return problems;
}

export const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[~']/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);

/** 앱의 DailyPack JSON 형식으로 바꾼다. id 는 내용에서 만들어 날짜가 달라도 같은 단어는 같은 복습 카드가 된다. */
export function toAppPack(pack: GeneratedPack, req: PackRequest) {
  const itemIds = new Map<string, string>([
    ...pack.expressions.map((e) => [e.pattern.toLowerCase(), `exp-${slug(e.pattern)}`] as [string, string]),
    ...pack.words.map((w) => [w.word.toLowerCase(), `w-${slug(w.word)}`] as [string, string]),
  ]);
  return {
    date: req.date,
    topic: pack.topic,
    contentLevel: req.contentLevel,
    expressions: pack.expressions.map((e) => ({
      id: `exp-${slug(e.pattern)}`,
      pattern: e.pattern,
      highlight: e.highlight,
      meaning: e.meaning,
      usage: e.usage,
      examples: e.examples,
      compare: e.compare_en ? { en: e.compare_en, ko: e.compare_ko } : null,
      level: req.contentLevel.split(".")[0],
      topic: pack.topic,
    })),
    words: pack.words.map((w) => ({
      id: `w-${slug(w.word)}`,
      word: w.word,
      posEn: w.pos_en,
      posKo: w.pos_ko,
      meaning: w.meaning,
      ipa: w.ipa,
      pronKo: w.pron_ko,
      example: w.example,
      level: w.level,
    })),
    sentences: pack.sentences.map((s, i) => ({ id: `s-${req.date}-${i + 1}`, en: s.en, ko: s.ko, focus: s.focus })),
    quiz: pack.quiz.map((q, i) => ({
      id: q.review_of ? `q-${q.review_of}` : `q-${req.date}-${i + 1}`,
      prompt: q.prompt,
      choices: q.choices,
      answerIndex: q.answer_index,
      explanation: q.explanation,
      reviewOf: q.review_of || null,
      // 이 문제를 틀리면 복습 일정이 당겨질 표현·단어
      itemId: q.review_of || itemIds.get(q.tests.toLowerCase()) || null,
    })),
  };
}

export class PackGenerationError extends Error {
  constructor(
    message: string,
    readonly problems: string[] = [],
  ) {
    super(message);
  }
}

type Client = Pick<Anthropic, "beta">;

/** 재시도할 때는 새 요청에 직전 문제를 덧붙인다 (대화를 이어 붙이지 않아 단순하고 안전하다). */
function retryNote(problems: string[]): string {
  if (problems.length === 0) return "";
  return `\n\n주의: 직전에 만든 팩에 다음 문제가 있었습니다. 이번에는 꼭 지켜 주세요.\n- ${problems.join("\n- ")}`;
}

/**
 * Claude 로 팩을 만든다. 구조화 출력으로 형식을 강제하고,
 * 규칙 검사에서 걸리면 문제 목록을 알려주고 한 번 더 만든다.
 */
export async function generatePack(client: Client, req: PackRequest, maxAttempts = 2) {
  let problems: string[] = [];
  const usage: Array<Record<string, number | null | undefined>> = [];

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const response = await client.beta.messages.parse({
      model: MODEL,
      max_tokens: 16000,
      // 정책상 거절되면 서버에서 다른 모델로 이어서 처리 (거절 사유별 자동 선택)
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      cache_control: { type: "ephemeral" },
      system: SYSTEM_PROMPT,
      output_config: { effort: "medium", format: betaZodOutputFormat(GeneratedPack) },
      messages: [{ role: "user", content: buildUserPrompt(req) + retryNote(problems) }],
    });
    usage.push({
      input: response.usage.input_tokens,
      output: response.usage.output_tokens,
      cacheRead: response.usage.cache_read_input_tokens,
    });

    if (response.stop_reason === "refusal") {
      throw new PackGenerationError("Claude 가 요청을 거절했습니다");
    }
    if (response.stop_reason === "max_tokens") {
      problems = ["응답이 너무 길어 잘렸습니다. 문장을 더 짧게 만들어 주세요."];
    } else if (!response.parsed_output) {
      problems = ["응답을 스키마대로 읽을 수 없습니다"];
    } else {
      problems = validatePack(response.parsed_output, req);
      if (problems.length === 0) return { pack: toAppPack(response.parsed_output, req), usage, attempts: attempt };
    }
  }
  throw new PackGenerationError("규칙에 맞는 팩을 만들지 못했습니다", problems);
}
