import { timingSafeEqual } from "node:crypto";

import Anthropic from "@anthropic-ai/sdk";

import { generateCorrection } from "./correct.js";
import { generateGrade } from "./grade.js";
import { generatePack, PackGenerationError } from "./pack.js";
import { CorrectRequest, GradeRequest, PackRequest } from "./schema.js";

export interface HandlerResult {
  status: number;
  body: unknown;
}

type Client = Pick<Anthropic, "beta">;

function tokenMatches(header: string | undefined, expected: string): boolean {
  const given = header?.startsWith("Bearer ") ? header.slice(7) : "";
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

interface HandlerOpts {
  method: string;
  authorization: string | undefined;
  body: unknown;
  appToken: string;
  client: Client;
  log?: (msg: string, data?: unknown) => void;
}

/** 메서드·토큰 검사. 통과하면 null */
function checkAccess(opts: HandlerOpts): HandlerResult | null {
  if (opts.method !== "POST") return { status: 405, body: { error: "POST only" } };
  if (!opts.appToken || !tokenMatches(opts.authorization, opts.appToken)) {
    return { status: 401, body: { error: "unauthorized" } };
  }
  return null;
}

/** 생성 중 오류를 HTTP 응답으로 바꾼다 (팩·교정 공통). 모르는 오류는 다시 던진다 */
function errorResult(e: unknown, log: (msg: string, data?: unknown) => void, what: string): HandlerResult {
  if (e instanceof PackGenerationError) {
    log(`${what} rejected`, { message: e.message, problems: e.problems, usage: e.usage });
    return { status: 502, body: { error: e.message, problems: e.problems } };
  }
  // 일시적인 문제(요청 한도, 과부하, 시간 초과, 연결 끊김)는 503: 앱이 "잠시 뒤에 다시"로 안내한다
  if (e instanceof Anthropic.RateLimitError) return { status: 503, body: { error: "rate limited, retry later" } };
  if (e instanceof Anthropic.APIConnectionError || (e instanceof Anthropic.APIError && (e.status === 529 || (e.status ?? 0) >= 500))) {
    log("anthropic temporary error", { status: e instanceof Anthropic.APIError ? e.status : undefined });
    return { status: 503, body: { error: "temporarily unavailable, retry later" } };
  }
  if (e instanceof Anthropic.AuthenticationError) {
    log("anthropic auth failed", { status: e.status, message: e.message });
    return { status: 500, body: { error: "server misconfigured" } };
  }
  if (e instanceof Anthropic.APIError) {
    log("anthropic api error", { status: e.status, message: e.message });
    return { status: 502, body: { error: "upstream error" } };
  }
  throw e;
}

/**
 * POST /dailyPack
 * - Authorization: Bearer <APP_TOKEN> (개인용 앱 전용 토큰)
 * - body: PackRequest
 */
export async function handleDailyPack(opts: HandlerOpts): Promise<HandlerResult> {
  const log = opts.log ?? (() => {});
  const denied = checkAccess(opts);
  if (denied) return denied;

  const parsed = PackRequest.safeParse(opts.body);
  if (!parsed.success) {
    return { status: 400, body: { error: "invalid request", issues: parsed.error.issues.slice(0, 5) } };
  }

  try {
    const { pack, usage, attempts } = await generatePack(opts.client, parsed.data);
    log("pack generated", { date: parsed.data.date, attempts, usage });
    return { status: 200, body: pack };
  } catch (e) {
    return errorResult(e, log, "pack");
  }
}

/**
 * POST /correct — '내 상황으로 말하기' 한 문장 교정
 * - Authorization: Bearer <APP_TOKEN>
 * - body: CorrectRequest → { ok, corrected, notes, errorType, usedExpression }
 */
export async function handleCorrect(opts: HandlerOpts): Promise<HandlerResult> {
  const log = opts.log ?? (() => {});
  const denied = checkAccess(opts);
  if (denied) return denied;

  const parsed = CorrectRequest.safeParse(opts.body);
  if (!parsed.success) {
    return { status: 400, body: { error: "invalid request", issues: parsed.error.issues.slice(0, 5) } };
  }

  try {
    const { correction, usage } = await generateCorrection(opts.client, parsed.data);
    log("correction generated", { ok: correction.ok, usage });
    return { status: 200, body: correction };
  } catch (e) {
    return errorResult(e, log, "correction");
  }
}

/**
 * POST /grade — TOEIC Speaking 한 문항 채점
 * - Authorization: Bearer <APP_TOKEN>
 * - body: GradeRequest → { score, maxScore, level, targetMet, summaryKo, goodKo, fixes, improved, nextTipKo }
 */
export async function handleGrade(opts: HandlerOpts): Promise<HandlerResult> {
  const log = opts.log ?? (() => {});
  const denied = checkAccess(opts);
  if (denied) return denied;

  const parsed = GradeRequest.safeParse(opts.body);
  if (!parsed.success) {
    return { status: 400, body: { error: "invalid request", issues: parsed.error.issues.slice(0, 5) } };
  }

  try {
    const { grade, usage } = await generateGrade(opts.client, parsed.data);
    log("grade generated", { task: parsed.data.task, score: grade.score, usage });
    return { status: 200, body: grade };
  } catch (e) {
    return errorResult(e, log, "grade");
  }
}
