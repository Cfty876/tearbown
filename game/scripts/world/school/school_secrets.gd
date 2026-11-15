class_name SchoolSecrets
extends DistrictSecrets

signal football_scored(event: Dictionary)

const BELL_SECONDS := 15.0
const BELL_COOLDOWN := 35.0

var school: SchoolLevel
var elevator: SchoolElevator
var football: SchoolFootball
var _projection: SpotLight3D
var _projector: VoxelObject
var _projector_on := false
var _bell_until := 0.0
var _bell_on := false
var _red_lamps: Array[MeshInstance3D] = []
var _acid_until := 0.0
var _acid_used := false
var _acid_pool: MeshInstance3D
var _hoop: AnimatableBody3D
var _hoop_dropped := false
var _rails_shifted := false
var _rails: Array[AnimatableBody3D] = []
var _rail_home: Array[Vector3] = []
var _bookcases: Array[AnimatableBody3D] = []
var _books_fallen := false
var _saved_voxels: Array[Dictionary] = []
var _power := true
var _screen: MeshInstance3D
var traps: SchoolTraps
var campus_actions: SchoolCampusActions
var _controls := {}
var _button_meshes: Array[Mesh] = []
var _button_pressed_at := {}
var other_player_position := Vector3.INF
var _football_touch_at := 0.0
var _restroom_ready := [0.0, 0.0]
var _transfer_mask: ColorRect


func _ready() -> void:
	_restroom_ready.resize(RoomRules.SIDES)
	_restroom_ready.fill(0.0)
	world.sfx.install_school_bell()
	var overlay := CanvasLayer.new()
	overlay.layer = 25
	add_child(overlay)
	_transfer_mask = ColorRect.new()
	_transfer_mask.color = Color(0.02, 0.07, 0.08, 0)
	_transfer_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_transfer_mask)
	_transfer_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camera_station()
	_warning_lamps()
	_routes()
	for key: String in school.restroom_links:
		add_control(key, school.restroom_links[key].button, Vector3(0.28, 0.28, 0.19),
			"перейти в такую же кабинку другого корпуса", Vector3.LEFT)
	elevator = SchoolElevator.new()
	elevator.controller = self
	add_child(elevator)
	elevator.build()
	football = SchoolFootball.new()
	football.controller = self
	add_child(football)
	_destructibles()
	_wardrobe_setup()
	_books_setup()
	traps = SchoolTraps.new()
	traps.controller = self
	add_child(traps)
	traps.build()
	campus_actions = SchoolCampusActions.new()
	campus_actions.controller = self
	add_child(campus_actions)
	campus_actions.build()
	var weather := SchoolWeather.new()
	weather.controller = self
	add_child(weather)
	reset_round(120)


func _button(key: String, at: Vector3, size: Vector3, swatch: String, label: String) -> StaticBody3D:
	if label.is_empty():
		return super._button(key, at, size, swatch, label)
	var normal := Vector3.UP if key in ["radio", "guard_bell", "screen_hint"] else Vector3.BACK
	return add_control(key, at, size, label, normal)


func add_control(key: String, at: Vector3, size: Vector3, label: String, normal: Vector3,
		secondary := false) -> StaticBody3D:
	var old: StaticBody3D = targets.get(key, null)
	var body := _target(key, at, size if absf(normal.y) < 0.9 else Vector3(size.x, size.z, size.y), label)
	if secondary and old:
		targets[key] = old
	body.set_meta("shot_button", true)
	if _button_meshes.is_empty():
		_button_meshes = SchoolButton.models()
	var control := SchoolButton.install(body, size, normal, _button_meshes)
	_controls[key] = control
	var collider := body.get_child(0) as CollisionShape3D
	var shape := CylinderShape3D.new()
	shape.radius = 0.179 * control.scale.x
	shape.height = 0.25 * control.scale.x
	collider.shape = shape
	collider.basis = control.basis.orthonormalized() * Basis(Vector3.RIGHT, PI * 0.5)
	collider.position = body.global_basis.inverse() * normal * 0.03
	return body


func mount_panel(button: Vector3, floor_y: float, normal: Vector3) -> void:
	var depth := 3
	var top := button.y + 0.19 if absf(normal.y) < 0.9 else button.y - 0.045
	var height := maxi(3, floori((top - floor_y) * 10.0))
	var stand := Build.vol(Vector3i(4, height, depth))
	SchoolLevel.box(stand, Vector3i(0, 0, 0), Vector3i(4, 1, depth), "metal_dark")
	SchoolLevel.box(stand, Vector3i(1, 1, 0), Vector3i(2, height - 2, 2), "metal_teal")
	SchoolLevel.box(stand, Vector3i(0, height - 3, 0), Vector3i(4, 3, depth), "metal_dark")
	SchoolLevel.box(stand, Vector3i(0, height - 1, 0), Vector3i(4, 1, depth), "metal")
	var at := Vector3(button.x, floor_y, button.z)
	if absf(normal.y) < 0.9:
		at -= normal * 0.192
	var yaw := atan2(normal.x, normal.z) if absf(normal.y) < 0.9 else 0.0
	DistrictSecretProps.model(self, stand, at, true, yaw, "Крепление кнопки")


