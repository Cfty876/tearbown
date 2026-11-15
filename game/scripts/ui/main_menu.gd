extends Control

const AUTOSTART := ["bench", "tour", "drive", "tools", "crater", "dtour", "audit", "glass", "level", "cinematic", "card"]
const ART := "res://ui/menu_courtyard.png"
const SHADE := preload("res://shaders/menu_veil.gdshader")
var _page: Control
var _selected := GameState.LEVEL_DISTRICT
var _status: Label
var _room_waiting := false
var _host_launch: Button
var _lobby_count: Label
var _lobby_roster: GridContainer
var _back_action := Callable()


func _ready() -> void:
	var commands := OS.get_cmdline_user_args()
	if "--bot-hide" in commands:
		GameState.start.call_deferred(GameState.LEVEL_SCHOOL, "", true)
		return
	for arg in commands:
		if arg.begins_with("--lan-host="):
			WebSession.host_lan(arg.get_slice("=", 1), {"auto_start": true})
			return
		if arg.begins_with("--lan-join="):
			WebSession.join_lan(arg.get_slice("=", 1), true)
			return
	for arg in commands:
		if arg.trim_prefix("--").split("=")[0] in AUTOSTART:
			GameState.start.call_deferred(GameState.level, GameState.cinematic)
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	WebSession.status_changed.connect(_status_message)
	WebSession.lobby_changed.connect(_lobby_changed)
	_home()


func _screen(dense := false) -> Control:
	if is_instance_valid(_page):
		remove_child(_page)
		_page.queue_free()
	_back_action = Callable()
	_room_waiting = false
	_page = Control.new()
	add_child(_page)
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := MenuStyle.cover(MenuStyle.image(ART))
	_page.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADE
	mat.set_shader_parameter("dense", dense)
	shade.material = mat
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var strip := HBoxContainer.new()
	_page.add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = 100
	strip.offset_right = -100
	strip.offset_top = -62
	strip.offset_bottom = -28
	strip.add_child(MenuStyle.label("BREAKPOINT     /     ВОКСЕЛЬНАЯ ПЕСОЧНИЦА", 17, MenuStyle.GOLD))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(gap)
	strip.add_child(MenuStyle.label(OS.get_name().to_upper(), 17, MenuStyle.MUTED))
	return _page


func _home() -> void:
	WebSession.leave()
	_screen()
	var box := VBoxContainer.new()
	box.position = Vector2(100, 196)
	box.custom_minimum_size.x = 500
	box.add_theme_constant_override("separation", 16)
	_page.add_child(box)
	box.add_child(MenuStyle.label("В О К С Е Л Ь Н А Я   П Е С О Ч Н И Ц А", 22, MenuStyle.GOLD))
	box.add_child(MenuStyle.label("BREAKPOINT", 112))
	box.add_child(MenuStyle.label("ДВОРЫ   /   РАЗРУШЕНИЕ   /   ПРЯТКИ", 22, MenuStyle.MUTED))
	_space(box, 37)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 470
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	actions.add_child(MenuStyle.button("Начать игру", _maps, true, 78))
	var create := _create_web_room if OS.has_feature("web") else _create_room
	actions.add_child(MenuStyle.button("Создать комнату", create, false, 72))
	actions.add_child(MenuStyle.button("Войти по коду", _lobby, false, 54))
	actions.add_child(MenuStyle.button("Настройки", _settings, false, 62))
	if not OS.has_feature("web"):
		actions.add_child(MenuStyle.button("Выйти", GameState.exit_game, false, 62))
	if not WebSession.last_error.is_empty():
		box.add_child(MenuStyle.label(WebSession.last_error, 19, MenuStyle.GOLD))
	var stamp := MenuStyle.label("01  /  ДВОРЫ ЗАРЕЧЬЯ", 21, MenuStyle.TEXT)
	_page.add_child(stamp)
	stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	stamp.offset_left = -382
	stamp.offset_top = -142
	stamp.offset_right = -96


func _interior(kicker: String, title: String, subtitle: String, back: Callable) -> VBoxContainer:
	_screen(true)
	_back_action = back
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_page.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 100
	box.offset_right = -100
	box.offset_top = 59
	box.offset_bottom = -100
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	row.add_child(MenuStyle.button("Назад", back, false, 50))
	row.add_child(MenuStyle.label(kicker, 18, MenuStyle.GOLD))
	box.add_child(MenuStyle.label(title, 62))
	if not subtitle.is_empty():
		box.add_child(MenuStyle.label(subtitle, 24, MenuStyle.MUTED))
	_space(box, 6)
	return box


