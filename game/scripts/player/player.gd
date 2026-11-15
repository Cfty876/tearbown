class_name Player
extends CharacterBody3D
## First-person controller: walk/sprint/crouch/jump, voxel step climbing,
## pushing bodies, and grabbing/carrying/throwing physics objects.

const WALK := 4.6
const SPRINT := 7.8
const CROUCH_SPEED := 2.3
const JUMP := 5.2
const GRAVITY := 13.0
const STEP_HEIGHT := 0.36
const STAND_EYE := 1.62
const CROUCH_EYE := 0.95
const GRAB_RANGE := 3.2
const VEHICLE_RANGE := 3.5
const DOOR_RANGE := 2.6
const GRAB_FORCE := 2600.0     # N; ~120 kg can be carried, heavier things only dragged
const THROW_SPEED := 13.0
signal sound_emitted(at: Vector3, range_metres: float, kind: String)
## Half size of the walkable map (set by main for the loaded level).
var border := 39.4

var mouse_sensitivity := 0.0022
var touch_mode := false
var movement_enabled := true
var interaction_enabled := true
var navigation_menu_open := false
var transit_active := false
var hide_spot := -1
var hides: DistrictHides
var possessed_npc: SchoolNpc
var bot_hunt: SchoolHideMatch
var show_body := true
var avatar: VoxelAvatar
var head: Node3D
var camera: Camera3D
var tools: PlayerTools
var crouching: bool:
	get:
		return _crouch
var grabbed: VoxelObject
var spawn_point := Vector3.ZERO

const MAX_HEALTH := 100.0
var health := MAX_HEALTH
var god_mode := false
var dead := false
## 0..1, drives the red screen flash in the HUD.
var hurt := 0.0
var _since_hurt := 10.0
var _step_acc := 0.0
var footstep_serial := 0
var footstep_material := VoxMat.CONCRETE
var footstep_running := false

var _col: CollisionShape3D
var _capsule: CapsuleShape3D
var _crouch := false
var _eye := STAND_EYE
var _shake := 0.0
var _bob_t := 0.0
var _grab_local := Vector3.ZERO
var _grab_dist := 2.0
var _yaw := 0.0
var _pitch := 0.0
var vehicle: VoxelVehicle
var _car_yaw := 0.0
var _car_pitch := 0.22
var _driving := false
var _exit_requested := false
var _last_vehicle_exit := Vector3.ZERO
var _exit_fall_protection := 0.0
var _recent_vehicle_body: VoxelObject


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
	# A voxel chassis can jump when Jolt resolves its suspension contacts.
	platform_floor_layers = Layers.STATIC
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(52.0)
	safe_margin = 0.02
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	_col = CollisionShape3D.new()
	_col.shape = _capsule
	_col.position.y = 0.9
	add_child(_col)
	head = Node3D.new()
	head.position.y = STAND_EYE
	add_child(head)
	camera = Camera3D.new()
	camera.fov = GameState.fov
	camera.cull_mask &= ~VoxelAvatar.HEAD_LAYER
	camera.near = 0.03
	camera.far = 600.0
	head.add_child(camera)
	camera.make_current()
	tools = PlayerTools.new()
	tools.player = self
	camera.add_child(tools)
	if show_body:
		avatar = VoxelAvatar.new()
		avatar.first_person = true
		add_child(avatar)
	spawn_point = global_position
	_yaw = rotation.y


func _unhandled_input(e: InputEvent) -> void:
	if navigation_menu_open:
		return
	if e is InputEventMouseMotion and not touch_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(e.relative)
	elif e is InputEventMouseButton and e.pressed and not touch_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("grab"):
		interact()
	elif e.is_action_pressed("crouch") and is_instance_valid(possessed_npc):
		toggle_disguise_seat()
		get_viewport().set_input_as_handled()


