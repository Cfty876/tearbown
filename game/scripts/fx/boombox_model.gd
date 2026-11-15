class_name BoomboxModel
extends Node3D

const INSERT_TIME := 0.80
const EMPTY := Color("#324650")
const AMBER := Color("#ffb66a")
const TEAL := Color("#71dacd")
static var _housing: Mesh

var held := false
var _door: Node3D
var _tape: Node3D
var _shell: MeshInstance3D
var _reels: Array[Node3D] = []
var _meters: Array[MeshInstance3D] = []
var _lamp: StandardMaterial3D
var _cones: Array[MeshInstance3D] = []
var _insert_age := INSERT_TIME
var _is_playing := false
var _on_air := false
var _bands := Vector3.ZERO
var _smooth := Vector3.ZERO
var _clock := 0.0
var _color := EMPTY


func _ready() -> void:
	if _housing == null:
		_housing = _build_housing()
	var case := MeshInstance3D.new()
	case.mesh = _housing
	if held:
		case.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(case)
	for x in [-0.154, 0.154]:
		var cone := _piece(self, Vector3(x, -0.007, 0.107), Vector3(0.054, 0.053, 0.012), Color("#52616a"), false)
		_cones.append(cone)
		_piece(cone, Vector3(0.0, 0.0, 0.009), Vector3(0.022, 0.023, 0.008), Color("#17242b"), false)
	_door = Node3D.new()
	add_child(_door)
	_door.position = Vector3(0, -0.051, 0.118)
	for x in [-0.063, 0.063]:
		_piece(_door, Vector3(x, 0.036, 0), Vector3(0.012, 0.071, 0.010), Color("#798f90"), false)
	_piece(_door, Vector3(0, 0.065, 0), Vector3(0.125, 0.012, 0.011), Color("#355c60"), false)
	_tape = Node3D.new()
	add_child(_tape)
	_shell = _piece(_tape, Vector3.ZERO, Vector3(0.112, 0.049, 0.013), _color, true)
	_piece(_tape, Vector3(0, 0.004, 0.008), Vector3(0.081, 0.025, 0.004), Color("#162127"), true)
	for x in [-0.023, 0.023]:
		var reel := Node3D.new()
		_tape.add_child(reel)
		reel.position = Vector3(x, 0.004, 0.012)
		_piece(reel, Vector3.ZERO, Vector3(0.018, 0.006, 0.003), Color("#d9cfb4"), true)
		_piece(reel, Vector3.ZERO, Vector3(0.006, 0.018, 0.003), Color("#d9cfb4"), true)
		_reels.append(reel)
	for i in 7:
		_meters.append(_piece(self, Vector3((i - 3) * 0.016, 0.067, 0.117), Vector3(0.010, 0.010, 0.006), Color("#263639"), true))
	var indicator := _piece(self, Vector3(0.088, 0.068, 0.111), Vector3(0.015, 0.010, 0.008), Color("#253331"), true)
	_lamp = indicator.material_override as StandardMaterial3D
	_apply_insert()


func insert_tape(tint: Color) -> void:
	_color = tint
	_insert_age = 0.0
	_apply_insert()


func set_tape(tint: Color) -> void:
	_color = tint
	_insert_age = INSERT_TIME
	_apply_insert()


func meter(playing: bool, bands: Vector3, on_air := false) -> void:
	if _is_playing != playing or _on_air != on_air:
		_lamp.albedo_color = Color("#7fbaff") if on_air else (Color("#75e2a5") if playing else Color("#253331"))
	_is_playing = playing
	_bands = bands
	_on_air = on_air


func insertion_pose() -> float:
	return smoothstep(0.0, 0.18, _insert_age) * (1.0 - smoothstep(0.59, INSERT_TIME, _insert_age))


func _process(delta: float) -> void:
	if _insert_age < INSERT_TIME:
		_insert_age = minf(INSERT_TIME, _insert_age + delta)
		_apply_insert()
	if not is_visible_in_tree() or (not _is_playing and _smooth.length_squared() < 0.0002):
		return
	_clock += delta
	_smooth = _smooth.lerp(_bands if _is_playing else Vector3.ZERO, 1.0 - exp(-18.0 * delta))
	if _is_playing:
		_reels[0].rotation.z += delta * 7.0
		_reels[1].rotation.z -= delta * 9.0
	for i in _meters.size():
		var intensity := _smooth[mini(i / 3, 2)] * 0.85 + _smooth.x * 0.15
		var enabled := intensity > 0.09 + float(i % 3) * 0.23
		var material := _meters[i].material_override as StandardMaterial3D
		material.albedo_color = (AMBER if i >= 5 else TEAL) if enabled else Color("#263639")
	for cone in _cones:
		cone.position.z = 0.107 + _smooth.x * sin(_clock * 76.0) * 0.009


func _apply_insert() -> void:
	if _door == null:
		return
	var hatch := smoothstep(0.0, 0.21, _insert_age) * (1.0 - smoothstep(0.58, INSERT_TIME, _insert_age))
	var slot := smoothstep(0.21, 0.60, _insert_age)
	_door.rotation.x = hatch * 1.03
	_tape.position = Vector3(0.0, lerpf(-0.095, -0.016, slot), lerpf(0.258, 0.109, slot))
	_tape.rotation.x = (1.0 - slot) * 0.65
	(_shell.material_override as StandardMaterial3D).albedo_color = _color
	_tape.visible = _color != EMPTY and (_insert_age >= 0.12)


func _piece(parent: Node3D, at: Vector3, size: Vector3, tint: Color, lit: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	if lit:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part.material_override = material
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


static func _build_housing() -> Mesh:
	var v := Build.vol(Vector3i(26, 16, 11))
	var at := SchoolLevel.box
	at.call(v, Vector3i(0, 1, 0), Vector3i(26, 11, 10), "metal_dark")
	at.call(v, Vector3i(1, 11, 0), Vector3i(24, 1, 10), "metal_teal")
	for x in [2, 20]:
		at.call(v, Vector3i(x, 0, 1), Vector3i(4, 1, 9), "rubber")
	for x in [5, 21]:
		v.fill_cylinder(Vector3(x, 6, 9), 4.5, 2, 2, VoxMat.id("metal"))
		v.fill_cylinder(Vector3(x, 6, 10), 3.5, 1, 2, VoxMat.id("rubber"))
	at.call(v, Vector3i(9, 3, 8), Vector3i(8, 5, 2), "metal_teal")
	at.call(v, Vector3i(9, 9, 10), Vector3i(8, 1, 1), "metal_dark")
	for x in [9, 16]:
		at.call(v, Vector3i(x, 12, 4), Vector3i(1, 3, 2), "metal")
	at.call(v, Vector3i(9, 15, 4), Vector3i(8, 1, 2), "rubber")
	at.call(v, Vector3i(4, 12, 2), Vector3i(3, 1, 2), "metal_yellow")
	at.call(v, Vector3i(19, 12, 2), Vector3i(3, 1, 2), "metal_red")
	var model := VoxModel.instance(v, 0.019, Vector3(13, 6, 5))
	var mesh := model.mesh
	model.free()
	return mesh
