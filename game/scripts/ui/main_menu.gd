extends Control
## Title screen: pick the district map, the prototype range or the fly-throughs.
## Any scripted command line run (--bench, --level, --cinematic, ...) skips it.

const AUTOSTART := ["bench", "tour", "drive", "tools", "crater", "dtour", "audit", "glass", "level", "cinematic"]
var _loading := false
var _touch := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").split("=")[0] in AUTOSTART:
			GameState.start.call_deferred(GameState.level, GameState.cinematic)
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_touch = TouchControls.available()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://ui/menu_bg.png"):
		bg.texture = load("res://ui/menu_bg.png")
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.04, 0.03, 0.55)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	box.offset_left = 110
	box.offset_top = -410 if _touch else -320
	box.offset_right = 760
	box.offset_bottom = 230
	box.add_theme_constant_override("separation", 9 if _touch else 14)
	add_child(box)
	var title := Label.new()
	title.text = "ВОКСЕЛЬНЫЙ СНОС"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Полностью разрушаемый воксельный мир"
	sub.add_theme_font_size_override("font_size", 22)
	sub.modulate = Color(1, 1, 1, 0.8)
	box.add_child(sub)
	box.add_child(_spacer(26))
	if WebSession.available():
		_button(box, "Прятки вдвоём — по коду", WebSession.show_rooms)
	_button(box, "Американский пригород — карта", func(): _launch(GameState.LEVEL_DISTRICT))
	if OS.has_feature("web"):
		var maps := HBoxContainer.new()
		maps.add_theme_constant_override("separation", 10)
		box.add_child(maps)
		_button(maps, "Полигон", func(): _launch(GameState.LEVEL_PROTO), 320)
		_button(maps, "Лёгкая карта", func(): _launch(GameState.LEVEL_POCKET), 320)
	else:
		_button(box, "Полигон — прототип механик", func(): _launch(GameState.LEVEL_PROTO))
	_button(box, "Кинопролёты по пригороду", func(): _launch(GameState.LEVEL_DISTRICT, "all"))
	var q := OptionButton.new()
	for n in Quality.NAMES:
		q.add_item("Графика: " + n)
	q.selected = GameState.quality
	q.item_selected.connect(func(i: int):
		GameState.quality = i
		GameState.save_graphics())
	q.add_theme_font_size_override("font_size", 33 if _touch else 24)
	q.custom_minimum_size = Vector2(520, 78 if _touch else 54)
	box.add_child(q)
	var lens := CheckButton.new()
	lens.text = "Мягкие края и солнечные лучи" if OS.has_feature("web") else "Автофокус, мягкие края и солнечные лучи"
	if _touch:
		lens.add_theme_font_size_override("font_size", 30)
		lens.custom_minimum_size.y = 66
	lens.button_pressed = GameState.lens_effects
	lens.toggled.connect(func(on: bool):
		GameState.lens_effects = on
		GameState.save_graphics())
	box.add_child(lens)
	var motion := CheckButton.new()
	motion.text = "Размытие при резком повороте"
	if _touch:
		motion.add_theme_font_size_override("font_size", 30)
		motion.custom_minimum_size.y = 66
	motion.button_pressed = GameState.motion_blur
	motion.toggled.connect(func(on: bool):
		GameState.motion_blur = on
		GameState.save_graphics())
	box.add_child(motion)
	_button(box, "Выход", GameState.exit_game)
	var hint := Label.new()
	hint.text = "Esc в игре — пауза и возврат в меню"
	if _touch:
		hint.text = "Играй горизонтально. Пауза в правом верхнем углу."
	if not WebSession.last_error.is_empty():
		hint.text = WebSession.last_error
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)


func _launch(map: String, cinematic := "") -> void:
	if _loading:
		return
	_loading = true
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.055, 0.038, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var status := Label.new()
	status.text = "Загрузка воксельного мира…"
	status.add_theme_font_size_override("font_size", 32)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(status)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.start(map, cinematic)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(parent: Control, text: String, cb: Callable, width := 0) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(600, 96) if _touch else Vector2(520, 58)
	if width > 0:
		b.custom_minimum_size.x = width
	b.add_theme_font_size_override("font_size", 37 if _touch else 28)
	b.pressed.connect(cb)
	parent.add_child(b)
