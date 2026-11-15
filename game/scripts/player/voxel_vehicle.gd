class_name VoxelVehicle
extends Node
## Raycast vehicle that drives a dynamic VoxelObject: four suspension rays,
## engine, brakes, steering and tire grip applied as forces. The car body stays
## a normal destructible voxel object; a wheel whose hub voxels were destroyed
## stops working. Enter/leave with E (handled by Player).

const RADIUS_DEFAULT := 0.34
const TRAVEL := 0.16
const DRIVER_TRAVEL := 0.27
const MAX_STEP := 0.42
const UPRIGHT_LIMIT := 0.48
const GRIP := 1.15
const MAX_STEER := 0.55

var body: VoxelObject
## Wheel hubs in object space (meters); the first two are the steered front wheels.
var hubs: Array[Vector3] = []
## Object-space forward direction of the car.
var forward_local := Vector3(-1, 0, 0)
var driver: Player
var speed := 0.0
var radius := RADIUS_DEFAULT
## Autopilot input (traffic): used when no player drives.
var auto_active := false
var auto_throttle := 0.0
var auto_steer := 0.0
var auto_brake := false

var _steer := 0.0
var _contacts := 0
var _step_cooldown := 0.0
var _travel := TRAVEL


static func attach(obj: VoxelObject, hub_points: Array[Vector3], forward: Vector3, wheel_radius := RADIUS_DEFAULT) -> VoxelVehicle:
	var v := VoxelVehicle.new()
	v.radius = wheel_radius
	v.body = obj
	v.hubs = hub_points
	v.forward_local = forward
	v.name = "Vehicle"
	obj.add_child(v)
	return v


