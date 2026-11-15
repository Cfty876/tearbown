class_name OnlineRooms
extends RefCounted

const MAX_FRAME := 2100000
const POSE_BACKLOG := 131072
const TOTAL_BACKLOG := 3145728
const CONFIG_PATH := "user://online.cfg"

var socket := WebSocketPeer.new()
var pending := {}
var active := false
var _handshake_sent := false


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
	return ""


static func valid_url(value: String) -> bool:
	if value.length() > 400 or value.contains(" ") or value.contains("#") or value.contains("@"):
		return false
	return (value.begins_with("wss://") and value.length() > 6) or value.begins_with("ws://127.0.0.1:") or value.begins_with("ws://localhost:")


static func remember_url(value: String) -> void:
	var config := ConfigFile.new()
	config.set_value("online", "url", value)
	config.save(CONFIG_PATH)


func connect_room(url: String, command: Dictionary) -> Error:
	pending = command
	socket.inbound_buffer_size = MAX_FRAME + 4096
	socket.outbound_buffer_size = TOTAL_BACKLOG + 4096
	socket.max_queued_packets = 256
	socket.heartbeat_interval = 15.0
	var result := socket.connect_to_url(url)
	active = result == OK
	return result


func stop() -> void:
	active = false
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text('{"op":"leave"}')
		socket.close(1000)


func poll() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not active:
		return result
	socket.poll()
	match socket.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			active = false
			result.append({"op": "closed"})
		WebSocketPeer.STATE_OPEN:
			if not _handshake_sent:
				if not OS.has_feature("web"):
					socket.set_no_delay(true)
				_handshake_sent = true
				if not send(pending):
					active = false
					result.append({"op": "closed"})
					return result
				pending.clear()
			for i in mini(48, socket.get_available_packet_count()):
				var raw := socket.get_packet()
				if raw.size() > MAX_FRAME or not socket.was_string_packet():
					continue
				var record: Variant = JSON.parse_string(raw.get_string_from_utf8())
				if record is Dictionary:
					result.append(record)
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
	return send({"op": "frame", "payload": payload, "reliable": reliable, "author": author,
		"skip": skip, "to": to, "media": media}, reliable)