func _camera_station() -> void:
	mount_panel(SchoolLevel.RADIO, 9.99, Vector3.UP)
	_button("radio", SchoolLevel.RADIO, Vector3(0.38, 0.34, 0.32), "metal_red", "включить школьный звонок")
	var screen := Build.vol(Vector3i(16, 12, 9))
	SchoolLevel.box(screen, Vector3i.ZERO, Vector3i(16, 12, 8), "metal_dark")
	SchoolLevel.box(screen, Vector3i(2, 3, 8), Vector3i(12, 8, 1), "metal_teal")
	for x in [3, 7, 11]:
		SchoolLevel.box(screen, Vector3i(x, 4, 8), Vector3i(2, 4, 1), "metal_blue")
	SchoolLevel.box(screen, Vector3i(2, 1, 8), Vector3i(1, 1, 1), "lamp")
	var console := SchoolLevel.MONITOR
	DistrictSecretProps.model(self, screen, console + Vector3(0, -0.57, -0.33))
	_target("monitor", console, Vector3(1.64, 1.13, 0.34), "открыть школьные камеры")
	DistrictSecretProps.radio_table(self, radio_dock())
	_button("guard_bell", console + Vector3(1.02, -0.43, 0.04), Vector3(0.32, 0.29, 0.27),
		"metal_red", "включить школьный звонок")
	var post := Build.vol(Vector3i(8, 41, 8))
	SchoolLevel.box(post, Vector3i.ZERO, Vector3i(8, 3, 8), "concrete")
	SchoolLevel.box(post, Vector3i(3, 3, 3), Vector3i(2, 38, 2), "metal_dark")
	DistrictSecretProps.model(self, post, Vector3(2, 2, -39), true, 0, "Стойка камеры")
	var anchors: Array[Vector3] = [Vector3(-19.8, 5.85, -18), Vector3(19.8, 5.85, 18),
		Vector3(-6.4, 5.23, 5.94), Vector3(2, 5.98, -39)]
	var offsets: Array[Vector3] = [Vector3(0, -0.49, 0), Vector3(0, -0.49, 0),
		Vector3(0, -0.16, 0.48), Vector3(-0.46, 0, 0)]
	_camera_views.assign([Vector3(-19.4, 2.65, -5), Vector3(19.3, 2.65, 5),
		Vector3(1, 2, 23), Vector3(-28, 2, -55)])
	_disabled.resize(anchors.size())
	var model := DistrictSecretProps.camera_model()
	for i in anchors.size():
		var at := anchors[i] + offsets[i]
		_camera_points.append(at)
		DistrictSecretProps.camera_mount(self, anchors[i], at)
		var body := _target("camera/%d" % i, at, Vector3(0.6, 0.43, 0.83), "")
		body.look_at(_camera_views[i])
		var mesh := MeshInstance3D.new()
		mesh.mesh = model
		body.add_child(mesh)
	_cctv = DistrictCCTV.new()
	_cctv.secrets = self
	_cctv.camera_names = SchoolLevel.CAMERA_NAMES
	_cctv.analog_feed = true
	_cctv.station_title = "ШКОЛА 120  /  ПОСТ ОХРАНЫ"
	_cctv.alarm_title = "ШКОЛЬНЫЙ РАДИОУЗЕЛ"
	_cctv.alarm_duration = BELL_SECONDS
	_cctv.alarm_cooldown = BELL_COOLDOWN
	add_child(_cctv)


func _warning_lamps() -> void:
	var beacon := BoxMesh.new()
	beacon.size = Vector3(0.20, 0.13, 0.22)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ee3724")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color("#f93a24")
	material.emission_energy_multiplier = 3.2
	beacon.material = material
	for at in school.warning_points:
		var lamp := MeshInstance3D.new()
		lamp.mesh = beacon
		lamp.position = at
		lamp.visibility_range_end = 32.0
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
		lamp.hide()
		_red_lamps.append(lamp)


