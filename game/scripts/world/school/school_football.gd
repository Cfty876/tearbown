class_name SchoolFootball
extends RigidBody3D

const START := Vector3(-24, 2.40, -52)
const RADIUS := 0.25
const GOAL_LEFT := -43.95
const GOAL_RIGHT := -4.05

var controller: SchoolSecrets
var _last := START
var _kick_ready := 0.0
var _reset_at := 0.0
var _replica := Transform3D.IDENTITY
var _has_pose := false


func _ready() -> void:
	name = "Воксельный футбольный мяч"
	position = START
	mass = 0.75
	linear_damp = 0.48
	angular_damp = 0.65
	continuous_cd = true
	collision_layer = Layers.DYNAMIC
	collision_mask = Layers.SOLID | Layers.PLAYER
	var material := PhysicsMaterial.new()
	material.friction = 0.64
	material.bounce = 0.56
	physics_material_override = material
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	var collider := CollisionShape3D.new()
	collider.shape = sphere
	add_child(collider)
	set_meta("secret_key", "football")
	var volume := Build.vol(Vector3i(15, 15, 15))
	for x in 15:
		for y in 15:
			for z in 15:
				var offset := Vector3(x - 7, y - 7, z - 7)
				if offset.length_squared() > 55.0:
					continue
				var axis := offset.abs()
				var patch := (axis.x > 4 and axis.y < 2 and axis.z < 3) or (axis.y > 4 and axis.z < 2 and axis.x < 3) \
					or (axis.z > 4 and axis.x < 2 and axis.y < 3) or (axis.x > 3 and axis.y > 3 and axis.z > 3)
				volume.set_voxel(Vector3i(x, y, z), VoxMat.id("rubber" if patch else ("metal_white" if (x + y + z) % 5 else "pvc")))
	var mesh := VoxModel.instance(volume, 0.035, Vector3.ONE * 7.5)
	add_child(mesh)


func try_kick(at: Vector3, shot: bool, verified_hit: bool, touch := false) -> bool:
	var distance := global_position.distance_squared_to(at)
	if distance > (2250.0 if shot else (1.0 if touch else 7.3)) or controller._now() < _kick_ready or _reset_at > 0.0:
		return false
	if not verified_hit and controller._target_key(controller.world.raycast(at + Vector3.UP * (0.42 if touch else 1.2),
			global_position, DistrictSecrets.MASK)) != "football":
		return false
	var direction := global_position - at
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return false
	_kick_ready = controller._now() + 0.26
	var aim := direction.normalized()
	apply_central_impulse(aim * (11.0 if shot else (3.0 if touch else 6.0)) + Vector3.UP * (1.15 if shot else 0.85))
	apply_torque_impulse(aim.cross(Vector3.UP) * 0.10)
	controller.world.sfx.play("thud", global_position, -5.0, 1.3)
	return true


func receive_pose(pose: Transform3D) -> void:
	if not _has_pose or global_position.distance_squared_to(pose.origin) > 9.0:
		global_transform = pose
		reset_physics_interpolation()
	_has_pose = true
	_replica = pose


func reset_ball() -> void:
	_reset_at = 0.0
	_kick_ready = 0.0
	_has_pose = false
	_last = START
	global_transform = Transform3D(Basis.IDENTITY, START)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if WebSession.connected and not WebSession.is_host:
		freeze = true
		if _has_pose:
			global_transform = global_transform.interpolate_with(_replica, minf(delta * 19.0, 1.0))
		return
	freeze = false
	var now := controller._now()
	if _reset_at > 0.0:
		if now >= _reset_at:
			reset_ball()
		return
	var at := global_position
	var goal := GOAL_LEFT if at.x < GOAL_LEFT and _last.x >= GOAL_LEFT else (GOAL_RIGHT if at.x > GOAL_RIGHT and _last.x <= GOAL_RIGHT else INF)
	if is_finite(goal):
		var crossing := _last.lerp(at, (goal - _last.x) / (at.x - _last.x))
		if absf(crossing.z + 53.5) < 3.35 and crossing.y > 2.1 and crossing.y < 4.05:
			_reset_at = now + 1.35
			var event := {"key": "football_goal", "side": 0}
			controller.apply_event(event)
			controller.football_scored.emit(event)
	if at.y < 0.4 or absf(at.x + 24.0) > 29.0 or at.z < -73.0 or at.z > -34.0:
		reset_ball()
		return
	_last = at
