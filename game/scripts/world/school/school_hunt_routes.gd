class_name SchoolHuntRoutes
extends RefCounted

const STEP := 1.18
const FLOOR_Y := {-1: -3.68, 0: 2.12, 1: 6.02, 2: 9.82, 3: 13.62, 4: 17.52, 5: 5.24}
const DIRECTIONS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
const CAMPUS_SITES := ["west", "east", "bridge", "sports_bridge", "annex"]

var world: VoxelWorld
var school: SchoolLevel
var graph := AStar3D.new()
var cells := {}
var passages := {}
var covers: Array[Dictionary] = []
var lockers: Array[Dictionary] = []
var outdoor_covers: Array[Dictionary] = []
var basement_covers: Array[Dictionary] = []
var stations: Array[Dictionary] = []
var reachable := {}
var entry_exit := -1
var entry_inside := -1
var _clearance := PhysicsShapeQueryParameters3D.new()


func _init(voxel_world: VoxelWorld, level: SchoolLevel) -> void:
	world = voxel_world
	school = level
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.53
	_clearance.shape = capsule
	_clearance.collision_mask = Layers.STATIC


func build() -> void:
	var timer := Time.get_ticks_msec()
	for floor: int in FLOOR_Y:
		var regions := _regions(floor)
		for area: Rect2 in regions:
			for x in range(ceili(area.position.x / STEP), floori(area.end.x / STEP) + 1):
				for z in range(ceili(area.position.y / STEP), floori(area.end.y / STEP) + 1):
					var cell := Vector3i(x, floor, z)
					if cells.has(cell):
						continue
					var probe := Vector3(x * STEP, FLOOR_Y[floor], z * STEP)
					var feet := floor_at(probe)
					if feet.is_finite() and _space_at(feet):
						cells[cell] = _point(feet)
				if Time.get_ticks_msec() - timer > 18:
					await world.get_tree().process_frame
					timer = Time.get_ticks_msec()
	for cell: Vector3i in cells:
		var from: int = cells[cell]
		for direction: Vector2i in DIRECTIONS:
			var other := cell + Vector3i(direction.x, 0, direction.y)
			if cells.has(other):
				var to: int = cells[other]
				var a := graph.get_point_position(from)
				var b := graph.get_point_position(to)
				# Только специальный переход умеет открыть обе створки и подняться на порог.
				var crosses_entry := floori(a.y) == 2 and floori(b.y) == 2 and absf(a.x) < 2.3 and absf(b.x) < 2.3 \
					and (a.z - 12.24) * (b.z - 12.24) < 0.0
				if not crosses_entry and _walkable_link(a, b):
					graph.connect_points(from, to)
		if Time.get_ticks_msec() - timer > 18:
			await world.get_tree().process_frame
			timer = Time.get_ticks_msec()
	_connect_classrooms()
	_connect_entry()
	_connect_stairs()
	_connect_shortcuts()
	_connect_lift()
	var origin := nearest(school.spawn, 5.0, true)
	_walk_component(origin)
	_collect_covers()
	for cover in covers:
		var at: Vector3 = cover.at
		if at.y < -2.0:
			basement_covers.append(cover)
		elif at.y < 4.0 and "этаж" not in str(cover.zone):
			outdoor_covers.append(cover)


func _regions(floor: int) -> Array[Rect2]:
	var regions: Array[Rect2] = []
	if floor == 0:
		var edge := SchoolLevel.HALF - 0.7
		return [Rect2(-edge, -edge, edge * 2.0, edge * 2.0)]
	if floor == 5:
		var greenhouse: Rect2i = SchoolGrid.SITES.greenhouse
		return [Rect2(Vector2(greenhouse.position) * 0.1, Vector2(greenhouse.size) * 0.1)]
	if floor == -1:
		for zone: String in SchoolBasement.TUNNELS:
			for room: Rect2i in SchoolBasement.TUNNELS[zone]:
				regions.append(Rect2(room).grow(-0.35))
		return regions
	for site in CAMPUS_SITES:
		var room: Rect2i = SchoolGrid.SITES[site]
		regions.append(Rect2(Vector2(room.position) * 0.1, Vector2(room.size) * 0.1))
	return regions