func _routes() -> void:
	_school_shaft("bunker", SchoolLevel.LOBBY_HATCH, Vector3(0, 0, 1.42))
	_school_shaft("boiler", SchoolLevel.BOILER_HATCH, Vector3(0, 0, 1.40))
	var loft := SchoolLevel.ATTIC
	_ladder("loft", PackedVector3Array([loft + Vector3(0, 0.22, 0.95),
		loft + Vector3(0, 0.24, 0), loft + Vector3(0, 3.91, 0),
		loft + Vector3(0, 3.91, 0.88)]), "залезть в голубятню")
	DistrictSecretProps.ladder(self, loft + Vector3(0.52, 0.22, 0),
		loft + Vector3(0.52, 4.2, 0), Vector3.BACK)
	_ladder("greenhouse", PackedVector3Array([SchoolYard.GREENHOUSE_LOW, SchoolYard.GREENHOUSE_TOP,
		SchoolYard.GREENHOUSE_TOP + Vector3(0, 0, -1.04)]), "подняться на галерею теплицы")
	_ladder("gym_walk", PackedVector3Array([Vector3(35.87, 9.82, -1.24),
		Vector3(35.87, 12.11, -1.24), Vector3(36.65, 12.11, -1.24)]), "взобраться на мостки спортзала")

	var duct := SchoolLevel.DUCT
	var landing := Vector3(duct.x, 2.28, duct.z + 1.2)
	_target("duct", duct + Vector3(0, 0.34, 0.63), Vector3(0.64, 0.60, 0.53), "спуститься по вытяжке")
	_paths["duct"] = PackedVector3Array([duct + Vector3(0, 0.23, 0), Vector3(duct.x, 2.28, duct.z), landing])
	_target("duct_return", landing + Vector3(0, 0.92, -0.1), Vector3(0.51, 0.58, 0.51), "пролезть в лаборантскую")
	_paths["duct_return"] = PackedVector3Array([landing, Vector3(duct.x, 2.28, duct.z),
		duct + Vector3(0, 0.23, 0), duct + Vector3(0, 0.23, 0.98)])
	var tube := Build.vol(Vector3i(16, 39, 16))
	for y in range(0, 39, 4):
		SchoolLevel.box(tube, Vector3i(0, y, 1), Vector3i(2, 4, 14), "metal_dark")
		SchoolLevel.box(tube, Vector3i(14, y, 1), Vector3i(2, 4, 14), "metal_dark")
		SchoolLevel.box(tube, Vector3i(2, y, 0), Vector3i(12, 4, 2), "metal_teal")
	DistrictSecretProps.model(self, tube, Vector3(duct.x, 2.21, duct.z))

	SchoolPipe.build(self)
	for z: float in SchoolCampus.DUCT_STANDS:
		var frame := Build.vol(Vector3i(50, 41, 6))
		SchoolLevel.box(frame, Vector3i(44, 0, 0), Vector3i(6, 5, 6), "concrete_dark")
		SchoolLevel.box(frame, Vector3i(45, 5, 1), Vector3i(4, 33, 4), "metal_teal")
		SchoolLevel.box(frame, Vector3i(0, 34, 1), Vector3i(50, 4, 4), "metal_teal")
		for i in 10:
			SchoolLevel.box(frame, Vector3i(35 + i, 34 - i, 1), Vector3i(1, 4, 4), "metal_dark")
		school.place(frame, Vector3(58.6, SchoolLevel.GROUND, z - 0.3), "Опора вентиляционной трубы")
	var floodlight_control := Vector3(64.15, 3.11, -29.7)
	mount_panel(floodlight_control, SchoolLevel.GROUND, Vector3.BACK)
	_button("power", floodlight_control, Vector3(0.34, 0.44, 0.27),
		"metal_yellow", "переключить прожекторы стадиона")
	var projector_at := Vector3(46.45, 10.0, 2.68)
	var projector := Build.vol(Vector3i(18, 15, 14))
	SchoolLevel.box(projector, Vector3i.ZERO, Vector3i(18, 2, 14), "metal_dark")
	SchoolLevel.box(projector, Vector3i(1, 2, 1), Vector3i(16, 9, 12), "wood_dark")
	SchoolLevel.box(projector, Vector3i(0, 11, 0), Vector3i(18, 1, 14), "wood")
	SchoolLevel.box(projector, Vector3i(3, 12, 4), Vector3i(9, 3, 8), "metal_teal")
	for x in [4, 9]:
		projector.fill_cylinder(Vector3(x, 13, 5), 2.3, 2, 2, VoxMat.id("metal"))
	SchoolLevel.box(projector, Vector3i(6, 12, 12), Vector3i(3, 3, 2), "metal_dark")
	SchoolLevel.box(projector, Vector3i(7, 13, 13), Vector3i(1, 1, 1), "lamp")
	_projector = DistrictSecretProps.model(self, projector, projector_at, true, 0.0, "Пульт кинопроектора")
	_button("screen_hint", projector_at + Vector3(0.53, 1.22, 0.11),
		Vector3(0.24, 0.24, 0.21), "metal_blue", "переключить проектор")
	_projection = SpotLight3D.new()
	_projection.position = projector_at + Vector3(-0.15, 1.34, 0.72)
	_projection.light_color = Color("#c7e5ff")
	_projection.light_energy = 2.6
	_projection.spot_range = 17.0
	_projection.spot_angle = 23.0
	add_child(_projection)
	_projection.look_at(SchoolLevel.FILM + Vector3.UP * 2.0)
	_projection.hide()