func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if body.freeze:
		return
	_travel = move_toward(_travel, DRIVER_TRAVEL if driver else TRAVEL, delta * 0.52)
	var travel := _travel
	_step_cooldown = maxf(0.0, _step_cooldown - delta)
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if driver:
		if driver.movement_enabled and not driver.navigation_menu_open:
			throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
			steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
			handbrake = Input.is_action_pressed("jump")
		body.sleeping = false
	elif auto_active:
		throttle = auto_throttle
		steer_in = auto_steer
		handbrake = auto_brake
		body.sleeping = false
	elif body.sleeping:
		return

	var xf := body.global_transform
	var up := xf.basis.y.normalized()
	var fwd := (xf.basis * forward_local).normalized()
	speed = body.linear_velocity.dot(fwd)
	var steer_limit := MAX_STEER * (1.0 - clampf(absf(speed) / 35.0, 0.0, 0.65))
	_steer = move_toward(_steer, steer_in * steer_limit, delta * 2.5)

	var m := body.mass
	var per_wheel := m / 4.0
	var k := per_wheel * 9.8 / (travel * 0.62)
	var c := 2.0 * sqrt(k * per_wheel) * 0.45
	var com := body.to_global(body.center_of_mass)
	var space := body.get_world_3d().direct_space_state
	var exclude: Array[RID] = [body.get_rid()]
	var drive_direction := (fwd * signf(throttle)).slide(Vector3.UP).normalized()
	_contacts = 0
	for i in hubs.size():
		var hub_local := hubs[i]
		var hv := Vector3i((hub_local / VoxelObject.VS).floor())
		if body.volume.get_voxel(hv) == 0:
			continue  # wheel shot off
		var hub := xf * hub_local
		var q := PhysicsRayQueryParameters3D.create(hub, hub - up * (radius + travel), Layers.SOLID, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		_contacts += 1
		var p: Vector3 = hit.position
		var dist := hub.distance_to(p)
		var compression := radius + travel - dist
		var r := p - body.global_position
		var vel := body.linear_velocity + body.angular_velocity.cross(p - com)
		var fn := maxf(k * compression - c * vel.dot(up), 0.0)
		body.apply_force(up * fn, r)

		var wf := fwd
		if i < 2:
			wf = fwd.rotated(up, _steer)
		var normal: Vector3 = hit.normal
		if normal.dot(up) > 0.38:
			wf = wf.slide(normal).normalized()
		var wr := normal.cross(wf).normalized()
		var v_long := vel.dot(wf)
		var v_lat := vel.dot(wr)
		# Tire forces act at axle height near the center of mass to limit body roll.
		var r_tire := r + up * (com - p).dot(up) * 0.6
		var max_f := fn * (1.52 if driver else GRIP)
		var f_lat := clampf(-v_lat * per_wheel / delta * 0.5, -max_f, max_f)
		var f_long := 0.0
		if handbrake:
			f_long = clampf(-v_long * per_wheel / delta * 0.3, -max_f, max_f)
			f_lat *= 0.35
		elif throttle != 0.0:
			var reverse := signf(throttle) != signf(v_long) and absf(v_long) > 0.5
			if reverse:
				f_long = signf(throttle) * minf(per_wheel * 9.0, absf(v_long) * per_wheel / delta)
			elif absf(v_long) < 22.0:
				var pull := lerpf(7.2, 4.2, smoothstep(4.0, 13.0, absf(v_long))) if driver else 4.2
				f_long = throttle * per_wheel * pull
		else:
			f_long = -v_long * per_wheel * 0.4
		f_long = clampf(f_long, -max_f, max_f)
		body.apply_force(wr * f_lat + wf * f_long, r_tire)
	if driver and _contacts > 0 and absf(throttle) > 0.1 and up.y > UPRIGHT_LIMIT and _step_cooldown == 0.0 and absf(speed) < 3.2:
		var rise := _step_height(space, drive_direction, exclude)
		if rise > 0.0:
			_try_step_up(drive_direction, rise)
	VoxelWorld.instance.sfx.loop("engine_%d" % get_instance_id(), "engine", body.global_position, driver != null,
		-8.0 + absf(throttle) * 3.0, 0.55 + absf(speed) / 16.0)
	if driver and _contacts > 0:
		body.angular_velocity -= body.angular_velocity.project(fwd) * 0.13


func _step_height(space: PhysicsDirectSpaceState3D, direction: Vector3, exclude: Array[RID]) -> float:
	var size := Vector3(body.volume.get_size()) * VoxelObject.VS
	var half_length := size.x * 0.5 if absf(forward_local.x) > 0.5 else size.z * 0.5
	var center := body.world_center()
	var axle := direction * maxf(0.0, half_length - 0.87)
	var rise := _step_at(space, center + axle, direction, size.y, exclude)
	if rise > 0.0:
		return rise
	# The rear axle reaches the same ledge after the front wheels are already up.
	return _step_at(space, center - axle, direction, size.y, exclude)


func _step_at(space: PhysicsDirectSpaceState3D, axle: Vector3, direction: Vector3,
		height: float, exclude: Array[RID]) -> float:
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		axle + Vector3.UP * 0.5, axle - Vector3.UP * (height + 0.55), Layers.STATIC, exclude))
	if ground.is_empty() or ground.normal.y < 0.68:
		return 0.0
	var from: Vector3 = ground.position + Vector3.UP * 0.09
	var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * 1.38, Layers.STATIC, exclude))
	if face.is_empty() or absf(face.normal.y) > 0.45 or face.normal.dot(direction) > -0.5:
		return 0.0
	var upper: Vector3 = face.position + direction * 0.13 + Vector3.UP * MAX_STEP
	var probe := PhysicsRayQueryParameters3D.create(upper, upper - Vector3.UP * (MAX_STEP + 0.12), Layers.STATIC, exclude)
	probe.hit_from_inside = true
	var top := space.intersect_ray(probe)
	if top.is_empty() or top.normal.y < 0.68:
		return 0.0
	var rise: float = top.position.y - ground.position.y
	return rise if rise >= 0.06 and rise <= MAX_STEP else 0.0


func _try_step_up(direction: Vector3, rise: float) -> void:
	var motion := PhysicsTestMotionParameters3D.new()
	var start := body.global_transform
	motion.from = start
	var lift := Vector3.UP * (rise + 0.10)
	motion.motion = lift
	if PhysicsServer3D.body_test_motion(body.get_rid(), motion):
		return
	var raised := start.translated(lift)
	motion.from = raised
	motion.motion = direction * 0.76
	if PhysicsServer3D.body_test_motion(body.get_rid(), motion):
		return
	body.global_transform = raised.translated(direction * 0.68)
	var velocity := body.linear_velocity
	velocity += direction * maxf(0.0, 1.8 - velocity.dot(direction))
	velocity.y = clampf(velocity.y, 0.0, 0.8)
	body.linear_velocity = velocity
	body.sleeping = false
	_step_cooldown = 0.38


