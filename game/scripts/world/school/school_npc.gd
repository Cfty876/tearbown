class_name SchoolNpc
extends Area3D

const POSSESSED_SPEED := 2.5
const HEIGHT_ADULT := 1.89
const HEIGHT_CHILD := 1.48
const POSE_BYTES := 12
const ACTIONS := ["", "cook", "wipe", "eat", "monitor", "patrol", "watch", "sweep",
	"rest", "board", "teach", "walk", "run", "study", "break", "seat_idle", "inspect"]

var id: int
var role: String
var variant: int
var holder := -1
var offended := false
var removed := false
var routes: SchoolNpcRoutes
var routines: Array = []
var teacher: SchoolNpc
var order_offset := 0.0
var avatar: SchoolNpcAvatar
var _shape: CollisionShape3D
var _phase := -1
var _index := 0
var _station := {}
var _path := PackedVector3Array()
var _path_index := 0
var _leaving_seat := false
var _probe_timer := 0.0
var _arrived := false
var _retry := 0.0
var _look_timer := 0.0
var _glance := 0.0
var _flinch := 0.0
var _animation := ""
var _seat := 0.0
var _speed := 0.0
var _height := 0.0
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _proxy_ready := false
var _blocked_paths := 0
var _rng := RandomNumberGenerator.new()
var _control_anchor := Vector3.INF
var _control_previous := Vector3.INF
var _held_seat := 0.0
var _held_pose := {}
var _stand_source := Vector3.INF
var _durations := Vector3(30, 30, 30)
var _tempo := 1.0
var _patience := 1.0
var _interest := 0.0
var _curiosity_hold := 0.0
var _floor_probe_left := 0.0
var _fall_speed := 0.0
var _displaced := false


func _ready() -> void:
	_rng.seed = 12007 + id * 157
	_durations = Vector3(_rng.randf_range(26.0, 34.0), _rng.randf_range(28.0, 34.0), _rng.randf_range(25.0, 34.0))
	_tempo = _rng.randf_range(0.84, 1.17)
	_patience = _rng.randf_range(0.65, 2.2)
	match role:
		"guard": _interest = 0.61 if variant > 1 else 0.0
		"mechanic": _interest = _rng.randf_range(0.18, 0.31)
		"teacher": _interest = _rng.randf_range(0.09, 0.26)
		"student":
			var quiet := variant % 5 in [1, 4]
			_interest = _rng.randf_range(0.07, 0.26) if quiet else _rng.randf_range(0.64, 0.98)
			_tempo *= 0.82 if quiet else 1.08
			_patience *= 1.45 if quiet else 0.76
	collision_layer = Layers.NPC
	collision_mask = 0
	monitoring = false
	monitorable = false
	_shape = CollisionShape3D.new()
	_shape.shape = CapsuleShape3D.new()
	add_child(_shape)
	_set_height(HEIGHT_CHILD if role == "student" else HEIGHT_ADULT)
	avatar = SchoolNpcAvatar.new()
	add_child(avatar)
	avatar.build(role, variant)
	reset(0.0, true)
	_look_timer = fmod(id * 0.17, 0.8)


func access_point() -> Vector3:
	return _station.access if _arrived and _seat > 0.0 else global_position


func reset(time: float, initial := false) -> void:
	if removed:
		return
	_arrived = true
	_phase = _phase_at(time)
	var spots: Array = routines[posmod(_phase, 3)]
	_index = _first_stop(spots.size())
	_station = spots[_index]
	global_position = _station.at
	rotation.y = _station.yaw
	_path = PackedVector3Array()
	_speed = 0.0
	_animation = _station.action
	_seat = _station.seat
	_glance = 0.0
	_curiosity_hold = 0.0
	_stand_source = Vector3.INF
	_retry = _patience
	_fall_speed = 0.0
	_floor_probe_left = fmod(id * 0.037, 0.15)
	_displaced = false
	_blocked_paths = 0
	_proxy_ready = false
	if initial:
		avatar.animate(_animation, 0.0, _seat, 0.0, 0.0, 1.0)
	_update_shape()