func floor_at(at: Vector3, range_y := 0.48) -> Vector3:
	var hit := world.raycast(at + Vector3.UP * range_y, at - Vector3.UP * range_y, Layers.STATIC)
	if hit.is_empty() or hit.normal.y < 0.62:
		return Vector3.INF
	return hit.position + Vector3.UP * 0.025


func _space_at(at: Vector3) -> bool:
	_clearance.transform.origin = at + Vector3.UP * 0.775
	return world.get_world_3d().direct_space_state.intersect_shape(_clearance, 1).is_empty()


func _point(at: Vector3) -> int:
	var id := graph.get_available_point_id()
	graph.add_point(id, at)
	return id


func _walkable_link(from: Vector3, to: Vector3) -> bool:
	if absf(from.y - to.y) > 0.38:
		return false
	var across := (to - from).slide(Vector3.UP).normalized().cross(Vector3.UP) * 0.27
	for offset in [Vector3.UP * 0.34, Vector3.UP * 1.25, Vector3.UP * 0.84 + across, Vector3.UP * 0.84 - across]:
		if not world.raycast(from + offset, to + offset, Layers.STATIC).is_empty():
			return false
	return floor_at(from.lerp(to, 0.5), 0.40).is_finite()


func nearest(at: Vector3, radius := 2.65, check_path := false, connected_only := false) -> int:
	var ix := roundi(at.x / STEP)
	var iz := roundi(at.z / STEP)
	var extent := ceili(radius / STEP)
	var closest := -1
	var best := radius * radius
	for floor: int in FLOOR_Y:
		if absf(float(FLOOR_Y[floor]) - at.y) > 0.79:
			continue
		for x in range(ix - extent, ix + extent + 1):
			for z in range(iz - extent, iz + extent + 1):
				var id: int = cells.get(Vector3i(x, floor, z), -1)
				if id < 0 or graph.is_point_disabled(id) or (connected_only and not reachable.has(id)):
					continue
				var other := graph.get_point_position(id)
				var distance := other.distance_squared_to(at)
				if distance < best and (not check_path or _walkable_link(at, other)):
					closest = id
					best = distance
	return closest


func _connect_classrooms() -> void:
	for room: Dictionary in school.rooms:
		if not room.plan.has("door_z"):
			continue
		var plan: Dictionary = room.plan
		var at := SchoolGrid.origin("west" if room.at.x < 0.0 else "east", SchoolLevel.GROUND + (int(room.floor) - 1) * SchoolLevel.LEVEL_HEIGHT)
		var z := (int(plan.door_z) + 8) * 0.1
		var near := at + Vector3(6.40 if plan.col == 0 else 11.58, 0.23, z)
		var far := at + Vector3(7.46 if plan.col == 0 else 12.74, 0.23, z)
		if _walkable_link(near, far):
			_add_passage(PackedVector3Array([near, far]), "doorway", true)


func _connect_entry() -> void:
	var path := PackedVector3Array([Vector3(0, 2.225, 10.62), Vector3(0, 2.225, 12.10),
		Vector3(0, 2.225, 12.34), Vector3(0, 2.025, 13.25), Vector3(0, 2.025, 14.16)])
	var inside := nearest(path[0], 1.4, true)
	var outside := nearest(path[-1], 1.4, true)
	if inside < 0 or outside < 0 or inside == outside:
		return
	entry_exit = outside
	entry_inside = inside
	_add_passage(path, "entrance", true)


func _connect_stairs() -> void:
	for side in 2:
		var z0 := 3 if side == 0 else 483
		var x0 := 3 if side == 0 else 123
		for floor in 3:
			var origin := SchoolGrid.origin("west" if side == 0 else "east", SchoolLevel.GROUND + floor * SchoolLevel.LEVEL_HEIGHT)
			var left := (x0 + 16) * 0.1
			var right := (x0 + 48) * 0.1
			var aisle := 7.52 if side == 0 else 11.48
			var entry_z := (z0 + 75) * 0.1
			var path := PackedVector3Array([origin + Vector3(aisle, 0.225, entry_z), origin + Vector3(left, 0.225, entry_z)])
			for step in 10:
				var y := (2 + roundi((step + 1) * 1.9)) * 0.1 + 0.025
				path.append(origin + Vector3(left, y, (z0 + 58 - step * 4) * 0.1))
			path.append(origin + Vector3(left, 2.125, (z0 + 18) * 0.1))
			path.append(origin + Vector3(right, 2.125, (z0 + 18) * 0.1))
			for step in 10:
				var y := (21 + roundi((step + 1) * 1.9)) * 0.1 + 0.025
				path.append(origin + Vector3(right, y, (z0 + 25 + step * 4) * 0.1))
			path.append(origin + Vector3(right, 4.025, entry_z))
			path.append(origin + Vector3(aisle, 4.025, entry_z))
			_add_passage(path, "stairs", true)
	var entrance := SchoolBasement.ENTRANCE
	var middle := entrance.get_center().y
	var stair := PackedVector3Array([Vector3(entrance.position.x - 0.8, 2.02, middle)])
	for step in 30:
		stair.append(Vector3(entrance.position.x + (step + 0.5) * 0.3,
			SchoolLevel.BASEMENT + 6.025 - step * 0.2, middle))
	stair.append(Vector3(entrance.end.x + 1.0, -3.68, middle))
	_add_passage(stair, "stairs", true)


