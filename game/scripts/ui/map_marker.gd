class_name MapMarker
extends RefCounted

const INK := Color("#10191e")
const ICONS := [
	'<path d="M9 9h14v14H9z" fill="none" stroke="white" stroke-width="3"/>',
	'<path d="m16 5 11 11-11 11L5 16z" fill="white"/>',
	'<path d="M7 12h18l-5-5m5 13H7l5 5" fill="none" stroke="white" stroke-width="3"/>',
	'<path d="M7 16h18m-9-9v18" stroke="white" stroke-width="4"/>',
	'<circle cx="16" cy="16" r="6" fill="white"/>',
	'<path d="m16 5 11 20H5z" fill="white"/>',
	'<circle cx="16" cy="16" r="8" fill="none" stroke="white" stroke-width="3"/>',
	'<circle cx="16" cy="16" r="5" fill="white"/><circle cx="16" cy="16" r="10" fill="none" stroke="white" stroke-width="2"/>',
	'<path d="M10 26V7h15l-4 5 4 4H11" fill="none" stroke="white" stroke-width="3"/>',
	'<path d="M6 13h5l7-5v16l-7-5H6z" fill="white"/><path d="M21 12q6 4 0 8m3-11q10 7 0 14" fill="none" stroke="white" stroke-width="1.7"/>',
]
static var _icons: Array[ImageTexture] = []


static func preload_icons() -> void:
	if not _icons.is_empty():
		return
	for glyph in ICONS:
		var image := Image.new()
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="15" fill="#10191e"/>%s</svg>' % glyph)
		_icons.append(ImageTexture.create_from_image(image))


static func paint(canvas: Control, at: Vector2, kind: int, r: float, pulse: float) -> void:
	var tint := MapStyle.tint(kind)
	var extent := Vector2.ONE * (r + 2.5)
	canvas.draw_texture_rect(_icons[kind], Rect2(at - extent, extent * 2.0), false, tint)
	if kind in [MapStyle.PING, MapStyle.HORN] and pulse > 0.0:
		canvas.draw_arc(at, r + 3.0 * pulse, 0, TAU, 18, Color(tint, 1.0 - pulse * 0.45), 1.3, true)


static func arrow(canvas: Control, at: Vector2, forward: Vector2, tint: Color, r: float) -> void:
	var side := forward.orthogonal()
	var points := PackedVector2Array([at + forward * r, at - forward * r * 0.72 + side * r * 0.66,
		at - forward * r * 0.34, at - forward * r * 0.72 - side * r * 0.66])
	canvas.draw_circle(at, r + 2.5, INK, true, -1, true)
	canvas.draw_colored_polygon(points, tint)
