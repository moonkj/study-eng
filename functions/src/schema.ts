import { z } from "zod";

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
        en: z.string().describe("오늘 단어 하나를 포함한 실생활 짧은 문장 (12단어 이하, 단어 예문과 다른 새 문장)"),
        ko: z.string(),
        focus: z.string().describe("문장에 쓰인 오늘 단어 (words[].word 중 하나와 정확히 같게)"),
      }),
    )
    .describe("요청한 따라 말하기 문장 수만큼"),
  quiz: z
    .array(
      z.object({
        prompt: z.string().describe("한국어 문장"),
        choices: z.array(z.string()).describe("영어 보기 3개. 정답 1개 + 한국인이 자주 하는 실수로 만든, 확실히 틀린 오답 2개"),
        answer_index: z.number().int().describe("정답 보기 index (0부터)"),
        explanation: z.string().describe("왜 정답인지, 오답은 왜 틀렸는지 1~2문장 한국어"),
        review_of: z.string().describe("복습 문제면 review 항목의 id, 오늘 내용이면 빈 문자열"),
        tests: z.string().describe("오늘 내용 문제면 이 문제가 다루는 오늘 표현의 pattern 또는 단어를 그대로, 복습 문제면 빈 문자열"),
      }),
    )
    .describe("오늘 내용 6문항 + 복습 항목마다 1문항"),
});
export type GeneratedPack = z.infer<typeof GeneratedPack>;
