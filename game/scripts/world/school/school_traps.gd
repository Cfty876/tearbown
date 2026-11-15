class_name SchoolTraps
extends Node3D

const POINTS := {
	"lobby_hatch": [SchoolLevel.LOBBY_HATCH, 2.0, "Открыть люк ключом охраны"],
	"pool_drain": [SchoolTrapProps.POOL_DRAIN, 1.24, ""],
	"field_hatch": [SchoolTrapProps.FIELD_HATCH, 1.83, ""],
}
const KEY_BUNKER := 1
const KEY_SERVICE := 2
const CARRIED_ITEMS := ["Ключ от убежища", "Ключ ПАЗа и щитовой", "Слесарный набор"]

var controller: SchoolSecrets
var _spent := {}
var _cooldowns := {}
var _keys := [0, 0]
var _service_unlocked := false
var _tools := [false, false]
var _clouds: Array[Dictionary] = []
var _hazards: Array[Dictionary] = []
var _lids := {}
var _moving := {}
var _flashes: ColorRect
var _air_body: Node3D
var _air_velocity := Vector3.ZERO
var _air_until := 0.0
var _gas_until := 0.0
var _gas_event_sent := false
var _last_hurt := 0.0
var _picture_open := false
var _safe_open := false
var _safe_shell: Node3D
var _power_on := true
var _garage_deck: AnimatableBody3D
var _garage_bus: VoxelObject
var _garage_home: Transform3D
var _garage_high := false
var _fire_poll := 0.0
var _paper_smoke := false


func build() -> void:
	_keys.resize(RoomRules.SIDES)
	_keys.fill(0)
	_tools.resize(RoomRules.SIDES)
	_tools.fill(false)
	for key: String in SchoolTrapProps.MODES:
		var data: Array = SchoolTrapProps.MODES[key]
		var at: Vector3 = data[1]
		var v := SchoolTrapProps.volume(key)
		var extent := Vector3(v.get_size()) * 0.1
		var height := extent.y * 0.5
		if key == "picture" or key == "safe":
			at.y += 1.08
		var target := controller._target(key, at + Vector3.UP * height, extent.max(Vector3(0.30, 0.25, 0.22)), data[2])
		var model := DistrictSecretProps.model(target, v, Vector3.DOWN * height)
		if key == "director_key":
			model.scale = Vector3.ONE * 0.67
		if key in ["saw", "medkit", "steam", "tesla", "phone", "mains", "garage_lift"]:
			var base := StaticBody3D.new()
			base.position = at + Vector3.UP * height * 0.68
			base.collision_layer = Layers.STATIC
			base.collision_mask = 0
			controller._collision(base, Vector3(extent.x * 0.85, height * 1.36, extent.z * 0.8), Vector3.ZERO)
			add_child(base)
		if key in ["saw", "steam", "tesla", "mains", "garage_lift"]:
			var panel := at + Vector3(0, maxf(0.65, height), extent.z * 0.5 + 0.41)
			controller.mount_panel(panel, at.y, Vector3.BACK)
			controller.add_control(key, panel, Vector3(0.34, 0.34, 0.20), data[2], Vector3.BACK, true)
		if key == "air":
			_air_body = target
	var safe_at: Vector3 = SchoolTrapProps.MODES.safe[1] + Vector3.UP * 1.08
	_safe_shell = Node3D.new()
	_safe_shell.position = safe_at
	add_child(_safe_shell)
	DistrictSecretProps.model(_safe_shell, SchoolTrapProps.volume("safe_open"), Vector3.ZERO)
	DistrictSecretProps.model(_safe_shell, SchoolTrapProps.volume("safe_door"), Vector3(0.59, 0.12, -0.74), false, PI * 0.5)
	_safe_shell.hide()
	controller._set_target("safe", false)
	controller._set_target("director_key", false)
	for key: String in POINTS:
		var data: Array = POINTS[key]
		var point: Vector2 = data[0]
		var at := Vector3(point.x, data[1], point.y)
		var lid_kind := "pool" if key == "pool_drain" else ("lobby" if key == "lobby_hatch" else "field")
		_lids[key] = controller._mover(SchoolTrapProps.lid(lid_kind), at, Vector3(2, 0.16, 2), key)
		controller._target(key, at + Vector3.UP * 0.24, Vector3(2.0, 0.18, 2.0), data[2])
	for p in [SchoolTrapProps.POOL_DRAIN, SchoolTrapProps.FIELD_HATCH]:
		var bottom := Vector3(p.x, -3.68, p.y)
		DistrictSecretProps.ladder(self, bottom + Vector3(0.67, 0, 0), bottom + Vector3(0.67, 5.74, 0), Vector3.BACK)
		var name := "pool_return" if p == SchoolTrapProps.POOL_DRAIN else "field_return"
		controller._target(name, bottom + Vector3(0, 1.0, 0.65), Vector3(0.8, 0.8, 0.5), "Подняться по шахте")
		var landing_y := 1.34 if p == SchoolTrapProps.POOL_DRAIN else 2.04
		controller._paths[name] = PackedVector3Array([bottom, Vector3(p.x, landing_y, p.y), Vector3(p.x, landing_y, p.y + 1.55)])
	var roof := SchoolLevel.ATTIC
	DistrictDoor.install(controller.world, Vector3(roof.x - 0.65, 17.5, roof.z + 1.57), 0.0, "door_metal")
	_build_stage_and_gear()
	_build_garage()
	_garage_pit_routes()
	_build_extra_routes()
	_build_cover_details()
	var fade := CanvasLayer.new()
	fade.layer = 18
	add_child(fade)
	_flashes = ColorRect.new()
	_flashes.color = Color(0.93, 0.97, 1.0, 0.0)
	_flashes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.add_child(_flashes)
	_flashes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controller._set_target("safe", false)