func _school_shaft(key: String, point: Vector2, offset: Vector3, title := "спуститься в убежище") -> void:
	var low := Vector3(point.x, -3.68, point.y)
	var mouth := Vector3(point.x, 2.25, point.y)
	var high := mouth + offset
	var rail := low + Vector3(0.77, 0, 0)
	DistrictSecretProps.ladder(self, rail, rail + Vector3.UP * 6.0, Vector3.BACK)
	_target(key + "/down", high + Vector3.UP * 0.19, Vector3(0.95, 0.38, 0.7), title)
	_target(key + "/up", low + Vector3(0, 0.88, 0.5), Vector3(0.74, 0.82, 0.56), "подняться наверх")
	_paths[key + "/down"] = PackedVector3Array([high, mouth, low])
	_paths[key + "/up"] = PackedVector3Array([low, mouth, high])


func _destructibles() -> void:
	var a := SchoolLevel.ACID + Vector3(0, 1.0, 0)
	var bottle := Build.vol(Vector3i(10, 17, 10))
	bottle.fill_cylinder(Vector3(5, 0, 5), 4.4, 12, 1, VoxMat.id("glass"))
	bottle.fill_cylinder(Vector3(5, 1, 5), 3.2, 8, 1, VoxMat.id("metal_blue"))
	bottle.fill_cylinder(Vector3(5, 12, 5), 2.4, 4, 1, VoxMat.id("glass"))
	bottle.fill_cylinder(Vector3(5, 16, 5), 2.5, 1, 1, VoxMat.id("metal_dark"))
	var target := _target("acid", a + Vector3.UP * 0.85, Vector3(0.94, 1.7, 0.94), "Столкнуть бутыль со стола")
	DistrictSecretProps.model(target, bottle, Vector3(0, -0.85, 0))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.92
	barrel.bottom_radius = 0.92
	barrel.height = 0.017
	barrel.radial_segments = 24
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(0.35, 0.74, 0.12, 0.75)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.emission_enabled = true
	tint.emission = Color("#75f02b")
	tint.emission_energy_multiplier = 0.55
	barrel.material = tint
	_acid_pool = MeshInstance3D.new()
	_acid_pool.mesh = barrel
	_acid_pool.position = SchoolLevel.ACID + Vector3.UP * 0.226
	add_child(_acid_pool)
	_acid_pool.hide()
	var hoop := Build.vol(Vector3i(19, 21, 13))
	SchoolLevel.box(hoop, Vector3i(0, 7, 6), Vector3i(19, 14, 2), "pvc")
	SchoolLevel.box(hoop, Vector3i(4, 10, 5), Vector3i(11, 8, 1), "metal_teal")
	SchoolLevel.box(hoop, Vector3i(7, 8, 0), Vector3i(5, 2, 6), "metal_red")
	SchoolLevel.box(hoop, Vector3i(8, 0, 6), Vector3i(3, 7, 3), "metal_dark")
	_hoop = _mover(hoop, SchoolLevel.HOOP - Vector3.UP * 1.77, Vector3(1.9, 2.1, 1.30), "Баскетбольный щит")
	_hoop.set_meta("secret_key", "hoop")
	var bracket := SchoolLevel.HOOP + Vector3.UP * 0.58
	_button("hoop", bracket, Vector3(0.64, 0.32, 0.43), "metal_yellow", "")
	DistrictSecretProps.beam(self, bracket, Vector3(bracket.x, 13.47, bracket.z), 0.045, Color("#495661"))
	var sheet := Build.vol(Vector3i(104, 27, 2))
	SchoolLevel.box(sheet, Vector3i.ZERO, Vector3i(104, 26, 1), "pvc")
	SchoolLevel.box(sheet, Vector3i(0, 26, 0), Vector3i(104, 1, 2), "metal_dark")
	_screen = DistrictSecretProps.model(self, sheet, SchoolLevel.FILM + Vector3(0, 1.10, 0)) as MeshInstance3D


func _wardrobe_setup() -> void:
	var rack := Build.vol(Vector3i(15, 21, 92))
	for z in [1, 45, 89]:
		SchoolLevel.box(rack, Vector3i(7, 1, z), Vector3i(2, 20, 2), "metal_dark")
		SchoolLevel.box(rack, Vector3i(1, 1, z), Vector3i(13, 2, 3), "metal")
		for x in [3, 11]:
			SchoolLevel.box(rack, Vector3i(x, 0, z), Vector3i(1, 2, 3), "tank_black")
	SchoolLevel.box(rack, Vector3i(7, 18, 1), Vector3i(2, 2, 90), "metal")
	for z in range(3, 88, 3):
		SchoolLevel.box(rack, Vector3i(3, 4 + z % 3, z), Vector3i(8, 14 - z % 3, 3),
			["metal_blue", "curtain_red", "wood_dark", "curtain_green"][z % 4])
	for i in 5:
		var at := SchoolLevel.WARDROBE + Vector3(-6.4 + i * 3.05, 0.10, -0.9 + (i % 2) * 5.1)
		_rails.append(_mover(rack, at, Vector3(1.29, 2.07, 9.18), "Вешалки · ряд %d" % (i + 1)))
		_rail_home.append(at)
		_rack_tracks(at, rack_shift(i))
	_target("racks", SchoolLevel.WARDROBE + Vector3(8.1, 1.13, -2.2),
		Vector3(0.32, 0.44, 0.36), "")
	targets.racks.collision_layer = 0


