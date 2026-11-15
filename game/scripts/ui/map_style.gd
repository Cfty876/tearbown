class_name MapStyle
extends Resource

enum { POINT, SECRET, PORTAL, LOOT, NPC, THREAT, ALLY, PING, OBJECTIVE, HORN }
const NAMES := ["Ориентиры", "Тайники", "Переходы", "Гаджеты", "NPC", "Угрозы", "Союзники", "Пинги", "Цели", "Гудок"]
const GLYPHS := ["□", "◆", "↔", "+", "●", "△", "○", "✦", "⚑", "♪"]
const PRIORITY := [HORN, PING, OBJECTIVE, THREAT, ALLY, SECRET, PORTAL, LOOT, POINT, NPC]
const PALETTES := [
	[Color("#10191e"), Color("#334951"), Color("#e6bc78"), Color("#f0e8d8")],
	[Color("#111e2d"), Color("#3c5774"), Color("#92cfff"), Color("#e8f3ff")],
	[Color("#161616"), Color("#707070"), Color("#ffe088"), Color("#ffffff")],
]
const COLORS := ["#e6bc78", "#d8a2ff", "#73dfca", "#f3cc82", "#a9bac1", "#ff9479", "#86c4ff", "#fff1a6", "#ffd986", "#ffd294"]
const ACCESSIBLE := ["#f4d284", "#e9b9ff", "#72e4ff", "#ffd87b", "#edf2f5", "#ffbf82", "#9fc8ff", "#ffffff", "#ffe080", "#ffdb9c"]
const DEFAULTS := {"visible": true, "size": 222.0, "opacity": 0.94, "rotate": false, "zoom": 1,
	"style": 0, "accessible": false, "reduced_motion": false, "fog": true, "markers": 1023}

@export var redraw_hz := 20.0
@export var sample_hz := 10.0
@export var mini_limit := 15
@export var large_limit := 52
@export var zoom_metres := Vector3(44.0, 70.0, 106.0)


static func settings(saved: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	result.merge(saved, true)
	result["size"] = clampf(float(result["size"]), 160.0, 290.0)
	result.opacity = clampf(float(result.opacity), 0.45, 1.0)
	result.zoom = clampi(int(result.zoom), 0, 2)
	result.style = clampi(int(result.style), 0, 2)
	result.markers = (int(result.markers) & 511) | (1 << HORN)
	return result


static func tint(kind: int) -> Color:
	return Color((ACCESSIBLE if GameState.map_options.accessible else COLORS)[kind])


static func palette() -> Array:
	return PALETTES[GameState.map_options.style]
