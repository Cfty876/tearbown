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
const GRAB_FORCE := 2600.0     # N; ~120 kg can be carried, heavier things only dragged
const THROW_SPEED := 13.0
## Half size of the walkable map (set by main for the loaded level).
var border := 39.4

var mouse_sensitivity := 0.0022
var touch_mode := false
var movement_enabled := true
var interaction_enabled := true
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
var _pre_speed := 0.0

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


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
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
	camera.fov = 78.0
	camera.near = 0.03
	camera.far = 600.0
	head.add_child(camera)
	camera.make_current()
	tools = PlayerTools.new()
	tools.player = self
	camera.add_child(tools)
	spawn_point = global_position
	_yaw = rotation.y


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and not touch_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(e.relative)
	elif e is InputEventMouseButton and e.pressed and not touch_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("grab"):
		interact()


func apply_look(relative: Vector2) -> void:
	if vehicle:
		_car_yaw -= relative.x * mouse_sensitivity
		_car_pitch = clampf(_car_pitch + relative.y * mouse_sensitivity, -0.2, 1.2)
		return
	look_at_dir(_yaw - relative.x * mouse_sensitivity,
		clampf(_pitch - relative.y * mouse_sensitivity, -1.53, 1.53))


func interact() -> void:
	if dead or not movement_enabled or not interaction_enabled:
		return
	if vehicle:
		exit_vehicle()
	elif grabbed:
		release_grab(false)
	elif not try_enter_vehicle():
		try_grab()


func look_at_dir(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	rotation.y = yaw
	head.rotation.x = pitch


func aim_ray(length: float) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var ex: Array[RID] = [get_rid()]
	return VoxelWorld.instance.raycast(from, to, Layers.SOLID, ex)


func aim_dir() -> Vector3:
	return -camera.global_basis.z


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector3.ZERO
		return
	if vehicle:
		if not is_instance_valid(vehicle) or not is_instance_valid(vehicle.body):
			exit_vehicle()
		else:
			global_position = vehicle.seat_position()
			velocity = Vector3.ZERO
			return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if movement_enabled else Vector2.ZERO
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch != _crouch:
		_set_crouch(want_crouch)
	var speed := CROUCH_SPEED if _crouch else (SPRINT if is_sprinting() else WALK)
	var wish := (global_basis * Vector3(input.x, 0, input.y))
	wish.y = 0
	wish = wish.normalized() * speed

	if is_on_floor():
		var k := 1.0 - exp(-14.0 * delta)
		velocity.x = lerpf(velocity.x, wish.x, k)
		velocity.z = lerpf(velocity.z, wish.z, k)
		if movement_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	else:
		var k := 1.0 - exp(-2.5 * delta)
		velocity.x = lerpf(velocity.x, wish.x, k)
		velocity.z = lerpf(velocity.z, wish.z, k)
		velocity.y -= GRAVITY * delta

	_try_step_up(delta)
	_pre_speed = Vector2(velocity.x, velocity.z).length()
	var fall_speed := -velocity.y
	var was_floor := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_floor and fall_speed > 11.0:
		damage((fall_speed - 11.0) * 9.0)
		VoxelWorld.instance.sfx.play("thud", global_position, 0.0, 0.7)
	_footsteps(delta)
	if not WebSession.connected or WebSession.is_host:
		_push_bodies(delta)
	_update_grab(delta)

	# Map border (half size of the loaded voxel terrain).
	global_position.x = clampf(global_position.x, -border, border)
	global_position.z = clampf(global_position.z, -border, border)
	if global_position.y < -30.0:
		global_position = spawn_point
		velocity = Vector3.ZERO


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
		var vo := c.get_collider() as VoxelObject
		if vo and _pre_speed > 2.0 and absf(c.get_normal().y) < 0.5:
			# Running into a window breaks it instead of stopping like a wall.
			var vox := vo.voxel_at_hit(c.get_position(), c.get_normal())
			if vox != 0 and VoxMat.material_of(vox) == VoxMat.GLASS:
				var p := c.get_position() - c.get_normal() * 0.05
				VoxelWorld.instance.damage_at(vo, p, 0.6, 0.6, Vector3.ZERO, 0.5, 14)
				VoxelWorld.instance.damage_at(vo, p + Vector3.UP * 0.7, 0.6, 0.6, Vector3.ZERO, 0.5, 14)
				velocity += -c.get_normal() * _pre_speed * 0.6
				continue
		var body := c.get_collider() as RigidBody3D
		if body == null or body.freeze or body == grabbed:
			continue
		var push := -c.get_normal()
		push.y = maxf(push.y, 0.0)
		var strength := clampf(velocity.length() * 9.0, 0.0, 60.0)
		body.apply_impulse(push * strength * minf(body.mass, 80.0) / 80.0, c.get_position() - body.global_position)


func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint") and not _crouch and Input.is_action_pressed("move_forward")


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
	hurt = maxf(hurt - delta * 1.5, 0.0)
	_since_hurt += delta
	if not dead and _since_hurt > 4.0 and health < MAX_HEALTH:
		health = minf(health + 14.0 * delta, MAX_HEALTH)
	if vehicle and is_instance_valid(vehicle) and is_instance_valid(vehicle.body):
		camera.global_transform = vehicle.chase_camera(_car_yaw, _car_pitch)
		return
	var target_eye := CROUCH_EYE if _crouch else STAND_EYE
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-12.0 * delta))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob_t += delta * hspeed * 1.9
	var bob := sin(_bob_t) * 0.035 * clampf(hspeed / WALK, 0.0, 1.5)
	head.position = Vector3(0, _eye + bob, 0)
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
	if hit.is_empty():
		return
	var obj := hit.collider as VoxelObject
	if obj == null or obj.static_mode:
		return
	grabbed = obj
	grabbed.held = true
	_grab_local = obj.to_local(hit.position)
	_grab_dist = clampf(camera.global_position.distance_to(hit.position), 1.3, GRAB_RANGE)
	add_collision_exception_with(obj)
	obj.sleeping = false
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
	var obj := grabbed
	grabbed = null
	# Re-enable collision with the player once the object is clear.
	get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(obj):
			remove_collision_exception_with(obj))


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

