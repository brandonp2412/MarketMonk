const ORIGIN = "https://brandonp2412.github.io";
const PREFIX = "/api/finance";
const UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/125 Safari/537.36";
function reply(data, status = 200, cors = true) {
  return Response.json(data, {status, headers: {
    ...(cors ? {"Access-Control-Allow-Origin": ORIGIN, "Vary": "Origin"} : {}),
    "Cache-Control": status === 200 ? "public, max-age=60" : "no-store",
    "X-Content-Type-Options": "nosniff"
  }});
}
export function parseRequest(url) {
  const query = url.searchParams;
  if (url.search.length > 512 || new Set(query.keys()).size !== [...query.keys()].length) throw Error("Invalid query");
  if (url.pathname === PREFIX + "/v1/finance/search") {
    const q = query.get("q")?.trim();
    if (!q || q.length > 50 || [...query.keys()].some(k => k !== "q")) throw Error("Invalid search");
    return {path: "/v1/finance/search", query, q};
  }
  const m = url.pathname.match(/^\/api\/finance\/v8\/finance\/chart\/([A-Za-z0-9._^=%-]{1,144})$/);
  if (!m) throw Error("Unsupported route");
  const symbol = decodeURIComponent(m[1]);
  if (!/^[A-Za-z0-9._^=-]{1,48}$/.test(symbol)) throw Error("Invalid symbol");
  if ([...query.keys()].some(k => !["range", "interval", "period1", "period2", "includePrePost"].includes(k))) throw Error("Invalid query");
  const interval = query.get("interval") || "1d";
  if (!["1m","2m","5m","15m","30m","1d","1wk","1mo"].includes(interval)) throw Error("Invalid interval");
  const range = query.get("range");
  if (range && !/^\d{1,3}(d|mo|y)$/.test(range)) throw Error("Invalid range");
  for (const key of ["period1","period2"]) if (query.has(key) && !/^\d{1,11}$/.test(query.get(key))) throw Error("Invalid timestamp");
  if (query.has("includePrePost") && !["true","false"].includes(query.get("includePrePost"))) throw Error("Invalid pre/post flag");
  return {path: "/v8/finance/chart/" + encodeURIComponent(symbol), query, symbol, interval};
}
async function upstream(url) {
  return fetch(url, {headers: {"User-Agent": UA, Accept: "application/json, text/plain, */*", Origin: "https://finance.yahoo.com"}, redirect: "manual"});
}
export default {async fetch(request, env, ctx) {
  if (request.headers.get("Origin") !== ORIGIN) return reply({error:"Origin not permitted"},403,false);
  if (request.method !== "GET") return reply({error:"GET required"},405);
  let spec;
  try {spec = parseRequest(new URL(request.url));} catch {return reply({error:"Invalid finance request"},422);}
  const key = new Request(request.url);
  const cache = globalThis.caches?.default;
  if (cache) {
    const hit = await cache.match(key);
    if (hit) return hit;
  }
  try {
    let result;
    let lastStatus = 503;
    for (const host of ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]) {
      try {
        const yahoo = await upstream("https://" + host + spec.path + "?" + spec.query);
        if (!yahoo.ok) {
          lastStatus = [404, 429].includes(yahoo.status) ? yahoo.status : 503;
          continue;
        }
        if (!yahoo.headers.get("content-type")?.includes("application/json")) continue;
        const headers = {"Access-Control-Allow-Origin":ORIGIN,"Vary":"Origin","Content-Type":"application/json","Cache-Control":"public, max-age=60","X-Content-Type-Options":"nosniff"};
        result = new Response(yahoo.body,{headers});
        break;
      } catch {}
    }
    if (!result) return reply({error:"Market data unavailable"},lastStatus);
    if (cache) ctx.waitUntil(cache.put(key,result.clone()).catch(()=>{}));
    return result;
  } catch {return reply({error:"Market data unavailable"},503);}
}};
