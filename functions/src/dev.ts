/**
 * 로컬 개발 서버: 배포 없이 앱과 연결해 보기.
 *   ANTHROPIC_API_KEY=... APP_TOKEN=dev-token npm run dev
 *   flutter run --dart-define=CONTENT_API_URL=http://localhost:8787/dailyPack --dart-define=CONTENT_API_TOKEN=dev-token
 */
import { createServer } from "node:http";

import Anthropic from "@anthropic-ai/sdk";

import { handleDailyPack } from "./handler.js";

const port = Number(process.env.PORT ?? 8787);
const appToken = process.env.APP_TOKEN ?? "";
if (!appToken) {
  console.error("APP_TOKEN 환경 변수를 설정해 주세요.");
  process.exit(1);
}
if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_AUTH_TOKEN) {
  console.warn("경고: ANTHROPIC_API_KEY 가 없어요. `ant auth login` 프로필이 없다면 팩 생성이 실패합니다.");
}
const client = new Anthropic({ timeout: 75_000, maxRetries: 0 });

createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "authorization, content-type");
  if (req.method === "OPTIONS") {
    res.writeHead(204).end();
    return;
  }
  if (req.url !== "/dailyPack") {
    res.writeHead(404).end();
    return;
  }
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  let body: unknown = null;
  try {
    body = JSON.parse(Buffer.concat(chunks).toString("utf8") || "null");
  } catch {
    // 잘못된 JSON 은 handler 에서 400 으로 처리된다
  }
  try {
    const result = await handleDailyPack({
      method: req.method ?? "GET",
      authorization: req.headers.authorization,
      body,
      appToken,
      client,
      log: (msg, data) => console.log(msg, JSON.stringify(data ?? {})),
    });
    res.writeHead(result.status, { "content-type": "application/json; charset=utf-8" }).end(JSON.stringify(result.body));
  } catch (e) {
    console.error(e);
    res.writeHead(500).end(JSON.stringify({ error: "internal error" }));
  }
}).listen(port, () => console.log(`todaye dev server: http://localhost:${port}/dailyPack`));
