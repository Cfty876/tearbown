class_name DistrictDoor
extends Node

var body: VoxelObject
var opened := false
var _closed_yaw: float
var _width := 0.9
var _animation: Tween
var _hinge: Vector3
var _open_turn := 0.0
const PIVOT_OFFSET := Vector3(0.0, 0.0, 0.15)


static func install(parent: Node3D, hinge: Vector3, yaw: float, finish: String) -> void:
	var volume := Build.vol(Vector3i(9, 20, 3))
	volume.fill_box(Vector3i(0, 0, 1), Vector3i(9, 20, 2), VoxMat.id(finish))
	var dark := VoxMat.id("wood_dark")
	for x in [0, 8]:
		volume.fill_box(Vector3i(x, 1, 0), Vector3i(x + 1, 20, 1), dark)
	for y in [1, 9, 18]:
		volume.fill_box(Vector3i(1, y, 0), Vector3i(8, y + 1, 1), dark)
	for z in [0, 2]:
		volume.fill_box(Vector3i(6, 9, z), Vector3i(8, 10, z + 1), VoxMat.id("metal_yellow"))
	install_leaf(parent, hinge, yaw, volume)


static func install_leaf(parent: Node3D, hinge: Vector3, yaw: float, volume: VoxelVolume, open_turn := 0.0) -> DistrictDoor:
	var obj := VoxelObject.new()
	obj.setup(volume, false)
	obj.label = "Дверь"
	obj.freeze = true
	obj.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	obj.transform = Transform3D(Basis(Vector3.UP, yaw), hinge - Basis(Vector3.UP, yaw) * PIVOT_OFFSET)
	parent.add_child(obj)
	var door := DistrictDoor.new()
	door.name = "DistrictDoor"
	door.body = obj
	door._closed_yaw = yaw
	door._hinge = hinge
	door._open_turn = open_turn
	door._width = volume.get_size().x * 0.1
	obj.add_child(door)
	return door


func interact(actor: Vector3, other := Vector3.INF) -> void:
	if body.global_position.distance_squared_to(actor) > 10.0:
		return
	if WebSession.connected and not WebSession.is_host:
		WebSession.send({"k": "door_request", "id": body.network_id})
		return
	if opened and (_in_swing(actor) or _in_swing(other)):
		return
	var forward := Basis(Vector3.UP, _closed_yaw).z
	var away := 1.0 if (actor - body.global_position).dot(forward) >= 0.0 else -1.0
	var turn := (_open_turn if not is_zero_approx(_open_turn) else away * deg_to_rad(92.0)) if not opened else 0.0
	set_open(not opened, turn)
	if WebSession.connected:
		WebSession.send({"k": "door_set", "id": body.network_id, "open": opened, "turn": turn})


func set_open(on: bool, turn: float) -> void:
	opened = on
	if _animation:
		_animation.kill()
	_animation = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var angle := _closed_yaw + clampf(turn, -1.62, 1.62)
	var swing := _animation.tween_method(_set_angle, _closed_yaw + angle_difference(_closed_yaw, body.rotation.y), angle, 0.34 if on else 0.42)
	swing.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN_OUT)
	VoxelWorld.instance.sfx.play("hide_wood", body.global_position, -12.0, 0.87)


func _set_angle(angle: float) -> void:
	var basis := Basis(Vector3.UP, angle)
	body.transform = Transform3D(basis, _hinge - basis * PIVOT_OFFSET)


func _in_swing(at: Vector3) -> bool:
	if not at.is_finite() or absf(at.y - body.global_position.y) > 1.8:
		return false
	var hinge := (body.get_parent() as Node3D).to_global(_hinge)
	var feet := Vector3(at.x, hinge.y, at.z)
	for i in 9:
		var angle := _closed_yaw + angle_difference(_closed_yaw, body.rotation.y) * (1.0 - i / 8.0)
		var tip := hinge + Basis(Vector3.UP, angle) * Vector3(_width, 0, 0)
		if Geometry3D.get_closest_point_to_segment(feet, hinge, tip).distance_squared_to(feet) < 0.22:
			return true
	return false
