class_name GameGadgets
extends Node3D

signal requested(action: String, slot: int)
signal confirmed(event: Dictionary)

enum { FLASH, FIRE, SODA, CLOCK }
const TITLES := ["Светошумовая", "Огненный коктейль", "Газировка", "Часы"]
const TOOL_HINTS := ["ЛКМ — бросить светошумовую", "ЛКМ — бросить огненный коктейль",
	"ЛКМ — выпить и ускориться", "ЛКМ — остановить время"]
const TINTS := [Color("#efe5bf"), Color("#fa8250"), Color("#68e1cf"), Color("#ceb2ff")]
const STOCK := 30.0
const CLOCK_DURATION := 3.5
const BOOST_DURATION := 8.0
const FLASH_DURATION := 5.0
const REACH := 2.65

var world: VoxelWorld
var main: Node3D
var pause_menu: PauseMenu
var local_side := 0
var dispenser_enabled := true
var inventories: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0])]
var boost_until := [0.0, 0.0]
var clock_owner := -1
var clock_until := 0.0
var _clock_start := 0.0
var _clock_elapsed := 0.0
var _flash_until := 0.0
var _vend_until := 0.0
var _use_until := [0.0, 0.0]
var _map: FullMap
var map_data: MapSession
var _mini_map: MapCanvas
var _veil: ColorRect
var _vending_at: Vector3
var button: StaticBody3D
var _press: SchoolButton
var _pickups := {}
var _throws := {}
var _next_throw := 0
var _rigids := {}
var _paused := {}
var _paused_tweens: Array[Tween] = []
var _meshes: Array[Mesh] = []


func _ready() -> void:
	local_side = WebSession.local_side
	dispenser_enabled = not WebSession.connected or bool(WebSession.rules.gadgets)
	inventories.resize(RoomRules.SIDES)
	for side in inventories.size():
		inventories[side] = PackedInt32Array([0, 0, 0, 0])
	boost_until.resize(RoomRules.SIDES)
	boost_until.fill(0.0)
	_use_until.resize(RoomRules.SIDES)
	_use_until.fill(0.0)
	var at := Vector3(7, TestLevel.GY, 23)
	match GameState.level:
		GameState.LEVEL_DISTRICT: at = DistrictSecretProps.VENDING
		GameState.LEVEL_SCHOOL: at = Vector3(50, 2.2, -14.18)
		GameState.LEVEL_HIDE: at = Vector3(3.4, 1.0, 9.0)
	_vending_at = at
	DistrictSecretProps.model(self, DistrictSecretProps.vending(), at, true, 0, "Автомат гаджетов")
	button = _trigger(at + Vector3(0.36, 1.03, 0.423), Vector3(0.24, 0.24, 0.17))
	button.set_meta("gadget_dispenser", true)
	_press = SchoolButton.install(button, Vector3(0.25, 0.25, 0.19), Vector3.BACK, SchoolButton.models())
	for item in TITLES.size():
		var v := GadgetModels.volume(item)
		_meshes.append(VoxModel.mesh(v, 0.017, Vector3(v.get_size()) * 0.5))
	var overlay := CanvasLayer.new()
	overlay.layer = 11
	add_child(overlay)
	map_data = MapSession.new()
	map_data.gadgets = self
	add_child(map_data)
	_mini_map = MapCanvas.new()
	_mini_map.miniature = true
	_mini_map.data = map_data
	_mini_map.open_requested.connect(_open_navigation)
	overlay.add_child(_mini_map)
	_mini_map.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	GameState.settings_changed.connect(_map_preferences)
	get_window().size_changed.connect(_map_preferences)
	_map_preferences()
	_map = FullMap.new()
	_map.controller = self
	_map.data = map_data
	overlay.add_child(_map)
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.hide()
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.hide()
	map_data.ensure_atlas.call_deferred()


