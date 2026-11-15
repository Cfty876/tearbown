import { createHash } from "node:crypto";

// Redis keeps the room and the recent reliable frames together across instances.
const update = String.raw`
local key, stream, topic = KEYS[1], KEYS[2], KEYS[3]
local op, now, id, token, lease = ARGV[1], tonumber(ARGV[2]), ARGV[3], ARGV[4], ARGV[5]
local raw = redis.call('GET', key)
local room = raw and cjson.decode(raw) or nil
local function answer(value) return cjson.encode(value) end
local function publicState()
    local members = {}
    for memberId, _ in pairs(room.peers) do table.insert(members, tonumber(memberId)) end
    table.sort(members)
    return {op='state', rules=room.rules, members=members,
        started=room.started, revision=room.revision or 0}
end
local function save(notify)
    if notify then room.revision = (room.revision or 0) + 1 end
    redis.call('SET', key, answer(room), 'PX', room.expires - now)
    if notify then redis.call('PUBLISH', topic, answer(publicState())) end
end
local function finish()
    redis.call('DEL', key, stream)
    redis.call('PUBLISH', topic, '{"op":"ended"}')
end
if op == 'create' then
    if room then
        local host = room.peers['1']
        if host and host.token == token and host.lease == lease then
            return answer({room=room,id=1})
        end
        return answer({error='collision'})
    end
    room = cjson.decode(ARGV[6])
    room.peers = {['1']={token=token, lease=lease, deadline=now+50000, seen=0}}
    save(nil)
    return answer({room=room,id=1})
end
if not room or now >= room.expires then return answer({error='missing'}) end
local peer = room.peers[id]
if op == 'join' then
    if ARGV[6] == 'web' and room.rules.map ~= 'hide' then return answer({error='platform'}) end
    if room.started then return answer({error='full'}) end
    local count = 0
    for otherId, other in pairs(room.peers) do
        if other.token == token and other.lease == lease and other.deadline >= now then
            return answer({room=room,id=tonumber(otherId)})
        end
        if other.deadline < now then
            if otherId == '1' then finish(); return answer({error='missing'}) end
            room.peers[otherId] = nil
        else count = count + 1 end
    end
    if count >= room.limit then return answer({error='full'}) end
    id = tostring(room.next)
    room.next = room.next + 1
    room.peers[id] = {token=token, lease=lease, deadline=now+50000, seen=0}
    save(true)
    return answer({room=room,id=tonumber(id)})
end
if not peer or peer.token ~= token or peer.deadline < now then return answer({error='missing'}) end
if op == 'resume' then
    if ARGV[6] == 'web' and room.rules.map ~= 'hide' then return answer({error='platform'}) end
    for otherId, other in pairs(room.peers) do
        if other.deadline < now and (room.started or otherId == '1') then
            finish()
            return answer({error='missing'})
        end
    end
    peer.lease = lease
    peer.deadline = now + 50000
    save(nil)
    return answer({room=room,id=tonumber(id)})
end
if peer.lease ~= lease then return answer({error='stale'}) end
if op == 'touch' then
    peer.deadline = now + 50000
    local changed = false
    for otherId, other in pairs(room.peers) do
        if other.deadline < now then
            if room.started or otherId == '1' then
                finish()
                return answer({error='missing'})
            end
            room.peers[otherId] = nil
            changed = true
        end
    end
    save(changed)
    if (room.revision or 0) > tonumber(ARGV[6]) then return answer({state=publicState()}) end
elseif op == 'leave' then
    if room.started or id == '1' then finish()
    else room.peers[id] = nil; save(true) end
elseif op == 'start' then
    if id ~= '1' then return answer({ok=true}) end
    if room.started then return answer({room=room}) end
    local count = 0
    for _, other in pairs(room.peers) do
        if other.deadline < now then return answer({error='full'}) end
        count = count + 1
    end
    if count ~= room.limit then return answer({error='full'}) end
    room.started = true
    room.expires = now + 21600000
    save(true)
    return answer({room=room})
elseif op == 'frame' then
    if not room.started then return answer({error='missing'}) end
    local sequence = tonumber(ARGV[6])
    if sequence > 0 and sequence <= peer.seen then return answer({seen=peer.seen}) end
    if sequence > 0 and sequence ~= peer.seen + 1 then return answer({error='sequence'}) end
    local frame = cjson.decode(ARGV[7])
    frame.op = 'frame'
    if id ~= '1' then
        frame.author = tonumber(id)
        frame.to = 1
        frame.skip = -1
    elseif not room.peers[tostring(frame.author)] or frame.media then frame.author = 1 end
    if frame.media and room.limit ~= 2 then return answer({error='media'}) end
    frame.sender = tonumber(id)
    if sequence > 0 then
        peer.seen = sequence
        room.journalPeak = math.max(room.journalPeak or 0, #ARGV[7])
        local retain = math.max(8, math.min(1024, math.floor(20971520 / room.journalPeak)))
        room.journalCount = (room.journalCount or 0) + 1
        room.historyTrimmed = room.historyTrimmed or room.journalCount > retain
        frame.cursor = redis.call('XADD', stream, 'MAXLEN', '=', retain, '*', 'frame', answer(frame))
        redis.call('PEXPIRE', stream, room.expires - now)
        save(nil)
    end
    redis.call('PUBLISH', topic, answer(frame))
    return answer({seen=peer.seen})
else return answer({error='missing'}) end
return answer({ok=true})
`;