func _maps() -> void:
	WebSession.leave()
	var box := _interior("ИГРА   /   01", "Выбери карту", "Три локации. На следующем экране можно выбрать режим.", _home)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 25)
	box.add_child(row)
	var index := 0
	for id in GameState.MAPS:
		index += 1
		var map: Array = GameState.MAPS[id]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#151c24f7")))
		row.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 15)
		card.add_child(body)
		body.add_child(MenuStyle.label("ЛОКАЦИЯ   /   0%d" % index, 18, MenuStyle.GOLD))
		var photo := MenuStyle.cover(MenuStyle.image(map[2]))
		photo.custom_minimum_size.y = 295
		body.add_child(photo)
		body.add_child(MenuStyle.label(map[0], 38))
		body.add_child(MenuStyle.label(map[1], 20, MenuStyle.MUTED))
		_space(body, 4)
		body.add_child(MenuStyle.button("Выбрать карту", func(): _modes(id), true))
	var tween := create_tween()
	row.modulate.a = 0
	tween.tween_property(row, "modulate:a", 1.0, 0.19)


func _modes(map: String) -> void:
	WebSession.leave()
	_selected = map
	var data: Array = GameState.MAPS[map]
	var box := _interior("ИГРА   /   02", "Выбери режим", data[0] + "   ·   " + data[1], _maps)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	_mode_card(row, "01   /   ОДИН ИГРОК", "Одиночная игра",
		"Исследуй карту в песочнице или потренируйся с Шорохом." if map == GameState.LEVEL_SCHOOL else "Исследуй карту, води машины и испытывай воксельное разрушение.",
		"Открыть", _solo_school if map == GameState.LEVEL_SCHOOL else func(): GameState.start(_selected))
	_mode_card(row, "02   /   ПО СЕТИ", "Прятки",
		"Присоединяйся к комнате по коду и играй за команду ищущих или прячущихся.",
		"Ввести код комнаты", _lobby)


