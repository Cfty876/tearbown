class_name Hud
extends CanvasLayer
## Crosshair, tool bar, help panel and the performance overlay (F3).

var player: Player
var world: VoxelWorld
var quality_name := ""

var _cross: Control
var _inventory: ToolInventory
var _hint: Label
var _interaction_prompt: InteractionPrompt
var _prompt_object: Node3D
var _prompt_local := Vector3.ZERO
var _prompt_message := ""
var _prompt_needs_aim := false
var _gadget_label: Label
var _charge_panel: PanelContainer
var _charge_meter: ProgressBar
var _charge_label: Label
var _stats: Label
var _help: Label
var _msg: Label
var _msg_t := 0.0
var _show_stats := true
var _frame_ms := PackedFloat32Array()
var _fps_acc := 0.0
var _fps_frames := 0
var _fps := 0.0
var _worst_ms := 0.0
var _avg_ms := 0.0
var _vignette: ColorRect
var _hp_bg: ColorRect
var _hp: ColorRect
var _grab_key := "E"
var _horn_locator: HornLocator


func _ready() -> void:
	layer = 10
	add_to_group("hud")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0.6, 0.02, 0.0, 0.0)
	root.add_child(_vignette)
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.45)
	_hp_bg.size = Vector2(260, 14)
	root.add_child(_hp_bg)
	_hp = ColorRect.new()
	_hp.color = Color(0.92, 0.25, 0.2, 0.9)
	_hp.position = Vector2(2, 2)
	_hp.size = Vector2(256, 10)
	_hp_bg.add_child(_hp)

	_cross = Crosshair.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(_cross)

	_inventory = ToolInventory.new()
	_inventory.player = player
	_inventory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = _label(root, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -40
	_hint.offset_bottom = -16
	_hint.offset_left = -600
	_hint.offset_right = 600
	_hint.modulate = Color(1, 1, 1, 0.75)

	_interaction_prompt = InteractionPrompt.new()
	root.add_child(_interaction_prompt)
	_gadget_label = _label(root, 17, HORIZONTAL_ALIGNMENT_LEFT)
	_gadget_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_gadget_label.offset_left = 30
	_gadget_label.offset_top = -146
	_gadget_label.hide()

	_charge_panel = PanelContainer.new()
	_charge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_charge_panel.offset_left = 30
	_charge_panel.offset_right = 280
	_charge_panel.offset_top = -121
	_charge_panel.offset_bottom = -66
	_charge_panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#151b22ec"), Color("#58626c")))
	root.add_child(_charge_panel)
	var charge_layout := VBoxContainer.new()
	charge_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_panel.add_child(charge_layout)
	_charge_label = _label(charge_layout, 18, HORIZONTAL_ALIGNMENT_LEFT)
	_charge_meter = ProgressBar.new()
	_charge_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_meter.max_value = 1.0
	_charge_meter.step = 0.0
	_charge_meter.show_percentage = false
	_charge_meter.custom_minimum_size.y = 7
	_charge_meter.add_theme_stylebox_override("background", MenuStyle.panel(Color("#313b43"), Color.TRANSPARENT, 3))
	_charge_meter.add_theme_stylebox_override("fill", MenuStyle.panel(Color("#83d3e5"), Color.TRANSPARENT, 3))
	charge_layout.add_child(_charge_meter)
	_charge_panel.hide()

	_stats = _label(root, 14, HORIZONTAL_ALIGNMENT_LEFT)
	_show_stats = false
	_stats.visible = _show_stats
	_stats.position = Vector2(14, 10)
	_help = _label(root, 15, HORIZONTAL_ALIGNMENT_LEFT)
	_help.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_help.offset_left = -550
	_help.offset_right = -18
	_help.offset_top = 10
	_help.visible = false
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_controls()
	GameState.settings_changed.connect(_refresh_controls)
	_msg = _label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_msg.offset_top = 120
	_msg.offset_left = -500
	_msg.offset_right = 500
	root.add_child(_inventory)
	_horn_locator = HornLocator.new()
	root.add_child(_horn_locator)


func show_horn(at: Vector3) -> void:
	_horn_locator.mark(at)
	if is_instance_valid(world.gadgets):
		world.gadgets.map_data.record_horn(at)


func clear_horn() -> void:
	_horn_locator.clear()


func _refresh_controls() -> void:
	_grab_key = GameControls.key_name("grab")
	_help.text = "%s / %s / %s / %s — движение   ·   %s — бег   ·   %s — прыжок\n%s — присесть   ·   %s — снаряжение   ·   1–9 / колесо — инструмент\nЛКМ — действие   ·   %s — взаимодействие   ·   %s — телепорт\nF11 — экран   ·   Esc — пауза" % [
		GameControls.key_name("move_forward"), GameControls.key_name("move_left"), GameControls.key_name("move_back"),
		GameControls.key_name("move_right"), GameControls.key_name("sprint"), GameControls.key_name("jump"),
		GameControls.key_name("crouch"), GameControls.key_name("tool_inventory"), _grab_key, GameControls.key_name("teleport"),
	]
	_help.text += "\n%s — карта   ·   %s — масштаб мини-карты" % [GameControls.key_name("open_map"), GameControls.key_name("map_zoom")]
	if GameState.level in [GameState.LEVEL_DISTRICT, GameState.LEVEL_SCHOOL]:
		_help.text += "\n%s — пневматика" % GameControls.key_name("secret_shot")
		if WebSession.connected and not OS.has_feature("web"):
			_help.text += "   ·   удерживай %s — голос" % GameControls.key_name("voice_chat")


func _label(parent: Control, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func message(text: String, seconds := 2.5) -> void:
	_msg.text = text
	_msg_t = seconds


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif e.is_action_pressed("toggle_stats"):
		_show_stats = not _show_stats


func _process(delta: float) -> void:
	_msg_t -= delta
	_msg.visible = _msg_t > 0.0
	var ms := delta * 1000.0
	_fps_acc += delta
	_fps_frames += 1
	_worst_ms = maxf(_worst_ms, ms)
	if _fps_acc >= 0.5:
		_fps = _fps_frames / _fps_acc
		_avg_ms = _fps_acc * 1000.0 / _fps_frames
		_fps_acc = 0.0
		_fps_frames = 0
		_update_stats()
		_worst_ms = 0.0
	if player == null:
		return
	_vignette.color.a = 0.65 if player.dead else player.hurt * 0.4
	_hp.size.x = 256.0 * player.health / Player.MAX_HEALTH
	_hp_bg.visible = player.health < Player.MAX_HEALTH or player.dead
	_hp_bg.position = Vector2(30, get_viewport().get_visible_rect().size.y - 46)
	var utility_left := 30.0
	if is_instance_valid(world.gadgets) and world.gadgets._mini_map.visible:
		utility_left = world.gadgets._mini_map.get_rect().end.x + 12.0
	_charge_panel.offset_left = utility_left
	_charge_panel.offset_right = utility_left + 250.0
	_gadget_label.offset_left = utility_left
	_cross.visible = not _inventory.is_open
	_hint.visible = not _inventory.is_open
	var charge := player.tools.extinguisher_charge
	_charge_panel.visible = player.tools.current == PlayerTools.EXTINGUISHER and player.vehicle == null and player.possessed_npc == null and not player.dead and not _inventory.is_open
	if _charge_panel.visible:
		_charge_meter.value = charge
		_charge_label.text = "ДАВЛЕНИЕ  %d%%" % roundi(charge * 100.0) if charge > 0.0 else "УБЕРИ ДЛЯ ЗАПРАВКИ"
	_update_gadget_status()
	_interaction_prompt.hide()
	if _inventory.is_open:
		return
	var t := player.tools
	var hint := PlayerTools.hint_for(t.current)
	if t.current == PlayerTools.BOOMBOX:
		hint += "   ·   %s — кассеты   ·   %s — поставить" % [GameControls.key_name("cassette_library"), GameControls.key_name("place_boombox")]
	if player.movement_enabled and not player.dead and not player.vehicle and not player.grabbed and player.possessed_npc == null and not player.clock_locked() and not player.transit_active:
		_update_object_prompt()
	else:
		_prompt_object = null
	if is_instance_valid(player.possessed_npc):
		var seat_action := "встать" if player.possessed_npc.seating_camera().is_finite() else "сесть"
		hint = "%s  ·  %s — %s  ·  %s — выйти" % [SchoolPopulation.ROLES[player.possessed_npc.role],
			GameControls.key_name("crouch"), seat_action, _grab_key]
	elif player.vehicle and is_instance_valid(player.vehicle):
		var exit_hint := "выйти / поставить на колёса" if player.vehicle.tipped() else "выйти"
		hint = "%d км/ч   ·   %s — %s   ·   мышь — камера" % [roundi(absf(player.vehicle.speed) * 3.6), _grab_key, exit_hint]
	elif player.grabbed:
		hint = "Предмет %.0f кг   ·   ЛКМ — бросить   ·   %s — отпустить" % [player.grabbed.mass, _grab_key]
	else:
		var hit := player.aim_ray(3.2)
		if not hit.is_empty() and hit.collider is VoxelObject:
			var o: VoxelObject = hit.collider

			var vox := o.voxel_at_hit(hit.position, hit.normal)
			if vox > 0:
				var mat := VoxMat.material_of(vox)
				hint += "   |   %s" % VoxMat.NAMES.get(mat, "?")

	if _hint.text != hint:
		_hint.text = hint
	(_cross as Crosshair).grab_hint = player.grabbed != null


func _update_object_prompt() -> void:
	var hit := player.aim_ray(2.65, DistrictSecrets.MASK)
	var object: Node3D
	var point := Vector3.ZERO
	var message := ""
	var needs_aim := false
	var placed := world.boombox.pickup_target() if is_instance_valid(world.boombox) else null
	if is_instance_valid(placed):
		object = placed
		point = placed.global_position + Vector3.UP * 0.30
		message = "%s — отключить и забрать" % _grab_key if world.boombox.on_air() else "%s — подобрать бумбокс" % _grab_key
		needs_aim = true
	if message.is_empty() and player.tools.current == PlayerTools.POSSESSOR and player.possessed_npc == null and is_instance_valid(world.population):
		var npc := world.population.aim_target(player)
		if npc:
			object = npc
			point = npc.global_position + Vector3.UP * (npc._height + 0.23)
			var role: String = SchoolPopulation.ROLES[npc.role]
			message = "%s · недоступен" % role if npc.offended or npc.holder >= 0 else "%s · огонь — вселиться" % role
			needs_aim = true
	if is_instance_valid(player.hides):
		var id := player.hides.target()
		if id >= 0 and message.is_empty():
			var info: Dictionary = player.hides.spots[id]
			object = info.building
			point = player.hides.panel_focus(info)
			message = player.hides.hint(id)
	if message.is_empty() and not hit.is_empty():
		object = hit.collider
		point = hit.position + hit.normal * 0.045
		message = world.gadgets.hint(hit) if is_instance_valid(world.gadgets) else ""
		needs_aim = object.has_meta("gadget_pickup")
		if message.is_empty() and is_instance_valid(world.secrets):
			message = world.secrets.hint(hit)
	if message.is_empty():
		var solid := player.aim_ray(Player.VEHICLE_RANGE)
		match player.object_action(solid):
			"door":
				var door := solid.collider.get_node("DistrictDoor") as DistrictDoor
				message = "%s — %s дверь" % [_grab_key, "закрыть" if door.opened else "открыть"]
			"vehicle":
				message = "%s — сесть за руль" % _grab_key
			"vehicle_locked":
				message = "%s — проверить замок ПАЗа" % _grab_key
			"grab":
				message = "%s — взять предмет" % _grab_key
		if not message.is_empty():
			object = solid.collider
			point = solid.position + solid.normal * 0.045
			needs_aim = true
	if not message.is_empty() and is_instance_valid(object):
		if object != _prompt_object:
			_prompt_object = object
			_prompt_local = object.to_local(point)
		_prompt_message = message
		_prompt_needs_aim = needs_aim
	elif _prompt_needs_aim:
		_prompt_object = null
	elif is_instance_valid(_prompt_object):
		point = _prompt_object.to_global(_prompt_local)
		var eye := player.camera.global_position
		var blocked := world.raycast(eye, point)
		if eye.distance_squared_to(point) > 8.0 * 8.0 or (not blocked.is_empty() and blocked.collider != _prompt_object):
			_prompt_object = null
	if not is_instance_valid(_prompt_object) or (_prompt_object is CollisionObject3D and _prompt_object.collision_layer == 0):
		return
	_interaction_prompt.present(_prompt_message)
	_interaction_prompt.anchor_to(player.camera, _prompt_object.to_global(_prompt_local))


func _update_gadget_status() -> void:
	var gadgets := world.gadgets
	if not is_instance_valid(gadgets):
		return
	var status := ""
	var tint := Color("#e7dcce")
	if gadgets.clock_active():
		status = "Время остановлено · %.1f с" % maxf(0, gadgets.clock_until - Time.get_ticks_msec() * 0.001)
	elif gadgets.speed_multiplier() > 1.0:
		status = "Ускорение · %d с" % ceili(gadgets.boost_until[gadgets.local_side] - gadgets.scene_time())
	_gadget_label.text = status.strip_edges()
	_gadget_label.modulate = tint
	_gadget_label.visible = not status.is_empty() and not _inventory.is_open


func _update_stats() -> void:
	_stats.visible = _show_stats
	if not _show_stats or world == null:
		return
	var draw := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var active := Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	_stats.text = "FPS %d   кадр %.1f мс (макс %.1f)\nCPU: логика %.1f мс, физика %.1f мс\nотрисовка: %d вызовов, %.1fK треуг., VRAM %.0f МБ\nобъекты: %d (динам. %d, активн. %d), обломки %d, огонь %d\nперестройка чанков: %d в очереди, %.1f мс; обломки %.1f мс, огонь %.1f мс\nкачество: %s" % [
		roundi(_fps), _avg_ms, _worst_ms, proc, phys, draw, prims / 1000.0, vram,
		world.objects.size(), world.dynamic_count(), active, world.debris.active_count, world.fire.count(),
		world.pending_rebuilds(), world.stats.rebuild_usec / 1000.0, world.stats.debris_usec / 1000.0,
		world.stats.fire_usec / 1000.0, quality_name]


class Crosshair:
	extends Control
	var grab_hint := false:
		set(value):
			if grab_hint != value:
				grab_hint = value
				queue_redraw()

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.85)
		if grab_hint:
			draw_arc(Vector2.ZERO, 9.0, 0, TAU, 24, c, 2.0)
		else:
			draw_circle(Vector2.ZERO, 2.5, Color(0, 0, 0, 0.5))
			draw_circle(Vector2.ZERO, 1.6, c)
