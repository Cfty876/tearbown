class_name DistrictTransit
extends Node3D

const PORTAL_SHADER := preload("res://shaders/transit_field.gdshader")
const MIN_SPACING := 20.0
const INDOOR_COUNT := 4
const COLORS := [Color("#79e6f4"), Color("#ffc27e"), Color("#91f3c6"), Color("#abafff"), Color("#f3a89d")]
const SITES := [
	Vector2(11, 45), Vector2(-17, -6), Vector2(-59, 39), Vector2(50, -53), Vector2(-43, -80),
	Vector2(17, 45), Vector2(-11, -6), Vector2(-53, 39), Vector2(56, -53), Vector2(-37, -80),
	Vector2(11, 39), Vector2(-17, 0), Vector2(-59, 45), Vector2(50, -59), Vector2(-43, -86),
	Vector2(86, 61), Vector2(65, 78), Vector2(39, 70), Vector2(-22, 75), Vector2(-62, 72),
	Vector2(79, -75), Vector2(86, -53), Vector2(5, -89), Vector2(-86, -54), Vector2(85, 12),
]

var player: Player
var world: VoxelWorld
var level: DistrictLevel
var _stations: Array[Node3D] = []
var _origins: Array[Vector3] = []
var _indoor: Array[bool] = []
var _prompt: InteractionPrompt
var _prompt_station := -1
var _flash: ColorRect
var _cooldown := 0.0
var _near := -1
var _active_seed := -1


