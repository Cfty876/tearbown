class_name SchoolPipe
extends RefCounted
## Each node is the feet position on the shared ventilation line.
const NODES := [
	Vector3(49.5, 2.2, 44.5), Vector3(49.5, 2.2, 42.0), Vector3(49.5, 6.0, 42.0),
	Vector3(60.0, 6.0, 42.0), Vector3(60.0, 6.0, -41.0), Vector3(63.3, 6.0, -41.0),
	Vector3(63.3, 2.0, -41.0), Vector3(63.3, 2.0, -44.0),
	Vector3(19.5, 6.0, -41.0), Vector3(19.5, 6.0, -32.5), Vector3(19.5, 6.0, -26.2),
	Vector3(-19.5, 6.0, -32.5), Vector3(-19.5, 6.0, -26.2),
]
const STOPS := [0, 7, 10, 12]
const NAMES := ["мастерские", "двор котельной", "корпус Б", "корпус А"]
const LANDINGS := [Vector3(49.5, 2.27, 46.0), Vector3(63.3, 2.07, -45.6),
	Vector3(19.5, 6.07, -24.7), Vector3(-19.5, 6.07, -24.7)]
const LEGS := [[0, 1, 2, 3, 4, 5, 6, 7], [7, 6, 5, 4, 8, 9, 10], [10, 9, 11, 12]]
const SHELL := 20
const INNER := 16
const FLOOR_CLEARANCE := 0.045


static func build(controller: SchoolSecrets) -> void:
	var joins := {}
	var segments := {}
	for leg: Array in LEGS:
		for i in range(leg.size() - 1):
			var a: int = leg[i]
			var b: int = leg[i + 1]
			var direction := Vector3i((Vector3(NODES[b]) - Vector3(NODES[a])).normalized().round())
			if not joins.has(a):
				joins[a] = []
			if not joins.has(b):
				joins[b] = []
			if direction not in joins[a]:
				joins[a].append(direction)
				joins[b].append(-direction)
			var segment := Vector2i(mini(a, b), maxi(a, b))
			if not segments.has(segment):
				segments[segment] = true
				_section(controller.school, _center(a), _center(b))
	for i: int in joins:
		var stop := STOPS.find(i)
		if stop >= 0:
			joins[i].append(Vector3i((Vector3(LANDINGS[stop]) - Vector3(NODES[i])).normalized().round()))
		_joint(controller.school, _center(i), joins[i], stop)
	_support_crossings(controller.school)
	for i in LEGS.size():
		_register_route(controller, i, i + 1, LEGS[i])
		var reversed: Array = LEGS[i].duplicate()
		reversed.reverse()
		_register_route(controller, i + 1, i, reversed)


static func _support_crossings(level: SchoolLevel) -> void:
	var column := Build.vol(Vector3i(6, 38, 6))
	SchoolLevel.box(column, Vector3i.ZERO, Vector3i(6, 3, 6), "concrete_dark")
	SchoolLevel.box(column, Vector3i(1, 3, 1), Vector3i(4, 33, 4), "metal_teal")
	SchoolLevel.box(column, Vector3i(0, 36, 0), Vector3i(6, 2, 6), "metal_dark")
	for at in [Vector3(-16.2, 2, -32.8), Vector3(11.7, 2, -32.8), Vector3(30.2, 2, -41.3), Vector3(44.2, 2, -41.3)]:
		level.place(column, at, "Стойка перехода вентиляции")


static func _center(index: int) -> Vector3:
	return Vector3(NODES[index]) + Vector3.UP * (0.8 + FLOOR_CLEARANCE)


static func _section(level: SchoolLevel, a: Vector3, b: Vector3) -> void:
	var delta := (b - a).abs()
	var axis := delta.max_axis_index()
	var length := roundi(delta[axis] * 10) - SHELL
	assert(length > 0, "Pipe junctions need at least 2 m of separation")
	var size := Vector3i.ONE * SHELL
	size[axis] = length
	var volume := Build.vol(size)
	SchoolLevel.box(volume, Vector3i.ZERO, size, "metal_teal")
	var cut := Vector3i.ONE * 2
	var opening := Vector3i.ONE * INNER
	cut[axis] = 0
	opening[axis] = length
	SchoolLevel.box(volume, cut, opening, "")
	for rib in range(0, length, 21):
		for face in 3:
			if face == axis:
				continue
			for edge in [0, SHELL - 1]:
				var strip := Vector3i.ZERO
				var extent := Vector3i.ONE * SHELL
				strip[axis] = rib
				strip[face] = edge
				extent[axis] = 1
				extent[face] = 1
				SchoolLevel.box(volume, strip, extent, "metal_dark")
	var base := (a.min(b) - Vector3.ONE).snapped(Vector3.ONE * 0.1)
	base[axis] += 2.0
	if axis != 1:
		_line_interior(level, volume, axis, length, base)
	_clear_existing_floor(volume, base)
	level.place(volume, base, "Воксельная вентиляция", Vector3i(64, 38, 64))


