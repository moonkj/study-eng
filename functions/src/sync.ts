import { timingSafeEqual } from "node:crypto";

import { z } from "zod";

import type { HandlerResult } from "./handler.js";

/** 기기 간 동기화: 학습 기록 전체(앱 저장 JSON 문자열) 하나를 버전과 함께 둔다 */
export interface SyncDoc {
  version: number;
  data: string;
}

/** 저장소 (실서버는 Firestore, 테스트는 메모리) */
export interface SyncStorage {
  get(): Promise<SyncDoc | null>;
  /** 지금 버전이 [baseVersion] 일 때만 바꾼다. 바꿨으면 새 버전, 아니면 지금 문서 */
  putIf(baseVersion: number, data: string): Promise<{ ok: true; version: number } | { ok: false; current: SyncDoc | null }>;
}

/** Firestore 문서 한 개 제한(1MiB)보다 작게 */
export const MAX_SYNC_CHARS = 900_000;

export const SyncRequest = z.discriminatedUnion("op", [
  z.object({ op: z.literal("get") }),
  z.object({
    op: z.literal("put"),
    /** 이 기기가 마지막으로 맞춘 서버 버전 (처음이면 0) */
    baseVersion: z.number().int().min(0),
    data: z.string().min(2).max(MAX_SYNC_CHARS),
  }),
]);

function tokenMatches(header: string | undefined, expected: string): boolean {
  const given = header?.startsWith("Bearer ") ? header.slice(7) : "";
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * POST /sync
 * - Authorization: Bearer <APP_TOKEN>
 * - { op: "get" } → { version, data | null }
 * - { op: "put", baseVersion, data } → 200 { version } / 다른 기기가 먼저 바꿨으면 409 { version, data } (앱이 합쳐서 다시 보낸다)
 */
export async function handleSync(opts: {
  method: string;
  authorization: string | undefined;
  body: unknown;
  appToken: string;
  storage: SyncStorage;
  log?: (msg: string, data?: unknown) => void;
}): Promise<HandlerResult> {
  const log = opts.log ?? (() => {});
  if (opts.method !== "POST") return { status: 405, body: { error: "POST only" } };
  if (!opts.appToken || !tokenMatches(opts.authorization, opts.appToken)) {
    return { status: 401, body: { error: "unauthorized" } };
  }
  const parsed = SyncRequest.safeParse(opts.body);
  if (!parsed.success) {
    return { status: 400, body: { error: "invalid request", issues: parsed.error.issues.slice(0, 5) } };
  }
  const req = parsed.data;
  try {
    if (req.op === "get") {
      const doc = await opts.storage.get();
      return { status: 200, body: { version: doc?.version ?? 0, data: doc?.data ?? null } };
    }
    const r = await opts.storage.putIf(req.baseVersion, req.data);
    if (r.ok) {
      log("sync saved", { version: r.version, chars: req.data.length });
      return { status: 200, body: { version: r.version } };
    }
    return { status: 409, body: { version: r.current?.version ?? 0, data: r.current?.data ?? null } };
  } catch (e) {
    log("sync storage error", { message: e instanceof Error ? e.message : String(e) });
    return { status: 503, body: { error: "temporarily unavailable, retry later" } };
  }
}

/** 메모리 저장소 (테스트·로컬 개발용) */
export class MemorySyncStorage implements SyncStorage {
  doc: SyncDoc | null = null;
  async get() {
    return this.doc;
  }
  async putIf(baseVersion: number, data: string) {
    const now = this.doc?.version ?? 0;
    if (now !== baseVersion) return { ok: false as const, current: this.doc };
    this.doc = { version: now + 1, data };
    return { ok: true as const, version: now + 1 };
  }
}
