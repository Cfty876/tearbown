class_name DistrictInteriors
## Top-down furniture plans in 10 cm cells. Furniture is baked into the building volume.

const WALL := 0
const FLOOR := 1
const PASSAGE := 2
const FURNITURE := 3
const CLEARANCE := 3 # The player capsule fits in a centered 7 x 7 patch.
const FABRICS := ["curtain_red", "curtain_green", "curtain_beige"]
const FIXTURE_SIZE := {
	"wardrobe": Vector3i(13, 23, 13), "desk": Vector3i(8, 9, 9), "table": Vector3i(9, 9, 21),
	"bed": Vector3i(13, 9, 22), "nightstand": Vector3i(5, 9, 5), "dresser": Vector3i(8, 9, 8),
	"couch": Vector3i(16, 10, 9), "coffee": Vector3i(11, 6, 5), "tv": Vector3i(15, 14, 5),
	"bookcase": Vector3i(5, 19, 10), "kitchen": Vector3i(8, 19, 15), "fridge": Vector3i(8, 18, 7),
	"bath": Vector3i(9, 23, 17), "sink": Vector3i(6, 11, 6), "toilet": Vector3i(5, 8, 7),
	"radiator": Vector3i(10, 5, 3),
}
static var _plans := {}
static var _house_plans: Array[Layout] = []


class Layout:
	var size: Vector2i
	var cells := PackedByteArray()
	var furniture: Array[Dictionary] = []
	var access: Array[Vector2i] = []

	func _init(extent: Vector2i, room: Rect2i) -> void:
		size = extent
		cells.resize(size.x * size.y)
		_stamp(room, FLOOR)

	func _stamp(rect: Rect2i, value: int) -> void:
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells[x + z * size.x] = value

	func reserve(rect: Rect2i) -> void:
		if not _fits(rect, true):
			push_error("Interior passage is outside the free floor: %s" % rect)
			return
		_stamp(rect, PASSAGE)

	func block(rect: Rect2i) -> void:
		_stamp(rect, WALL)

	func place(kind: String, at: Vector2i, required := true) -> void:
		var extent: Vector3i = FIXTURE_SIZE[kind]
		var rect := Rect2i(at, Vector2i(extent.x, extent.z))
		if not _fits(rect):
			if required:
				push_error("Interior slot overlaps a wall, passage or prop: %s at %s" % [kind, at])
			return
		_stamp(rect, FURNITURE)
		furniture.append({"kind": kind, "at": at})

	func _fits(rect: Rect2i, allow_passage := false) -> bool:
		if not Rect2i(Vector2i.ZERO, size).encloses(rect):
			return false
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := cells[x + z * size.x]
				if cell != FLOOR and not (allow_passage and cell == PASSAGE):
					return false
		return true

	func has_route() -> bool:
		var visited := PackedByteArray()
		visited.resize(cells.size())
		var queue: Array[Vector2i] = [access[0]]
		var index := 0
		while index < queue.size():
			var point := queue[index]
			index += 1
			if not Rect2i(Vector2i.ZERO, size).has_point(point):
				continue
			var id := point.x + point.y * size.x
			if visited[id] != 0:
				continue
			var space := Rect2i(point - Vector2i.ONE * CLEARANCE, Vector2i.ONE * (2 * CLEARANCE + 1))
			visited[id] = 1 if _fits(space, true) else 2
			if visited[id] == 1:
				queue.append(point + Vector2i.LEFT)
				queue.append(point + Vector2i.RIGHT)
				queue.append(point + Vector2i.UP)
				queue.append(point + Vector2i.DOWN)
		for point in access:
			if visited[point.x + point.y * size.x] != 1:
				return false
		return true