func _map_preferences() -> void:
	var settings: Dictionary = GameState.map_options
	var pixels: float = settings["size"]
	var width := get_window().size.x
	if width > 0 and width <= 1024:
		pixels *= 1.16
	_mini_map.offset_left = 22.0
	_mini_map.offset_right = 22.0 + pixels
	var touch_margin := 195.0 if world.player.touch_mode else 58.0
	_mini_map.offset_top = -touch_margin - pixels
	_mini_map.offset_bottom = -touch_margin
	_mini_map.modulate.a = settings.opacity
	_mini_map.visible = bool(settings.visible) and not pause_menu.is_open() and not world.player.navigation_menu_open


func _open_navigation() -> void:
	var player := world.player
	if not player.navigation_menu_open and not player.dead and not pause_menu.is_open() and GameState.cinematic.is_empty():
		_map.open_map()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_map") and not event.is_echo():
		_open_navigation()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_zoom") and not event.is_echo() and not world.player.navigation_menu_open and not pause_menu.is_open():
		GameState.map_options.zoom = (int(GameState.map_options.zoom) + 1) % 3
		GameState.save_graphics()
		get_viewport().set_input_as_handled()


func _trigger(at: Vector3, extent: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = Layers.SECRET
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extent
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body


func is_dispenser_hit(hit: Dictionary) -> bool:
	return dispenser_enabled and not hit.is_empty() and hit.collider == button


func hint(hit: Dictionary) -> String:
	if is_dispenser_hit(hit):
		var wait := ceili(_vend_until - scene_time())
		return "Выдача через %d с" % wait if wait > 0 else "%s — выдать гаджеты" % GameControls.key_name("grab")
	if not hit.is_empty() and hit.collider.has_meta("gadget_pickup"):
		var slot := int(hit.collider.get_meta("gadget_pickup"))
		if _pickups.has(slot):
			var item := int(_pickups[slot].item)
			if inventories[local_side][item] >= _pack_count(item):
				return "Запас уже полный"
			return "%s — взять · %s" % [GameControls.key_name("grab"), TITLES[item]]
	return ""


func interact() -> bool:
	var hit := world.player.aim_ray(REACH, DistrictSecrets.MASK)
	if is_dispenser_hit(hit):
		request("vend")
		return true
	if not hit.is_empty() and hit.collider.has_meta("gadget_pickup"):
		request("take", int(hit.collider.get_meta("gadget_pickup")))
		return true
	return false


func shoot_dispenser(source: Player, hit: Dictionary) -> void:
	if not WebSession.connected:
		request("vend")
	elif WebSession.is_host:
		var side := WebSession.local_side if source == world.player else int(source.get_meta("room_side", 1))
		authorize("shot", 0, side, source.global_position, source.camera.global_position, source.aim_dir(), hit.collider)


func request(action: String, slot := -1) -> void:
	if WebSession.connected:
		requested.emit(action, slot)
	else:
		var p := world.player
		authorize(action, slot, 0, p.global_position, p.camera.global_position, p.aim_dir())


func use(item: int) -> void:
	var p := world.player
	if p.movement_enabled and not p.dead and not p.vehicle and not p.navigation_menu_open and not p.transit_active and not local_frozen():
		request("use", item)


func authorize(action: String, slot: int, side: int, feet: Vector3, eye: Vector3, aim: Vector3,
		verified: CollisionObject3D = null) -> void:
	if not dispenser_enabled or side < 0 or side >= inventories.size() or not feet.is_finite() or not eye.is_finite() or not aim.is_finite() or frozen_for(side):
		return
	var now := scene_time()
	var event := {"action": action, "slot": slot, "side": side}
	match action:
		"vend", "shot":
			if now < _vend_until or clock_active() and action == "shot":
				return
			if action == "shot":
				if verified != button or eye.distance_squared_to(button.global_position) > 46.0 * 46.0:
					return
			elif not _can_reach(button, eye):
				return
			event.action = "vend"
			event["item"] = randi_range(FLASH, CLOCK)
		"take":
			if not _pickups.has(slot):
				return
			var drop: Dictionary = _pickups[slot]
			if not _can_reach(drop.node, eye) or inventories[side][drop.item] >= _pack_count(drop.item):
				return
			event["item"] = drop.item
		"use":
			if slot < 0 or slot >= TITLES.size() or inventories[side][slot] <= 0 or _real_time() < float(_use_until[side]):
				return
			if slot == CLOCK and clock_active():
				return
			if slot in [FLASH, FIRE]:
				_next_throw += 1
				event["id"] = _next_throw
				event["at"] = _pack(eye + aim.normalized() * 0.12)
				event["velocity"] = _pack(aim.normalized() * 13.0 + Vector3.UP * 2.1)
		_:
			return
	_commit(event)


func _can_reach(body: StaticBody3D, eye: Vector3) -> bool:
	if eye.distance_squared_to(body.global_position) > (REACH + 0.18) * (REACH + 0.18):
		return false
	var hit := world.raycast(eye, body.global_position, DistrictSecrets.MASK)
	return hit.get("collider") == body


func _commit(event: Dictionary) -> void:
	apply_event(event)
	confirmed.emit(event)


func apply_event(event: Dictionary) -> void:
	var side := int(event.side)
	var slot := int(event.slot)
	if side < 0 or side >= inventories.size():
		return
	match str(event.action):
		"vend":
			if int(event.item) < FLASH or int(event.item) > CLOCK:
				return
			_vend_until = scene_time() + STOCK
			_dispense(int(event.item))
		"take":
			if int(event.item) < FLASH or int(event.item) > CLOCK:
				return
			if _pickups.has(slot):
				var drop: Dictionary = _pickups[slot]
				drop.node.collision_layer = 0
				drop.node.queue_free()
				_pickups.erase(slot)
			var item := int(event.item)
			inventories[side][item] += 1
			if side == local_side:
				world.player.tools.refresh_slots()
				world.sfx.play_ui("click", -6.0)
		"use":
			if slot < FLASH or slot > CLOCK:
				return
			inventories[side][slot] = maxi(0, inventories[side][slot] - 1)
			_use_until[side] = _real_time() + 0.42
			if slot in [FLASH, FIRE]:
				_throw(int(event.id), slot, side, _unpack(event.at), _unpack(event.velocity))
			elif slot == SODA:
				boost_until[side] = scene_time() + BOOST_DURATION
				if side == local_side:
					world.sfx.play_ui("metal", -8.0, 1.6)
			elif slot == CLOCK:
				_start_clock(side)
			if side == local_side:
				world.player.tools.refresh_slots()
		"impact":
			var point := _unpack(event.at)
			if _throws.has(slot):
				_throws[slot].node.queue_free()
				_throws.erase(slot)
			if int(event.item) == FLASH:
				_flash_impact(side, point)
			else:
				_fire_impact(point)


func _pack_count(item: int) -> int:
	return 1 if item == SODA else 3


func viewmodel(item: int) -> MeshInstance3D:
	var model := _mesh(item)
	model.scale = Vector3.ONE * 0.78
	model.position = Vector3(-0.04, 0.04, -0.08)
	model.rotation.y = -0.24
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


func _mesh(item: int) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _meshes[item]
	return mesh


func _dispense(item: int) -> void:
	_clear_pickups()
	_press.push()
	world.sfx.play("metal", _vending_at, -5.0)
	for slot in _pack_count(item):
		var start := _vending_at + Vector3(0, 0.68, 0.42)
		var at := _vending_at + Vector3((slot - 1) * 0.37 if _pack_count(item) > 1 else 0.0, 0.26, 0.83)
		var body := _trigger(at, Vector3(0.34, 0.48, 0.40))
		body.set_meta("gadget_pickup", slot)
		var mesh := _mesh(item)
		mesh.position = start - at
		body.add_child(mesh)
		var tween := body.create_tween()
		tween.tween_property(mesh, "position", Vector3.ZERO, 0.25 + slot * 0.08).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(mesh, "rotation:y", 0.6 + slot * 0.44, 0.28)
		_pickups[slot] = {"node": body, "item": item}


func _throw(id: int, item: int, side: int, at: Vector3, velocity: Vector3) -> void:
	var mesh := _mesh(item)
	mesh.position = at
	add_child(mesh)
	_throws[id] = {"node": mesh, "item": item, "side": side, "velocity": velocity, "age": 0.0, "landed": false}
	world.sfx.play("throw", at, -5.0)


func _physics_process(delta: float) -> void:
	if clock_owner >= 0:
		if not clock_active():
			_finish_clock()
		else:
			_freeze_rigids()
	for id: int in _throws.keys():
		var flight: Dictionary = _throws[id]
		if clock_active() and int(flight.side) != clock_owner:
			continue
		flight.age += delta
		var mesh: MeshInstance3D = flight.node
		var from := mesh.global_position
		var next: Vector3 = from
		if not flight.landed:
			flight.velocity += Vector3.DOWN * 16.0 * delta
			next += Vector3(flight.velocity) * delta
			var hit := world.raycast(from, next)
			if not hit.is_empty():
				flight.landed = true
				next = hit.position + hit.normal * 0.095
			mesh.global_position = next
			mesh.rotation.x += delta * 8.0
		var item := int(flight.item)
		var burst: bool = (flight.landed or flight.age > 2.6) if item == FIRE else flight.age > 1.25
		if burst and world.network_role != 2:
			_commit({"action": "impact", "slot": id, "side": flight.side, "item": item, "at": _pack(next)})


func _flash_impact(side: int, at: Vector3) -> void:
	world.sfx.play("impact", at, 2.5, 1.8, 14.0)
	world.fx.sparks(at, Vector3.UP)
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = Color("#edf2ff")
	light.omni_range = 14.0
	light.light_energy = 4.5
	add_child(light)
	var fade := light.create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.18)
	fade.tween_callback(light.queue_free)
	if side == local_side:
		return
	var view := world.player.camera
	var towards := at - view.global_position
	if towards.length_squared() > 21.0 * 21.0 or -view.global_basis.z.dot(towards.normalized()) < 0.58:
		return
	if world.raycast(view.global_position, at, Layers.SOLID | Layers.CLOTH).is_empty():
		_flash_until = _real_time() + FLASH_DURATION


