class_name RoomRoundUi
extends CanvasLayer

var room: NetworkHide
var solo_player: Player
var _root: Control
var _curtain: ColorRect
var _left_door: ColorRect
var _right_door: ColorRect
var _waiting_title: Label
var _stun_label: Label
var _controls: VBoxContainer
var _brief: Control
var _roles: Array[OptionButton] = []
var _selection: Array[int] = []
var _rule_draft := {}
var _error: Label
var _editing := false
var _tween: Tween


func _ready() -> void:
	layer = 31
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func clear() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()
	_curtain = null
	_left_door = null
	_right_door = null
	_waiting_title = null
	_stun_label = null
	_controls = null
	_brief = null
	_roles.clear()
	_editing = false
	var active_player := room.player if is_instance_valid(room) else solo_player
	if is_instance_valid(active_player):
		active_player.navigation_menu_open = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if active_player.touch_mode or OS.has_feature("web") else Input.MOUSE_MODE_CAPTURED


func _screen(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


func _center(bg: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	bg.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)
	return content


func _headline(text: String, size_px: int, tint := MenuStyle.TEXT) -> Label:
	var label := MenuStyle.label(text, size_px, tint)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func hide_phase(is_seeker: bool) -> void:
	if not is_seeker:
		return
	_curtain = _screen(Color("#0a1118"))
	_left_door = _door_leaf(0.0, 0.5, false)
	_right_door = _door_leaf(0.5, 1.0, true)
	var body := _center(_curtain)
	if not bool(GameState.map_options.reduced_motion):
		body.modulate.a = 0.0
		create_tween().tween_property(body, "modulate:a", 1.0, 0.28)
	body.add_child(_headline("ШКОЛЬНЫЕ ПРЯТКИ" if GameState.level == GameState.LEVEL_SCHOOL else "ПРЯТКИ", 22, MenuStyle.GOLD))
	_waiting_title = _headline("Комната ожидания", 58)
	body.add_child(_waiting_title)
	body.add_child(_headline("Прячущиеся занимают позиции", 24, MenuStyle.MUTED))


func _door_leaf(left: float, right: float, right_leaf: bool) -> ColorRect:
	var door := ColorRect.new()
	door.color = Color("#141f28") if right_leaf else Color("#17242e")
	door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.add_child(door)
	door.anchor_left = left
	door.anchor_right = right
	door.anchor_bottom = 1.0
	var edge := ColorRect.new()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.color = Color("#627482")
	door.add_child(edge)
	edge.anchor_left = 0.0 if right_leaf else 1.0
	edge.anchor_right = edge.anchor_left
	edge.anchor_bottom = 1.0
	edge.offset_left = -2
	edge.offset_right = 2
	var handle := ColorRect.new()
	handle.color = Color("#aa8159")
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door.add_child(handle)
	handle.anchor_left = 0.10 if right_leaf else 0.90
	handle.anchor_right = handle.anchor_left
	handle.anchor_top = 0.56
	handle.anchor_bottom = handle.anchor_top
	handle.offset_left = -8.0
	handle.offset_right = 8.0
	handle.offset_bottom = 74.0
	for i in 4:
		var rib := ColorRect.new()
		rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rib.color = Color("#1b2a34")
		door.add_child(rib)
		rib.anchor_top = 0.16 + i * 0.23
		rib.anchor_right = 1.0
		rib.offset_bottom = 2.0
	return door


func door_duration_ms() -> int:
	return 140 if bool(GameState.map_options.reduced_motion) else 750


func open_door(is_seeker: bool) -> void:
	if not is_seeker or not is_instance_valid(_curtain):
		return
	_curtain.color = Color.TRANSPARENT
	for node in _curtain.get_children():
		if node != _left_door and node != _right_door:
			node.hide()
	var duration := door_duration_ms() * 0.001
	var width := _root.get_viewport_rect().size.x * 0.55
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_left_door, "position:x", _left_door.position.x - width, duration)
	_tween.tween_property(_right_door, "position:x", _right_door.position.x + width, duration)
	_tween.chain().tween_callback(func():
		if is_instance_valid(_curtain):
			_curtain.queue_free()
			_curtain = null)
	VoxelWorld.instance.sfx.play_ui("metal", -9.0)
	var active_player := room.player if is_instance_valid(room) else solo_player
	if is_instance_valid(active_player) and not bool(GameState.map_options.reduced_motion):
		active_player.shake(0.15)


func update_countdown(stunned: bool) -> void:
	if stunned and is_instance_valid(room) and room._phase == "seek":
		if not is_instance_valid(_stun_label):
			var body := _center(_root)
			_stun_label = _headline("", 50, Color("#f4bbb6"))
			body.add_child(_stun_label)
		var left := maxf(0.0, (room._stun_until[WebSession.local_side] - Time.get_ticks_msec()) * 0.001)
		_stun_label.text = "ОГЛУШЕНИЕ   %.1f с" % left
		_stun_label.show()
	elif is_instance_valid(_stun_label):
		_stun_label.hide()


func first_briefing() -> void:
	clear()
	_rule_draft = room.rules.duplicate()
	_selection = room._seekers.duplicate()
	_layout_brief("Подготовка раунда", "Создатель распределяет игроков.")