func _connect_shortcuts() -> void:
	var secrets := world.secrets as SchoolSecrets
	for key: String in secrets._paths:
		if key == "cyclone" or key.begins_with("pipe/"):
			var pipe: PackedVector3Array = secrets._paths[key].duplicate()
			var station := 0 if key == "cyclone" else int(key.get_slice("/", 1))
			pipe.insert(0, SchoolPipe.LANDINGS[station])
			_add_passage(pipe, "pipe", false)
		elif key == "loft/up":
			var loft: PackedVector3Array = secrets._paths[key].duplicate()
			loft.insert(0, SchoolLevel.ATTIC + Vector3(1.15, 0.22, 0.96))
			loft.append(SchoolLevel.ATTIC + Vector3(0, 3.93, 2.28))
			_add_passage(loft, "ladder", true)
		elif key == "greenhouse/up":
			_add_passage(secrets._paths[key], "ladder", true)
		elif key in ["duct", "duct_return", "boiler/down", "boiler/up"]:
			_add_passage(secrets._paths[key], "ventilation" if key.begins_with("duct") else "shaft", false)
	for key: String in school.restroom_links:
		var link: Dictionary = school.restroom_links[key]
		var other: Vector3 = school.restroom_links[link.pair].landing
		_add_passage(PackedVector3Array([link.landing, other]), "booth", false)


func _connect_lift() -> void:
	var lift := (world.secrets as SchoolSecrets).elevator
	var stops := PackedInt64Array()
	for floor in SchoolElevator.FLOORS.size():
		stops.append(nearest(lift.landing(floor), 2.25, true))
	for from in stops.size():
		for to in stops.size():
			if from == to or stops[from] < 0 or stops[to] < 0 or stops[from] == stops[to]:
				continue
			var edge := Vector2i(stops[from], stops[to])
			graph.connect_points(edge.x, edge.y, false)
			passages[edge] = {"kind": "lift", "from": from, "to": to,
				"path": PackedVector3Array([graph.get_point_position(edge.x), graph.get_point_position(edge.y)])}


func add_bunker_routes() -> void:
	var secrets := world.secrets as SchoolSecrets
	for key in ["bunker/down", "bunker/up"]:
		if secrets._paths.has(key):
			_add_passage(secrets._paths[key], "shaft", false)


func utility_approach(key: String) -> Dictionary:
	var at: Vector3 = world.secrets._action_pos(key)
	if not at.is_finite():
		return {}
	var node := _station_approach(key, at)
	if node < 0:
		return {}
	var point := graph.get_point_position(node)
	return {"node": node, "at": point, "spot": -1, "quality": 0,
		"zone": zone(point), "utility": key}


func _add_passage(path: PackedVector3Array, kind: String, reversible: bool) -> void:
	if path.size() < 2:
		return
	var from := nearest(path[0], 2.8, true)
	var to := nearest(path[-1], 2.8, true)
	if from < 0 or to < 0 or from == to:
		return
	graph.connect_points(from, to, reversible)
	var way := PackedVector3Array([graph.get_point_position(from)])
	way.append_array(path)
	way.append(graph.get_point_position(to))
	passages[Vector2i(from, to)] = {"kind": kind, "path": way}
	if reversible:
		way = way.duplicate()
		way.reverse()
		passages[Vector2i(to, from)] = {"kind": kind, "path": way}


