class_name SchoolBasement
extends RefCounted
## A single floor plan drives both the tunnel shell and all vertical openings.

const ENTRANCE := Rect2(-41.6, 1.0, 9.6, 5.2)
const GARAGE_PIT := Rect2(48.8, 63.5, 3.4, 5.8)
const GARAGE_PIT_BASE := -1.0
const TUNNELS := {
	"wardrobe": [Rect2i(-29, -11, 19, 26)],
	"hall": [Rect2i(-12, -2, 29, 7), Rect2i(14, -10, 4, 11), Rect2i(52, -13, 7, 5)],
	"range": [Rect2i(2, -12, 53, 9)],
	"heat": [Rect2i(48, -54, 5, 44), Rect2i(48, -56, 8, 7)],
	"drain": [Rect2i(-18, -59, 6, 52), Rect2i(-26, -56, 12, 5),
		Rect2i(-24, -10, 11, 3), Rect2i(41, -10, 6, 21)],
	"landing": [Rect2i(-32, 1, 4, 6)],
}

static func build(level: SchoolLevel) -> void:
	var cells := {}
	for style: String in TUNNELS:
		for rect: Rect2i in TUNNELS[style]:
			for x in range(rect.position.x, rect.end.x):
				for z in range(rect.position.y, rect.end.y):
					cells[Vector2i(x, z)] = style
	var shaft_centers := shafts()
	var tiles := {}
	for cell: Vector2i in cells:
		var key := Vector2i(floori(cell.x / 12.0), floori(cell.y / 12.0))
		if not tiles.has(key):
			tiles[key] = Build.vol(Vector3i(120, 40, 120))
		var v: VoxelVolume = tiles[key]
		var q := cell - key * 12
		var at := Vector3i(q.x * 10, 3, q.y * 10)
		var finish: String = cells[cell]
		var floor_mat := "concrete_dark" if finish == "drain" else "concrete"
		SchoolLevel.box(v, at - Vector3i(0, 3, 0), Vector3i(10, 3, 10), "bedrock")
		SchoolLevel.box(v, at, Vector3i(10, 2, 10), floor_mat)
		SchoolLevel.box(v, at + Vector3i(0, 33, 0), Vector3i(10, 3, 10), "concrete_dark")
		SchoolLevel.box(v, at + Vector3i(0, 36, 0), Vector3i(10, 1, 10), "bedrock")

		for edge: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cells.has(cell + edge):
				continue
			if edge == Vector2i.LEFT and cell.x == -32 and cell.y in [2, 3, 4, 5]:
				continue
			var start := at + Vector3i(8 if edge.x > 0 else 0, 2, 8 if edge.y > 0 else 0)
			var size := Vector3i(10 if edge.x == 0 else 2, 31, 10 if edge.y == 0 else 2)
			SchoolLevel.box(v, start, size, "brick" if finish == "heat" else "concrete_dark")
			SchoolLevel.box(v, start + Vector3i(0, 10, 0), Vector3i(size.x, 2, size.z), "plaster_green")
		for edge: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cells.has(cell + edge) or (edge == Vector2i.LEFT and cell.x == -32 and cell.y in [2, 3, 4, 5]):
				continue
			var outer := at + Vector3i(9 if edge.x > 0 else 0, 0, 9 if edge.y > 0 else 0)
			var lining := Vector3i(10 if edge.x == 0 else 1, 37, 10 if edge.y == 0 else 1)
			SchoolLevel.box(v, outer, lining, "bedrock")
		if finish in ["heat", "drain"]:
			var conduit_x := 8 if finish == "heat" else 1
			SchoolLevel.box(v, at + Vector3i(conduit_x, 31, 0), Vector3i(1, 2, 10), "metal_teal")
			if posmod(cell.y, 4) == 0:
				SchoolLevel.box(v, at + Vector3i(conduit_x, 29, 4), Vector3i(1, 4, 2), "metal_dark")
		var clear_lamp := true
		var slice := Rect2i(cell * 10, Vector2i(10, 10))
		for shaft: Vector2 in shaft_centers:
			var cut := shaft_footprint(shaft).intersection(slice)
			if cut.has_area():
				clear_lamp = false
				var offset := cut.position - slice.position
				if shaft == SchoolLevel.LIFT:
					var cabin := Rect2i(shaft_footprint(shaft).position + Vector2i(3, 3), Vector2i(18, 18)).intersection(slice)
					if cabin.has_area():
						var pit := cabin.position - slice.position
						SchoolLevel.box(v, at + Vector3i(pit.x, 0, pit.y), Vector3i(cabin.size.x, 2, cabin.size.y), "")
				SchoolLevel.box(v, at + Vector3i(offset.x, 2, offset.y),
					Vector3i(cut.size.x, 35, cut.size.y), "")
		if clear_lamp and ((cell.y == -7 and posmod(cell.x, 7) == 3) or (cell.x in [-15, 50] and posmod(cell.y, 8) == 2)):
			SchoolLevel.box(v, at + Vector3i(2, 31, 2), Vector3i(6, 2, 4), "lamp")
			level.fixture(v, at + Vector3i(4, 31, 4), Vector3(cell.x + 0.5, SchoolLevel.BASEMENT + 2.8, cell.y + 0.5), Color("#c1d6bf"), 0.94, 6.5)
	for key: Vector2i in tiles:
		var shell := level.place(tiles[key], Vector3(key.x * 12, SchoolLevel.BASEMENT - 0.3, key.y * 12),
			"Подземные переходы", Vector3i(60, 40, 60))
		shell.set_meta("layout_locked", true)
		level.basements[key] = shell
	for shaft: Vector2 in shaft_centers:
		_line_shaft(level, shaft)
	_service_stairs(level)
	SchoolYard.underground_props(level)
	_guard_post(level)


