import { timingSafeEqual } from "node:crypto";

import Anthropic from "@anthropic-ai/sdk";

import { generatePack, PackGenerationError } from "./pack.js";
import { PackRequest } from "./schema.js";

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

/**
 * POST /dailyPack
 * - Authorization: Bearer <APP_TOKEN> (개인용 앱 전용 토큰)
 * - body: PackRequest
 */
export async function handleDailyPack(opts: {
  method: string;
  authorization: string | undefined;
  body: unknown;
  appToken: string;
  client: Client;
  log?: (msg: string, data?: unknown) => void;
}): Promise<HandlerResult> {
  const log = opts.log ?? (() => {});
  if (opts.method !== "POST") return { status: 405, body: { error: "POST only" } };
  if (!opts.appToken || !tokenMatches(opts.authorization, opts.appToken)) {
    return { status: 401, body: { error: "unauthorized" } };
  }

  const parsed = PackRequest.safeParse(opts.body);
  if (!parsed.success) {
    return { status: 400, body: { error: "invalid request", issues: parsed.error.issues.slice(0, 5) } };
  }

  try {
    const { pack, usage, attempts } = await generatePack(opts.client, parsed.data);
    log("pack generated", { date: parsed.data.date, attempts, usage });
    return { status: 200, body: pack };
  } catch (e) {
    if (e instanceof PackGenerationError) {
      log("pack rejected", { message: e.message, problems: e.problems, usage: e.usage });
      return { status: 502, body: { error: e.message, problems: e.problems } };
    }
    // 일시적인 문제(요청 한도, 과부하, 시간 초과, 연결 끊김)는 503: 앱이 "잠시 뒤에 다시"로 안내한다
    if (e instanceof Anthropic.RateLimitError) return { status: 503, body: { error: "rate limited, retry later" } };
    if (e instanceof Anthropic.APIConnectionError || (e instanceof Anthropic.APIError && (e.status === 529 || (e.status ?? 0) >= 500))) {
      log("anthropic temporary error", { status: e instanceof Anthropic.APIError ? e.status : undefined });
      return { status: 503, body: { error: "temporarily unavailable, retry later" } };
    }
    if (e instanceof Anthropic.AuthenticationError) {
      log("anthropic auth failed");
      return { status: 500, body: { error: "server misconfigured" } };
    }
    if (e instanceof Anthropic.APIError) {
      log("anthropic api error", { status: e.status, message: e.message });
      return { status: 502, body: { error: "upstream error" } };
    }
    throw e;
  }
}