static func apartments(v: VoxelVolume, start_x: int, y: int, front: int, rear: int,
		seed: int, balcony: bool, hides: Array[Dictionary], secret := false) -> void:
	for bay: int in [0, 1, 3, 4]:
		var front_plan := apartment_plan(bay, false, false)
		var rear_plan := apartment_plan(bay, true, balcony and bay in [1, 3])
		var x := start_x + bay * front_plan.size.x
		_bake(v, front_plan, Vector3i(x, y, front), seed, hides)
		if secret and bay == 4:
			_box(v, Vector3i(x + 3, y, rear + 37), Vector3i(4, 18, 10), "wood_dark")
			for shelf in [4, 9, 14]:
				_box(v, Vector3i(x + 7, y + shelf, rear + 38), Vector3i(2, 2, 8), "wood_light")
			_box(v, Vector3i(x + 20, y, rear + 42), Vector3i(6, 6, 7), "wood_dark")
			_box(v, Vector3i(x + 20, y + 6, rear + 42), Vector3i(5, 5, 5), "wood")
		else:
			_bake(v, rear_plan, Vector3i(x, y, rear), seed + 1, hides)
		if bay == 0:
			# The rug shares the floor surface, so its edge cannot catch the capsule.
			_box(v, Vector3i(x + 5, y - 1, front + 27), Vector3i(12, 1, 8), FABRICS[seed % 3])


static func apartment_plan(bay: int, rear: bool, balcony: bool) -> Layout:
	var key := Vector3i(bay, int(rear), int(balcony))
	if _plans.has(key):
		return _plans[key]
	var depth := 52 if rear else 59
	var plan := Layout.new(Vector2i(30, depth), Rect2i(3, 0, 24, depth))
	if rear:
		plan.reserve(Rect2i(11, 0, 9, depth if balcony else 27))
		plan.reserve(Rect2i(3, 17, 24, 10))
		plan.access.assign([Vector2i(14, 4), Vector2i(6, 21), Vector2i(23, 21)])
		if balcony:
			plan.access.append(Vector2i(14, 47))
		match bay:
			0:
				plan.reserve(Rect2i(16, 24, 9, 17))
				plan.access.append(Vector2i(20, 34))
				plan.place("bed", Vector2i(3, 28))
				plan.place("dresser", Vector2i(19, 43))
			1:
				plan.reserve(Rect2i(11, 23, 9, 18))
				plan.access.append(Vector2i(15, 11))
				plan.access.append(Vector2i(15, 35))
				plan.place("kitchen", Vector2i(3, 1))
				plan.place("fridge", Vector2i(3, 32))
				plan.place("bookcase", Vector2i(22, 33))
			3:
				plan.reserve(Rect2i(11, 23, 9, 20))
				plan.access.append(Vector2i(15, 37))
				plan.place("desk", Vector2i(3, 33))
				plan.place("bookcase", Vector2i(22, 34))
			4:
				plan.reserve(Rect2i(12, 25, 9, 23))
				plan.access.append(Vector2i(16, 38))
				plan.place("bath", Vector2i(3, 30))
				plan.place("sink", Vector2i(21, 28))
				plan.place("toilet", Vector2i(22, 39))
	else:
		plan.reserve(Rect2i(11, 35, 9, depth - 35))
		plan.reserve(Rect2i(3, 35, 24, 11))
		plan.access.assign([Vector2i(14, 54), Vector2i(6, 40), Vector2i(23, 40)])
		match bay:
			0:
				plan.reserve(Rect2i(5, 18, 12, 18))
				plan.access.append(Vector2i(10, 22))
				plan.place("wardrobe", Vector2i(3, 5))
				plan.place("desk", Vector2i(19, 13))
			1:
				plan.reserve(Rect2i(19, 10, 8, 26))
				plan.access.append(Vector2i(22, 20))
				plan.place("table", Vector2i(10, 10))
				plan.place("bookcase", Vector2i(3, 10))
			3:
				plan.access.append(Vector2i(12, 33))
				plan.place("bed", Vector2i(3, 7))
				plan.place("nightstand", Vector2i(18, 9))
				plan.place("dresser", Vector2i(19, 22))
			4:
				plan.reserve(Rect2i(19, 14, 8, 26))
				plan.access.append(Vector2i(14, 19))
				plan.place("couch", Vector2i(3, 7))
				plan.place("coffee", Vector2i(5, 23))
				plan.place("tv", Vector2i(3, 29))
				plan.place("bookcase", Vector2i(3, 46))
		plan.place("radiator", Vector2i(10, 1), false)
	if not plan.has_route():
		push_error("Apartment plan has a blocked passage: %s" % key)
		plan.furniture.clear()
	_plans[key] = plan
	return plan


