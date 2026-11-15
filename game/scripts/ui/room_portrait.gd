class_name RoomPortrait
extends Control

const TINTS := [Color("#55b8b4"), Color("#e6a15d"), Color("#8e97dc"), Color("#ad8a68"),
	Color("#7bb085"), Color("#ce8097"), Color("#79a3bd"), Color("#dab96c"), Color("#937da8")]

var side := 0


func _ready() -> void:
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var frame := minf(size.x, size.y)
	var unit := frame / 16.0
	var origin := (size - Vector2.ONE * frame) / 2.0
	var color: Color = TINTS[posmod(side, TINTS.size())]
	draw_style_box(MenuStyle.panel(color.darkened(0.70), color.darkened(0.30), 9), Rect2(origin, Vector2.ONE * frame))
	_pixel(origin, unit, Rect2(3, 11, 10, 4), color.darkened(0.28))
	_pixel(origin, unit, Rect2(6, 11, 4, 3), color.lightened(0.28))
	var skin: Color = [Color("#e8bb8b"), Color("#aa725b"), Color("#c99366")][posmod(side, 3)]
	_pixel(origin, unit, Rect2(5, 4, 6, 7), skin)
	_pixel(origin, unit, Rect2(9, 5, 2, 6), skin.darkened(0.16))
	var hair := color.darkened(0.72)
	_pixel(origin, unit, Rect2(5, 3, 6, 2), hair)
	_pixel(origin, unit, Rect2(4, 5, 1, 3), hair)
	_pixel(origin, unit, Rect2(5, 5, 2 + side % 2, 1), hair)
	_pixel(origin, unit, Rect2(6, 7, 1, 1), Color("#1e2229"))
	_pixel(origin, unit, Rect2(9, 7, 1, 1), Color("#1e2229"))
	if side == RoomRules.BOT_SIDE:
		_pixel(origin, unit, Rect2(5, 6, 6, 2), Color("#a6e6d8"))
	else:
		_pixel(origin, unit, Rect2(7, 9, 2, 1), skin.darkened(0.35))


func _pixel(origin: Vector2, unit: float, rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(origin + rect.position * unit, rect.size * unit), color)