func apply_look(relative: Vector2) -> void:
	if clock_locked():
		return
	relative *= GameState.mouse_speed
	if GameState.invert_y:
		relative.y = -relative.y
	if vehicle:
		_car_yaw -= relative.x * mouse_sensitivity
		_car_pitch = clampf(_car_pitch + relative.y * mouse_sensitivity, -0.2, 1.2)
		return
	look_at_dir(_yaw - relative.x * mouse_sensitivity,
		clampf(_pitch - relative.y * mouse_sensitivity, -1.53, 1.53))


func interact() -> void:
	if dead or not movement_enabled or navigation_menu_open or transit_active or clock_locked():
		return
	if is_instance_valid(possessed_npc):
		VoxelWorld.instance.population.release()
	elif _driving:
		_exit_requested = true
	elif grabbed:
		release_grab(false)
	elif is_instance_valid(VoxelWorld.instance.boombox) and VoxelWorld.instance.boombox.pick_up():
		return
	elif (is_instance_valid(hides) and hides.interact()
			or is_instance_valid(VoxelWorld.instance.secrets) and VoxelWorld.instance.secrets.interact()
			or is_instance_valid(VoxelWorld.instance.gadgets) and VoxelWorld.instance.gadgets.interact()):
		return
	else:
		var hit := aim_ray(VEHICLE_RANGE)
		match object_action(hit):
			"door":
				(hit.collider.get_node("DistrictDoor") as DistrictDoor).interact(global_position)
				sound_emitted.emit(hit.position, 11.0, "door")
			"vehicle":
				enter_vehicle(hit.collider.get_node("Vehicle"))
			"vehicle_locked":
				get_tree().call_group("hud", "message", "Ключ от ПАЗа в кабинете директора. Опусти подъёмник перед выездом", 2.8)
			"grab":
				_grab_hit(hit)


func toggle_disguise_seat() -> void:
	if not dead and movement_enabled and not navigation_menu_open and not clock_locked() and is_instance_valid(possessed_npc):
		VoxelWorld.instance.population.toggle_seat()


func object_action(hit: Dictionary) -> String:
	if hit.is_empty() or not hit.collider is VoxelObject:
		return ""
	var object: VoxelObject = hit.collider
	if not is_instance_valid(object) or object.is_queued_for_deletion():
		return ""
	var distance := camera.global_position.distance_squared_to(hit.position)
	var door := object.get_node_or_null("DistrictDoor") as DistrictDoor
	if door:
		return "door" if distance <= DOOR_RANGE * DOOR_RANGE else ""
	if not interaction_enabled:
		return ""
	var ride := object.get_node_or_null("Vehicle") as VoxelVehicle
	if ride:
		if is_instance_valid(ride.driver) or distance > VEHICLE_RANGE * VEHICLE_RANGE:
			return ""
		var secrets := VoxelWorld.instance.secrets
		if object.label == "Школьный автобус ПАЗ" and secrets is SchoolSecrets and not secrets.traps.can_board():
			return "vehicle_locked"
		return "vehicle"
	if distance <= GRAB_RANGE * GRAB_RANGE and not object.static_mode and not object.freeze and not object.held:
		return "grab"
	return ""


