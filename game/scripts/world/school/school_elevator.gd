class_name SchoolElevator
extends Node3D

const FLOORS := [-3.7, 2.2, 6.0, 9.8, 13.6]
const NAMES := ["подвал", "1-й этаж", "2-й этаж", "3-й этаж", "4-й этаж"]
const DOOR_TIME := 0.34
const FLOOR_THICKNESS := 0.2

var controller: SchoolSecrets
var cabin: AnimatableBody3D
var stop := 1
var busy := false
var doors_open := false
var _door_pairs: Array[Array] = []
var _cabin_leaves: Array[AnimatableBody3D] = []
var _motion: Tween
var _rider_height := INF


func build() -> void:
	var center := _at_floor(stop)
	var shell := Build.vol(Vector3i(18, 26, 18))
	SchoolLevel.box(shell, Vector3i.ZERO, Vector3i(18, 2, 18), "metal_dark")
	SchoolLevel.box(shell, Vector3i(0, 24, 0), Vector3i(18, 2, 18), "metal_teal")
	SchoolLevel.box(shell, Vector3i(0, 2, 0), Vector3i(18, 22, 1), "metal_teal")
	for x in [0, 17]:
		SchoolLevel.box(shell, Vector3i(x, 2, 1), Vector3i(1, 22, 17), "metal_teal")
		SchoolLevel.box(shell, Vector3i(x, 10, 2), Vector3i(1, 2, 14), "metal")
	for z in [1, 5, 9, 13, 17]:
		SchoolLevel.box(shell, Vector3i(1, 1, z), Vector3i(16, 1, 1), "rubber")
	SchoolLevel.box(shell, Vector3i(4, 23, 6), Vector3i(10, 1, 6), "lamp")
	SchoolLevel.box(shell, Vector3i(16, 7, 6), Vector3i(1, 15, 6), "metal_dark")
	cabin = AnimatableBody3D.new()
	cabin.name = "Кабина школьного лифта"
	cabin.position = center
	cabin.sync_to_physics = false
	cabin.collision_layer = Layers.STATIC
	cabin.collision_mask = 0
	add_child(cabin)
	DistrictSecretProps.model(cabin, shell, Vector3.ZERO)
	controller._collision(cabin, Vector3(1.8, 0.2, 1.8), Vector3(0, 0.1, 0))
	controller._collision(cabin, Vector3(1.8, 0.2, 1.8), Vector3(0, 2.5, 0))
	controller._collision(cabin, Vector3(1.8, 2.2, 0.1), Vector3(0, 1.3, -0.85))
	for side in [-1.0, 1.0]:
		controller._collision(cabin, Vector3(0.1, 2.2, 1.8), Vector3(side * 0.85, 1.3, 0))
	for side in [-1.0, 1.0]:
		var inner := _leaf(center + Vector3(side * 0.45, FLOOR_THICKNESS, 0.78))
		inner.reparent(cabin, true)
		_cabin_leaves.append(inner)
	for floor in FLOORS.size():
		var landing := _at_floor(floor)
		var leaves: Array[AnimatableBody3D] = []
		for side in [-1.0, 1.0]:
			leaves.append(_leaf(landing + Vector3(side * 0.45, FLOOR_THICKNESS, 1.04)))
		_door_pairs.append(leaves)
		var call := landing + Vector3(-1.19 if floor == 2 else 1.19, 1.36, 1.65)
		controller.mount_panel(call, FLOORS[floor], Vector3.BACK)
		controller.add_control("lift_call/%d" % floor, call,
			Vector3(0.23, 0.23, 0.18), "вызвать лифт · " + NAMES[floor], Vector3.BACK)
		var position_on_panel := Vector3(0.69, 0.87 + 0.22 * floor, -0.01)
		var select := controller.add_control("lift_floor/%d" % floor, center + position_on_panel,
			Vector3(0.14, 0.14, 0.12), "ехать · " + NAMES[floor], Vector3.LEFT)
		select.reparent(cabin, true)
		_label(cabin, position_on_panel + Vector3(-0.025, 0.012, 0.18), "−1" if floor == 0 else str(floor), -PI * 0.5, 0.0034)
		_label(self, landing + Vector3(0, 2.65, 1.16), "ЛИФТ  ·  " + ("−1" if floor == 0 else str(floor)), 0.0, 0.005)


func _leaf(at: Vector3) -> AnimatableBody3D:
	var leaf := Build.vol(Vector3i(9, 23, 2))
	SchoolLevel.box(leaf, Vector3i.ZERO, Vector3i(9, 23, 2), "metal_teal")
	SchoolLevel.box(leaf, Vector3i(1, 10, 1), Vector3i(7, 2, 1), "metal")
	SchoolLevel.box(leaf, Vector3i(4, 3, 1), Vector3i(1, 16, 1), "metal_dark")
	return controller._mover(leaf, at, Vector3(0.9, 2.3, 0.2), "Створка школьного лифта")


