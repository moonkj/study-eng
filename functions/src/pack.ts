import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";

import { GeneratedPack, PackRequest, type ErrorType } from "./schema.js";

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
- 따라 말하기 문장 중 2~3개는 오늘 표현을 넣어 만들고, 그 문장의 focus 에는 그 표현의 highlight 를 그대로 씁니다. 나머지 문장의 focus 는 오늘 단어입니다.
- 한국어 번역은 직역하지 말고 자연스러운 말투로 씁니다.

발음 표기:
- IPA 는 미국 일반 발음(General American) 기준으로, 플랩(t→d 소리) 같은 실제 발음을 반영합니다.
- 표현의 pron_ko 는 highlight 부분을 실제 대화처럼 이어 말한 소리로 적고, linking 에는 연음·약음(to→트, and→은, want to→워너 등) 요령을 한 문장으로 씁니다.
- 한글 발음(pron_ko)은 실제 대화 속도 기준으로 쓰고, 강세 음절을 [대괄호]로 표시합니다. 끝소리는 받침으로 적고 '으'를 덧붙이지 않습니다. 강세 괄호에는 강세 음절 전체(받침 포함)를 넣고, /ɑ/ 로 소리 나는 o 는 '아'로 적습니다. (예: actually → [액]슈얼리, crowded → [크라우]딛, commute → 커[뮤웃], on time → 안 [타임], definitely → [데]퍼닛리)

퀴즈 (한국어 문장을 보고 알맞은 영어 고르기, 3지선다):
- 오답은 원어민이 들으면 확실히 틀린 문장이어야 합니다. 뜻만 다른 자연스러운 문장, 원어민도 쓰는 맞는 문장은 오답으로 쓰지 않습니다.
- 오답은 한국인이 실제로 자주 하는 실수로 만듭니다: 한국어 직역(discuss about, reach to, arrive 뒤 전치사 누락), prefer A than B, 관사 누락, 3인칭 -s, 시제 일치, bored/boring 혼동, 어순, 콩글리시.
- 해설은 "규칙 + 대비 쌍"으로 씁니다: 규칙 한 문장 뒤에 맞는 형태와 틀린 형태를 나란히 보여 줍니다. (예: "arrive 뒤엔 at/in 이 필요해요. arrive at the station (O) / arrive the station (X)")
- error_type 에는 오답 2개가 노리는 실수 유형을 하나 고릅니다: word_choice(단어 선택), grammar_form(시제·수 일치·-ed/-ing 등 형태), preposition(전치사), word_order(어순), collocation(함께 쓰는 말), meaning(뜻 혼동).
- 오늘 표현 3개는 각각 퀴즈 1문항 이상에서 다루고, 그 문항의 tests 에 그 표현의 pattern 을 그대로 씁니다.
- 복습 항목이 주어지면 항목마다 퀴즈 1문항을 만들고 review_of 에 그 id 를 넣습니다.

시리즈 대화 (dialogue):
- 같은 등장인물이 매일 이어 가는 짧은 시트콤 같은 대화입니다. 4~6줄, 한 줄은 짧게(12단어 이하) 씁니다.
- 오늘 표현 3개 중 2개 이상을 highlight 그대로 대사에 넣습니다. 오늘 단어도 자연스러우면 섞습니다.
- 시리즈 정보가 주어지면 그 제목과 등장인물(cast)만 쓰고, 지난 회 줄거리에서 자연스럽게 이어 갑니다. 없으면 새 제목과 등장인물 2명(영어 이름)을 정합니다.

그 밖에:
- 최근에 배운 표현·단어 목록에 있는 것은 다시 내지 않고, 최근 주제와 겹치지 않는 상황을 고릅니다.
- 차별적이거나 민감한 내용은 넣지 않습니다.`;

const SKILL_KO: Record<string, string> = {
  vocabulary: "어휘",
  grammar: "문장 구성",
  listening: "듣기",
  speaking: "말하기",
};

const ERROR_KO: Record<ErrorType, string> = {
  word_choice: "단어 선택",
  grammar_form: "문법 형태",
  preposition: "전치사",
  word_order: "어순",
  collocation: "함께 쓰는 말",
  meaning: "뜻 혼동",
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

  const recentTopics = req.recentTopics?.length ? req.recentTopics.join(" | ") : "(없음)";
  const topicLine = req.topicHint?.trim() ? `오늘 상황: ${req.topicHint.trim()} — 이 상황으로 주제를 정하세요.` : "오늘 상황: 자유 (최근 주제와 겹치지 않게)";
  const weakLine = req.weakErrorTypes?.length
    ? `자주 틀리는 오답 유형: ${req.weakErrorTypes.map((t) => `${t}(${ERROR_KO[t]})`).join(", ")} — 오늘 내용 퀴즈 2~3문항은 이 유형을 노린 오답으로 만들고 error_type 도 그 유형으로 적으세요.`
    : "자주 틀리는 오답 유형: (아직 없음)";
  const s = req.series;
  const seriesLine = s
    ? `시리즈 대화: 제목 "${s.title}", ${s.episode}회, 등장인물 ${s.cast.join(", ")}${s.lastSummary ? `\n지난 회 줄거리: ${s.lastSummary}` : ""}`
    : "시리즈 대화: 새 시리즈 1회 (제목과 등장인물 2명을 새로 정하세요)";

  return `날짜: ${req.date}
