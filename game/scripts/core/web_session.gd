extends Node

signal packet(data: Dictionary)
signal media_packet(data: Dictionary)
signal status_changed(text: String)
signal lobby_changed
signal transport_restored

const LAN_PORT := 47840
const MEDIA_CHANNEL := 2
const ROOM_VERSION := 5
var connected := false
var is_host := false
var code := ""
var last_error := ""
var local_side := 0
var rules := {}
var roster: Array[int] = []
var joined := false
var _pending: Array[Dictionary] = []
var _lan: ENetMultiplayerPeer
var _members: Array[int] = []
var _pin := ""
var _join_deadline := 0
var _lan_failure_pending := false
var _auto_start := false
var _rejected := ""
var _online: OnlineRooms
var _online_id := 0
var _online_media_at := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		multiplayer.peer_disconnected.connect(_peer_left)
		multiplayer.connected_to_server.connect(_joined_transport)
		multiplayer.connection_failed.connect(_lan_failed)
		multiplayer.server_disconnected.connect(_lan_failed)


func send(data: Dictionary, reliable := true) -> bool:
	if not connected:
		return false
	if _online != null:
		return _online.frame(JSON.stringify(data), reliable, _online_id)
	if _lan != null:
		if is_host:
			return broadcast(data, reliable, local_side)
		return rpc_id(1, "_client_reliable" if reliable else "_client_pose", JSON.stringify(data)) == OK
	return false


func broadcast(data: Dictionary, reliable: bool, side: int, skip := -1) -> bool:
	if _online != null:
		if not connected or not is_host or side < 0 or side >= roster.size():
			return false
		var excluded := roster[skip] if skip >= 0 and skip < roster.size() else -1
		return _online.frame(JSON.stringify(data), reliable, roster[side], excluded)
	if _lan == null:
		return false
	var raw := JSON.stringify(data)
	var delivered := true
	for i in range(1, roster.size()):
		if i != skip:
			var result := rpc_id(roster[i], "_host_reliable" if reliable else "_host_pose", raw, side)
			delivered = delivered and result == OK
	return delivered


func send_to_side(side: int, data: Dictionary) -> bool:
	if not is_host or not connected or side <= 0 or side >= roster.size():
		return false
	if _online != null:
		return _online.frame(JSON.stringify(data), true, _online_id, -1, roster[side])
	return _lan != null and rpc_id(roster[side], "_host_reliable", JSON.stringify(data), 0) == OK


func can_share_media() -> bool:
	return connected and (_lan != null or _online != null) and roster.size() == 2


func send_media(data: Dictionary) -> bool:
	if not can_share_media():
		return false
	if _online != null:
		var chunk: bool = data.get("kind", "") == "chunk"
		var now := Time.get_ticks_msec()
		# Передача кассеты оставляет место в очереди для игрового трафика.
		if chunk and now < _online_media_at:
			return false
		var sent := _online.frame(Marshalls.raw_to_base64(var_to_bytes(data)), true, _online_id, -1, roster[1 - local_side], true)
		if sent and chunk:
			_online_media_at = now + 200
		return sent
	return rpc_id(roster[1 - local_side], "_lan_media", data) == OK


func drain() -> void:
	for data in _pending:
		packet.emit(data)
	_pending.clear()


func leave() -> void:
	connected = false
	joined = false
	is_host = false
	code = ""
	rules = {}
	roster.clear()
	_members.clear()
	_pending.clear()
	_join_deadline = 0
	_lan_failure_pending = false
	_rejected = ""
	local_side = 0
	_auto_start = false
	_online_id = 0
	_online_media_at = 0
	if _online != null:
		_online.stop()
		_online = null
	if _lan != null:
		var peer := _lan
		_lan = null
		multiplayer.multiplayer_peer = null
		peer.close()


func is_online() -> bool:
	return _online != null


func is_reconnecting() -> bool:
	return _online != null and _online.reconnecting


func host_online(map: String, options: Dictionary, endpoint := "") -> void:
	if GameState.room_map_allowed(map):
		_open_online({"op": "create", "rules": RoomRules.normalized(map, options)}, endpoint)


func join_room(raw: String, endpoint := "") -> void:
	var key := raw.strip_edges().to_upper()
	if key.begins_with("BP-"):
		var digits := key.substr(3).replace("-", "")
		if digits.length() != 8 or not digits.is_valid_hex_number() or digits.begins_with("+"):
			_status("Проверь код онлайн-комнаты. Пример BP-A1B2-C3D4.")
			return
		_open_online({"op": "join", "code": "BP-%s-%s" % [digits.left(4), digits.right(4)]}, endpoint)
	elif OS.has_feature("web"):
		_status("Введите онлайн-код, например BP-A1B2-C3D4.")
	else:
		join_lan(key)


