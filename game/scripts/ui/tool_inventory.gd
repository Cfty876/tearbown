class_name ToolInventory
extends Control

const ICONS := preload("res://ui/tool_icons.svg")
const ITEM_COLORS := [Color("#e6c479"), Color("#a9d8e1"), Color("#e1ae93")]
const SHORT_NAMES := ["Кувалда", "Дробовик", "Бомба", "Ракетница", "Баллончик", "Огнетушитель", "Доска", "Хамелеон", "Гудок", "Резонатор", "Бумбокс"]
const CATEGORY := ["БЛИЖНИЙ УДАР", "ОГНЕСТРЕЛЬНОЕ", "МЕТАТЕЛЬНОЕ", "ТЯЖЁЛОЕ",
	"МАРКИРОВКА", "ТУШЕНИЕ И ТЯГА", "КОНСТРУКЦИЯ", "МАСКИРОВКА", "СИГНАЛ", "ВСЕЛЕНИЕ", "МУЗЫКА"]
const TINTS := [Color("#ffcc80"), Color("#f4ac8a"), Color("#ef986a"), Color("#fbad85"),
	Color("#94d5ec"), Color("#e7a393"), Color("#e7d493"), Color("#99dac6"), Color("#decfa0"), Color("#87e1cb"), Color("#b9cfed")]
const GADGET_NAMES := ["Флешка", "Коктейль", "Газировка", "Часы"]
const IVORY := Color("#f4e9d6")
const MUTED := Color("#a8adb0")
const SLATE := Color("#171d20")
const INNER := 116.0
const OUTER := 258.0
const DEAD_ZONE := 34.0

var player: Player
var is_open := false
var _preview := 0
var _current := 0
var _pointer := Vector2.ZERO
var _touch_open := false
var _icons: Array[AtlasTexture] = []
var _gadget_icons: Array[ImageTexture] = []
var _item_icons: Array[AtlasTexture] = []
var _carried: Array[int] = []
var _has_item_slot := false
var _font: Font
var _slot: StyleBoxFlat
var _selected: StyleBoxFlat
var _plate: StyleBoxFlat
var _wheel_tween: Tween
var _wheel_amount := 0.0:
	set(value):
		_wheel_amount = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_slot = _panel(Color("#171d20ec"), Color("#66717766"), 8)
	_selected = _panel(Color("#3b3026f5"), Color("#d5a872c7"), 8)
	_plate = _panel(Color("#12181bf3"), Color("#7e858769"), 12)
	for i in PlayerTools.NAMES.size():
		var icon := AtlasTexture.new()
		icon.atlas = ICONS
		icon.region = Rect2(i * 64, 0, 64, 64)
		icon.filter_clip = true
		_icons.append(icon)
	_gadget_icons = GadgetIcons.build()
	for i in SchoolTraps.CARRIED_ITEMS.size():
		var icon := AtlasTexture.new()
		icon.atlas = ICONS
		icon.region = Rect2((PlayerTools.NAMES.size() + i) * 64, 0, 64, 64)
		icon.filter_clip = true
		_item_icons.append(icon)
	_current = player.tools.current
	player.tools.selection_changed.connect(_select)
	player.tools.slots_changed.connect(_refresh_slots)
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_open and (not _can_open() or (not _touch_open and not Input.is_action_pressed("tool_inventory"))):
		_close(false)
	var show_strip := player.vehicle == null and not player.dead and not player.navigation_menu_open
	if visible != show_strip:
		visible = show_strip
	var world := VoxelWorld.instance
	var school := is_instance_valid(world) and world.secrets is SchoolSecrets and is_instance_valid(world.secrets.traps)
	var carried: Array[int] = []
	if school:
		carried = world.secrets.traps.carried_items(world.secrets.local_side)
	if _has_item_slot != school or _carried != carried:
		_has_item_slot = school
		_carried = carried
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_open:
		_close(false)