const scriptId = createHash("sha1").update(update).digest("hex");

export class RoomStore {
  constructor(db, namespace = "breakpoint:rooms:v1") {
    this.db = db;
    this.namespace = namespace;
  }

  keys(code) {
    const key = this.namespace + ":{" + code + "}";
    return [key, key + ":journal", key + ":events"];
  }

  async retry(operation, perform) {
    try {
      return await perform();
    } catch (error) {
      if (error.name !== "TimeoutError" && error.message !== "Command timed out"
          && error.message !== "fetch failed") throw error;
      try {
        return await perform();
      } catch (retryError) {
        throw new Error("Redis " + operation + " failed after retry", { cause: retryError });
      }
    }
  }

  async run(code, op, client, arg = "", payload = "") {
    return this.retry(op, async () => {
      const args = [3, ...this.keys(code), op, Date.now(), client.id ?? "",
        client.token ?? "", client.lease ?? "", arg, payload];
      let reply;
      try {
        reply = await this.db.evalsha(scriptId, ...args);
      } catch (error) {
        if (!error.message.includes("NOSCRIPT")) throw error;
        reply = await this.db.eval(update, ...args);
      }
      return JSON.parse(reply);
    });
  }

  async get(code) {
    const value = await this.retry("get", () => this.db.get(this.keys(code)[0]));
    return value ? JSON.parse(value) : null;
  }

  async replay(code, cursor, visit) {
    const key = this.keys(code)[1];
    // If history was trimmed, terminating is safer than reviving a desynchronised map.
    if (cursor !== "0-0") {
      const first = (await this.retry("history start", () => this.db.xrange(key, "-", "+", "COUNT", 1)))[0];
      if (first && compareCursor(first[0], cursor) > 0) return false;
    }
    for (let batch = 0; batch < 16; batch++) {
      const events = await this.retry("replay", () => this.db.xrange(key, "(" + cursor, "+", "COUNT", 32));
      for (const [id, [, value]] of events) {
        if (!visit({ ...JSON.parse(value), cursor: id })) return false;
        cursor = id;
      }
      if (events.length < 32) return true;
    }
    return false;
  }
}

export function compareCursor(a, b) {
  const [at, ai] = a.split("-").map(Number);
  const [bt, bi] = b.split("-").map(Number);
  return at - bt || ai - bi;
}
