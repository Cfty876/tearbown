class_name NetworkHide
extends Node

const HIDE_SECONDS := 22.0
const SEEK_SECONDS := 105.0
const FINISH_SECONDS := 5.0
const MAX_VOLUME := 1000000
var player: Player
var world: VoxelWorld
var pause_menu: PauseMenu
var _proxy: Player
var _avatar: MeshInstance3D
var _remote_position := Vector3.ZERO
var _remote_yaw := 0.0
var _remote_seen := false
var _dynamic := {}
var _phase := "wait"
var _remaining := 0.0
var _deadline_ms := 0
var _round := 0
var _seeker_host := true
var _result := ""
var _pose_timer := 0.0
var _pose_serial := 0
var _remote_serial := -1
var _state_timer := 0.0
var _fire_timer := 0.0
var _fire_visible := false
var _fire_last := false
var _tool_last := -1
var _hud: Label


func _ready() -> void:
	player.god_mode = true
	player.interaction_enabled = false
	player.tools.mirror_only = not WebSession.is_host
	player.tools.input_enabled = false
	var model := Build.vol(Vector3i(6, 17, 4))
	model.fill_box(Vector3i(0, 0, 0), Vector3i(2, 7, 4), VoxMat.id("metal_dark"))
	model.fill_box(Vector3i(4, 0, 0), Vector3i(6, 7, 4), VoxMat.id("metal_dark"))
	model.fill_box(Vector3i(0, 7, 0), Vector3i(6, 13, 4), VoxMat.id("road_yellow"))
	model.fill_box(Vector3i(1, 13, 0), Vector3i(5, 17, 4), VoxMat.id("wood"))
	_avatar = VoxModel.instance(model, 0.1, Vector3(3, 0, 2))
	_avatar.hide()
	add_child(_avatar)
	if WebSession.is_host:
		_proxy = Player.new()
		_proxy.god_mode = true
		add_child(_proxy)
		_proxy.set_physics_process(false)
		_proxy.set_process(false)
		_proxy.set_process_unhandled_input(false)
		_proxy.collision_layer = 0
		_proxy.collision_mask = 0
		_proxy.tools.hide()
		_proxy.tools.input_enabled = false
		_proxy.tools.set_process_unhandled_input(false)
		player.camera.make_current()
		world.network_dirty.clear()
		world.network_blast.connect(func(at: Vector3, radius: float):
			WebSession.send({"k": "blast", "p": _pack(at), "r": radius}))
	else:
		world.fire.set_process(false)
		world.fire.show_fire(PackedVector3Array())
		for object in world.objects:
			_freeze_replica(object)
	var canvas := CanvasLayer.new()
	canvas.layer = 12
	add_child(canvas)
	_hud = Label.new()
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -430
	_hud.offset_right = 430
	_hud.offset_top = 85
	_hud.add_theme_font_size_override("font_size", 31)
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_color_override("font_color", Color("#ffe4ac"))
	canvas.add_child(_hud)
	WebSession.packet.connect(_receive)
	WebSession.drain()
	WebSession.send({"k": "ready"})


func _process(delta: float) -> void:
	var allowed := _phase == "seek" or (_phase == "hide" and not _am_seeker())
	player.movement_enabled = allowed and not pause_menu.is_open()
	player.tools.input_enabled = _phase == "seek" and not pause_menu.is_open()
	if not WebSession.is_host:
		var fire := player.tools.input_enabled and not player.tools._inventory_open and not player.tools._fire_blocked \
			and (Input.is_action_pressed("fire") or Input.is_action_just_pressed("fire"))
		if fire != _fire_last or player.tools.current != _tool_last:
			_fire_last = fire
			_tool_last = player.tools.current
			WebSession.send({"k": "tool", "fire": fire, "tool": _tool_last,
				"p": _pack(player.position), "y": player.rotation.y, "x": player.head.rotation.x})
	_remaining = maxf(0.0, (_deadline_ms - Time.get_ticks_msec()) * 0.001)
	if WebSession.is_host:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = 0.25
			_send_fire()
		match _phase:
			"hide":
				if _remaining <= 0.0:
					_phase = "seek"
					_set_remaining(SEEK_SECONDS)
					_send_state()
			"seek":
				if _caught():
					_finish("Игрок найден")
				elif _remaining <= 0.0:
					_finish("Прячущийся продержался")
			"done":
				if _remaining <= 0.0:
					_start_round()
	var smoothing := 1.0 - exp(-15.0 * delta)
	_avatar.position = _avatar.position.lerp(_remote_position, smoothing)
	_avatar.rotation.y = lerp_angle(_avatar.rotation.y, _remote_yaw, smoothing)
	_avatar.visible = _remote_seen and (_phase == "seek" or _phase == "done" or (_phase == "hide" and not _am_seeker()))
	for id in _dynamic:
		var o: VoxelObject = world.network_objects.get(id)
		if is_instance_valid(o):
			o.global_transform = o.global_transform.interpolate_with(_dynamic[id], smoothing)
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = 0.058
		_send_pose()
		if WebSession.is_host:
			_flush_voxels()
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 0.75
		if WebSession.is_host:
			_send_state()
		elif _phase == "wait":
			WebSession.send({"k": "ready"})
	_update_label()