func _build_stage_and_gear() -> void:
	var player_world := controller.world
	var piano := Build.place(player_world, SchoolTrapProps.piano(), Vector3(40.4, 10.3, 13.6), false, 0.0, "Пианино")
	controller._target("piano", Vector3(40.4, 11.08, 12.78), Vector3(1.85, 0.7, 0.35), "Столкнуть пианино со сцены")
	_moving.piano = {"body": piano, "at": piano.position}
	for i in 6:
		Build.place(player_world, SchoolTrapProps.mock_rifle(), Vector3(6.2 + (i % 3) * 1.38, -3.7, -11.25 + (i / 3) * 0.53),
			false, 0.0, "Деревянный учебный макет")
	for i in 4:
		var ball := Build.vol(Vector3i(5, 5, 5))
		ball.fill_sphere(Vector3(2.5, 2.5, 2.5), 2.35, VoxMat.id("plastic_orange"))
		Build.place(player_world, ball, Vector3(38.5 + i * 0.55, 6.02, -12.5), false, 0.0, "Мяч")
	for i in 3:
		Build.place(player_world, Build.plank(21, 130 + i), Vector3(-14.8, 2.2, -13.7 + i * 0.48), false, 0.0, "Доска для баррикады")
	for x in [-34.0, -17.0]:
		Build.place(player_world, DistrictProps.bench(120), Vector3(x, 2.02, -69.5), false, 0.0, "Лавка трибун")
	var bed := Build.vol(Vector3i(20, 21, 10))
	for x in [0, 27]:
		for z in [0, 9]:
			SchoolTrapProps.b(bed, Vector3i(x, 0, z), Vector3i(1, 21, 1), "metal_teal")
	for y in [5, 15]:
		SchoolTrapProps.b(bed, Vector3i(0, y, 0), Vector3i(20, 1, 10), "metal_dark")
		SchoolTrapProps.b(bed, Vector3i(1, y + 1, 1), Vector3i(18, 2, 8), "curtain_beige")
	var bunk := Build.place(player_world, bed, Vector3(45.1, 6.02, 16.45), false, 0.0, "Кровать для баррикады")
	controller._target("bunk", Vector3(45.1, 7.16, 15.86), Vector3(1.7, 0.85, 0.36), "Сдвинуть койку в проход")
	_moving.bunk = {"body": bunk, "at": bunk.position}
	var floor := Vector3(47.2, 13.43, 12.8)
	DistrictSecretProps.beam(self, floor - Vector3.UP * 0.61, floor, 0.032, Color("#363a43"))
	for x: float in [40.68, 47.68, 54.25]:
		var top := Vector3(x, 12.17, -4.1)
		var low := Vector3(x, 6.09, -4.1)
		DistrictSecretProps.beam(self, low + Vector3.UP, top + Vector3.UP * 0.72, 0.037, Color("#716146"))
		var key := "rope_%d" % roundi(x)
		controller._target(key, low + Vector3(0, 1.55, 0), Vector3(0.31, 1.1, 0.31), "Взобраться по канату")
		controller._paths[key] = PackedVector3Array([low, top])
	var knot := Vector3(44.3, 13.62, 11.55)
	DistrictSecretProps.beam(self, Vector3(knot.x, 10.2, knot.z), knot, 0.041, Color("#706351"))
	controller._target("stage_rope", knot + Vector3.UP * 0.9, Vector3(0.52, 1.15, 0.52), "Спуститься на сцену")
	controller._paths.stage_rope = PackedVector3Array([knot, Vector3(knot.x, 10.35, knot.z)])


