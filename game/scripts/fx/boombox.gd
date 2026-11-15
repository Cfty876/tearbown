class_name Boombox
extends Node3D

const CHUNK := 24576
const IN_FLIGHT := 8 * CHUNK
const TRANSFER_TIMEOUT := 18.0
const RADIO_DOCK := -1

var world: VoxelWorld
var library := CassetteLibrary.new()
var remote_position := Vector3.ZERO
var local: AudioStreamPlayer3D
var remote: AudioStreamPlayer3D
var _out := {}
var _in := {}
var _cached_remote := {}
var _local_id := 0
var _remote_id := 0
var _round := 0
var _local_deployment := 0
var _remote_deployment := 0
var _radio_owner := -1
var _radio_cable: Node3D
var _radio_pickup := false
var _range_update := 0.0
var _insert_left := 0.0
var _pending_play := false
var _pending_title := ""
var _active_tape_id := ""
var _local_tint := BoomboxModel.EMPTY
var _remote_tint := BoomboxModel.EMPTY
var local_bands := Vector3.ZERO
var _remote_bands := Vector3.ZERO
var _local_box: StaticBody3D
var _remote_box: StaticBody3D
var _local_model: BoomboxModel
var _remote_model: BoomboxModel
var _layer: CanvasLayer
var _panel: Control
var _list: ItemList
var _status: Label
var _play: Button
var _dialog: FileDialog
var _file_callback: JavaScriptObject


func _ready() -> void:
	local = _speaker(&"Cassette local")
	remote = _speaker(&"Cassette remote")
	local.finished.connect(_release_radio)
	WebSession.media_packet.connect(_receive)


func _speaker(bus_name: StringName) -> AudioStreamPlayer3D:
	var speaker := AudioStreamPlayer3D.new()
	speaker.unit_size = 13.0
	speaker.max_distance = 104.0
	speaker.max_db = -3.0
	speaker.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	if DisplayServer.get_name() != "headless":
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.add_bus_effect(index, AudioEffectSpectrumAnalyzer.new())
		speaker.bus = bus_name
	add_child(speaker)
	return speaker


func toggle() -> void:
	var entry := library.current()
	if local.playing or _pending_play or not _out.is_empty():
		var switching := not entry.is_empty() and str(entry.id) != _active_tape_id
		_stop_local(true, switching)
		if not switching:
			return
	if entry.is_empty():
		open_library()
		return
	var bytes := library.read(entry)
	var stream := CassetteLibrary.decode(bytes, entry.ext)
	if stream == null:
		_release_radio()
		_feedback("Не удалось прочитать кассету.")
		return
	local.stream = stream
	_local_id += 1
	_active_tape_id = entry.id
	_pending_title = str(entry.title)
	_local_tint = entry.color
	_insert_left = BoomboxModel.INSERT_TIME
	world.player.tools.boombox_view.insert_tape(_local_tint)
	world.sfx.play_ui("click", -5.0, 0.85)
	if is_instance_valid(_local_model) and is_placed():
		_local_model.insert_tape(_local_tint)
	_pending_play = true
	if WebSession.can_share_media() and _send("offer", _local_id, {
		"ext": entry.ext, "size": bytes.size(), "color": _local_tint, "digest": CassetteLibrary.digest(bytes)}):
		_out = {"bytes": bytes, "sent": 0, "acked": 0, "time": TRANSFER_TIMEOUT}
		_feedback("Передаём кассету…")
	elif WebSession.connected:
		_feedback("Кассета играет у тебя. Синхронизация доступна в комнате на двоих." if not WebSession.can_share_media()
			else "Кассета играет у тебя. Не удалось начать передачу.")


func _play_at(speaker: AudioStreamPlayer3D, at: Vector3, offset := 0.0) -> void:
	speaker.global_position = at
	_shape_speaker(speaker, speaker == remote)
	speaker.play(offset)


func _stop_local(notify := true, keep_radio := false) -> void:
	if notify and (local.playing or _pending_play or not _out.is_empty()):
		_send("stop", _local_id)
	local.stop()
	_out.clear()
	_pending_play = false
	_insert_left = 0.0
	if notify and not keep_radio:
		_release_radio()
	_feedback("Воспроизведение остановлено.", false)


