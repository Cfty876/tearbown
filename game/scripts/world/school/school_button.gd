class_name SchoolButton
extends Node3D

const REST := 0.033
const DOWN := -0.034

var _plunger: MeshInstance3D
var _motion: Tween

static func models() -> Array[Mesh]:
	var base := Build.vol(Vector3i(22, 22, 8))
	base.fill_cylinder(Vector3(11, 11, 0), 10.5, 3, 2, VoxMat.id("metal_dark"))
	base.fill_cylinder(Vector3(11, 11, 3), 10.0, 3, 2, VoxMat.id("metal"))
	base.fill_cylinder(Vector3(11, 11, 6), 9.5, 2, 2, VoxMat.id("metal_white"))
	base.fill_cylinder(Vector3(11, 11, 2), 8.2, 6, 2, 0)
	var cap := Build.vol(Vector3i(22, 22, 6))
	cap.fill_cylinder(Vector3(11, 11, 0), 7.3, 4, 2, VoxMat.id("plastic_red"))
	cap.fill_cylinder(Vector3(11, 11, 4), 7.1, 1, 2, VoxMat.id("brand_red"))
	cap.fill_cylinder(Vector3(11, 11, 5), 6.2, 1, 2, VoxMat.id("brand_red"))
	return [VoxModel.mesh(base, 0.017, Vector3(11, 11, 6)), VoxModel.mesh(cap, 0.017, Vector3(11, 11, 0))]


static func install(parent: Node3D, size: Vector3, normal: Vector3, meshes: Array[Mesh]) -> SchoolButton:
	var button := SchoolButton.new()
	var socket := MeshInstance3D.new()
	socket.mesh = meshes[0]
	button.add_child(socket)
	button._plunger = MeshInstance3D.new()
	button._plunger.mesh = meshes[1]
	button._plunger.position.z = REST
	button.add_child(button._plunger)
	parent.add_child(button)
	button.look_at(button.global_position + normal, Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP, true)
	button.scale = Vector3.ONE * minf(size.x, size.y) / 0.36
	return button


func push() -> void:
	if _motion:
		_motion.kill()
	_motion = create_tween()
	_motion.tween_property(_plunger, "position:z", DOWN, 0.085).set_trans(Tween.TRANS_QUAD)
	_motion.tween_interval(0.075)
	_motion.tween_property(_plunger, "position:z", REST, 0.18).set_trans(Tween.TRANS_SINE)
