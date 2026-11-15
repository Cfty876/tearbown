class_name SchoolPopulation
extends Node3D

signal requested(action: String, id: int, direction: Vector3)
signal confirmed(event: Dictionary)
signal exhausted(side: int)

const RANGE := 7.5
const ROLES := {"cook": "Повар", "guard": "Охранник", "mechanic": "Механик",
	"teacher": "Учитель", "student": "Ученик"}

var world: VoxelWorld
var level: SchoolLevel
var actors: Array[SchoolNpc] = []
var _seats: Array[Dictionary] = []
var local_side := 0
var local_allowed := true
var remote_poses := {}
var _held := [-1, -1]
var _time := 0.0
var _health := [100.0, 100.0]
var _grace := [0.0, 0.0]
var _revision := 0
var _exit_shape := CapsuleShape3D.new()


func _ready() -> void:
	_held.resize(RoomRules.SIDES)
	_held.fill(-1)
	_health.resize(RoomRules.SIDES)
	_health.fill(100.0)
	_grace.resize(RoomRules.SIDES)
	_grace.fill(0.0)
	_exit_shape.radius = 0.32
	_exit_shape.height = 1.77
	var at := func(x: float, z: float): return Vector3(x, 2.22, z)
	_spawn("cook", 0, 0.0, level.npc_jobs.get("cook"), [
		[SchoolNpcRoutes.station(at.call(53.7, -6.8), PI / 2, "cook")],
		[SchoolNpcRoutes.station(at.call(49.35, -5.25), PI / 2, "wipe"),
		 SchoolNpcRoutes.station(at.call(49.35, -8.6), PI / 2, "wipe")],
		[SchoolNpcRoutes.station(at.call(48.4, -4.1), 0.0, "eat", 0.51, at.call(49.3, -4.1))]])
	_spawn("guard", 1, 11.0, null, [
		[SchoolNpcRoutes.station(at.call(-5.4, 3.9), 0.0, "monitor", 0.51, at.call(-4.0, 3.9))],
		[SchoolNpcRoutes.station(Vector3(-3.6, 2.04, -15.4), 0.0, "patrol"),
		 SchoolNpcRoutes.station(Vector3(3.6, 2.04, -18.6), PI / 2, "patrol")],
		[SchoolNpcRoutes.station(at.call(1.95, 9.7), PI, "watch")]])
	_spawn("mechanic", 2, 19.0, level.npc_jobs.get("mechanic"), [
		[SchoolNpcRoutes.station(at.call(46.86, 68.0), -PI / 2, "wipe"),
		 SchoolNpcRoutes.station(at.call(46.86, 69.5), -PI / 2, "wipe")],
		[SchoolNpcRoutes.station(at.call(54.1, 61.2), 0.0, "sweep"),
		 SchoolNpcRoutes.station(at.call(55.0, 62.0), PI / 2, "sweep")],
		[SchoolNpcRoutes.station(at.call(55.3, 69.7), 0.0, "rest", 0.51, at.call(54.6, 69.7))]])
	for i in level.npc_classes.size():
		_class_group(level.npc_classes[i], i)
	var basement_y := SchoolLevel.BASEMENT + 0.22
	_spawn("guard", 3, 12.0, null, [
		[SchoolNpcRoutes.station(Vector3(-10.54, basement_y, -1.02), 0.0, "inspect")],
		[SchoolNpcRoutes.station(Vector3(-10.85, basement_y, 0.61), -PI / 2, "patrol"),
		 SchoolNpcRoutes.station(Vector3(-5.25, basement_y, 0.61), PI / 2, "patrol")],
		[SchoolNpcRoutes.station(Vector3(-8.25, basement_y, 4.22), 0.0, "rest", 0.51,
		 Vector3(-8.25, basement_y, 3.42))]])


