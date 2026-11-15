class_name DistrictSecrets
extends Node3D

signal action_requested(key: String, shot: bool)
signal weapon_hit_requested(key: String, source: Player)

const SHOTGUN_BUTTON := "shotgun_button/"

const MASK := Layers.SOLID | Layers.SECRET
const VIEW_COUNT := 10
const CAMERA_RECOVERY := 15.0
const ALARM_COOLDOWN := 18.0
const DOGHOUSE_BASE := Vector3(DistrictSecretMap.DOGHOUSE.x, 2.04, DistrictSecretMap.DOGHOUSE.y)

var player: Player
var world: VoxelWorld
var level: DistrictLevel
var can_shoot := true
var local_side := 0
var targets := {}
var rugs: Array[Dictionary] = []
var _paths := {}
var _lilac_meshes: Array[MeshInstance3D] = []
var _cupboard: AnimatableBody3D
var _car: VoxelObject
var _lift_deck: AnimatableBody3D
var _trap: AnimatableBody3D
var _cable: MeshInstance3D
var _camera_points: Array[Vector3] = []
var _camera_views: Array[Vector3] = []
var _cctv: DistrictCCTV
var _trace: MeshInstance3D
var _trace_at := -1.0
var _tweens := {}
var _travel: Tween
var _cross_open := false
var _lowered := false
var _lift_broken := false
var _lift_hits := 0
var _dog_open := false
var _zip_broken := false
var _booth_until := [0.0, 0.0]
var _alarm_until := 0.0
var _next_shot := 0.0
var _disabled: Array[float] = []
var _seed := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_booth_until.resize(RoomRules.SIDES)
	_booth_until.fill(0.0)
	DistrictSecretMap.build(world)
	_setup_rooms()
	_setup_routes()
	_setup_props()
	_setup_cameras()
	world.sfx.install_gate_alarm(DistrictSecretProps.GATE_SIREN)
	_seed = -1
	reset_round(1964)
	world.geometry_changed.connect(_mark_destruction)


func _now() -> float:
	return world.gadgets.scene_time() if is_instance_valid(world.gadgets) else Time.get_ticks_msec() * 0.001


