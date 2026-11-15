class_name MapSession
extends Node

signal changed
signal ping_requested(at: Vector2, floor_id: int)

const PING_SECONDS := 12.0
const HORN_SECONDS := 8.0

var gadgets: GameGadgets
var style := MapStyle.new()
var atlas := MapAtlas.new()
var fog := MapFog.new()
var markers: Array[Dictionary] = []
var nearby: Array[Dictionary] = []
var buckets: Array[Array] = []
var target := Vector2.INF
var target_floor := 0
var route := PackedVector2Array()
var route_status := ""
var current_floor := 0
var _ready_atlas := false
var _clock := 0.0
var _next_ping := 0.0
var _route_from := Vector2.INF
var _route_floor := -20
var _grids := {}
var _registrations := {}


func _ready() -> void:
	for i in MapStyle.NAMES.size():
		buckets.append([])
	GameState.settings_changed.connect(changed.emit)


func ensure_atlas() -> void:
	if _ready_atlas:
		return
	_ready_atlas = true
	var world := gadgets.world
	atlas.collect(gadgets.main, world)
	atlas.texture(0)
	for site in atlas.sites:
		if not str(site.name).is_empty():
			markers.append(marker(site.area.get_center(), MapStyle.POINT, 0, site.name))
	for room in atlas.rooms:
		if not str(room.title).is_empty():
			var item := marker(room.area.get_center(), MapStyle.POINT, room.floor, room.title)
			item.detail = true
			markers.append(item)
	markers.append(marker(xz(gadgets.button.global_position), MapStyle.LOOT, 0, "Автомат гаджетов"))
	var secrets := world.secrets
	if is_instance_valid(secrets) and secrets.targets.has("monitor"):
		var at: Vector3 = secrets.targets.monitor.global_position
		markers.append(marker(xz(at), MapStyle.POINT, atlas.layer_at(at.y), "Пост наблюдения"))
	_rebuild_buckets()
	changed.emit()