func _build_garage() -> void:
	var plate := Build.vol(Vector3i(29, 3, 53))
	SchoolTrapProps.b(plate, Vector3i.ZERO, plate.get_size(), "metal_dark")
	for z in range(0, 53, 4):
		for x in [0, 27]:
			SchoolTrapProps.b(plate, Vector3i(x, 2, z), Vector3i(2, 1, 2), "metal_yellow")
	var guide := Build.vol(Vector3i(7, 34, 7))
	SchoolTrapProps.b(guide, Vector3i.ZERO, Vector3i(7, 3, 7), "concrete_dark")
	SchoolTrapProps.b(guide, Vector3i(1, 3, 1), Vector3i(5, 30, 5), "metal_teal")
	SchoolTrapProps.b(guide, Vector3i(2, 8, 0), Vector3i(3, 23, 1), "metal")
	SchoolTrapProps.b(guide, Vector3i(0, 32, 0), Vector3i(7, 2, 7), "metal_yellow")
	for x in [48.42, 52.58]:
		var at := Vector3(x, 2.2, 66.4)
		DistrictSecretProps.model(self, guide, at, false)
		var stand := StaticBody3D.new()
		stand.position = at
		stand.collision_layer = Layers.STATIC
		stand.collision_mask = 0
		add_child(stand)
		controller._collision(stand, Vector3(0.5, 3.3, 0.5), Vector3(0, 1.65, 0))
	_garage_deck = controller._mover(plate, Vector3(50.5, 1.89, 66.4), Vector3(2.9, 0.3, 5.3), "Гаражный подъёмник")
	for object in controller.world.objects:
		if object.label == "Школьный автобус ПАЗ":
			_garage_bus = object
			_garage_home = object.transform
			break


func _garage_pit_routes() -> void:
	var edge := Vector3(50.5, 2.27, 69.78)
	var mouth := Vector3(50.5, 2.27, 68.77)
	var floor := Vector3(50.5, -0.73, 68.77)
	DistrictSecretProps.ladder(self, floor + Vector3(0.59, 0, 0.22), mouth + Vector3(0.59, 0.25, 0.22), Vector3.BACK)
	controller._target("garage_pit/down", edge + Vector3(0, 0.18, -0.15), Vector3(0.72, 0.35, 0.55),
		"спуститься под подъёмник")
	controller._target("garage_pit/up", floor + Vector3(0, 1.1, 0.17), Vector3(0.68, 0.72, 0.46),
		"подняться из ямы")
	var down := PackedVector3Array([edge, mouth, floor, floor + Vector3.FORWARD * 0.65])
	controller._paths["garage_pit/down"] = down
	var up := down.duplicate()
	up.reverse()
	controller._paths["garage_pit/up"] = up
	controller.add_control("garage_lift_low", Vector3(49.15, 0.35, 67.63), Vector3(0.28, 0.28, 0.18),
		"опустить или поднять ПАЗ", Vector3.RIGHT)


func _build_extra_routes() -> void:
	controller._paths.fan = PackedVector3Array([Vector3(-15.2, 6.24, -9.2),
		Vector3(-15.2, 9.86, -9.2), Vector3(-15.2, 9.86, -8.08)])
	var grate := controller._target("chimney", Vector3(57.6, 3.44, -56.55), Vector3(0.95, 1.2, 0.41), "")
	var grille := Build.vol(Vector3i(11, 13, 2))
	for x in [0, 3, 6, 9]:
		SchoolTrapProps.b(grille, Vector3i(x, 0, 0), Vector3i(2, 13, 2), "metal_dark")
	for y in [0, 11]:
		SchoolTrapProps.b(grille, Vector3i(0, y, 0), Vector3i(11, 2, 2), "metal_red")
	DistrictSecretProps.model(grate, grille, Vector3.DOWN * 0.65)
	controller._paths.chimney_ride = PackedVector3Array([Vector3(57.6, 2.26, -56.4),
		Vector3(58.8, 6.0, -61.2), Vector3(58.8, 8.3, -61.2), Vector3(58.5, 8.14, -58.45)])
	controller._target("bar", Vector3(-46.8, 3.6, -32.7), Vector3(0.52, 0.67, 0.52), "Перехватиться на перекладине")
	controller._paths.bar = PackedVector3Array([Vector3(-46.8, 2.08, -33.8), Vector3(-46.8, 3.34, -32.7),
		Vector3(-45.72, 3.15, -31.7), Vector3(-45.35, 2.08, -31.22)])


func _build_cover_details() -> void:
	var panel := BoxMesh.new()
	panel.size = Vector3(0.045, 1.30, 1.50)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/school_mirror.gdshader")
	panel.material = material
	var mirror := MeshInstance3D.new()
	mirror.mesh = panel
	mirror.position = Vector3(16.85, 3.65, 23.25)
	add_child(mirror)
	var pane := StaticBody3D.new()
	pane.position = mirror.position
	pane.collision_layer = Layers.STATIC
	pane.collision_mask = 0
	controller._collision(pane, panel.size, Vector3.ZERO)
	add_child(pane)
	var mats := Build.vol(Vector3i(45, 27, 2))
	for x in range(0, 45, 3):
		SchoolTrapProps.b(mats, Vector3i(x, 0, 0), Vector3i(3, 27 - x % 4, 2),
			"curtain_green" if x % 2 else "metal_green")
	DistrictSecretProps.model(self, mats, Vector3(50.5, -3.7, -11.0))