학습자 전체 레벨: ${req.level} / 영역별: ${skills}
오늘 콘텐츠 난이도: ${req.contentLevel}
약한 영역: ${SKILL_KO[req.focusSkill]} — ${focusHint}
따라 말하기 문장 수: ${req.speakingSentences}

최근에 배운 표현 (다시 내지 마세요): ${req.avoid.expressions.join(" | ") || "(없음)"}
최근에 배운 단어 (다시 내지 마세요): ${req.avoid.words.join(", ") || "(없음)"}
최근 주제 (겹치지 마세요): ${recentTopics}
${topicLine}
${weakLine}
${seriesLine}

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
  forget: ["forgets", "forgot", "forgotten", "forgetting"],
  feel: ["feels", "felt", "feeling"],
  spend: ["spends", "spent", "spending"],
  wake: ["wakes", "woke", "woken", "waking"],
  meet: ["meets", "met", "meeting"],
  sleep: ["sleeps", "slept", "sleeping"],
  send: ["sends", "sent", "sending"],
  lose: ["loses", "lost", "losing"],
  win: ["wins", "won", "winning"],
  sit: ["sits", "sat", "sitting"],
  stand: ["stands", "stood", "standing"],
  understand: ["understands", "understood", "understanding"],
  give: ["gives", "gave", "given", "giving"],
  see: ["sees", "saw", "seen", "seeing"],
  know: ["knows", "knew", "known", "knowing"],
  grow: ["grows", "grew", "grown", "growing"],
  drive: ["drives", "drove", "driven", "driving"],
  ride: ["rides", "rode", "ridden", "riding"],
  write: ["writes", "wrote", "written", "writing"],
  eat: ["eats", "ate", "eaten", "eating"],
  drink: ["drinks", "drank", "drunk", "drinking"],
  begin: ["begins", "began", "begun", "beginning"],
  break: ["breaks", "broke", "broken", "breaking"],
  choose: ["chooses", "chose", "chosen", "choosing"],
  fall: ["falls", "fell", "fallen", "falling"],
  hear: ["hears", "heard", "hearing"],
  lend: ["lends", "lent", "lending"],
  mean: ["means", "meant", "meaning"],
  read: ["reads", "reading"],
  sell: ["sells", "sold", "selling"],
  speak: ["speaks", "spoke", "spoken", "speaking"],
  teach: ["teaches", "taught", "teaching"],
  wear: ["wears", "wore", "worn", "wearing"],
};

/**
 * 한 단어의 흔한 활용형 (규칙 변화 + 자주 쓰는 불규칙 동사).
 * 비교급(-er/-est)은 형용사·부사일 때만 붙인다 (hard → hardly 처럼 뜻이 다른 단어가 통과하지 않게, -ly 는 넣지 않는다).
 */
export function wordForms(word: string, pos = ""): string[] {
  const w = word.toLowerCase();
  const adj = /adj|adv|형용|부사/i.test(pos);
  const forms = new Set([w, `${w}s`, `${w}es`, `${w}ed`, `${w}d`, `${w}ing`]);
  if (adj) {
    forms.add(`${w}er`);
    forms.add(`${w}est`);
    if (w.endsWith("e")) {
      forms.add(`${w}r`);
      forms.add(`${w}st`);
    }
  }
  if (w.endsWith("e")) forms.add(`${w.slice(0, -1)}ing`);
  if (/[^aeiou]y$/.test(w)) {
    const stem = w.slice(0, -1);
    forms.add(`${stem}ies`);
    forms.add(`${stem}ied`);
    if (adj) {
      forms.add(`${stem}ier`);
      forms.add(`${stem}iest`);
    }
  }
  if (/[^aeiou][aeiou][bdgmnprt]$/.test(w)) {
    const d = `${w}${w.at(-1)}`;
    forms.add(`${d}ed`);
    forms.add(`${d}ing`);
    if (adj) {
      forms.add(`${d}er`);
      forms.add(`${d}est`);
    }
  }
  for (const f of IRREGULAR[w] ?? []) forms.add(f);
  return [...forms];
}