func _solo_school() -> void:
	var box := _interior("ШКОЛА № 120", "Одиночная игра", "", func(): _modes(GameState.LEVEL_SCHOOL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	_mode_card(row, "СВОБОДНАЯ ИГРА", "Песочница", "Исследуй школу в своём темпе.", "Играть", func(): GameState.start(_selected))
	_mode_card(row, "ТРЕНИРОВКА", "Искать Шороха", "Бот меняет укрытия, оставляет следы и отвечает в чате.", "Искать бота",
		func(): GameState.start(_selected, "", true))
	box.add_child(BotModelPanel.new())
	if GameState.developer_tools() and OS.get_name() == "Windows":
		var practice := HBoxContainer.new()
		practice.add_theme_constant_override("separation", 12)
		box.add_child(practice)
		var count := SchoolReplayRecorder.completed(SchoolReplayRecorder.batch())
		var title := "Продолжить запись · %d из 5" % count if count > 0 and count < 5 else "Записать 5 раундов"
		practice.add_child(MenuStyle.button(title, func(): GameState.start(GameState.LEVEL_SCHOOL, "", true, true), true, 54))
		practice.add_child(MenuStyle.button("Открыть папку записей", SchoolReplayRecorder.open_folder, false, 54))


func _mode_card(parent: HBoxContainer, badge: String, title: String, info: String, action: String, callback: Callable) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 318
	card.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#151c24f7")))
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	card.add_child(body)
	body.add_child(MenuStyle.label(badge, 20, MenuStyle.GOLD))
	body.add_child(MenuStyle.label(title, 44))
	var summary := MenuStyle.label(info, 23, MenuStyle.MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(summary)
	body.add_child(MenuStyle.button(action, callback, true))


func _lobby() -> void:
	var web := OS.has_feature("web")
	var box := _interior("ПРЯТКИ   /   ПОДКЛЮЧЕНИЕ", "Войти в комнату",
		"Введи код комнаты. Коды онлайн-комнат начинаются с BP.", _home)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var address := LineEdit.new()
	address.placeholder_text = "BP‑XXXX‑XXXX" if web else "BP‑XXXX‑XXXX или XXXX‑XXXX‑XXXX"
	address.max_length = 32
	address.custom_minimum_size.x = 460
	address.add_theme_font_size_override("font_size", 29)
	address.add_theme_stylebox_override("normal", MenuStyle.panel(MenuStyle.PANEL))
	row.add_child(address)
	var endpoint := LineEdit.new()
	endpoint.placeholder_text = "Адрес онлайн-сервера, wss://…/rooms"
	endpoint.text = OnlineRooms.configured_url()
	endpoint.max_length = 400
	endpoint.custom_minimum_size.y = 55
	endpoint.hide()
	box.add_child(endpoint)
	address.text_changed.connect(func(value: String): endpoint.visible = not web and value.strip_edges().to_upper().begins_with("BP"))
	var join := func(): WebSession.join_room(address.text, endpoint.text)
	row.add_child(MenuStyle.button("Подключиться", join, true, 65))
	address.text_submitted.connect(func(_value: String): join.call())
	endpoint.text_submitted.connect(func(_value: String): join.call())
	address.grab_focus()
	_status = MenuStyle.label(WebSession.last_error, 24, MenuStyle.GOLD)
	box.add_child(_status)


func _create_web_room() -> void:
	WebSession.leave()
	var box := _interior("ПРЯТКИ   /   БРАУЗЕР", "Арена", "Прятки вдвоём. Создай комнату и отправь код другу.", _home)
	box.add_child(MenuStyle.button("Создать онлайн-комнату", func():
		WebSession.host_online(GameState.LEVEL_HIDE, {"seek": 105}), true, 65))
	_status = MenuStyle.label("", 24, MenuStyle.GOLD)
	box.add_child(_status)


func _create_room() -> void:
	WebSession.leave()
	var box := _interior("ПРЯТКИ   /   СОЗДАНИЕ", "Создать комнату", "", _home)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var setup := RoomSetup.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(setup)
	_status = MenuStyle.label("", 24, MenuStyle.GOLD)
	box.add_child(_status)


func _lobby_changed() -> void:
	if not WebSession.joined or WebSession.connected:
		if _room_waiting:
			_lobby()
		return
	if not _room_waiting:
		var network := "ОНЛАЙН" if WebSession.is_online() else "ЛОКАЛЬНАЯ СЕТЬ"
		var box := _interior("ПРЯТКИ   /   " + network, GameState.map_info(WebSession.rules.map)[0], "", _home)
		_room_waiting = true
		var rules := WebSession.rules
		box.add_child(MenuStyle.label("%d ищущих   /   %d прячущихся   ·   %s" % [
			rules.seekers, rules.hiders, RoomRules.ZONES[rules.zone]], 25, MenuStyle.MUTED))
		_lobby_count = MenuStyle.label("", 31, MenuStyle.GOLD)
		box.add_child(_lobby_count)
		_lobby_roster = GridContainer.new()
		_lobby_roster.columns = 4
		_lobby_roster.add_theme_constant_override("h_separation", 13)
		_lobby_roster.add_theme_constant_override("v_separation", 9)
		box.add_child(_lobby_roster)
		if WebSession.is_host:
			var room_code := MenuStyle.label(WebSession.code, 48)
			box.add_child(room_code)
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 14)
			box.add_child(actions)
			actions.add_child(MenuStyle.button("Скопировать код", func(): DisplayServer.clipboard_set(room_code.text), false, 58))
			if not WebSession.is_online():
				var adapters := OptionButton.new()
				for ip in WebSession.lan_addresses():
					adapters.add_item(ip)
				adapters.item_selected.connect(func(i: int): room_code.text = WebSession.code_for(adapters.get_item_text(i)))
				if adapters.item_count > 1:
					actions.add_child(adapters)
				else:
					adapters.free()
			_host_launch = MenuStyle.button("Начать раунд", WebSession.begin_room, true, 64)
			box.add_child(_host_launch)
		else:
			box.add_child(MenuStyle.label("Создатель запустит раунд, когда все подключатся.", 23, MenuStyle.MUTED))
	_lobby_count.text = "Игроки %d / %d%s" % [WebSession.lobby_count(), RoomRules.human_count(WebSession.rules),
		"   ·   Шорох в команде прячущихся" if WebSession.rules.bot else ""]
	for card in _lobby_roster.get_children():
		_lobby_roster.remove_child(card)
		card.queue_free()
	for side in WebSession.lobby_count():
		_lobby_portrait(side, "Создатель" if side == 0 else "Игрок %d" % (side + 1))
	if WebSession.rules.bot:
		_lobby_portrait(RoomRules.BOT_SIDE, "Шорох · ИИ")
	if is_instance_valid(_host_launch):
		_host_launch.disabled = not WebSession.can_start()


func _lobby_portrait(side: int, title: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#1a2631"), Color("#324451")))
	_lobby_roster.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var portrait := RoomPortrait.new()
	portrait.side = side
	row.add_child(portrait)
	row.add_child(MenuStyle.label(title, 19))


func _status_message(text: String) -> void:
	if is_instance_valid(_status) and _status.is_inside_tree():
		_status.text = text


func _settings() -> void:
	var box := _interior("BREAKPOINT   /   ПАРАМЕТРЫ", "Настройки", "", _home)
	box.add_child(GameSettingsPanel.new())


func _unhandled_input(event: InputEvent) -> void:
	if _back_action.is_valid() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_action.call()


func _space(parent: Control, height: int) -> void:
	var node := Control.new()
	node.custom_minimum_size.y = height
	parent.add_child(node)
