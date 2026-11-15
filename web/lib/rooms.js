import { randomBytes, createHash } from "node:crypto";
import { createServer } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { RoomStore, compareCursor } from "./room-store.js";

const VERSION = 4;
const MAX_FRAME = 2_100_000;
const MAPS = new Set(["proto", "district", "school"]);
const CODE = /^BP-[0-9A-F]{4}-[0-9A-F]{4}$/;
const TOKEN = /^[0-9a-f]{64}$/;
const CURSOR = /^\d{1,14}-\d{1,8}$/;
const errors = {
  missing: "Комната закрыта или время переподключения истекло.",
  platform: "Запустите ту же версию игры, что и создатель комнаты.",
  full: "Комната заполнена или игра уже началась.",
  sequence: "Не удалось восстановить порядок игровых событий.",
  media: "Передача кассет доступна в комнатах на двоих.",
};

function send(ws, value, reliable = true) {
  if (ws.readyState !== WebSocket.OPEN) return false;
  if (!reliable && ws.bufferedAmount > 128 * 1024) return false;
  if (ws.bufferedAmount > 8 * 1024 * 1024) {
    ws.close(1013, "busy");
    return false;
  }
  ws.send(JSON.stringify(value));
  return true;
}

function fail(ws, message, code = 1008) {
  send(ws, { op: "error", message });
  ws.close(code);
}