func handles(key: String) -> bool:
	if key == "garage_lift_low":
		return true
	return SchoolTrapProps.MODES.has(key) or POINTS.has(key) or key in ["piano", "bunk", "chimney"]


func destructible(key: String) -> bool:
	return key in ["pool_drain", "field_hatch", "chimney"] or (SchoolTrapProps.MODES.has(key) and SchoolTrapProps.MODES[key][0] in ["shot", "both"])


func route_allowed(key: String) -> bool:
	match key:
		"garage_pit/down", "garage_pit/up":
			if not _garage_high or controller._now() < float(_cooldowns.get("garage_lift", 0.0)):
				controller._message("Подними ПАЗ, чтобы открыть проход")
				return false
		"bunker/down":
			if not _spent.has("lobby_hatch"):
				controller._message("Люк под ковриком закрыт. Ключ на столе охраны")
				return false
		"bunker/up":
			return _spent.has("lobby_hatch")
		"pool_return":
			return _spent.has("pool_drain")
		"field_return":
			return _spent.has("field_hatch")
	return true


func bot_utility_ready(key: String, side: int) -> bool:
	if _spent.has(key):
		return false
	match key:
		"guard_key":
			return not _spent.has("lobby_hatch") and (_keys[side] & KEY_BUNKER) == 0
		"lobby_hatch":
			return (_keys[side] & KEY_BUNKER) != 0
		"picture":
			return not _picture_open and not _safe_open
		"safe":
			return _picture_open and not _safe_open
		"director_key":
			return _safe_open and (_keys[side] & KEY_SERVICE) == 0
		"mains":
			return _power_on and (_keys[side] & KEY_SERVICE) != 0
	return false


func authorize(key: String, side: int, at: Vector3, shot: bool, blast_hit: bool, button_shot := false) -> Dictionary:
	var mode := str(SchoolTrapProps.MODES[key][0]) if SchoolTrapProps.MODES.has(key) else ("shot" if key in ["field_hatch", "pool_drain", "chimney"] else "use")
	if mode != "both" and (mode == "shot") != shot and not (key == "lobby_hatch" and blast_hit):
		return {}
	if _spent.has(key):
		return {}
	var time := controller._now()
	if time < float(_cooldowns.get(key, 0.0)):
		return controller._reject(side, "Механизм ещё активен")
	if key == "lobby_hatch" and not blast_hit and (_keys[side] & KEY_BUNKER) == 0:
		return controller._reject(side, "Нужен ключ охраны")
	if key == "safe" and (not _picture_open or _safe_open):
		return {}
	if key == "director_key" and not _safe_open:
		return {}
	if key == "mains" and not (shot or button_shot) and not _can_use_service_lock(side):
		return controller._reject(side, "Нужен ключ из сейфа директора")
	if key == "tesla" and not _power_on:
		return controller._reject(side, "Щитовая отключена")
	if key == "medkit" and side == controller.local_side and controller.player.health >= Player.MAX_HEALTH:
		return controller._reject(side, "Здоровье полное")
	if key in ["garage_lift", "garage_lift_low"]:
		if time < float(_cooldowns.get("garage_lift", 0.0)):
			return controller._reject(side, "Подъёмник ещё движется")
		if is_instance_valid(_garage_bus) and controller.player.vehicle == _garage_bus.get_node_or_null("Vehicle"):
			return controller._reject(side, "Выйди из автобуса перед подъёмом")
		for feet: Vector3 in [at, controller.other_player_position]:
			if feet.is_finite() and SchoolBasement.GARAGE_PIT.has_point(Vector2(feet.x, feet.z)) and feet.y > 0.05 and feet.y < 4.65:
				return controller._reject(side, "Отойди от края платформы")
	var event := {"key": key, "side": side, "shot": shot}
	if key == "mains" and button_shot:
		event["button_shot"] = true
	if key == "gas":
		event["ignite"] = _gas_until > time
	if key == "fixer" and not shot:
		var hand := at + Vector3.UP * 1.40
		var direction := controller.player.aim_dir() if side == controller.local_side else point_away_from_bench(at)
		var end := hand + direction * 5.4
		var surface := controller.world.raycast(hand, end)
		if not surface.is_empty():
			end = surface.position
		event["burst"] = [end.x, end.y, end.z]
	controller.apply_event(event)
	return event