func _ready() -> void:
	for i in COLORS.size() * 2:
		_station(i)
		_stations[i].hide()
	var canvas := CanvasLayer.new()
	canvas.layer = 14
	add_child(canvas)
	var ui := Control.new()
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt = InteractionPrompt.new()
	ui.add_child(_prompt)
	_flash = ColorRect.new()
	_flash.color = Color(0.35, 0.82, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not WebSession.connected:
		arrange(randi())


func arrange(seed_value: int) -> void:
	if seed_value == _active_seed:
		return
	_active_seed = seed_value
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var sites := _pick_sites(random)
	_shuffle(sites, random)
	_origins.clear()
	_prompt_station = -1
	_indoor.clear()
	for i in _stations.size():
		var station := _stations[i]
		station.visible = i < sites.size()
		if not station.visible:
			continue
		var site := sites[i]
		var inside := bool(site.inside)
		_origins.append(site.at)
		_indoor.append(inside)
		station.position = site.at
		station.rotation.y = site.yaw
		station.scale = Vector3.ONE * (0.72 if inside else 1.0)
	_near = -1
	_cooldown = 0.35


func _pick_sites(random: RandomNumberGenerator) -> Array[Dictionary]:
	var indoor := level.portal_sites.duplicate()
	var outdoor: Array[Dictionary] = []
	for xz: Vector2 in SITES:
		outdoor.append({"at": Vector3(xz.x, level.ground_height(xz.x, xz.y), xz.y), "inside": false, "yaw": 0.0})
	var best: Array[Dictionary] = []
	for attempt in 32:
		_shuffle(indoor, random)
		_shuffle(outdoor, random)
		var result: Array[Dictionary] = []
		_append_spaced(indoor, result, INDOOR_COUNT)
		if result.size() < INDOOR_COUNT:
			continue
		_append_spaced(outdoor, result, _stations.size())
		if result.size() == _stations.size():
			return result
		if result.size() > best.size():
			best = result
	if best.size() % 2 != 0:
		best.pop_back()
	return best


func _append_spaced(sites: Array[Dictionary], result: Array[Dictionary], goal: int) -> void:
	for site in sites:
		var at: Vector3 = site.at
		var clear := true
		for chosen in result:
			var offset: Vector3 = at - chosen.at
			if Vector2(offset.x, offset.z).length_squared() <= MIN_SPACING * MIN_SPACING:
				clear = false
				break
		if clear:
			result.append(site)
			if result.size() >= goal:
				return


func _shuffle(sites: Array[Dictionary], random: RandomNumberGenerator) -> void:
	for i in range(sites.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var previous := sites[j]
		sites[j] = sites[i]
		sites[i] = previous


func _station(index: int) -> void:
	var station := Node3D.new()
	_stations.append(station)
	add_child(station)
	var volume := VoxModel.volume(Vector3i(24, 29, 12))
	var steel := VoxMat.id("metal_dark")
	var plate := VoxMat.id("metal_teal")
	var amber := VoxMat.id("road_yellow")
	volume.fill_box(Vector3i(0, 0, 0), Vector3i(24, 2, 12), steel)
	volume.fill_box(Vector3i(1, 2, 1), Vector3i(23, 3, 11), plate)
	for x in [1, 20]:
		volume.fill_box(Vector3i(x, 2, 3), Vector3i(x + 3, 25, 9), steel)
		volume.fill_box(Vector3i(x, 6, 3), Vector3i(x + 3, 22, 4), plate)
		volume.fill_box(Vector3i(x, 22, 3), Vector3i(x + 3, 24, 4), amber)
	for x in range(2, 23, 4):
		volume.fill_box(Vector3i(x, 2, 1), Vector3i(x + 2, 3, 2), amber)
	volume.fill_box(Vector3i(1, 24, 2), Vector3i(23, 28, 10), steel)
	volume.fill_box(Vector3i(6, 25, 2), Vector3i(18, 27, 3), VoxMat.id("sign_glow"))
	station.add_child(VoxModel.instance(volume, 0.096, Vector3(12, 0, 6)))
	var field := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.51, 1.97)
	field.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_SHADER
	mat.set_shader_parameter("tint", COLORS[index / 2])
	mat.set_shader_parameter("phase", float(index) * 0.67)
	field.material_override = mat
	field.position = Vector3(0, 1.28, 0)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.visibility_range_end = 65.0
	station.add_child(field)
	var caption := Label3D.new()
	caption.text = "ПАРА %02d   /   %s" % [index / 2 + 1, "А" if index % 2 == 0 else "Б"]
	caption.modulate = COLORS[index / 2]
	caption.font_size = 39
	caption.outline_size = 12
	caption.pixel_size = 0.006
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.position.y = 2.96
	station.add_child(caption)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_near = -1
	if not player.dead and not player.vehicle and player.hide_spot < 0 and not player.navigation_menu_open:
		var distance := 5.0
		for i in _origins.size():
			var sq := _origins[i].distance_squared_to(player.global_position)
			if sq < distance and world.raycast(player.camera.global_position, _origins[i] + Vector3.UP * 0.95).is_empty():
				_near = i
				distance = sq
	_prompt.hide()
	if not player.movement_enabled or player.clock_locked() or _cooldown > 0.0 or player.tools._inventory_open:
		_prompt_station = -1
		return
	var eye := player.camera.global_position
	if _near >= 0:
		var to_portal := _origins[_near] + Vector3.UP * 1.3 - eye
		if player.aim_dir().dot(to_portal.normalized()) > 0.81:
			_prompt_station = _near
	if _prompt_station >= 0:
		var point := _origins[_prompt_station] + Vector3.UP * 1.3
		if eye.distance_squared_to(point) > 64.0 or not world.raycast(eye, point).is_empty():
			_prompt_station = -1
		else:
			_prompt.present("%s — войти в портал %02d" % [GameControls.key_name("teleport"), _prompt_station / 2 + 1])
			_prompt.anchor_to(player.camera, point)


func _unhandled_input(event: InputEvent) -> void:
	if _near >= 0 and player.movement_enabled and not player.clock_locked() and event.is_action_pressed("teleport") and not player.tools._inventory_open:
		travel_to(_near)
		get_viewport().set_input_as_handled()


func travel_to(from: int) -> bool:
	if from < 0 or from >= _origins.size() or _cooldown > 0.0 or from != _near:
		return false
	var index := from ^ 1
	var destination := _clear_landing(_origins[index], _stations[index].rotation.y, _indoor[index])
	if not destination.is_finite():
		get_tree().call_group("hud", "message", "Выход портала перекрыт", 2.0)
		return false
	player.release_grab(false)
	player.tools.cancel_placement()
	player.global_position = destination
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	_cooldown = 1.15
	world.sfx.play_ui("transit", -8.0)
	_flash.color = Color(COLORS[index / 2], 0.46)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.42)
	return true


func _clear_landing(at: Vector3, yaw := 0.0, inside := false) -> Vector3:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Layers.SOLID
	query.exclude = [player.get_rid()]
	var step := 0.68 if inside else 1.35
	for offset: Vector3 in [Vector3(0, 0, step), Vector3(0, 0, -step), Vector3(step, 0, 0), Vector3(-step, 0, 0), Vector3.ZERO]:
		var center := at + offset.rotated(Vector3.UP, yaw)
		var search := 0.48 if inside else 1.4
		var floor_hit := world.raycast(center + Vector3.UP * search, center - Vector3.UP * search, Layers.STATIC)
		if floor_hit.is_empty() or floor_hit.normal.y < 0.67:
			continue
		var landing: Vector3 = floor_hit.position + Vector3.UP * 0.09
		query.transform = Transform3D(Basis.IDENTITY, landing + Vector3.UP * 0.92)
		if space.intersect_shape(query, 1).is_empty():
			return landing
	return Vector3.INF
