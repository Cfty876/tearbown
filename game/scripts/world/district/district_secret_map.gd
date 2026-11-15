class_name DistrictSecretMap
extends RefCounted

const PHARMACY := Vector2i(-79, 20)
const SHOP := Vector2i(54, 29)
const GARAGE := Vector2i(12, -83)
const DOGHOUSE := Vector2i(72, -79)
const SHAFTS := [PHARMACY, SHOP, GARAGE, DOGHOUSE]
const TILE := 12
const BOTTOM := -2.5
const FLOOR := -2.29
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const PASSAGES := [Rect2i(-83, 17, 8, 7), Rect2i(-76, 19, 132, 3), Rect2i(53, 20, 3, 11),
	Rect2i(11, -84, 3, 105), Rect2i(11, -83, 63, 3), Rect2i(69, -82, 6, 6)]


static func dig(level: DistrictLevel) -> void:
	for shaft: Vector2i in SHAFTS:
		level._fill(shaft.x - 1, shaft.y - 1, shaft.x + 1, shaft.y + 1, 0, 32, "")


static func cut_floor(volume: VoxelVolume, center: Vector2, shaft: Vector2i) -> void:
	var size := volume.get_size()
	var start := Vector2i(roundi((shaft.x - 1 - center.x) * 10.0 + size.x * 0.5),
		roundi((shaft.y - 1 - center.y) * 10.0 + size.z * 0.5))
	volume.fill_box(Vector3i(start.x, 0, start.y), Vector3i(start.x + 20, 2, start.y + 20), 0)


static func build(world: VoxelWorld) -> void:
	var cells := {}
	for area: Rect2i in PASSAGES:
		_rect(cells, area.position.x, area.position.y, area.end.x, area.end.y)
	var tiles := {}
	var concrete := VoxMat.id("concrete_dark")
	var floor_tile := VoxMat.id("concrete")
	var rail := VoxMat.id("plaster_green")
	var lamp := VoxMat.id("lamp")
	for cell: Vector2i in cells:
		var tile := Vector2i(floori(float(cell.x) / TILE), floori(float(cell.y) / TILE))
		if not tiles.has(tile):
			tiles[tile] = Build.vol(Vector3i(TILE * 10, 25, TILE * 10))
		var volume: VoxelVolume = tiles[tile]
		var at := cell - tile * TILE
		var x := at.x * 10
		var z := at.y * 10
		volume.fill_box(Vector3i(x, 0, z), Vector3i(x + 10, 2, z + 10), floor_tile)
		var shaft_cell := false
		for shaft: Vector2i in SHAFTS:
			if Rect2i(shaft - Vector2i.ONE, Vector2i(2, 2)).has_point(cell):
				shaft_cell = true
				break
		if not shaft_cell:
			volume.fill_box(Vector3i(x, 23, z), Vector3i(x + 10, 25, z + 10), concrete)
		for side: Vector2i in DIRECTIONS:
			if cells.has(cell + side):
				continue
			var start := Vector3i(x + (9 if side.x > 0 else 0), 2, z + (9 if side.y > 0 else 0))
			var extent := Vector3i(10 if side.x == 0 else 1, 23, 10 if side.y == 0 else 1)
			volume.fill_box(start, start + extent, concrete)
			start.y = 9
			extent.y = 2
			volume.fill_box(start, start + extent, rail)
		if not shaft_cell and (cell.x == 12 and posmod(cell.y, 6) == 2
				or cell.y in [-82, 20] and posmod(cell.x, 6) == 2):
			volume.fill_box(Vector3i(x + 3, 22, z + 3), Vector3i(x + 7, 23, z + 7), lamp)
			_light(world, Vector3(cell.x + 0.5, -0.5, cell.y + 0.5), Color(0.75, 0.91, 0.79))
	for tile: Vector2i in tiles:
		var object := VoxelObject.new().setup(tiles[tile], true, Vector3i(60, 25, 60))
		object.position = Vector3(tile.x * TILE, BOTTOM, tile.y * TILE)
		object.label = "utility_tunnel"
		world.add_child(object)
	for pos: Vector3 in [Vector3(-80, -0.52, 22), Vector3(54, -0.6, 26), Vector3(72, -0.5, -78)]:
		_light(world, pos, Color(0.94, 0.72, 0.44))


static func _rect(cells: Dictionary, x0: int, z0: int, x1: int, z1: int) -> void:
	for x in range(x0, x1):
		for z in range(z0, z1):
			cells[Vector2i(x, z)] = true


static func _light(world: VoxelWorld, at: Vector3, tint: Color) -> void:
	var fixture := Build.vol(Vector3i(5, 2, 3))
	fixture.fill_box(Vector3i.ZERO, Vector3i(5, 1, 3), VoxMat.id("lamp"))
	fixture.fill_box(Vector3i(0, 1, 0), Vector3i(5, 2, 3), VoxMat.id("metal_dark"))
	var body := Build.place(world, fixture, at + Vector3.UP * 0.14, true, 0, "Светильник коллектора")
	var light := Build.lamp_light(body, Vector3i(2, 0, 1), tint, 0.9, 4.8)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 14.0
	light.distance_fade_length = 8.0