static func rack_shift(index: int) -> float:
	return 1.4 if index % 2 else -2.65


func _rack_tracks(home: Vector3, shift: float) -> void:
	var depth := ceili((9.2 + absf(shift) + 0.4) * 10.0)
	var rail := Build.vol(Vector3i(11, 1, depth))
	for x in [1, 9]:
		SchoolLevel.box(rail, Vector3i(x, 0, 0), Vector3i(1, 1, depth), "metal")
	for z in range(1, depth, 8):
		SchoolLevel.box(rail, Vector3i(0, 0, z), Vector3i(11, 1, 1), "metal_dark")
	var z := home.z + shift * 0.5
	DistrictSecretProps.model(self, rail, Vector3(home.x, SchoolLevel.BASEMENT + 0.2, z))


func _books_setup() -> void:
	var shelf := Build.vol(Vector3i(15, 25, 7))
	SchoolRooms.shelf(shelf, Vector3i(0, 0, 0), 15, 25, 4)
	for i in 5:
		_bookcases.append(_mover(shelf, Vector3(-15.65 + i * 0.93, 9.82, 25.2),
			Vector3(1.48, 2.49, 0.68), "Стеллаж-домино"))
		_bookcases[-1].rotation.y = PI * 0.5
	_button("books", Vector3(-16.11, 10.08, 25.25), Vector3(0.49, 0.38, 0.52), "wood_light", "")


func hint(hit := {}) -> String:
	if player.transit_active or player.navigation_menu_open:
		return ""
	var key := _target_key(player.aim_ray(2.65, MASK) if hit.is_empty() else hit)
	if key == "football":
		return "%s — пнуть мяч" % GameControls.key_name("grab")
	var label := str(targets[key].get_meta("secret_label")) if targets.has(key) else ""
	if not label.is_empty():
		return "%s — %s" % [GameControls.key_name("grab"), label]
	return ""


func interact() -> bool:
	if player.transit_active:
		return false
	var key := _target_key(player.aim_ray(2.65, MASK))
	if key == "football":
		_request(key)
		return true
	if not targets.has(key) or str(targets[key].get_meta("secret_label")).is_empty():
		return false
	if key == "monitor":
		_cctv.open()
	elif _paths.has(key) and not traps.handles(key):
		if traps.route_allowed(key):
			if _is_pipe(key):
				_request(key)
			else:
				var crouched_route := key in ["duct", "duct_return"] or key.begins_with("gym_walk") or key.begins_with("rope_")
				_follow(_paths[key], key in ["bar", "stage_rope"], crouched_route)
	else:
		_request(key)
	return true


func touch_football() -> void:
	if _now() >= _football_touch_at:
		_football_touch_at = _now() + 0.33
		_request("football_touch")


func _is_pipe(key: String) -> bool:
	return key == "cyclone" or key.begins_with("pipe/")


func _start_pipe(key: String) -> void:
	var path: PackedVector3Array = _paths[key].duplicate()
	var landing := player._clear_exit(path[-1] + Vector3.UP * 0.7)
	if not landing.is_finite() or absf(landing.y - path[-1].y) > 0.65:
		_message("Станция вентиляции перекрыта")
		return
	path[-1] = landing
	_follow(path, true, true, true)


func hit_target(hit: Dictionary, from_shotgun := false, source: Player = null) -> bool:
	var key := _target_key(hit)
	if key == "football":
		if is_instance_valid(source):
			_request_hit(key, source)
		return true
	if not key.is_empty() and hit.collider.has_meta("shot_button"):
		if from_shotgun:
			_request_hit(SHOTGUN_BUTTON + key, source)
		return true
	if key.begins_with("camera/") or key in ["acid", "hoop", "books"] or traps.destructible(key):
		_request_hit(key, source)
		return true
	return false


func _action_pos(key: String) -> Vector3:
	if key == "football":
		return football.global_position
	if key == "alarm":
		return targets.monitor.global_position
	return targets[key].global_position if targets.has(key) else Vector3.INF