func _fire_impact(at: Vector3) -> void:
	world.sfx.play("glass", at, 1.0)
	world.fx.flash(at, Color("#ff9456"), 2.4, 5.5, 0.28)
	world.fx.sparks(at, Vector3.UP)
	world.fx.dust(at, Color("#fa9260"), 0.6)
	if world.network_role == 2:
		return
	world.fire.surface_flames(at)
	for object in world.objects_in_sphere(at, 2.6).slice(0, 16):
		world.fire.ignite_near(object, at, 2.6, 6)


func _real_time() -> float:
	return Time.get_ticks_msec() * 0.001


func scene_time() -> float:
	var now := _real_time()
	return now - _clock_elapsed - clampf(now - _clock_start, 0, CLOCK_DURATION) if clock_owner >= 0 else now - _clock_elapsed


func clock_active() -> bool:
	return clock_owner >= 0 and _real_time() < clock_until


func frozen_for(side: int) -> bool:
	return clock_active() and side != clock_owner


func local_frozen() -> bool:
	return frozen_for(local_side)


func speed_multiplier() -> float:
	return 1.4 if scene_time() < float(boost_until[local_side]) else 1.0


func _start_clock(side: int) -> void:
	_clock_start = _real_time()
	clock_until = _clock_start + CLOCK_DURATION
	clock_owner = side
	for node in [world.fire, world.debris]:
		_paused[node] = node.is_processing()
		node.set_process(false)
	if world.secrets is SchoolSecrets:
		var ball := (world.secrets as SchoolSecrets).football
		_paused[ball] = ball.is_physics_processing()
		ball.set_physics_process(false)
	_freeze_rigids()
	if is_instance_valid(world.secrets):
		_hold_tween(world.secrets._travel)
		for animation: Tween in world.secrets._tweens.values():
			_hold_tween(animation)
		if world.secrets is SchoolSecrets:
			_hold_tween(world.secrets.elevator._motion)
	for body in world.objects:
		if is_instance_valid(body):
			var door := body.get_node_or_null("DistrictDoor") as DistrictDoor
			if door:
				_hold_tween(door._animation)
	world.sfx.play_ui("transit", -2.0, 0.7)