static func house(v: VoxelVolume, seed: int) -> void:
	var origins := [Vector3i(7, 3, 7), Vector3i(55, 3, 7), Vector3i(7, 35, 7), Vector3i(65, 35, 7)]
	var no_hides: Array[Dictionary] = []
	for i in origins.size():
		_bake(v, house_plan(i), origins[i], seed + i, no_hides)


static func house_plan(index: int) -> Layout:
	if _house_plans.is_empty():
		for room in 4:
			_house_plans.append(_build_house_plan(room))
	return _house_plans[index]


static func _build_house_plan(room: int) -> Layout:
	var size := Vector2i([46, 64, 56, 54][room], 82)
	var plan := Layout.new(size, Rect2i(Vector2i.ZERO, size))
	match room:
		0: # Ground-floor living room.
			plan.reserve(Rect2i(19, 35, 27, 12))
			plan.access.assign([Vector2i(40, 40), Vector2i(24, 40)])
			plan.place("couch", Vector2i(7, 7))
			plan.place("coffee", Vector2i(9, 20))
			plan.place("tv", Vector2i(8, 29))
			plan.place("bookcase", Vector2i(6, 52))
			plan.place("desk", Vector2i(32, 56))
		1: # Ground-floor kitchen and hall with two outside doors.
			plan.block(Rect2i(42, 44, 18, 36))
			plan.reserve(Rect2i(2, 0, 13, 46))
			plan.reserve(Rect2i(0, 15, 64, 13))
			plan.reserve(Rect2i(0, 35, 42, 12))
			plan.reserve(Rect2i(36, 35, 18, 9))
			plan.access.assign([Vector2i(7, 5), Vector2i(59, 21), Vector2i(5, 40), Vector2i(46, 39)])
			plan.place("kitchen", Vector2i(24, 0))
			plan.place("fridge", Vector2i(37, 3))
			plan.place("table", Vector2i(17, 53))
			plan.place("dresser", Vector2i(4, 61))
		2: # Upper bedroom across the partition.
			plan.reserve(Rect2i(18, 15, 38, 13))
			plan.access.assign([Vector2i(50, 21), Vector2i(23, 21)])
			plan.place("bed", Vector2i(7, 37))
			plan.place("nightstand", Vector2i(21, 40))
			plan.place("dresser", Vector2i(26, 57))
			plan.place("desk", Vector2i(30, 32))
		3: # Landing and a second bedroom.
			plan.block(Rect2i(32, 44, 18, 36))
			plan.reserve(Rect2i(0, 15, 36, 13))
			plan.reserve(Rect2i(22, 24, 10, 57))
			plan.access.assign([Vector2i(5, 21), Vector2i(27, 75)])
			plan.place("bed", Vector2i(3, 32))
			plan.place("nightstand", Vector2i(16, 34))
			plan.place("dresser", Vector2i(39, 31))
			plan.place("bookcase", Vector2i(4, 63))
	if not plan.has_route():
		push_error("House plan has a blocked passage: %d" % room)
		plan.furniture.clear()
	return plan