export function createRooms({ redis, commands = redis, namespace, rotateMs = 245_000, onError = () => {} } = {}) {
  const server = createServer(async (_req, res) => {
    let healthy = false;
    try { healthy = Boolean(redis) && await commands.ping() === "PONG"; } catch {}
    res.writeHead(healthy ? 200 : 503, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    res.end(JSON.stringify({ ready: healthy, protocol: VERSION, resume: true }));
  });
  const sockets = new WebSocketServer({
    server, maxPayload: MAX_FRAME, perMessageDeflate: false,
  });

  const store = redis && new RoomStore(commands, namespace);
  const subscriber = redis?.duplicate();
  // One subscription per active room on this Function instance.
  const rooms = new Map();

  function deliverFrame(ws, frame) {
    const client = ws.session;
    if (frame.cursor) {
      if (compareCursor(frame.cursor, client.cursor) <= 0) return true;
      client.cursor = frame.cursor;
    }
    if (frame.sender === client.id || frame.skip === client.id ||
        (frame.to > 0 && frame.to !== client.id)) return true;
    return send(ws, { op: "frame", author: frame.author, payload: frame.payload,
      media: frame.media, cursor: frame.cursor }, Boolean(frame.cursor)) || !frame.cursor;
  }

  function sendState(ws, state, operation, seen) {
    if (operation === undefined && (ws.revision ?? -1) >= state.revision) return true;
    ws.revision = state.revision;
    ws.started = state.started;
    ws.members = state.members;
    const op = operation ?? (state.started ? "start" : "lobby");
    const { id, code, token } = ws.session;
    return send(ws, { op, id, code, token, started: state.started, seen,
      rules: state.rules, members: state.members });
  }

  function publishState(ws, room, operation) {
    const client = ws.session;
    if (!room || !room.peers[String(client.id)]) {
      fail(ws, errors.missing);
      return false;
    }
    if (room.peers[String(client.id)].lease !== client.lease) {
      ws.close(1000, "replaced");
      return false;
    }
    return sendState(ws, {
      started: room.started, rules: room.rules, revision: room.revision ?? 0,
      members: Object.keys(room.peers).map(Number).sort((a, b) => a - b),
    }, operation, room.peers[String(client.id)].seen);
  }

  function report(ws, error) {
    if (error === "stale") ws.close(1000, "replaced");
    else fail(ws, errors[error] ?? "Сервер комнат временно недоступен.");
  }

  function serialized(ws, operation) {
    ws.queue = ws.queue.then(async () => {
      if (ws.readyState === WebSocket.OPEN) await operation();
    }).catch(error => {
      onError(error);
      ws.close(1013, "temporary failure");
    });
  }

  subscriber?.on("message", (topic, raw) => {
    const bucket = rooms.get(topic);
    if (!bucket) return;
    const data = JSON.parse(raw);
    for (const ws of bucket.clients) {
      if (data.op === "batch") {
        if (!ws.catchingUp) {
          for (const frame of data.frames) deliverFrame(ws, frame);
        }
      } else if (data.op === "frame") {
        if (ws.catchingUp) {
          if (data.cursor && ws.bufferedFrames.length < 512) ws.bufferedFrames.push(data);
          else if (data.cursor) ws.close(1013, "history backlog");
        } else {
          deliverFrame(ws, data);
        }
      } else if (data.op === "ended") {
        fail(ws, "Комната завершена.");
      } else if (data.op === "state") {
        serialized(ws, async () => sendState(ws, data));
      }
    }
  });
  subscriber?.on("error", () => {
    for (const ws of sockets.clients) if (ws.session) ws.close(1013, "subscription unavailable");
  });
  redis?.on("error", () => {});

  async function attach(ws, code, result, client, cursor, reconnecting) {
    client.id = result.id;
    client.code = code;
    client.cursor = cursor;
    const topic = store.keys(code)[2];
    let bucket = rooms.get(topic);
    if (!bucket) {
      bucket = { clients: new Set(), subscribed: subscriber.subscribe(topic) };
      rooms.set(topic, bucket);
    }
    ws.session = client;
    ws.catchingUp = true;
    ws.bufferedFrames = [];
    bucket.clients.add(ws);
    try {
      await bucket.subscribed;
      const room = await store.get(code);
      if (reconnecting && cursor === "0-0" && room?.historyTrimmed) {
        return fail(ws, "История комнаты истекла. Начните новый раунд.");
      }
      if (!publishState(ws, room, reconnecting ? "resumed" : undefined)) return;
      if (reconnecting && room.started) {
        const complete = await store.replay(code, cursor, frame => deliverFrame(ws, frame));
        if (!complete) return fail(ws, "История комнаты истекла. Начните новый раунд.");
      }
      for (const frame of ws.bufferedFrames) deliverFrame(ws, frame);
    } finally {
      ws.bufferedFrames = [];
      ws.catchingUp = false;
    }
  }

  function sendVolatile(ws, msg) {
    const client = ws.session;
    const host = client.id === 1;
    const author = host && ws.members.includes(msg.author) ? msg.author : client.id;
    const to = host && Number.isSafeInteger(msg.to) ? msg.to : (host ? -1 : 1);
    const skip = host && Number.isSafeInteger(msg.skip) ? msg.skip : -1;
    const kind = msg.payload.match(/"k"\s*:\s*"([a-z_]+)"/)?.[1] ?? "";
    const key = author + ":" + kind;
    if (ws.volatile.size < 24 || ws.volatile.has(key)) {
      ws.volatile.set(key, { op: "frame", author, to, skip, sender: client.id, media: false,
        payload: msg.payload });
    }
    if (ws.volatileSending) return;
    ws.volatileSending = true;
    void (async () => {
      try {
        const topic = store.keys(client.code)[2];
        while (ws.readyState === WebSocket.OPEN && ws.volatile.size) {
          const batch = [...ws.volatile.values()];
          ws.volatile.clear();
          await commands.publish(topic, JSON.stringify({ op: "batch", frames: batch }));
        }
      } catch (error) {
        ws.volatile.clear();
        onError(error);
      } finally {
        ws.volatileSending = false;
      }
    })();
  }

  sockets.on("connection", (ws, request) => {
    if (!store) return fail(ws, "Хранилище комнат не подключено.");
    if (sockets.clients.size > 512) return fail(ws, "Сервер комнат заполнен.", 1013);
    ws.queue = Promise.resolve();
    ws.volatile = new Map();
    let messages = 0;
    let credit = 4_200_000;
    let last = Date.now();
    const handshake = setTimeout(() => {
      if (!ws.session) fail(ws, "Истекло время подключения.");
    }, 12_000);
    const rotate = setTimeout(() => ws.close(1012, "renew connection"), rotateMs);
    const presence = setInterval(() => {
      if (!ws.session) return;
      serialized(ws, async () => {
        const result = await store.run(ws.session.code, "touch", ws.session);
        if (result.error) report(ws, result.error);
      });
    }, 10_000);
    ws.on("error", () => ws.terminate());
    ws.on("close", () => {
      clearInterval(presence);
      clearTimeout(handshake);
      clearTimeout(rotate);
      if (!ws.session) return;
      const topic = store.keys(ws.session.code)[2];
      const bucket = rooms.get(topic);
      bucket?.clients.delete(ws);
      if (bucket?.clients.size === 0) {
        rooms.delete(topic);
        subscriber.unsubscribe(topic).catch(() => {});
      }
    });

    ws.on("message", (raw, binary) => {
      const now = Date.now();
      credit = Math.min(4_200_000, credit + (now - last) * 220) - raw.length - 1024;
      last = now;
      if (binary || credit < 0 || messages >= 160) return ws.close(1013, "traffic limit");
      let msg;
      try { msg = JSON.parse(raw); } catch { return; }
      if (!msg || typeof msg !== "object" || Array.isArray(msg)) return;
      if (ws.session && ws.started && msg.op === "frame" && msg.reliable === false &&
          !msg.media && typeof msg.payload === "string" && msg.payload.length <= 65_000) {
        sendVolatile(ws, msg);
        return;
      }
      ++messages;
      serialized(ws, async () => {
        --messages;
        if (!ws.session) {
          if (msg.version !== VERSION) return fail(ws, "Обновите игру. Версии протокола различаются.");
          const ip = request.headers["x-vercel-forwarded-for"] ?? request.socket.remoteAddress ?? "unknown";
          const rate = store.namespace + ":open:" + createHash("sha256").update(String(ip)).digest("hex");
          const limit = await commands.eval("local n=redis.call('INCR',KEYS[1]);if n==1 then redis.call('EXPIRE',KEYS[1],60) end;return n", 1, rate);
          if (limit > 60) return fail(ws, "Слишком много подключений. Повторите через минуту.", 1013);
          const web = msg.web === true;
          const platform = web ? "web" : "desktop";
          const client = { lease: randomBytes(18).toString("hex"), token: randomBytes(32).toString("hex") };
          let code = typeof msg.code === "string" ? msg.code : "";
          let result;
          if (msg.op === "create") {
            const rules = msg.rules;
            if (!rules || !(web ? rules.map === "hide" : MAPS.has(rules.map)) ||
                ![rules.seekers, rules.hiders].every(n => Number.isInteger(n) && n >= 1 && n <= 4) ||
                (rules.bot === true && rules.map !== "school") || JSON.stringify(rules).length > 1800) {
              return fail(ws, "Неверные настройки комнаты.");
            }
            for (let attempt = 0; attempt < 3; attempt++) {
              const id = randomBytes(4).toString("hex").toUpperCase();
              code = "BP-" + id.slice(0, 4) + "-" + id.slice(4);
              result = await store.run(code, "create", client, JSON.stringify({
                rules, web, limit: rules.seekers + rules.hiders - Number(rules.bot === true),
                next: 2, started: false, expires: Date.now() + 1_800_000,
              }));
              if (!result.error) break;
            }
          } else if (CODE.test(code) && msg.op === "join") {
            result = await store.run(code, "join", client, platform);
          } else if (CODE.test(code) && msg.op === "resume" &&
              Number.isSafeInteger(msg.id) && TOKEN.test(msg.token) && CURSOR.test(msg.cursor)) {
            client.id = msg.id;
            client.token = msg.token;
            result = await store.run(code, "resume", client, platform);
          } else return fail(ws, "Проверьте код комнаты.");
          if (result?.error) return report(ws, result.error);
          if (ws.readyState === WebSocket.OPEN) {
            await attach(ws, code, result, client, msg.op === "resume" ? msg.cursor : "0-0", msg.op === "resume");
          }
          return;
        }
        const client = ws.session;
        if (msg.op === "leave") {
          await store.run(client.code, "leave", client);
          ws.close(1000);
        } else if (msg.op === "start") {
          const result = await store.run(client.code, "start", client);
          if (result.error) report(ws, result.error);
          else if (result.room) publishState(ws, result.room);
        } else if (msg.op === "frame" && ws.started && typeof msg.payload === "string" &&
            msg.payload.length <= 2_000_000 && (!msg.media || msg.payload.length <= 45_000)) {
          const sequence = Number.isSafeInteger(msg.sequence) && msg.sequence > 0 ? msg.sequence : 0;
          const result = await store.run(client.code, "frame", client, sequence, JSON.stringify({
            payload: msg.payload, author: Number.isInteger(msg.author) ? msg.author : 1,
            to: Number.isInteger(msg.to) ? msg.to : -1, skip: Number.isInteger(msg.skip) ? msg.skip : -1,
            media: msg.media === true,
          }));
          if (result.error) report(ws, result.error);
          else if (sequence > 0) send(ws, { op: "ack", sequence: result.seen });
        }
      });
    });
  });

  server.on("close", () => {
    sockets.close();
    subscriber?.disconnect();
  });
  return { server, sockets };
}
