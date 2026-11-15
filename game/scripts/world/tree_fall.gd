class_name TreeFall
extends Node

const LEAN_TIME := 0.62
const LEAN_ANGLE := 0.44
const STUMP_CLEARANCE_TIME := 0.45

var trunk: VoxelObject
var _stump: VoxelObject
var _axis := Vector3.RIGHT
var _cut := Vector3.ZERO
var _initial: Transform3D
var _elapsed := 0.0
var _released := false


static func begin(parent: Node3D, stump: VoxelObject, piece: VoxelObject, cut: Vector3, direction: Vector3) -> void:
	var fall := TreeFall.new()
	fall.trunk = piece
	fall._stump = stump
	fall._cut = cut
	fall._initial = piece.global_transform
	fall._axis = Vector3.UP.cross(direction).normalized()
	piece.tree_falling = true
	piece.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	piece.freeze = true
	parent.add_child(fall)
	fall._ignore_stump(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(trunk):
		queue_free()
		return
	_elapsed += delta
	if _released:
		if _elapsed >= LEAN_TIME + STUMP_CLEARANCE_TIME:
			queue_free()
		return
	var t := minf(_elapsed / LEAN_TIME, 1.0)
	var angle := LEAN_ANGLE * (t * 0.20 + t * t * 0.80)
	var turn := Basis(_axis, angle)
	trunk.global_transform = Transform3D(turn * _initial.basis, _cut + turn * (_initial.origin - _cut))
	if t >= 1.0:
		var omega := _axis * (LEAN_ANGLE * 1.8 / LEAN_TIME)
		var arm := trunk.to_global(trunk.center_of_mass) - _cut
		trunk.freeze = false
		trunk.sleeping = false
		trunk.linear_velocity = omega.cross(arm)
		trunk.angular_velocity = omega
		_released = true


func _exit_tree() -> void:
	_ignore_stump(false)


func _ignore_stump(ignore: bool) -> void:
	if not is_instance_valid(trunk) or not is_instance_valid(_stump):
		return
	for chunk in _stump._chunks.values():
		if not chunk.body.is_valid():
			continue
		if ignore:
			PhysicsServer3D.body_add_collision_exception(trunk.get_rid(), chunk.body)
		else:
			PhysicsServer3D.body_remove_collision_exception(trunk.get_rid(), chunk.body)
