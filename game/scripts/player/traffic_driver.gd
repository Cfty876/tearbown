class_name TrafficDriver
extends Node
## Autopilot for background traffic: follows a lane polyline at cruise speed,
## brakes for anything in front, and loops back to the start when the route
## ends (only while the player is far away, so nobody sees the teleport).
## A wrecked, flipped or player-driven vehicle stops being traffic.

var vehicle: VoxelVehicle
var route: Array[Vector3] = []
var cruise := 9.0
var _i := 1
var _stuck := 0.0
var _flipped := 0.0
var _start_voxels := 0
var _start_xform: Transform3D
var _waiting := false
var _wait_t := 0.0


static func attach(v: VoxelVehicle, points: Array[Vector3], speed: float) -> TrafficDriver:
	var d := TrafficDriver.new()
	d.vehicle = v
	d.route = points
	d.cruise = speed
	d.name = "Traffic"
	v.body.add_child(d)
	return d


func _ready() -> void:
	_start_voxels = vehicle.body.voxel_count()
	_start_xform = vehicle.body.global_transform
	vehicle.auto_active = true


func _stop() -> void:
	if is_instance_valid(vehicle):
		vehicle.auto_active = false
		vehicle.auto_throttle = 0.0
	queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(vehicle.body) or vehicle.driver:
		_stop()
		return
	var b := vehicle.body
	if b.freeze:
		return
	if b.voxel_count() < _start_voxels * 0.8:
		_stop()  # wrecked
		return
	var up := b.global_basis.y
	_flipped = _flipped + delta if up.y < 0.4 else 0.0
	if _flipped > 2.0:
		_stop()
		return
	if _waiting:
		vehicle.auto_throttle = 0.0
		vehicle.auto_brake = true
		_wait_t += delta
		if _wait_t > 1.0:
			_wait_t = 0.0
			_restart()
		return
	var pos := b.world_center()
	var fwd := (b.global_basis * vehicle.forward_local)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var target := route[_i]
	var to := target - pos
	to.y = 0.0
	if to.length() < 5.0:
		_i += 1
		if _i >= route.size():
			_restart()
			return
		target = route[_i]
		to = target - pos
		to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	vehicle.auto_steer = clampf(ang * 2.2, -1.0, 1.0)
	# Brake for obstacles straight ahead (not the road itself).
	var front := pos + fwd * 3.0 + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(front, front + fwd * (4.0 + vehicle.speed * 0.9), Layers.SOLID | Layers.PLAYER, [b.get_rid()])
	var hit := b.get_world_3d().direct_space_state.intersect_ray(q)
	var want := cruise * (1.0 - clampf(absf(ang) - 0.2, 0.0, 0.6))
	if not hit.is_empty():
		want = 0.0
	var err := want - vehicle.speed
	vehicle.auto_throttle = clampf(err * 0.35, -1.0, 1.0)
	vehicle.auto_brake = want == 0.0 and vehicle.speed < 1.0
	if want > 1.0 and vehicle.speed < 0.4:
		_stuck += delta
		if _stuck > 8.0:
			_restart()
	else:
		_stuck = 0.0


func _restart() -> void:
	_i = 1
	_stuck = 0.0
	var p := VoxelWorld.instance.player
	if p and (p.global_position.distance_to(_start_xform.origin) < 40.0 or p.global_position.distance_to(vehicle.body.global_position) < 40.0):
		_waiting = true
		return  # wait until nobody watches
	_waiting = false
	vehicle.auto_brake = false
	var b := vehicle.body
	b.global_transform = _start_xform
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