func think(delta: float, time: float, world: VoxelWorld, eyes: Array[Vector3]) -> void:
	if removed or holder >= 0:
		return
	if _fall_or_recover(delta, world):
		return
	var phase := _phase_at(time)
	var spots: Array = routines[posmod(phase, 3)]
	_retry = maxf(0.0, _retry - delta)
	if phase != _phase:
		_phase = phase
		_index = _first_stop(spots.size())
		_go(spots[_index])
	elif _arrived and spots.size() > 1 and _retry <= 0.0:
		_index = (_index + 1) % spots.size()
		_go(spots[_index])
	elif not _arrived and _path.is_empty() and _retry <= 0.0:
		_go(spots[_index])

	_speed = 0.0
	if not _arrived:
		_walk(delta, world)
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = _rng.randf_range(0.48, 0.93)
		var direction := _look(world, eyes)
		if absf(direction) > 0.001:
			_glance = direction
			_curiosity_hold = lerpf(0.28, 1.5, _interest)
	_curiosity_hold = maxf(0.0, _curiosity_hold - delta)
	if _curiosity_hold <= 0.0:
		_glance = 0.0
	_update_shape()


func _fall_or_recover(delta: float, world: VoxelWorld) -> bool:
	_floor_probe_left -= delta
	if _fall_speed <= 0.0 and _floor_probe_left > 0.0:
		if _displaced:
			_walk_displaced(delta, world)
		return _displaced
	_floor_probe_left = 0.15
	var feet := global_position
	if _fall_speed == 0.0 and _arrived and _seat > 0.0:
		feet = access_point()
	var start := feet + Vector3.UP * (0.18 if _fall_speed > 0.0 else 0.36)
	var drop := maxf(0.31, _fall_speed * delta + 0.12)
	var support := world.raycast(start, feet - Vector3.UP * drop, Layers.STATIC)
	if not support.is_empty() and support.normal.y > 0.55:
		if _fall_speed > 0.0:
			if support.position.y >= feet.y - _fall_speed * delta - 0.055:
				global_position.y = support.position.y + 0.025
				_fall_speed = 0.0
				_displaced = true
				return true
		else:
			if not _displaced:
				return false
			var targets: Array = routines[posmod(_phase, 3)]
			for station: Dictionary in targets:
				if _supported_station(world, station):
					_displaced = false
					_go(station)
					return false
			_walk_displaced(delta, world)
			return true
	if _fall_speed <= 0.0:
		global_position = feet
		_path.clear()
		_seat = 0.0
		_arrived = false
		_stand_source = Vector3.INF
		_animation = ""
		_speed = 0.0
	_fall_speed = minf(_fall_speed + 21.0 * delta, 19.0)
	global_position.y -= _fall_speed * delta
	if global_position.y < -30.0:
		global_position = world.player.spawn_point
		_fall_speed = 0.0
		_displaced = true
	_update_shape()
	return true


func _supported_station(world: VoxelWorld, station: Dictionary) -> bool:
	var at: Vector3 = station.access
	if absf(at.y - global_position.y) > 0.8:
		return false
	var hit := world.raycast(at + Vector3.UP * 0.27, at - Vector3.UP * 0.26, Layers.STATIC)
	return not hit.is_empty() and hit.normal.y > 0.55


func _walk_displaced(delta: float, world: VoxelWorld) -> void:
	var ahead := -global_basis.z
	var step := global_position + ahead * delta * 1.25
	var look_ahead := global_position + ahead * 0.45
	if _can_step(world, look_ahead):
		global_position = step
		_speed = 1.25
	else:
		rotation.y += 1.45
		_speed = 0.0


func _phase_at(time: float) -> int:
	if is_instance_valid(teacher):
		return teacher._phase_at(time + order_offset - teacher.order_offset)
	var cycle := _durations.x + _durations.y + _durations.z
	var elapsed := time + order_offset
	var local := fposmod(elapsed, cycle)
	var phase := 0 if local < _durations.x else (1 if local < _durations.x + _durations.y else 2)
	return floori(elapsed / cycle) * 3 + phase


func _first_stop(count: int) -> int:
	return posmod(id + _phase, count) if role == "student" else 0


func _go(station: Dictionary) -> void:
	var from := _stand_source if _stand_source.is_finite() else access_point()
	_leaving_seat = (_arrived and _seat > 0.0) or _stand_source.is_finite()
	_stand_source = Vector3.INF
	_station = station
	_arrived = false
	_seat = 0.0
	_animation = ""
	_path_index = 0
	_probe_timer = 0.0
	if routes:
		_path = routes.path(from, station.access)
	else:
		_path = _guard_path(from, station.access)
	if routes and _path.is_empty():
		_retry = 1.3
	else:
		if _leaving_seat:
			_path.insert(0, from)
		# Chair coordinates are an animation endpoint, entered from a clear aisle.
		_path.append(station.access)
		if station.seat > 0.0:
			_path.append(station.at)