/**
 * 문장에 단어(또는 구동사)가 들어 있는지. 활용형과, 구동사 사이에 목적어가 끼는 경우(figure it out)를 허용한다.
 * 구동사의 첫 단어만 활용하고, 나머지 단어 사이에는 최대 3단어까지 끼어들 수 있다.
 */
export function containsWord(sentence: string, word: string, pos = ""): boolean {
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const parts = word.toLowerCase().trim().split(/\s+/);
  // 고정 표현(on time 등)은 활용하지 않고 붙여 쓴 그대로, 구동사만 활용·목적어 끼움 허용
  const fixed = parts.length > 1 && pos !== "" && !/verb|동사/i.test(pos);
  const first = fixed ? esc(parts[0]) : `(?:${wordForms(parts[0], pos).map(esc).join("|")})`;
  const gap = fixed ? "" : "(?:[\\s,]+[\\w']+){0,3}?";
  const rest = parts.slice(1).map((p) => `${gap}[\\s,]+${esc(p)}`);
  const re = new RegExp(`\\b${first}${rest.join("")}\\b`, "i");
  return re.test(sentence.replace(/[’]/g, "'"));
}

/**
 * 문장에 표현의 highlight 가 들어 있는지. 대소문자·굽은 따옴표·공백 차이와 끝 구두점은 무시하고,
 * highlight 에 ~ 가 있으면 그 앞뒤 조각이 순서대로 나오는지 본다.
 */
