class_name ToolInventory
extends Control

const ICONS := preload("res://ui/tool_icons.svg")
const SHORT_NAMES := ["Кувалда", "Дробовик", "Бомба", "Ракетница", "Горелка", "Баллончик", "Огнетуш."]
const CATEGORY := ["БЛИЖНИЙ УДАР", "ОГНЕСТРЕЛЬНОЕ", "МЕТАТЕЛЬНОЕ", "ТЯЖЁЛОЕ",
	"РЕЗКА", "МАРКИРОВКА", "ТУШЕНИЕ"]
const TINTS := [Color("#ffcc80"), Color("#f4ac8a"), Color("#ef986a"), Color("#fbad85"),
	Color("#94d5ec"), Color("#e7d493"), Color("#99dac6")]
const IVORY := Color("#f4e9d6")
const MUTED := Color("#a8adb0")
const SLATE := Color("#171d20")
const SLOT := Vector2(112, 84)
const SLOT_STEP := 120.0
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
var _font: Font
var _slot: StyleBoxFlat
var _selected: StyleBoxFlat
var _plate: StyleBoxFlat
var _wheel_tween: Tween
var _bar_tween: Tween
var _wheel_amount := 0.0:
	set(value):
		_wheel_amount = value
		queue_redraw()
var _bar_marker := 0.0:
	set(value):
		_bar_marker = value
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
	_current = player.tools.current
	_bar_marker = float(_current)
	player.tools.selection_changed.connect(_select)
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_open and (not _can_open() or (not _touch_open and not Input.is_action_pressed("tool_inventory"))):
		_close(false)
	var show_strip := player.vehicle == null and not player.dead
	if visible != show_strip:
		visible = show_strip


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_open:
		_close(false)


