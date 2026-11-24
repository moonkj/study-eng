import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";

import { handleCorrect, handleDailyPack } from "./handler.js";

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