func _setup_rooms() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying float local_eye_z;
varying vec3 voxel_pos;
void vertex() {
	local_eye_z = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).z;
	voxel_pos = VERTEX * 10.0;
}
void fragment() {
	if (local_eye_z < 0.0) { discard; }
	float weave = 0.85 + 0.15 * sin(voxel_pos.x * 26.0) * sin(voxel_pos.y * 24.0);
	ALBEDO = COLOR.rgb * weave;
	ROUGHNESS = 0.97;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	for room in level.secret_rooms:
		var building := room.building as VoxelObject
		var index := rugs.size()
		var rug := VoxelObject.new().setup(DistrictSecretProps.rug(), true)
		rug.static_layer = Layers.SECRET
		rug.voxel_material_override = material
		rug.retain_when_empty = true
		rug.label = "false_rug"
		rug.rotation.y = building.rotation.y + PI
		var center := building.to_global(Vector3(room.rug) * 0.1)
		rug.position = center - rug.basis * Vector3(0.95, 0, 0)
		add_child(rug)
		var shield_key := "shield/%d" % index
		var escape_key := "escape/%d" % index
		_button(shield_key, building.to_global(Vector3(room.shield) * 0.1),
			Vector3(0.23, 0.32, 0.26), "metal_blue", "включить щит на 5 секунд")
		_button(escape_key, building.to_global(Vector3(room.escape) * 0.1),
			Vector3(0.23, 0.32, 0.26), "curtain_green", "уйти через гараж")
		var warning := OmniLight3D.new()
		warning.position = center + building.global_basis * Vector3(0, 1.9, 0.55)
		warning.light_color = Color("#74ccfb")
		warning.light_energy = 1.3
		warning.omni_range = 2.8
		warning.hide()
		add_child(warning)
		rugs.append({"body": rug, "building": building, "at": center, "until": 0.0,
			"next": 0.0, "broken": false, "light": warning})


func _setup_routes() -> void:
	DistrictSecretProps.garage(self)
	var cross := level.pharmacy_cross
	_button("cross", cross, Vector3(0.28, 0.28, 0.15), "brand_green", "нажать на центральный светодиод")

	var roof := level.roof_route
	_ladder("roof_climb", roof, "лестница на крышу")
	var start := roof[-1] + Vector3(1.1, 1.8, -0.3)
	var end := Vector3(12.0, 7.0, -82.0)
	_cable = DistrictSecretProps.beam(self, start, end, 0.029, Color("#202622"))
	for peg in [[start, roof[-1].y], [end, 5.7]]:
		var base := Vector3(peg[0])
		DistrictSecretProps.beam(self, Vector3(base.x, peg[1], base.z), base, 0.065, Color("#707b72"))
	for height: float in [0.33, 0.73]:
		var arm := start + Vector3.UP * height
		DistrictSecretProps.beam(self, arm - Vector3.RIGHT * 0.68, arm + Vector3.RIGHT * 0.68, 0.026, Color("#606c69"))
	DistrictSecretProps.beam(self, start, start + Vector3.UP * 0.91, 0.043, Color("#707b72"))
	_button("zip_start", start, Vector3(0.36, 0.32, 0.34), "metal_yellow", "съехать по кабелю")
	_button("zip_end", end, Vector3(0.36, 0.32, 0.34), "metal_yellow", "перерезать крепление")
	_paths["zip_start"] = PackedVector3Array([start - Vector3.UP * 1.5, end - Vector3.UP * 1.25])
	_shaft("pharmacy_hatch", DistrictSecretMap.PHARMACY, Vector3(1.34, 0, 0))
	_shaft("shop_hatch", DistrictSecretMap.SHOP, Vector3(1.35, 0, 0))
	_shaft("garage_hatch", DistrictSecretMap.GARAGE, Vector3(1.48, 0, 0))
	_shaft("cellar_hatch", DistrictSecretMap.DOGHOUSE, Vector3(0, 0, 1.40))

	var rack := DistrictSecretProps.cabinet()
	_cupboard = _mover(rack, Vector3(-79, 2.2, 20), Vector3(2.0, 2.2, 2.0), "medicine_rack")
	var deck := Build.vol(Vector3i(20, 2, 20))
	DistrictSecretProps.box(deck, Vector3i.ZERO, Vector3i(20, 2, 20), "metal_dark")
	_lift_deck = _mover(deck, Vector3(12, 3.50, -83), Vector3(2.0, 0.2, 2.0), "lift_deck")
	var arms := Build.vol(Vector3i(54, 4, 22))
	for x in [0, 35]:
		for z in [2, 15]:
			DistrictSecretProps.box(arms, Vector3i(x, 0, z), Vector3i(19, 2, 4), "metal_dark")
			DistrictSecretProps.box(arms, Vector3i(x if x == 0 else 49, 2, z), Vector3i(5, 2, 4), "metal_yellow")
	DistrictSecretProps.model(_lift_deck, arms, Vector3.ZERO)
	DistrictSecretMap._light(world, Vector3(10.4, 5.19, -82.2), Color("#f1d5a7"))
	DistrictSecretMap._light(world, Vector3(13.6, 5.19, -82.2), Color("#f1d5a7"))
	_car = VoxelObject.new().setup(DistrictSecretProps.garage_car(), true)
	_car.follow_static_transform = true
	_car.retain_when_empty = true
	_car.label = "lift_car"
	_car.rotation.y = PI * 0.5
	_car.position = _car_at(false)
	add_child(_car)
	_button("lower", Vector3(11.25, -1.03, -82.45), Vector3(0.25, 0.33, 0.25),
		"metal_yellow", "опустить автомобиль")
	_button("raise", Vector3(14.18, 3.15, -83.75), Vector3(0.27, 0.36, 0.25),
		"metal_yellow", "поднять автомобиль аварийным приводом")
	var dog := DOGHOUSE_BASE
	DistrictSecretProps.model(self, DistrictSecretProps.doghouse(), dog, true, 0.0, "doghouse")
	var boards := Build.vol(Vector3i(18, 1, 20))
	DistrictSecretProps.box(boards, Vector3i.ZERO, Vector3i(18, 1, 20), "wood_dark")
	_trap = _mover(boards, dog - Vector3.UP * 0.03, Vector3(1.8, 0.1, 2), "cellar_trap")
	var plank := Build.vol(Vector3i(9, 4, 8))
	DistrictSecretProps.box(plank, Vector3i.ZERO, Vector3i(9, 4, 8), "wood")
	DistrictSecretProps.model(self, plank, Vector3(dog.x + 1.9, DistrictSecretMap.FLOOR, dog.z + 1.9), true, 0.0, "cellar_crate")
	DistrictSecretProps.bunker(self)


func _setup_props() -> void:
	var booth_volume := DistrictSecretProps.booth()
	for i in DistrictSecretProps.BOOTHS.size():
		var at: Vector3 = DistrictSecretProps.BOOTHS[i]
		var yaw: float = DistrictSecretProps.BOOTH_YAWS[i]
		DistrictSecretProps.model(self, booth_volume, at, true, yaw, "blue_booth")
		var flush := _button("booth/%d" % i, at + Vector3(0, 1.04, -0.39).rotated(Vector3.UP, yaw),
			Vector3(0.28, 0.19, 0.11), "metal_blue", "смыть воду")
		flush.rotation.y = yaw

	var lilac_mesh := VoxModel.mesh(DistrictSecretProps.lilac(), 0.1, Vector3(12, 0, 12))
	for at in level.lilacs:
		var shrub := MeshInstance3D.new()
		shrub.mesh = lilac_mesh
		shrub.position = at
		shrub.rotation.y = float(_lilac_meshes.size()) * 2.4
		shrub.visibility_range_end = 64.0
		shrub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shrub)
		_lilac_meshes.append(shrub)


