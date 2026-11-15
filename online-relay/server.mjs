import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { WebSocket, WebSocketServer } from 'ws';

const VERSION = 4;
const BYTE_LIMIT = 2_100_000;
const POSE_QUEUE = 128 * 1024;
const RELIABLE_QUEUE = 3 * 1024 * 1024;
const MAX_PEERS = 512;
const MAX_PER_ADDRESS = 24;
const MAX_ROOMS = 256;
const LOBBY_TTL = 30 * 60_000;
const ROUND_TTL = 6 * 60 * 60_000;
const DESKTOP_MAPS = new Set(['proto', 'district', 'school']);

export function createRelay() {
  const rooms = new Map();
  const addresses = new Map();
  const server = createServer((req, res) => {
    const healthy = req.method === 'GET' && req.url === '/healthz';
    res.writeHead(healthy ? 200 : 404, { 'Content-Type': 'text/plain' });
    res.end(healthy ? 'ok\n' : 'not found\n');
  });
  const sockets = new WebSocketServer({
    server, path: '/rooms', maxPayload: BYTE_LIMIT, perMessageDeflate: false,
  });
  const trustedProxy = process.env.TRUST_LOCAL_PROXY === '1';

  function deliver(socket, text, reliable = true) {
    if (socket.readyState !== WebSocket.OPEN) return;
    if (!reliable && socket.bufferedAmount > POSE_QUEUE) return;
    if (socket.bufferedAmount > RELIABLE_QUEUE) {
      socket.terminate();
      return;
    }
    socket.send(text, (error) => { if (error) socket.terminate(); });
  }
  const send = (socket, msg) => deliver(socket, JSON.stringify(msg));
  function fail(socket, message) {
    send(socket, { op: 'error', message });
    socket.close(1008);
  }
  function publish(room, op) {
    const members = [...room.members.keys()];
    for (const [id, socket] of room.members) {
      send(socket, { op, id, code: room.code, rules: room.rules, members });
    }
  }
  function closeRoom(room, reason) {
    rooms.delete(room.code);
    for (const socket of room.members.values()) {
      socket.room = null;
      send(socket, { op: 'error', message: reason });
      socket.close(1000);
    }
    room.members.clear();
  }
  function register(socket, msg) {
    if (msg.version !== VERSION) {
      fail(socket, 'Обновите игру. Версии игры и сервера различаются.');
      return;
    }
    const address = addresses.get(socket.address);
    if (++address.attempts > 40) {
      fail(socket, 'Слишком много попыток. Попробуйте через минуту.');
      return;
    }
    const web = msg.web === true;
    let room;
    if (msg.op === 'create') {
      const rules = msg.rules;
      if (!rules || typeof rules !== 'object' || !(web ? rules.map === 'hide' : DESKTOP_MAPS.has(rules.map)) ||
          ![rules.seekers, rules.hiders].every(n => Number.isInteger(n) && n >= 1 && n <= 4) ||
          (rules.bot === true && rules.map !== 'school') || JSON.stringify(rules).length > 1800) {
        fail(socket, 'Неверные настройки комнаты.');
        return;
      }
      if (rooms.size >= MAX_ROOMS) {
        fail(socket, 'Сервер комнат заполнен. Попробуйте позже.');
        return;
      }
      let key;
      do { key = randomBytes(4).toString('hex').toUpperCase(); }
      while (rooms.has('BP-' + key.slice(0, 4) + '-' + key.slice(4)));
      const code = 'BP-' + key.slice(0, 4) + '-' + key.slice(4);
      room = {
        code, rules, web, members: new Map(), nextId: 2,
        limit: rules.seekers + rules.hiders - Number(rules.bot === true),
        started: false, expires: Date.now() + LOBBY_TTL,
      };
      rooms.set(code, room);
      socket.roomId = 1;
    } else if (msg.op === 'join') {
      room = typeof msg.code === 'string' ? rooms.get(msg.code) : undefined;
      if (room && room.web !== web) {
        fail(socket, 'Этот код для другой версии игры. Запустите ту же версию, что и создатель.');
        return;
      }
      if (!room || room.started || room.members.size >= room.limit) {
        fail(socket, 'Онлайн-комната закрыта, заполнена или код неверен.');
        return;
      }
      socket.roomId = room.nextId++;
    } else {
      fail(socket, 'Сначала создайте комнату или введите код.');
      return;
    }
    socket.room = room;
    room.members.set(socket.roomId, socket);
    publish(room, 'lobby');
  }
  sockets.on('connection', (socket, req) => {
    const forwarded = req.headers['x-forwarded-for'];
    const fromLoopback = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
    socket.address = trustedProxy && fromLoopback && typeof forwarded === 'string'
      ? forwarded.split(',').at(-1).trim() : req.socket.remoteAddress;
    const address = addresses.get(socket.address) ?? { active: 0, attempts: 0 };
    if (sockets.clients.size > MAX_PEERS || address.active >= MAX_PER_ADDRESS) {
      fail(socket, 'Сервер занят. Попробуйте подключиться позже.');
      return;
    }
    addresses.set(socket.address, address);
    ++address.active;
    socket.alive = true;
    socket.registerBy = Date.now() + 12_000;
    let allowance = BYTE_LIMIT * 2;
    let updated = Date.now();
    socket.on('error', () => socket.terminate());
    socket.on('pong', () => { socket.alive = true; });
    socket.on('close', () => {
      --address.active;
      const room = socket.room;
      if (!room) return;
      room.members.delete(socket.roomId);
      if (socket.roomId === 1 || room.started) {
        closeRoom(room, socket.roomId === 1 ? 'Создатель вышел из комнаты.' : 'Один из игроков отключился.');
      } else {
        publish(room, 'lobby');
      }
    });
    socket.on('message', (raw, binary) => {
      const now = Date.now();
      allowance = Math.min(BYTE_LIMIT * 2, allowance + (now - updated) * 220);
      updated = now;
      allowance -= raw.length + 1024;
      if (binary || allowance < 0) {
        fail(socket, 'Превышен лимит передачи данных.');
        return;
      }
      let msg;
      try { msg = JSON.parse(raw); } catch { return; }
      if (!msg || typeof msg !== 'object' || Array.isArray(msg)) return;
      const room = socket.room;
      if (!room) {
        register(socket, msg);
        return;
      }
      if (msg.op === 'leave') {
        socket.close(1000);
        return;
      }
      if (msg.op === 'start' && socket.roomId === 1 && !room.started && room.members.size === room.limit) {
        room.started = true;
        room.expires = now + ROUND_TTL;
        publish(room, 'start');
        return;
      }
      if (msg.op !== 'frame' || !room.started || typeof msg.payload !== 'string') return;
      const isHost = socket.roomId === 1;
      const media = msg.media === true;
      if (media && (room.members.size !== 2 || msg.payload.length > 45_000)) return;
      const author = isHost && !media && room.members.has(msg.author) ? msg.author : socket.roomId;
      const text = JSON.stringify({ op: 'frame', author, media, payload: msg.payload });
      if (!isHost) {
        deliver(room.members.get(1), text, msg.reliable !== false);
        return;
      }
      for (const [id, target] of room.members) {
        if (id !== 1 && id !== msg.skip && (!(msg.to > 0) || id === msg.to)) {
          deliver(target, text, msg.reliable !== false);
        }
      }
    });
  });
  const heartbeat = setInterval(() => {
    const now = Date.now();
    for (const room of rooms.values()) {
      if (room.expires <= now) closeRoom(room, 'Время работы комнаты истекло.');
    }
    for (const socket of sockets.clients) {
      if ((!socket.room && socket.registerBy < now) || socket.alive === false) {
        socket.terminate();
        continue;
      }
      if (socket.readyState === WebSocket.OPEN) {
        socket.alive = false;
        socket.ping();
      }
    }
  }, 10_000);
  const attempts = setInterval(() => {
    for (const [ip, address] of addresses) {
      if (address.active === 0) addresses.delete(ip);
      else address.attempts = 0;
    }
  }, 60_000);
  server.on('close', () => {
    clearInterval(heartbeat);
    clearInterval(attempts);
    sockets.close();
  });
  return { server, sockets };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const { server, sockets } = createRelay();
  server.listen(Number(process.env.PORT || 8787), process.env.BIND || '127.0.0.1', () => {
    console.log('BREAKPOINT relay listening on', server.address());
  });
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => {
      for (const socket of sockets.clients) socket.terminate();
      server.close();
    });
  }
}