func reset_round(round_id: int) -> void:
	_stop_local(false)
	remote.stop()
	remote.stream = null
	_in.clear()
	_round = round_id
	_remote_id = 0
	_local_deployment = 0
	_remote_deployment = 0
	_radio_pickup = false
	_set_radio_owner(-1)
	_set_box(false, false)
	_set_box(true, false)
	if is_instance_valid(world.player.tools):
		world.player.tools.refresh_slots()


func _send(kind: String, id: int, fields := {}) -> bool:
	return WebSession.send_media({"kind": kind, "id": id, "round": _round}.merged(fields))


func _process(delta: float) -> void:
	if _insert_left > 0.0 and _insert_left <= delta:
		world.sfx.play_ui("click", -3.0, 0.71)
	_insert_left = maxf(0.0, _insert_left - delta)
	local.global_position = _source(false)
	remote.global_position = _source(true)
	if _pending_play and _insert_left <= 0.0:
		_pending_play = false
		_play_at(local, local.global_position)
		if _out.is_empty() and not WebSession.connected:
			_feedback(_pending_title)
	if not _out.is_empty():
		if not WebSession.is_reconnecting():
			_out.time -= delta
		if _out.time <= 0.0:
			_end_transfer("Кассета играет у тебя. Второй игрок не успел её получить.")
		elif _out.get("ready", false):
			if not _pending_play:
				var offset := local.get_playback_position() if local.playing else 0.0
				if _send("start", _local_id, {"offset": offset}):
					_out.clear()
					_feedback(_pending_title)
		else:
			_send_chunks()
	if not _in.is_empty():
		if not WebSession.is_reconnecting():
			_in.time -= delta
		if _in.time <= 0.0:
			_in.clear()
		elif _in.get("ready", false) and not _in.get("announced", false):
			_in.announced = _send("ready", _remote_id, {"reuse": _in.get("reuse", false)})
	_range_update -= delta
	if _range_update <= 0.0:
		_range_update = 0.12
		_shape_speaker(local, false)
		_shape_speaker(remote, true)
		local_bands = _spectrum(local)
		_remote_bands = _spectrum(remote)
	if is_placed():
		_local_model.meter(local.playing, local_bands, _on_radio(false))
	if is_instance_valid(_remote_box) and _remote_box.visible:
		_remote_model.meter(remote.playing, _remote_bands, _on_radio(true))
	if is_instance_valid(_panel) and _panel.visible:
		_play.text = "Остановить" if (local.playing or _pending_play or not _out.is_empty()) and library.selected == _active_tape_id else "Воспроизвести"


func _end_transfer(message: String) -> void:
	_send("stop", _local_id)
	_out.clear()
	_feedback(message)


func _spectrum(speaker: AudioStreamPlayer3D) -> Vector3:
	if not speaker.playing or speaker.bus == &"Master":
		return Vector3.ZERO
	var index := AudioServer.get_bus_index(speaker.bus)
	if index < 0 or AudioServer.get_bus_effect_count(index) == 0:
		return Vector3.ZERO
	var spectrum := AudioServer.get_bus_effect_instance(index, 0) as AudioEffectSpectrumAnalyzerInstance
	if spectrum == null:
		return Vector3.ZERO
	var bands := Vector3.ZERO
	var edges := [45.0, 235.0, 1700.0, 8200.0]
	for i in 3:
		var level := spectrum.get_magnitude_for_frequency_range(edges[i], edges[i + 1]).length()
		bands[i] = clampf((linear_to_db(maxf(level, 0.00001)) + 59.0) / 39.0, 0.0, 1.0)
	return bands


func _source(other: bool) -> Vector3:
	if _on_radio(other):
		return world.secrets.broadcast_position()
	var box := _remote_box if other else _local_box
	if is_instance_valid(box) and box.visible:
		return box.global_position + Vector3.UP * 0.14
	return (remote_position if other else world.player.global_position) + Vector3.UP * 1.1


func _side() -> int:
	return int(world.network_role == 2)


