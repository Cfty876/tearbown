class_name MenuStyle
extends RefCounted

const GOLD := Color("#ffd08b")
const TEXT := Color("#fff2e2")
const MUTED := Color("#b8b1aa")
const PANEL := Color("#12181f")
const STROKE := Color("#42454b")


static func label(value: String, size: int, tint := TEXT) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", tint)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func panel(fill: Color, border := STROKE, radius := 14) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	result.content_margin_left = 22
	result.content_margin_right = 22
	result.content_margin_top = 14
	result.content_margin_bottom = 14
	return result


static func button(title: String, callback: Callable, primary := false, height := 64) -> Button:
	var result := Button.new()
	result.text = title
	result.custom_minimum_size.y = height
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_size_override("font_size", 25)
	result.add_theme_stylebox_override("normal", panel(Color("#e6b16f") if primary else Color("#222b35")))
	result.add_theme_stylebox_override("hover", panel(Color("#ffd399") if primary else Color("#354151"), GOLD))
	result.add_theme_stylebox_override("pressed", panel(Color("#c89458") if primary else Color("#414955"), GOLD))
	var focus := panel(Color.TRANSPARENT, GOLD)
	focus.set_border_width_all(2)
	result.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		result.add_theme_color_override(state, Color("#1c1918") if primary else TEXT)
	result.pressed.connect(callback)
	return result


static func image(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return load("res://ui/menu_bg.png") as Texture2D


static func cover(texture: Texture2D) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
