class_name RoundBoard
extends Control

const SURVIVOR := Color("#7ce0d0")
const SEEKER := Color("#ffca89")
const EDGE := Color("#3c4d56")

var _body: PanelContainer
var _trim: Control
var _phase: Label
var _clock: Label
var _hiders: Label
var _seekers: Label
var _role: Label
var _ratio := 0.0
var _accent := SURVIVOR
var _last_phase := ""
var _seconds := -1
var _hider_count := -1
var _seeker_count := -1
var _intro: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -271
	offset_right = 271
	offset_top = 24
	offset_bottom = 132
	_body = PanelContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := MenuStyle.panel(Color("#111d26f5"), EDGE, 11)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 12
	style.shadow_color = Color("#06101880")
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	_body.add_theme_stylebox_override("panel", style)
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_constant_override("separation", 12)
	_body.add_child(strip)
	var left := _column(strip, 140)
	_hiders = _blip(left, "0", 36, SURVIVOR)
	_blip(left, "ОСТАЛИСЬ", 15, Color("#b6d9d4"))
	_rule(strip)
	var middle := _column(strip, 164)
	_phase = _blip(middle, "ПОДГОТОВКА", 14, MenuStyle.MUTED)
	_clock = _blip(middle, "00:00", 38, MenuStyle.TEXT)
	_role = _blip(middle, "", 13, Color("#b7c3ce"))
	_rule(strip)
	var right := _column(strip, 140)
	_seekers = _blip(right, "0", 36, SEEKER)
	_blip(right, "ИЩУЩИЕ", 15, Color("#eed6b6"))
	_trim = Control.new()
	_trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_trim)
	_trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trim.draw.connect(func():
		var length := maxf(0.0, _trim.size.x - 26.0)
		_trim.draw_rect(Rect2(13, _trim.size.y - 6, length, 2), EDGE)
		_trim.draw_rect(Rect2(13, _trim.size.y - 6, length * _ratio, 2), _accent)
	)
	_trim.resized.connect(_trim.queue_redraw)


func refresh(state: String, remain: float, duration: float, survivors: int, seekers: int, role: String) -> void:
	visible = state not in ["brief", "done"]
	if not visible:
		return
	var phase_changed := state != _last_phase
	var seconds := ceili(maxf(0.0, remain))
	if phase_changed or seconds != _seconds:
		_clock.text = "%02d:%02d" % [seconds / 60, seconds % 60] if state != "wait" else "—:—"
		_accent = Color("#ff8b7b") if state == "seek" and seconds <= 15 else (SEEKER if state == "seek" else SURVIVOR)
		_clock.add_theme_color_override("font_color", _accent)
		_ratio = clampf(float(seconds) / maxf(1.0, duration), 0.0, 1.0) if state in ["hide", "seek", "reconnect"] else 0.0
		_trim.queue_redraw()
		_seconds = seconds
	if survivors != _hider_count:
		_hider_count = survivors
		_hiders.text = str(maxi(0, survivors))
	if seekers != _seeker_count:
		_seeker_count = seekers
		_seekers.text = str(maxi(0, seekers))
	if _role.text != role:
		_role.text = role
	if phase_changed:
		_last_phase = state
		match state:
			"hide": _phase.text = "ВРЕМЯ СПРЯТАТЬСЯ"
			"seek": _phase.text = "ПОИСК"
			"reconnect": _phase.text = "ВОССТАНАВЛИВАЕМ СВЯЗЬ"
			_: _phase.text = "ПОДГОТОВКА"
		if _intro != null:
			_intro.kill()
		if not bool(GameState.map_options.get("reduced_motion", false)):
			_body.modulate.a = 0.70
			_intro = create_tween()
			_intro.tween_property(_body, "modulate:a", 1.0, 0.24)
		else:
			_body.modulate.a = 1.0


static func _column(row: HBoxContainer, width: float) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.custom_minimum_size.x = width
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.alignment = BoxContainer.ALIGNMENT_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_constant_override("separation", 1)
	row.add_child(result)
	return result


static func _blip(column: VBoxContainer, caption: String, font_size: int, color: Color) -> Label:
	var label := MenuStyle.label(caption, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return label


static func _rule(row: HBoxContainer) -> void:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(1, 46)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.color = EDGE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