func _on_radio(other: bool) -> bool:
	return is_instance_valid(world.secrets) and _radio_owner == (1 - _side() if other else _side())


func _shape_speaker(speaker: AudioStreamPlayer3D, other: bool) -> void:
	var broadcast := _on_radio(other)
	var school_wide := broadcast and world.secrets is SchoolSecrets
	speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if school_wide else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	speaker.unit_size = 120.0 if broadcast else 13.0
	speaker.max_distance = 0.0 if school_wide else (450.0 if broadcast else 104.0)
	speaker.panning_strength = 0.24 if school_wide else 1.0
	if school_wide:
		speaker.volume_db = -10.0
		speaker.attenuation_filter_cutoff_hz = 7400.0
		speaker.attenuation_filter_db = -8.0
		return
	Sfx.shape_distance(speaker, -5.0, world.sfx.listener_position())


func _at_console(at: Vector3) -> bool:
	return is_instance_valid(world.secrets) and world.secrets.targets.has("monitor") and at.distance_squared_to(world.secrets.targets.monitor.global_position) <= 9.0


func broadcast_available() -> bool:
	return _radio_owner == _side() or (_radio_owner < 0 and not is_placed() and (local.playing or _pending_play or not library.current().is_empty()))


func broadcast_label() -> String:
	if _radio_owner == _side():
		return "Отключить и забрать"
	if _radio_owner >= 0:
		return "Эфир занят"
	if is_placed():
		return "Подбери бумбокс"
	if library.current().is_empty():
		return "Нет кассеты"
	return "Эфир с бумбокса"


func toggle_public_address() -> void:
	if not broadcast_available() or not _at_console(world.player.global_position):
		return
	var enabled := _radio_owner != _side()
	if world.network_role == 2:
		_send("radio_request", 0, {"enabled": enabled})
	else:
		_authorize_radio(0, enabled)


func _authorize_radio(side: int, enabled: bool) -> void:
	if enabled:
		var placed := is_placed() if side == 0 else (is_instance_valid(_remote_box) and _remote_box.visible)
		if _radio_owner >= 0 or placed or not _at_console(world.player.global_position if side == 0 else remote_position):
			return
	elif _radio_owner != side:
		return
	_set_radio_owner(side if enabled else -1)
	_send("radio_state", 0, {"side": _radio_owner})


func _set_radio_owner(side: int) -> void:
	if _radio_owner == side or (side >= 0 and not is_instance_valid(world.secrets)):
		return
	var previous := _radio_owner
	_radio_owner = side
	if previous >= 0:
		var other := previous != _side()
		_set_box(other, false)
		if is_instance_valid(_radio_cable):
			_radio_cable.hide()
		if other:
			_in.clear()
			remote.stop()
		else:
			_stop_local(true, true)
			world.player.tools.refresh_slots()
			if _radio_pickup:
				world.player.tools.select(PlayerTools.BOOMBOX)
			_radio_pickup = false
	if side >= 0:
		var other := side != _side()
		var dock := world.secrets.radio_dock()
		_set_box(other, true, dock)
		_show_radio_cable(dock)
		if not other:
			world.player.tools.refresh_slots()
	local.global_position = _source(false)
	remote.global_position = _source(true)
	_shape_speaker(local, false)
	_shape_speaker(remote, true)
	if side == _side():
		world.sfx.play_ui("click", -5.0, 1.14)
		if not local.playing and not _pending_play:
			if library.current().is_empty():
				_release_radio()
			else:
				toggle()