func _setup_cameras() -> void:
	DistrictSecretProps.roof_station(self)
	var console := DistrictSecretProps.watch_terminal(self)
	_target("monitor", console, Vector3(1.34, 0.8, 0.32), "открыть пульт камер")
	DistrictSecretProps.radio_table(self, radio_dock())
	var pole_gate := _camera_pole(Vector3(7.4, 2.0, -78.1))
	var pole_playground := _camera_pole(Vector3(-30.4, 2.0, -32.0))
	var pole_east := _camera_pole(Vector3(65.2, 2.0, 7.4))
	var anchors: Array[Vector3] = [Vector3(-69, 6.35, 29.42), Vector3(-68, 7.54, 21),
		pole_gate, Vector3(15.04, 4.88, -80.8),
		DistrictSecretProps.ROOF_STATION + Vector3(-2.42, 2.22, 1.34),
		pole_playground, Vector3(55.6, 5.19, 35.54), Vector3(56, 7.33, -70.05),
		pole_east, Vector3(10, -0.17, 20.55)]
	var offsets: Array[Vector3] = [Vector3(0, -0.08, 0.54), Vector3(0, -0.58, 0),
		Vector3(0.4, 0, 0), Vector3(-0.52, 0, 0), Vector3(-0.52, 0, 0),
		Vector3(0.42, 0, 0), Vector3(0, -0.03, 0.52), Vector3(0, -0.08, 0.54),
		Vector3(-0.44, 0, 0), Vector3(0, -0.43, 0)]
	_camera_views.assign([Vector3(-67, 2.5, 37), Vector3(-65, 2.5, 27),
		Vector3(-3, 2.5, -83), Vector3(12, 2.4, -83), level.roof_route[-1],
		Vector3(-17, 2.3, -17), Vector3(53, 2.4, 43), Vector3(53, 2.2, -61),
		Vector3(58, 2.3, -4), Vector3(20, -1.55, 20.55)])
	DistrictSecretMap._light(world, console + Vector3(0.7, 0.64, 0.8), Color("#f7ddb3"))
	_disabled.resize(VIEW_COUNT)
	var camera_mesh := DistrictSecretProps.camera_model()
	for i in VIEW_COUNT:
		var at := anchors[i] + offsets[i]
		_camera_points.append(at)
		DistrictSecretProps.camera_mount(self, anchors[i], at)
		var body := _target("camera/%d" % i, at, Vector3(0.61, 0.43, 0.84), "")
		body.look_at(_camera_views[i], Vector3.UP)
		var model := MeshInstance3D.new()
		model.mesh = camera_mesh
		model.visibility_range_end = 78.0
		body.add_child(model)
	_cctv = DistrictCCTV.new()
	_cctv.secrets = self
	add_child(_cctv)


func _camera_pole(at: Vector3) -> Vector3:
	var post := Build.vol(Vector3i(8, 35, 8))
	DistrictSecretProps.box(post, Vector3i.ZERO, Vector3i(8, 3, 8), "concrete")
	DistrictSecretProps.box(post, Vector3i(3, 3, 3), Vector3i(2, 32, 2), "metal_dark")
	DistrictSecretProps.box(post, Vector3i(2, 32, 2), Vector3i(4, 2, 4), "metal")
	DistrictSecretProps.model(self, post, at, true, 0.0, "cctv_pole")
	return at + Vector3.UP * 3.3


