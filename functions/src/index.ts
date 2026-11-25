import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";

import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { handleCorrect, handleDailyPack, handleGrade } from "./handler.js";
import { handleSync, type SyncStorage } from "./sync.js";

/** Claude API 키와 앱 전용 토큰은 Secret Manager 에만 둔다 (firebase functions:secrets:set ...). */
const anthropicKey = defineSecret("ANTHROPIC_API_KEY");
const appToken = defineSecret("APP_TOKEN");

let client: Anthropic | undefined;

export const dailyPack = onRequest(
  {
    region: "asia-northeast3", // 서울
    secrets: [anthropicKey, appToken],
    timeoutSeconds: 180,
    memory: "512MiB",
    maxInstances: 2,
    cors: true,
  },
  async (req, res) => {
    // 함수 제한 시간(180초) 안에 두 번 시도할 수 있게: 시도당 75초, SDK 자동 재시도는 끈다
    client ??= new Anthropic({ apiKey: anthropicKey.value(), timeout: 75_000, maxRetries: 0 });
    const result = await handleDailyPack({
      method: req.method,
      authorization: req.get("authorization"),
      body: req.body,
      appToken: appToken.value(),
      client,
      log: (msg, data) => logger.info(msg, data),
    });
    res.status(result.status).json(result.body);
  },
);

/** '내 상황으로 말하기' 교정: 한 번만 짧게 묻는다 (시도당 30초) */
let correctClient: Anthropic | undefined;

export const correct = onRequest(
  {
    region: "asia-northeast3",
    secrets: [anthropicKey, appToken],
    timeoutSeconds: 45,
    memory: "256MiB",
    maxInstances: 2,
    cors: true,
  },
  async (req, res) => {
    correctClient ??= new Anthropic({ apiKey: anthropicKey.value(), timeout: 30_000, maxRetries: 0 });
    const result = await handleCorrect({
      method: req.method,
      authorization: req.get("authorization"),
      body: req.body,
      appToken: appToken.value(),
      client: correctClient,
      log: (msg, data) => logger.info(msg, data),
    });
    res.status(result.status).json(result.body);
  },
);

/** TOEIC Speaking 채점: 한 번만 짧게 묻는다 (시도당 30초) */
let gradeClient: Anthropic | undefined;

export const grade = onRequest(
  {
    region: "asia-northeast3",
    secrets: [anthropicKey, appToken],
    timeoutSeconds: 45,
    memory: "256MiB",
    maxInstances: 2,
    cors: true,
  },
  async (req, res) => {
    gradeClient ??= new Anthropic({ apiKey: anthropicKey.value(), timeout: 30_000, maxRetries: 0 });
    const result = await handleGrade({
      method: req.method,
      authorization: req.get("authorization"),
      body: req.body,
      appToken: appToken.value(),
      client: gradeClient,
      log: (msg, data) => logger.info(msg, data),
    });
    res.status(result.status).json(result.body);
  },
);

/** 기기 간 동기화 (아이폰·아이패드). Firestore 문서 하나(todaye/sync)에 학습 기록 전체를 버전과 함께 둔다 */
let syncStorage: SyncStorage | undefined;

function firestoreSyncStorage(): SyncStorage {
  if (getApps().length === 0) initializeApp();
  const ref = getFirestore().collection("todaye").doc("sync");
  return {
    async get() {
      const snap = await ref.get();
      if (!snap.exists) return null;
      const d = snap.data()!;
      return { version: d.version as number, data: d.data as string };
    },
    async putIf(baseVersion, data) {
      return getFirestore().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const now = snap.exists ? (snap.data()!.version as number) : 0;
        if (now !== baseVersion) {
          return { ok: false as const, current: snap.exists ? { version: now, data: snap.data()!.data as string } : null };
        }
        tx.set(ref, { version: now + 1, data, updatedAt: FieldValue.serverTimestamp() });
        return { ok: true as const, version: now + 1 };
      });
    },
  };
}

export const sync = onRequest(
  {
    region: "asia-northeast3",
    secrets: [appToken],
    // 앱 토큰으로 직접 검사한다 (Google 로그인 없이 호출)
    invoker: "public",
    timeoutSeconds: 20,
    memory: "256MiB",
    maxInstances: 2,
    cors: true,
  },
  async (req, res) => {
    syncStorage ??= firestoreSyncStorage();
    const result = await handleSync({
      method: req.method,
      authorization: req.get("authorization"),
      body: req.body,
      appToken: appToken.value(),
      storage: syncStorage,
      log: (msg, data) => logger.info(msg, data),
    });
    res.status(result.status).json(result.body);
  },
);