static func _bake(v: VoxelVolume, plan: Layout, origin: Vector3i, seed: int, hides: Array[Dictionary]) -> void:
	var fabric: String = FABRICS[seed % FABRICS.size()]
	for slot in plan.furniture:
		var at: Vector2i = slot.at
		var p := origin + Vector3i(at.x, 0, at.y)
		if not _fits_shell(v, p, FIXTURE_SIZE[slot.kind]):
			push_error("Interior furniture lost its floor or overlaps the shell: %s at %s" % [slot.kind, p])
			continue
		match slot.kind:
			"wardrobe":
				_wardrobe(v, p, hides)
			"bath":
				_bath(v, p, hides)
			"bed":
				_bed(v, p, fabric)
			"table":
				_dining(v, p)
			"couch":
				_couch(v, p, fabric)
			"kitchen":
				_kitchen(v, p)
			"desk":
				_table(v, p, Vector3i(8, 8, 5), "wood_light")
				_table(v, p + Vector3i(2, 0, 5), Vector3i(4, 5, 4), "wood_dark")
				_box(v, p + Vector3i(2, 8, 1), Vector3i(4, 1, 2), "curtain_beige")
			"dresser":
				_box(v, p + Vector3i(0, 0, 2), Vector3i(8, 9, 6), "wood_dark")
				for y in [2, 5, 8]:
					_box(v, p + Vector3i(1, y - 1, 1), Vector3i(6, 2, 1), "wood")
					_box(v, p + Vector3i(3, y, 0), Vector3i(2, 1, 1), "metal_white")
			"nightstand":
				_table(v, p, Vector3i(5, 5, 5), "wood")
				_box(v, p + Vector3i(1, 5, 1), Vector3i(3, 4, 3), "lamp")
			"coffee":
				_table(v, p, Vector3i(11, 5, 5), "wood_light")
				_box(v, p + Vector3i(3, 5, 1), Vector3i(5, 1, 3), "curtain_beige")
			"tv":
				_box(v, p, Vector3i(15, 7, 5), "wood_dark")
				_box(v, p + Vector3i(3, 7, 1), Vector3i(9, 7, 4), "tank_black")
				_box(v, p + Vector3i(4, 8, 0), Vector3i(7, 5, 1), "metal_teal")
			"bookcase":
				_box(v, p + Vector3i(1, 0, 0), Vector3i(4, 19, 10), "wood_dark")
				for shelf in [3, 8, 13]:
					_box(v, p + Vector3i(0, shelf, 1), Vector3i(1, 4, 2), FABRICS[(seed + shelf) % 3])
					_box(v, p + Vector3i(0, shelf + 1, 5), Vector3i(1, 3, 3), "wood_light")
			"fridge":
				_box(v, p, Vector3i(7, 18, 7), "pvc")
				for y in [8, 13]:
					_box(v, p + Vector3i(7, y, 1), Vector3i(1, 1, 4), "metal_dark")
			"sink":
				_box(v, p + Vector3i(1, 0, 1), Vector3i(4, 7, 4), "pvc")
				_box(v, p + Vector3i(0, 7, 0), Vector3i(6, 2, 6), "pvc")
				_box(v, p + Vector3i(1, 8, 1), Vector3i(4, 1, 4), "")
				_box(v, p + Vector3i(3, 9, 4), Vector3i(1, 2, 1), "metal")
			"toilet":
				_box(v, p, Vector3i(5, 4, 7), "pvc")
				_box(v, p + Vector3i(0, 4, 4), Vector3i(5, 4, 3), "pvc")
				_box(v, p + Vector3i(1, 3, 1), Vector3i(3, 1, 3), "metal_dark")
			"radiator":
				_box(v, p + Vector3i(0, 1, 0), Vector3i(10, 4, 2), "metal_white")
				for x in [0, 9]:
					_box(v, p + Vector3i(x, 0, 1), Vector3i(1, 1, 2), "metal_dark")


static func _fits_shell(v: VoxelVolume, p: Vector3i, size: Vector3i) -> bool:
	for occupied in v.material_histogram(p, p + size):
		if occupied > 0:
			return false
	var support := 0
	for occupied in v.material_histogram(p + Vector3i.DOWN, p + Vector3i(size.x, 0, size.z)):
		support += occupied
	return support == size.x * size.z


static func _wardrobe(v: VoxelVolume, p: Vector3i, hides: Array[Dictionary]) -> void:
	for x in [0, 12]:
		_box(v, p + Vector3i(x, 0, 0), Vector3i(1, 23, 13), "wood_dark")
	_box(v, p, Vector3i(13, 23, 1), "wood_dark")
	_box(v, p + Vector3i(0, 22, 0), Vector3i(13, 1, 13), "wood")
	_box(v, p + Vector3i(0, 0, 12), Vector3i(3, 22, 1), "wood")
	_box(v, p + Vector3i(1, 19, 3), Vector3i(11, 1, 8), "wood")
	_box(v, p + Vector3i(2, 20, 4), Vector3i(5, 2, 5), "curtain_beige")
	hides.append({"bath": false, "center": Vector3(p) + Vector3(6.5, 0.7, 6.4),
		"front": Vector3(p) + Vector3(7.5, 0, 17.5), "panel": Vector3(p) + Vector3(3, 0.1, 12.8)})