export function containsPhrase(sentence: string, highlight: string): boolean {
  const norm = (t: string) => t.toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ");
  const text = norm(sentence);
  const parts = norm(highlight)
    .split("~")
    .map((p) => p.trim().replace(/^[\s.,!?]+|[\s.,!?]+$/g, ""))
    .filter(Boolean);
  if (parts.length === 0) return false;
  let from = 0;
  for (const part of parts) {
    const at = text.indexOf(part, from);
    if (at < 0) return false;
    from = at + part.length;
  }
  return true;
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
    if (!containsWord(w.example.en, w.word, w.pos_en)) problems.push(`단어 "${w.word}" 의 예문에 단어가 들어있지 않습니다`);
  }
  const wordExamples = new Set(pack.words.map((w) => lower(w.example.en.trim())));
  for (const s of pack.sentences) {
    // focus 는 오늘 단어이거나 오늘 표현의 highlight
    const exp = pack.expressions.find((e) => lower(e.highlight.trim()) === lower(s.focus.trim()));
    if (exp) {
      if (!containsPhrase(s.en, exp.highlight)) problems.push(`문장 "${s.en}" 에 표현 "${exp.highlight}" 가 들어있지 않습니다`);
    } else if (!words.has(lower(s.focus))) problems.push(`문장 "${s.en}" 의 focus "${s.focus}" 가 오늘 단어나 표현 highlight 가 아닙니다`);
    else if (!containsWord(s.en, s.focus, pack.words.find((w) => lower(w.word) === lower(s.focus))?.pos_en)) problems.push(`문장 "${s.en}" 에 "${s.focus}" 가 들어있지 않습니다`);
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

  // 반복·중복은 앱 id 와 같은 기준(slug)으로 본다 ("Could I get ~?" 와 "could I get ~" 는 같은 카드)
  const avoidWords = new Set(req.avoid.words.map(slug));
  const repeated = pack.words.filter((w) => avoidWords.has(slug(w.word))).map((w) => w.word);
  if (repeated.length) problems.push(`최근에 배운 단어를 다시 냈습니다: ${repeated.join(", ")}`);
  const avoidExp = new Set(req.avoid.expressions.map(slug));
  const repeatedExp = pack.expressions.filter((e) => avoidExp.has(slug(e.pattern))).map((e) => e.pattern);
  if (repeatedExp.length) problems.push(`최근에 배운 표현을 다시 냈습니다: ${repeatedExp.join(", ")}`);
  const expSlugs = pack.expressions.map((e) => slug(e.pattern));
  if (new Set(expSlugs).size !== expSlugs.length) problems.push("표현끼리 너무 비슷합니다 (같은 표현이 두 번 나왔습니다)");
  const wordSlugs = pack.words.map((w) => slug(w.word));
  if (new Set(wordSlugs).size !== wordSlugs.length) problems.push("words 에 중복이 있습니다 (철자만 조금 다른 같은 단어)");


  const reviewIds = new Set(req.review.map((r) => r.id));
  for (const q of pack.quiz) {
    if (!q.review_of && exampleKo.has(q.prompt.trim())) problems.push(`퀴즈 "${q.prompt}" 가 예문 번역과 똑같습니다. 새 문장으로 만들어 주세요`);
    if (q.choices.length < 3 || q.choices.length > 4) problems.push(`퀴즈 "${q.prompt}" 의 보기는 3~4개여야 합니다`);
    if (q.answer_index < 0 || q.answer_index >= q.choices.length) problems.push(`퀴즈 "${q.prompt}" 의 answer_index 가 범위를 벗어났습니다`);
    if (new Set(q.choices).size !== q.choices.length) problems.push(`퀴즈 "${q.prompt}" 의 보기에 중복이 있습니다`);
    if (q.review_of && !reviewIds.has(q.review_of)) problems.push(`퀴즈 "${q.prompt}" 의 review_of "${q.review_of}" 는 복습 항목 id 가 아닙니다`);
  }
  const reviewOfs = pack.quiz.map((q) => q.review_of).filter(Boolean);
  if (new Set(reviewOfs).size !== reviewOfs.length) problems.push("같은 복습 항목의 퀴즈가 두 번 나왔습니다. 항목마다 1문항만 만들어 주세요");
  const reviewQuizzes = new Set(pack.quiz.map((q) => q.review_of).filter(Boolean));
  for (const id of reviewIds) if (!reviewQuizzes.has(id)) problems.push(`복습 항목 ${id} 의 퀴즈가 없습니다`);
  const todayQuiz = pack.quiz.filter((q) => !q.review_of);
  const todayQuizzes = todayQuiz.length;
  if (todayQuizzes < 5 || todayQuizzes > 8) problems.push(`오늘 내용 퀴즈는 6문항 정도여야 합니다 (현재 ${todayQuizzes})`);

  // 표현마다 퀴즈 1문항 이상 (tests 로 연결된 itemId 기준: 앱이 틀린 표현의 복습을 당길 수 있게)
  const ids = itemIdMap(pack);
  const quizzed = new Set(todayQuiz.map((q) => findItemId(pack, q.tests, ids)));
  for (const e of pack.expressions) {
    if (!quizzed.has(`exp-${slug(e.pattern)}`))
      problems.push(`표현 "${e.pattern}" 의 퀴즈가 없습니다. 이 표현을 다루는 문항을 만들고 tests 에 pattern 을 그대로 써 주세요`);
  }

  // 약한 오답 유형을 노린 문항이 2개 이상
  const weak = new Set(req.weakErrorTypes ?? []);
  if (weak.size) {
    const n = todayQuiz.filter((q) => weak.has(q.error_type)).length;
    if (n < 2) problems.push(`오답 유형 ${[...weak].join(", ")} 을(를) 노린 퀴즈가 ${n}문항입니다. 2~3문항으로 만들어 주세요`);
  }

  const recent = new Set((req.recentTopics ?? []).map((t) => t.replace(/\s+/g, "")));
  if (recent.has(pack.topic.replace(/\s+/g, ""))) problems.push(`주제 "${pack.topic}" 는 최근에 다룬 주제입니다. 다른 상황으로 바꿔 주세요`);

  problems.push(...validateDialogue(pack, req));

  return problems;
}

/** 시리즈 대화: 4~6줄, 표현 highlight 2개 이상(표현이 2개 미만이면 전부), 시리즈가 있으면 등장인물 고정 */
function validateDialogue(pack: GeneratedPack, req: PackRequest): string[] {
  const problems: string[] = [];
  const d = pack.dialogue;
  if (d.lines.length < 4 || d.lines.length > 6) problems.push(`dialogue 는 4~6줄이어야 합니다 (현재 ${d.lines.length}줄)`);
  const all = d.lines.map((l) => l.en).join("\n");
  const used = pack.expressions.filter((e) => containsPhrase(all, e.highlight)).length;
  const need = Math.min(2, pack.expressions.length);
  if (used < need) problems.push(`dialogue 에 오늘 표현이 ${used}개만 들어 있습니다. highlight 그대로 ${need}개 이상 넣어 주세요`);
  const cast = req.series?.cast;
  if (cast) {
    const names = new Set(cast.map((c) => c.trim().toLowerCase()));
    const strangers = [...new Set(d.lines.map((l) => l.speaker.trim()).filter((sp) => !names.has(sp.toLowerCase())))];
    if (strangers.length) problems.push(`dialogue 에 시리즈 등장인물(${cast.join(", ")})이 아닌 사람이 나옵니다: ${strangers.join(", ")}`);
  } else if (new Set(d.lines.map((l) => l.speaker.trim().toLowerCase())).size < 2) {
    problems.push("dialogue 에는 등장인물이 2명 이상 나와야 합니다");
  }
  return problems;
}