static func _guard_post(level: SchoolLevel) -> void:
	var floor_y := SchoolLevel.BASEMENT + 0.20
	var bench := Build.vol(Vector3i(19, 10, 7))
	for x in [1, 16]:
		SchoolLevel.box(bench, Vector3i(x, 0, 1), Vector3i(2, 5, 6), "metal_teal")
	SchoolLevel.box(bench, Vector3i(0, 4, 0), Vector3i(19, 1, 7), "wood_light")
	SchoolLevel.box(bench, Vector3i(0, 7, 6), Vector3i(19, 2, 1), "wood_dark")
	for x in [1, 16]:
		SchoolLevel.box(bench, Vector3i(x, 5, 6), Vector3i(2, 2, 1), "metal_teal")
	level.place(bench, Vector3(-9.1, floor_y, 3.94), "Скамья подземного поста")
	var panel := Build.vol(Vector3i(13, 14, 4))
	SchoolLevel.box(panel, Vector3i.ZERO, panel.get_size(), "metal_green")
	SchoolLevel.box(panel, Vector3i(1, 2, 3), Vector3i(11, 10, 1), "metal_dark")
	SchoolLevel.box(panel, Vector3i(8, 10, 3), Vector3i(3, 2, 1), "lamp")
	var at := Vector3(-11.15, floor_y + 0.87, -1.8)
	level.fixture(panel, Vector3i(9, 10, 3), at + Vector3(0.95, 1.05, 0.42), Color("#b7c7b2"), 0.78, 4.7)
	level.place(panel, at, "Щиток подземного поста")


static func shafts() -> Array[Vector2]:
	return [SchoolLevel.LOBBY_HATCH, SchoolLevel.LIFT, SchoolLevel.BOILER_HATCH,
		Vector2(SchoolLevel.HOOP.x, SchoolLevel.HOOP.z), SchoolTrapProps.POOL_DRAIN, SchoolTrapProps.FIELD_HATCH]


static func shaft_footprint(shaft: Vector2) -> Rect2i:
	var start := Vector2i((shaft * 10.0).round()) - Vector2i(12, 12)
	return Rect2i(start, Vector2i(24, 24))


static func shaft_top(shaft: Vector2) -> float:
	return 1.1 if shaft == SchoolTrapProps.POOL_DRAIN else 1.4