func look_at_dir(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	rotation.y = yaw
	head.rotation.x = pitch


func aim_ray(length: float, mask := Layers.SOLID) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var ex: Array[RID] = [get_rid()]
	return VoxelWorld.instance.raycast(from, to, mask, ex)


func aim_dir() -> Vector3:
	return -camera.global_basis.z


func clock_locked() -> bool:
	var world := VoxelWorld.instance
	return is_instance_valid(world) and world.player == self and is_instance_valid(world.gadgets) and world.gadgets.local_frozen()


func _physics_process(delta: float) -> void:
	if VoxelWorld.instance and VoxelWorld.instance.player == self and WebSession.connected and int(WebSession.rules.zone) > 0 \
			and not RoomRules.contains(global_position, border + 0.3):
		if vehicle:
			exit_vehicle(true)
		if hide_spot >= 0 and is_instance_valid(hides):
			hides.reset_player()
		transit_active = false
		if is_instance_valid(VoxelWorld.instance.secrets):
			VoxelWorld.instance.secrets.cancel_player_travel()
		global_position = spawn_point
		velocity = Vector3.ZERO
		reset_physics_interpolation()
	if clock_locked():
		return
	if dead or transit_active:
		velocity = Vector3.ZERO
		return
	_exit_fall_protection = maxf(0.0, _exit_fall_protection - delta)
	if _exit_fall_protection <= 0.0 and is_instance_valid(_recent_vehicle_body):
		var body := _recent_vehicle_body
		var size := Vector3(body.volume.get_size()) * VoxelObject.VS
		var local := body.to_local(global_position + Vector3.UP * 0.8)
		if not AABB(Vector3.ONE * -0.65, size + Vector3.ONE * 1.3).has_point(local):
			_clear_vehicle_exception()
	if hide_spot >= 0:
		velocity = Vector3.ZERO
		return
	if _driving:
		if not is_instance_valid(vehicle) or not is_instance_valid(vehicle.body):
			exit_vehicle(true)
			return
		else:
			if _exit_requested:
				_exit_requested = false
				if exit_vehicle():
					return
			global_position = vehicle.seat_position()
			velocity = Vector3.ZERO
			return
	var can_move := movement_enabled and not navigation_menu_open
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_move else Vector2.ZERO
	var disguised := is_instance_valid(possessed_npc)
	var want_crouch := not disguised and Input.is_action_pressed("crouch")
	if want_crouch != _crouch:
		_set_crouch(want_crouch)
	var speed := CROUCH_SPEED if _crouch else (SPRINT if is_sprinting() else WALK)
	if disguised:
		speed = SchoolNpc.POSSESSED_SPEED
	var secrets := VoxelWorld.instance.secrets
	var wet: bool = secrets is SchoolSecrets and secrets.wet_tile() and not _crouch
	if not _crouch and secrets is SchoolSecrets:
		speed *= secrets.move_multiplier()
	if not _crouch and is_instance_valid(VoxelWorld.instance.gadgets):
		speed *= VoxelWorld.instance.gadgets.speed_multiplier()
	if wet:
		speed *= 1.09
	var wish := (global_basis * Vector3(input.x, 0, input.y))
	wish.y = 0
	wish = wish.normalized() * speed

	if is_on_floor():
		var k := 1.0 - exp(-(3.0 if wet else 14.0) * delta)
		velocity.x = lerpf(velocity.x, wish.x, k)
		velocity.z = lerpf(velocity.z, wish.z, k)
		if can_move and not disguised and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	else:
		var k := 1.0 - exp(-2.5 * delta)
		velocity.x = lerpf(velocity.x, wish.x, k)
		velocity.z = lerpf(velocity.z, wish.z, k)
		velocity.y -= GRAVITY * delta
	if can_move and tools.thrusting and global_position.y < 56.0:
		var jet := -aim_dir() * 23.0 + Vector3.UP * 3.0
		velocity += jet * delta
		velocity.y = minf(velocity.y, 10.0)

	_try_step_up(delta)
	var fall_speed := -velocity.y
	var was_floor := is_on_floor()
	move_and_slide()
	if secrets is SchoolSecrets and wish.length_squared() > 1.0:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == secrets.football:
				secrets.touch_football()
				break
	if is_on_floor() and not was_floor and fall_speed > 11.0:
		if _exit_fall_protection <= 0.0 and not _landed_on_vehicle():
			damage((fall_speed - 11.0) * 9.0)
		VoxelWorld.instance.sfx.play("thud", global_position, 0.0, 0.7)
		sound_emitted.emit(global_position, 19.0, "landing")
	_footsteps(delta)
	if not WebSession.connected or (WebSession.is_host and GameState.level == GameState.LEVEL_HIDE):
		_push_bodies(delta)
	_update_grab(delta)

	# Map border (half size of the loaded voxel terrain).
	global_position.x = clampf(global_position.x, -border, border)
	global_position.z = clampf(global_position.z, -border, border)
	if global_position.y < -30.0:
		global_position = spawn_point
		velocity = Vector3.ZERO


func _landed_on_vehicle(source: VoxelObject = null) -> bool:
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		var object := contact.get_collider() as VoxelObject
		if object and (source == null or source == object) and object.has_node("Vehicle") and contact.get_normal().y >= cos(floor_max_angle):
			return true
	return false


## Climbs single voxel ledges (up to STEP_HEIGHT) like stairs.
func _try_step_up(delta: float) -> void:
	if not is_on_floor() and velocity.y > 0.5:
		return
	var horiz := Vector3(velocity.x, 0, velocity.z)
	if horiz.length_squared() < 0.04:
		return
	var motion := horiz * delta + horiz.normalized() * 0.05
	var xf := global_transform
	if not test_move(xf, motion):
		return
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(xf, up):
		return
	var raised := xf.translated(up)
	if test_move(raised, motion):
		return
	# Find the actual ledge height by dropping back down from the raised position.
	var moved := raised.translated(motion)
	var col := KinematicCollision3D.new()
	if test_move(moved, -up, col):
		var drop := col.get_travel().length()
		var rise := STEP_HEIGHT - drop
		if rise > 0.02:
			global_position.y += rise + 0.01
			velocity.y = maxf(velocity.y, 0.0)


func _push_bodies(_delta: float) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body == null or body.freeze or body == grabbed or body == _recent_vehicle_body:
			continue
		if body is VoxelObject and VoxMat.material_of(body.voxel_at_hit(c.get_position(), c.get_normal())) == VoxMat.GLASS:
			continue
		var push := -c.get_normal()
		push.y = 0.0 if body.has_node("Vehicle") else maxf(push.y, 0.0)
		var strength := clampf(velocity.length() * 9.0, 0.0, 60.0)
		body.apply_impulse(push * strength * minf(body.mass, 80.0) / 80.0, c.get_position() - body.global_position)


func is_sprinting() -> bool:
	if has_meta("room_running"):
		return bool(get_meta("room_running"))
	return possessed_npc == null and Input.is_action_pressed("sprint") and not _crouch and Input.is_action_pressed("move_forward")


func _set_crouch(on: bool) -> void:
	if not on:
		# Only stand up if there is headroom.
		var q := PhysicsShapeQueryParameters3D.new()
		var s := CapsuleShape3D.new()
		s.radius = 0.3
		s.height = 1.8
		q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.95, 0))
		q.collision_mask = collision_mask
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return
	_crouch = on
	_capsule.height = 1.1 if on else 1.8
	_col.position.y = _capsule.height * 0.5


