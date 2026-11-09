class_name PauseMenu
extends CanvasLayer
## Esc: pause with Resume / Main menu / Quit.

signal quality_changed(preset: int)

var _panel: Control
var lens: CameraLens
var touch_mode := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0, 0, 0, 0.55)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -280 if touch_mode else -220
	box.offset_right = 280 if touch_mode else 220
	box.offset_top = -270 if touch_mode else -190
	box.offset_bottom = 190
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var t := Label.new()
	t.text = "Пауза"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	box.add_child(t)
	_btn(box, "Продолжить", toggle)
	if touch_mode:
		var quality := OptionButton.new()
		for preset_name in Quality.NAMES:
			quality.add_item("Графика: " + preset_name)
		quality.select(GameState.quality)
		quality.custom_minimum_size.y = 84
		quality.add_theme_font_size_override("font_size", 32)
		quality.item_selected.connect(func(preset: int): quality_changed.emit(preset))
		box.add_child(quality)
	var lens_label := "Мягкие края и солнечные лучи" if OS.has_feature("web") else "Фокус, края и солнечные лучи"
	_setting(box, lens_label, GameState.lens_effects, func(on: bool):
		GameState.lens_effects = on
		_update_lens())
	_setting(box, "Размытие при повороте", GameState.motion_blur, func(on: bool):
		GameState.motion_blur = on
		_update_lens())
	_btn(box, "Главное меню", func(): GameState.to_menu())
	_btn(box, "Выход", GameState.exit_game)


func _setting(parent: Control, text: String, on: bool, cb: Callable) -> void:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = on
	if touch_mode:
		check.add_theme_font_size_override("font_size", 30)
		check.custom_minimum_size.y = 70
	check.toggled.connect(cb)
	parent.add_child(check)


func _update_lens() -> void:
	GameState.save_graphics()
	lens.configure(GameState.quality, GameState.lens_effects, GameState.motion_blur)


func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(440, 96 if touch_mode else 56)
	b.add_theme_font_size_override("font_size", 36 if touch_mode else 26)
	b.pressed.connect(cb)
	parent.add_child(b)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	var on := not _panel.visible
	get_tree().paused = on and not WebSession.connected
	_panel.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on or touch_mode else Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _panel.visible