func authorize(key: String, side: int, at: Vector3, shot: bool, blast_hit := false, verified_hit := false) -> Dictionary:
	if side < 0 or side >= RoomRules.SIDES or not at.is_finite():
		return {}
	if key in ["football", "football_touch"]:
		if not football.try_kick(at, shot, verified_hit or side == local_side, key == "football_touch"):
			return {}
		return {"key": key, "side": side}
	var button_shot := key.begins_with(SHOTGUN_BUTTON)
	if button_shot:
		key = key.trim_prefix(SHOTGUN_BUTTON)
		if not shot or blast_hit or not _controls.has(key):
			return {}
	var point: Vector3 = _controls[key].global_position if button_shot else _action_pos(key)
	if not point.is_finite() or at.distance_squared_to(point) > (2116.0 if shot else 10.0):
		return {}
	if side != local_side and (shot or traps.handles(key) or campus_actions.handles(key) or elevator.handles(key)) and not blast_hit and not verified_hit:
		var hit := world.raycast(at + Vector3.UP * 1.43, point, MASK)
		if not hit.is_empty() and _target_key(hit) != key:
			return {}
	if button_shot:
		if _now() - float(_button_pressed_at.get(key, -10.0)) < 0.4:
			return {}
		shot = false
	if _is_pipe(key) and _paths.has(key):
		if shot or at.distance_squared_to(_paths[key][0]) > (18.0 if button_shot else 10.0):
			return _reject(side, "Подойди ко входу в трубу")
		var ride := {"key": key, "side": side}
		apply_event(ride)
		return ride
	if school.restroom_links.has(key):
		var source: Dictionary = school.restroom_links[key]
		var range_squared := 9.0 if button_shot else 1.05
		if shot or at.distance_squared_to(source.landing) > range_squared or _now() < float(_restroom_ready[side]):
			return {}
		var exit: Vector3 = school.restroom_links[source.pair].landing
		var floor_hit := player._clear_exit(exit + Vector3.UP * 0.35)
		if not floor_hit.is_finite() or absf(floor_hit.y - exit.y) > 0.22 or other_player_position.distance_squared_to(exit) < 0.85:
			return _reject(side, "Кабинка в другом корпусе занята или повреждена")
		var transfer := {"key": key, "side": side}
		apply_event(transfer)
		return transfer
	if campus_actions.handles(key):
		if shot or not campus_actions.can_use(key, at, other_player_position):
			return _reject(side, "Проход занят или механизм перезаряжается")
		var action := {"key": key, "side": side}
		apply_event(action)
		return action
	if traps.handles(key):
		return traps.authorize(key, side, at, shot, blast_hit, button_shot)
	var destructible := key in ["acid", "hoop", "books"] or key.begins_with("camera/")
	if destructible != shot and key != "acid":
		return {}
	var event := {"key": key, "side": side}
	match key:
		"alarm", "radio", "guard_bell":
			if _now() < _alarm_until:
				return _reject(side, "Радиоузел перезаряжается")
		"acid":
			if _acid_used:
				return {}
		"books":
			if _books_fallen:
				return {}
		"hoop":
			if _hoop_dropped:
				return {}
		"racks", "power", "screen_hint":
			pass
		_:
			if elevator.handles(key):
				var floor := _index(key)
				if not elevator.can_move(key, floor, at, other_player_position):
					return _reject(side, "Лифт занят или проход перекрыт")
				event["floor"] = floor
			elif not key.begins_with("camera/"):
				return {}
	apply_event(event)
	return event


func apply_event(event: Dictionary) -> void:
	var key := str(event.get("key", ""))
	var side := int(event.get("side", -1))
	if side < 0 or side >= RoomRules.SIDES:
		return
	var time := _now()
	if _controls.has(key) and not bool(event.get("shot", false)):
		_button_pressed_at[key] = time
		(_controls[key] as SchoolButton).push()
		world.sfx.play("click", _controls[key].global_position, -5.0)
	if key == "notice":
		super.apply_event(event)
	elif key == "football_goal":
		world.sfx.goal_bell()
		_message("ГОЛ  /  СТАДИОН")
	elif _is_pipe(key) and _paths.has(key):
		if side == local_side:
			_start_pipe(key)
	elif school.restroom_links.has(key):
		_restroom_ready[side] = time + 1.6
		if side == local_side:
			_animate_restroom_transfer(school.restroom_links[school.restroom_links[key].pair].landing)
	elif campus_actions.handles(key):
		campus_actions.apply(key)
	elif traps.handles(key):
		traps.apply(event)
	elif key in ["alarm", "radio", "guard_bell"]:
		_alarm_until = time + BELL_COOLDOWN
		_bell_until = time + BELL_SECONDS
		_bell_on = true
		world.sfx.school_bell(true)
		_message("Школьный звонок · шум движения заглушён")
	elif key.begins_with("camera/"):
		_disable_camera(_index(key), time)
	elif elevator.handles(key):
		elevator.move(int(event.get("floor", -1)))
	elif key == "racks":
		_rails_shifted = not _rails_shifted
		for i in _rails.size():
			var shift := Vector3.BACK * rack_shift(i) if _rails_shifted else Vector3.ZERO
			_animate("rack/%d" % i, _rails[i], _rail_home[i] + shift, 1.25)
		world.sfx.play("hide_slide", SchoolLevel.WARDROBE, -2.5)
	elif key == "power":
		_power = not _power
		for lamp in school.yard_lights:
			lamp.visible = _power
		world.sfx.play("click", targets.power.global_position)
	elif key == "screen_hint":
		_projector_on = not _projector_on
		_update_projection()
		world.sfx.play("click", targets.screen_hint.global_position)
	elif key == "acid":
		_acid_used = true
		_acid_until = time + 5.0
		_acid_pool.show()
		_set_target("acid", false)
		world.fx.dust(_acid_pool.global_position, Color("#a0dd48"), 0.65)
		world.sfx.play("glass", _acid_pool.global_position)
		world.sfx.loop("school_acid", "extinguisher", _acid_pool.global_position, true, -11.0)
	elif key == "books":
		_books_fallen = true
		_set_target("books", false)
		for i in _bookcases.size():
			var shelf := _bookcases[i]
			var fall := create_tween()
			fall.tween_interval(float(i) * 0.19)
			fall.tween_property(shelf, "rotation:z", -1.48, 0.38).set_trans(Tween.TRANS_QUAD)
			fall.parallel().tween_property(shelf, "position", shelf.position + Vector3(0.46, 0.25, 0), 0.38)
			_tweens["book/%d" % i] = fall
		world.fx.dust_cloud(_bookcases[2].global_position, 1.05)
		world.sfx.play("collapse", _bookcases[2].global_position, -1.5)
	elif key == "hoop":
		_hoop_dropped = true
		_set_target("hoop", false)
		var fall := create_tween()
		fall.tween_property(_hoop, "position:y", 6.19, 0.66).set_trans(Tween.TRANS_QUAD)
		fall.tween_callback(_break_gym)
		fall.tween_property(_hoop, "position:y", -3.65, 0.9).set_trans(Tween.TRANS_QUAD)
		fall.tween_callback(_shatter_hoop)
		_tweens["hoop"] = fall