func _process(delta: float) -> void:
	camera.fov = GameState.fov
	if is_instance_valid(avatar):
		avatar.visible = not dead and not is_instance_valid(possessed_npc)
		if not vehicle:
			avatar.pose(Vector2(velocity.x, velocity.z).length(), _pitch, _crouch, delta)
	hurt = maxf(hurt - delta * 1.5, 0.0)
	_since_hurt += delta
	if not god_mode and not dead and _since_hurt > 4.0 and health < MAX_HEALTH:
		health = minf(health + 14.0 * delta, MAX_HEALTH)
	if vehicle and is_instance_valid(vehicle) and is_instance_valid(vehicle.body):
		if avatar:
			var seat := vehicle.seat_basis() * Basis.from_scale(Vector3(1, 0.59, 1))
			avatar.global_transform = Transform3D(seat, vehicle.seat_position())
		camera.global_transform = vehicle.chase_camera(_car_yaw, _car_pitch)
		return
	var target_eye := CROUCH_EYE if _crouch else STAND_EYE
	if is_instance_valid(possessed_npc):
		target_eye = 1.24 if possessed_npc.role == "student" else 1.56
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-12.0 * delta))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob_t += delta * hspeed * 1.9
	var bob := sin(_bob_t) * 0.035 * clampf(hspeed / WALK, 0.0, 1.5)
	var seat_eye := possessed_npc.seating_camera() if is_instance_valid(possessed_npc) else Vector3.INF
	var head_target := to_local(seat_eye) if seat_eye.is_finite() else Vector3(0, _eye + bob, 0)
	head.position = head.position.lerp(head_target, 1.0 - exp(-12.0 * delta)) if possessed_npc else head_target
	_shake = maxf(_shake - delta * 1.8, 0.0)
	var s := _shake * _shake
	camera.h_offset = randf_range(-1, 1) * s * 0.12
	camera.v_offset = randf_range(-1, 1) * s * 0.12
	camera.rotation.z = randf_range(-1, 1) * s * 0.03


