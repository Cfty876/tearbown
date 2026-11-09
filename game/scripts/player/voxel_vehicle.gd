class_name VoxelVehicle
extends Node
## Raycast vehicle that drives a dynamic VoxelObject: four suspension rays,
## engine, brakes, steering and tire grip applied as forces. The car body stays
## a normal destructible voxel object; a wheel whose hub voxels were destroyed
## stops working. Enter/leave with E (handled by Player).

const RADIUS_DEFAULT := 0.34
const TRAVEL := 0.16
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
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if driver:
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
	var k := per_wheel * 9.8 / (TRAVEL * 0.7)
	var c := 2.0 * sqrt(k * per_wheel) * 0.45
	var com := body.to_global(body.center_of_mass)
	var space := body.get_world_3d().direct_space_state
	_contacts = 0
	for i in hubs.size():
		var hub_local := hubs[i]
		var hv := Vector3i((hub_local / VoxelObject.VS).floor())
		if body.volume.get_voxel(hv) == 0:
			continue  # wheel shot off
		var hub := xf * hub_local
		var q := PhysicsRayQueryParameters3D.create(hub, hub - up * (radius + TRAVEL), Layers.SOLID, [body.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		_contacts += 1
		var p: Vector3 = hit.position
		var dist := hub.distance_to(p)
		var compression := radius + TRAVEL - dist
		var r := p - body.global_position
		var vel := body.linear_velocity + body.angular_velocity.cross(p - com)
		var fn := maxf(k * compression - c * vel.dot(up), 0.0)
		body.apply_force(up * fn, r)

		var wf := fwd
		if i < 2:
			wf = fwd.rotated(up, _steer)
		var wr := up.cross(wf).normalized()
		var v_long := vel.dot(wf)
		var v_lat := vel.dot(wr)
		# Tire forces act at axle height near the center of mass to limit body roll.
		var r_tire := r + up * (com - p).dot(up) * 0.6
		var max_f := fn * GRIP
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
				f_long = throttle * per_wheel * 4.2
		else:
			f_long = -v_long * per_wheel * 0.4
		f_long = clampf(f_long, -max_f, max_f)
		body.apply_force(wr * f_lat + wf * f_long, r_tire)
	VoxelWorld.instance.sfx.loop("engine_%d" % get_instance_id(), "engine", body.global_position, driver != null,
		-8.0 + absf(throttle) * 3.0, 0.55 + absf(speed) / 16.0)
	if driver and _contacts > 0:
		body.angular_velocity -= body.angular_velocity.project(fwd) * 0.08


func seat_position() -> Vector3:
	return body.to_global(body.center_of_mass + Vector3(0, 0.5, 0))


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
