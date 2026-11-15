class_name GameSettingsPanel
extends VBoxContainer

var _key_action := ""
var _key_buttons := {}
var _section := "Графика"
var _settings_body: VBoxContainer
var _settings_scroll: ScrollContainer


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_show_section()


func _clear_content() -> void:
	_key_action = ""
	_key_buttons.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _cinematics() -> void:
	if WebSession.connected:
		return
	get_tree().paused = false
	GameState.start(GameState.LEVEL_DISTRICT, "all")


func _show_section() -> void:
	_clear_content()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	add_child(tabs)
	for tab in ["Графика", "Эффекты камеры", "Управление", "Звук", "Карта"]:
		tabs.add_child(MenuStyle.button(tab, func(): _choose_section(tab), tab == _section, 58))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#151c24f5")))
	add_child(panel)
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_settings_scroll)
	_settings_body = VBoxContainer.new()
	_settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_body.add_theme_constant_override("separation", 11)
	_settings_scroll.add_child(_settings_body)
	match _section:
		"Графика":
			_toggle("Полноэкранный режим   ·   F11", GameState.fullscreen, func(on: bool): GameState.fullscreen = on)
			_option("Качество графики", Quality.NAMES, GameState.quality, func(index: int): GameState.quality = index)
			_toggle("Адаптивное разрешение 3D", GameState.adaptive_resolution, func(on: bool): GameState.adaptive_resolution = on)
			_option("Эффекты оружия", ["Обычные", "Кинематографичные"], int(GameState.cinematic_fx),
				func(index: int): GameState.cinematic_fx = index == 1)
			_toggle("Вертикальная синхронизация", GameState.vsync, func(on: bool): GameState.vsync = on)
			_option("Ограничение FPS", ["60", "120", "Без ограничения"], maxi(0, [60, 120, 0].find(GameState.fps_limit)),
				func(index: int): GameState.fps_limit = [60, 120, 0][index])
		"Эффекты камеры":
			_toggle("Мягкие края", GameState.lens_effects, func(on: bool): GameState.lens_effects = on)
			_slider("Интенсивность мягких краёв", 0.1, 1.5, 0.05, GameState.edge_strength, func(value: float): GameState.edge_strength = value)
			_toggle("Дальний автофокус", GameState.autofocus, func(on: bool): GameState.autofocus = on)
			_toggle("Солнечные лучи", GameState.sun_rays, func(on: bool): GameState.sun_rays = on)
			_toggle("Размытие при резком повороте", GameState.motion_blur, func(on: bool): GameState.motion_blur = on)
			_slider("Интенсивность размытия", 0.1, 1.5, 0.05, GameState.motion_strength, func(value: float): GameState.motion_strength = value)
		"Управление":
			_slider("Чувствительность мыши", 0.25, 3.0, 0.05, GameState.mouse_speed, func(value: float): GameState.mouse_speed = value)
			_slider("Поле зрения", 60.0, 110.0, 1.0, GameState.fov, func(value: float): GameState.fov = value)
			_toggle("Инверсия вертикали", GameState.invert_y, func(on: bool): GameState.invert_y = on)
			_key_buttons.clear()
			for action in GameControls.BINDINGS:
				var b := MenuStyle.button(_binding_name(action), func(): _begin_key(action), false, 50)
				b.custom_minimum_size.x = 260
				_setting_row(GameControls.BINDINGS[action][0]).add_child(b)
				_key_buttons[action] = b
			_settings_body.add_child(MenuStyle.label("ЛКМ — использовать инструмент   ·   1–9 — выбрать инструмент   ·   Esc — пауза", 21, MenuStyle.MUTED))
			_settings_body.add_child(MenuStyle.button("Вернуть исходные клавиши", _reset_keys, false, 53))
		"Звук":
			_slider("Общая громкость", 0.0, 1.0, 0.01, GameState.master_volume, func(value: float): GameState.master_volume = value)
			_slider("Музыка окружения", 0.0, 1.0, 0.01, GameState.music_volume, func(value: float): GameState.music_volume = value)
		"Карта":
			var options: Dictionary = GameState.map_options
			_toggle("Мини-карта", options.visible, func(on: bool): options.visible = on)
			_slider("Размер мини-карты", 160, 290, 2.0, options["size"], func(value: float): options["size"] = value)
			_slider("Непрозрачность", 0.45, 1.0, 0.05, options.opacity, func(value: float): options.opacity = value)
			_option("Ориентация", ["Север сверху", "По направлению взгляда"], int(options.rotate), func(index: int): options.rotate = index == 1)
			_option("Масштаб", ["44 м", "70 м", "106 м"], options.zoom, func(index: int): options.zoom = index)
			_option("Оформление", ["Топографическая", "Ночной дозор", "Монохром"], options.style, func(index: int): options.style = index)
			_toggle("Контрастные маркеры", options.accessible, func(on: bool): options.accessible = on)
			_toggle("Уменьшить анимацию", options.reduced_motion, func(on: bool): options.reduced_motion = on)
			_toggle("Туман исследования", options.fog, func(on: bool): options.fog = on)
			for kind in MapStyle.HORN:
				var flag := 1 << kind
				_toggle(MapStyle.NAMES[kind], (int(options.markers) & flag) != 0, func(on: bool):
					options.markers = (int(options.markers) | flag) if on else (int(options.markers) & ~flag))
	var cinematic := MenuStyle.button("Кинопролёты", _cinematics, false, 58)
	cinematic.disabled = WebSession.connected
	add_child(cinematic)


