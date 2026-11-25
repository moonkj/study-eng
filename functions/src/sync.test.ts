import assert from "node:assert/strict";
import { test } from "node:test";

import { handleSync, MemorySyncStorage } from "./sync.js";

const auth = "Bearer tok";
const call = (storage: MemorySyncStorage, body: unknown, authorization = auth) =>
  handleSync({ method: "POST", authorization, body, appToken: "tok", storage });

test("sync: 토큰이 없으면 거절", async () => {
  const r = await call(new MemorySyncStorage(), { op: "get" }, "Bearer nope");
  assert.equal(r.status, 401);
});

test("sync: 처음에는 비어 있고, 버전이 맞으면 저장하고 버전이 오른다", async () => {
  const s = new MemorySyncStorage();
  assert.deepEqual((await call(s, { op: "get" })).body, { version: 0, data: null });
  const put = await call(s, { op: "put", baseVersion: 0, data: '{"a":1}' });
  assert.equal(put.status, 200);
  assert.deepEqual(put.body, { version: 1 });
  assert.deepEqual((await call(s, { op: "get" })).body, { version: 1, data: '{"a":1}' });
});

test("sync: 다른 기기가 먼저 바꿨으면 409 와 지금 문서를 돌려준다", async () => {
  const s = new MemorySyncStorage();
  await call(s, { op: "put", baseVersion: 0, data: '{"a":1}' });
  const stale = await call(s, { op: "put", baseVersion: 0, data: '{"b":2}' });
  assert.equal(stale.status, 409);
  assert.deepEqual(stale.body, { version: 1, data: '{"a":1}' });
});

test("sync: 형식이 틀리면 400", async () => {
  const r = await call(new MemorySyncStorage(), { op: "put", baseVersion: -1, data: "" });
  assert.equal(r.status, 400);
});
