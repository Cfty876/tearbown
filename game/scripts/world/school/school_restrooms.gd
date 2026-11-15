class_name SchoolRestrooms
extends RefCounted

const NAMES := ["МУЖ", "ЖЕН"]
const TRIM := ["plaster_green", "plaster_yellow"]
const STALL := Vector2i(26, 23)


static func build(v: VoxelVolume, area: Rect2i, partition: int) -> Array[Dictionary]:
	var booths: Array[Dictionary] = []
	var half := area.position.y + area.size.y / 2
	SchoolLevel.box(v, Vector3i(area.position.x, 2, half), Vector3i(area.size.x, 35, 2), "plaster_blue")
	for group in 2:
		var low := area.position.y if group == 0 else half + 2
		var high := half if group == 0 else area.end.y
		var door := low + 12
		var grid := SchoolGrid.new(Rect2i(area.position.x, low, area.size.x, high - low))
		grid.protect("Проход", Rect2i(area.position.x, low, area.size.x - STALL.x - 3, high - low))
		SchoolLevel.box(v, Vector3i(area.position.x, 1, low), Vector3i(area.size.x, 1, high - low), "concrete")
		for z in range(low, high, 4):
			for x in range(area.position.x, area.end.x, 4):
				var aged := "pvc" if (x * 3 + z * 5) % 7 > 1 else "plaster_yellow"
				SchoolLevel.box(v, Vector3i(x, 1, z), Vector3i(3, 1, mini(3, high - z)), aged)
		SchoolLevel.box(v, Vector3i(area.end.x - 1, 2, low), Vector3i(1, 10, high - low), "pvc")
		SchoolLevel.box(v, Vector3i(area.end.x - 1, 12, low), Vector3i(1, 2, high - low), TRIM[group])
		Build.door(v, 0, partition, 3, door, 2, 19, 25, "wood_dark")
		for jamb in [door, door + 18]:
			SchoolLevel.box(v, Vector3i(partition, 2, jamb), Vector3i(3, 25, 1), "wood_dark")
		SchoolLevel.box(v, Vector3i(partition - 1, 28, door - 2), Vector3i(1, 8, 25), TRIM[group])
		VoxelFont.draw(v, NAMES[group], Vector3i(partition - 1, 34, door + 1), Vector3i(0, 0, 1), VoxMat.id("metal_white"))
		var sink := Vector3i(area.end.x - 9, 2, low + 29)
		var sink_reserved := grid.reserve(sink, 8, 6)
		assert(sink_reserved, "Restroom basin overlaps aisle or stalls")
		_basin(v, sink)
		for stall_index in 2:
			var z := low + 3 + stall_index * 33
			var base := Vector3i(area.end.x - STALL.x - 1, 2, z)
			var reserved := grid.reserve(base, STALL.x, STALL.y)
			assert(reserved, "Restroom stall overlaps aisle or fixtures")
			_stall(v, base, TRIM[group])
			booths.append({"group": group, "transit": stall_index == 0, "hinge": Vector3(base) + Vector3(0, 0.35, 1.25),
				"entry": Vector3(partition + 1.5, 2.35, door + 1.3),
				"landing": Vector3(base) + Vector3(9, 0.08, 11.5),
				"button": Vector3(base) + Vector3(24.3, 11, 5.0),
				"plan": {"area": grid.bounds, "placements": grid.placements, "hides": []}})
	return booths


