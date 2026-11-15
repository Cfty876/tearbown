class_name PauseMenu
extends CanvasLayer

var _panel: ColorRect
var _actions: VBoxContainer
var _settings: VBoxContainer
var touch_mode := false
var editor: LayoutEditor


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	_panel.color = Color("#10151adc")
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.hide()
	add_child(_panel)
	_actions = VBoxContainer.new()
	_actions.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_actions.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_actions.grow_vertical = Control.GROW_DIRECTION_BOTH
	_actions.custom_minimum_size.x = 460
	_actions.add_theme_constant_override("separation", 12)
	_panel.add_child(_actions)
	_actions.add_child(MenuStyle.label("BREAKPOINT   /   ПАУЗА", 28, MenuStyle.GOLD))
	_actions.add_child(MenuStyle.button("Продолжить", toggle, true, 72))
	_actions.add_child(MenuStyle.button("Настройки", _open_settings, false, 66))
	if editor:
		_actions.add_child(MenuStyle.button("Режим правок", _open_editor, false, 66))
	_actions.add_child(MenuStyle.button("Главное меню", GameState.to_menu, false, 66))
	_actions.add_child(MenuStyle.button("Выход", GameState.exit_game, false, 66))


func _open_editor() -> void:
	editor.open()
	if editor.active:
		_panel.hide()


func _open_settings() -> void:
	_actions.hide()
	_settings = VBoxContainer.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.offset_left = 72
	_settings.offset_top = 42
	_settings.offset_right = -72
	_settings.offset_bottom = -42
	_settings.add_theme_constant_override("separation", 12)
	_panel.add_child(_settings)
	var title := HBoxContainer.new()
	_settings.add_child(title)
	title.add_child(MenuStyle.button("Назад", _close_settings, false, 56))
	title.add_child(MenuStyle.label("   Настройки", 44))
	_settings.add_child(GameSettingsPanel.new())


func _close_settings() -> void:
	if is_instance_valid(_settings):
		_panel.remove_child(_settings)
		_settings.queue_free()
		_settings = null
	_actions.show()


func _unhandled_input(e: InputEvent) -> void:
	if is_instance_valid(editor) and editor.active:
		return
	if e.is_action_pressed("ui_cancel"):
		if is_instance_valid(_settings):
			_close_settings()
		else:
			toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	var on := not _panel.visible
	if not on:
		_close_settings()
	get_tree().paused = on and not WebSession.connected
	_panel.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on or touch_mode else Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _panel.visible
