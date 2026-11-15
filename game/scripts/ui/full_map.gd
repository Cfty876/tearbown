class_name FullMap
extends Control
## Полноэкранный план с этажами, метками и фильтрами.

var controller: GameGadgets
var data: MapSession
var canvas: MapCanvas
var _frame: PanelContainer
var _sheet: PanelContainer
var _mouse_mode := Input.MOUSE_MODE_CAPTURED
var _title: Label
var _status: Label
var _coords: Label
var _legend: VBoxContainer
var _floor: OptionButton
var _filters: OptionButton
var _list: ItemList
var _landmarks: Array[Dictionary] = []
var _current_layer := -20
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("#071018ec")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = PanelContainer.new()
	add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 34
	_frame.offset_top = 30
	_frame.offset_right = -34
	_frame.offset_bottom = -30
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	_frame.add_child(root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	root.add_child(heading)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_stack)
	title_stack.add_child(MenuStyle.label("КАРТА МЕСТНОСТИ", 15, MenuStyle.GOLD))
	_title = MenuStyle.label("", 36)
	title_stack.add_child(_title)
	_coords = MenuStyle.label("", 16, MenuStyle.MUTED)
	heading.add_child(_coords)
	heading.add_child(_button("Закрыть", close_map))
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	root.add_child(content)
	_sheet = PanelContainer.new()
	_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_sheet)
	canvas = MapCanvas.new()
	canvas.data = data
	canvas.custom_minimum_size = Vector2(350, 270)
	canvas.pin_selected.connect(data.set_pin)
	_sheet.add_child(canvas)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 306
	side.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#142129"), Color("#354b53"), 10))
	content.add_child(side)
	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", 11)
	side.add_child(sidebar)
	sidebar.add_child(MenuStyle.label("Слои и метки", 22))
	_floor = _option()
	sidebar.add_child(_floor)
	_floor.item_selected.connect(func(index: int):
		canvas.floor_selection = _floor.get_item_id(index)
		_refresh_landmarks()
		canvas.queue_redraw())
	_filters = _option()
	_filters.add_item("Все метки", 0)
	for i in MapStyle.NAMES.size():
		_filters.add_item("%s   %s" % [MapStyle.GLYPHS[i], MapStyle.NAMES[i]], i + 1)
	_filters.item_selected.connect(func(index: int):
		canvas.category = index - 1
		_refresh_landmarks()
		canvas.queue_redraw())
	sidebar.add_child(_filters)
	var spacer := HSeparator.new()
	sidebar.add_child(spacer)
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 5)
	sidebar.add_child(_legend)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 120
	_list.add_theme_font_size_override("font_size", 15)
	_list.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#0e1920"), Color("#2c414a"), 6))
	_list.item_activated.connect(_choose_landmark)
	_list.item_selected.connect(_choose_landmark)
	sidebar.add_child(_list)
	sidebar.add_child(_button("Очистить метку", data.clear_pin))
	var footer := HBoxContainer.new()
	root.add_child(footer)
	_status = MenuStyle.label("", 16, MenuStyle.GOLD)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	footer.add_child(_button("−", func(): canvas.zoom_by(1.0 / 1.22, canvas.size * 0.5)))
	footer.add_child(_button("+", func(): canvas.zoom_by(1.22, canvas.size * 0.5)))
	footer.add_child(_button("Обзор", canvas.recenter))
	GameState.settings_changed.connect(_apply_style)
	_apply_style()


func _button(label: String, action: Callable) -> Button:
	var result := MenuStyle.button(label, action, false, 38)
	result.add_theme_font_size_override("font_size", 17)
	return result


func _option() -> OptionButton:
	var control := OptionButton.new()
	control.custom_minimum_size.y = 45
	control.add_theme_font_size_override("font_size", 17)
	return control


func _apply_style() -> void:
	var colors := MapStyle.palette()
	_frame.add_theme_stylebox_override("panel", MenuStyle.panel(colors[0], colors[1], 16))
	var plot := MenuStyle.panel(colors[0], colors[1], 4)
	plot.content_margin_left = 2
	plot.content_margin_right = 2
	plot.content_margin_top = 2
	plot.content_margin_bottom = 2
	_sheet.add_theme_stylebox_override("panel", plot)
	_title.add_theme_color_override("font_color", colors[3])
	if visible:
		_refresh_landmarks()


func open_map() -> void:
	if visible or controller.world.player.navigation_menu_open:
		return
	data.ensure_atlas()
	var player := controller.world.player
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.navigation_menu_open = true
	_title.text = str(GameState.MAPS.get(GameState.level, ["Арена"])[0])
	_floor.clear()
	_floor.add_item("Текущий этаж", MapCanvas.AUTO_FLOOR)
	for floor_id in data.atlas.layers():
		_floor.add_item(MapAtlas.floor_name(floor_id), floor_id)
	_floor.select(0)
	_filters.select(0)
	canvas.floor_selection = MapCanvas.AUTO_FLOOR
	canvas.category = -1
	canvas.recenter()
	_refresh_landmarks()
	show()
	_update_status()


func close_map() -> void:
	if not visible:
		return
	hide()
	canvas._drag = false
	canvas._touch_id = -1
	var player := controller.world.player
	if is_instance_valid(player):
		player.navigation_menu_open = false
		player.tools._fire_blocked = true
	Input.mouse_mode = _mouse_mode


func _refresh_landmarks() -> void:
	_landmarks.clear()
	_list.clear()
	_current_layer = canvas.floor_id()
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()
	var relevant := [MapStyle.POINT, MapStyle.LOOT, MapStyle.NPC, MapStyle.PING, MapStyle.HORN]
	for kind in relevant:
		if (int(GameState.map_options.markers) & (1 << kind)) != 0:
			_legend.add_child(MenuStyle.label("%s   %s" % [MapStyle.GLYPHS[kind], MapStyle.NAMES[kind]], 15, MapStyle.tint(kind)))
	for marker in data.markers:
		if marker.floor != _current_layer:
			continue
		if (int(GameState.map_options.markers) & (1 << int(marker.kind))) == 0 or (canvas.category >= 0 and marker.kind != canvas.category):
			continue
		_landmarks.append(marker)
		_list.add_item("%s   %s" % [MapStyle.GLYPHS[marker.kind], marker.title])


func _choose_landmark(index: int) -> void:
	if index >= 0 and index < _landmarks.size():
		var item := _landmarks[index]
		data.set_pin(item.at, item.floor, false)


func _input(event: InputEvent) -> void:
	var escape: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	if visible and (escape or event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_map")):
		close_map()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if controller.world.player.dead:
		close_map()
		return
	_time -= delta
	if _time <= 0.0:
		_time = 0.15
		_update_status()


func _update_status() -> void:
	var at := MapSession.xz(controller.world.player.global_position)
	_coords.text = "%s    /    X %+.0f    Z %+.0f" % [MapAtlas.floor_name(canvas.floor_id()), at.x, at.y]
	_status.text = "Перетяни карту   ·   Нажми, чтобы поставить метку" if not data.target.is_finite() else "%s   ·   %.0f м до метки" % [data.route_status, at.distance_to(data.target)]
	if _current_layer != canvas.floor_id():
		_refresh_landmarks()