func try_enter_vehicle() -> bool:
	var hit := aim_ray(3.5)
	if hit.is_empty():
		return false
	var obj := hit.collider as VoxelObject
	if obj == null or not obj.has_node("Vehicle"):
		return false
	enter_vehicle(obj.get_node("Vehicle"))
	return true


func enter_vehicle(v: VoxelVehicle) -> void:
	var obj := v.body
	vehicle = v
	vehicle.driver = self
	collision_layer = 0
	collision_mask = 0
	camera.top_level = true
	_car_yaw = 0.0
	_car_pitch = 0.22
	_set_hands(false)
	VoxelWorld.instance.sfx.play("click", obj.global_position, -6.0)


func _set_hands(on: bool) -> void:
	if tools:
		tools.visible = on
		tools.input_enabled = on


func exit_vehicle() -> void:
	var v := vehicle
	vehicle = null
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
	_set_hands(true)
	if v == null or not is_instance_valid(v) or not is_instance_valid(v.body):
		return
	v.driver = null
	# Step out on the left side of the car, or on the roof if that is blocked.
	var b := v.body
	var side := b.global_basis * v.forward_local.cross(Vector3.UP).normalized()
	var spots := [b.to_global(b.center_of_mass) - side * 1.6, b.to_global(b.center_of_mass) + side * 1.6,
		b.to_global(b.center_of_mass) + Vector3.UP * 1.6]
	for p: Vector3 in spots:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _capsule
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.5, 0))
		q.collision_mask = Layers.SOLID
		if get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			global_position = p - Vector3(0, 0.4, 0)
			break
	velocity = b.linear_velocity
	look_at_dir(atan2(-side.x, -side.z) + PI * 0.5, 0.0)


# ------------------------------------------------------------------ health

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


func _die() -> void:
	dead = true
	health = 0.0
	if vehicle:
		exit_vehicle()
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
	global_position = spawn_point
	velocity = Vector3.ZERO


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	_step_acc += hs * delta
	if _step_acc > (0.9 if hs > 6.0 else 0.7):
		_step_acc = 0.0
		VoxelWorld.instance.sfx.play("step", global_position, -14.0 + (4.0 if hs > 6.0 else 0.0), randf_range(0.85, 1.15))