func _spawn(role: String, variant: int, offset: float, routes: SchoolNpcRoutes, routines: Array, teacher: SchoolNpc = null) -> SchoolNpc:
	var npc := SchoolNpc.new()
	npc.id = actors.size()
	npc.name = "%s %02d" % [ROLES[role], npc.id + 1]
	npc.role = role
	npc.variant = variant
	npc.routes = routes
	npc.routines = routines
	npc.teacher = teacher
	npc.order_offset = offset
	actors.append(npc)
	add_child(npc)
	for shift: Array in routines:
		for station: Dictionary in shift:
			if station.seat > 0.0:
				_seats.append(station)
	return npc


func _class_group(plan: Dictionary, index: int) -> void:
	var routes: SchoolNpcRoutes = plan.routes
	var area: Rect2i = plan.area
	var chair: Vector3i = plan.teacher_chair
	var desks: Array = plan.student_chairs
	if chair == Vector3i.ZERO or desks.size() < 5:
		push_error("School NPC room %d has %d desks and teacher seat %s" % [index + 1, desks.size(), chair])
		return
	var origin := routes.origin
	var offset := 4.0 + float(index * 8)
	var chair_at := origin + Vector3(chair + Vector3i(2, 0, 2)) * 0.1 + Vector3.UP * 0.02
	var teacher_access := chair_at + Vector3(-0.75, 0, 0.07)
	var board := origin + Vector3((area.position.x + 24) * 0.1, 0.22, (area.position.y + 12) * 0.1)
	var desk_aisle := origin + Vector3((area.position.x + 33) * 0.1, 0.22, (area.position.y + 30) * 0.1)
	var teacher := _spawn("teacher", index, offset, routes, [
		[SchoolNpcRoutes.station(board, 0.0, "board")],
		[SchoolNpcRoutes.station(chair_at, PI, "teach", 0.51, teacher_access)],
		[SchoolNpcRoutes.station(desk_aisle, PI, "walk"),
		 SchoolNpcRoutes.station(desk_aisle + Vector3(0, 0, 4.2), 0.0, "walk")]])
	var bench: Vector3i = plan.bench
	var bench_side := 1.0 if plan.col == 0 else -1.0
	for student in 5:
		chair = desks[student]
		chair_at = origin + Vector3(chair + Vector3i(2, 0, 2)) * 0.1 + Vector3.UP * 0.02
		var dir := 1.0 if chair.x < area.position.x + 28 else -1.0
		var access := chair_at + Vector3(dir * 0.57, 0, -0.05)
		var bench_at := origin + Vector3(bench + Vector3i(0, 0, 3 + student * 5)) * 0.1 + Vector3.UP * 0.02
		var bench_access := bench_at + Vector3(bench_side * 0.68, 0, 0)
		var hall_x := 8.25 + float(student) * 0.57
		var hall_z: float = (plan.door_z + 8) * 0.1
		var delay := 0.7 + float((index * 3 + student * 7) % 10) * 0.43
		_spawn("student", index * 5 + student, offset - delay, routes, [
			[SchoolNpcRoutes.station(origin + Vector3(hall_x, 0.22, hall_z + 1.5 + student * 0.6), PI, "run"),
			 SchoolNpcRoutes.station(origin + Vector3(hall_x, 0.22, hall_z - 1.15 - student * 0.6), 0.0, "run")],
			[SchoolNpcRoutes.station(chair_at, 0.0, "study", 0.51, access)],
			[SchoolNpcRoutes.station(bench_at, -bench_side * PI * 0.5, "break", 0.51, bench_access)]], teacher)


func _physics_process(delta: float) -> void:
	var frozen := world.gadgets.clock_active()
	if not frozen:
		_time += delta
	for side in _held.size():
		_grace[side] = maxf(0.0, _grace[side] - delta)
	var player := world.player
	var eye := player.camera.global_position
	var targets: Array[Vector3] = []
	if _held[local_side] < 0:
		targets.append(eye)
	for side: int in remote_poses:
		if _held[side] < 0:
			targets.append(remote_poses[side].at + Vector3.UP * 1.4)
	for npc in actors:
		if npc.removed:
			continue
		if npc.holder == local_side:
			npc.control(player.global_position, player.rotation.y, player.head.rotation.x, delta)
		elif world.network_role == 1 and remote_poses.has(npc.holder):
			var pose: Dictionary = remote_poses[npc.holder]
			npc.control(pose.at, pose.yaw, pose.pitch, delta)
		elif world.network_role == 2:
			npc.interpolate_pose(delta)
		elif not frozen:
			npc.think(delta, _time, world, targets)
		npc.present(delta, eye, frozen)


