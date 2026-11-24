import { z } from "zod";

/** 퀴즈 오답 유형 (앱의 kErrorTypes 와 같게) */
export const ERROR_TYPES = ["word_choice", "grammar_form", "preposition", "word_order", "collocation", "meaning"] as const;
export const ErrorType = z.enum(ERROR_TYPES);
export type ErrorType = z.infer<typeof ErrorType>;

/** 앱 → 서버: 오늘의 팩을 만들 때 필요한 학습자 정보 */
export const PackRequest = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  /** 전체 레벨 (예: "B1.2") */
  level: z.string().max(8),
  /** 오늘 콘텐츠 난이도 (자동 조정 결과, 예: "B1.3") */
  contentLevel: z.string().max(8),
  skills: z.record(z.enum(["vocabulary", "grammar", "listening", "speaking"]), z.string().max(8)),
  /** 가장 약한 영역 */
  focusSkill: z.enum(["vocabulary", "grammar", "listening", "speaking"]),
  speakingSentences: z.number().int().min(5).max(15),
  /** 최근에 배운 표현·단어 (중복 방지) */
  avoid: z.object({
    // 항목 길이도 제한한다 (긴 문자열로 입력 토큰 비용이 커지지 않게)
    expressions: z.array(z.string().max(80)).max(200),
    words: z.array(z.string().max(60)).max(400),
  }),
  /** 오늘 복습할 항목 (간격 반복으로 돌아온 것) */
  review: z
    .array(
      z.object({
        id: z.string().max(80),
        kind: z.enum(["expression", "word"]),
        text: z.string().max(80),
        meaning: z.string().max(120),
      }),
    )
    .max(6),
  /** 최근 14일 주제 (겹치지 않게). 아래 필드는 모두 선택: 예전 앱 요청도 그대로 받는다 */
  recentTopics: z.array(z.string().max(40)).max(14).optional(),
  /** 주제 지도에서 고른 오늘 상황 (한국어) */
  topicHint: z.string().max(80).optional(),
  /** 자주 틀리는 오답 유형 (최대 2개): 퀴즈 2~3문항이 이 유형을 노린다 */
  weakErrorTypes: z.array(ErrorType).max(2).optional(),
  /** 주간 시리즈 대화: 같은 등장인물·제목으로 이어 간다 */
  series: z
    .object({
      title: z.string().min(1).max(60),
      episode: z.number().int().min(1).max(999),
      cast: z.array(z.string().min(1).max(20)).min(1).max(4),
      lastSummary: z.string().max(300).optional(),
    })
    .optional(),
});
export type PackRequest = z.infer<typeof PackRequest>;

const Example = z.object({
  en: z.string().describe("자연스러운 구어체 영어 문장"),
  ko: z.string().describe("자연스러운 한국어 번역 (직역 금지)"),
});