func _can_open() -> bool:
	return (
		is_visible_in_tree() and is_instance_valid(player) and player.vehicle == null
		and not player.dead and player.grabbed == null and player.tools.input_enabled
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
				_preview = posmod(roundi((relative.angle() + PI * 0.5) / _segment_angle()), _icons.size())
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
			_preview = posmod(roundi(angle / _segment_angle()), _icons.size())
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: _close(false)
			MOUSE_BUTTON_WHEEL_UP: _preview_slot(_preview - 1)
			MOUSE_BUTTON_WHEEL_DOWN: _preview_slot(_preview + 1)
	elif event is InputEventKey:
		for i in _icons.size():
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
	_preview = posmod(index, _icons.size())
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
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bar_tween.tween_property(self, "_bar_marker", float(index), 0.17)
	queue_redraw()


func _draw() -> void:
	if _icons.is_empty():
		return
	if player.touch_mode:
		if _wheel_amount < 0.05:
			var area := Rect2(size.x * 0.5 - 124.0, 20.0, 248.0, 56.0)
			draw_style_box(_plate, area)
			_icon(_current, area.position + Vector2(33, 28), 49.0, TINTS[_current])
			_text(SHORT_NAMES[_current], Rect2(area.position + Vector2(59, 8), Vector2(178, 38)),
				23, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		_draw_strip()
	if _wheel_amount > 0.002:
		_draw_wheel()


func _draw_strip() -> void:
	var width := SLOT_STEP * _icons.size() - (SLOT_STEP - SLOT.x)
	var zoom := minf(1.0, size.x / (width + 52.0))
	var origin := Vector2(size.x * 0.5 - width * zoom * 0.5, size.y - 126.0)
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	for i in _icons.size():
		var at := Vector2(i * SLOT_STEP, 0)
		var active := i == _current
		var accent: Color = TINTS[i] if active else MUTED
		draw_style_box(_selected if active else _slot, Rect2(at, SLOT))
		_text(str(i + 1), Rect2(at + Vector2(9, 8), Vector2(18, 20)), 17, accent)
		_icon(i, at + Vector2(SLOT.x * 0.5, 33), 54.0, accent)
		_text(SHORT_NAMES[i], Rect2(at + Vector2(3, 60), Vector2(SLOT.x - 6, 19)), 17,
			IVORY if active else MUTED)
	var marker := Vector2(_bar_marker * SLOT_STEP + 19.0, SLOT.y - 3.0)
	draw_rect(Rect2(marker, Vector2(SLOT.x - 38, 2)), TINTS[_current])
	_text("TAB  ·  СНАРЯЖЕНИЕ", Rect2(Vector2(width - 230, -27), Vector2(230, 19)),
		15, Color("#f6dfba"), HORIZONTAL_ALIGNMENT_RIGHT)
	draw_set_transform(Vector2.ZERO)


func _draw_wheel() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.027, 0.033, 0.039, _wheel_amount * 0.74))
	draw_set_transform(_wheel_center(), 0.0, Vector2.ONE * _wheel_scale())
	var active: Color = TINTS[_preview]
	draw_circle(Vector2.ZERO, OUTER + 13.0, Color("#0c1114df"), true, -1, true)
	draw_arc(Vector2.ZERO, OUTER + 12.0, 0.0, TAU, 96, Color("#81909575"), 1.0, true)
	var half := _segment_angle() * 0.5 - 0.027
	for i in _icons.size():
		var a := _angle(i)
		var selected := i == _preview
		var color: Color = TINTS[i]
		var fill := SLATE.lerp(color, 0.19) if selected else SLATE
		draw_colored_polygon(_wedge(a - half, a + half), fill)
		var line := color if selected else Color("#49555c")
		draw_arc(Vector2.ZERO, OUTER, a - half, a + half, 20, line, 3.0 if selected else 1.0, true)
		if selected:
			draw_arc(Vector2.ZERO, INNER + 4, a - half, a + half, 18, color, 1.0, true)
		var cell := Vector2.from_angle(a) * 185.0
		_icon(i, cell - Vector2(0, 5), 76.0 if selected else 65.0, color if selected else MUTED)
		_text(SHORT_NAMES[i], Rect2(cell + Vector2(-68, 28), Vector2(136, 24)), 18, IVORY if selected else MUTED)
		_text("%02d" % (i + 1), Rect2(cell + Vector2(-68, -49), Vector2(136, 17)), 14, line)
	draw_circle(Vector2.ZERO, INNER - 5.0, Color("#10171a"), true, -1, true)
	draw_arc(Vector2.ZERO, INNER - 5.0, 0.0, TAU, 64, Color("#84909382"), 1.0, true)
	_icon(_preview, Vector2(0, -23), 102.0, active)
	_text(CATEGORY[_preview], Rect2(-96, 37, 192, 23), 15, active)
	_text("%02d  /  %02d" % [_preview + 1, _icons.size()], Rect2(-84, 65, 168, 21), 16, MUTED)
	var caret := Vector2.from_angle(_angle(_preview)) * (OUTER + 23.0)
	draw_circle(caret, 4.0, active, true, -1, true)
	_text("С Н А Р Я Ж Е Н И Е", Rect2(-215, -331, 430, 34), 23, IVORY)
	draw_style_box(_plate, Rect2(-260, 293, 520, 100))
	_text(PlayerTools.NAMES[_preview].to_upper(), Rect2(-244, 307, 488, 33), 24, active)
	_text(PlayerTools.HINTS[_preview], Rect2(-244, 350, 488, 24), 17, IVORY)
	var instruction := "КОСНИСЬ СЕКТОРА  ·  ВЫБРАТЬ" if player.touch_mode else "ОТПУСТИ TAB  ·  ВЫБРАТЬ        ESC / ПКМ  ·  ОТМЕНА"
	_text(instruction, Rect2(-310, 407, 620, 22), 18, MUTED)
	draw_set_transform(Vector2.ZERO)


func _wheel_center() -> Vector2:
	return size * 0.5 + Vector2(0, -16)


func _wheel_scale() -> float:
	return minf(1.0, minf(size.x / 620.0, size.y / 940.0)) * lerpf(0.87, 1.0, _wheel_amount)


func _segment_angle() -> float:
	return TAU / _icons.size()


func _angle(i: int) -> float:
	return _segment_angle() * i - PI * 0.5


func _wedge(start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	const STEPS := 18
	for i in range(STEPS + 1):
		points.append(Vector2.from_angle(lerpf(start, end, float(i) / STEPS)) * OUTER)
	for i in range(STEPS, -1, -1):
		points.append(Vector2.from_angle(lerpf(start, end, float(i) / STEPS)) * INNER)
	return points


func _icon(index: int, at: Vector2, extent: float, tint: Color) -> void:
	draw_texture_rect(_icons[index], Rect2(at - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), false, tint)


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