func round_reset() -> void:
	_time = 0.0
	_health.resize(RoomRules.SIDES)
	_health.fill(100.0)
	_grace.resize(RoomRules.SIDES)
	_grace.fill(0.0)
	_revision = 0
	remote_poses.clear()
	for side in _held.size():
		var npc := actor(_held[side])
		if npc:
			npc.set_holder(-1, false)
	_held.resize(RoomRules.SIDES)
	_held.fill(-1)
	_set_local_player(null, Vector3.INF)
	world.player.health = Player.MAX_HEALTH
	for npc in actors:
		npc.reset(_time)


func actor(id: int) -> SchoolNpc:
	return actors[id] if id >= 0 and id < actors.size() else null


func disguise(side: int) -> int:
	return _held[side]


func concealed(side: int) -> bool:
	return _held[side] >= 0 or _grace[side] > 0.0


func trace(from: Vector3, to: Vector3, mask: int, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask | Layers.NPC, exclude)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func aim_target(player: Player) -> SchoolNpc:
	var eye := player.camera.global_position
	var hit := trace(eye, eye + player.aim_dir() * RANGE, Layers.SOLID | Layers.CLOTH, [player.get_rid()])
	return hit.get("collider") as SchoolNpc


func fire_tool(player: Player) -> void:
	if not local_allowed:
		return
	var npc := aim_target(player)
	if npc == null:
		_note("Наведи устройство на персонажа в пределах 7,5 м")
		return
	if npc.offended or npc.holder >= 0:
		_note("Этот персонаж недоступен для вселения")
		return
	if world.network_role == 0:
		authorize("enter", npc.id, 0, player.global_position, player.camera.global_position, player.aim_dir())
	else:
		requested.emit("enter", npc.id, player.aim_dir())


func release() -> void:
	var player := world.player
	if world.network_role == 0:
		authorize("leave", _held[local_side], 0, player.global_position, player.camera.global_position, player.aim_dir())
	else:
		requested.emit("leave", _held[local_side], player.aim_dir())


func toggle_seat() -> void:
	var player := world.player
	var id: int = _held[local_side]
	if world.network_role == 0:
		authorize("sit", id, 0, player.global_position, player.camera.global_position, player.aim_dir())
	else:
		requested.emit("sit", id, player.aim_dir())


func authorize(action: String, id: int, side: int, feet: Vector3, eye: Vector3, direction: Vector3) -> void:
	var npc := actor(id)
	if npc == null or npc.removed or not feet.is_finite() or not direction.is_finite():
		return
	if action == "sit":
		if npc.holder == side:
			_set_seat(npc, side, feet, direction)
		return
	var valid_position := Vector3.INF
	if action == "enter":
		if npc.holder >= 0 or npc.offended or _held[side] >= 0 or not eye.is_finite():
			return
		var hit := trace(eye, eye + direction.normalized() * RANGE, Layers.SOLID | Layers.CLOTH, [world.player.get_rid()])
		if hit.get("collider") != npc:
			return
		valid_position = _safe_near(npc.access_point(), npc.rotation.y)
	elif action == "leave" and npc.holder == side:
		valid_position = _safe_near(feet, npc.rotation.y, false)
	else:
		return
	if valid_position.is_finite():
		var event := {"action": action, "id": id, "side": side, "at": _pack(valid_position), "yaw": npc.rotation.y}
		if action == "enter":
			event["seated"] = npc.disguise_pose()
		_publish(event)
	elif side == local_side:
		_note("Освободи место рядом с персонажем")