/** Claude 가 만드는 오늘의 팩 (구조화 출력 스키마) */
export const GeneratedPack = z.object({
  topic: z.string().describe("오늘의 상황 주제, 한국어 2~6자 · 2~6자 형식 (예: '출근길 · 일상')"),
  expressions: z
    .array(
      z.object({
        pattern: z.string().describe("회화 패턴. 빈칸은 ~ 로 표시 (예: \"I've been meaning to ~\")"),
        highlight: z.string().describe("pattern 안에서 형광펜 칠할 핵심 부분, pattern 의 부분 문자열"),
        meaning: z.string().describe("한국어 뜻 (예: '계속 ~하려고 했어')"),
        usage: z.string().describe("언제 쓰는지 1~2문장, 친근한 존댓말"),
        examples: z.array(Example).describe("예문 정확히 2개"),
        compare_en: z.string().describe("헷갈리기 쉬운 비슷한 표현 (영어)"),
        compare_ko: z.string().describe("그 표현과의 차이 한 문장 (한국어)"),
        pron_ko: z
          .string()
          .describe("highlight 부분을 실제 대화 속도로 이어 말한 한글 발음, 강세 음절은 [대괄호] (예: been meaning to → 빈 [미]닝 트)"),
        linking: z
          .string()
          .describe("이어 말하기·약하게 말하기 요령 한 문장, 친근한 존댓말 (예: to 는 '투'가 아니라 '트'처럼 약하게 붙여요)"),
      }),
    )
    .describe("정확히 3개"),
  words: z
    .array(
      z.object({
        word: z.string().describe("단어 또는 짧은 구 (소문자)"),
        pos_en: z.string().describe("noun, verb, adjective, adverb, phrasal verb, phrase 중 하나"),
        pos_ko: z.string().describe("명사, 동사, 형용사, 부사, 구동사, 표현 중 하나"),
        meaning: z.string().describe("한국어 뜻, 쉼표로 1~2개"),
        ipa: z.string().describe("미국 일반 발음(GA) IPA, 슬래시 포함 (예: /ˈæk.ʃu.ə.li/)"),
        pron_ko: z.string().describe("실제 대화 속도의 한글 발음, 강세 음절은 [대괄호] (예: [액]슈얼리)"),
        example: Example.describe("word 를 그대로 포함한 예문"),
        level: z.string().describe("CEFR (A1~C1)"),
      }),
    )
    .describe("정확히 10개"),
  sentences: z
    .array(
      z.object({
        en: z.string().describe("오늘 단어 하나(또는 오늘 표현 하나)를 포함한 실생활 짧은 문장 (12단어 이하, 예문과 다른 새 문장)"),
        ko: z.string(),
        focus: z
          .string()
          .describe("문장에 쓰인 오늘 단어(words[].word 중 하나) 또는 오늘 표현의 highlight, 원문과 정확히 같게"),
      }),
    )
    .describe("요청한 따라 말하기 문장 수만큼"),
  quiz: z
    .array(
      z.object({
        prompt: z.string().describe("한국어 문장"),
        choices: z.array(z.string()).describe("영어 보기 3개. 정답 1개 + 한국인이 자주 하는 실수로 만든, 확실히 틀린 오답 2개"),
        answer_index: z.number().int().describe("정답 보기 index (0부터)"),
        explanation: z
          .string()
          .describe("규칙 + 대비 쌍, 1~2문장 한국어 (예: 'arrive 뒤엔 at/in 이 필요해요. arrive at the station (O) / arrive the station (X)')"),
        error_type: ErrorType.describe("오답 2개가 노리는 실수 유형"),
        review_of: z.string().describe("복습 문제면 review 항목의 id, 오늘 내용이면 빈 문자열"),
        tests: z.string().describe("오늘 내용 문제면 이 문제가 다루는 오늘 표현의 pattern 또는 단어를 그대로, 복습 문제면 빈 문자열"),
      }),
    )
    .describe("오늘 내용 6문항 + 복습 항목마다 1문항"),
  dialogue: z
    .object({
      title: z.string().describe("시리즈 제목 (주어진 시리즈가 있으면 그대로, 없으면 새로 짓기, 영어 2~5단어)"),
      summary: z.string().describe("이번 회 줄거리 한 문장 (한국어, 다음 회에 이어 쓰기 위함)"),
      lines: z
        .array(
          z.object({
            speaker: z.string().describe("등장인물 이름 (cast 중 하나)"),
            en: z.string().describe("짧은 구어체 대사"),
            ko: z.string().describe("자연스러운 한국어 번역"),
          }),
        )
        .describe("4~6줄, 오늘 표현을 대사에 넣기"),
    })
    .describe("오늘 표현으로 만든 짧은 시리즈 대화"),
});
export type GeneratedPack = z.infer<typeof GeneratedPack>;

/** 앱 → 서버: '내 상황으로 말하기' 교정 요청 */
export const CorrectRequest = z.object({
  expression: z.object({
    pattern: z.string().min(1).max(80),
    highlight: z.string().min(1).max(60),
    meaning: z.string().max(120),
  }),
  /** 학습자가 고른 상황 (한국어, 선택) */
  situationKo: z.string().max(200).optional(),
  /** 학습자가 쓴 영어 문장 (공백만 있으면 거절) */
  sentence: z.string().trim().min(1).max(300),
  level: z.string().max(8),
});
export type CorrectRequest = z.infer<typeof CorrectRequest>;

