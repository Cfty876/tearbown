class_name DistrictCCTV
extends CanvasLayer

const CAMERA_NAMES := ["Крыльцо аптеки", "Торговый зал", "Гаражный проезд", "Смотровая яма",
	"Вход на крышу", "Детская площадка", "Автосервис", "Парковка супермаркета", "Восточный двор", "Теплотрасса"]
const BACKGROUND := Color("#070e14")
const PANEL := Color("#111e29ec")
const BORDER := Color("#3d5465")
const TEXT := Color("#f1f6f8")
const MUTED := Color("#b0c4cd")
const LIVE := Color("#a9eedc")
const ALERT := Color("#ff9a85")
const FRAME_WIDTHS := [854, 1024, 1280, 1600]
const FRAME_RATES := [15.0, 20.0, 24.0, 30.0]

var secrets: DistrictSecrets
var camera_names: Array = CAMERA_NAMES
var analog_feed := false
var station_title := "ЗАРЕЧЬЕ  /  ПОСТ НАБЛЮДЕНИЯ"
var alarm_title := "ГАРАЖНЫЕ ВОРОТА"
var alarm_duration := Sfx.siren_duration()
var alarm_cooldown := maxf(DistrictSecrets.ALARM_COOLDOWN, alarm_duration)
var _root: ColorRect
var _chrome: MarginContainer
var _view: SubViewport
var _camera: Camera3D
var _feed: TextureRect
var _title: Label
var _signal_label: Label
var _lost: CenterContainer
var _restore_label: Label
var _alarm: Button
var _broadcast: Button
var _channels: Array[Button] = []
var _index := 0
var _quality := -1
var _frame_timer := 0.0
var _mouse_mode := Input.MOUSE_MODE_CAPTURED
var _world_cull_mask := 0


func _ready() -> void:
	layer = 16
	_root = ColorRect.new()
	_root.color = BACKGROUND
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_feed = TextureRect.new()
	_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_feed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)
	_feed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_chrome()
	_build_signal_loss()
	get_window().size_changed.connect(_resize_feed)
	_root.hide()
	set_process(false)
	set_process_input(false)


func _build_chrome() -> void:
	_chrome = MarginContainer.new()
	_root.add_child(_chrome)
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		_chrome.add_theme_constant_override("margin_" + side, 26)
	var layout := VBoxContainer.new()
	_chrome.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)
	var station := _panel()
	header.add_child(station)
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 4)
	station.add_child(identity)
	identity.add_child(MenuStyle.label(station_title, 16, LIVE))
	_title = MenuStyle.label("", 32, TEXT)
	identity.add_child(_title)
	_signal_label = MenuStyle.label("", 17, LIVE)
	identity.add_child(_signal_label)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(space)
	var clean := _button("Чистый кадр  ·  Space", _toggle_chrome)
	clean.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(clean)
	var exit := _button("Закрыть  ·  Esc", close)
	exit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(exit)
	var breathing_room := Control.new()
	breathing_room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	breathing_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(breathing_room)

	var footer := _panel()
	layout.add_child(footer)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 18)
	footer.add_child(controls)
	var channel_list := VBoxContainer.new()
	channel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channel_list.add_theme_constant_override("separation", 6)
	controls.add_child(channel_list)
	var hint := "КАНАЛЫ  /  ← →  ИЛИ  1–%s" % ("0" if camera_names.size() == 10 else str(camera_names.size()))
	if WebSession.connected and not OS.has_feature("web"):
		hint += "     ·     Удерживай %s для связи" % GameControls.key_name("voice_chat")
	channel_list.add_child(MenuStyle.label(hint, 16, MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	channel_list.add_child(row)
	for i in camera_names.size():
		var channel := _button("%02d" % (i + 1), _show_channel.bind(i))
		channel.custom_minimum_size.x = 43
		channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel.toggle_mode = true
		channel.tooltip_text = camera_names[i]
		_channels.append(channel)
		row.add_child(channel)
	var alarm_group := VBoxContainer.new()
	alarm_group.add_theme_constant_override("separation", 6)
	controls.add_child(alarm_group)
	alarm_group.add_child(MenuStyle.label(alarm_title, 16, MUTED))
	_alarm = _button("Включить тревогу", secrets.request_alarm, true)
	_alarm.custom_minimum_size.x = 216
	alarm_group.add_child(_alarm)
	_broadcast = _button("Эфир с бумбокса", _toggle_broadcast)
	alarm_group.add_child(_broadcast)


func _build_signal_loss() -> void:
	_lost = CenterContainer.new()
	_lost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lost)
	_lost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := _panel()
	_lost.add_child(box)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	box.add_child(content)
	content.add_child(MenuStyle.label("КАНАЛ ОТКЛЮЧЁН", 19, ALERT))
	content.add_child(MenuStyle.label("Сигнал потерян", 45, TEXT))
	_restore_label = MenuStyle.label("", 21, MUTED)
	content.add_child(_restore_label)
	_lost.hide()


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 14))
	return panel


func _style(fill: Color, edge: Color, padding: int) -> StyleBoxFlat:
	var result := MenuStyle.panel(fill, edge, 8)
	result.content_margin_left = padding
	result.content_margin_right = padding
	result.content_margin_top = 7
	result.content_margin_bottom = 7
	return result