static func _stall(v: VoxelVolume, at: Vector3i, trim: String) -> void:
	for z in [0, STALL.y - 1]:
		SchoolLevel.box(v, at + Vector3i(0, 0, z), Vector3i(STALL.x, 24, 1), trim)
	SchoolLevel.box(v, at + Vector3i(STALL.x - 1, 0, 0), Vector3i(1, 24, STALL.y), trim)
	SchoolLevel.box(v, at + Vector3i(0, 22, 0), Vector3i(1, 2, STALL.y), "wood_dark")
	var bowl := at + Vector3i(20, 0, 12)
	SchoolLevel.box(v, bowl + Vector3i(-2, 0, -2), Vector3i(5, 4, 5), "pvc")
	SchoolLevel.box(v, bowl + Vector3i(-4, 4, -3), Vector3i(8, 2, 7), "pvc")
	SchoolLevel.box(v, bowl + Vector3i(-3, 5, -2), Vector3i(5, 1, 5), "metal_blue")
	SchoolLevel.box(v, bowl + Vector3i(2, 6, -3), Vector3i(2, 10, 1), "metal")
	SchoolLevel.box(v, bowl + Vector3i(2, 16, -3), Vector3i(3, 5, 7), "pvc")
	SchoolLevel.box(v, bowl + Vector3i(1, 17, 0), Vector3i(1, 2, 1), "metal")


static func _basin(v: VoxelVolume, at: Vector3i) -> void:
	SchoolLevel.box(v, at + Vector3i(4, 0, 2), Vector3i(3, 8, 2), "pvc")
	SchoolLevel.box(v, at + Vector3i(0, 7, 0), Vector3i(8, 3, 6), "pvc")
	SchoolLevel.box(v, at + Vector3i(1, 9, 1), Vector3i(5, 1, 4), "plaster_blue")
	SchoolLevel.box(v, at + Vector3i(6, 10, 2), Vector3i(1, 4, 1), "metal")
	SchoolLevel.box(v, at + Vector3i(4, 13, 2), Vector3i(3, 1, 1), "metal")
	SchoolLevel.box(v, at + Vector3i(7, 16, 0), Vector3i(1, 10, 6), "wood_dark")
	SchoolLevel.box(v, at + Vector3i(6, 17, 1), Vector3i(1, 8, 4), "metal")
	SchoolLevel.box(v, at + Vector3i(6, 17, 1), Vector3i(1, 2, 2), "plaster_yellow")


static func _leaf(width: int, height: int, entry: bool) -> VoxelVolume:
	var leaf := Build.vol(Vector3i(width, height, 3))
	var finish := "wood" if entry else "plaster_green"
	SchoolLevel.box(leaf, Vector3i(0, 0, 1), Vector3i(width, height, 1), finish)
	for x in [0, width - 1]:
		SchoolLevel.box(leaf, Vector3i(x, 0, 1), Vector3i(1, height, 1), "wood_dark")
	for z in [0, 2]:
		for y in [2, height - 4]:
			SchoolLevel.box(leaf, Vector3i(2, y, z), Vector3i(width - 4, 2, 1), "wood_dark")
		SchoolLevel.box(leaf, Vector3i(width - 5, 9, z), Vector3i(3, 2, 1), "metal")
		for y in [4, height - 5]:
			SchoolLevel.box(leaf, Vector3i(0, y, z), Vector3i(2, 1, 1), "metal_dark")
	return leaf


static func install(level: SchoolLevel, booths: Array[Dictionary], origin: Vector3, side: int, floor: int) -> void:
	for booth in booths:
		var hinge := origin + Vector3(booth.hinge) * 0.1
		var door := DistrictDoor.install_leaf(level.world, hinge, -PI * 0.5, _leaf(20, 19, false))
		door.body.label = "Дверца кабинки"
		level.restroom_doors.append(door)
		if not booth.transit:
			continue
		var entry := DistrictDoor.install_leaf(level.world, origin + Vector3(booth.entry) * 0.1,
			-PI * 0.5, _leaf(16, 24, true), PI * 0.5)
		entry.body.label = "Дверь санузла"
		level.restroom_doors.append(entry)
		var key := "wc/%d/%d/%d" % [floor, side, booth.group]
		level.restroom_links[key] = {"landing": origin + Vector3(booth.landing) * 0.1,
			"button": origin + Vector3(booth.button) * 0.1,
			"pair": "wc/%d/%d/%d" % [floor, 1 - side, booth.group]}