static func _bath(v: VoxelVolume, p: Vector3i, hides: Array[Dictionary]) -> void:
	_box(v, p, Vector3i(9, 6, 17), "pvc")
	_box(v, p + Vector3i(1, 2, 1), Vector3i(7, 4, 15), "")
	_box(v, p + Vector3i(0, 6, 2), Vector3i(2, 3, 2), "metal")
	_box(v, p + Vector3i(0, 5, 1), Vector3i(1, 18, 1), "metal")
	_box(v, p + Vector3i(1, 22, 1), Vector3i(8, 1, 1), "metal")
	_box(v, p + Vector3i(8, 22, 1), Vector3i(1, 1, 16), "metal")
	hides.append({"bath": true, "center": Vector3(p) + Vector3(4.5, 2.7, 8),
		"front": Vector3(p) + Vector3(13, 0, 8), "panel": Vector3(p) + Vector3(8.5, 4, 1.4)})


static func _bed(v: VoxelVolume, p: Vector3i, fabric: String) -> void:
	_box(v, p, Vector3i(13, 9, 2), "wood_dark")
	_box(v, p + Vector3i(0, 0, 2), Vector3i(13, 3, 20), "wood_dark")
	_box(v, p + Vector3i(0, 3, 2), Vector3i(13, 2, 20), "curtain_beige")
	_box(v, p + Vector3i(1, 5, 7), Vector3i(11, 1, 14), fabric)
	_box(v, p + Vector3i(3, 5, 3), Vector3i(7, 2, 3), "pvc")


static func _couch(v: VoxelVolume, p: Vector3i, fabric: String) -> void:
	_box(v, p, Vector3i(16, 4, 9), "wood_dark")
	_box(v, p + Vector3i(0, 4, 0), Vector3i(16, 6, 2), fabric)
	_box(v, p + Vector3i(1, 4, 2), Vector3i(14, 2, 7), fabric)
	for x in [0, 14]:
		_box(v, p + Vector3i(x, 4, 2), Vector3i(2, 4, 6), fabric)


static func _kitchen(v: VoxelVolume, p: Vector3i) -> void:
	_box(v, p, Vector3i(7, 9, 8), "pvc")
	_box(v, p + Vector3i(0, 3, 7), Vector3i(7, 4, 1), "metal_dark")
	for corner in [Vector3i(1, 9, 1), Vector3i(4, 9, 1), Vector3i(1, 9, 5), Vector3i(4, 9, 5)]:
		_box(v, p + corner, Vector3i(2, 1, 2), "tank_black")
	_box(v, p + Vector3i(0, 0, 8), Vector3i(7, 9, 7), "wood")
	_box(v, p + Vector3i(0, 9, 8), Vector3i(8, 1, 7), "metal_white")
	_box(v, p + Vector3i(2, 10, 9), Vector3i(4, 1, 4), "metal_dark")
	_box(v, p + Vector3i(2, 11, 12), Vector3i(1, 2, 1), "metal")
	_box(v, p + Vector3i(0, 9, 1), Vector3i(1, 10, 6), "wood")
	_box(v, p + Vector3i(1, 16, 1), Vector3i(6, 3, 6), "pvc")
	_box(v, p + Vector3i(6, 17, 2), Vector3i(1, 1, 3), "metal_white")


static func _dining(v: VoxelVolume, p: Vector3i) -> void:
	_table(v, p + Vector3i(0, 0, 5), Vector3i(9, 8, 10), "wood")
	for z in [0, 17]:
		_table(v, p + Vector3i(2, 0, z), Vector3i(5, 5, 4), "wood_dark")
		_box(v, p + Vector3i(2, 5, z + (3 if z > 0 else 0)), Vector3i(5, 4, 1), "wood")
	_box(v, p + Vector3i(3, 8, 9), Vector3i(3, 1, 3), "curtain_beige")


static func _table(v: VoxelVolume, p: Vector3i, size: Vector3i, finish: String) -> void:
	_box(v, p + Vector3i(0, size.y - 1, 0), Vector3i(size.x, 1, size.z), finish)
	for x in [0, size.x - 1]:
		for z in [0, size.z - 1]:
			_box(v, p + Vector3i(x, 0, z), Vector3i(1, size.y - 1, 1), "wood_dark")


static func _box(v: VoxelVolume, p: Vector3i, size: Vector3i, finish: String) -> void:
	v.fill_box(p, p + size, 0 if finish.is_empty() else VoxMat.id(finish))