static func xz(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


static func marker(at: Vector2, kind: int, floor_id: int, title: String) -> Dictionary:
	return {"at": at, "kind": kind, "floor": floor_id, "title": title}


func record_horn(at: Vector3) -> void:
	ensure_atlas()
	var point := xz(at)
	var floor_id := atlas.layer_at(at.y - 1.3)
	if not validate_ping(point, floor_id):
		return
	var item := marker(point, MapStyle.HORN, floor_id, "Гудок")
	item.expires = Time.get_ticks_msec() * 0.001 + HORN_SECONDS
	_registrations[&"horn"] = item
	_rebuild_buckets()
	changed.emit()


# Источник решает, можно ли раскрывать позицию объекта игроку в текущем режиме.
func register_marker(key: StringName, at: Vector3, kind: int, title: String) -> void:
	if kind < 0 or kind >= buckets.size() or not at.is_finite():
		return
	ensure_atlas()
	_registrations[key] = marker(xz(at), kind, atlas.layer_at(at.y), title)
	changed.emit()


func unregister_marker(key: StringName) -> void:
	if _registrations.erase(key):
		changed.emit()


func _rebuild_buckets() -> void:
	for bucket in buckets:
		bucket.clear()
	for m: Dictionary in _registrations.values():
		buckets[int(m.kind)].append(m)
	for m in markers:
		buckets[int(m.kind)].append(m)
	for m in nearby:
		buckets[int(m.kind)].append(m)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0 or not _ready_atlas:
		return
	_clock = 1.0 / style.sample_hz
	var world := gadgets.world
	var player := world.player
	var pos := player.global_position
	var point := xz(pos)
	current_floor = atlas.layer_at(pos.y)
	fog.reveal(current_floor, atlas.uv(point), 9.0 / (atlas.half * 2.0))
	nearby.clear()
	if is_instance_valid(world.population) and (int(GameState.map_options.markers) & (1 << MapStyle.NPC)) != 0:
		var eye := player.camera.global_position
		for npc in world.population.actors:
			if not is_instance_valid(npc) or not npc.visible or pos.distance_squared_to(npc.global_position) > 14.0 * 14.0:
				continue
			if world.raycast(eye, npc.global_position + Vector3.UP, Layers.SOLID | Layers.CLOTH).is_empty():
				nearby.append(marker(xz(npc.global_position), MapStyle.NPC, atlas.layer_at(npc.global_position.y), "NPC"))
	for item in gadgets._pickups.values():
		if is_instance_valid(item.node) and pos.distance_squared_to(item.node.global_position) < 18.0 * 18.0:
			var at: Vector3 = item.node.global_position
			nearby.append(marker(xz(at), MapStyle.LOOT, atlas.layer_at(at.y), "Гаджет"))
	var now := Time.get_ticks_msec() * 0.001
	for key: StringName in _registrations.keys():
		if float(_registrations[key].get("expires", INF)) < now:
			_registrations.erase(key)
	_rebuild_buckets()
	if target.is_finite() and (_route_floor != current_floor or not _route_from.is_finite() or _route_from.distance_squared_to(point) > 9.0):
		_rebuild_route(point)


func validate_ping(at: Vector2, floor_id: int) -> bool:
	ensure_atlas()
	return at.is_finite() and absf(at.x) <= atlas.half and absf(at.y) <= atlas.half and floor_id in atlas.layers()


func set_pin(at: Vector2, floor_id: int, share := true) -> void:
	if not validate_ping(at, floor_id):
		return
	target = at
	target_floor = floor_id
	_rebuild_route(xz(gadgets.world.player.global_position))
	var now := Time.get_ticks_msec() * 0.001
	if share and now >= _next_ping:
		_next_ping = now + 0.65
		ping_requested.emit(at, floor_id)
		gadgets.world.sfx.play_ui("click", -9.0, 1.22)
	changed.emit()


func remote_ping(at: Vector2, floor_id: int) -> void:
	if not validate_ping(at, floor_id):
		return
	var item := marker(at, MapStyle.PING, floor_id, "Пинг игрока")
	item.expires = Time.get_ticks_msec() * 0.001 + PING_SECONDS
	_registrations[&"remote_ping"] = item
	_rebuild_buckets()
	changed.emit()


func clear_pin() -> void:
	target = Vector2.INF
	route.clear()
	route_status = ""
	changed.emit()


func reset_round() -> void:
	_registrations.clear()
	_rebuild_buckets()
	clear_pin()


func _rebuild_route(from: Vector2) -> void:
	_route_from = from
	current_floor = atlas.layer_at(gadgets.world.player.global_position.y)
	_route_floor = current_floor
	route = PackedVector2Array()
	if current_floor != target_floor:
		route_status = "Метка на другом этаже"
		return
	var grid := _grid(target_floor)
	if grid != null:
		var start := _nearest_cell(grid, from)
		var end := _nearest_cell(grid, target)
		if grid.is_in_boundsv(start) and grid.is_in_boundsv(end):
			route = _compress_path(grid.get_point_path(start, end))
	if route.size() > 1:
		route_status = "Маршрут по плану"
	else:
		route = PackedVector2Array([from, target])
		route_status = "Направление к метке"


func _compress_path(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var result := PackedVector2Array([points[0]])
	var last := points[1] - points[0]
	for i in range(1, points.size() - 1):
		var next := points[i + 1] - points[i]
		if not next.is_equal_approx(last):
			result.append(points[i])
		last = next
	result.append(points[-1])
	return result


func _grid(floor_id: int) -> AStarGrid2D:
	if floor_id > 0:
		return null
	if _grids.has(floor_id):
		return _grids[floor_id]
	var step := 2.0 if floor_id < 0 else 3.2
	var cells := ceili(atlas.half * 2.0 / step)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, cells, cells)
	grid.cell_size = Vector2.ONE * step
	grid.offset = Vector2.ONE * (-atlas.half + step * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in cells:
		for x in cells:
			var id := Vector2i(x, y)
			var at := grid.get_point_position(id)
			var walkable := floor_id == 0
			if floor_id < 0:
				for r in atlas.tunnels:
					if r.has_point(at):
						walkable = true
						break
			else:
				for site in atlas.sites:
					if site.key in ["stadium", "stands", "maze", "entry"]:
						continue
					if site.area.grow(0.5).has_point(at):
						walkable = false
						break
			grid.set_point_solid(id, not walkable)
	_grids[floor_id] = grid
	return grid


func _nearest_cell(grid: AStarGrid2D, point: Vector2) -> Vector2i:
	var guess := Vector2i(((point - grid.offset) / grid.cell_size).round()).clamp(Vector2i.ZERO, grid.region.end - Vector2i.ONE)
	var best := Vector2i(-1, -1)
	var distance := INF
	for y in range(-4, 5):
		for x in range(-4, 5):
			var id := guess + Vector2i(x, y)
			if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
				var d := grid.get_point_position(id).distance_squared_to(point)
				if d < distance:
					best = id
					distance = d
	return best
