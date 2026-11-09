class_name Hud
extends CanvasLayer
## Crosshair, tool bar, help panel and the performance overlay (F3).

var player: Player
var world: VoxelWorld
var quality_name := ""

var _cross: Control
var _inventory: ToolInventory
var _hint: Label
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

	_stats = _label(root, 14, HORIZONTAL_ALIGNMENT_LEFT)
	_show_stats = not player.touch_mode
	_stats.visible = _show_stats
	_stats.position = Vector2(14, 10)
	_help = _label(root, 15, HORIZONTAL_ALIGNMENT_LEFT)
	_help.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_help.offset_left = -550
	_help.offset_right = -18
	_help.offset_top = 10
	_help.visible = not player.touch_mode
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.text = """[F1] справка   [F3] статистика   [F4] качество графики
WASD — движение, Shift — бег, Ctrl — присесть, Space — прыжок
ЛКМ — инструмент, E — взять / отпустить, ЛКМ с предметом — бросить
Удерживай Tab — снаряжение, 1–7 / колесо — быстрый выбор
Колесо с предметом — дистанция удержания
F5 — перезапуск карты, F6 — бенчмарк, Esc — пауза"""
	_msg = _label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_msg.offset_top = 120
	_msg.offset_left = -500
	_msg.offset_right = 500
	root.add_child(_inventory)


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
	_cross.visible = not _inventory.is_open
	_hint.visible = not _inventory.is_open
	if _inventory.is_open:
		return
	var t := player.tools
	var hint: String = PlayerTools.HINTS[t.current]
	if player.vehicle and is_instance_valid(player.vehicle):
		hint = "%d км/ч   W/S — газ/тормоз, A/D — руль, Space — ручник, E — выйти, мышь — камера" % roundi(absf(player.vehicle.speed) * 3.6)
	elif player.grabbed:
		hint = "держу: %s, %.0f кг — ЛКМ бросить, E отпустить" % [player.grabbed.label, player.grabbed.mass]
	else:
		var hit := player.aim_ray(3.2)
		if not hit.is_empty() and hit.collider is VoxelObject:
			var o: VoxelObject = hit.collider
			var vox := o.voxel_at_hit(hit.position, hit.normal)
			if vox > 0:
				var mat := VoxMat.material_of(vox)
				hint += "   |   %s" % VoxMat.NAMES.get(mat, "?")
				if o.has_node("Vehicle"):
					hint += ", %.0f кг [E] сесть за руль" % o.mass
				elif not o.static_mode:
					hint += ", %.0f кг [E]" % o.mass
	if _hint.text != hint:
		_hint.text = hint
	(_cross as Crosshair).grab_hint = player.grabbed != null


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
