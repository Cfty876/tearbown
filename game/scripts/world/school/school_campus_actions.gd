class_name SchoolCampusActions
extends Node3D

const COOLDOWN := 26.0
const KEYS := ["yard_gate", "yard_drill", "yard_shutter", "garden_screen", "yard_decoy"]

var controller: SchoolSecrets
var _blocks := {}
var _homes := {}
var _open := {}
var _orientations := {}
var _beacons: Array[Node3D] = []
var _drill_until := 0.0
var _next_drill := 0.0
var _next_decoy := 0.0
var _decoy_until := 0.0
var _decoy_pulse := 0.0


func build() -> void:
	var gate := SchoolCampus.GATE
	var leaf := Build.vol(Vector3i(38, 24, 3))
	for x in range(0, 38, 5):
		SchoolLevel.box(leaf, Vector3i(x, 0, 1), Vector3i(2, 24, 2), "metal_dark")
	for y in [2, 21]:
		SchoolLevel.box(leaf, Vector3i(0, y, 0), Vector3i(38, 3, 3), "metal_teal")
	for x in range(1, 36, 5):
		SchoolLevel.box(leaf, Vector3i(x, 6, 0), Vector3i(3, 2, 3), "metal_yellow")
	_build_mover("yard_gate", leaf, gate, "Ворота полигона")
	_posts(gate, 3.8, 5.5, 0.82)
	_rail(Vector3(15.0, 2.0, 65.02), 110, "Ограда полигона")
	_rail(Vector3(27.6, 2.0, 65.02), 46, "Ограда полигона")
	_station("yard_gate", gate + Vector3(-2.78, 0, -0.83), "Открыть или закрыть ворота", Vector3.FORWARD)
	_station("yard_gate_inside", gate + Vector3(2.8, 0, 0.77), "Открыть или закрыть ворота", Vector3.BACK, "yard_gate")

	var shutter := SchoolCampus.SHUTTER
	var shutter_leaf := Build.vol(Vector3i(32, 23, 4))
	for y in range(0, 23, 3):
		SchoolLevel.box(shutter_leaf, Vector3i(0, y, 0), Vector3i(32, 3, 4), "metal_dark")
		SchoolLevel.box(shutter_leaf, Vector3i(1, y + 1, 0), Vector3i(30, 1, 1), "metal")
	for x in range(0, 32, 4):
		SchoolLevel.box(shutter_leaf, Vector3i(x, 0, 0), Vector3i(2, 3, 4), "metal_yellow")
	var shutter_yaw := PI * 0.5
	var facing := Basis(Vector3.UP, shutter_yaw)
	_build_mover("yard_shutter", shutter_leaf, shutter, "Защитная заслонка", shutter_yaw)
	_posts(shutter, 3.2, 5.3, 0.88, shutter_yaw)
	_rail(Vector3(shutter.x, 2.0, 24.25), 35, "Ограда техдвора", shutter_yaw)
	_rail(Vector3(shutter.x, 2.0, 30.8), 12, "Ограда техдвора", shutter_yaw)
	_station("yard_shutter", shutter + facing * Vector3(-2.47, 0, -0.72), "Поднять или опустить заслонку", facing * Vector3.FORWARD)
	_station("yard_shutter_inside", shutter + facing * Vector3(2.47, 0, 0.73), "Поднять или опустить заслонку", facing * Vector3.BACK, "yard_shutter")


	_station("yard_drill", SchoolCampus.DRILL, "Включить дым и сирену на полигоне", Vector3.FORWARD)
	for i in 2:
		var at := Vector3(20.5 + 7.5 * i, 2.0, 74.0)
		var beacon := Build.vol(Vector3i(12, 32, 12))
		SchoolLevel.box(beacon, Vector3i(4, 0, 4), Vector3i(4, 28, 4), "metal_teal")
		SchoolLevel.box(beacon, Vector3i(1, 27, 1), Vector3i(10, 3, 10), "metal_dark")
		DistrictSecretProps.model(self, beacon, at, true, 0, "Сигнальная стойка")
		var light := MeshInstance3D.new()
		var dome := CylinderMesh.new()
		dome.top_radius = 0.26
		dome.bottom_radius = 0.35
		dome.height = 0.23
		dome.radial_segments = 10
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#ff4a23")
		material.emission_enabled = true
		material.emission = Color("#ff4622")
		material.emission_energy_multiplier = 3.0
		dome.material = material
		light.mesh = dome
		light.position = at + Vector3.UP * 3.1
		add_child(light)
		_beacons.append(light)

	_garden()
	reset()