/** Claude 가 만드는 교정 결과 (구조화 출력 스키마). null 대신 "none" 을 쓰고 앱 형식으로 바꿀 때 null 로 둔다 */
export const GeneratedCorrection = z.object({
  ok: z.boolean().describe("문법·자연스러움에 문제가 없으면 true (사소한 구두점은 무시)"),
  corrected: z.string().describe("자연스럽게 고친 문장. 문제가 없으면 원문 그대로"),
  notes: z.string().describe("한국어 1~2문장, 친절한 존댓말. 고친 이유 또는 칭찬"),
  error_type: z.enum([...ERROR_TYPES, "none"]).describe("가장 큰 실수 유형, 문제가 없으면 none"),
  used_expression: z.boolean().describe("문장이 오늘 표현(highlight)을 알맞게 썼으면 true"),
});
export type GeneratedCorrection = z.infer<typeof GeneratedCorrection>;

/** TOEIC Speaking 문제 유형 */
export const TOEIC_TASKS = ["read_aloud", "picture", "respond", "info", "opinion"] as const;
export const ToeicTask = z.enum(TOEIC_TASKS);
export type ToeicTask = z.infer<typeof ToeicTask>;

/** TOEIC Speaking 레벨 (낮은 순) */
export const TOEIC_LEVELS = ["NL", "NM", "NH", "IL", "IM1", "IM2", "IM3", "IH", "AL"] as const;
export const ToeicLevel = z.enum(TOEIC_LEVELS);

/** 학습자가 고르는 목표 레벨 (점수 110/130/140/160/180) */
export const TOEIC_TARGETS = ["IM1", "IM2", "IM3", "IH", "AL"] as const;
export const ToeicTarget = z.enum(TOEIC_TARGETS);
export type ToeicTarget = z.infer<typeof ToeicTarget>;

/** 앱 → 서버: TOEIC Speaking 한 문항 채점 요청 */
export const GradeRequest = z.object({
  task: ToeicTask,
  /** 목표 레벨 (없으면 IM3) */
  target: ToeicTarget.default("IM3"),
  /** 화면에 보여 준 내용: 지문 / 사진 설명 맥락 / 상황+질문 / 표+질문 / 의견 질문 */
  prompt: z.string().trim().min(1).max(3000),
  /** 모범 답안 또는 (read_aloud) 지문 자체 */
  reference: z.string().max(3000).optional(),
  /** 학습자 답변 음성 인식 결과 (비거나 일부만 있을 수 있음) */
  transcript: z.string().max(2000),
  /** 실제로 말한 시간(초) */
  seconds: z.number().min(0).max(600),
  /** 답변 제한 시간(초) */
  limitSeconds: z.number().positive().max(600),
});
export type GradeRequest = z.infer<typeof GradeRequest>;

/** Claude 가 만드는 채점 결과 (구조화 출력 스키마). 점수 범위·개수는 서버가 다시 맞춘다 */
export const GeneratedGrade = z.object({
  score: z.number().int().describe("ETS 문항 점수: read_aloud·picture·respond·info 는 0~3, opinion 은 0~5"),
  level: ToeicLevel.describe("이 답변이 보여 주는 대략적인 TOEIC Speaking 레벨"),
  target_met: z.boolean().describe("이 답변이 이 문항에서 목표 레벨에 기대되는 수준을 충족하면 true"),
  summary_ko: z.string().describe("한국어 1~2문장 총평, 격려하되 솔직하게"),
  good_ko: z.array(z.string()).describe("잘한 점 최대 2개 (한국어, 짧게)"),
  fixes: z
    .array(
      z.object({
        from: z.string().describe("transcript 에 있는 틀린·어색한 영어 부분 그대로"),
        to: z.string().describe("고친 영어"),
        why_ko: z.string().describe("고친 이유 한 문장 (한국어)"),
      }),
    )
    .describe("구체적인 영어 교정 최대 3개. 음성 인식 오류로 보이는 것은 넣지 않는다"),
  improved: z.string().describe("학습자 답변을 목표 레벨에 맞게 다시 쓴 영어 답변, 학습자의 생각은 유지"),
  next_tip_ko: z.string().describe("다음에 바로 해 볼 수 있는 팁 하나 (한국어)"),
});
export type GeneratedGrade = z.infer<typeof GeneratedGrade>;