func apply(event: Dictionary) -> void:
	var key := str(event.key)
	var side := int(event.side)
	var mine := side == controller.local_side
	var now := controller._now()
	var at := controller._action_pos(key)
	match key:
		"lobby_hatch":
			if not bool(event.get("shot", false)):
				_keys[side] &= ~KEY_BUNKER
			_open_lid(key)
		"pool_drain", "field_hatch":
			_open_lid(key)
		"cement":
			_consume(key)
			_cloud(at + Vector3.UP * 0.8, 2.7, 8.0, Color("#d6cbb4"))
			controller.world.sfx.play("crumble", at, 1.0)
		"air":
			_spent[key] = true
			_air_until = now + 3.3
			_air_velocity = Vector3(-19.0, 1.8, 2.0)
			_air_body.set_deferred("collision_layer", 0)
			controller.world.sfx.play("rocket", at, -3.0, 1.65)
		"gas":
			if bool(event.get("ignite", false)):
				_consume(key)
				_gas_until = 0.0
				_gas_event_sent = false
				_remove_cloud("gas")
				_effect_blast(at, 2.8)
			else:
				_gas_until = now + 12.0
				_cloud(at, 2.3, 12.0, Color("#aab490"), "gas")
				controller.world.sfx.loop("school_gas", "extinguisher", at, true, -8.0)
		"saw", "tesla":
			var duration := 6.5 if key == "saw" else 4.5
			_cooldowns[key] = now + duration + 5.0
			_hazards.append({"key": key, "at": at, "radius": 1.1 if key == "saw" else 2.1, "until": now + duration, "next": now})
			controller.world.sfx.loop("school_" + key, "engine" if key == "saw" else "extinguisher", at, true, -7.0, 1.75)
		"steam":
			_cooldowns[key] = now + 15.0
			_cloud(at + Vector3.UP, 3.1, 8.0, Color("#d5e4e7"))
			controller.world.sfx.play("extinguisher", at, -2.0)
		"dishes":
			_consume(key)
			controller.world.sfx.play("glass", at, 4.0, 1.25)
			controller.world.sfx.play("metal", at, -1.0, 1.4)
			controller.world.fx.dust(at, Color.WHITE, 0.48)
		"medkit":
			_consume(key)
			if mine:
				controller.player.health = minf(Player.MAX_HEALTH, controller.player.health + 55.0)
				controller._message("Аптечка · здоровье восстановлено")
		"tools":
			_consume(key)
			_tools[side] = true
			if mine:
				controller._message("Слесарный набор · один усиленный удар кувалдой")
		"picture":
			_picture_open = not _picture_open
			controller._set_target("picture", not _picture_open)
			controller._set_target("safe", _picture_open)
			controller.world.sfx.play("hide_wood", at, -6.0)
		"safe":
			_safe_open = true
			controller._set_target("safe", false)
			controller._set_target("director_key", true)
			_safe_shell.show()
			controller.world.sfx.play("metal", at, -5.0, 0.86)
		"director_key", "guard_key":
			_consume(key)
			_keys[side] |= KEY_BUNKER if key == "guard_key" else KEY_SERVICE
			if mine:
				controller._message("Ключ от убежища" if key == "guard_key" else "Ключ ПАЗа и щитовой")
		"phone":
			_cooldowns[key] = now + 10.0
			if mine:
				_phone()
		"spotlight":
			_spent[key] = true
			var lamp := controller.targets[key] as Node3D
			lamp.set_deferred("collision_layer", 0)
			var fall := create_tween()
			fall.tween_property(lamp, "position:y", 10.4, 0.52).set_trans(Tween.TRANS_QUAD)
			fall.parallel().tween_property(lamp, "rotation:z", 1.45, 0.52)
			fall.tween_callback(func(): _effect_blast(lamp.global_position, 1.2, false))
			controller._tweens["stage_light"] = fall
		"fixer":
			_consume(key)
			if event.has("burst"):
				var burst: Array = event.burst
				var destination := Vector3(burst[0], burst[1], burst[2])
				var vial := Build.vol(Vector3i(4, 7, 4))
				SchoolTrapProps.b(vial, Vector3i.ZERO, Vector3i(4, 5, 4), "glass")
				SchoolTrapProps.b(vial, Vector3i(1, 5, 1), Vector3i(2, 2, 2), "metal_blue")
				var thrown := DistrictSecretProps.model(self, vial, at)
				var round_seed := controller._seed
				var arc := create_tween()
				arc.tween_property(thrown, "position", (at + destination) * 0.5 + Vector3.UP * 0.67, 0.17)
				arc.tween_property(thrown, "position", destination, 0.18)
				arc.tween_callback(func():
					thrown.queue_free()
					if round_seed == controller._seed:
						_fixer_burst(destination))
			else:
				_fixer_burst(at)
		"reel":
			_consume(key)
			_cloud(at, 2.1, 11.0, Color("#686865"))
			controller.world.sfx.play("crumble", at, -4.0)
		"coal":
			if mine:
				controller.player._set_crouch(true)
				controller._message("В угле можно затаиться на 12 секунд")
			_cloud(at, 1.8, 12.0, Color("#494c49"), "coal")
		"mains":
			var shot := bool(event.get("shot", false)) or bool(event.get("button_shot", false))
			if not shot:
				_unlock_service(side)
			_cooldowns[key] = now + 3.0
			_power_on = false if shot else not _power_on
			for light in controller.school.interior_lights + controller.school.yard_lights:
				light.visible = _power_on
			for marker in controller._red_lamps:
				marker.visible = not _power_on
			controller.world.fx.sparks(at, Vector3.UP)
			controller.world.sfx.play("metal", at, -1.0)
		"fan":
			if mine:
				controller._follow(controller._paths.fan, true, true)
		"chimney":
			_spent[key] = true
			controller._set_target(key, false)
			controller._target("chimney_ride", at + Vector3(0, 0, -0.15), Vector3(0.85, 1.0, 0.35), "Пролезть к дымовой трубе")
		"wheel":
			controller.apply_event({"key": "racks", "side": side})
			_cooldowns[key] = now + 1.4
			for rack in controller._rails:
				_hazards.append({"key": "rails", "at": rack.global_position + Vector3.UP,
					"radius": 0.62, "until": now + 1.25, "next": now})
			controller.world.sfx.play("metal", at, 0.0)
		"microphone":
			if mine:
				controller._message("Громкая связь · удерживай %s рядом с микрофоном" % GameControls.key_name("voice_chat"))
		"loose_tile":
			_consume(key)
			controller.world.sfx.play("crumble", at, -0.7, 1.2)
			controller.world.fx.dust(at, Color("#aa9b8b"), 0.55)
		"piano", "bunk":
			_shove(key)
		"springboard":
			_cooldowns[key] = now + 3.0
			if mine:
				var launch := SchoolTrapProps.MODES[key][1] as Vector3
				controller._follow(PackedVector3Array([launch + Vector3(0, 1.5, -0.34),
					launch + Vector3(0, 3.75, -4.8), Vector3(47.7, 1.42, 10.1)]), true)
		"garage_lift", "garage_lift_low":
			_cooldowns["garage_lift"] = now + 1.75
			_garage_high = not _garage_high
			var rise := 2.45 if _garage_high else -2.45
			controller._animate("garage_lift", _garage_deck, _garage_deck.position + Vector3.UP * rise, 1.55)
			if is_instance_valid(_garage_bus) and _bus_over_platform():
				_garage_bus.freeze = true
				_garage_bus.linear_velocity = Vector3.ZERO
				_garage_bus.angular_velocity = Vector3.ZERO
				controller._animate("school_bus", _garage_bus, _garage_bus.position + Vector3.UP * rise, 1.55)
				if not _garage_high and not WebSession.connected:
					var bus := _garage_bus
					get_tree().create_timer(1.6).timeout.connect(func():
						if is_instance_valid(bus):
							bus.freeze = false)
			controller.world.sfx.play("metal", at, 0.0)