func cancel_player_travel() -> void:
	super.cancel_player_travel()
	if is_instance_valid(_transfer_mask):
		_transfer_mask.color.a = 0.0


func _animate_restroom_transfer(destination: Vector3) -> void:
	if player.transit_active:
		return
	player.transit_active = true
	player.velocity = Vector3.ZERO
	player.release_grab(false)
	player.tools.cancel_placement()
	_travel = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_travel.tween_property(_transfer_mask, "color:a", 1.0, 0.17)
	_travel.tween_callback(func():
		var landing := player._clear_exit(destination + Vector3.UP * 0.42)
		if not player.dead and landing.is_finite() and absf(landing.y - destination.y) <= 0.22:
			_teleport(destination)
		else:
			_message("Кабинка в другом корпусе перекрыта"))
	_travel.tween_property(_transfer_mask, "color:a", 0.0, 0.27)
	_travel.tween_callback(func(): player.transit_active = false)


func _set_target(key: String, active: bool) -> void:
	var target: StaticBody3D = targets[key]
	target.visible = active
	target.set_deferred("collision_layer", Layers.SECRET if active else 0)


func _shatter_hoop() -> void:
	var at := _hoop.global_position + Vector3.UP * 0.35
	_hoop.hide()
	_hoop.collision_layer = 0
	for i in 28:
		var offset := Vector3(randf_range(-0.9, 0.9), randf_range(0, 0.7), randf_range(-0.4, 0.4))
		var color := Color("#aebbbb") if i % 3 else Color("#396e70")
		world.debris.spawn(at + offset, color.srgb_to_linear(), 0.13, offset * 3.0 + Vector3.UP * 1.3)
	world.fx.dust_cloud(at, 1.1)
	world.sfx.play("crumble", at, -1.0)


func _break_gym() -> void:
	var where := SchoolLevel.HOOP
	for floor in [0, 1]:
		var object: VoxelObject = school.annex[floor]
		_hole(object, Vector3(where.x, object.global_position.y + 0.10, where.z), 1.28)
	world.fx.dust_cloud(Vector3(where.x, 6.15, where.z), 1.9)
	world.sfx.play("collapse", Vector3(where.x, 6.15, where.z), 3.0)


func _hole(object: VoxelObject, at: Vector3, size: float, height := 2) -> void:
	var center := Vector3i(object.to_voxel(at).floor())
	var radius := roundi(size * 10.0)
	var cells: Array[Vector3i] = []
	var values := PackedByteArray()
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if x * x + z * z > radius * radius:
				continue
			for y in range(height):
				var cell := Vector3i(center.x + x, y, center.z + z)
				var old := object.volume.get_voxel(cell)
				if old == 0:
					continue
				cells.append(cell)
				values.append(old)
				object.volume.set_voxel(cell, 0)
	object.mark_dirty(center - Vector3i(radius, 2, radius), center + Vector3i(radius, height + 2, radius))
	_saved_voxels.append({"object": object, "cells": cells, "values": values, "center": center, "radius": radius, "height": height})
	world.geometry_changed.emit(at, size)

func _update_projection() -> void:
	var intact := is_instance_valid(_projector) and VoxMat.material_of(_projector.volume.get_voxel(Vector3i(7, 13, 13))) == VoxMat.EMISSIVE
	_projection.visible = _projector_on and intact


