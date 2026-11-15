class_name SchoolNpcAvatar
extends Node3D

const CELL := 0.037
const FACE_CELL := 0.019
const HIP := 0.762
const THIGH := 0.365
const SHIN := 0.36
const ANKLE := 0.056
const CHILD_COLORS := ["metal_blue", "curtain_red", "curtain_green", "plaster_yellow", "metal_teal",
	"wood_dark", "plaster_blue", "metal_green", "wood", "curtain_beige"]
const HAIR := ["wood_dark", "tank_black", "wood_light", "wood", "panel_grey"]
const ROLE_COLORS := {"cook": "pvc", "guard": "vest_dark", "mechanic": "metal_blue"}
const PROPS := {"cook": "metal", "wipe": "curtain_beige", "eat": "wood_light", "sweep": "wood",
	"board": "plastic_white", "study": "plaster_yellow"}
static var _outfits := {}
static var _hand_meshes := {}

var head: MeshInstance3D
var _torso: MeshInstance3D
var _arms: Array[MeshInstance3D] = []
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _hand: MeshInstance3D
var _time := 0.0
var _step := 0.0
var _action := ""
var _child := false
var _seat_blend := 0.0
var _seat_height := 0.51
var _manner := 0.0


func build(role: String, variant: int) -> void:
	_child = role == "student"
	_manner = float((variant * 7 + 3) % 19) / 18.0
	var key := "%s:%d" % [role, variant]
	if not _outfits.has(key):
		_outfits[key] = _make_outfit(role, variant)
	var meshes: Array = _outfits[key]
	_torso = _piece(meshes[0], Vector3(0, 0.73, 0))
	head = _piece(meshes[1], Vector3(0, 1.53, 0))
	for side in [-1.0, 1.0]:
		_arms.append(_piece(meshes[2], Vector3(side * 0.249, 1.29, 0)))
		var hip := _piece(meshes[3], Vector3(side * 0.10, HIP, 0))
		var knee := _piece(meshes[4], Vector3(0, -THIGH, 0), hip)
		var ankle := _piece(meshes[5], Vector3(0, -SHIN, 0), knee)
		_hips.append(hip)
		_knees.append(knee)
		_ankles.append(ankle)
	_hand = MeshInstance3D.new()
	_hand.position = Vector3(0, -0.41, -0.067)
	_hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arms[1].add_child(_hand)
	if _child:
		scale = Vector3(0.83, 0.79, 0.83)


func animate(action: String, speed: float, seat: float, glance: float, flinch: float, delta: float) -> void:
	_time += delta * lerpf(0.83, 1.18, _manner)
	_step += delta * speed * 3.7
	var walking := clampf(speed * 0.45, 0.0, 1.0)
	var stride := sin(_step) * walking
	var ease := 1.0 - exp(-11.0 * delta)
	if seat > 0.0:
		_seat_height = seat
	_seat_blend = lerpf(_seat_blend, 1.0 if seat > 0.0 else 0.0, ease)
	var seated_y := _seat_height / scale.y + 0.033
	var hip_y := lerpf(HIP, seated_y, _seat_blend)
	var hips_back := 0.025 * _seat_blend
	_torso.position = Vector3(0, hip_y, hips_back)
	var lean := (0.10 if action in ["study", "eat", "monitor"] else 0.04) * _seat_blend
	_torso.rotation.x = -lean
	head.position = Vector3(0, hip_y + 0.80, hips_back - lean * 0.72)
	head.rotation.y = lerp_angle(head.rotation.y, glance, ease)
	head.rotation.x = sin(_time * 2.3) * 0.024 + flinch * 0.24 - lean * 0.78
	_torso.rotation.z = sin(_step) * walking * 0.07 + flinch * 0.10
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_pose_leg(i, hip_y, hips_back, side * stride)
		_arms[i].position.y = hip_y + 0.56
		_arms[i].position.z = hips_back - lean * 0.55
		var rest_angle := -0.55 if action in ["break", "rest", "seat_idle"] else 1.08
		var arm_angle := lerpf(-0.10 - side * stride * 0.58, rest_angle, _seat_blend)
		var arm_roll := side * 0.045
		if i == 1:
			match action:
				"cook": arm_angle = -1.72 + sin(_time * 4.4) * 0.21
				"wipe": arm_angle = -1.02 + sin(_time * 5.6) * 0.24
				"board":
					arm_angle = -2.40 + sin(_time * 4.0) * 0.29
					arm_roll = 0.17 + sin(_time * 3.1) * 0.18
				"eat": arm_angle = 1.20 + maxf(0.0, sin(_time * 1.9)) * 1.08
				"sweep": arm_angle = -0.82 + sin(_time * 4.7) * 0.25
				"study": arm_angle = 1.27 + sin(_time * 6.8) * 0.061
				"monitor": arm_angle = 1.10 + sin(_time * 2.5) * 0.08
				"inspect": arm_angle = 1.62 + sin(_time * 2.4) * 0.15
			if action in ["cook", "wipe", "board", "sweep"]:
				arm_angle = -arm_angle
		if action in ["break", "rest", "seat_idle"]:
			arm_angle = 0.23 + _manner * 0.36 + sin(_time * 1.7 + float(i)) * 0.025
		_arms[i].rotation.x = lerpf(_arms[i].rotation.x, arm_angle + flinch * -0.35, ease)
		_arms[i].rotation.z = lerpf(_arms[i].rotation.z, arm_roll, ease)
	if action != _action:
		_action = action
		_hand.mesh = _prop(action)