func _show_radio_cable(dock: Vector3) -> void:
	if not is_instance_valid(_radio_cable):
		_radio_cable = Node3D.new()
		add_child(_radio_cable)
		_radio_cable.global_position = dock
		var start := Vector3(0.237, 0.092, -0.051)
		var end := world.secrets.radio_socket() - dock
		var curve := Curve3D.new()
		curve.add_point(start, Vector3.ZERO, Vector3(0.09, 0.01, -0.14))
		curve.add_point(Vector3(0.34, 0.034, 0.085), Vector3(-0.06, 0, 0.015), Vector3(0.10, 0, -0.012))
		curve.add_point(end, Vector3(0.01, -0.04, 0.12))
		curve.bake_interval = 0.045
		var points := curve.get_baked_points()
		var rubber := StandardMaterial3D.new()
		rubber.albedo_color = Color("#344855")
		rubber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var plug := StandardMaterial3D.new()
		plug.albedo_color = Color("#cf9444")
		plug.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for i in range(1, points.size()):
			_cable_segment(points[i - 1], points[i], 0.022, rubber)
		_cable_segment(start, start + Vector3(0.045, 0, -0.014), 0.042, plug)
		_cable_segment(end, end + Vector3(0.0, -0.014, 0.05), 0.046, plug)
	_radio_cable.show()


func _cable_segment(from: Vector3, to: Vector3, width: float, material: Material) -> void:
	var segment := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, from.distance_to(to) + width * 0.38)
	segment.mesh = mesh
	segment.material_override = material
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_radio_cable.add_child(segment)
	segment.position = (from + to) * 0.5
	segment.basis = Basis.looking_at((to - from).normalized())


func _release_radio() -> void:
	if _radio_owner != _side():
		return
	if world.network_role == 2:
		_send("radio_request", 0, {"enabled": false})
	else:
		_authorize_radio(0, false)


func on_air() -> bool:
	return _on_radio(false)


func is_placed() -> bool:
	return is_instance_valid(_local_box) and _local_box.visible


func pickup_target() -> Node3D:
	if not is_placed():
		return null
	var hit := world.player.aim_ray(2.65, Layers.SOLID | Layers.BOOMBOX)
	return _local_box if hit.get("collider") == _local_box else null


func pick_up() -> bool:
	if pickup_target() == null:
		return false
	if on_air():
		_radio_pickup = true
		_release_radio()
		return true
	_set_box(false, false)
	_send("box_pickup", _local_deployment)
	world.sfx.play_ui("click", -9.0, 1.1)
	world.player.tools.refresh_slots()
	world.player.tools.select(PlayerTools.BOOMBOX)
	return true


func place() -> bool:
	var player := world.player
	if is_placed() or player.dead or not player.movement_enabled or player.vehicle or player.grabbed or is_instance_valid(player.possessed_npc) or player.hide_spot >= 0 or player.clock_locked() or player.transit_active:
		return false
	var hit := player.aim_ray(3.25, Layers.SOLID)
	if hit.is_empty() or (hit.collider.collision_layer & Layers.STATIC) == 0:
		_feedback("Наведи прицел на ровную поверхность.")
		return false
	var surface: Vector3 = hit.position
	if hit.normal.y < 0.92:
		# Adjacent voxel collision boxes can report a side normal at a floor seam.
		var probe := surface + Vector3(0.027, 0, 0.019)
		var top := world.raycast(probe + Vector3.UP * 0.065, probe - Vector3.UP * 0.065, Layers.STATIC)
		if top.is_empty() or top.normal.y < 0.92:
			_feedback("Наведи прицел на ровную поверхность.")
			return false
		surface.y = top.position.y
	var at := surface + Vector3.UP * 0.01
	var yaw := player.rotation.y
	var footprint := BoxShape3D.new()
	footprint.size = Vector3(0.51, 0.30, 0.26)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = footprint
	query.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.165)
	query.collision_mask = Layers.SOLID | Layers.PLAYER | Layers.BOOMBOX
	if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_feedback("Бумбоксу нужно больше места.")
		return false
	var edge := Vector3.RIGHT.rotated(Vector3.UP, yaw) * 0.20
	for offset in [edge, -edge]:
		if world.raycast(at + offset + Vector3.UP * 0.05, at + offset - Vector3.UP * 0.065, Layers.STATIC).is_empty():
			_feedback("Нужна опора под обеими ножками.")
			return false
	_release_radio()
	_local_deployment += 1
	_set_box(false, true, at, yaw)
	_send("box_place", _local_deployment, {"at": at, "yaw": yaw, "color": _local_tint})
	world.player.tools.refresh_slots()
	world.sfx.play("thud", at, -7.0)
	return true