func tipped() -> bool:
	return is_instance_valid(body) and body.global_basis.y.normalized().y < UPRIGHT_LIMIT


func right_vehicle() -> bool:
	if not tipped() or body.freeze or body.linear_velocity.length_squared() > 16.0:
		return false
	var forward := (body.global_basis * forward_local).slide(Vector3.UP)
	if forward.length_squared() < 0.02:
		forward = body.global_basis.z.cross(Vector3.UP)
	if forward.length_squared() < 0.02:
		forward = Vector3.FORWARD
	var upright := Basis.looking_at(forward, Vector3.UP) * Basis.looking_at(forward_local, Vector3.UP).inverse()
	var size := Vector3(body.volume.get_size()) * VoxelObject.VS
	var space := body.get_world_3d().direct_space_state
	var exclude: Array[RID] = [body.get_rid()]
	if is_instance_valid(driver):
		exclude.append(driver.get_rid())
	var clearance := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size * Vector3(0.97, 0.96, 0.97)
	clearance.shape = box
	clearance.collision_mask = Layers.SOLID | Layers.PLAYER
	clearance.exclude = exclude
	var center := body.world_center()
	var offsets := [Vector2.ZERO, Vector2(0.70, 0), Vector2(-0.70, 0), Vector2(0, 0.70), Vector2(0, -0.70)]
	for offset: Vector2 in offsets:
		var at := center + Vector3(offset.x, 0, offset.y)
		if driver and (absf(at.x) > driver.border - 0.4 or absf(at.z) > driver.border - 0.4):
			continue
		var floor_height := _recovery_floor(space, at, upright, size, exclude)
		if not is_finite(floor_height):
			continue
		at.y = floor_height + size.y * 0.5 + 0.065
		clearance.transform = Transform3D(upright, at)
		if not space.intersect_shape(clearance, 1).is_empty():
			continue
		body.global_transform = Transform3D(upright, at - upright * (size * 0.5))
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
		body.reset_physics_interpolation()
		speed = 0.0
		_steer = 0.0
		VoxelWorld.instance.sfx.play("metal", at, -5.0, 0.85)
		return true
	return false


func _recovery_floor(space: PhysicsDirectSpaceState3D, center: Vector3, basis: Basis, size: Vector3,
		exclude: Array[RID]) -> float:
	var high := -INF
	var low := INF
	for sample in [Vector2.ZERO, Vector2(-0.32, -0.30), Vector2(0.32, -0.30), Vector2(-0.32, 0.30), Vector2(0.32, 0.30)]:
		var point := center + basis * Vector3(size.x * sample.x, 0, size.z * sample.y)
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.70, point - Vector3.UP * 2.3, Layers.STATIC, exclude)
		ray.hit_from_inside = true
		var floor := space.intersect_ray(ray)
		if floor.is_empty() or floor.normal.y < 0.60:
			return INF
		high = maxf(high, floor.position.y)
		low = minf(low, floor.position.y)
	return high if high - low <= MAX_STEP else INF


func seat_position() -> Vector3:
	var front_axle := hubs[0].lerp(hubs[1], 0.28)
	var cabin_floor := front_axle + Vector3.UP * 0.12 - forward_local * 0.72
	return body.to_global(cabin_floor)


func seat_basis() -> Basis:
	return body.global_basis * Basis.looking_at(forward_local, Vector3.UP)


func chase_camera(yaw_offset: float, pitch: float) -> Transform3D:
	var fwd := (body.global_basis * forward_local)
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	fwd = fwd.rotated(Vector3.UP, yaw_offset)
	var target := body.to_global(body.center_of_mass) + Vector3.UP * 1.0
	var dir := (fwd * cos(pitch) + Vector3.UP * sin(-pitch)).normalized()
	var cam := target - dir * 7.0 + Vector3.UP * 1.2
	# Keep the camera out of walls.
	var q := PhysicsRayQueryParameters3D.create(target, cam, Layers.STATIC, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		cam = hit.position + (target - cam).normalized() * 0.3
	return Transform3D.IDENTITY.looking_at(target - cam, Vector3.UP).translated(cam)