func _bus_over_platform() -> bool:
	var center := _garage_bus.world_center()
	return Vector2(center.x, center.z).distance_squared_to(Vector2(_garage_deck.position.x, _garage_deck.position.z)) < 1.7


func _phone() -> void:
	var game = controller.get_parent()
	for node in game.get_children():
		if node is NetworkHide and not node._am_seeker():
			var seeker: Player = node.nearest_hunter(controller.player.global_position)
			if not is_instance_valid(seeker):
				continue
			var pos := seeker.global_position
			var part := "спорткорпус" if pos.x > 32 and absf(pos.z) < 20 else ("корпус А" if pos.x < -10 else "корпус Б")
			var level := clampi(floori((pos.y - 2.05) / 3.8) + 1, 1, 4)
			var place := "подвал" if pos.y < 0 else (part + ", этаж %d" % level if absf(pos.z) < 31 and absf(pos.x) < 59 else "двор")
			controller._message("Пост охраны · ищущий сейчас в зоне: " + place)
			return
	controller._message("Пост охраны · ищущий вне наблюдения")


func _shove(key: String) -> void:
	_spent[key] = true
	controller._set_target(key, false)
	var prop := _moving[key].body as VoxelObject
	if not is_instance_valid(prop):
		return
	if WebSession.connected:
		controller._animate("shove/" + key, prop, prop.position + Vector3(0, -0.45 if key == "piano" else 0.0, -2.05), 0.65)
	else:
		prop.freeze = false
		prop.apply_central_impulse(Vector3(0, 0.3, -4.8) * prop.mass)
	controller.world.sfx.play("hide_wood", prop.global_position, -1.0)


func _open_lid(key: String) -> void:
	_spent[key] = true
	var body := _lids[key] as AnimatableBody3D
	body.hide()
	body.set_deferred("collision_layer", 0)
	controller._set_target(key, false)
	controller.world.sfx.play("metal", body.global_position, -4.0)


func _consume(key: String) -> void:
	_spent[key] = true
	controller._set_target(key, false)


func _effect_blast(at: Vector3, radius: float, terrain := true) -> void:
	var world := controller.world
	if terrain and not WebSession.connected:
		world.explode(at, radius, 6.8)
	else:
		world.fx.explosion(at, radius)
		world.sfx.play("explosion", at, 5.0)
		_hazards.append({"key": "impact", "at": at, "radius": radius, "until": controller._now() + 1.1, "next": 0.0})