func shooter_box(shooter: Player) -> StaticBody3D:
	return _local_box if shooter == world.player else _remote_box


func shotgun_hit(body: StaticBody3D, shooter: Player) -> void:
	if world.network_role != 1 or not WebSession.is_host:
		return
	var other := shooter == world.player
	var target := _remote_box if other else _local_box
	if not is_instance_valid(target) or body != target or not target.visible:
		return
	var wired := _on_radio(other)
	var id := RADIO_DOCK if wired else (_remote_deployment if other else _local_deployment)
	_break_box(other)
	_send("box_break", id, {"side": 1 if other else 0})
	if wired:
		_authorize_radio(1 if other else 0, false)


func _break_box(other: bool) -> void:
	var box := _remote_box if other else _local_box
	if not is_instance_valid(box) or not box.visible:
		return
	var at := box.global_position + Vector3.UP * 0.14
	_set_box(other, false)
	world.fx.sparks(at, Vector3.UP)
	world.fx.dust(at, Color("#8d9b9c"), 0.34)
	world.sfx.play("metal", at, -2.0, 0.76)
	var tint := _remote_tint if other else _local_tint
	for i in 8:
		var speed := Vector3(randf_range(-2.4, 2.4), randf_range(0.5, 2.1), randf_range(-2.4, 2.4))
		world.debris.spawn(at + speed * 0.045, (tint if i % 3 == 0 else Color("#354653")).srgb_to_linear(), 0.042, speed)
	if other:
		_in.clear()
		remote.stop()
		remote.stream = null
	else:
		_stop_local(false)
		world.player.tools.refresh_slots()
		_feedback("Бумбокс разбит и возвращён в инвентарь.")


func _set_box(other: bool, enabled: bool, at := Vector3.ZERO, yaw := 0.0) -> void:
	var body := _remote_box if other else _local_box
	var model := _remote_model if other else _local_model
	if not is_instance_valid(body):
		if not enabled:
			return
		body = StaticBody3D.new()
		body.collision_mask = 0
		add_child(body)
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = Vector3(0.51, 0.30, 0.26)
		shape.shape = bounds
		shape.position.y = 0.15
		body.add_child(shape)
		model = BoomboxModel.new()
		model.position.y = 0.117
		body.add_child(model)
		if other:
			_remote_box = body
			_remote_model = model
		else:
			_local_box = body
			_local_model = model
	body.visible = enabled
	body.collision_layer = Layers.BOOMBOX if enabled else 0
	if enabled:
		body.global_position = at
		body.rotation.y = yaw
		model.set_tape(_remote_tint if other else _local_tint)
	else:
		model.meter(false, Vector3.ZERO)
	var speaker := remote if other else local
	speaker.global_position = _source(other)


func _send_chunks() -> void:
	var bytes: PackedByteArray = _out.bytes
	for attempt in 4:
		var start: int = _out.sent
		if start >= bytes.size() or start - int(_out.acked) >= IN_FLIGHT:
			break
		var end := mini(bytes.size(), start + CHUNK)
		if not _send("chunk", _local_id, {"from": start, "bytes": bytes.slice(start, end)}):
			break
		_out.sent = end