func _choose_section(tab: String) -> void:
	_section = tab
	_show_section()


func _setting_row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 52
	_settings_body.add_child(row)
	var caption := MenuStyle.label(title, 24)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	return row


func _toggle(title: String, enabled: bool, change: Callable) -> void:
	var field := CheckButton.new()
	field.text = "Вкл." if enabled else "Выкл."
	field.custom_minimum_size.x = 145
	field.add_theme_font_size_override("font_size", 22)
	field.button_pressed = enabled
	field.toggled.connect(func(on: bool):
		field.text = "Вкл." if on else "Выкл."
		change.call(on)
		GameState.save_graphics())
	_setting_row(title).add_child(field)


func _option(title: String, choices: Array, selected: int, change: Callable) -> void:
	var field := OptionButton.new()
	field.custom_minimum_size.x = 260
	field.add_theme_font_size_override("font_size", 23)
	field.add_theme_stylebox_override("normal", MenuStyle.panel(Color("#222b35")))
	field.add_theme_stylebox_override("hover", MenuStyle.panel(Color("#354151"), MenuStyle.GOLD))
	for choice in choices:
		field.add_item(choice)
	field.select(selected)
	field.item_selected.connect(func(index: int):
		change.call(index)
		GameState.save_graphics())
	_setting_row(title).add_child(field)


func _slider(title: String, min_value: float, max_value: float, step: float, current: float, change: Callable) -> void:
	var row := _setting_row(title)
	var field := HSlider.new()
	field.min_value = min_value
	field.max_value = max_value
	field.step = step
	field.value = current
	field.custom_minimum_size.x = 280
	row.add_child(field)
	var number := MenuStyle.label("  %.2f" % current, 22, MenuStyle.GOLD)
	number.custom_minimum_size.x = 90
	row.add_child(number)
	field.value_changed.connect(func(value: float):
		change.call(value)
		number.text = "  %.2f" % value
		GameState.save_graphics())


func _binding_name(action: String) -> String:
	return GameControls.key_name(action)


func _begin_key(action: String) -> void:
	if _key_action != "" and is_instance_valid(_key_buttons.get(_key_action)):
		_key_buttons[_key_action].text = _binding_name(_key_action)
	_key_action = action
	_key_buttons[action].text = "Нажми клавишу"


func _reset_keys() -> void:
	_key_action = ""
	GameState.bindings.clear()
	GameControls.install(GameState.bindings)
	GameState.save_graphics()
	for action in _key_buttons:
		_key_buttons[action].text = _binding_name(action)


func _input(event: InputEvent) -> void:
	if _key_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var action := _key_action
	var key: Key = event.physical_keycode
	if key == KEY_ESCAPE:
		_key_action = ""
		_key_buttons[action].text = _binding_name(action)
		return
	if key == KEY_F11 or (key >= KEY_1 and key <= KEY_9):
		_key_buttons[action].text = "Зарезервирована"
		return
	for other in GameControls.BINDINGS:
		if other != action and InputMap.action_has_event(other, _physical_key(key)):
			_key_buttons[action].text = "Клавиша занята"
			return
	GameState.bindings[action] = int(key)
	GameControls.bind(action, key)
	GameState.save_graphics()
	_key_action = ""
	_key_buttons[action].text = _binding_name(action)


func _physical_key(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event