func _button(key: String, at: Vector3, size: Vector3, swatch: String, label: String) -> StaticBody3D:
	var body := _target(key, at, size, label)
	if not label.is_empty():
		body.set_meta("shot_button", true)
	var v := Build.vol(Vector3i((size * 10.0).ceil()).max(Vector3i.ONE))
	DistrictSecretProps.box(v, Vector3i.ZERO, v.get_size(), swatch)
	DistrictSecretProps.box(v, Vector3i(1, 1, v.get_size().z - 1), Vector3i(1, 1, 1), "lamp")
	DistrictSecretProps.model(body, v, -Vector3.UP * size.y * 0.5)
	return body


func _target(key: String, at: Vector3, size: Vector3, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = Layers.SECRET
	body.collision_mask = 0
	body.set_meta("secret_key", key)
	body.set_meta("secret_label", label)
	_collision(body, size, Vector3.ZERO)
	add_child(body)
	targets[key] = body
	return body


func _collision(body: CollisionObject3D, size: Vector3, at: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = at
	body.add_child(collider)


func _mover(volume: VoxelVolume, at: Vector3, size: Vector3, label: String) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = label
	body.set_meta("layout_label", label)
	body.set_meta("layout_origin", at)
	body.position = at
	body.sync_to_physics = false
	body.collision_layer = Layers.STATIC
	body.collision_mask = Layers.PLAYER
	_collision(body, size, Vector3.UP * size.y * 0.5)
	add_child(body)
	DistrictSecretProps.model(body, volume, Vector3.ZERO)
	return body


func _shaft(key: String, cell: Vector2i, offset: Vector3) -> void:
	var low := Vector3(cell.x, DistrictSecretMap.FLOOR, cell.y)
	var mouth := Vector3(cell.x, 2.28, cell.y)
	var high := mouth + offset
	var ladder_at := low + offset.normalized() * 0.83
	DistrictSecretProps.ladder(self, ladder_at, ladder_at + Vector3.UP * 4.6,
		Vector3.RIGHT if absf(offset.z) > 0.1 else Vector3.BACK)
	var mouth_key := key + "/down"
	var floor_key := key + "/up"
	_target(mouth_key, mouth + offset * 0.80 + Vector3.UP * 0.13, Vector3(0.9, 0.26, 0.9), "спуститься")
	_target(floor_key, low + offset * 0.47 + Vector3.UP * 0.9, Vector3(0.55, 0.65, 0.55), "подняться")
	_paths[mouth_key] = PackedVector3Array([high, mouth, low])
	_paths[floor_key] = PackedVector3Array([low, mouth, high])


func _ladder(key: String, path: PackedVector3Array, label: String) -> void:
	DistrictSecretProps.ladder(self, path[0], path[1])
	_target(key + "/up", path[0] + Vector3.UP * 1.25, Vector3(0.78, 1.5, 0.53), label)
	_target(key + "/down", path[-1] + Vector3.UP * 0.35, Vector3(0.82, 0.68, 0.68), "спуститься по лестнице")
	_paths[key + "/up"] = path
	var reverse := path.duplicate()
	reverse.reverse()
	_paths[key + "/down"] = reverse


func _car_at(lowered: bool) -> Vector3:
	return Vector3(11.05, 2.18 if lowered else 3.69, -80.9)


func _target_key(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var collider: Object = hit.collider
	if collider.has_meta("secret_key"):
		return str(collider.get_meta("secret_key"))
	if collider == _car or collider == _lift_deck:
		return "lift_break"
	for i in rugs.size():
		if collider == rugs[i].body:
			return "rug/%d" % i
	return ""


func hint(hit := {}) -> String:
	if player.transit_active or player.hide_spot >= 0 or player.navigation_menu_open:
		return ""
	var key := _target_key(player.aim_ray(2.65, MASK) if hit.is_empty() else hit)
	if targets.has(key):
		var label := str(targets[key].get_meta("secret_label"))
		if not label.is_empty():
			return "%s — %s" % [GameControls.key_name("grab"), label]
	return ""


func interact() -> bool:
	if player.transit_active or player.hide_spot >= 0:
		return false
	var key := _target_key(player.aim_ray(2.65, MASK))
	if not targets.has(key) or str(targets[key].get_meta("secret_label")).is_empty():
		return false
	if key == "monitor":
		_cctv.open()
	elif _paths.has(key):
		var blocked := (key.begins_with("pharmacy_hatch") and not _cross_open
			or key.begins_with("garage_hatch") and _lowered and not _lift_broken
			or key.begins_with("cellar_hatch") and not _dog_open
			or key == "zip_start" and _zip_broken)
		if blocked:
			_message("Маршрут перекрыт")
		else:
			_follow(_paths[key], key == "zip_start", key.begins_with("garage_hatch") or key.begins_with("cellar_hatch"))
	else:
		_request(key)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not player.movement_enabled or player.dead or player.vehicle or player.navigation_menu_open or player.transit_active:
		return
	if event.is_action_pressed("secret_shot") and can_shoot:
		var time := _now()
		if time < _next_shot:
			return
		_next_shot = time + 0.32
		var hit := player.aim_ray(38.0, MASK)
		world.sfx.play("rifle", player.camera.global_position, -14.0)
		if not hit.is_empty():
			world.fx.sparks(hit.position, hit.normal)
			hit_target(hit)
		get_viewport().set_input_as_handled()


func hit_target(hit: Dictionary, from_shotgun := false, source: Player = null) -> bool:
	var key := _target_key(hit)
	if key.is_empty():
		return false
	if key.begins_with("rug/") or key.begins_with("camera/") or key in ["zip_start", "zip_end", "cross", "lift_break"]:
		_request_hit(key, source)
	elif from_shotgun and hit.collider.has_meta("shot_button"):
		_request_hit(SHOTGUN_BUTTON + key, source)
	return true


func _request_hit(key: String, source: Player) -> void:
	if WebSession.connected and is_instance_valid(source):
		weapon_hit_requested.emit(key, source)
	else:
		_request(key, true)


func _request(key: String, shot := false) -> void:
	if WebSession.connected:
		action_requested.emit(key, shot)
	else:
		authorize(key, local_side, player.global_position, shot)


func authorize(key: String, side: int, at: Vector3, shot: bool, blast_hit := false, verified_hit := false) -> Dictionary:
	var time := _now()
	if not at.is_finite() or side < 0 or side >= RoomRules.SIDES:
		return {}
	var button_shot := key.begins_with(SHOTGUN_BUTTON)
	if button_shot:
		key = key.trim_prefix(SHOTGUN_BUTTON)
		if not shot or blast_hit or not targets.has(key) or not targets[key].has_meta("shot_button"):
			return {}
	var pos := _action_pos(key)
	var range_m := 46.0 if shot else 3.15
	if not pos.is_finite() or at.distance_squared_to(pos) > range_m * range_m:
		return {}
	if shot and not button_shot:
		if not (key.begins_with("rug/") or key.begins_with("camera/") or key in ["zip_start", "zip_end", "cross", "lift_break"]):
			return {}
	if side != local_side and not verified_hit and (targets.has(key) or shot):
		var hit := world.raycast(at + Vector3.UP * 1.43, pos, MASK)
		if not hit.is_empty() and _target_key(hit) != key:
			return {}
	if button_shot:
		shot = false
	var event := {"key": key, "side": side}
	var i := _index(key)
	if key.begins_with("shield/"):
		if time < rugs[i].next or rugs[i].broken:
			return _reject(side, "Щит пока недоступен")
	elif key.begins_with("escape/"):
		pass
	elif key.begins_with("rug/"):
		if not shot or rugs[i].broken or time < rugs[i].until:
			return _reject(side, "Преграда защищена") if time < rugs[i].until else {}
	elif key.begins_with("camera/"):
		if not shot:
			return {}
	elif key.begins_with("booth/"):
		if time < _booth_until[side]:
			return _reject(side, "Смыв восстановится через %d с" % ceili(_booth_until[side] - time))
	elif key == "cross":
		if _cross_open:
			return _reject(side, "Шкаф уже отъехал")
	elif key in ["lower", "raise", "lift_break"]:
		if _lift_broken or (key == "lower" and _lowered) or (key == "raise" and not _lowered):
			return {}
		if key == "lift_break":
			event["hits"] = 3 if blast_hit else _lift_hits + 1
	elif key == "dog":
		if _dog_open:
			return {}
	elif key in ["zip_start", "zip_end"]:
		if (key == "zip_start" and not shot) or _zip_broken:
			return {}
	elif key == "alarm":
		if time < _alarm_until:
			return _reject(side, "Сирена остывает")
	else:
		return {}
	apply_event(event)
	return event


func _reject(side: int, label: String) -> Dictionary:
	if side == local_side:
		_message(label)
	return {"key": "notice", "side": side, "label": label} if side != local_side else {}


func _action_pos(key: String) -> Vector3:
	if targets.has(key):
		return targets[key].global_position
	var index := _index(key)
	if key.begins_with("rug/") and index >= 0 and index < rugs.size():
		return rugs[index].at + Vector3.UP * 1.0
	if key == "lift_break":
		return Vector3(12, 2.8 if _lowered else 4.0, -83)
	if key == "dog":
		return DOGHOUSE_BASE
	if key == "alarm":
		return targets.monitor.global_position
	return Vector3.INF


func _index(key: String) -> int:
	return key.get_slice("/", 1).to_int() if key.contains("/") else -1


func apply_event(event: Dictionary) -> void:
	var key := str(event.get("key", ""))
	var side := int(event.get("side", -1))
	if side < 0 or side >= RoomRules.SIDES:
		return
	var mine := side == local_side
	var time := _now()
	var i := _index(key)
	if key == "notice":
		if mine:
			_message(str(event.get("label", "")))
	elif key.begins_with("shield/"):
		rugs[i].until = time + 5.0
		rugs[i].next = time + 18.0
		rugs[i].light.show()
		world.sfx.play("transit", rugs[i].at, -8.0)
		if mine:
			_message("Щит активен · 5 секунд")
	elif key.begins_with("escape/"):
		if mine:
			_teleport(DistrictSecretProps.GARAGE_EXIT)
	elif key.begins_with("rug/"):
		_break_rug(i)
	elif key.begins_with("camera/"):
		_disable_camera(i, time)
	elif key.begins_with("booth/"):
		_booth_until[side] = time + 40.0
		if mine:
			var other := 1 - i
			var exit_offset := Vector3(0, 0.13, 0.39).rotated(Vector3.UP, DistrictSecretProps.BOOTH_YAWS[other])
			_teleport(Vector3(DistrictSecretProps.BOOTHS[other]) + exit_offset)
	elif key == "cross":
		_cross_open = true
		_animate("rack", _cupboard, Vector3(-80.95, 2.2, 20), 1.15)
		world.sfx.play("hide_slide", _cupboard.global_position, -4.0)
		if mine:
			_message("В подсобке аптеки открылся вход в бункер")
	elif key in ["lower", "raise"]:
		_lowered = key == "lower"
		_animate("car", _car, _car_at(_lowered), 1.3)
		_animate("deck", _lift_deck, Vector3(12, 1.99 if _lowered else 3.50, -83), 1.3)
		world.sfx.play("metal", _lift_deck.global_position, -4.0)
	elif key == "lift_break":
		_lift_hits = int(event.hits)
		if _lift_hits < 3:
			world.fx.sparks(_car.world_center(), Vector3.UP)
			world.sfx.play("metal", _car.world_center(), -5.0)
			if mine:
				_message("Блокировка ослабла · %d/3" % _lift_hits)
			return
		_lift_broken = true
		for n in 16:
			var offset := Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 0.7), randf_range(-1.8, 1.8))
			world.debris.spawn(_car.world_center() + offset, Color("#496561"), 0.16, offset * 2.8 + Vector3.UP)
		_car.volume.fill_box(Vector3i.ZERO, _car.volume.get_size(), 0)
		_car.rebuild_all()
		_lift_deck.hide()
		_lift_deck.set_deferred("collision_layer", 0)
		world.fx.dust_cloud(Vector3(12, 2.6, -83), 0.8)
		world.sfx.play("metal", Vector3(12, 2.6, -83), -4.0)
	elif key == "dog":
		_dog_open = true
		_trap.set_deferred("collision_layer", 0)
		_animate("trap", _trap, _trap.position - Vector3.UP * 3.5, 0.48)
		world.sfx.play("wood_break", _trap.global_position, -3.0)
	elif key in ["zip_start", "zip_end"]:
		_zip_broken = true
		_cable.hide()
		world.sfx.play("metal", targets[key].global_position, -4.0)
	elif key == "alarm":
		_alarm_until = time + maxf(ALARM_COOLDOWN, Sfx.siren_duration())
		world.sfx.play_gate_alarm()


func _break_rug(index: int) -> void:
	var room := rugs[index]
	if room.broken:
		return
	room.broken = true
	var rug := room.body as VoxelObject
	var at: Vector3 = room.at + Vector3.UP
	for n in 20:
		var voxel := Vector3i(n * 7 % 19, n * 11 % 23, 0)
		var id := rug.volume.get_voxel(voxel)
		if id != 0:
			world.debris.spawn(rug.voxel_to_world(Vector3(voxel)), VoxMat.color_of(id).srgb_to_linear(), 0.09,
				Vector3(randf_range(-1, 1), randf_range(0.4, 2.0), randf_range(-1, 1)))
	rug.volume.fill_box(Vector3i.ZERO, rug.volume.get_size(), 0)
	rug.rebuild_all()
	world.sfx.play("cloth_rip", at, -1.0)
	world.fx.dust(at, Color("#82604a"), 0.65)
	_mark_destruction(at, 1.0)


func protected(object: VoxelObject, at: Vector3, radius: float) -> bool:
	var time := _now()
	for room in rugs:
		if room.until <= time:
			continue
		if object == room.body or (object == room.building
				and at.distance_squared_to(Vector3(room.at) + Vector3.UP) < pow(2.4 + radius, 2.0)):
			return true
	return false


func blast(at: Vector3, radius: float) -> void:
	for i in rugs.size():
		if Vector3(rugs[i].at).distance_squared_to(at) <= radius * radius and not protected(rugs[i].body, at, radius):
			_break_rug(i)
	if at.distance_squared_to(_action_pos("lift_break")) <= radius * radius:
		authorize("lift_break", local_side, at, true, true)
	for key in ["zip_start", "zip_end"]:
		if at.distance_squared_to(_action_pos(key)) <= radius * radius:
			authorize(key, local_side, at, true)


func _animate(key: String, node: Node3D, at: Vector3, duration: float) -> void:
	if _tweens.has(key):
		(_tweens[key] as Tween).kill()
	var animation := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	animation.tween_property(node, "position", at, duration).set_trans(Tween.TRANS_SINE)
	_tweens[key] = animation


func cancel_player_travel() -> void:
	if is_instance_valid(_travel):
		_travel.kill()
	player.transit_active = false
	player.velocity = Vector3.ZERO


func _follow(path: PackedVector3Array, zip: bool, crouch_passage := false, face_route := false) -> void:
	if player.transit_active or path.size() < 2:
		return
	if WebSession.connected and int(WebSession.rules.zone) > 0:
		for stop: Vector3 in path:
			if not RoomRules.contains(stop, player.border - 0.4):
				_message("Этот проход выходит за границу раунда")
				return
	player.transit_active = true
	if crouch_passage:
		player._set_crouch(true)
	player.release_grab(false)
	player.tools.cancel_placement()
	player.velocity = Vector3.ZERO
	_travel = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var last := player.global_position
	var destination := path[-1]
	for at in path:
		var movement := at - last
		var duration := maxf(0.075, movement.length() / (13.5 if face_route else (19.0 if zip else 3.3)))
		_travel.tween_property(player, "global_position", at, duration)
		if face_route and movement.length_squared() > 0.01:
			var yaw := atan2(-movement.x, -movement.z)
			var pitch := atan2(movement.y, Vector2(movement.x, movement.z).length())
			_travel.parallel().tween_method(func(weight: float):
				var target_yaw := player.rotation.y if Vector2(movement.x, movement.z).length_squared() < 0.01 else yaw
				player.look_at_dir(lerp_angle(player.rotation.y, target_yaw, weight),
					lerpf(player.head.rotation.x, clampf(pitch, -0.82, 0.82), weight)),
				0.0, 0.38, minf(0.30, duration))
		last = at
	_travel.tween_callback(func():
		player.transit_active = false
		player.velocity = Vector3.ZERO
		player._exit_fall_protection = 0.8
		player.reset_physics_interpolation()
		if zip:
			world.sfx.play("thud", destination, -9.0))
	world.sfx.play("throw" if zip else "metal", player.global_position, -9.0)


func _teleport(at: Vector3) -> void:
	var landing := player._clear_exit(at + Vector3.UP * 0.42)
	if not landing.is_finite():
		_message("Выход занят")
		return
	world.sfx.play("transit", player.global_position, -6.0)
	player.release_grab(false)
	player.tools.cancel_placement()
	player.global_position = landing
	player.velocity = Vector3.ZERO
	player._exit_fall_protection = 0.8
	player.reset_physics_interpolation()
	world.sfx.play("transit", landing, -6.0)


func _physics_process(_delta: float) -> void:
	if player.movement_enabled and not player.transit_active and player.crouching and not _dog_open:
		var at := player.global_position - DOGHOUSE_BASE
		if absf(at.x) < 0.56 and absf(at.z) < 0.60 and absf(at.y) < 0.5:
			_request("dog")


func _process(_delta: float) -> void:
	var time := _now()
	for room in rugs:
		if room.light.visible and time >= room.until:
			room.light.hide()


func obscures(from: Vector3, to: Vector3) -> bool:
	for shrub in _lilac_meshes:
		var center := shrub.global_position + Vector3.UP * 1.12
		if center.distance_squared_to(to) < 0.84 * 0.84 and center.distance_squared_to(from) > 0.84 * 0.84:
			return true
	var hit := world.raycast(from, to, Layers.SECRET)
	return _target_key(hit).begins_with("rug/")


func _mark_destruction(at: Vector3, radius: float) -> void:
	var now := _now()
	if (not can_shoot or radius < 0.5 or now - _trace_at < 0.4
			or player.global_position.distance_squared_to(at) > 22.0 * 22.0):
		return
	_trace_at = now
	if is_instance_valid(_trace):
		_trace.queue_free()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.32
	ring.rings = 12
	ring.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.67, 0.28, 0.65)
	ring.material = material
	var trace := MeshInstance3D.new()
	trace.mesh = ring
	trace.position = at + Vector3.UP * 0.14
	trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trace)
	_trace = trace
	var fade := create_tween().set_parallel()
	fade.tween_property(trace, "scale", Vector3.ONE * 2.8, 1.65)
	fade.tween_property(material, "albedo_color:a", 0.0, 1.65)
	fade.chain().tween_callback(trace.queue_free)