func _set_seat(npc: SchoolNpc, side: int, feet: Vector3, direction: Vector3) -> void:
	var facing := atan2(-direction.x, -direction.z)
	var event := {"action": "sit", "id": npc.id, "side": side, "at": _pack(feet), "yaw": facing, "seated": []}
	if npc.seating_camera().is_finite():
		_publish(event)
		return
	var best := 1.06 * 1.06
	var seat := {}
	for station: Dictionary in _seats:
		var at: Vector3 = station.at
		var distance := feet.distance_squared_to(at)
		if distance >= best:
			continue
		if actors.any(func(other: SchoolNpc):
			return other != npc and not other.removed and other._seat > 0.0 and other.global_position.distance_squared_to(at) < 0.16):
			continue
		var top: Vector3 = at + Vector3.UP * float(station.seat)
		var support := world.raycast(top + Vector3.UP * 0.13, top - Vector3.UP * 0.12, Layers.STATIC)
		if support.is_empty() or support.normal.y < 0.6:
			continue
		if not world.raycast(feet + Vector3.UP * 0.70, station.access + Vector3.UP * 0.70).is_empty():
			continue
		seat = station
		best = distance
	if not seat.is_empty():
		var access := _safe_near(seat.access, seat.yaw)
		if access.is_finite() and access.distance_squared_to(seat.access) < 0.22:
			var at: Vector3 = seat.at
			event["at"] = _pack(access)
			event["yaw"] = seat.yaw
			event["seated"] = [at.x, at.y, at.z, seat.seat, "seat_idle"]
			_publish(event)
			return
	var ground := world.raycast(feet + Vector3.UP * 0.10, feet - Vector3.UP * 0.16, Layers.STATIC)
	var ahead := feet + Vector3.UP * 0.32
	var front := Vector3.FORWARD.rotated(Vector3.UP, facing) * 0.55
	if ground.is_empty() or ground.normal.y < 0.6 or not world.raycast(ahead, ahead + front).is_empty():
		if side == local_side:
			_note("Здесь мало места, чтобы сесть")
		return
	event["seated"] = [feet.x, feet.y, feet.z, 0.17, "seat_idle"]
	_publish(event)


func weapon_blast(at: Vector3, radius: float, source: Player) -> void:
	for npc in actors:
		if not npc.removed and HideCombat.blast_reaches(world, at, npc.global_position, radius):
			weapon_hit(npc, source)


func shotgun_hit(npc: SchoolNpc, source: Player) -> void:
	weapon_hit(npc, source)


func weapon_hit(npc: SchoolNpc, source: Player) -> void:
	if world.network_role == 2 or npc.removed:
		return
	var shooter := local_side if source == world.player else int(source.get_meta("room_side", 1))
	var victim := npc.holder
	var room := world.get_parent().get_node_or_null("NetworkHide") as NetworkHide
	if is_instance_valid(room) and not room.can_attack(source):
		return
	if victim == shooter:
		return
	if victim < 0:
		if not npc.offended:
			_publish({"action": "offend", "id": npc.id})
		return
	var safe := _safe_near(npc.global_position, npc.rotation.y)
	if not safe.is_finite():
		safe = level.spawn if victim == 0 else level.second_spawn
	var health: float = world.player.health if world.network_role == 0 else _health[victim]
	if is_instance_valid(room):
		if not room.opponents(shooter, victim):
			return
		room.combat_damage(source, victim)
		health = room.combat_hp(victim)
	else:
		health = maxf(0.0, health - Player.MAX_HEALTH * 0.25)
	_publish({"action": "break", "id": npc.id, "side": victim, "at": _pack(safe),
		"yaw": npc.rotation.y, "health": health})
	if not is_instance_valid(room) and _health[victim] <= 0.0:
		exhausted.emit(victim)


func _publish(event: Dictionary) -> void:
	event["revision"] = _revision + 1
	apply_event(event)
	confirmed.emit(event)