func _garden() -> void:
	var at := SchoolCampus.GARDEN_GATE
	var screen := Build.vol(Vector3i(32, 23, 4))
	SchoolLevel.box(screen, Vector3i.ZERO, Vector3i(32, 23, 4), "wood_dark")
	for y in range(1, 23, 3):
		SchoolLevel.box(screen, Vector3i(1, y, 0), Vector3i(30, 2, 1), "wood_light")
	for x in [1, 29]:
		SchoolLevel.box(screen, Vector3i(x, 0, 3), Vector3i(2, 23, 1), "metal_teal")
	_build_mover("garden_screen", screen, at, "Садовая ширма")
	_posts(at, 3.2, 5.3, 0.6)
	_station("garden_screen", at + Vector3(-2.45, 0, -0.9), "Поднять или закрыть ширму сада", Vector3.FORWARD)
	_station("garden_screen_inside", at + Vector3(2.45, 0, 0.9), "Поднять или закрыть ширму сада", Vector3.BACK, "garden_screen")
	_station("yard_decoy", SchoolCampus.DECOY, "Звонок-приманка у теплицы", Vector3.BACK)
	var bell := Build.vol(Vector3i(8, 31, 8))
	SchoolLevel.box(bell, Vector3i(3, 0, 3), Vector3i(2, 27, 2), "metal_teal")
	bell.fill_cylinder(Vector3(4, 27, 4), 3.8, 3, 1, VoxMat.id("metal_red"))
	bell.fill_cylinder(Vector3(4, 30, 4), 2.5, 1, 1, VoxMat.id("metal"))
	DistrictSecretProps.model(self, bell, SchoolCampus.DECOY + Vector3.RIGHT * 0.85, true, 0, "Садовый звонок")


func _build_mover(key: String, volume: VoxelVolume, at: Vector3, title: String, yaw := 0.0) -> void:
	_blocks[key] = controller._mover(volume, at, Vector3(volume.get_size()) * 0.1, title)
	_blocks[key].rotation.y = yaw
	_orientations[key] = Basis(Vector3.UP, yaw).inverse()
	_homes[key] = at
	_open[key] = false


func _station(key: String, at: Vector3, title: String, normal: Vector3, shared := "") -> void:
	var box := Build.vol(Vector3i(6, 15, 5))
	SchoolLevel.box(box, Vector3i(1, 0, 2), Vector3i(4, 12, 2), "metal_teal")
	SchoolLevel.box(box, Vector3i(0, 10, 0), Vector3i(6, 5, 5), "metal_dark")
	SchoolLevel.box(box, Vector3i(0, 10, 0), Vector3i(6, 1, 5), "metal_yellow")
	DistrictSecretProps.model(self, box, at, true, 0, "Пульт управления")
	var control := at + Vector3.UP * 1.25 + normal * 0.29
	controller.add_control(key, control, Vector3(0.36, 0.36, 0.23), title, normal)
	if not shared.is_empty():
		set_meta(key, shared)


