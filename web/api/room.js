import { createHmac, randomBytes, createHash } from "node:crypto";

const TTL = 600;
const LIMIT = 80;
const PREFIX = "vox-web:room:v1:";
const CAS = "if redis.call('GET',KEYS[1])~=ARGV[1] then return 0 end redis.call('SET',KEYS[1],ARGV[2],'KEEPTTL') return 1";
const RATE = "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],60) end return n";

export function memoryStore() {
  const values = new Map();
  function get(key) {
    const entry = values.get(key);
    if (entry?.expiry > Date.now()) return entry;
    values.delete(key);
    return undefined;
  }
  return async function command(op, ...args) {
    const [key, data] = args;
    if (op === "GET") return get(key)?.data ?? null;
    if (op === "SET") {
      if (get(key)) return null;
      for (const k of values.keys()) get(k);
      values.set(key, { data, expiry: Date.now() + TTL * 1000 });
      return "OK";
    }
    if (key === RATE) {
      const k = args[2];
      const item = get(k) ?? { data: 0, expiry: Date.now() + 60000 };
      item.data += 1;
      values.set(k, item);
      return item.data;
    }
    const [, , room, before, after] = args;
    const item = get(room);
    if (item?.data !== before) return 0;
    item.data = after;
    return 1;
  };
}

function redisStore(env) {
  const url = env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN;
  if (!url || !token) return null;
  return async (...command) => {
    const response = await fetch(url, {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify(command),
      signal: AbortSignal.timeout(5000),
    });
    const body = await response.json();
    if (!response.ok || body.error) throw new Error("Room storage unavailable");
    return body.result;
  };
}

function iceServers(env) {
  const servers = [{ urls: "stun:stun.l.google.com:19302" }];
  const urls = env.TURN_URLS?.split(",").map((url) => url.trim()).filter(Boolean);
  if (urls?.length && env.TURN_SECRET) {
    const username = Math.floor(Date.now() / 1000 + 3600) + ":" + randomBytes(8).toString("hex");
    const credential = createHmac("sha1", env.TURN_SECRET).update(username).digest("base64");
    servers.push({ urls, username, credential });
  }
  return servers;
}

const reply = (value, status = 200) =>
  Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
const failure = (error, status) => reply({ error }, status);

export function makeRoomHandler({ command, env = process.env, local = false } = {}) {
  return async (request) => {
    if (request.method !== "POST") return failure("Метод недоступен", 405);
    const requestUrl = new URL(request.url);
    const origin = request.headers.get("origin");
    if (origin && origin !== requestUrl.origin) return failure("Недопустимый источник", 403);
    if (!command) return failure("В Vercel не подключено хранилище комнат", 503);
    try {
      if (Number(request.headers.get("content-length")) > 18000) return failure("Сигнал слишком большой", 413);
      const text = await request.text();
      if (text.length > 18000) return failure("Сигнал слишком большой", 413);
      let body;
      try { body = JSON.parse(text); } catch { return failure("Некорректный JSON", 400); }
      if (!body || typeof body !== "object") return failure("Некорректный запрос", 400);
      const { action, code, token } = body;
      if (action === "create" || action === "join") {
        if (!local) {
          const ip = request.headers.get("x-vercel-forwarded-for")?.split(",")[0] ?? "unknown";
          const bucket = "vox-web:room:rate:" + createHash("sha256").update(ip).digest("hex");
          if (await command("EVAL", RATE, 1, bucket) > 40) return failure("Повтори чуть позже", 429);
        }
      }
      if (action === "create") {
        for (let attempt = 0; attempt < 4; attempt += 1) {
          const code = randomBytes(4).toString("hex").toUpperCase();
          const host = randomBytes(24).toString("hex");
          const value = JSON.stringify({ host, guest: "", toHost: [], toGuest: [] });
          if (await command("SET", PREFIX + code, value, "NX", "EX", TTL)) {
            return reply({ code, token: host, host: true, iceServers: iceServers(env) });
          }
        }
        return failure("Комната не создана. Повтори попытку", 503);
      }
      if (typeof code !== "string" || !/^[0-9A-F]{8}$/.test(code)) return failure("Проверь код комнаты", 400);
      const key = PREFIX + code;
      if (!["join", "poll", "signal"].includes(action)) return failure("Неизвестная команда", 400);
      for (let attempt = 0; attempt < 5; attempt += 1) {
        const before = await command("GET", key);
        if (!before) return failure("Комната закрыта или код устарел", 404);
        const room = JSON.parse(before);
        if (action === "join") {
          if (room.guest) return failure("В комнате уже два игрока", 409);
          room.guest = randomBytes(24).toString("hex");
          if (await command("EVAL", CAS, 1, key, before, JSON.stringify(room))) {
            return reply({ code, token: room.guest, host: false, iceServers: iceServers(env) });
          }
          continue;
        }
        if (!token || (token !== room.host && token !== room.guest)) return failure("Нет доступа к комнате", 403);
        const host = token === room.host;
        if (action === "poll") {
          const queue = host ? room.toHost : room.toGuest;
          const cursor = Number.isInteger(body.cursor) ? Math.max(0, body.cursor) : 0;
          return reply({ messages: queue.slice(cursor), cursor: queue.length });
        }
        const signal = body.signal;
        if (!signal || typeof signal !== "object" || !["offer", "answer", "ice"].includes(signal.kind)) {
          return failure("Недопустимый сигнал", 400);
        }
        if ((signal.kind === "offer" && !host) || (signal.kind === "answer" && host)) {
          return failure("Недопустимая роль отправителя", 403);
        }
        const queue = host ? room.toGuest : room.toHost;
        if (queue.length >= LIMIT) return failure("Лимит обмена сигналами. Создай новую комнату", 409);
        queue.push(signal);
        if (await command("EVAL", CAS, 1, key, before, JSON.stringify(room))) return reply({ ok: true });
      }
      return failure("Сигнал столкнулся с другим запросом. Повтори попытку", 503);
    } catch (error) {
      console.error("Room API:", error.name);
      return failure("Сервис комнат временно недоступен", 503);
    }
  };
}

export default { fetch: makeRoomHandler({ command: redisStore(process.env) }) };