func apply_event(event: Dictionary) -> void:
	var npc := actor(int(event.get("id", -1)))
	if npc == null or npc.removed:
		return
	_revision = int(event.get("revision", _revision))
	var action := str(event.get("action", ""))
	if action == "offend":
		npc.hit()
		return
	var side := int(event.get("side", -1))
	var position_data: Variant = event.get("at")
	if side < 0 or side >= _held.size() or not position_data is Array or position_data.size() != 3:
		return
	var at := Vector3(position_data[0], position_data[1], position_data[2])
	if action == "enter":
		_held[side] = npc.id
		npc.set_holder(side, side == local_side, at, event.get("seated", []), float(event.get("yaw", 0.0)))
	elif action == "sit":
		if npc.holder != side:
			return
		npc.set_held_pose(at, event.get("seated", []), float(event.get("yaw", 0.0)))
		if side == local_side:
			world.player.global_position = at
			world.player.velocity = Vector3.ZERO
			world.player.reset_physics_interpolation()
		return
	elif action in ["leave", "break"]:
		_held[side] = -1
		npc.set_holder(-1, false)
		if action == "break":
			world.fx.dust(npc.global_position + Vector3.UP * 0.72, Color("#9bbfbc"), 0.66)
			npc.remove()
			_grace[side] = 2.0
			_health[side] = clampf(float(event.get("health", 0)), 0, Player.MAX_HEALTH)
	else:
		return
	if side == local_side:
		_set_local_player(npc if action == "enter" else null, at, float(event.get("yaw", 0.0)))
		if action == "break":
			world.player.possession_damage(_health[side])
			_note("Маскировка раскрыта · −20 здоровья" if WebSession.connected else "Маскировка раскрыта · −25% здоровья")
		elif action == "enter":
			_note("%s · %s — выйти" % [ROLES[npc.role], GameControls.key_name("grab")])


func snapshot() -> String:
	var packet := PackedByteArray()
	packet.resize(4 + actors.size() * SchoolNpc.POSE_BYTES)
	packet.encode_u32(0, _revision)
	for npc in actors:
		npc.write_pose(packet, 4 + npc.id * SchoolNpc.POSE_BYTES)
	return Marshalls.raw_to_base64(packet)


func read_snapshot(encoded: String) -> void:
	var packet := Marshalls.base64_to_raw(encoded)
	if packet.size() != 4 + actors.size() * SchoolNpc.POSE_BYTES or packet.decode_u32(0) != _revision:
		return
	for npc in actors:
		if not npc.removed and npc.holder != local_side:
			npc.receive_pose(packet, 4 + npc.id * SchoolNpc.POSE_BYTES)


func _set_local_player(npc: SchoolNpc, at: Vector3, yaw := 0.0) -> void:
	var player := world.player
	player.possessed_npc = npc
	player.tools.visible = npc == null
	player.tools._fire_blocked = true
	player.tools.cancel_placement()
	if at.is_finite():
		player.global_position = at
		player.look_at_dir(yaw, 0.0)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
	player.tools.refresh_slots()


func _safe_near(center: Vector3, yaw: float, use_center := true) -> Vector3:
	var offsets := [Vector3.ZERO] if use_center else []
	offsets.append_array([Vector3(0.67, 0, 0), Vector3(-0.67, 0, 0), Vector3(0, 0, 0.78), Vector3(0, 0, -0.78),
		Vector3(1.1, 0, 0.25), Vector3(-1.1, 0, 0.25)])
	var ex: Array[RID] = [world.player.get_rid()]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _exit_shape
	query.collision_mask = Layers.SOLID
	query.exclude = ex
	var space := get_world_3d().direct_space_state
	for offset: Vector3 in offsets:
		var point := center + offset.rotated(Vector3.UP, yaw)
		var floor := world.raycast(point + Vector3.UP * 0.27, point - Vector3.UP * 0.48, Layers.STATIC, ex)
		if floor.is_empty() or floor.normal.y < 0.65:
			continue
		var feet: Vector3 = floor.position + Vector3.UP * 0.04
		query.transform.origin = feet + Vector3.UP * 0.90
		if space.intersect_shape(query, 1).is_empty():
			return feet
	return Vector3.INF


func _note(message: String) -> void:
	get_tree().call_group("hud", "message", message, 2.4)


func _pack(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