func _process(delta: float) -> void:
	super._process(delta)
	if _projector_on:
		_update_projection()
	var time := _now()
	traps.tick(delta)
	campus_actions.tick(time)
	if _bell_on:
		if time >= _bell_until:
			_bell_on = false
			world.sfx.school_bell(false)
		var blink := posmod(floori(time * 6.0), 2) == 0 if _bell_on else not traps._power_on
		for lamp in _red_lamps:
			lamp.visible = blink
	if _acid_until > 0.0 and time >= _acid_until:
		_acid_until = 0.0
		_acid_pool.hide()
		world.sfx.loop("school_acid", "extinguisher", _acid_pool.global_position, false)
		_hole(school.wings[Vector2i(0, 1)], SchoolLevel.ACID + Vector3.UP * 0.13, 0.92, 12)
		world.fx.dust(_acid_pool.global_position, Color("#83b749"), 0.7)
		world.sfx.play("crumble", _acid_pool.global_position, -3.0)


func blast(at: Vector3, radius: float) -> void:
	var away := football.global_position - at
	if away.length_squared() < radius * radius:
		football.apply_central_impulse(away.normalized() * 8.0 + Vector3.UP * 1.6)
	for key in ["acid", "hoop", "books", "lobby_hatch", "field_hatch", "pool_drain", "gas", "mains"]:
		if at.distance_squared_to(_action_pos(key)) <= radius * radius:
			authorize(key, local_side, at, true, true)


func obscures(from: Vector3, to: Vector3) -> bool:
	if super.obscures(from, to) or traps.obscures(from, to) or traps.slowed(from):
		return true
	if not is_instance_valid(_screen) or not _screen.visible:
		return false
	var impact: Variant = Plane(Vector3.BACK, SchoolLevel.FILM.z).intersects_segment(from, to)
	if impact == null:
		return false
	var at: Vector3 = impact
	return absf(at.x - SchoolLevel.FILM.x) < 5.2 and at.y > 10.9 and at.y < 13.62


func move_multiplier() -> float:
	return 0.52 if traps.slowed(player.global_position + Vector3.UP) else 1.0


func wet_tile() -> bool:
	var at := player.global_position
	var pool := at.y < 2.55 and at.y > 1.15 and at.x > 38.0 and at.x < 53.2 and at.z > 5.3 and at.z < 15.4
	var roof := at.y > 17.45 and at.y < 19.0 and at.x > -28.0 and at.x < -20.5 and at.z > 25.8 and at.z < 31.0
	return pool or roof


func broadcast_position() -> Vector3:
	return SchoolLevel.RADIO + Vector3.UP * 2.0


func radio_dock() -> Vector3:
	return SchoolLevel.MONITOR + Vector3(-1.20, -0.57, -0.23)


func radio_socket() -> Vector3:
	return SchoolLevel.MONITOR + Vector3(-0.77, -0.47, -0.27)


func on_public_address() -> bool:
	return player.global_position.distance_squared_to(targets.microphone.global_position) < 6.0


func reset_round(seed: int) -> void:
	if _seed == seed:
		return
	_seed = seed
	football.reset_ball()
	world.sfx.stop_goal_bell()
	_disabled.fill(0.0)
	_button_pressed_at.clear()
	_football_touch_at = 0.0
	_restroom_ready.fill(0.0)
	_transfer_mask.color.a = 0.0
	_alarm_until = 0.0
	_bell_on = false
	world.sfx.school_bell(false)
	for lamp in _red_lamps:
		lamp.hide()
	_cctv.close()
	if is_instance_valid(_travel):
		_travel.kill()
	for tween: Tween in _tweens.values():
		tween.kill()
	_tweens.clear()
	player.transit_active = false
	elevator.reset()
	_acid_until = 0.0
	_acid_used = false
	_acid_pool.hide()
	world.sfx.loop("school_acid", "extinguisher", _acid_pool.global_position, false)
	_set_target("acid", true)
	_hoop_dropped = false
	_hoop.show()
	_hoop.collision_layer = Layers.STATIC
	_hoop.position = SchoolLevel.HOOP - Vector3.UP * 1.77
	_set_target("hoop", true)
	_books_fallen = false
	_set_target("books", true)
	for i in _bookcases.size():
		_bookcases[i].position = Vector3(-15.65 + i * 0.93, 9.82, 25.2)
		_bookcases[i].rotation = Vector3(0, PI * 0.5, 0)
	_rails_shifted = false
	for i in _rails.size():
		_rails[i].position = _rail_home[i]
	for edit in _saved_voxels:
		var object := edit.object as VoxelObject
		if not is_instance_valid(object):
			continue
		for i in edit.cells.size():
			object.volume.set_voxel(edit.cells[i], edit.values[i])
		var extent := Vector3i(edit.radius, edit.height + 2, edit.radius)
		object.mark_dirty(Vector3i(edit.center) - extent, Vector3i(edit.center) + extent)
	_saved_voxels.clear()
	_screen.show()
	_projector_on = false
	_projection.hide()
	_power = true
	for lamp in school.yard_lights:
		lamp.show()
	traps.reset()
	campus_actions.reset()
	for door in school.entry_doors + school.restroom_doors:
		if is_instance_valid(door) and door.opened:
			door.set_open(false, 0.0)