func _button(text: String, callback: Callable, alarm := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", BACKGROUND)
	button.add_theme_color_override("font_hover_pressed_color", BACKGROUND)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal",
		_style(Color("#4b282be8") if alarm else PANEL, ALERT if alarm else BORDER, 9))
	button.add_theme_stylebox_override("hover",
		_style(Color("#723f3d") if alarm else Color("#294453"), ALERT if alarm else LIVE, 9))
	button.add_theme_stylebox_override("pressed", _style(LIVE, LIVE, 9))
	button.add_theme_stylebox_override("hover_pressed", _style(LIVE, LIVE, 9))
	button.add_theme_stylebox_override("disabled", _style(PANEL, BORDER, 9))
	button.pressed.connect(callback)
	return button


func _setup_view() -> void:
	_view = SubViewport.new()
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.world_3d = get_viewport().world_3d
	_view.gui_disable_input = true
	_view.positional_shadow_atlas_size = 0
	_view.use_occlusion_culling = false
	if not OS.has_feature("web"):
		_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	add_child(_view)
	_camera = Camera3D.new()
	_camera.cull_mask = 1 | VoxelAvatar.HEAD_LAYER
	_camera.fov = 78.0
	_view.add_child(_camera)
	_camera.make_current()
	_feed.texture = _view.get_texture()
	if analog_feed:
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/school_cctv.gdshader")
		_feed.material = material


func _resize_feed() -> void:
	if not is_instance_valid(_view) or not _root.visible:
		return
	_quality = clampi(GameState.quality, 0, FRAME_WIDTHS.size() - 1)
	var size := Vector2(get_window().size)
	if size.x < 2.0 or size.y < 2.0:
		return
	var scale_factor := minf(1.0, FRAME_WIDTHS[_quality] / maxf(size.x, size.y))
	_view.size = Vector2i((size * scale_factor).round().max(Vector2(2, 2)))
	if analog_feed:
		var analog_scale := minf(1.0, 760.0 / maxf(size.x, size.y))
		_view.size = Vector2i((size * analog_scale).round().max(Vector2(2, 2)))
	_camera.far = [66.0, 76.0, 88.0, 100.0][_quality]
	_frame_timer = 0.0


func open() -> void:
	if _root.visible:
		return
	if not is_instance_valid(_view):
		_setup_view()
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	secrets.player.navigation_menu_open = true
	_world_cull_mask = secrets.player.camera.cull_mask
	secrets.player.camera.cull_mask = 0
	_chrome.show()
	_root.show()
	_resize_feed()
	set_process(true)
	set_process_input(true)
	_show_channel(_index)
	_refresh_broadcast()


func _toggle_broadcast() -> void:
	secrets.world.boombox.toggle_public_address()
	_refresh_broadcast()


func _refresh_broadcast() -> void:
	var box := secrets.world.boombox
	_broadcast.disabled = box == null or not box.broadcast_available()
	_broadcast.text = box.broadcast_label() if box != null else "Эфир с бумбокса"


func close() -> void:
	if not is_instance_valid(_root) or not _root.visible:
		return
	_root.hide()
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	set_process_input(false)
	secrets.player.navigation_menu_open = false
	secrets.player.camera.cull_mask = _world_cull_mask
	Input.mouse_mode = _mouse_mode


func _toggle_chrome() -> void:
	_chrome.visible = not _chrome.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _chrome.visible else Input.MOUSE_MODE_HIDDEN


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("grab"):
		close()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_select(-1 if event.is_action_pressed("ui_left") else 1)
	elif not _chrome.visible and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_toggle_chrome()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			_toggle_chrome()
		elif event.physical_keycode >= KEY_0 and event.physical_keycode <= KEY_9:
			var number: int = 9 if event.physical_keycode == KEY_0 else event.physical_keycode - KEY_1
			if number >= camera_names.size():
				return
			_show_channel(number)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


func _select(step: int) -> void:
	_show_channel(posmod(_index + step, camera_names.size()))


func _show_channel(index: int) -> void:
	_index = index
	var at := secrets._camera_points[index]
	var target := secrets._camera_views[index]
	_camera.global_position = at + at.direction_to(target) * 0.45
	_camera.look_at(target)
	_title.text = "%02d  %s" % [index + 1, camera_names[index]]
	for i in _channels.size():
		_channels[i].set_pressed_no_signal(i == index)
	_frame_timer = 0.0
	_refresh_signal(secrets._now())


func _refresh_signal(now: float) -> void:
	var down := secrets._disabled[_index] - now
	var active := down <= 0.0
	_feed.visible = active
	_lost.visible = not active
	_signal_label.text = "●  ПРЯМОЙ ЭФИР   /   КАНАЛ %02d" % (_index + 1) if active else "●  НЕТ СИГНАЛА"
	_signal_label.add_theme_color_override("font_color", LIVE if active else ALERT)
	if not active:
		_restore_label.text = "Восстановление через %02d с" % ceili(down)
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if (not secrets.player.movement_enabled or secrets.player.dead
			or secrets.player.global_position.distance_squared_to(secrets.targets.monitor.global_position) > 9.0):
		close()
		return
	if _quality != GameState.quality:
		_resize_feed()
	_frame_timer -= delta
	if _frame_timer > 0.0:
		return
	_frame_timer = 1.0 / FRAME_RATES[_quality]
	var now := secrets._now()
	var cooldown := secrets._alarm_until - now
	_alarm.disabled = cooldown > 0.0
	if cooldown > alarm_cooldown - alarm_duration:
		_alarm.text = "Тревога включена"
	elif cooldown > 0.0:
		_alarm.text = "Повтор через %02d с" % ceili(cooldown)
	else:
		_alarm.text = "Включить тревогу"
	_refresh_broadcast()
	_refresh_signal(now)
