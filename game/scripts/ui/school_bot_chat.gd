class_name SchoolBotChat
extends CanvasLayer

const SYSTEM := "Ты — Шорох, соперник игрока в прятках на карте «Школа № 120» в BREAKPOINT. Ты прячешься, игрок ищет. Говори от первого лица и обращайся к игроку на «ты». Отвечай по-русски одной или двумя короткими фразами. Можно дружелюбно подколоть соперника. Не выдавай своё местоположение и не выдумывай правила. Для поимки нужно 5 попаданий по 20 здоровья. Проверка шкафа только раскрывает укрытие."
const EXAMPLE := [
	{"role": "user", "content": "Ты где?"},
	{"role": "assistant", "content": "Так я тебе и сказал! Послушай, не скрипит ли где паркет."},
]
const MAX_HISTORY := 6
const MAX_LINES := 22
const BOT_INK := Color("#f0bb80")
const PLAYER_INK := Color("#9bd9e7")

var player: Player
var pause_menu: PauseMenu
var opened := false
var teammate := false
var local_model := true
var team_system := ""
var can_open: Callable
var tactical_reply: Callable
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _messages: VBoxContainer
var _round_label: Label
var _entry: LineEdit
var _send: Button
var _toast: Label
var _status: Label
var _previous_mouse := Input.MOUSE_MODE_CAPTURED
var _lines: Array[Dictionary] = []
var _history: Array[Dictionary] = []
var _waiting := false
var _toast_left := 0.0
var _round_phase := "hide"
var _round_seconds := 0
var _round_remaining := 0


func _ready() -> void:
	layer = 16
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast = MenuStyle.label("", 18, MenuStyle.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_outline_color", Color("#0d1218"))
	_toast.add_theme_constant_override("outline_size", 7)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)
	_right(_toast, 430.0, 82.0, 155.0)
	_toast.hide()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#111b25fa"), Color("#435467"), 17))
	_root.add_child(_panel)
	_right(_panel, 514.0, 82.0, 612.0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 11)
	_panel.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 13)
	body.add_child(header)
	header.add_child(_portrait())
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	identity.add_child(MenuStyle.label("Шорох", 27, BOT_INK))
	_round_label = MenuStyle.label("", 15, Color("#9cabbc"))
	identity.add_child(_round_label)
	var close := _compact_button("×", close_chat)
	close.tooltip_text = "Закрыть чат (Esc)"
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_messages = VBoxContainer.new()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 7)
	_scroll.add_child(_messages)
	_status = MenuStyle.label("", 16, MenuStyle.MUTED)
	body.add_child(_status)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 7)
	body.add_child(quick)
	var prompts := ["Иди на 4 этаж", "Спрячься в подвале", "Сколько осталось?"] if teammate else ["Как искать?", "Когда сигнал?", "Сколько осталось?"]
	for prompt: String in prompts:
		quick.add_child(_compact_button(prompt, _submit.bind(prompt)))
	var compose := HBoxContainer.new()
	compose.add_theme_constant_override("separation", 10)
	body.add_child(compose)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Сообщение боту"
	_entry.max_length = 240
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.add_theme_font_size_override("font_size", 18)
	_entry.add_theme_stylebox_override("normal", MenuStyle.panel(Color("#0c131c"), Color("#45566a"), 9))
	_entry.text_submitted.connect(_submit)
	compose.add_child(_entry)
	_send = MenuStyle.button("Отправить", func(): _submit(_entry.text), true, 45)
	compose.add_child(_send)
	_panel.hide()
	BotLanguage.changed.connect(_refresh_status)
	_refresh_status()
	set_round_clock("hide", 0, 0)


func open_chat() -> void:
	if opened or not _available() or player.navigation_menu_open:
		return
	opened = true
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.navigation_menu_open = true
	_panel.show()
	_toast.hide()
	if not bool(GameState.map_options.reduced_motion):
		_panel.modulate.a = 0.65
		create_tween().tween_property(_panel, "modulate:a", 1.0, 0.16)
	_scroll_to_end.call_deferred()
	_entry.grab_focus()
	if local_model:
		BotLanguage.warmup()