func _guard_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	if from.y < 0.0 or to.y < 0.0:
		return points
	if from.x < -2.0 and from.z > 1.0:
		points.append(Vector3(0, 2.22, 4.2))
	elif from.z < -6.5 and to.z > -6.5:
		points.append(Vector3(0, 2.05, -7.2))
	if to.z < -6.5 and from.z > -6.5:
		points.append(Vector3(0, 2.22, -5.3))
		points.append(Vector3(0, 2.05, -7.2))
	elif to.z > -6.5 and from.z < -6.5:
		points.append(Vector3(0, 2.22, -5.3))
	if to.x < -2.0 and to.z > 1.0:
		points.append(Vector3(0, 2.22, 4.2))
	return points


func _walk(delta: float, world: VoxelWorld) -> void:
	if _path_index >= _path.size():
		return
	var next := _path[_path_index]
	var shift := next - global_position
	var is_seat: bool = _station.seat > 0.0 and _path_index == _path.size() - 1
	if is_seat and _station.action == "study" and is_instance_valid(teacher) and not teacher.removed and teacher._animation != "teach":
		return
	if shift.length_squared() < 0.0064:
		_path_index += 1
		_probe_timer = 0.0
		if _path_index == _path.size():
			global_position = _station.at
			rotation.y = _station.yaw
			_arrived = true
			_animation = _station.action
			_seat = _station.seat
			_retry = _patience
			_blocked_paths = 0
		return
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = 0.14
		var step := global_position.move_toward(next, 0.46)
		if not is_seat and not (_leaving_seat and _path_index == 0) and not _can_step(world, step):
			_path.clear()
			_blocked_paths += 1
			_retry = minf(4.0, 0.8 + _blocked_paths * 0.55)
			return
	var goal_speed := (3.1 if role == "student" and posmod(_phase, 3) == 0 else (1.85 if role == "student" else 1.45)) * _tempo
	global_position = global_position.move_toward(next, delta * goal_speed)
	var flat := Vector2(shift.x, shift.z)
	if flat.length_squared() > 0.005:
		rotation.y = lerp_angle(rotation.y, atan2(-shift.x, -shift.z), 1.0 - exp(-9.0 * delta))
	_speed = goal_speed


func _can_step(world: VoxelWorld, next: Vector3) -> bool:
	# The generated route covers static furniture. Live probes also account for
	# destroyed floors, moved props and player-built barricades.
	var ground := world.raycast(next + Vector3.UP * 0.28, next - Vector3.UP * 0.28, Layers.STATIC)
	if ground.is_empty() or ground.normal.y < 0.58:
		return false
	for height: float in [0.64, 1.10]:
		var lift := Vector3.UP * height
		if not world.raycast(global_position + lift, next + lift).is_empty():
			return false
	return true


func _look(world: VoxelWorld, eyes: Array[Vector3]) -> float:
	if _interest == 0.0 or offended or _rng.randf() > _interest:
		return 0.0
	var at := global_position + Vector3.UP * (_height - 0.16)
	for eye in eyes:
		var to := eye - at
		if to.length_squared() > 6.5 * 6.5 or to.length_squared() < 0.20:
			continue
		var turn := wrapf(atan2(-to.x, -to.z) - rotation.y, -PI, PI)
		if absf(turn) < 1.35 and world.raycast(at, eye).is_empty():
			return clampf(turn, -1.08, 1.08)
	return 0.0


func control(at: Vector3, yaw: float, pitch: float, delta: float) -> void:
	if _held_seat > 0.0 and at.distance_squared_to(_control_anchor) > 0.21 * 0.21:
		_held_seat = 0.0
	_speed = minf(_control_previous.distance_to(at) / maxf(delta, 0.001), 4.0)
	_control_previous = at
	global_position = _held_pose.at if _held_seat > 0.0 else at
	rotation.y = _held_pose.yaw if _held_seat > 0.0 else yaw
	_glance = clampf(wrapf(yaw - rotation.y, -PI, PI), -1.08, 1.08)
	var resting: bool = _speed < 0.36 and at.distance_squared_to(_station.access) < 0.38
	_animation = _held_pose.action if _held_seat > 0.0 else (_station.action if resting and _station.seat == 0.0 else "")
	_seat = _held_seat
	avatar.head.rotation.x = clampf(pitch, -0.65, 0.65)
	_update_shape()


func seating_camera() -> Vector3:
	return global_position + Vector3.UP * (_height - 0.22) if _held_seat > 0.0 else Vector3.INF


