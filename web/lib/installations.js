import { createHash, timingSafeEqual } from "node:crypto";

const TTL = 30 * 86400;
const PAGE = 50;
const ID = /^[a-f0-9]{32}$/;
const TOKEN = /^[a-f0-9]{64}$/;
const VERSION = /^(?:0|[1-9]\d{0,3})(?:\.(?:0|[1-9]\d{0,3})){2}$/;
const hash = value => createHash("sha256").update(value).digest("hex");

const heartbeat = [
  "local old=redis.call('GET',KEYS[2])",
  "local data=cjson.decode(ARGV[1])",
  "if old then local prior=cjson.decode(old); data.target=prior.target end",
  "redis.call('SET',KEYS[2],cjson.encode(data),'EX',ARGV[3])",
  "redis.call('ZADD',KEYS[1],data.seen,ARGV[2])",
  "return cjson.encode(data)"
].join("\n");

const dispatch = [
  "local count=0",
  "for i=1,#KEYS do",
  "  local old=redis.call('GET',KEYS[i])",
  "  if old then",
  "    local data=cjson.decode(old)",
  "    data.target=ARGV[1]",
  "    redis.call('SET',KEYS[i],cjson.encode(data),'KEEPTTL')",
  "    count=count+1",
  "  end",
  "end",
  "return count"
].join("\n");

function authorized(req, secret) {
  const header = req.headers.authorization;
  return typeof secret === "string" && TOKEN.test(secret) &&
    typeof header === "string" && header.startsWith("Bearer ") &&
    timingSafeEqual(Buffer.from(hash(header.slice(7))), Buffer.from(hash(secret)));
}

async function readBody(req) {
  let body = req.body;
  if (body === undefined) {
    const parts = [];
    let size = 0;
    for await (const part of req) {
      size += part.length;
      if (size > 8192) throw new Error("too large");
      parts.push(part);
    }
    body = Buffer.concat(parts).toString();
  }
  if (Buffer.isBuffer(body)) body = body.toString();
  if (typeof body === "string" && Buffer.byteLength(body) <= 8192) body = JSON.parse(body);
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("invalid body");
  return body;
}

export function installationHandler(db, secret, environment) {
  // The shared hash tag keeps multi-key Lua operations in one Redis cluster slot.
  const prefix = "{breakpoint-installations-" + environment + "}:";
  const index = prefix + "index";
  const key = id => prefix + "device:" + id;
  return async function handler(req, res) {
    const reply = (status, body) => {
      res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
      res.end(JSON.stringify(body));
    };
    const params = new URL(req.url, "http://localhost").searchParams;
    const admin = req.method === "GET" || params.has("admin");
    if (admin && !authorized(req, secret)) return reply(401, { error: "Доступ закрыт." });
    if (!db) return reply(503, { error: "Реестр недоступен." });

    let data;
    if (req.method === "POST") {
      try { data = await readBody(req); }
      catch { return reply(400, { error: "Некорректный запрос." }); }
    }
    const now = Date.now();
    try {
      if (req.method === "GET") {
        const offset = Number(params.get("offset") || 0);
        if (!Number.isSafeInteger(offset) || offset < 0 || offset > 1_000_000) return reply(400, { error: "Некорректная страница." });
        const records = await db.eval(
          "redis.call('ZREMRANGEBYSCORE',KEYS[1],'-inf',ARGV[1]); return redis.call('ZREVRANGE',KEYS[1],ARGV[2],ARGV[3])",
          1, index, now - TTL * 1000, offset, offset + PAGE);
        const devices = records.slice(0, PAGE).map(id => key(id));
        const values = devices.length ? await db.eval("return redis.call('MGET',unpack(KEYS))", devices.length, ...devices) : [];
        return reply(200, { devices: values.filter(Boolean).map(JSON.parse), more: records.length > PAGE });
      }

      if (req.method !== "POST") return reply(405, { error: "Метод не поддерживается." });
      if (admin) {
        const { ids, version } = data;
        if (typeof version !== "string" || !VERSION.test(version) || !Array.isArray(ids) ||
            !ids.length || ids.length > PAGE || !ids.every(id => typeof id === "string" && ID.test(id))) {
          return reply(400, { error: "Укажи установки и версию." });
        }
        const keys = [...new Set(ids)].map(key);
        const sent = await db.eval(dispatch, keys.length, ...keys, version);
        return reply(200, { sent });
      }

      const { token, version, platform, operation } = data;
      if (typeof token !== "string" || !TOKEN.test(token)) return reply(400, { error: "Неверный идентификатор." });
      const id = hash(token).slice(0, 32);
      if (operation === "remove") {
        await db.eval("redis.call('DEL',KEYS[2]); return redis.call('ZREM',KEYS[1],ARGV[1])", 2, index, key(id), id);
        return reply(200, {});
      }
      if (operation !== "check" || typeof version !== "string" || !VERSION.test(version) ||
          !["Windows", "macOS"].includes(platform)) return reply(400, { error: "Некорректная установка." });
      const address = req.headers["x-vercel-forwarded-for"] || req.socket.remoteAddress || "";
      const rate = await db.eval(
        "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],60) end; return n",
        1, prefix + "rate:" + hash(String(address)));
      if (rate > 100) return reply(429, { error: "Повтори через минуту." });
      const device = JSON.parse(await db.eval(heartbeat, 2, index, key(id),
        JSON.stringify({ id, version, platform, seen: now }), id, TTL));
      return reply(200, { target: device.target || "" });
    } catch {
      return reply(503, { error: "Реестр временно недоступен." });
    }
  };
}
