class_name InteractionPrompt
extends TextureRect
## Rasterized at half resolution, so the edges and lettering share a pixel grid.

const HEIGHT := 35
const PIXEL_SCALE := 2

var _viewport: SubViewport
var _card: Card
var _last := ""
var _display_size := Vector2(248, 70)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.size = Vector2i(260, HEIGHT)
	add_child(_viewport)
	texture = _viewport.get_texture()
	_card = Card.new()
	_viewport.add_child(_card)
	hide()


func present(message: String) -> void:
	if _last != message:
		_last = message
		var separator := message.find(" — ")
		_card.key = message.left(separator) if separator > 0 else ""
		_card.caption = message.substr(separator + 3) if separator > 0 else message
		var length := ceili(ThemeDB.fallback_font.get_string_size(_card.caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
		var key_width := _card.key_width()
		var max_width := maxi(120, floori(get_viewport_rect().size.x / PIXEL_SCALE) - 16)
		var width := mini(max_width, maxi(124, length + key_width + 29))
		_viewport.size = Vector2i(width, HEIGHT)
		_card.width = width
		_card.queue_redraw()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_display_size = Vector2(width, HEIGHT) * PIXEL_SCALE
	size = _display_size
	show()


func anchor_to(camera: Camera3D, point: Vector3) -> void:
	if camera.is_position_behind(point):
		hide()
		return
	var pixel := camera.unproject_position(point)
	position = (pixel + Vector2(12.0, -_display_size.y - 5.0)).round()
	if position.x + size.x > get_viewport_rect().size.x - 8.0:
		position.x = roundf(pixel.x - size.x - 12.0)
	visible = get_viewport_rect().intersects(Rect2(position, size))


class Card extends Node2D:
	var key := ""
	var caption := ""
	var width := 260

	func key_width() -> int:
		if key.is_empty():
			return 0
		return maxi(19, ceili(ThemeDB.fallback_font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 10)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var bezel := Color("#435158")
		var copper := Color("#eeb174")
		draw_rect(Rect2(6, 6, width - 9, 28), Color("#090c11bc"))
		draw_rect(Rect2(3, 4, width - 6, 28), bezel)
		draw_rect(Rect2(0, 7, width, 22), bezel)
		draw_rect(Rect2(4, 5, width - 8, 26), Color("#161d25f5"))
		draw_rect(Rect2(1, 8, width - 2, 20), Color("#161d25f5"))
		draw_rect(Rect2(5, 5, 17, 1), copper)
		draw_rect(Rect2(width - 20, 30, 14, 1), Color("#697b7d"))
		var pad := key_width()
		if pad > 0:
			draw_rect(Rect2(7, 11, pad, 15), Color("#97582e"))
			draw_rect(Rect2(7, 9, pad, 14), copper)
			draw_rect(Rect2(8, 10, pad - 2, 2), Color("#ffe1b3"))
			draw_string(font, Vector2(7, 20), key, HORIZONTAL_ALIGNMENT_CENTER, pad, 11, Color("#241912"))
		var text_x := 10 + (pad + 4 if pad else 0)
		draw_string(font, Vector2(text_x, 21), caption, HORIZONTAL_ALIGNMENT_LEFT, width - text_x - 14, 10, Color("#f6ebdc"))
		for i in 3:
			draw_rect(Rect2(width - 11 + (i % 2) * 3, 11 + i * 3, 2, 2), copper.darkened(i * 0.14))