func _pose_leg(i: int, hip_y: float, hips_back: float, stride: float) -> void:
	var hip := _hips[i]
	var knee := _knees[i]
	var ankle := _ankles[i]
	var lateral := -1.0 if i == 0 else 1.0
	hip.position = Vector3(lateral * (0.10 + _seat_blend * 0.015), hip_y, hips_back)
	var reach := lerpf(0.36, 0.56, clampf((0.51 - _seat_height) * 2.85, 0.0, 1.0))
	if _child and _seat_height >= 0.4:
		reach -= 0.065
	reach += (_manner - 0.5) * 0.06 * lateral
	var vertical := maxf(0.05, hip_y - ANKLE)
	var distance := clampf(Vector2(reach, vertical).length(), 0.08, THIGH + SHIN - 0.001)
	var hip_angle := atan2(reach, vertical) + acos(clampf((distance * distance + THIGH * THIGH - SHIN * SHIN) / (2.0 * distance * THIGH), -1.0, 1.0))
	var knee_angle := -acos(clampf((distance * distance - THIGH * THIGH - SHIN * SHIN) / (2.0 * THIGH * SHIN), -1.0, 1.0))
	hip.rotation.x = lerpf(stride * 0.67, hip_angle, _seat_blend)
	knee.rotation.x = lerpf(-maxf(0.0, -stride) * 0.42, knee_angle, _seat_blend)
	ankle.rotation.x = -(hip.rotation.x + knee.rotation.x) * _seat_blend