func set_held_pose(at: Vector3, pose: Array, yaw: float) -> void:
	_held_seat = float(pose[3]) if pose.size() == 5 else 0.0
	_control_anchor = at
	_control_previous = at
	if _held_seat > 0.0:
		var pose_at := Vector3(pose[0], pose[1], pose[2])
		_held_pose = SchoolNpcRoutes.station(pose_at, yaw, str(pose[4]), _held_seat, at)
		global_position = pose_at
		_animation = _held_pose.action
	else:
		_held_pose.clear()
		global_position = at
		_animation = ""
	_seat = _held_seat
	rotation.y = yaw
	_update_shape()


func disguise_pose() -> Array:
	if _arrived and _seat > 0.0:
		return [global_position.x, global_position.y, global_position.z, _seat, _animation]
	return []


func present(delta: float, eye: Vector3, frozen: bool) -> void:
	if removed or frozen or global_position.distance_squared_to(eye) > 46.0 * 46.0:
		return
	_flinch = move_toward(_flinch, 0.0, delta * 3.0)
	avatar.animate(_animation, _speed, _seat, _glance, _flinch, delta)


func set_holder(side: int, local: bool, at := Vector3.INF, seated_pose: Array = [], yaw := 0.0) -> void:
	holder = side
	avatar.head.layers = VoxelAvatar.HEAD_LAYER if local else 1
	avatar.position.z = 0.17 if local else 0.0
	if side >= 0:
		set_held_pose(at, seated_pose, yaw)
	else:
		_path.clear()
		_arrived = _held_seat > 0.0 and global_position.distance_squared_to(_station.at) < 0.04 and _animation == _station.action
		_stand_source = _control_anchor if _held_seat > 0.0 and not _arrived else Vector3.INF
		_retry = 0.0
		_proxy_ready = false
		_held_seat = 0.0
		_held_pose.clear()


func hit() -> void:
	offended = true
	_flinch = 1.0


func remove() -> void:
	removed = true
	collision_layer = 0
	hide()


func write_pose(bytes: PackedByteArray, offset: int) -> void:
	if removed:
		bytes.encode_u8(offset + 11, 255)
		return
	bytes.encode_s16(offset, roundi(position.x * 100.0))
	bytes.encode_s16(offset + 2, roundi(position.y * 100.0))
	bytes.encode_s16(offset + 4, roundi(position.z * 100.0))
	bytes.encode_s16(offset + 6, roundi(wrapf(rotation.y, -PI, PI) * 1000.0))
	bytes.encode_u8(offset + 8, roundi(_speed * 20.0))
	bytes.encode_u8(offset + 9, roundi(_seat * 100.0))
	bytes.encode_s8(offset + 10, roundi(_glance * 100.0))
	bytes.encode_u8(offset + 11, maxi(ACTIONS.find(_animation), 0))


func receive_pose(bytes: PackedByteArray, offset: int) -> void:
	var action := bytes.decode_u8(offset + 11)
	if action >= ACTIONS.size():
		return
	_target = Vector3(bytes.decode_s16(offset), bytes.decode_s16(offset + 2), bytes.decode_s16(offset + 4)) * 0.01
	_target_yaw = bytes.decode_s16(offset + 6) * 0.001
	_speed = bytes.decode_u8(offset + 8) * 0.05
	_seat = bytes.decode_u8(offset + 9) * 0.01
	_glance = bytes.decode_s8(offset + 10) * 0.01
	_animation = ACTIONS[action]
	if not _proxy_ready or global_position.distance_squared_to(_target) > 25.0:
		global_position = _target
		rotation.y = _target_yaw
		_proxy_ready = true
	_update_shape()


func interpolate_pose(delta: float) -> void:
	if not _proxy_ready:
		return
	var blend := 1.0 - exp(-16.0 * delta)
	global_position = global_position.lerp(_target, blend)
	rotation.y = lerp_angle(rotation.y, _target_yaw, blend)


func _update_shape() -> void:
	var height := HEIGHT_CHILD if role == "student" else HEIGHT_ADULT
	if _seat > 0.0:
		var model_scale := 0.79 if role == "student" else 1.0
		height -= maxf(0.0, (SchoolNpcAvatar.HIP - 0.033) * model_scale - _seat)
	_set_height(height)


func _set_height(height: float) -> void:
	if is_equal_approx(height, _height):
		return
	_height = height
	var capsule := _shape.shape as CapsuleShape3D
	capsule.radius = 0.23 if role == "student" else 0.27
	capsule.height = height
	_shape.position.y = height * 0.5