func _open_online(command: Dictionary, endpoint: String) -> void:
	leave()
	var url := endpoint.strip_edges()
	if url.is_empty():
		url = OnlineRooms.configured_url()
	if not OnlineRooms.valid_url(url):
		_status("Сервер комнат пока недоступен." if OS.has_feature("web") else "Введи WSS-адрес сервера комнат.")
		return
	command["version"] = ROOM_VERSION
	var transport := OnlineRooms.new()
	if transport.connect_room(url, command) != OK:
		_status("Не удалось открыть соединение с сервером комнат.")
		return
	_online = transport
	last_error = ""
	_join_deadline = Time.get_ticks_msec() + 24000
	_status("Подключаемся к серверу комнат…")


func _receive_online(message: Dictionary) -> void:
	var operation := str(message.get("op", ""))
	match operation:
		"closed", "error":
			_online_failed(str(message.get("message", "")))
		"reconnecting":
			_status("Переподключаемся к комнате…")
			get_tree().call_group("hud", "message", "Переподключаемся к комнате…", 4.0)
		"lobby", "start", "resumed":
			var options: Dictionary = message.get("rules", {})
			var map := str(options.get("map", ""))
			if connected:
				if operation == "resumed":
					get_tree().call_group("hud", "message", "Связь восстановлена", 3.0)
					transport_restored.emit()
				return
			if not GameState.room_map_allowed(map):
				_online_failed("Для этой комнаты нужна другая версия игры.")
				return
			_members.clear()
			for id in message.get("members", []):
				_members.append(int(id))
			_online_id = int(message.get("id", 0))
			if _online_id not in _members or _members.is_empty() or _members[0] != 1:
				_online_failed("Сервер прислал неверный состав комнаты.")
				return
			code = str(message.get("code", ""))
			is_host = _online_id == 1
			rules = RoomRules.normalized(map, options)
			_join_deadline = 0
			joined = true
			if operation == "start" or (operation == "resumed" and bool(message.get("started", false))):
				roster.assign(_members)
				local_side = roster.find(_online_id)
				connected = true
				GameState.start.call_deferred(map)
			else:
				_status("В комнате · %s" % GameState.map_info(map)[0])
				lobby_changed.emit()
		"frame":
			var side := roster.find(int(message.get("author", 0)))
			var raw := str(message.get("payload", ""))
			if bool(message.get("media", false)):
				if can_share_media() and side == 1 - local_side and raw.length() <= 45000 and not raw.is_empty():
					var data: Variant = bytes_to_var(Marshalls.base64_to_raw(raw))
					if data is Dictionary:
						media_packet.emit(data)
			else:
				_decode(raw, side)


func _online_failed(message: String) -> void:
	var in_game := connected
	leave()
	last_error = message if not message.is_empty() else ("Связь с сервером комнат потеряна." if in_game else "Сервер комнат недоступен. Проверь адрес и подключение.")
	_status(last_error)
	lobby_changed.emit()
	if in_game:
		GameState.to_menu.call_deferred()


func host_lan(map: String, options := {}) -> void:
	leave()
	if not GameState.MAPS.has(map):
		return
	rules = RoomRules.normalized(map, options)
	_auto_start = bool(options.get("auto_start", false))
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(LAN_PORT, RoomRules.MAX_HUMANS, MEDIA_CHANNEL + 1)
	if result != OK:
		_status("Не удалось открыть комнату на порту %d." % LAN_PORT)
		return
	_lan = peer
	is_host = true
	joined = true
	_pin = "%04X" % randi_range(0, 65535)
	code = code_for(lan_addresses()[0])
	_members.assign([1])
	last_error = ""
	multiplayer.multiplayer_peer = peer
	_refresh_lobby()


func code_for(ip: String) -> String:
	var result := ""
	var octets := ip.split(".")
	if octets.size() != 4:
		return ""
	for octet in octets:
		result += "%02X" % int(octet)
	return "%s-%s-%s" % [result.left(4), result.right(4), _pin]


static func decode_code(raw: String) -> PackedStringArray:
	var key := raw.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if key.length() != 12 or not key.is_valid_hex_number() or key.begins_with("+"):
		return []
	var parts := PackedStringArray()
	for i in range(0, 8, 2):
		parts.append(str(key.substr(i, 2).hex_to_int()))
	return [".".join(parts), key.right(4)]


func join_lan(raw: String, legacy := false) -> void:
	leave()
	var decoded := decode_code(raw)
	if decoded.is_empty() and legacy and raw.is_valid_ip_address():
		decoded = PackedStringArray([raw, ""])
	if decoded.is_empty():
		_status("Введите код из окна создателя комнаты, например C0A8-0118-5BCD.")
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(decoded[0], LAN_PORT, MEDIA_CHANNEL + 1) != OK:
		_status("Подключение к комнате не удалось.")
		return
	_lan = peer
	_pin = decoded[1]
	last_error = ""
	_join_deadline = Time.get_ticks_msec() + 12000
	multiplayer.multiplayer_peer = peer
	_status("Подключаемся к комнате…")


func lan_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			addresses.append(ip)
	addresses.sort_custom(func(a: String, b: String): return int(b.begins_with("192.168.")) < int(a.begins_with("192.168.")))
	if addresses.is_empty():
		addresses.append("127.0.0.1")
	return addresses


func can_start() -> bool:
	return joined and is_host and not connected and _members.size() == RoomRules.human_count(rules)