func _piece(mesh: Mesh, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.visibility_range_end = 52.0
	(parent if parent else self).add_child(part)
	return part


static func _make_outfit(role: String, variant: int) -> Array:
	var base: String = ROLE_COLORS.get(role, CHILD_COLORS[posmod(variant, CHILD_COLORS.size())])
	var pants := "wood_dark" if role == "teacher" else "vest_dark"
	var skin := "skin_dark" if variant % 7 == 4 or variant % 11 == 6 else "skin"
	var hair: String = HAIR[variant % HAIR.size()]
	var shirt := Build.vol(Vector3i(12, 16, 9))
	SchoolLevel.box(shirt, Vector3i.ZERO, shirt.get_size(), base)
	SchoolLevel.box(shirt, Vector3i(0, 0, 0), Vector3i(12, 2, 9), pants)
	var collar := "plastic_white" if role in ["teacher", "student"] else "metal_teal"
	SchoolLevel.box(shirt, Vector3i(3, 13, 0), Vector3i(6, 2, 1), collar)
	match role:
		"cook":
			SchoolLevel.box(shirt, Vector3i(2, 2, 0), Vector3i(8, 11, 1), "curtain_beige")
			SchoolLevel.box(shirt, Vector3i(4, 4, 0), Vector3i(4, 3, 1), "metal_teal")
		"guard":
			SchoolLevel.box(shirt, Vector3i(1, 11, 0), Vector3i(3, 2, 1), "metal_yellow")
			SchoolLevel.box(shirt, Vector3i(8, 8, 0), Vector3i(2, 5, 1), "metal_dark")
		"mechanic":
			for x in [2, 9]:
				SchoolLevel.box(shirt, Vector3i(x, 7, 0), Vector3i(1, 9, 1), "metal_teal")
			SchoolLevel.box(shirt, Vector3i(3, 4, 0), Vector3i(6, 4, 1), "metal_dark")
		"teacher":
			SchoolLevel.box(shirt, Vector3i(5, 4, 0), Vector3i(2, 9, 1), "wood_dark")
			SchoolLevel.box(shirt, Vector3i(2, 9, 0), Vector3i(2, 2, 1), "pvc")
		"student":
			for y in [4, 8, 11]:
				SchoolLevel.box(shirt, Vector3i(2, y, 0), Vector3i(8, 1, 1), collar if variant % 2 == 0 else "wood_dark")
			if variant % 5 == 2:
				SchoolLevel.box(shirt, Vector3i(2, 3, 7), Vector3i(8, 10, 2), "metal_teal")
	var face := _face(role, variant, skin, hair)
	var sleeve := Build.vol(Vector3i(4, 14, 6))
	SchoolLevel.box(sleeve, Vector3i.ZERO, sleeve.get_size(), base)
	SchoolLevel.box(sleeve, Vector3i.ZERO, Vector3i(4, 3, 6), skin)
	SchoolLevel.box(sleeve, Vector3i(0, 3, 0), Vector3i(4, 1, 6), collar)
	var thigh := Build.vol(Vector3i(5, 11, 6))
	SchoolLevel.box(thigh, Vector3i.ZERO, Vector3i(5, 11, 6), pants)
	SchoolLevel.box(thigh, Vector3i(4, 1, 1), Vector3i(1, 9, 1), "metal_dark")
	var shin := Build.vol(Vector3i(5, 10, 5))
	SchoolLevel.box(shin, Vector3i.ZERO, Vector3i(5, 10, 5), pants)
	SchoolLevel.box(shin, Vector3i(0, 0, 0), Vector3i(5, 2, 5), "metal_dark")
	var shoe := Build.vol(Vector3i(5, 3, 9))
	SchoolLevel.box(shoe, Vector3i.ZERO, Vector3i(5, 1, 9), "tank_black")
	SchoolLevel.box(shoe, Vector3i(0, 1, 1), Vector3i(5, 2, 8), "boot")
	return [VoxModel.mesh(shirt, CELL, Vector3(6, 0, 4.5)),
		VoxModel.mesh(face, FACE_CELL, Vector3(13, 11, 11)),
		VoxModel.mesh(sleeve, CELL, Vector3(2, 13, 3)),
		VoxModel.mesh(thigh, CELL, Vector3(2.5, 10, 3)),
		VoxModel.mesh(shin, CELL, Vector3(2.5, 10, 2.5)),
		VoxModel.mesh(shoe, CELL, Vector3(2.5, 1, 6))]


static func _face(role: String, variant: int, skin: String, hair: String) -> VoxelVolume:
	var v := Build.vol(Vector3i(26, 32, 22))
	var b := SchoolLevel.box
	var shade := "npc_face_shadow_dark" if skin == "skin_dark" else "npc_face_shadow"
	var lips := "npc_face_lips_dark" if skin == "skin_dark" else "npc_face_lips"
	b.call(v, Vector3i(4, 2, 3), Vector3i(18, 20, 16), skin)
	b.call(v, Vector3i(3, 6, 5), Vector3i(20, 15, 13), skin)
	b.call(v, Vector3i(6, 0, 5), Vector3i(14, 4, 12), skin)
	b.call(v, Vector3i(2, 8, 9), Vector3i(3, 7, 5), skin)
	b.call(v, Vector3i(21, 8, 9), Vector3i(3, 7, 5), skin)
	b.call(v, Vector3i(2, 10, 10), Vector3i(1, 3, 3), shade)
	b.call(v, Vector3i(23, 10, 10), Vector3i(1, 3, 3), shade)
	for x in [5, 17]:
		b.call(v, Vector3i(x, 7, 2), Vector3i(4, 2, 1), shade)
		b.call(v, Vector3i(x, 11, 2), Vector3i(5, 3, 1), "plastic_white")
		var iris: String = ["npc_iris_hazel", "metal_teal", "metal_blue", "wood_dark"][variant % 4]
		b.call(v, Vector3i(x + 1, 11, 1), Vector3i(3, 3, 1), iris)
		b.call(v, Vector3i(x + 2, 12, 0), Vector3i(1, 2, 1), "tank_black")
		b.call(v, Vector3i(x + 1, 13, 0), Vector3i(1, 1, 1), "plastic_white")
		b.call(v, Vector3i(x - 1, 15 + (variant + x) % 2, 2), Vector3i(6, 1, 1), hair)
	b.call(v, Vector3i(11, 8, 2), Vector3i(4, 4, 1), skin)
	b.call(v, Vector3i(12, 8, 1), Vector3i(2, 2, 1), skin)
	b.call(v, Vector3i(10, 5, 2), Vector3i(6, 1, 1), lips)
	b.call(v, Vector3i(11, 4, 2), Vector3i(4, 1, 1), shade)
	b.call(v, Vector3i(4, 19, 2), Vector3i(18, 6, 17), hair)
	b.call(v, Vector3i(6, 25, 4), Vector3i(14, 1 + variant % 3, 13), hair)
	b.call(v, Vector3i(4, 13 + variant % 3, 16), Vector3i(18, 9, 4), hair)
	var fringe := 3 + (variant * 3) % 8
	b.call(v, Vector3i(fringe, 16, 2), Vector3i(7, 4, 2), hair)
	b.call(v, Vector3i(5 + variant % 7, 24, 3), Vector3i(8, 2, 3), "wood" if hair == "wood_dark" else hair)
	if role == "teacher" and variant % 2 == 0:
		for x in [4, 16]:
			b.call(v, Vector3i(x, 10, 1), Vector3i(7, 1, 1), "metal_dark")
			b.call(v, Vector3i(x, 14, 1), Vector3i(7, 1, 1), "metal_dark")
			for edge in [x, x + 6]:
				b.call(v, Vector3i(edge, 11, 1), Vector3i(1, 3, 1), "metal_dark")
		b.call(v, Vector3i(11, 13, 1), Vector3i(5, 1, 1), "metal_dark")
	if role in ["cook", "guard", "mechanic"]:
		var cap := "pvc" if role == "cook" else ("vest_dark" if role == "guard" else "metal_blue")
		b.call(v, Vector3i(3, 20, 1), Vector3i(20, 5, 19), cap)
		b.call(v, Vector3i(5, 25, 3), Vector3i(16, 6 if role == "cook" else 2, 15), cap)
		if role != "cook":
			b.call(v, Vector3i(5, 19, 0), Vector3i(16, 2, 4), "metal_dark")
			b.call(v, Vector3i(11, 22, 0), Vector3i(4, 3, 1), "metal_yellow")
		if role == "guard" and variant > 1:
			b.call(v, Vector3i(8, 5, 2), Vector3i(10, 2, 1), hair)
	return v


static func _prop(action: String) -> Mesh:
	if not PROPS.has(action):
		return null
	if not _hand_meshes.has(action):
		var size := Vector3i(4, 4, 4)
		var v := Build.vol(Vector3i(6, 24, 7))
		match action:
			"sweep":
				SchoolLevel.box(v, Vector3i(2, 1, 2), Vector3i(1, 22, 1), "wood")
				SchoolLevel.box(v, Vector3i(0, 0, 1), Vector3i(6, 4, 3), "curtain_beige")
			"cook":
				SchoolLevel.box(v, Vector3i(2, 0, 2), Vector3i(1, 12, 1), "metal")
				SchoolLevel.box(v, Vector3i(1, 11, 1), Vector3i(3, 4, 3), "metal_dark")
			_:
				SchoolLevel.box(v, Vector3i(0, 0, 1), size, PROPS[action])
		_hand_meshes[action] = VoxModel.mesh(v, 0.018, Vector3(2, 11 if action == "sweep" else 2, 2))
	return _hand_meshes[action]
