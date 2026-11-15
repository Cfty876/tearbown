// Redis keeps the room and the recent reliable frames together across instances.
const update = String.raw`
local key, stream, topic = KEYS[1], KEYS[2], KEYS[3]
local op, now, id, token, lease = ARGV[1], tonumber(ARGV[2]), ARGV[3], ARGV[4], ARGV[5]
local raw = redis.call('GET', key)
local room = raw and cjson.decode(raw) or nil
local function answer(value) return cjson.encode(value) end
local function save(kind)
    redis.call('SET', key, answer(room), 'PX', room.expires - now)
    if kind then redis.call('PUBLISH', topic, answer({op=kind})) end
end
local function finish()
    redis.call('DEL', key, stream)
    redis.call('PUBLISH', topic, '{"op":"ended"}')
end
if op == 'create' then
    if room then return answer({error='collision'}) end
    room = cjson.decode(ARGV[6])
    room.peers = {['1']={token=token, lease=lease, deadline=now+50000, seen=0}}
    save(nil)
    return answer({room=room,id=1})
end
if not room or now >= room.expires then return answer({error='missing'}) end
local peer = room.peers[id]
if op == 'join' then
    if room.web ~= (ARGV[6] == 'web') then return answer({error='platform'}) end
    if room.started then return answer({error='full'}) end
    local count = 0
    for otherId, other in pairs(room.peers) do
        if other.deadline < now then
            if otherId == '1' then finish(); return answer({error='missing'}) end
            room.peers[otherId] = nil
        else count = count + 1 end
    end
    if count >= room.limit then return answer({error='full'}) end
    id = tostring(room.next)
    room.next = room.next + 1
    room.peers[id] = {token=token, lease=lease, deadline=now+50000, seen=0}
    save('state')
    return answer({room=room,id=tonumber(id)})
end
if not peer or peer.token ~= token or peer.deadline < now then return answer({error='missing'}) end
if op == 'resume' then
    if room.web ~= (ARGV[6] == 'web') then return answer({error='platform'}) end
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
    save(changed and 'state' or nil)
elseif op == 'leave' then
    if room.started or id == '1' then finish()
    else room.peers[id] = nil; save('state') end
elseif op == 'start' then
    if id ~= '1' or room.started then return answer({ok=true}) end
    local count = 0
    for _, other in pairs(room.peers) do
        if other.deadline < now then return answer({error='full'}) end
        count = count + 1
    end
    if count ~= room.limit then return answer({error='full'}) end
    room.started = true
    room.expires = now + 21600000
    save('state')
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

export class RoomStore {
  constructor(db, namespace = "breakpoint:rooms:v1") {
    this.db = db;
    this.namespace = namespace;
    this.db.defineCommand("updateBreakpointRoom", { numberOfKeys: 3, lua: update });
  }

  keys(code) {
    const key = this.namespace + ":{" + code + "}";
    return [key, key + ":journal", key + ":events"];
  }

  async run(code, op, client, arg = "", payload = "") {
    return JSON.parse(await this.db.updateBreakpointRoom(
      ...this.keys(code), op, Date.now(), client.id ?? "",
      client.token ?? "", client.lease ?? "", arg, payload,
    ));
  }

  async get(code) {
    const value = await this.db.get(this.keys(code)[0]);
    return value ? JSON.parse(value) : null;
  }

  async replay(code, cursor, visit) {
    const key = this.keys(code)[1];
    // If history was trimmed, terminating is safer than reviving a desynchronised map.
    if (cursor !== "0-0") {
      const first = (await this.db.xrange(key, "-", "+", "COUNT", 1))[0];
      if (first && compareCursor(first[0], cursor) > 0) return false;
    }
    for (let batch = 0; batch < 16; batch++) {
      const events = await this.db.xrange(key, "(" + cursor, "+", "COUNT", 32);
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