func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


func apply_blast(pos: Vector3, reach: float, power: float) -> void:
	if dead:
		return
	var c := global_position + Vector3(0, 0.9, 0)
	var d := c.distance_to(pos)
	if d >= reach:
		return
	var dir := (c - pos).normalized() + Vector3.UP * 0.4
	velocity += dir.normalized() * power * 1.6 * (1.0 - d / reach)
	var k := 1.0 - d / reach
	damage(power * 24.0 * k * k)


# ------------------------------------------------------------------ grabbing

func try_grab() -> void:
	var hit := aim_ray(GRAB_RANGE)
	if object_action(hit) == "grab":
		_grab_hit(hit)


func _grab_hit(hit: Dictionary) -> void:
	grabbed = hit.collider
	grabbed.held = true
	_grab_local = grabbed.to_local(hit.position)
	_grab_dist = clampf(camera.global_position.distance_to(hit.position), 1.3, GRAB_RANGE)
	add_collision_exception_with(grabbed)
	grabbed.sleeping = false
	VoxelWorld.instance.sfx.play("click", hit.position, -8.0)


func release_grab(throw: bool) -> void:
	if not is_instance_valid(grabbed):
		grabbed = null
		return
	grabbed.held = false
	if throw:
		var imp := aim_dir() * THROW_SPEED * minf(grabbed.mass, 45.0)
		grabbed.apply_impulse(imp, grabbed.to_global(_grab_local) - grabbed.global_position)
		VoxelWorld.instance.sfx.play("throw", grabbed.global_position, -4.0)
	var released := weakref(grabbed) as WeakRef
	grabbed = null
	# Re-enable collision only if the released object survived the delay.
	get_tree().create_timer(0.4).timeout.connect(func():
		var object := released.get_ref() as VoxelObject
		if is_instance_valid(object) and grabbed != object:
			remove_collision_exception_with(object))


func grab_scroll(delta_dist: float) -> void:
	_grab_dist = clampf(_grab_dist + delta_dist, 1.0, GRAB_RANGE + 0.6)


func _update_grab(delta: float) -> void:
	if grabbed == null:
		return
	if not is_instance_valid(grabbed) or grabbed.is_queued_for_deletion():
		grabbed = null
		return
	var target := camera.global_position + aim_dir() * _grab_dist
	var p := grabbed.to_global(_grab_local)
	if p.distance_to(target) > 2.6:
		release_grab(false)
		return
	var com := grabbed.to_global(grabbed.center_of_mass)
	var v_at := grabbed.linear_velocity + grabbed.angular_velocity.cross(p - com)
	var desired := (target - p) * 14.0
	desired = desired.limit_length(14.0)
	var dv := desired - v_at
	# Velocity servo with a force limit: light things snap, heavy ones lag and drag.
	var imp := dv * grabbed.mass + Vector3.UP * grabbed.mass * 9.8 * delta
	imp = imp.limit_length(GRAB_FORCE * delta)
	grabbed.apply_impulse(imp, p - grabbed.global_position)
	if grabbed.mass < 200.0:
		grabbed.angular_velocity *= 0.9


# ------------------------------------------------------------------ vehicles

