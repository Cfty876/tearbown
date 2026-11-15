class_name VoxelAvatar
extends Node3D

const CELL := 0.044
const HEAD_LAYER := 1 << 3
static var _parts := {}
var _head: MeshInstance3D
var _arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _legs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _cycle := 0.0
var _stride := 0.0
var _run_blend := 0.0
var _jacket: MeshInstance3D
var first_person := false
var _hit_duration := 0.0
var _hit_remaining := 0.0
var _hit_strength := 0.0
var _hit_side := 0.0


func _ready() -> void:
	_build_parts()
	_jacket = _piece("jacket", Vector3(0.0, 0.73, 0.0))
	_head = _piece("head", Vector3(0.0, 1.59, 0.0))
	if first_person:
		_head.layers = HEAD_LAYER
		position.z = 0.18
	for side in [-1.0, 1.0]:
		var arm := _piece("arm", Vector3(side * 0.275, 1.32, 0.0))
		var elbow := _piece("forearm", Vector3(0.0, -0.264, 0.0), arm)
		_arms.append(arm)
		_forearms.append(elbow)
		var thigh := _piece("leg", Vector3(side * 0.112, 0.745, 0.0))
		var shin := _piece("shin", Vector3(0.0, -0.352, 0.0), thigh)
		_legs.append(thigh)
		_shins.append(shin)


func pose(speed: float, pitch: float, crouch: bool, delta: float, sprint := false) -> void:
	_run_blend = lerpf(_run_blend, float(sprint and speed > 1.0 and not crouch), 1.0 - exp(-11.0 * delta))
	_cycle += delta * speed * lerpf(2.10, 1.73, _run_blend)
	_stride = lerpf(_stride, clampf(speed / 6.0, 0.0, 1.0), 1.0 - exp(-11.0 * delta))
	var swing := sin(_cycle) * _stride
	scale.y = lerpf(scale.y, 0.64 if crouch else 1.0, 1.0 - exp(-13.0 * delta))
	var bob := (1.0 - cos(_cycle * 2.0)) * _run_blend * 0.026
	_jacket.position.y = 0.73 + bob
	_jacket.rotation = Vector3(-0.19 * _run_blend, swing * 0.12 * _run_blend, swing * 0.055 * _run_blend)
	_head.position = Vector3(0.0, 1.59 + bob, -0.10 * _run_blend)
	_head.rotation = Vector3(clampf(pitch - 0.06 * _run_blend, -0.73, 0.73), -_jacket.rotation.y * 0.38, 0.0)
	for i in 2:
		var sign_value := -1.0 if i == 0 else 1.0
		var stride := swing * sign_value
		_legs[i].rotation.x = stride * lerpf(0.58, 0.90, _run_blend) + (0.24 if crouch else 0.06 * _run_blend)
		_shins[i].rotation.x = -maxf(0.0, -stride) * lerpf(0.32, 1.12, _run_blend)
		_arms[i].position.y = 1.32 + bob
		_arms[i].position.z = -0.10 * _run_blend
		_arms[i].rotation.x = -stride * lerpf(0.43, 0.64, _run_blend) + 0.11 * _run_blend
		_arms[i].rotation.z = -sign_value * 0.09 * _run_blend
		_forearms[i].rotation.x = lerpf(0.08, 1.13, _run_blend) + maxf(0.0, stride) * 0.20 * _run_blend

	if _hit_remaining > 0.0:
		var elapsed := 1.0 - _hit_remaining / _hit_duration
		var recoil := smoothstep(-0.08, 0.13, elapsed) * (1.0 - smoothstep(0.12, 1.0, elapsed)) * _hit_strength
		_jacket.rotation.x += recoil * 0.70
		_jacket.rotation.z += recoil * _hit_side
		_head.rotation.x += recoil * 0.50
		_head.rotation.z = recoil * _hit_side * 0.60
		for i in 2:
			_arms[i].rotation.x += recoil * (0.68 if i == 0 else 1.05)
			_forearms[i].rotation.x += recoil * 0.60
		_hit_remaining = maxf(0.0, _hit_remaining - delta)