func show_result(seekers_won: bool) -> void:
	clear()
	_rule_draft = room.rules.duplicate()
	_selection = room.suggested_seekers(_rule_draft, room._round + 1)
	var title := "Победа ищущих" if seekers_won else "Победа прячущихся"
	var splash := _screen(Color("#0b121cdd"))
	var box := _center(splash)
	var result_color := Color("#ffcf83") if seekers_won else Color("#91e5d9")
	var label := _headline(title, 81, result_color)
	box.add_child(_headline("РАУНД ЗАВЕРШЁН", 23, MenuStyle.MUTED))
	box.add_child(label)
	box.add_child(_headline("Найдено %d из %d" % [room._found.size(), room._hider_count()], 25, MenuStyle.MUTED))
	label.modulate.a = 0.0
	_tween = create_tween()
	var duration := 0.05 if bool(GameState.map_options.reduced_motion) else 0.38
	_tween.tween_property(label, "modulate:a", 1.0, duration)
	var line := ColorRect.new()
	line.color = result_color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.add_child(line)
	line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	line.offset_top = -8.0
	line.scale.x = 0.0
	_tween.parallel().tween_property(line, "scale:x", 1.0, duration + 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not OS.has_feature("web"):
		_tween.tween_interval(1.55)
		_tween.tween_callback(func():
			splash.queue_free()
			_layout_brief(title, "Подготовка следующего раунда"))
	room.world.sfx.play_ui("metal" if seekers_won else "click", -12.0, 0.8 if seekers_won else 1.12)


func _layout_brief(title: String, subtitle: String) -> void:
	room.player.navigation_menu_open = true
	if is_instance_valid(room._bot_chat):
		room._bot_chat.close_chat()
	room.player.navigation_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var base := _screen(Color("#0d151ef5"))
	_brief = base
	var body := _center(base)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 870
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#182530"), Color("#435565"), 18))
	body.add_child(panel)
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 9)
	panel.add_child(_controls)
	_controls.add_child(_headline(title, 46))
	_controls.add_child(_headline(subtitle, 20, MenuStyle.MUTED))
	var roles := GridContainer.new()
	roles.columns = 2
	roles.add_theme_constant_override("h_separation", 24)
	roles.add_theme_constant_override("v_separation", 6)
	_controls.add_child(roles)
	_roles.clear()
	for side in WebSession.roster.size():
		var person := HBoxContainer.new()
		person.add_theme_constant_override("separation", 12)
		roles.add_child(person)
		var portrait := RoomPortrait.new()
		portrait.side = side
		person.add_child(portrait)
		var label := MenuStyle.label("Создатель" if side == 0 else "Игрок %d" % (side + 1), 20)
		label.custom_minimum_size.x = 122
		person.add_child(label)
		var option := OptionButton.new()
		option.add_theme_font_size_override("font_size", 19)
		option.add_item("Прячется")
		option.add_item("Ищет")
		option.select(int(side in _selection))
		option.disabled = not WebSession.is_host
		option.item_selected.connect(_set_role.bind(side))
		person.add_child(option)
		_roles.append(option)
	if bool(_rule_draft.bot):
		var bot := HBoxContainer.new()
		bot.add_theme_constant_override("separation", 12)
		roles.add_child(bot)
		var portrait := RoomPortrait.new()
		portrait.side = RoomRules.BOT_SIDE
		bot.add_child(portrait)
		bot.add_child(MenuStyle.label("Шорох · прячется", 20))
	_error = _headline("", 19, MenuStyle.GOLD)
	_controls.add_child(_error)
	if WebSession.is_host:
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		actions.add_theme_constant_override("separation", 10)
		_controls.add_child(actions)
		actions.add_child(MenuStyle.button("Настройки матча", _edit_rules, false, 48))
		actions.add_child(MenuStyle.button("Начать раунд", _launch, true, 48))
	else:
		_controls.add_child(_headline("Ожидаем решения создателя", 20, MenuStyle.MUTED))
	var leave := MenuStyle.button("Покинуть комнату", GameState.to_menu, false, 44)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_controls.add_child(leave)


func _set_role(role_index: int, side: int) -> void:
	if role_index == 1 and side not in _selection:
		_selection.append(side)
	elif role_index == 0:
		_selection.erase(side)
	_error.text = "Ищущие %d из %d" % [_selection.size(), int(_rule_draft.seekers)]


func _launch() -> void:
	if not room.launch_next(_rule_draft, _selection):
		_error.text = "Выбери %d ищущих. Остальные будут прятаться." % int(_rule_draft.seekers)


func _edit_rules() -> void:
	if _editing:
		return
	_editing = true
	_controls.hide()
	var base := _screen(Color("#0c141dfb"))
	var shell := MarginContainer.new()
	base.add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		shell.add_theme_constant_override(key, 43)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	shell.add_child(stack)
	stack.add_child(_headline("Настройки следующего раунда", 42))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var setup := RoomSetup.new()
	setup.map_id = GameState.level
	setup.people_count = WebSession.roster.size()
	setup.existing = _rule_draft
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.submitted = func(data: Dictionary):
		_rule_draft = data
		if _selection.size() != int(data.seekers):
			_selection = room.suggested_seekers(data, room._round + 1)
		base.queue_free()
		_brief.queue_free()
		_layout_brief("Следующий раунд", "Проверь роли и запускай поиск.")
		_editing = false
	scroll.add_child(setup)
	stack.add_child(MenuStyle.button("Назад", func():
		base.queue_free()
		_controls.show()
		_editing = false, false, 43))