static func _line_shaft(level: SchoolLevel, shaft: Vector2) -> void:
	var bottom := SchoolLevel.BASEMENT + 0.2
	var footprint := shaft_footprint(shaft)
	var width := footprint.size.x
	var h := roundi((shaft_top(shaft) - bottom) * 10)
	var v := Build.vol(Vector3i(width, h, 24))
	for x in [0, width - 2]:
		SchoolLevel.box(v, Vector3i(x, 0, 0), Vector3i(2, h, 24), "concrete")
	var exit := 0 if shaft == SchoolTrapProps.POOL_DRAIN else 22
	for z in [0, 22]:
		SchoolLevel.box(v, Vector3i(2, 0, z), Vector3i(width - 4, h, 2), "concrete")
	for x in [0, width - 1]:
		SchoolLevel.box(v, Vector3i(x, 0, 0), Vector3i(1, h, 24), "bedrock")
	for z in [0, 23]:
		SchoolLevel.box(v, Vector3i(1, 0, z), Vector3i(width - 2, h, 1), "bedrock")
	SchoolLevel.box(v, Vector3i(4, 0, exit), Vector3i(width - 8, 22, 2), "")
	for y in [22, 34, 46]:
		SchoolLevel.box(v, Vector3i(1, y, 4), Vector3i(1, 2, 16), "metal_yellow")
	if shaft != SchoolLevel.LIFT and shaft != Vector2(SchoolLevel.HOOP.x, SchoolLevel.HOOP.z):
		SchoolLevel.box(v, Vector3i(width - 3, 19, 4), Vector3i(1, 2, 4), "lamp")
		level.fixture(v, Vector3i(width - 3, 19, 5), Vector3(shaft.x + 0.78, -1.81, shaft.y - 0.64), Color("#edbb82"), 0.7, 4.6)
	level.place(v, Vector3(footprint.position.x * 0.1, bottom, footprint.position.y * 0.1), "Облицовка шахты").set_meta("layout_locked", true)


static func _service_stairs(level: SchoolLevel) -> void:
	var v := Build.vol(Vector3i(96, 85, 52))
	for i in 30:
		var start_x := i * 3
		var height := 60 - i * 2
		SchoolLevel.box(v, Vector3i(start_x, 0, 0), Vector3i(3, height, 52), "concrete")
		SchoolLevel.box(v, Vector3i(start_x, 0, 0), Vector3i(3, maxi(1, height - 2), 52), "bedrock")
		SchoolLevel.box(v, Vector3i(start_x, height - 1, 8), Vector3i(1, 1, 36), "stone")
		for z in [4, 45]:
			if i % 3 == 0:
				SchoolLevel.box(v, Vector3i(start_x, height, z), Vector3i(1, 9, 1), "metal_teal")
			SchoolLevel.box(v, Vector3i(start_x, height + 8, z), Vector3i(3, 2, 1), "metal_dark")
	for z in [0, 48]:
		SchoolLevel.box(v, Vector3i(0, 2, z), Vector3i(86, 61, 4), "concrete_dark")
		SchoolLevel.box(v, Vector3i(0, 62, z), Vector3i(86, 5, 4), "brick_tan")
	SchoolLevel.box(v, Vector3i(86, 0, 0), Vector3i(10, 2, 52), "concrete")
	for z in [0, 48]:
		SchoolLevel.box(v, Vector3i(86, 2, z), Vector3i(10, 61, 4), "concrete_dark")
	SchoolLevel.box(v, Vector3i(86, 32, 4), Vector3i(10, 3, 44), "concrete_dark")
	SchoolLevel.box(v, Vector3i(86, 32, 4), Vector3i(4, 30, 44), "concrete_dark")
	for x in [18, 52, 81]:
		for z in [2, 48]:
			SchoolLevel.box(v, Vector3i(x, 60, z), Vector3i(3, 23, 2), "metal_teal")
	SchoolLevel.box(v, Vector3i(12, 82, 0), Vector3i(75, 3, 52), "roof_bitumen")
	SchoolLevel.box(v, Vector3i(12, 80, 0), Vector3i(75, 2, 3), "metal_teal")
	var base := Vector3(ENTRANCE.position.x, SchoolLevel.BASEMENT, ENTRANCE.position.y)
	for i in 3:
		var cell := Vector3i(16 + i * 37, 64 - i * 16, 4)
		level.fixture(v, cell, base + Vector3(cell) * 0.1 + Vector3(0, -0.06, 0.18), Color("#ffe0a9"), 1.0, 6.6)
	level.place(v, base, "Крытая лестница в убежище").set_meta("layout_locked", true)