func _flash() -> void:
	_flashes.color.a = 0.88
	create_tween().tween_property(_flashes, "color:a", 0.0, 1.7)


func point_away_from_bench(at: Vector3) -> Vector3:
	var direction := Vector3(at.x + 13.9, 0.0, at.z + 11.6).normalized()
	return Vector3.BACK if direction.is_zero_approx() else direction


func _fixer_burst(at: Vector3) -> void:
	controller.world.sfx.play("glass", at, -1.0)
	controller.world.fx.flash(at, Color("#b9daf9"), 2.0, 8.0, 0.2)
	var player := controller.player
	if player.global_position.distance_squared_to(at) < 45.0 and controller.world.raycast(at, player.camera.global_position).is_empty():
		_flash()


func _cloud(at: Vector3, radius: float, duration: float, color: Color, key := "") -> void:
	var model := Node3D.new()
	model.position = at
	add_child(model)
	var fog := SphereMesh.new()
	fog.radius = radius * 0.48
	fog.height = radius * 0.96
	fog.radial_segments = 13
	fog.rings = 8
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color;
void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float grain = sin(VERTEX.x * 4.1 + TIME) * sin(VERTEX.y * 5.3 - TIME * 0.6);
	ALBEDO = tint.rgb * (0.93 + grain * 0.13);
	ALPHA = smoothstep(0.0, 0.93, face) * 0.64;
}
"""
	material.shader = shader
	material.set_shader_parameter("tint", color)
	fog.material = material
	for i in 8:
		var puff := MeshInstance3D.new()
		puff.mesh = fog
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := i * TAU / 8.0
		puff.position = Vector3(cos(angle) * radius * 0.34, (i % 3 - 1) * 0.23, sin(angle) * radius * 0.34)
		model.add_child(puff)
	model.scale = Vector3.ONE * 0.16
	create_tween().tween_property(model, "scale", Vector3.ONE, 0.64)
	_clouds.append({"node": model, "at": at, "radius": radius, "until": controller._now() + duration, "key": key})


func _remove_cloud(key: String) -> void:
	for i in range(_clouds.size() - 1, -1, -1):
		if _clouds[i].key == key:
			_clouds[i].node.queue_free()
			_clouds.remove_at(i)


func tick(delta: float) -> void:
	var now := controller._now()
	var at := controller.player.global_position + Vector3.UP * 0.85
	var feet := controller.player.global_position
	if controller.player.movement_enabled and controller.player.is_sprinting() and not _spent.has("loose_tile"):
		if feet.distance_squared_to(controller._action_pos("loose_tile")) < 0.53 and now >= float(_cooldowns.get("loose_tile", 0.0)):
			controller._request("loose_tile")
			_cooldowns["loose_tile"] = now + 1.0
	for i in range(_clouds.size() - 1, -1, -1):
		if now >= _clouds[i].until:
			_clouds[i].node.queue_free()
			_clouds.remove_at(i)
	for i in range(_hazards.size() - 1, -1, -1):
		var danger := _hazards[i]
		if now >= danger.until:
			controller.world.sfx.loop("school_" + str(danger.key), "engine", danger.at, false)
			_hazards.remove_at(i)
			continue
		if danger.key == "tesla" and now >= danger.next:
			danger.next = now + 0.14
			controller.world.fx.sparks(Vector3(danger.at) + Vector3.UP * 0.8, Vector3.UP)
		if danger.key == "saw" and now >= danger.next:
			danger.next = now + 0.3
			controller.world.fx.sparks(Vector3(danger.at) + Vector3.UP * 0.21, Vector3.UP)
		if at.distance_squared_to(danger.at) < float(danger.radius) * float(danger.radius) and now - _last_hurt > 0.7:
			_last_hurt = now
			controller.player.damage(16.0 if danger.key == "tesla" else 11.0)
			controller.player.shake(0.42)
	if _air_until > now:
		var from := _air_body.global_position
		var to := from + _air_velocity * delta
		var hit := controller.world.raycast(from, to)
		if hit.is_empty():
			_air_body.global_position = to
			_air_body.rotate_z(delta * 4.0)
		else:
			_air_body.global_position = Vector3(hit.position) + Vector3(hit.normal) * 0.12
			_air_until = 0.0
			_effect_blast(_air_body.global_position, 0.82)
	if _gas_until > 0.0 and now >= _gas_until:
		_gas_until = 0.0
		controller.world.sfx.loop("school_gas", "extinguisher", controller._action_pos("gas"), false)
	_fire_poll -= delta
	if _fire_poll <= 0.0 and controller.world.network_role != 2 and controller.world.fire.count() > 0:
		_fire_poll = 0.35
		for point in controller.world.fire.visual_positions():
			if _gas_until > now and not _gas_event_sent and point.distance_squared_to(controller._action_pos("gas")) < 4.0:
				_gas_event_sent = true
				controller._request("gas", true)
			if not _spent.has("reel") and point.distance_squared_to(controller._action_pos("reel")) < 2.5:
				controller._request("reel", true)
			if not _paper_smoke and point.distance_squared_to(Vector3(-13.4, 10.72, 25.5)) < 16.0:
				_paper_smoke = true
				_cloud(point + Vector3.UP * 0.6, 2.7, 11.0, Color("#7b6c61"))
				controller.world.fire.ignite_near(controller.school.wings[Vector2i(0, 2)], point, 2.5, 8)


func obscures(from: Vector3, to: Vector3) -> bool:
	for cover in controller.school.greenhouse_cover:
		if to.distance_squared_to(cover) < 0.74 and from.distance_squared_to(cover) > 1.09:
			return true
	var curtain: Variant = Plane(Vector3.BACK, -11.0).intersects_segment(from, to)
	if curtain != null and absf(curtain.x - 50.5) < 2.25 and curtain.y < -1.15:
		return true
	for cloud in _clouds:
		var point: Vector3 = cloud.at
		var closest := Geometry3D.get_closest_point_to_segment(point, from, to)
		if point.distance_squared_to(closest) < float(cloud.radius) * float(cloud.radius):
			return true
	return false


func slowed(at: Vector3) -> bool:
	for danger in _hazards:
		if at.distance_squared_to(danger.at) < float(danger.radius) * float(danger.radius):
			return true
	return false


func hammer_multiplier() -> float:
	return 1.48 if _tools[controller.local_side] else 1.0


func spend_hammer_boost() -> void:
	var side := controller.local_side
	if _tools[side]:
		_tools[side] = false
		controller._message("Слесарный набор использован")


func _can_use_service_lock(side: int) -> bool:
	return _service_unlocked or (_keys[side] & KEY_SERVICE) != 0


func _unlock_service(side: int) -> void:
	if _service_unlocked:
		return
	_keys[side] &= ~KEY_SERVICE
	_service_unlocked = true
	if side == controller.local_side:
		controller._message("ПАЗ и щитовая разблокированы")


func can_board() -> bool:
	return (_can_use_service_lock(controller.local_side) and not _garage_high
		and controller._now() >= float(_cooldowns.get("garage_lift", 0.0)))


func unlock_for_boarding() -> bool:
	if not can_board():
		return false
	_unlock_service(controller.local_side)
	return true


func carried_items(side: int) -> Array[int]:
	var items: Array[int] = []
	if (_keys[side] & KEY_BUNKER) != 0:
		items.append(0)
	if (_keys[side] & KEY_SERVICE) != 0:
		items.append(1)
	if _tools[side]:
		items.append(2)
	return items


func reset() -> void:
	for key in _spent:
		controller._set_target(key, true)
	for key: String in _lids:
		var lid := _lids[key] as AnimatableBody3D
		lid.show()
		lid.set_deferred("collision_layer", Layers.STATIC)
	if controller.targets.has("chimney_ride"):
		controller.targets.chimney_ride.queue_free()
		controller.targets.erase("chimney_ride")
	_spent.clear()
	_cooldowns.clear()
	_keys.resize(RoomRules.SIDES)
	_keys.fill(0)
	_service_unlocked = false
	_tools.resize(RoomRules.SIDES)
	_tools.fill(false)
	for cloud in _clouds:
		cloud.node.queue_free()
	_clouds.clear()
	for hazard in _hazards:
		controller.world.sfx.loop("school_" + str(hazard.key), "engine", hazard.at, false)
	_hazards.clear()
	if _gas_until > 0.0:
		controller.world.sfx.loop("school_gas", "extinguisher", controller._action_pos("gas"), false)
	_gas_until = 0.0
	_gas_event_sent = false
	_paper_smoke = false
	_air_until = 0.0
	_air_body.global_position = SchoolTrapProps.MODES.air[1] + Vector3.UP * 0.85
	_air_body.rotation = Vector3.ZERO
	var stage_light := controller.targets.spotlight as Node3D
	stage_light.global_position = SchoolTrapProps.MODES.spotlight[1] + Vector3.UP * 0.45
	stage_light.rotation = Vector3.ZERO
	_picture_open = false
	_safe_open = false
	_safe_shell.hide()
	controller._set_target("picture", true)
	controller._set_target("safe", false)
	controller._set_target("director_key", false)
	_power_on = true
	for light in controller.school.interior_lights + controller.school.yard_lights:
		light.show()
	if is_instance_valid(_garage_bus) and (WebSession.connected or _garage_high):
		_garage_bus.transform = _garage_home
		_garage_bus.linear_velocity = Vector3.ZERO
		_garage_bus.angular_velocity = Vector3.ZERO
		_garage_bus.freeze = WebSession.connected
	_garage_high = false
	_garage_deck.position.y = 1.89
	for key: String in _moving:
		var prop := _moving[key].body as VoxelObject
		if is_instance_valid(prop):
			prop.position = _moving[key].at
			prop.linear_velocity = Vector3.ZERO