func flinch(duration: float, strength: float, push: Vector3) -> void:
	_hit_duration = duration
	_hit_remaining = duration
	_hit_strength = strength
	_hit_side = clampf(global_basis.x.normalized().dot(push), -1.0, 1.0)


func seated(on: bool) -> void:
	if first_person:
		_head.layers = 1 if on else HEAD_LAYER
		position.z = 0.0 if on else 0.18
	if not on:
		scale.y = 1.0
		return
	_jacket.rotation.x = 0.0
	_jacket.position.y = 0.73
	scale.y = 0.59
	_head.rotation.x = 0.0
	for i in 2:
		_legs[i].rotation.x = 1.38
		_shins[i].rotation.x = -1.16
		_arms[i].rotation.x = 0.91
		_forearms[i].rotation.x = 0.12


func _piece(key: String, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = _parts[key]
	piece.position = at
	(parent if parent != null else self).add_child(piece)
	return piece


static func _build_parts() -> void:
	if not _parts.is_empty():
		return
	var dark := VoxMat.id("vest_dark")
	var shirt := VoxMat.id("pvc")
	var stitch := VoxMat.id("metal_dark")
	var skin := VoxMat.id("skin")
	var hair := VoxMat.id("wood_dark")
	var head := VoxModel.volume(Vector3i(12, 11, 10))
	head.fill_box(Vector3i(1, 0, 0), Vector3i(11, 9, 9), skin)
	head.fill_box(Vector3i(0, 3, 3), Vector3i(12, 6, 7), skin)
	head.fill_box(Vector3i(1, 8, 0), Vector3i(11, 10, 10), hair)
	head.fill_box(Vector3i(2, 10, 1), Vector3i(10, 11, 8), hair)
	head.fill_box(Vector3i(1, 5, 7), Vector3i(11, 9, 10), hair)
	head.fill_box(Vector3i(1, 6, 0), Vector3i(3, 9, 3), hair)
	head.fill_box(Vector3i(3, 7, 0), Vector3i(7, 9, 2), hair)
	for x in [3, 8]:
		head.fill_box(Vector3i(x, 4, 0), Vector3i(x + 1, 6, 1), VoxMat.id("tank_black"))
	_parts["head"] = VoxModel.mesh(head, CELL, Vector3(6, 5, 5))
	var jacket := VoxModel.volume(Vector3i(12, 15, 8))
	jacket.fill_box(Vector3i.ZERO, jacket.get_size(), dark)
	jacket.fill_box(Vector3i(4, 2, 0), Vector3i(8, 14, 1), shirt)
	jacket.fill_box(Vector3i(6, 0, 0), Vector3i(7, 12, 1), stitch)
	jacket.fill_box(Vector3i(0, 0, 0), Vector3i(12, 2, 8), VoxMat.id("rubber"))
	_parts["jacket"] = VoxModel.mesh(jacket, CELL, Vector3(6, 0, 4))
	var arm := VoxModel.volume(Vector3i(4, 7, 6))
	arm.fill_box(Vector3i.ZERO, arm.get_size(), dark)
	_parts["arm"] = VoxModel.mesh(arm, CELL, Vector3(2, 6, 3))
	var forearm := VoxModel.volume(Vector3i(4, 7, 6))
	forearm.fill_box(Vector3i.ZERO, forearm.get_size(), dark)
	forearm.fill_box(Vector3i.ZERO, Vector3i(4, 3, 6), skin)
	forearm.fill_box(Vector3i(0, 3, 0), Vector3i(4, 4, 6), stitch)
	_parts["forearm"] = VoxModel.mesh(forearm, CELL, Vector3(2, 6, 3))
	var leg := VoxModel.volume(Vector3i(5, 9, 8))
	leg.fill_box(Vector3i(0, 0, 2), Vector3i(5, 9, 8), stitch)
	_parts["leg"] = VoxModel.mesh(leg, CELL, Vector3(2.5, 9, 5))
	var shin := VoxModel.volume(Vector3i(5, 9, 8))
	shin.fill_box(Vector3i(0, 3, 2), Vector3i(5, 9, 8), stitch)
	shin.fill_box(Vector3i.ZERO, Vector3i(5, 4, 8), VoxMat.id("boot"))
	_parts["shin"] = VoxModel.mesh(shin, CELL, Vector3(2.5, 9, 5))