static func _line_interior(level: SchoolLevel, volume: VoxelVolume, axis: int, length: int, base: Vector3) -> void:
	var across := 2 if axis == 0 else 0
	var strip := Vector3i(0, 1, 0)
	strip[axis] = length
	strip[across] = 1
	for edge in [3, 16]:
		var rail := Vector3i(0, 1, 0)
		rail[across] = edge
		SchoolLevel.box(volume, rail, strip, "metal_yellow")
		rail.y = 17
		SchoolLevel.box(volume, rail, strip, "metal")
	for position in range(3, length - 2, 7):
		var tile := Vector3i(0, 1, 0)
		var tread := Vector3i(0, 1, 0)
		tile[axis] = position
		tile[across] = 5
		tread[axis] = 1
		tread[across] = 10
		SchoolLevel.box(volume, tile, tread, "rubber")
	for position in range(8, length - 8, 130):
		var tile := Vector3i(0, 17, 0)
		var fixture := Vector3i(0, 1, 0)
		tile[axis] = position
		tile[across] = 7
		fixture[axis] = 5
		fixture[across] = 6
		SchoolLevel.box(volume, tile, fixture, "lamp")
		var light_at := Vector3(tile) * 0.1 + base - Vector3.UP * 0.10
		level.fixture(volume, tile + Vector3i(1 if axis == 0 else 2, 0, 1 if axis == 2 else 2), light_at, Color("#c8e8de"), 1.0, 4.2)


static func _joint(level: SchoolLevel, center: Vector3, directions: Array, stop: int) -> void:
	var size := Vector3i.ONE * SHELL
	var volume := Build.vol(size)
	SchoolLevel.box(volume, Vector3i.ZERO, size, "metal_teal")
	SchoolLevel.box(volume, Vector3i(0, 0, 0), Vector3i(SHELL, 2, SHELL), "metal_dark")
	SchoolLevel.box(volume, Vector3i.ONE * 2, Vector3i.ONE * INNER, "")
	for direction: Vector3i in directions:
		var axis := direction.abs().max_axis_index()
		var start := Vector3i.ONE * 2
		var extent := Vector3i.ONE * INNER
		start[axis] = SHELL / 2 if direction[axis] > 0 else 0
		extent[axis] = SHELL / 2
		SchoolLevel.box(volume, start, extent, "")
	if Vector3i.UP not in directions:
		SchoolLevel.box(volume, Vector3i(8, 17, 8), Vector3i(4, 1, 4), "lamp")
		level.fixture(volume, Vector3i(9, 17, 9), center + Vector3.UP * 0.66, Color("#ffe0ab"), 1.05, 3.4)
	var name := "Поворот вентиляции" if stop < 0 else "Станция %d · %s" % [stop + 1, NAMES[stop]]
	var base := (center - Vector3.ONE).snapped(Vector3.ONE * 0.1)
	_clear_existing_floor(volume, base)
	level.place(volume, base, name)


static func _clear_existing_floor(volume: VoxelVolume, base: Vector3) -> void:
	var size := volume.get_size()
	var footprint := Rect2i(Vector2i((Vector2(base.x, base.z) * 10.0).round()), Vector2i(size.x, size.z))
	if base.y < SchoolLevel.GROUND:
		SchoolLevel.box(volume, Vector3i.ZERO, Vector3i(size.x, roundi((SchoolLevel.GROUND - base.y) * 10.0), size.z), "")
		return
	for site in ["west", "east", "workshop"]:
		var floor_y := 2.2 if site == "workshop" else 6.0
		if base.y >= floor_y - 0.01 or base.y < floor_y - 0.22:
			continue
		var intersection: Rect2i = footprint.intersection(SchoolGrid.SITES[site])
		if intersection.has_area():
			var cut := intersection.position - footprint.position
			SchoolLevel.box(volume, Vector3i(cut.x, 0, cut.y),
				Vector3i(intersection.size.x, roundi((floor_y - base.y) * 10.0), intersection.size.y), "")


static func _register_route(controller: SchoolSecrets, from: int, to: int, leg: Array) -> void:
	var path := PackedVector3Array()
	for index: int in leg:
		path.append(Vector3(NODES[index]) + Vector3.UP * FLOOR_CLEARANCE)
	path.append(LANDINGS[to])
	var key := "cyclone" if from == 0 else "pipe/%d/%d" % [from, to]
	var sign_x := 1.0 if to > from else -1.0
	var control := Vector3(LANDINGS[from]) + Vector3(sign_x * 0.98, 1.02, 0)
	var stand := Build.vol(Vector3i(4, 12, 4))
	SchoolLevel.box(stand, Vector3i(1, 0, 1), Vector3i(2, 10, 2), "metal_teal")
	SchoolLevel.box(stand, Vector3i(0, 9, 0), Vector3i(4, 3, 4), "metal_dark")
	DistrictSecretProps.model(controller, stand, control - Vector3.UP * 1.02, true, 0.0, "Пульт вентиляции")
	var normal := Vector3.FORWARD if from == 1 else Vector3.BACK
	controller.add_control(key, control + normal * 0.23, Vector3(0.28, 0.28, 0.18),
		"проехать · %s" % NAMES[to], normal)
	controller._paths[key] = path
