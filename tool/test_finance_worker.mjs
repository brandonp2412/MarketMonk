import test from "node:test";
import assert from "node:assert/strict";
import worker, {parseRequest} from "./finance_worker.mjs";

const base = "https://marketmonk-finance.marketmonk.workers.dev/api/finance";
const origin = "https://brandonp2412.github.io";

test("only finance search and chart routes are accepted", () => {
  assert.equal(parseRequest(new URL(base + "/v1/finance/search?q=ant")).q, "ant");
  assert.equal(parseRequest(new URL(base + "/v8/finance/chart/NZDUSD%3DX?interval=1d&range=1d")).symbol, "NZDUSD=X");
  for (const path of [
    "/../ibkr/v1/portfolio",
    "/v8/finance/chart/%2Fetc%2Fpasswd",
    "/v8/finance/chart/ANT?interval=1d&interval=1m",
    "/v1/finance/search?q=ant&url=https://example.com",
  ]) assert.throws(() => parseRequest(new URL(base + path)));
});

test("rejects other origins, methods and private paths before fetching", async () => {
  const fetch = globalThis.fetch;
  globalThis.fetch = () => { throw Error("must not fetch"); };
  try {
    assert.equal((await worker.fetch(new Request(base + "/v1/finance/search?q=ant"))).status, 403);
    assert.equal((await worker.fetch(new Request(base + "/v1/finance/search?q=ant", {method:"POST",headers:{Origin:origin}}))).status,405);
    assert.equal((await worker.fetch(new Request(base + "/../ibkr/v1/portfolio", {headers:{Origin:origin}}))).status,422);
  } finally { globalThis.fetch = fetch; }
});

test("fetches real upstream JSON and does not forward credentials", async () => {
  const fetch = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({url,options});
    if (calls.length === 1) return new Response("rate limited",{status:429});
    return Response.json({quotes:[{symbol:"ANT"}]});
  };
  try {
    const response = await worker.fetch(new Request(base + "/v1/finance/search?q=ant", {
      headers:{Origin:origin,Authorization:"Bearer private-test-token",Cookie:"private-test-cookie"}
    }));
    assert.equal(response.status,200);
    assert.deepEqual(await response.json(),{quotes:[{symbol:"ANT"}]});
    assert.equal(response.headers.get("Access-Control-Allow-Origin"),origin);
    assert.equal(calls.length,2);
    assert.equal(calls[0].url,"https://query1.finance.yahoo.com/v1/finance/search?q=ant");
    assert.equal(calls[1].url,"https://query2.finance.yahoo.com/v1/finance/search?q=ant");
    for (const call of calls) {
      assert.equal(call.options.redirect,"manual");
      const h = new Headers(call.options.headers);
      assert.equal(h.has("Authorization"),false);
      assert.equal(h.has("Cookie"),false);
    }
  } finally {globalThis.fetch = fetch;}
});

test("preserves a rate limit when the second upstream is unavailable", async () => {
  const original = globalThis.fetch;
  let n = 0;
  globalThis.fetch = async () => new Response("", {status: ++n === 1 ? 429 : 503});
  try {
    const result = await worker.fetch(new Request(base + "/v1/finance/search?q=ant", {headers:{Origin:origin}}));
    assert.equal(result.status,429);
    assert.equal(result.headers.get("Access-Control-Allow-Origin"),origin);
  } finally { globalThis.fetch = original; }
});