func _receive(packet: Dictionary) -> void:
	if int(packet.get("round", -1)) != _round:
		return
	var id := int(packet.get("id", 0))
	match packet.get("kind", ""):
		"radio_request":
			if world.network_role == 1:
				_authorize_radio(1, bool(packet.get("enabled", false)))
		"radio_state":
			var side := int(packet.get("side", -2))
			if world.network_role == 2 and side in [-1, 0, 1]:
				_set_radio_owner(side)
		"box_place":
			var at: Variant = packet.get("at")
			var yaw := float(packet.get("yaw", 0.0))
			if (not _on_radio(true) and id > _remote_deployment and at is Vector3 and at.is_finite()
					and at.distance_squared_to(remote_position) <= 64.0 and is_finite(yaw)):
				_remote_deployment = id
				var tint: Variant = packet.get("color")
				if tint is Color:
					_remote_tint = tint
				_set_box(true, true, at, yaw)
				world.sfx.play("thud", at, -7.0)
		"box_pickup":
			if not _on_radio(true) and id == _remote_deployment:
				_set_box(true, false)
		"box_break":
			if world.network_role == 2:
				var side := int(packet.get("side", -1))
				if side == 0 and id == (RADIO_DOCK if _on_radio(true) else _remote_deployment):
					_break_box(true)
				elif side == 1 and id == (RADIO_DOCK if on_air() else _local_deployment):
					_break_box(false)
		"offer":
			var size := int(packet.get("size", 0))
			var ext := str(packet.get("ext", ""))
			if id <= _remote_id or size < 12 or size > CassetteLibrary.MAX_BYTES or ext not in CassetteLibrary.FORMATS:
				return
			_remote_id = id
			remote.stop()
			var tint: Variant = packet.get("color")
			if tint is Color:
				_remote_tint = tint
				if is_instance_valid(_remote_model) and _remote_box.visible:
					_remote_model.insert_tape(tint)
			var digest := str(packet.get("digest", ""))
			var reuse: bool = (digest.length() == 64 and digest == _cached_remote.get("digest", "")
				and size == _cached_remote.get("size", 0) and ext == _cached_remote.get("ext", ""))
			remote.stream = _cached_remote.stream if reuse else null
			_in = {"size": size, "ext": ext, "bytes": PackedByteArray(), "at": 0, "time": TRANSFER_TIMEOUT,
				"digest": digest, "ready": reuse, "reuse": reuse}
		"chunk":
			if id == _remote_id and not _in.is_empty():
				_accept_chunk(packet, id)
		"ack":
			if id == _local_id and not _out.is_empty():
				var offset := int(packet.get("at", -1))
				if offset > int(_out.acked) and offset <= int(_out.sent):
					_out.acked = offset
					_out.time = TRANSFER_TIMEOUT
		"ready":
			if (id == _local_id and not _out.is_empty()
					and (bool(packet.get("reuse", false)) or int(_out.sent) == _out.bytes.size())):
				_out.ready = true
				_out.time = TRANSFER_TIMEOUT
		"reject":
			if id == _local_id and not _out.is_empty():
				_end_transfer("Кассета играет у тебя. Второй игрок не смог её прочитать.")
		"start":
			if id == _remote_id and _in.get("ready", false) and remote.stream != null:
				_in.clear()
				var offset := float(packet.get("offset", 0.0))
				if is_finite(offset) and offset >= 0.0 and offset < remote.stream.get_length():
					_play_at(remote, _source(true), offset)
		"stop":
			if id == _remote_id:
				_in.clear()
				remote.stop()
				remote.stream = null


func _accept_chunk(packet: Dictionary, id: int) -> void:
	var payload: Variant = packet.get("bytes")
	var offset := int(packet.get("from", -1))
	if _in.get("ready", false) or not payload is PackedByteArray:
		return
	var data: PackedByteArray = payload
	if data.is_empty() or data.size() > CHUNK or offset != int(_in.at) or offset + data.size() > int(_in.size):
		return
	var bytes: PackedByteArray = _in.bytes
	_in.erase("bytes")
	bytes.append_array(data)
	var end := bytes.size()
	_in.at = end
	_in.time = TRANSFER_TIMEOUT
	if end == int(_in.size):
		remote.stream = CassetteLibrary.decode(bytes, _in.ext)
		if remote.stream != null:
			_in.ready = true
			var digest := str(_in.digest)
			if digest.length() == 64 and CassetteLibrary.digest(bytes) == digest:
				_cached_remote = {"digest": digest, "size": end, "ext": _in.ext, "stream": remote.stream}
		else:
			_send("reject", id)
			_in.clear()
	elif end % (CHUNK * 2) == 0:
		_send("ack", id, {"at": end})
	if not _in.is_empty() and not _in.get("ready", false):
		_in.bytes = bytes


func open_library() -> void:
	if world.player.navigation_menu_open:
		return
	if _panel == null:
		_make_panel()
	_refresh_list()
	world.player.navigation_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_panel.show()
	_list.grab_focus()