func close_chat() -> void:
	if not opened:
		return
	opened = false
	player.navigation_menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if OS.has_feature("web") else _previous_mouse
	_entry.release_focus()
	_panel.hide()


func say(line: String) -> void:
	_append("Бот", line)
	if not opened and _available():
		_toast.text = "Шорох  ·  " + line
		_toast_left = 5.5
		_toast.show()


func _available() -> bool:
	return (not can_open.is_valid() or bool(can_open.call())) and is_instance_valid(player) and not player.dead and not player.transit_active \
		and not pause_menu.is_open() and (not is_instance_valid(pause_menu.editor) or not pause_menu.editor.active)


func _process(delta: float) -> void:
	_root.visible = _available()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.hide()


func _input(event: InputEvent) -> void:
	if opened and event.is_action_pressed("ui_cancel"):
		close_chat()
	elif not opened and event.is_action_pressed("bot_chat") and not event.is_echo() and _available() and not player.navigation_menu_open:
		open_chat()
	else:
		return
	get_viewport().set_input_as_handled()


func _submit(raw: String) -> void:
	var question := raw.strip_edges()
	if not opened or _waiting or question.is_empty():
		return
	_entry.clear()
	_append("Ты", question)
	_waiting = true
	_refresh_status()
	var answer := ""
	if teammate and tactical_reply.is_valid():
		answer = str(await tactical_reply.call(question))
	if answer.is_empty():
		answer = _round_answer(question)
	var warmup_deadline := Time.get_ticks_msec() + 4000
	while local_model and answer.is_empty() and BotLanguage.state in ["verifying", "loading"] and Time.get_ticks_msec() < warmup_deadline:
		await get_tree().process_frame
	if local_model and answer.is_empty() and BotLanguage.state == "ready":
		# Короткое решение тактики может уже стоять в очереди.
		var deadline := Time.get_ticks_msec() + 1600
		while BotLanguage.busy() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var round_info := "Поиск ещё не начался." if _round_phase == "hide" else "Прошло %d секунд поиска." % _round_seconds
		var context: Array = [{"role": "system", "content": (team_system if teammate else SYSTEM) + " " + round_info}]
		if not teammate:
			context.append_array(EXAMPLE)
		context.append_array(_history)
		context.append({"role": "user", "content": question})
		answer = await BotLanguage.generate(get_instance_id(), context, 55)
		answer = _clean(answer)
	if answer.is_empty():
		answer = _quick_reply(question)
	_history.append({"role": "user", "content": question})
	_history.append({"role": "assistant", "content": answer})
	while _history.size() > MAX_HISTORY:
		_history.pop_front()
	say(answer)
	_waiting = false
	_refresh_status()


func _clean(answer: String) -> String:
	var line := answer.replace("\n", " ").replace("\r", " ").strip_edges().left(210)
	var cyrillic := 0
	for index in line.length():
		var character := line.unicode_at(index)
		if character >= 0x0400 and character <= 0x04ff:
			cyrillic += 1
	return line if cyrillic >= 4 else ""


func _quick_reply(question: String) -> String:
	var words := question.to_lower()
	if teammate:
		if "привет" in words:
			return "Привет! Можно договориться, на каком этаже я спрячусь."
		return "Я могу пойти во двор, в подвал или на выбранный этаж. Для произвольных ответов нужна локальная Qwen у создателя комнаты."
	if "гудок" in words or "сигнал" in words:
		return "Гудок выдаёт точку, где я был. После сигнала я меняю место."
	if "где" in words or "пряч" in words or "подсказ" in words:
		return "Послушай шаги и гудок. Если побегу, ты это услышишь."
	if "правил" in words or "как играть" in words or "поймать" in words:
		return "Найди меня до конца раунда и попади пять раз. Один удар или выстрел снимает 20 здоровья."
	if "привет" in words or "здрав" in words:
		return "Привет! Ну что, сыграем в прятки?"
	return "Я пока занят побегом. Спроси про правила, шаги или гудок."