func _hold_tween(animation: Tween) -> void:
	if is_instance_valid(animation) and animation.is_running() and animation not in _paused_tweens:
		animation.pause()
		_paused_tweens.append(animation)


func _freeze_rigids() -> void:
	for body in world.objects:
		if is_instance_valid(body) and not body.static_mode and not body.held and not body.freeze:
			_freeze_body(body)
	for child in world.get_children():
		if child is Projectiles.PipeBomb and not child.freeze:
			_freeze_body(child)
			child.set_process(false)
		elif child is Projectiles.Rocket and not _paused.has(child):
			_paused[child] = child.is_physics_processing()
			child.set_physics_process(false)
	if world.secrets is SchoolSecrets and not world.secrets.football.freeze:
		_freeze_body(world.secrets.football)


func _freeze_body(body: RigidBody3D) -> void:
	if _rigids.has(body):
		return
	_rigids[body] = [body.linear_velocity, body.angular_velocity, body.sleeping]
	body.freeze = true


func _finish_clock() -> void:
	_clock_elapsed += clampf(_real_time() - _clock_start, 0, CLOCK_DURATION)
	clock_owner = -1
	for body in _rigids:
		if not is_instance_valid(body):
			continue
		var state: Array = _rigids[body]
		body.freeze = false
		body.linear_velocity = state[0]
		body.angular_velocity = state[1]
		body.sleeping = state[2]
		if body is Projectiles.PipeBomb:
			body.set_process(true)
	_rigids.clear()
	for node in _paused:
		if is_instance_valid(node):
			if node is Projectiles.Rocket or node is SchoolFootball:
				node.set_physics_process(_paused[node])
			else:
				node.set_process(_paused[node])
	_paused.clear()
	for animation in _paused_tweens:
		if is_instance_valid(animation) and animation.is_valid():
			animation.play()
	_paused_tweens.clear()