func _close_library() -> void:
	_panel.hide()
	world.player.navigation_menu_open = false
	world.player.tools._fire_blocked = true
	if not world.player.touch_mode and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _play_from_library() -> void:
	toggle()
	if _pending_play:
		_close_library()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_panel) and _panel.visible and not _dialog.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("cassette_library")):
		get_viewport().set_input_as_handled()
		_close_library()


func _make_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 18
	add_child(_layer)
	_panel = ColorRect.new()
	_panel.color = Color("#070a10d7")
	_layer.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell := PanelContainer.new()
	shell.custom_minimum_size.x = 530
	shell.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#152029"), Color("#60848e"), 10))
	center.add_child(shell)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 11)
	shell.add_child(body)
	body.add_child(MenuStyle.label("Бумбокс", 34, MenuStyle.GOLD))
	_list = ItemList.new()
	_list.custom_minimum_size.y = 215
	_list.add_theme_font_size_override("font_size", 19)
	_list.add_theme_color_override("font_selected_color", MenuStyle.TEXT)
	var list_panel := MenuStyle.panel(Color("#0e151b"), Color("#415561"), 5)
	list_panel.content_margin_top = 7.0
	list_panel.content_margin_bottom = 7.0
	list_panel.content_margin_left = 7.0
	list_panel.content_margin_right = 7.0
	_list.add_theme_stylebox_override("panel", list_panel)
	_list.add_theme_stylebox_override("selected", MenuStyle.panel(Color("#243843"), Color("#567a83"), 4))
	_list.add_theme_stylebox_override("selected_focus", MenuStyle.panel(Color("#2f414a"), Color("#a0835f"), 4))
	_list.item_selected.connect(func(i: int): library.select(str(library.entries[i].id)))
	_list.item_activated.connect(func(_i: int): _play_from_library())
	body.add_child(_list)
	_status = MenuStyle.label("Кассеты хранятся в этом профиле.", 15, MenuStyle.MUTED)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	body.add_child(buttons)
	_play = MenuStyle.button("Воспроизвести", _play_from_library, true, 43)
	buttons.add_child(_play)
	buttons.add_child(MenuStyle.button("Импорт", _pick_file, false, 43))
	buttons.add_child(MenuStyle.button("Закрыть", _close_library, false, 43))
	_dialog = FileDialog.new()
	_dialog.title = "Импорт кассеты"
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Аудиофайлы"])
	_dialog.file_selected.connect(_import)
	_panel.add_child(_dialog)


func _pick_file() -> void:
	if not OS.has_feature("web"):
		_dialog.popup_centered_ratio(0.72)
		return
	var browser := JavaScriptBridge.get_interface("BreakpointAudio")
	if browser == null:
		_feedback("Открытие файла в браузере недоступно.")
		return
	_file_callback = JavaScriptBridge.create_callback(_import_web)
	browser.pick(CassetteLibrary.MAX_BYTES, _file_callback)


func _import_web(values: Array) -> void:
	_file_callback = null
	if values.is_empty() or not is_instance_valid(_panel):
		return
	var filename := str(values[0])
	if values.size() < 2:
		_feedback(str(values[0]))
		return
	var bytes := JavaScriptBridge.js_buffer_to_packed_byte_array(values[1])
	var error := library.import_bytes(bytes, filename)
	_refresh_list()
	_feedback("Кассета сохранена." if error.is_empty() else error)


func _refresh_list() -> void:
	_list.clear()
	for i in library.entries.size():
		var entry := library.entries[i]
		_list.add_item("▰  " + str(entry.title))
		_list.set_item_custom_fg_color(i, entry.color)
		if entry.id == library.selected:
			_list.select(i)
	_play.disabled = library.entries.is_empty()


func _import(path: String) -> void:
	var error := library.import_file(path)
	_refresh_list()
	_feedback("Кассета сохранена." if error.is_empty() else error)


func _feedback(message: String, show_hud := true) -> void:
	if is_instance_valid(_panel) and _panel.visible:
		_status.text = message
	elif show_hud:
		var hud := get_tree().get_first_node_in_group("hud") as Hud
		if hud != null:
			hud.message(message, 2.6)
