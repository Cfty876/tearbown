class_name HornLocator
extends Control

const DURATION := 3.0
const AMBER := Color("#ffd08b")

var _source := Vector3.ZERO
var _remaining := 0.0
var _point := Vector2.ZERO
var _direction := Vector2.ZERO
var _offscreen := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func mark(at: Vector3) -> void:
	_source = at
	_remaining = DURATION
	set_process(true)
	_process(0.0)


func clear() -> void:
	_remaining = 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_remaining -= delta
	var camera := get_viewport().get_camera_3d()
	if _remaining <= 0.0 or camera == null:
		clear()
		return
	var screen := get_viewport_rect().size
	var margin := Vector2(38.0, 38.0)
	var visible_area := Rect2(margin, screen - margin * 2.0)
	var projected := camera.unproject_position(_source)
	var behind := camera.is_position_behind(_source)
	_offscreen = behind or not visible_area.has_point(projected)
	if _offscreen:
		var view := camera.to_local(_source)
		var side := Vector2(view.x, -view.y) if behind else projected - screen * 0.5
		if side.length_squared() < 0.00001:
			side = Vector2.DOWN
		_direction = side.normalized()
		var half := screen * 0.5 - margin
		var reach := minf(half.x / maxf(absf(_direction.x), 0.001), half.y / maxf(absf(_direction.y), 0.001))
		_point = screen * 0.5 + _direction * reach
	else:
		_point = projected
	queue_redraw()


func _draw() -> void:
	if _remaining <= 0.0:
		return
	var fade := smoothstep(0.0, 0.65, _remaining)
	var tint := Color(AMBER, fade)
	var dark := Color(0.05, 0.06, 0.07, 0.85 * fade)
	draw_circle(_point, 15.0, dark, true, -1.0, true)
	draw_arc(_point, 15.0, 0.0, TAU, 36, tint, 1.5, true)
	var wave := fposmod((DURATION - _remaining) * 1.6, 1.0)
	draw_arc(_point, 17.0 + wave * 11.0, 0.0, TAU, 40, Color(AMBER, (1.0 - wave) * 0.55 * fade), 1.5, true)
	draw_colored_polygon(PackedVector2Array([_point + Vector2(-7, -2), _point + Vector2(-3, -2),
		_point + Vector2(5, -6), _point + Vector2(5, 6), _point + Vector2(-3, 2), _point + Vector2(-7, 2)]), tint)
	draw_arc(_point + Vector2(4, 0), 5.5, -0.77, 0.77, 10, tint, 1.4, true)
	if _offscreen:
		var tip := _point + _direction * 24.0
		var side := _direction.orthogonal() * 4.0
		draw_colored_polygon(PackedVector2Array([tip, tip - _direction * 6.0 + side, tip - _direction * 6.0 - side]), tint)