func _can_open() -> bool:
	return (
		is_visible_in_tree() and is_instance_valid(player) and player.vehicle == null
		and not player.dead and not player.navigation_menu_open and player.grabbed == null and player.possessed_npc == null and player.tools.input_enabled
		and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or player.touch_mode)
	)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("tool_inventory") and not is_open and _can_open():
		_open(false)
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if _touch_open and event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var local := get_global_transform_with_canvas().affine_inverse() * touch.position
			var relative := (local - _wheel_center()) / _wheel_scale()
			if relative.length() >= INNER and relative.length() <= OUTER + 25.0:
				_preview = _from_slot(roundi((relative.angle() + PI * 0.5) / _segment_angle()))
				_close(true)
			else:
				_close(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("tool_inventory"):
		_close(_can_open())
	elif event.is_action_pressed("ui_cancel"):
		_close(false)
	elif event is InputEventMouseMotion:
		_pointer = (_pointer + event.relative).limit_length(330.0)
		if _pointer.length_squared() > DEAD_ZONE * DEAD_ZONE:
			var angle := _pointer.angle() + PI * 0.5
			_preview = _from_slot(roundi(angle / _segment_angle()))
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: _close(false)
			MOUSE_BUTTON_WHEEL_UP: _preview_slot(_from_slot(player.tools.tool_slots().find(_preview) - 1))
			MOUSE_BUTTON_WHEEL_DOWN: _preview_slot(_from_slot(player.tools.tool_slots().find(_preview) + 1))
	elif event is InputEventKey:
		for i in range(PlayerTools.GADGET_START):
			if event.is_action_pressed("tool_%d" % (i + 1)):
				_preview_slot(i)
				break
	if event is InputEventMouse or event is InputEventKey or event.is_action("tool_inventory"):
		get_viewport().set_input_as_handled()


func open_touch() -> void:
	if not is_open and _can_open():
		_open(true)


func _open(by_touch: bool) -> void:
	is_open = true
	_touch_open = by_touch
	_preview = _current
	_pointer = Vector2.ZERO
	player.tools.set_inventory_open(true)
	_animate_wheel(1.0, 0.19)


func _preview_slot(index: int) -> void:
	_preview = index if index in player.tools.tool_slots() else _current
	_pointer = Vector2.ZERO
	queue_redraw()


func _close(confirm: bool) -> void:
	is_open = false
	_touch_open = false
	if is_instance_valid(player):
		if confirm:
			player.tools.select(_preview)
		player.tools.set_inventory_open(false)
	_animate_wheel(0.0, 0.13)


func _animate_wheel(goal: float, seconds: float) -> void:
	if _wheel_tween:
		_wheel_tween.kill()
	_wheel_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_wheel_tween.tween_property(self, "_wheel_amount", goal, seconds)
	queue_redraw()


func _select(index: int) -> void:
	_current = index
	queue_redraw()


func _refresh_slots() -> void:
	if _preview not in player.tools.tool_slots():
		_preview = player.tools.current
	queue_redraw()


func _draw() -> void:
	if is_instance_valid(player) and is_instance_valid(player.possessed_npc):
		_draw_carried(false)
		return
	if _icons.is_empty():
		return
	if player.touch_mode:
		if _wheel_amount < 0.05:
			var area := Rect2(size.x * 0.5 - 124.0, 20.0, 248.0, 56.0)
			draw_style_box(_plate, area)
			_icon(_current, area.position + Vector2(33, 28), 49.0, _tint(_current))
			_text(_short_name(_current), Rect2(area.position + Vector2(59, 8), Vector2(145, 38)),
				21, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
			if PlayerTools.is_gadget(_current):
				_text(_amount(_current), Rect2(area.position + Vector2(206, 8), Vector2(33, 38)), 15, _tint(_current))
	else:
		if _wheel_amount < 0.1:
			_draw_loadout()
	if _wheel_amount > 0.002:
		_draw_wheel()
	_draw_carried(_wheel_amount > 0.1)


func _draw_carried(expanded: bool) -> void:
	if not _has_item_slot or (_carried.is_empty() and not expanded):
		return
	var panel_size := Vector2(235, 53)
	var at := Vector2(size.x - 266.0, size.y - 201.0)
	if player.touch_mode:
		at = Vector2(26, 106)
	if expanded:
		panel_size.y = 52.0 + float(_carried.size()) * 35.0
		at.y = clampf(size.y * 0.45 - panel_size.y * 0.5, 90.0, size.y - panel_size.y - 45.0)
	var area := Rect2(at, panel_size)
	draw_style_box(_slot, area)
	var title_at := at + Vector2(12, 4)
	_text("ПРЕДМЕТЫ", Rect2(title_at, Vector2(209, 22)), 12, Color("#b8cacc"), HORIZONTAL_ALIGNMENT_LEFT)
	if expanded:
		if _carried.is_empty():
			_text("Слот пуст", Rect2(at + Vector2(12, 23), Vector2(209, 22)), 15, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		for i in _carried.size():
			var item := _carried[i]
			var row := at + Vector2(11, 27 + i * 35)
			draw_texture_rect(_item_icons[item], Rect2(row, Vector2(29, 29)), false, ITEM_COLORS[item])
			_text(SchoolTraps.CARRIED_ITEMS[item], Rect2(row + Vector2(36, 0), Vector2(174, 28)), 15, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		for i in _carried.size():
			var item := _carried[i]
			draw_texture_rect(_item_icons[item], Rect2(at + Vector2(11 + i * 32, 23), Vector2(28, 28)), false, ITEM_COLORS[item])
		var description: String = SchoolTraps.CARRIED_ITEMS[_carried[0]] if _carried.size() == 1 else "%d предмета" % _carried.size()
		var text_x := 15.0 + _carried.size() * 32.0
		_text(description, Rect2(at + Vector2(text_x, 24), Vector2(222.0 - text_x, 23)), 14, IVORY, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_loadout() -> void:
	var origin := Vector2(size.x - 266.0, size.y - 84.0)
	_draw_loadout_slot(_current, origin, true)
	var previous := player.tools.previous
	if previous in player.tools.tool_slots() and previous != _current:
		_draw_loadout_slot(previous, origin - Vector2(0, 57), false)


func _draw_loadout_slot(index: int, at: Vector2, active: bool) -> void:
	var color: Color = IVORY if active else MUTED
	draw_style_box(_selected if active else _slot, Rect2(at, Vector2(235, 52)))
	_icon(index, at + Vector2(47, 26), 55.0, color)
	_text(_short_name(index), Rect2(at + Vector2(83, 3), Vector2(137, 29)), 18, color, HORIZONTAL_ALIGNMENT_LEFT)
	var number := _amount(index) if PlayerTools.is_gadget(index) else player.tools.slot_label(index)
	_text("%s  /  %s" % [number, "В РУКЕ" if active else "ПРЕДЫДУЩЕЕ"],
		Rect2(at + Vector2(83, 29), Vector2(144, 19)), 12, _tint(index) if active else MUTED, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_wheel() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.027, 0.033, 0.039, _wheel_amount * 0.74))
	draw_set_transform(_wheel_center(), 0.0, Vector2.ONE * _wheel_scale())
	var active := _tint(_preview)
	draw_circle(Vector2.ZERO, OUTER + 13.0, Color("#0c1114df"), true, -1, true)
	draw_arc(Vector2.ZERO, OUTER + 12.0, 0.0, TAU, 96, Color("#81909575"), 1.0, true)
	var slots := player.tools.tool_slots()
	var half := TAU / slots.size() * 0.5 - 0.027
	var label_width := minf(136.0, 370.0 * sin(half) - 4.0)
	for i in slots:
		var a := _angle(i)
		var selected := i == _preview
		var color := _tint(i)
		var fill := SLATE.lerp(color, 0.19) if selected else SLATE
		draw_colored_polygon(_wedge(a - half, a + half), fill)
		var line := color if selected else Color("#49555c")
		draw_arc(Vector2.ZERO, OUTER, a - half, a + half, 20, line, 3.0 if selected else 1.0, true)
		if selected:
			draw_arc(Vector2.ZERO, INNER + 4, a - half, a + half, 18, color, 1.0, true)
		var radial := Vector2.from_angle(a)
		var cell := radial * 185.0
		var number := _amount(i) if PlayerTools.is_gadget(i) else player.tools.slot_label(i, slots)
		if slots.size() > 10:
			_icon(i, radial * 181.0, 70.0 if selected else 60.0, color if selected else MUTED)
			_text(number, Rect2(radial * 230.0 - Vector2(28, 9), Vector2(56, 18)), 15, line)
		else:
			_icon(i, cell - Vector2(0, 5), 76.0 if selected else 65.0, color if selected else MUTED)
			_text(_short_name(i), Rect2(cell + Vector2(-label_width * 0.5, 27), Vector2(label_width, 24)),
				18, IVORY if selected else MUTED)
			_text(number, Rect2(cell + Vector2(-38, -49), Vector2(76, 17)), 14, line)
	draw_circle(Vector2.ZERO, INNER - 5.0, Color("#10171a"), true, -1, true)
	draw_arc(Vector2.ZERO, INNER - 5.0, 0.0, TAU, 64, Color("#84909382"), 1.0, true)
	_icon(_preview, Vector2(0, -23), 102.0, active)
	var category: String = "ГАДЖЕТ" if PlayerTools.is_gadget(_preview) else CATEGORY[_preview]
	_text(category, Rect2(-96, 37, 192, 23), 15, active)
	_text("%02d  /  %02d" % [slots.find(_preview) + 1, slots.size()], Rect2(-84, 65, 168, 21), 16, MUTED)
	var caret := Vector2.from_angle(_angle(_preview)) * (OUTER + 23.0)
	draw_circle(caret, 4.0, active, true, -1, true)
	_text("С Н А Р Я Ж Е Н И Е", Rect2(-215, -331, 430, 34), 23, IVORY)
	draw_style_box(_plate, Rect2(-260, 293, 520, 100))
	_text(PlayerTools.title_for(_preview).to_upper(), Rect2(-244, 307, 488, 33), 24, active)
	_text(PlayerTools.hint_for(_preview), Rect2(-244, 350, 488, 24), 17, IVORY)
	var instruction := "КОСНИСЬ СЕКТОРА  ·  ВЫБРАТЬ" if player.touch_mode else "ОТПУСТИ TAB  ·  ВЫБРАТЬ        ESC / ПКМ  ·  ОТМЕНА"
	_text(instruction, Rect2(-310, 407, 620, 22), 18, MUTED)
	draw_set_transform(Vector2.ZERO)


func _wheel_center() -> Vector2:
	return size * 0.5 + Vector2(0, -16)


func _wheel_scale() -> float:
	return minf(1.0, minf(size.x / 620.0, size.y / 940.0)) * lerpf(0.87, 1.0, _wheel_amount)


func _segment_angle() -> float:
	return TAU / player.tools.tool_slots().size()


func _angle(i: int) -> float:
	return _segment_angle() * player.tools.tool_slots().find(i) - PI * 0.5


func _from_slot(index: int) -> int:
	var slots := player.tools.tool_slots()
	return slots[posmod(index, slots.size())]


func _wedge(start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	const STEPS := 18
	for i in range(STEPS + 1):
		points.append(Vector2.from_angle(lerpf(start, end, float(i) / STEPS)) * OUTER)
	for i in range(STEPS, -1, -1):
		points.append(Vector2.from_angle(lerpf(start, end, float(i) / STEPS)) * INNER)
	return points


func _tint(index: int) -> Color:
	return GameGadgets.TINTS[index - PlayerTools.GADGET_START] if PlayerTools.is_gadget(index) else TINTS[index]


func _short_name(index: int) -> String:
	return GADGET_NAMES[index - PlayerTools.GADGET_START] if PlayerTools.is_gadget(index) else SHORT_NAMES[index]


func _amount(index: int) -> String:
	return "×%d" % player.tools.gadget_charges(index)


func _icon(index: int, at: Vector2, extent: float, tint: Color) -> void:
	var area := Rect2(at - Vector2.ONE * extent * 0.5, Vector2.ONE * extent)
	if PlayerTools.is_gadget(index):
		draw_texture_rect(_gadget_icons[index - PlayerTools.GADGET_START], area.grow(-extent * 0.12), false)
	else:
		draw_texture_rect(_icons[index], area, false, tint)


func _text(text: String, box: Rect2, font_size: int, tint: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var baseline := (box.size.y - _font.get_height(font_size)) * 0.5 + _font.get_ascent(font_size)
	draw_string(_font, box.position + Vector2(0, baseline), text, align, box.size.x, font_size, tint)


func _panel(fill: Color, edge: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style