func _walk_component(origin: int) -> void:
	if origin < 0:
		return
	var pending := PackedInt64Array([origin])
	reachable[origin] = true
	var cursor := 0
	while cursor < pending.size():
		for neighbor: int in graph.get_point_connections(pending[cursor]):
			if not graph.is_point_disabled(neighbor) and not reachable.has(neighbor):
				reachable[neighbor] = true
				pending.append(neighbor)
		cursor += 1


func _collect_covers() -> void:
	for id in school.hide_spots.size():
		var info: Dictionary = school.hide_spots[id]
		var at: Vector3 = info.building.to_global(Vector3(info.front) * 0.1)
		var node := nearest(at, 2.45, true, true)
		if node >= 0:
			var approach := graph.get_point_position(node)
			if world.player.hides._accessible(id, approach):
				var spot := {"node": node, "at": approach, "spot": id, "quality": 3, "zone": zone(at)}
				lockers.append(spot)
				covers.append(spot)
	for cell: Vector3i in cells:
		if posmod(cell.x * 3 + cell.z * 5 + cell.y, 7) != 0:
			continue
		var id: int = cells[cell]
		if not reachable.has(id):
			continue
		var at := graph.get_point_position(id)
		var quality := 0
		for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var eye := at + Vector3.UP * 0.82
			if not world.raycast(eye, eye + dir * 2.2, Layers.STATIC).is_empty():
				quality += 1
		covers.append({"node": id, "at": at, "spot": -1, "quality": quality, "zone": zone(at)})
	for key in ["guard_bell", "radio", "screen_hint", "power", "wheel", "football"]:
		var at: Vector3 = world.secrets._action_pos(key)
		if not at.is_finite():
			continue
		var node := _station_approach(key, at)
		if node >= 0:
			stations.append({"key": key, "node": node, "at": at})


func _station_approach(key: String, at: Vector3) -> int:
	var secrets := world.secrets as SchoolSecrets
	var target: Vector3 = secrets._controls[key].global_position if secrets._controls.has(key) else at
	var chosen := -1
	var best := 10.0
	for i in 12:
		var side := Vector3.FORWARD.rotated(Vector3.UP, float(i) * TAU / 12.0)
		for height: float in [0.18, 1.02, 1.74]:
			var node := nearest(target + side * 1.42 - Vector3.UP * height, 1.65, false, true)
			if node < 0:
				continue
			var feet := graph.get_point_position(node)
			var distance := feet.distance_squared_to(at)
			if distance < best and can_use_station(key, feet):
				best = distance
				chosen = node
	return chosen


func can_use_station(key: String, feet: Vector3) -> bool:
	var secrets := world.secrets as SchoolSecrets
	var action: Vector3 = secrets._action_pos(key)
	var target: Vector3 = secrets._controls[key].global_position if secrets._controls.has(key) else action
	if not action.is_finite() or feet.distance_squared_to(action) > 10.0:
		return false
	var hit := world.raycast(feet + Vector3.UP * 1.43, target, DistrictSecrets.MASK)
	return hit.is_empty() or secrets._target_key(hit) == key


static func zone(at: Vector3) -> String:
	if at.y < -2.0:
		return "подземелье"
	if at.y > 16.9 and at.x < 58.0 and at.z > -30.0 and at.z < 32.0:
		return "крыша школы"
	var floor := clampi(roundi((at.y - 2.2) / 3.8) + 1, 1, 4)
	if at.z > -29.4 and at.z < 31.5:
		if at.x > -29.4 and at.x < -9.8:
			return "корпус А · %d этаж" % floor
		if at.x > 9.8 and at.x < 29.4:
			return "корпус Б · %d этаж" % floor
		if at.x >= 34.8 and at.x < 58.5 and at.z < 19.4 and at.z > -15.4:
			return "спорткорпус · %d этаж" % floor
		if absf(at.x) < 10.0 and at.z > -6.5 and at.z < 12.5:
			return "центральный переход · %d этаж" % floor
	if at.z < -36.0:
		if at.x < 7.0:
			return "стадион и трибуны"
		if at.x < 41.0:
			return "двор у теплицы"
		return "двор котельной"
	if at.z > 31.0:
		return "мастерские и гаражи" if at.x > 30.0 else "передний двор"
	return "боковые дорожки"
