import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { WebSocket } from 'ws';
import { createRelay } from './server.mjs';

test('health, room codes, start, directed traffic and disconnect', { timeout: 7000 }, async () => {
  const { server, sockets } = createRelay();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const host = '127.0.0.1:' + server.address().port;
  try {
    assert.equal((await fetch('http://' + host + '/healthz')).status, 200);
    async function open() {
      const socket = new WebSocket('ws://' + host + '/rooms');
      const queue = [];
      socket.on('message', raw => queue.push(JSON.parse(raw.toString())));
      await once(socket, 'open');
      return {
        socket,
        send(record) { socket.send(JSON.stringify(record)); },
        async read(op) {
          const deadline = Date.now() + 1000;
          while (queue.length === 0 && Date.now() < deadline) await new Promise(r => setTimeout(r, 5));
          const record = queue.shift();
          assert.equal(record?.op, op);
          return record;
        },
        queue,
      };
    }
    const owner = await open();
    const guest = await open();
    const other = await open();
    const stale = await open();
    const rules = { map: 'school', hiders: 1, seekers: 1, bot: false };
    stale.send({ op: 'create', version: 3, rules });
    assert.match((await stale.read('error')).message, /Версии/);
    owner.send({ op: 'create', version: 5, rules });
    other.send({ op: 'create', version: 5, rules });
    const lobby = await owner.read('lobby');
    assert.match(lobby.code, /^BP-[0-9A-F]{4}-[0-9A-F]{4}$/);
    const isolated = await other.read('lobby');
    assert.notEqual(isolated.code, lobby.code);
    guest.send({ op: 'join', web: true, version: 5, code: lobby.code });
    assert.deepEqual((await guest.read('lobby')).members, [1, 2]);
    assert.equal((await owner.read('lobby')).members.length, 2);
    owner.send({ op: 'start' });
    assert.equal((await owner.read('start')).id, 1);
    assert.equal((await guest.read('start')).id, 2);
    guest.send({ op: 'frame', payload: '{"k":"pose"}', reliable: false });
    assert.equal((await owner.read('frame')).author, 2);
    owner.send({ op: 'frame', to: 2, payload: '{"k":"state"}' });
    assert.equal((await guest.read('frame')).payload, '{"k":"state"}');
    guest.send({ op: 'frame', payload: 'AAAA', media: true });
    assert.equal((await owner.read('frame')).media, true);
    assert.deepEqual(other.queue, []);
    guest.socket.close();
    assert.match((await owner.read('error')).message, /отключился/);
  } finally {
    for (const socket of sockets.clients) socket.terminate();
    await new Promise(r => server.close(r));
  }
});
