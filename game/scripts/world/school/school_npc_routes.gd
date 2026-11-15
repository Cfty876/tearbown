class_name SchoolNpcRoutes
extends RefCounted

const STEP := 3
var origin: Vector3
var grid := AStarGrid2D.new()


func _init(volume: VoxelVolume, at: Vector3, area: Rect2i) -> void:
	origin = at
	var lo := (Vector2(area.position) / STEP).ceil()
	var hi := (Vector2(area.end) / STEP).floor()
	grid.region = Rect2i(Vector2i(lo), Vector2i(hi - lo))
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for z in range(grid.region.position.y, grid.region.end.y):
		for x in range(grid.region.position.x, grid.region.end.x):
			var id := Vector2i(x, z)
			var cell := id * STEP + Vector2i.ONE
			if not _walkable(volume, cell):
				grid.set_point_solid(id)


static func station(at: Vector3, facing: float, action: String, seat := 0.0, access := Vector3.INF) -> Dictionary:
	return {"at": at, "yaw": facing, "action": action, "seat": seat,
		"access": access if access.is_finite() else at}


func point(id: Vector2i) -> Vector3:
	var cell := id * STEP + Vector2i.ONE
	return origin + Vector3(cell.x * 0.1 + 0.05, 0.22, cell.y * 0.1 + 0.05)


func nearest(at: Vector3) -> Vector2i:
	var local := (at - origin) * (10.0 / STEP)
	var center := Vector2i(floori(local.x), floori(local.z))
	var nearest_id := center
	var best := INF
	for z in range(center.y - 5, center.y + 6):
		for x in range(center.x - 5, center.x + 6):
			var id := Vector2i(x, z)
			if not grid.region.has_point(id) or grid.is_point_solid(id):
				continue
			var distance := point(id).distance_squared_to(at)
			if distance < best:
				best = distance
				nearest_id = id
	return nearest_id if is_finite(best) else Vector2i(-9999, -9999)


func block(area: Rect2i) -> void:
	for z in range(grid.region.position.y, grid.region.end.y):
		for x in range(grid.region.position.x, grid.region.end.x):
			var id := Vector2i(x, z)
			if area.has_point(id * STEP + Vector2i.ONE):
				grid.set_point_solid(id)


func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := nearest(from)
	var end := nearest(to)
	if not grid.region.has_point(start) or not grid.region.has_point(end):
		return PackedVector3Array()
	var ids := grid.get_id_path(start, end)
	var route := PackedVector3Array()
	for id in ids:
		route.append(point(id))
	return route


static func _walkable(volume: VoxelVolume, cell: Vector2i) -> bool:
	for offset in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var x: int = cell.x + offset.x
		var z: int = cell.y + offset.y
		if volume.get_voxel(Vector3i(x, 1, z)) == 0:
			return false
		for y in [2, 4, 7, 10, 13, 16, 19]:
			if volume.get_voxel(Vector3i(x, y, z)) != 0:
				return false
	return true