func lobby_count() -> int:
	return _members.size()


func auto_rounds() -> bool:
	return _auto_start


func _process(_delta: float) -> void:
	if _online != null:
		var transport := _online
		for message in transport.poll():
			if _online != transport:
				break
			_receive_online(message)
		if _online != null and _join_deadline > 0 and Time.get_ticks_msec() > _join_deadline:
			_online_failed("")
	elif _join_deadline > 0 and Time.get_ticks_msec() > _join_deadline:
		_lan_failed()


func _joined_transport() -> void:
	if _lan != null and not is_host:
		rpc_id(1, "_hello", _pin, ROOM_VERSION)


@rpc("any_peer", "call_remote", "reliable")
func _hello(pin: String, version: int) -> void:
	if _lan == null or not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer in _members:
		return
	if version != ROOM_VERSION or (pin != _pin and not (_auto_start and pin.is_empty())):
		rpc_id(peer, "_denied", "Код комнаты неверен или сборки игры различаются.")
		return
	if connected or _members.size() >= RoomRules.human_count(rules):
		rpc_id(peer, "_denied", "Комната заполнена или игра уже началась.")
		return
	_members.append(peer)
	_refresh_lobby()
	if _auto_start and can_start():
		begin_room.call_deferred()


func _refresh_lobby() -> void:
	for peer in _members:
		if peer != 1:
			rpc_id(peer, "_lobby_state", rules, _members)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _lobby_state(options: Dictionary, members: Array[int]) -> void:
	if _lan == null or is_host or not GameState.MAPS.has(options.get("map")):
		return
	rules = RoomRules.normalized(str(options.map), options)
	_members = members
	_join_deadline = 0
	joined = true
	_status("В комнате · %s" % GameState.MAPS[rules.map][0])
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _denied(message: String) -> void:
	_rejected = message
	_lan_failed()


func begin_room() -> void:
	if not can_start():
		return
	if _online != null:
		_online.send({"op": "start"})
		return
	roster.assign(_members)
	_lan.refuse_new_connections = true
	for peer in roster:
		if peer != 1:
			rpc_id(peer, "_start_lan", rules, roster)
	connected = true
	print("[lan] host start ", rules.map, " roster ", roster, " rules ", rules)
	GameState.start.call_deferred(str(rules.map))


@rpc("authority", "call_remote", "reliable")
func _start_lan(options: Dictionary, members: Array[int]) -> void:
	if _lan == null or is_host or connected or not joined or not GameState.MAPS.has(options.get("map")):
		return
	rules = RoomRules.normalized(str(options.map), options)
	roster = members
	local_side = roster.find(multiplayer.get_unique_id())
	if local_side <= 0:
		return
	connected = true
	print("[lan] guest start ", rules.map, " side ", local_side, " roster ", roster)
	GameState.start.call_deferred(str(rules.map))


@rpc("any_peer", "call_remote", "reliable")
func _client_reliable(raw: String) -> void:
	_client_message(raw)


@rpc("any_peer", "call_remote", "unreliable")
func _client_pose(raw: String) -> void:
	_client_message(raw)


@rpc("authority", "call_remote", "reliable")
func _host_reliable(raw: String, side: int) -> void:
	if not is_host:
		_decode(raw, side)


@rpc("authority", "call_remote", "unreliable")
func _host_pose(raw: String, side: int) -> void:
	if not is_host:
		_decode(raw, side)


@rpc("any_peer", "call_remote", "reliable", 2)
func _lan_media(data: Dictionary) -> void:
	if can_share_media() and multiplayer.get_remote_sender_id() == roster[1 - local_side]:
		media_packet.emit(data)


func _client_message(raw: String) -> void:
	var side := roster.find(multiplayer.get_remote_sender_id())
	if is_host and side > 0:
		_decode(raw, side)


func _decode(raw: String, side: int) -> void:
	if not connected or raw.length() > 2000000 or side < 0 or side >= roster.size():
		return
	var data = JSON.parse_string(raw)
	if data is Dictionary:
		data["_side"] = side
		_queue_packet(data)


func _peer_left(id: int) -> void:
	if _lan == null or not is_host or id not in _members:
		return
	_members.erase(id)
	if connected:
		_lan_failed()
	else:
		_refresh_lobby()


func _lan_failed() -> void:
	if _lan == null or _lan_failure_pending:
		return
	_lan_failure_pending = true
	_finish_lan_failure.call_deferred(_lan)


func _finish_lan_failure(peer: ENetMultiplayerPeer) -> void:
	if peer != _lan:
		return
	var in_game := connected
	var message := _rejected
	leave()
	last_error = message if not message.is_empty() else ("Соединение потеряно." if in_game else "Комната недоступна. Проверьте код и локальную сеть.")
	_status(last_error)
	lobby_changed.emit()
	if in_game:
		GameState.to_menu.call_deferred()


func _status(value: String) -> void:
	status_changed.emit(value)


func _queue_packet(data: Dictionary) -> void:
	if packet.get_connections().is_empty():
		if _pending.size() < 256:
			_pending.append(data)
	else:
		packet.emit(data)