func _am_seeker() -> bool:
	return WebSession.is_host == _seeker_host


func _caught() -> bool:
	if not _remote_seen or player.position.distance_squared_to(_remote_position) > 2.15 * 2.15:
		return false
	return world.raycast(player.position + Vector3.UP, _remote_position + Vector3.UP).is_empty()


func _start_round() -> void:
	_round += 1
	_seeker_host = _round % 2 == 1
	_phase = "hide"
	_set_remaining(HIDE_SECONDS)
	_result = ""
	_reset_player()
	_send_state()


func _reset_player() -> void:
	var i := 0 if WebSession.is_host else 1
	player.position = HideLevel.SPAWNS[i]
	player.velocity = Vector3.ZERO
	player.look_at_dir(0.0 if i == 0 else PI, 0.0)
	_remote_position = HideLevel.SPAWNS[1 - i]
	_avatar.position = _remote_position
	_remote_seen = false
	if is_instance_valid(_proxy):
		_proxy.tools.sim_fire = false


func _finish(reason: String) -> void:
	_phase = "done"
	_set_remaining(FINISH_SECONDS)
	_result = reason
	if is_instance_valid(_proxy):
		_proxy.tools.sim_fire = false
	_send_state()


func _send_state() -> void:
	WebSession.send({"k": "state", "phase": _phase, "t": _remaining, "round": _round,
		"seeker": _seeker_host, "result": _result})


func _set_remaining(seconds: float) -> void:
	_remaining = seconds
	_deadline_ms = Time.get_ticks_msec() + roundi(seconds * 1000.0)


func _update_label() -> void:
	var role := "ИЩУЩИЙ" if _am_seeker() else "ПРЯЧУЩИЙСЯ"
	var seconds := "%02d:%02d" % [int(_remaining) / 60, int(_remaining) % 60]
	var value := "Ждём загрузку друга…"
	match _phase:
		"hide": value = role + "  ·  ПРЯТАТЬСЯ  " + seconds
		"seek": value = role + "  ·  ПОИСК  " + seconds
		"done": value = _result + "  ·  смена ролей " + seconds
	if _hud.text != value:
		_hud.text = value


func _pack(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _unpack(v: Variant) -> Vector3:
	if not v is Array or v.size() != 3:
		return Vector3.ZERO
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


func _xform(o: VoxelObject) -> Array:
	var q := o.global_basis.get_rotation_quaternion()
	return [_pack(o.global_position), [q.x, q.y, q.z, q.w]]


func _decode_xform(data: Array) -> Transform3D:
	var q: Array = data[1]
	return Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), _unpack(data[0]))


func _send_pose() -> void:
	_pose_serial += 1
	var p := {"k": "pose", "s": _pose_serial, "p": _pack(player.position), "y": player.rotation.y, "x": player.head.rotation.x}
	if WebSession.is_host:
		var dynamic: Array = []
		for o: VoxelObject in world.objects:
			if not o.static_mode and dynamic.size() < 42:
				dynamic.append([o.network_id, _xform(o)])
		p["dynamic"] = dynamic
	WebSession.send(p, false)


func _read_pose(p: Dictionary) -> void:
	var at := _unpack(p.get("p"))
	if not at.is_finite() or absf(at.x) > 15.0 or absf(at.z) > 15.0 or at.y < -2.0 or at.y > 18.0:
		return
	_remote_position = at
	_remote_yaw = float(p.get("y", 0.0))
	_remote_seen = true
	if is_instance_valid(_proxy):
		_proxy.position = at
		_proxy.look_at_dir(_remote_yaw, clampf(float(p.get("x", 0.0)), -1.53, 1.53))