func _process(_delta: float) -> void:
	_mini_map.visible = bool(GameState.map_options.visible) and not world.player.navigation_menu_open and not world.player.dead \
		and not pause_menu.is_open() and GameState.cinematic.is_empty()
	var remaining := _flash_until - _real_time()
	_veil.visible = remaining > 0.0 or clock_active()
	if remaining > 0.0:
		_veil.color = Color(0.98, 0.98, 1.0, smoothstep(0.0, 1.45, remaining))
	elif clock_active():
		_veil.color = Color(0.32, 0.26, 0.65, 0.24 if local_frozen() else 0.09)


func _clear_pickups() -> void:
	for drop in _pickups.values():
		drop.node.collision_layer = 0
		drop.node.queue_free()
	_pickups.clear()


func reset_round() -> void:
	if clock_owner >= 0:
		_finish_clock()
	for side in inventories.size():
		inventories[side].fill(0)
	boost_until.fill(0.0)
	_use_until.fill(0.0)
	_vend_until = 0.0
	_flash_until = 0.0
	_map.close_map()
	map_data.reset_round()
	world.player.tools.refresh_slots()
	_clear_pickups()
	for flight in _throws.values():
		flight.node.queue_free()
	_throws.clear()


func _pack(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _unpack(data: Array) -> Vector3:
	return Vector3(data[0], data[1], data[2])