func enter_vehicle(v: VoxelVehicle) -> void:
	if dead or _driving or not is_instance_valid(v) or not is_instance_valid(v.body) or is_instance_valid(v.driver):
		return
	var obj := v.body
	var secrets := VoxelWorld.instance.secrets
	if obj.label == "Школьный автобус ПАЗ" and secrets is SchoolSecrets and not secrets.traps.unlock_for_boarding():
		return
	_clear_vehicle_exception()
	_last_vehicle_exit = global_position
	_exit_requested = false
	vehicle = v
	_driving = true
	vehicle.driver = self
	collision_layer = 0
	collision_mask = 0
	camera.top_level = true
	_car_yaw = 0.0
	_car_pitch = 0.22
	_set_hands(false)
	if avatar:
		avatar.seated(true)
	VoxelWorld.instance.sfx.play("click", obj.global_position, -6.0)


func _set_hands(on: bool) -> void:
	if tools:
		tools.visible = on
		tools.input_enabled = on


func exit_vehicle(emergency := false) -> bool:
	var v := vehicle
	var landing := Vector3.INF
	var facing := aim_dir()
	if is_instance_valid(v) and is_instance_valid(v.body):
		facing = v.body.global_basis * v.forward_local
		landing = _vehicle_landing(v)
	if not landing.is_finite():
		if not emergency:
			if is_instance_valid(v) and v.right_vehicle():
				global_position = v.seat_position()
				camera.global_transform = v.chase_camera(_car_yaw, _car_pitch)
				camera.reset_physics_interpolation()
				reset_physics_interpolation()
				get_tree().call_group("hud", "message", "Машина на колёсах · нажми кнопку выхода ещё раз", 2.4)
				return false
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.message("Нет места для выхода. Переставь машину.", 2.0)
			return false
		landing = _clear_exit(_last_vehicle_exit + Vector3.UP * 0.5)
		if not landing.is_finite():
			landing = spawn_point
	if is_instance_valid(v):
		v.driver = null
	_clear_vehicle_exception()
	if is_instance_valid(v) and is_instance_valid(v.body):
		_recent_vehicle_body = v.body
		# Keep the old contact pair out of Jolt while the capsule moves out of the seat.
		add_collision_exception_with(_recent_vehicle_body)
		_recent_vehicle_body.add_collision_exception_with(self)
	vehicle = null
	_driving = false
	_exit_requested = false
	global_position = landing
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_exit_fall_protection = 1.35
	look_at_dir(atan2(-facing.x, -facing.z), 0.0)
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
	_set_hands(true)
	if avatar:
		avatar.transform = Transform3D.IDENTITY
		avatar.seated(false)
	return true


func _clear_vehicle_exception() -> void:
	if is_instance_valid(_recent_vehicle_body):
		remove_collision_exception_with(_recent_vehicle_body)
		_recent_vehicle_body.remove_collision_exception_with(self)
	_recent_vehicle_body = null


func _vehicle_landing(v: VoxelVehicle) -> Vector3:
	var body := v.body
	var size := Vector3(body.volume.get_size()) * VoxelObject.VS
	var center := body.to_global(Vector3(size.x * 0.5, 0.0, size.z * 0.5))
	var forward := body.global_basis * v.forward_local
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.01 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	var basis := body.global_basis
	var side_distance := (basis.transposed() * side).abs().dot(size * 0.5) + 0.64
	var end_distance := (basis.transposed() * forward).abs().dot(size * 0.5) + 0.71
	var lateral := body.linear_velocity.dot(side)
	var longitudinal := body.linear_velocity.dot(forward)
	var safe_side := -side if lateral > 0.0 else side
	var safe_end := forward if longitudinal < 0.0 else -forward
	var offsets: Array[Vector3] = [safe_side * side_distance, -safe_side * side_distance, safe_end * end_distance]
	if absf(longitudinal) < 1.5:
		offsets.append(-safe_end * end_distance)
	for offset in offsets:
		if body.linear_velocity.dot(offset.normalized()) > 3.0:
			continue
		var landing := _clear_exit(center + offset + Vector3.UP * minf(size.y, 1.6), body)
		if landing.is_finite():
			return landing
	return Vector3.INF