func _posts(at: Vector3, width: float, height: float, span: float, yaw := 0.0) -> void:
	var w := roundi(width * 10.0) + 10
	var h := roundi(height * 10.0)
	var d := roundi(span * 10.0)
	var v := Build.vol(Vector3i(w, h, d))
	for x in [0, w - 5]:
		SchoolLevel.box(v, Vector3i(x, 0, 1), Vector3i(5, h, d - 2), "metal_dark")
		SchoolLevel.box(v, Vector3i(x, 0, 0), Vector3i(5, 8, d), "metal_yellow")
	SchoolLevel.box(v, Vector3i(0, h - 5, 1), Vector3i(w, 5, d - 2), "metal_teal")
	DistrictSecretProps.model(self, v, at, true, yaw, "Направляющие")


func _rail(at: Vector3, cells: int, title: String, yaw := 0.0) -> void:
	var v := Build.vol(Vector3i(cells, 20, 3))
	for x in range(0, cells, 4):
		SchoolLevel.box(v, Vector3i(x, 0, 0), Vector3i(1, 20, 3), "metal_teal")
	for y in [0, 17]:
		SchoolLevel.box(v, Vector3i(0, y, 0), Vector3i(cells, 2, 3), "metal_dark")
	DistrictSecretProps.model(self, v, at, true, yaw, title)


func handles(key: String) -> bool:
	return key in KEYS or has_meta(key)


func can_use(key: String, actor: Vector3, other: Vector3) -> bool:
	var action := str(get_meta(key, key))
	if action == "yard_drill":
		return controller._now() >= _next_drill
	if action == "yard_decoy":
		return controller._now() >= _next_decoy
	if not bool(_open[action]):
		return true
	var home: Vector3 = _homes[action]
	var half_width := 2.15 if action == "yard_gate" else 1.9
	for at: Vector3 in [actor, other]:
		if not at.is_finite():
			continue
		var local: Vector3 = _orientations[action] * (at - home)
		if absf(local.x) < half_width and absf(local.z) < 1.10 and local.y > -0.4 and local.y < 2.7:
			return false
	return true


func apply(key: String) -> void:
	var action := str(get_meta(key, key))
	if action == "yard_drill":
		_drill_until = controller._now() + 8.0
		_next_drill = controller._now() + COOLDOWN
		controller.traps._cloud(Vector3(24, 3.05, 69.1), 4.4, 8.0, Color("#c6c5ad"), "yard_drill")
		controller.world.sfx.play_horn( Vector3(23.6, 4.6, 73.9))
		controller.world.sfx.loop("school_yard_drill", "school_yard_siren", Vector3(23.6, 4.6, 73.9), true, -10.0)
		return
	if action == "yard_decoy":
		_next_decoy = controller._now() + 18.0
		_decoy_until = controller._now() + 4.0
		_decoy_pulse = 0.0
		return
	_open[action] = not bool(_open[action])
	var dest: Vector3 = _homes[action]
	if _open[action]:
		dest.y += 2.52
	controller._animate(action, _blocks[action], dest, 0.82)
	controller.world.sfx.play("hide_slide", dest, -5.0, 0.73)


func tick(time: float) -> void:
	if time < _decoy_until and time >= _decoy_pulse:
		_decoy_pulse = time + 0.55
		controller.world.sfx.play("metal", SchoolCampus.DECOY + Vector3.UP * 2.8, 5.0, 1.3)
	if _drill_until > 0.0 and time >= _drill_until:
		_drill_until = 0.0
		controller.world.sfx.loop("school_yard_drill", "school_yard_siren", Vector3.ZERO, false)
	for lamp in _beacons:
		lamp.visible = _drill_until > 0.0 and posmod(floori(time * 5.0), 2) == 0


func reset() -> void:
	for key: String in _blocks:
		_blocks[key].position = _homes[key]
		_open[key] = false
	_drill_until = 0.0
	_next_drill = 0.0
	_next_decoy = 0.0
	_decoy_until = 0.0
	_decoy_pulse = 0.0
	controller.world.sfx.loop("school_yard_drill", "school_yard_siren", Vector3.ZERO, false)
	tick(0.0)