func _receive(p: Dictionary) -> void:
	var kind: String = p.get("k", "")
	if kind == "pose":
		var serial := int(p.get("s", -1))
		if serial <= _remote_serial:
			return
		_remote_serial = serial
		_read_pose(p)
		if not WebSession.is_host:
			for entry in p.get("dynamic", []):
				_dynamic[int(entry[0])] = _decode_xform(entry[1])
		return
	if WebSession.is_host:
		match kind:
			"ready":
				if _phase == "wait":
					_start_round()
			"tool":
				if _phase == "seek":
					_read_pose(p)
					_proxy.tools.select(clampi(int(p.get("tool", 0)), 0, PlayerTools.NAMES.size() - 1))
					var fire := bool(p.get("fire", false))
					_proxy.tools.remote_tap = fire and not _proxy.tools.sim_fire
					_proxy.tools.sim_fire = fire
		return
	match kind:
		"state":
			var new_round := int(p.get("round", 0))
			if new_round != _round:
				_round = new_round
				_reset_player()
			_phase = str(p.get("phase", "wait"))
			_set_remaining(float(p.get("t", 0.0)))
			_seeker_host = bool(p.get("seeker", true))
			_result = str(p.get("result", ""))
		"blast":
			var at := _unpack(p.get("p"))
			var radius := clampf(float(p.get("r", 1.0)), 0.1, 5.0)
			world.fx.explosion(at, radius)
			world.sfx.play("explosion", at, 6.0 + radius * 2.0)
			player.shake(clampf(radius * 1.6 / maxf(player.global_position.distance_to(at), 1.0), 0.0, 1.0))
		"gone":
			for id in p.get("ids", []):
				var o: VoxelObject = world.network_objects.get(int(id))
				_dynamic.erase(int(id))
				if is_instance_valid(o):
					o.queue_free()
		"vox":
			_apply_voxels(p)
		"fire":
			var points := PackedVector3Array()
			for at in p.get("points", []).slice(0, FireSystem.MAX_FIRES):
				points.append(_unpack(at))
			world.fire.show_fire(points)


func _send_fire() -> void:
	var points := world.fire.visual_positions()
	if points.is_empty() and not _fire_visible:
		return
	var packed: Array = []
	for at in points:
		packed.append(_pack(at))
	if WebSession.send({"k": "fire", "points": packed}):
		_fire_visible = not points.is_empty()


func _flush_voxels() -> void:
	if not world.network_removed.is_empty():
		if WebSession.send({"k": "gone", "ids": world.network_removed}):
			world.network_removed.clear()
	for id in world.network_dirty.keys().slice(0, 3):
		var o: VoxelObject = world.network_objects.get(id)
		if not is_instance_valid(o):
			world.network_dirty.erase(id)
			continue
		var raw := o.volume.get_data()
		if raw.size() > MAX_VOLUME:
			world.network_dirty.erase(id)
			continue
		var dim := o.volume.get_size()
		var packet := {
			"k": "vox", "id": id, "dim": [dim.x, dim.y, dim.z],
			"static": o.static_mode, "transform": _xform(o),
			"bytes": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_FASTLZ)),
		}
		if WebSession.send(packet):
			world.network_dirty.erase(id)


func _apply_voxels(packet: Dictionary) -> void:
	var id := int(packet.get("id", 0))
	if id <= 0 or id > 10000:
		return
	var d := _unpack(packet.get("dim"))
	var dim := Vector3i(d)
	var size := dim.x * dim.y * dim.z
	if dim.x <= 0 or dim.y <= 0 or dim.z <= 0 or size > MAX_VOLUME:
		return
	var compressed := Marshalls.base64_to_raw(str(packet.get("bytes", "")))
	var raw := compressed.decompress(size, FileAccess.COMPRESSION_FASTLZ)
	if raw.size() != size:
		return
	var o: VoxelObject = world.network_objects.get(id)
	if is_instance_valid(o):
		if o.volume.get_size() != dim:
			return
		o.volume.set_data(raw)
		o.mark_dirty(Vector3i.ZERO, dim - Vector3i.ONE)
	else:
		var v := Build.vol(dim)
		v.set_data(raw)
		o = VoxelObject.new()
		o.network_id = id
		o.setup(v, bool(packet.get("static", false)))
		o.transform = _decode_xform(packet["transform"])
		world.add_child(o)
		_freeze_replica(o)


func _freeze_replica(o: VoxelObject) -> void:
	if not o.static_mode:
		o.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		o.freeze = true
