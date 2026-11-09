class_name TouchControls
extends Control

const WALK_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]
const TAP_ACTIONS := ["grab", "jump", "fire"]
const BUTTONS := [
	["PAUSE", Vector2(0.947, 0.11), "ПАУЗА", 0.055],
	["TOOLS", Vector2(0.845, 0.11), "ВЕЩИ", 0.055],
	["grab", Vector2(0.935, 0.47), "ВЗЯТЬ", 0.067],
	["fire", Vector2(0.926, 0.73), "ОГОНЬ", 0.085],
	["jump", Vector2(0.801, 0.83), "ПРЫЖОК", 0.068],
	["crouch", Vector2(0.704, 0.88), "СЕСТЬ", 0.059],
	["sprint", Vector2(0.065, 0.51), "БЕГ", 0.058],
]
const UI_COLOR := Color("#eee4cc")
const UI_DARK := Color("#11181da6")
const UI_EDGE := Color("#e7c28885")
var player: Player
var inventory: ToolInventory
var pause: PauseMenu
var _touches := {}
var _look := -1
var _move := -1
var _move_origin := Vector2.ZERO
var _move_delta := Vector2.ZERO
var _crouch := false


static func available() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("matchMedia('(any-pointer: coarse)').matches || navigator.maxTouchPoints > 0"))
	return OS.has_feature("mobile")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _exit_tree() -> void:
	_release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		_release_all()


func _input(e: InputEvent) -> void:
	if not is_instance_valid(player) or player.dead or inventory.is_open or pause.is_open():
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_touch_start(e.index, _local(e.position))
		else:
			_touch_end(e.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if e.index == _move:
			_set_walk(_local(e.position) - _move_origin)
		elif e.index == _look:
			player.apply_look(e.screen_relative * 1.75)
		get_viewport().set_input_as_handled()


func _local(at: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * at


func _radius(fraction: float) -> float:
	return clampf(size.y, 560.0, 1250.0) * fraction


func _touch_start(index: int, at: Vector2) -> void:
	for data in BUTTONS:
		var action: String = data[0]
		if not _button_available(action):
			continue
		var center: Vector2 = data[1] * size
		if at.distance_to(center) <= _radius(data[3]) + 10.0:
			match action:
				"PAUSE":
					_release_all()
					pause.toggle()
					hide()
				"TOOLS":
					_release_all()
					inventory.open_touch()
				"crouch":
					_crouch = not _crouch
					if _crouch:
						Input.action_press(action)
					else:
						Input.action_release(action)
				_:
					_touches[index] = action
					Input.action_press(action)
					if action == "grab":
						player.interact()
			queue_redraw()
			return
	if player.grabbed:
		for side in [-1, 1]:
			if at.distance_to(_grab_point(side)) < _radius(0.047) + 10.0:
				player.grab_scroll(side * 0.28)
				return
	if at.x < size.x * 0.46 and at.y > size.y * 0.36 and _move < 0:
		_move = index
		_move_origin = at
		_set_walk(Vector2.ZERO)
	elif _look < 0:
		_look = index


func _touch_end(index: int) -> void:
	if index == _move:
		_move = -1
		_set_walk(Vector2.ZERO)
	if index == _look:
		_look = -1
	if _touches.has(index):
		var action: String = _touches[index]
		_touches.erase(index)
		if action not in _touches.values():
			Input.action_release(action)
	queue_redraw()


func _set_walk(delta: Vector2) -> void:
	_move_delta = delta.limit_length(_radius(0.13))
	var value := _move_delta / _radius(0.13)
	var axes := [-value.x, value.x, -value.y, value.y]
	for i in WALK_ACTIONS.size():
		if axes[i] > 0.08:
			Input.action_press(WALK_ACTIONS[i], axes[i])
		else:
			Input.action_release(WALK_ACTIONS[i])
	queue_redraw()


func _release_all() -> void:
	for action in WALK_ACTIONS:
		Input.action_release(action)
	for action in TAP_ACTIONS + ["crouch", "sprint"]:
		Input.action_release(action)
	_touches.clear()
	_move = -1
	_look = -1
	_move_delta = Vector2.ZERO
	_crouch = false
	queue_redraw()


func _grab_point(side: int) -> Vector2:
	return Vector2(0.66 + side * 0.052, 0.62) * size


func _button_available(action: String) -> bool:
	if action == "TOOLS":
		return not player.vehicle and not player.grabbed
	if action == "grab":
		return player.interaction_enabled
	return true


func _process(_delta: float) -> void:
	var show_controls := not inventory.is_open and not player.dead and not pause.is_open()
	if visible != show_controls:
		visible = show_controls
	if player.grabbed:
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player):
		return
	var origin := _move_origin if _move >= 0 else Vector2(0.14, 0.77) * size
	draw_circle(origin, _radius(0.13), UI_DARK, true, -1, true)
	draw_arc(origin, _radius(0.13), 0, TAU, 32, UI_EDGE, 3.0, true)
	draw_circle(origin + _move_delta, _radius(0.052), UI_EDGE, true, -1, true)
	for data in BUTTONS:
		var action: String = data[0]
		if not _button_available(action):
			continue
		var label: String = data[2]
		if action == "grab" and player.vehicle:
			label = "ВЫХОД"
		if action == "jump" and player.vehicle:
			label = "ТОРМ"
		var active := action in _touches.values() or (action == "crouch" and _crouch)
		_button(data[1] * size, _radius(data[3]), label, active)
	if player.grabbed:
		_button(_grab_point(-1), _radius(0.047), "−", false)
		_button(_grab_point(1), _radius(0.047), "+", false)


func _button(center: Vector2, radius: float, label: String, active: bool) -> void:
	draw_circle(center, radius, UI_EDGE if active else UI_DARK, true, -1, true)
	draw_arc(center, radius, 0, TAU, 24, UI_EDGE, 3.0, true)
	var font := ThemeDB.fallback_font
	var fs := roundi(radius * (0.52 if label.length() > 3 else 0.65))
	draw_string(font, center - Vector2(radius, -font.get_ascent(fs) * 0.42), label,
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, UI_COLOR)
