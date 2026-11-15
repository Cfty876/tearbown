class_name OnlineRooms
extends RefCounted

const MAX_FRAME := 2100000
const POSE_BACKLOG := 131072
const TOTAL_BACKLOG := 3145728
const CONFIG_PATH := "user://online.cfg"
const DEFAULT_RELAY := "wss://tearbown.vercel.app/api/rooms"

var socket := WebSocketPeer.new()
var pending := {}
var active := false
var _handshake_sent := false
var reconnecting := false
var _url := ""
var _identity := {}
var _cursor := "0-0"
var _resume_until := 0
var _retry_at := 0
var _connect_until := 0
var _attempts := 0
var _sequence := 0
var _outbox: Array[Dictionary] = []
var _outbox_bytes := 0
var _sent_through := 0


static func configured_url() -> String:
	if OS.has_feature("web"):
		var site := JavaScriptBridge.get_interface("BreakpointConfig")
		return str(site.relay) if site != null else ""
	var env := OS.get_environment("BREAKPOINT_RELAY_URL").strip_edges()
	if valid_url(env):
		return env
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var saved := str(config.get_value("online", "url", "")).strip_edges()
		if valid_url(saved):
			return saved
	var executable_dir := OS.get_executable_path().get_base_dir()
	var candidates := [executable_dir.path_join("online.cfg"), "res://online.cfg"]
	if OS.get_name() == "macOS":
		candidates.push_front(executable_dir.path_join("../Resources/online.cfg"))
	for sidecar: String in candidates:
		if config.load(sidecar) == OK:
			var bundled := str(config.get_value("online", "url", "")).strip_edges()
			if valid_url(bundled):
				return bundled
	return DEFAULT_RELAY


static func valid_url(value: String) -> bool:
	if value.length() > 400 or value.contains(" ") or value.contains("#") or value.contains("@"):
		return false
	return (value.begins_with("wss://") and value.length() > 6) or value.begins_with("ws://127.0.0.1:") or value.begins_with("ws://localhost:")


static func remember_url(value: String) -> void:
	var config := ConfigFile.new()
	config.set_value("online", "url", value)
	config.save(CONFIG_PATH)


func connect_room(url: String, command: Dictionary) -> Error:
	_url = url
	pending = command
	return _dial()


func _dial() -> Error:
	socket = WebSocketPeer.new()
	_handshake_sent = false
	_connect_until = Time.get_ticks_msec() + 5000
	socket.inbound_buffer_size = MAX_FRAME + 4096
	socket.outbound_buffer_size = TOTAL_BACKLOG + 4096
	socket.max_queued_packets = 256
	socket.heartbeat_interval = 15.0
	var result := socket.connect_to_url(_url)
	active = result == OK
	return result


func stop() -> void:
	active = false
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text('{"op":"leave"}')
		socket.close(1000)


func _lost(result: Array[Dictionary]) -> void:
	active = false
	if _identity.is_empty():
		result.append({"op": "closed"})
		return
	var now := Time.get_ticks_msec()
	if not reconnecting:
		reconnecting = true
		_resume_until = now + 42000
		_attempts = 0
		result.append({"op": "reconnecting"})
	_retry_at = now + mini(2800, 170 + _attempts * 400)


func _ack(sequence: int) -> void:
	while not _outbox.is_empty() and int(_outbox[0].sequence) <= sequence:
		var frame: Dictionary = _outbox.pop_front()
		_outbox_bytes -= str(frame.payload).length()


func _handle(record: Dictionary, result: Array[Dictionary]) -> void:
	var operation := str(record.get("op", ""))
	if operation in ["lobby", "start", "resumed"] and record.has("token"):
		_identity = {"op": "resume", "id": int(record.id), "code": str(record.code), "token": str(record.token)}
	if operation == "resumed":
		var seen := int(record.get("seen", 0))
		_ack(seen)
		_sent_through = seen
		reconnecting = false
	elif operation == "ack":
		_ack(int(record.get("sequence", 0)))
		return
	elif operation == "frame" and record.has("cursor"):
		_cursor = str(record.cursor)
	result.append(record)


func _flush() -> void:
	if reconnecting or not active or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var remaining := 8
	for message in _outbox:
		var number := int(message.sequence)
		if number > _sent_through:
			if remaining == 0 or socket.get_current_outbound_buffered_amount() > POSE_BACKLOG or not send(message):
				return
			_sent_through = number
			remaining -= 1


func poll() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var now := Time.get_ticks_msec()
	if reconnecting and now >= _resume_until:
		reconnecting = false
		active = false
		result.append({"op": "closed"})
		return result
	if reconnecting and not active and now >= _retry_at:
		_attempts += 1
		pending = _identity.merged({"cursor": _cursor, "version": WebSession.ROOM_VERSION, "web": OS.has_feature("web")})
		if _dial() != OK:
			_lost(result)
	if not active:
		return result
	socket.poll()
	if reconnecting and now >= _connect_until and socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_lost(result)
		return result
	match socket.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			_lost(result)
		WebSocketPeer.STATE_OPEN:
			if not _handshake_sent:
				if not OS.has_feature("web"):
					socket.set_no_delay(true)
				_handshake_sent = true
				if not send(pending):
					_lost(result)
					return result
				pending.clear()
			for i in mini(48, socket.get_available_packet_count()):
				var raw := socket.get_packet()
				if raw.size() > MAX_FRAME or not socket.was_string_packet():
					continue
				var record: Variant = JSON.parse_string(raw.get_string_from_utf8())
				if record is Dictionary:
					_handle(record, result)
			_flush()
	return result


func send(message: Dictionary, reliable := true) -> bool:
	if not active or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var backlog := socket.get_current_outbound_buffered_amount()
	if not reliable and backlog > POSE_BACKLOG:
		# Следующая позиция заменит пропущенную. Не накапливаем старые кадры.
		return false
	if backlog > TOTAL_BACKLOG:
		socket.close(1013, "busy")
		return false
	return socket.send_text(JSON.stringify(message)) == OK


func frame(payload: String, reliable: bool, author := 1, skip := -1, to := -1, media := false) -> bool:
	var message := {"op": "frame", "payload": payload, "reliable": reliable, "author": author,
		"skip": skip, "to": to, "media": media}
	if not reliable or _identity.is_empty():
		return not reconnecting and send(message, reliable)
	if _outbox.size() >= 160 or _outbox_bytes + payload.length() > 8 * 1024 * 1024:
		return false
	_sequence += 1
	message["sequence"] = _sequence
	_outbox.append(message)
	_outbox_bytes += payload.length()
	_flush()
	return true