export const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[~']/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);

/** 퀴즈가 다루는 오늘 항목 id. 철자가 조금 달라도(활용형·구두점) 찾는다. 못 찾으면 null. */
function findItemId(pack: GeneratedPack, tests: string, itemIds: Map<string, string>): string | null {
  if (!tests.trim()) return null;
  const exact = itemIds.get(slug(tests));
  if (exact) return exact;
  const w = pack.words.find((w) => containsWord(tests, w.word, w.pos_en));
  if (w) return `w-${slug(w.word)}`;
  const t = slug(tests);
  const e = pack.expressions.find((e) => {
    const p = slug(e.pattern);
    return p.length > 0 && (t.includes(p) || p.includes(t));
  });
  return e ? `exp-${slug(e.pattern)}` : null;
}

/** 오늘 항목 slug → 앱 id. tests 를 slug 로 맞춘다 (물음표·대소문자·공백 차이로 itemId 가 빠지지 않게) */
function itemIdMap(pack: GeneratedPack): Map<string, string> {
  return new Map<string, string>([
    ...pack.expressions.map((e) => [slug(e.pattern), `exp-${slug(e.pattern)}`] as [string, string]),
    ...pack.words.map((w) => [slug(w.word), `w-${slug(w.word)}`] as [string, string]),
  ]);
}

/** 앱의 DailyPack JSON 형식으로 바꾼다. id 는 내용에서 만들어 날짜가 달라도 같은 단어는 같은 복습 카드가 된다. */
export function toAppPack(pack: GeneratedPack, req: PackRequest) {
  const itemIds = itemIdMap(pack);
  const d = pack.dialogue;
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
      pron: e.pron_ko?.trim() ? { ko: e.pron_ko.trim(), tip: e.linking?.trim() ?? "" } : null,
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
      itemId: q.review_of || findItemId(pack, q.tests, itemIds),
      errorType: q.error_type,
    })),
    // 시리즈가 있으면 제목·회차는 요청 그대로 (Claude 가 바꿔 쓰지 않게), 없으면 새 시리즈 1회
    dialogue: {
      title: req.series?.title ?? d.title,
      episode: req.series?.episode ?? 1,
      cast: req.series?.cast ?? [...new Set(d.lines.map((l) => l.speaker.trim()))],
      summary: d.summary,
      lines: d.lines.map((l) => ({ speaker: l.speaker.trim(), en: l.en, ko: l.ko })),
    },
  };
}

export type Usage = Array<Record<string, number | null | undefined>>;

export class PackGenerationError extends Error {
  constructor(
    message: string,
    readonly problems: string[] = [],
    /** 실패하기까지 쓴 토큰 (비용 로그용) */
    readonly usage: Usage = [],
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
  const usage: Usage = [];

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let response;
    try {
      response = await client.beta.messages.parse({
        model: MODEL,
        max_tokens: 16000,
        // 정책상 거절되면 서버에서 다른 모델로 이어서 처리 (거절 사유별 자동 선택)
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        // 매일 바뀌는 사용자 메시지가 아니라 고정된 시스템 프롬프트를 캐시한다
        system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
        output_config: { effort: "medium", format: betaZodOutputFormat(GeneratedPack) },
        messages: [{ role: "user", content: buildUserPrompt(req) + retryNote(problems) }],
      });
    } catch (e) {
      // SDK 가 응답을 스키마로 읽다 실패한 경우(출력이 잘림 등)는 API 오류가 아니다: 짧게 다시 만든다
      if (e instanceof Anthropic.AnthropicError && !(e instanceof Anthropic.APIError)) {
        problems = ["응답이 잘렸거나 형식에 맞지 않았습니다. 문장을 더 짧게, 형식을 정확히 지켜 주세요."];
        continue;
      }
      if (e instanceof Error) Object.assign(e, { usage });
      throw e;
    }
    usage.push({
      input: response.usage.input_tokens,
      output: response.usage.output_tokens,
      cacheRead: response.usage.cache_read_input_tokens,
      cacheWrite: response.usage.cache_creation_input_tokens,
    });

    if (response.stop_reason === "refusal") {
      throw new PackGenerationError("Claude 가 요청을 거절했습니다", [], usage);
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
  throw new PackGenerationError("규칙에 맞는 팩을 만들지 못했습니다", problems, usage);
}
