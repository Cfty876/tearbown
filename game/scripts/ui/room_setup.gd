class_name RoomSetup
extends VBoxContainer

var map_id := GameState.LEVEL_SCHOOL
var existing := {}
var people_count := 0
var submitted: Callable
var _preview: TextureRect
var _preview_caption: Label
var _tabs: TabContainer
var _map: OptionButton
var _transport: OptionButton
var _hiders: SpinBox
var _seekers: SpinBox
var _hide: SpinBox
var _seek: SpinBox
var _bot: CheckButton
var _role: CheckButton
var _rotate: CheckButton
var _clues: CheckButton
var _gadgets: CheckButton
var _spectate: CheckButton
var _zone: OptionButton
var _tools: Array[CheckBox] = []
var _create: Button
var _summary: Label
var _model_panel: BotModelPanel


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 25)
	add_child(columns)
	var overview := _column(columns, "Локация")
	overview.custom_minimum_size.x = 420
	_preview = MenuStyle.cover(MenuStyle.image(GameState.MAPS[map_id][2]))
	_preview.custom_minimum_size.y = 214
	overview.add_child(_preview)
	_preview_caption = MenuStyle.label("", 19, MenuStyle.MUTED)
	_preview_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overview.add_child(_preview_caption)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 24)
	_tabs.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#141e28f7")))
	columns.add_child(_tabs)
	var game := VBoxContainer.new()
	game.name = "Матч"
	game.add_theme_constant_override("separation", 9)
	_tabs.add_child(game)
	var equipment := VBoxContainer.new()
	equipment.name = "Снаряжение"
	equipment.add_theme_constant_override("separation", 10)
	_tabs.add_child(equipment)
	if not submitted.is_valid():
		var help := MenuStyle.label("Один код для браузера и приложения.", 20, MenuStyle.MUTED)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not OS.has_feature("web"):
			_transport = _choice(overview, "Тип комнаты", ["Онлайн", "Локальная сеть"])
			_transport.item_selected.connect(func(index: int):
				help.text = "Один код для браузера и приложения." if index == 0 else "Для игроков в одной сети Wi-Fi или Ethernet.")
		overview.add_child(help)

	_map = _choice(game, "Карта", [])
	for id: String in GameState.MAPS:
		_map.add_item(GameState.MAPS[id][0])
		_map.set_item_metadata(_map.item_count - 1, id)
		if id == map_id:
			_map.select(_map.item_count - 1)
	_map.disabled = people_count > 0
	_map.item_selected.connect(func(_i: int): _update())
	_hiders = _number(game, "Прячущиеся", 1, RoomRules.MAX_TEAM, 1, 1)
	_seekers = _number(game, "Ищущие", 1, RoomRules.MAX_TEAM, 1, 1)
	_bot = _toggle(game, "Добавить Шороха в прячущиеся", false)
	_role = _toggle(game, "Создатель начинает ищущим", true)
	_rotate = _toggle(game, "Предлагать смену ролей после раунда", true)
	_bot.toggled.connect(func(_on: bool): _update())
	_hide = _number(game, "Фора и обсуждение тактики", 10, 120, 22, 1, " с")
	_seek = _number(game, "Время поиска", 30, 900, 180, 5, " с")
	_zone = _choice(game, "Игровая область", RoomRules.ZONES)
	equipment.add_child(MenuStyle.label("Инструменты в инвентаре", 21, MenuStyle.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	equipment.add_child(grid)
	for name_text: String in PlayerTools.NAMES:
		var tool := CheckBox.new()
		tool.text = name_text
		tool.button_pressed = true
		tool.add_theme_font_size_override("font_size", 20)
		tool.toggled.connect(func(_on: bool): _update())
		grid.add_child(tool)
		_tools.append(tool)
	_gadgets = _toggle(equipment, "Автоматы с гаджетами", true)
	_clues = _toggle(equipment, "Гудки бота во время поиска", true)
	_spectate = _toggle(equipment, "Найденные могут гулять без инструментов", false)
	_model_panel = BotModelPanel.new()
	add_child(_model_panel)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	add_child(footer)
	_summary = MenuStyle.label("", 22, MenuStyle.MUTED)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_summary)
	_create = MenuStyle.button("Применить настройки" if submitted.is_valid() else "Открыть лобби", _open, true, 60)
	footer.add_child(_create)
	_hiders.value_changed.connect(func(_n: float): _update())
	_seekers.value_changed.connect(func(_n: float): _update())
	if not existing.is_empty():
		_restore(existing)
	_update()


func _column(parent: HBoxContainer, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#141e28f7")))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 11)
	panel.add_child(box)
	box.add_child(MenuStyle.label(title, 29, MenuStyle.GOLD))
	return box


func _row(parent: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := MenuStyle.label(title, 21)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _choice(parent: VBoxContainer, title: String, items: Array) -> OptionButton:
	var control := OptionButton.new()
	control.custom_minimum_size = Vector2(258, 38)
	control.add_theme_font_size_override("font_size", 21)
	for value: String in items:
		control.add_item(value)
	_row(parent, title).add_child(control)
	return control


func _number(parent: VBoxContainer, title: String, low: int, high: int, selected: int, step_by: int, suffix := "") -> SpinBox:
	var control := SpinBox.new()
	control.custom_minimum_size = Vector2(128, 36)
	control.get_line_edit().add_theme_font_size_override("font_size", 20)
	control.min_value = low
	control.max_value = high
	control.step = step_by
	control.value = selected
	control.suffix = suffix
	_row(parent, title).add_child(control)
	return control


func _toggle(parent: VBoxContainer, title: String, enabled: bool) -> CheckButton:
	var control := CheckButton.new()
	control.text = title
	control.button_pressed = enabled
	control.add_theme_font_size_override("font_size", 21)
	parent.add_child(control)
	return control


func _active_map() -> String:
	return str(_map.get_selected_metadata())


func _update() -> void:
	if not is_instance_valid(_summary):
		return
	var is_school := _active_map() == GameState.LEVEL_SCHOOL
	_bot.visible = is_school
	_clues.visible = is_school and _bot.button_pressed
	_model_panel.visible = _clues.visible
	_preview.texture = MenuStyle.image(GameState.MAPS[_active_map()][2])
	_preview_caption.text = str(GameState.MAPS[_active_map()][1])
	_tools[PlayerTools.POSSESSOR].visible = is_school
	var bot_enabled := is_school and _bot.button_pressed
	_role.disabled = bot_enabled and _hiders.value == 1
	var people := int(_hiders.value + _seekers.value) - int(bot_enabled)
	if people_count > 0:
		var total := people_count + int(bot_enabled)
		_seekers.min_value = maxi(1, total - RoomRules.MAX_TEAM)
		_seekers.max_value = mini(RoomRules.MAX_TEAM, total - 1)
		var required := total - int(_seekers.value)
		_hiders.set_value_no_signal(required)
		people = int(_hiders.value + _seekers.value) - int(bot_enabled)
		_hiders.editable = false
		_role.hide()
		_model_panel.hide()
	var have_tool := false
	for id in _tools.size():
		if id != PlayerTools.POSSESSOR and id != PlayerTools.BOOMBOX and _tools[id].button_pressed:
			have_tool = true
	_create.disabled = not have_tool or (people_count > 0 and people != people_count)
	_summary.text = "%d игроков   ·   %d ИИ" % [people, int(bot_enabled)] if have_tool else "Выбери хотя бы один основной инструмент."


func _restore(data: Dictionary) -> void:
	_hiders.set_value_no_signal(int(data.hiders))
	_seekers.set_value_no_signal(int(data.seekers))
	_hide.set_value_no_signal(int(data.hide))
	_seek.set_value_no_signal(int(data.seek))
	_bot.set_pressed_no_signal(bool(data.bot))
	_role.set_pressed_no_signal(bool(data.host_seeks))
	_rotate.set_pressed_no_signal(bool(data.switch_roles))
	_zone.select(int(data.zone))
	_gadgets.set_pressed_no_signal(bool(data.gadgets))
	_clues.set_pressed_no_signal(bool(data.bot_clues))
	_spectate.set_pressed_no_signal(bool(data.free_spectate))
	for i in _tools.size():
		_tools[i].set_pressed_no_signal((int(data.tools) & (1 << i)) != 0)


func _open() -> void:
	var mask := 0
	for i in _tools.size():
		if _tools[i].button_pressed:
			mask |= 1 << i
	var data := {
		"hiders": int(_hiders.value), "seekers": int(_seekers.value),
		"hide": int(_hide.value), "seek": int(_seek.value), "bot": _bot.button_pressed,
		"host_seeks": _role.button_pressed, "switch_roles": _rotate.button_pressed,
		"zone": _zone.selected, "tools": mask, "gadgets": _gadgets.button_pressed, "bot_clues": _clues.button_pressed,
		"free_spectate": _spectate.button_pressed,
	}
	if submitted.is_valid():
		submitted.call(RoomRules.normalized(_active_map(), data))
	elif is_instance_valid(_transport) and _transport.selected == 1:
		WebSession.host_lan(_active_map(), data)
	else:
		WebSession.host_online(_active_map(), data)
