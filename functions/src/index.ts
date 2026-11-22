import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";

import { handleDailyPack } from "./handler.js";

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
    client ??= new Anthropic({ apiKey: anthropicKey.value(), timeout: 150_000 });
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