func _clear_exit(above: Vector3, exiting: VoxelObject = null) -> Vector3:
	if absf(above.x) > border or absf(above.z) > border:
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var floor_mask := Layers.STATIC if exiting != null else Layers.SOLID
	var search_depth := 3.2 if exiting != null else 4.5
	var ray := PhysicsRayQueryParameters3D.create(above, above - Vector3.UP * search_depth, floor_mask, [get_rid()])
	var ground := space.intersect_ray(ray)
	if ground.is_empty() or ground.normal.y < 0.62 or (exiting != null and ground.collider == exiting):
		return Vector3.INF
	var feet: Vector3 = ground.position + Vector3.UP * 0.07
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * _capsule.height * 0.5)
	q.collision_mask = Layers.SOLID
	q.exclude = [get_rid()]
	return feet if space.intersect_shape(q, 1).is_empty() else Vector3.INF


# ------------------------------------------------------------------ health

func damage_from_impact(amount: float, source: VoxelObject) -> void:
	if not is_instance_valid(source):
		return
	if source == _recent_vehicle_body and _exit_fall_protection > 0.0:
		return
	if source.has_node("Vehicle"):
		if _landed_on_vehicle(source):
			return
		var feet := source.to_local(global_position)
		var size := Vector3(source.volume.get_size()) * VoxelObject.VS
		var over_body := feet.x >= -0.15 and feet.x <= size.x + 0.15 and feet.z >= -0.15 and feet.z <= size.z + 0.15
		if over_body and feet.y >= size.y * 0.65 and source.global_basis.y.y > 0.55:
			return
	damage(amount)


func damage(amount: float) -> void:
	if god_mode or dead or amount < 0.5:
		return
	health -= amount
	_since_hurt = 0.0
	hurt = clampf(hurt + amount / 40.0, 0.0, 1.0)
	shake(clampf(amount / 60.0, 0.1, 0.6))
	VoxelWorld.instance.sfx.play("hurt", global_position, -4.0, randf_range(0.9, 1.1))
	if health <= 0.0:
		_die()


func possession_damage(remaining: float) -> void:
	health = remaining
	_since_hurt = 0.0
	hurt = 0.82
	shake(0.48)
	if health <= 0.0 and not god_mode:
		_die()


func _die() -> void:
	dead = true
	health = 0.0
	if is_instance_valid(hides):
		hides.reset_player()
	if _driving:
		exit_vehicle(true)
	if grabbed:
		release_grab(false)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("message"):
		hud.message("Вы погибли", 3.0)
	get_tree().create_timer(3.0).timeout.connect(_respawn)


func _respawn() -> void:
	dead = false
	health = MAX_HEALTH
	hurt = 0.0
	_exit_fall_protection = 0.0
	_clear_vehicle_exception()
	global_position = spawn_point
	velocity = Vector3.ZERO


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs < 0.55:
		_step_acc = 0.0
		return
	_step_acc += hs * delta
	var running := is_sprinting() and hs > 5.8
	if _step_acc >= (1.85 if running else (1.15 if _crouch else 1.48)):
		_step_acc = 0.0
		var world := VoxelWorld.instance
		var hit := world.raycast(global_position + Vector3.UP * 0.24, global_position - Vector3.UP * 0.5)
		var material := VoxMat.CONCRETE
		if not hit.is_empty() and hit.collider is VoxelObject:
			var object := hit.collider as VoxelObject
			var voxel := object.voxel_at_hit(hit.position, hit.normal)
			if voxel > 0:
				material = VoxMat.material_of(voxel)
		footstep_serial += 1
		footstep_material = material
		footstep_running = running
		world.sfx.footstep(material, global_position, running, _crouch, true)
		sound_emitted.emit(global_position, 4.8 if _crouch else (17.0 if running else 10.0), "step")