func _label(parent: Node3D, at: Vector3, title: String, yaw: float, scale_px: float) -> void:
	var label := Label3D.new()
	label.position = at
	label.rotation.y = yaw
	label.text = title
	label.pixel_size = scale_px
	label.font_size = 32
	label.modulate = Color("#f1e6c2")
	parent.add_child(label)


func _at_floor(floor: int) -> Vector3:
	return Vector3(SchoolLevel.LIFT.x, float(FLOORS[floor]) - FLOOR_THICKNESS, SchoolLevel.LIFT.y)


func landing(floor: int) -> Vector3:
	return _at_floor(floor) + Vector3(0.0, FLOOR_THICKNESS + 0.025, 2.04)


func cabin_feet() -> Vector3:
	return cabin.global_position + Vector3.UP * (FLOOR_THICKNESS + 0.025)


func request_for_bot(floor: int, feet: Vector3, inside: bool) -> bool:
	var key := ("lift_floor/" if inside else "lift_call/") + str(floor)
	if not can_move(key, floor, feet, controller.player.global_position):
		return false
	return not controller.authorize(key, 1, feet, false, false, true).is_empty()


func handles(key: String) -> bool:
	return key.begins_with("lift_call/") or key.begins_with("lift_floor/")


func can_move(key: String, floor: int, actor: Vector3, other: Vector3) -> bool:
	if busy or floor < 0 or floor >= FLOORS.size():
		return false
	if key.begins_with("lift_floor/") and not _inside(actor):
		return false
	return floor == stop or not (_in_threshold(actor) or _in_threshold(other))


func _inside(at: Vector3) -> bool:
	var offset := at - cabin.global_position
	return absf(offset.x) < 0.88 and absf(offset.z) < 0.88 and absf(offset.y - FLOOR_THICKNESS) < 0.38


func _in_threshold(at: Vector3) -> bool:
	if not at.is_finite():
		return false
	var offset := at - cabin.global_position
	return absf(offset.x) < 1.04 and absf(offset.z - 1.04) < 0.36 and absf(offset.y - FLOOR_THICKNESS) < 0.65


func move(floor: int) -> void:
	if busy or floor < 0 or floor >= FLOORS.size() or (stop == floor and doors_open):
		return
	busy = true
	_motion = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if floor != stop:
		_hold_rider()
		if doors_open:
			_slide(_motion, stop, false)
		doors_open = false
		var destination := _at_floor(floor).y
		var duration := maxf(0.55, absf(destination - cabin.position.y) / 3.0)
		_motion.tween_property(cabin, "position:y", destination, duration).set_trans(Tween.TRANS_SINE)
		controller.world.sfx.play("metal", cabin.global_position, -9.0)
	_motion.tween_callback(func():
		stop = floor
		controller.world.sfx.play("click", cabin.global_position, -7.0))
	_slide(_motion, floor, true)
	_motion.tween_callback(func():
		doors_open = true
		busy = false
		_release_rider())


func _slide(tween: Tween, floor: int, open: bool) -> void:
	var leaves := _door_pairs[floor]
	var offset := 1.4 if open else 0.45
	var x := SchoolLevel.LIFT.x
	tween.tween_property(leaves[0], "position:x", x - offset, DOOR_TIME).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(leaves[1], "position:x", x + offset, DOOR_TIME).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_cabin_leaves[0], "position:x", -offset, DOOR_TIME).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_cabin_leaves[1], "position:x", offset, DOOR_TIME).set_trans(Tween.TRANS_SINE)


func _hold_rider() -> void:
	var player := controller.player
	if not _inside(player.global_position) or player.transit_active or player.dead:
		return
	_rider_height = player.global_position.y - cabin.global_position.y
	player.velocity = Vector3.ZERO
	player.release_grab(false)
	player.tools.cancel_placement()
	player.transit_active = true


func _physics_process(_delta: float) -> void:
	if is_finite(_rider_height):
		controller.player.global_position.y = cabin.global_position.y + _rider_height


func _release_rider() -> void:
	if is_finite(_rider_height):
		controller.player.global_position.y = cabin.global_position.y + _rider_height
		controller.player.velocity = Vector3.ZERO
		controller.player.transit_active = false
		controller.player.reset_physics_interpolation()
		_rider_height = INF


func reset() -> void:
	if is_instance_valid(_motion):
		_motion.kill()
	_release_rider()
	stop = 1
	busy = false
	doors_open = false
	cabin.position = _at_floor(stop)
	_cabin_leaves[0].position.x = -0.45
	_cabin_leaves[1].position.x = 0.45
	for leaves in _door_pairs:
		leaves[0].position.x = SchoolLevel.LIFT.x - 0.45
		leaves[1].position.x = SchoolLevel.LIFT.x + 0.45