func set_round_clock(phase: String, seconds: int, remaining: int) -> void:
	if _round_phase == phase and _round_seconds == seconds and _round_remaining == remaining and not _round_label.text.is_empty():
		return
	_round_phase = phase
	_round_seconds = seconds
	_round_remaining = remaining
	_round_label.text = ("Обсуждение тактики" if teammate else "Ищу укрытие") if phase == "hide" else "Поиск · %02d:%02d" % [seconds / 60, seconds % 60]


func _round_answer(question: String) -> String:
	var words := question.to_lower()
	if "сколько" in words and ("остал" in words or "врем" in words):
		if _round_phase == "hide":
			return "До начала поиска %d с." % _round_remaining if teammate else "Пока я прячусь. На поиск у тебя будет пять с половиной минут."
		return "До конца поиска %d мин %02d с." % [_round_remaining / 60, _round_remaining % 60]
	if teammate:
		return ""
	if "когда" in words and ("сигнал" in words or "гудок" in words or "подсказ" in words):
		return "Первый гудок будет через минуту после начала поиска." if _round_seconds < 60 else "Метка гудка показывает, откуда прозвучал сигнал. После него я ухожу."
	if _round_seconds < 60 and ("подсказ" in words or "где ты" in words):
		return "Дай мне минуту поиска. Потом я подам сигнал."
	if "как искать" in words:
		return "Слушай шаги, проверяй шкафчики и смотри на метку гудка. Чтобы поймать меня, попади пять раз."
	return ""


func _append(author: String, line: String) -> void:
	_lines.append({"author": author, "line": line})
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
		var oldest := _messages.get_child(0)
		_messages.remove_child(oldest)
		oldest.queue_free()
	var mine := author == "Ты"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	_messages.add_child(row)
	var bubble := PanelContainer.new()
	bubble.custom_minimum_size.x = 372.0
	bubble.add_theme_stylebox_override("panel", MenuStyle.panel(
		Color("#153341") if mine else Color("#202c3c"),
		Color("#315566") if mine else Color("#39485c"), 12))
	row.add_child(bubble)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	bubble.add_child(content)
	var clock := "%02d:%02d" % [_round_seconds / 60, _round_seconds % 60]
	content.add_child(MenuStyle.label(("Ты" if mine else "Шорох") + "   ·   " + clock, 14, PLAYER_INK if mine else BOT_INK))
	var body := MenuStyle.label(line, 19, Color("#edf0f6"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(body)
	if opened:
		_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _compact_button(title: String, handler: Callable) -> Button:
	var button := MenuStyle.button(title, handler, false, 34)
	button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed"]:
		var plate := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		plate.content_margin_left = 11
		plate.content_margin_right = 11
		plate.content_margin_top = 6
		plate.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, plate)
	return button


func _portrait() -> TextureRect:
	var colors := [Color("#243243"), Color("#503629"), Color("#6d4b36"), Color("#d59b68"),
		Color("#edbc82"), Color("#222635"), Color("#567080")]
	var pixels := ["00111100", "01222110", "01143410", "01454540", "00444400", "00033000", "06655660", "06555560"]
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			image.set_pixel(x, y, colors[int(pixels[y][x])])
	var view := TextureRect.new()
	view.texture = ImageTexture.create_from_image(image)
	view.custom_minimum_size = Vector2(48, 48)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


func _refresh_status() -> void:
	if not local_model and is_instance_valid(_status):
		_status.text = "Шорох печатает…" if _waiting else "Командный чат"
		_send.disabled = _waiting
		return
	_send.disabled = _waiting
	if _waiting:
		_status.text = "Бот отвечает…"
	elif BotLanguage.state == "ready":
		_status.text = "Шорох · Qwen офлайн"
	elif BotLanguage.state in ["verifying", "loading"]:
		_status.text = "Подключаем модель…"
	else:
		_status.text = "Быстрые ответы · Qwen в меню выбора режима"


func _right(control: Control, width: float, top: float, bottom: float) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	control.offset_left = -width - 24.0
	control.offset_right = -24.0
	control.offset_top = top
	control.offset_bottom = bottom


func _exit_tree() -> void:
	BotLanguage.cancel(get_instance_id())