func reset_round(seed: int) -> void:
	if _seed == seed:
		return
	_seed = seed
	_rng.seed = seed
	_booth_until.fill(0.0)
	_alarm_until = 0.0
	world.sfx.stop_gate_alarm()
	_disabled.fill(0.0)
	if is_instance_valid(_travel):
		_travel.kill()
	player.transit_active = false
	for tween: Tween in _tweens.values():
		tween.kill()
	_tweens.clear()
	_cctv.close()
	for room in rugs:
		if room.broken:
			room.body.volume = DistrictSecretProps.rug()
			room.body.rebuild_all()
		room.broken = false
		room.until = 0.0
		room.next = 0.0
		room.light.hide()
	_cross_open = false
	_cupboard.position = Vector3(-79, 2.2, 20)
	_lowered = false
	if _lift_broken:
		_car.volume = DistrictSecretProps.garage_car()
		_car.rebuild_all()
	_lift_broken = false
	_lift_hits = 0
	_car.position = _car_at(false)
	_lift_deck.position = Vector3(12, 3.50, -83)
	_lift_deck.show()
	_lift_deck.set_deferred("collision_layer", Layers.STATIC)
	_dog_open = false
	_trap.position = DOGHOUSE_BASE - Vector3.UP * 0.03
	_trap.set_deferred("collision_layer", Layers.STATIC)
	_zip_broken = false
	_cable.show()


func _disable_camera(index: int, now: float) -> void:
	if index < 0 or index >= _disabled.size() or _disabled[index] > now:
		return
	_disabled[index] = now + CAMERA_RECOVERY
	world.fx.sparks(_camera_points[index], Vector3.UP)
	world.sfx.play("metal", _camera_points[index], -9.0)


func broadcast_position() -> Vector3:
	return DistrictSecretProps.GATE_SIREN


func radio_dock() -> Vector3:
	return targets.monitor.global_position + Vector3(-1.31, -0.615, 0.39)


func radio_socket() -> Vector3:
	return targets.monitor.global_position + Vector3(-0.54, -0.53, -0.27)


func request_alarm() -> void:
	_request("alarm")


func _message(label: String) -> void:
	get_tree().call_group("hud", "message", label, 2.5)
