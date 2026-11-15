import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { test } from "node:test";
import Redis from "ioredis";
import { WebSocket } from "ws";
import { createRooms } from "../lib/rooms.js";
import { upstashCommands } from "../lib/redis-rest.js";

const redisUrl = process.env.BREAKPOINT_TEST_REDIS_URL;

async function client(server) {
  const ws = new WebSocket("ws://127.0.0.1:" + server.address().port + "/api/rooms");
  const records = [];
  ws.on("message", raw => records.push(JSON.parse(raw)));
  ws.on("close", (code, reason) => records.push({ op: "close", code, reason: reason.toString() }));
  await once(ws, "open");
  return {
    ws, records,
    send(record) { ws.send(JSON.stringify(record)); },
    async read(op, predicate = () => true) {
      const end = Date.now() + 10000;
      do {
        const offset = records.findIndex(record => record.op === op && predicate(record));
        if (offset !== -1) return records.splice(offset, 1)[0];
        await new Promise(resolve => setTimeout(resolve, 12));
      } while (Date.now() < end);
      assert.fail("Missing " + op + " • " + JSON.stringify(records.map(({ op, code, reason, message }) => ({ op, code, reason, message }))));
    },
  };
}

test("Redis routes a room across Vercel instances and replays lost destruction after resume", {
  skip: !redisUrl, timeout: 45000,
}, async () => {
  const namespace = "breakpoint:qa:" + randomUUID();
  const redis = [new Redis(redisUrl, { commandTimeout: 6000 }), new Redis(redisUrl, { commandTimeout: 6000 })];
  if (process.env.BREAKPOINT_TEST_TRACE === "1") {
    for (const [index, db] of redis.entries()) {
      const run = db.sendCommand.bind(db);
      db.sendCommand = (command, ...args) => {
        const begin = Date.now();
        const pending = run(command, ...args);
        pending.then(() => console.log(index, command.name, Date.now() - begin, "ms"),
          error => console.error(index, command.name, error.message));
        return pending;
      };
    }
  }
  if (!upstashCommands(redisUrl, {})) {
    const duplicate = redis[0].duplicate.bind(redis[0]);
    redis[0].duplicate = () => {
      const subscriber = duplicate();
      const emit = subscriber.emit.bind(subscriber);
      subscriber.emit = (event, ...args) => {
        // Simulate losing the lobby update on the host's subscription.
        if (event === "message") {
          const frame = JSON.parse(args[1]);
          if (frame.op === "state" && !frame.started) return false;
        }
        return emit(event, ...args);
      };
      return subscriber;
    };
  }
  const instances = redis.map(db => createRooms({ redis: db, commands: process.env.BREAKPOINT_TEST_TCP === "1" ? db : upstashCommands(redisUrl, {}),
    namespace, onError: error => console.error(error.message) }));
  try {
    for (const { server } of instances) {
      server.listen(0, "127.0.0.1");
      await once(server, "listening");
    }
    const [first, second] = instances.map(instance => instance.server);
    const host = await client(first);
    const guest = await client(second);
    host.send({ op: "create", version: 4, rules: { map: "school", hiders: 1, seekers: 1 } });
    const lobby = await host.read("lobby");
    assert.match(lobby.code, /^BP-[A-F0-9]{4}-[A-F0-9]{4}$/);
    guest.send({ op: "join", version: 4, code: lobby.code });
    const identity = await guest.read("lobby");
    assert.deepEqual(identity.members, [1, 2]);
    await host.read("lobby", entry => entry.members.length === 2);
    host.send({ op: "start" });
    await host.read("start");
    await guest.read("start");

    host.send({ op: "frame", sequence: 1, payload: '{"k":"vox","id":42}' });
    const before = await guest.read("frame");
    assert.equal(before.author, 1);
    await host.read("ack", ack => ack.sequence === 1);
    guest.ws.terminate();

    host.send({ op: "frame", sequence: 2, payload: '{"k":"vox","id":43}' });
    host.send({ op: "frame", reliable: false, payload: '{"k":"pose","s":44}' });
    host.send({ op: "frame", sequence: 3, payload: '{"k":"gone","id":45}' });
    await host.read("ack", ack => ack.sequence === 3);
    const other = await client(first);
    const resume = { op: "resume", code: lobby.code, id: identity.id, token: identity.token,
      version: 4, cursor: before.cursor };
    other.send(resume);
    const resumed = await other.read("resumed");
    assert.equal(resumed.started, true);
    assert.equal(resumed.id, 2);
    assert.equal((await other.read("frame")).payload, '{"k":"vox","id":43}');
    assert.equal((await other.read("frame")).payload, '{"k":"gone","id":45}');

    host.send({ op: "frame", sequence: 3, payload: '{"k":"gone","id":45}' });
    await host.read("ack", ack => ack.sequence === 3);
    other.send({ op: "frame", sequence: 1, payload: '{"k":"tool"}', author: 1 });
    assert.equal((await host.read("frame")).author, 2);
    await other.read("ack", ack => ack.sequence === 1);
    assert.equal(other.records.filter(record => record.op === "frame").length, 0);
    const unauthorized = await client(second);
    unauthorized.send({ ...resume, token: "0".repeat(64) });
    await unauthorized.read("error");
    other.send({ op: "leave" });
    await host.read("error", message => message.message === "Комната завершена.");
  } finally {
    for (const { server, sockets } of instances) {
      for (const socket of sockets.clients) socket.terminate();
      await new Promise(resolve => server.close(resolve));
    }
    for (const db of redis) db.disconnect();
  }
});
