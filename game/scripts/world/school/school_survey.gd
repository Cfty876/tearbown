class_name SchoolSurvey
extends RefCounted
## Карта бота считает только клетки, доступные по графу, и открывается движением.

enum { ANY, YARD, BASEMENT, UPPER }
const CELL := 10.0
const REVEAL := 9.0
const TARGET := 0.90

var cells := {}
var destinations := {}
var explored := {}
var _by_kind := [0, 0, 0, 0]
var _last := Vector3.INF
var _last_yard := 0.0
var _yard_seen := false


static func area(at: Vector3, zone: String) -> int:
	if at.y < -2.0:
		return BASEMENT
	if at.y > 4.4:
		return UPPER
	return YARD if "этаж" not in zone else ANY


static func key(at: Vector3) -> Vector3i:
	var floor_id := -1 if at.y < -2.0 else clampi(roundi((at.y - 2.12) / 3.8), 0, 4)
	return Vector3i(floori(at.x / CELL), floor_id, floori(at.z / CELL))


func build(points: Array[Dictionary]) -> void:
	for point in points:
		var at: Vector3 = point.at
		var cell := key(at)
		if not cells.has(cell):
			cells[cell] = []
			destinations[cell] = []
		cells[cell].append(at)
		if int(point.spot) < 0:
			destinations[cell].append(point)


func reveal(at: Vector3) -> void:
	if at.distance_squared_to(_last) < 2.5 * 2.5:
		return
	_last = at
	var cell := key(at)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var neighbor := cell + Vector3i(dx, 0, dz)
			if explored.has(neighbor) or not cells.has(neighbor):
				continue
			for point: Vector3 in cells[neighbor]:
				if at.distance_squared_to(point) <= REVEAL * REVEAL:
					explored[neighbor] = true
					_by_kind[area(point, SchoolHuntRoutes.zone(point))] += 1
					break


func coverage() -> float:
	return float(explored.size()) / maxi(1, cells.size())


func watch_sector(at: Vector3, elapsed: float) -> void:
	if area(at, SchoolHuntRoutes.zone(at)) == YARD:
		_last_yard = elapsed
		_yard_seen = true


func needs_yard(elapsed: float, at: Vector3) -> bool:
	return area(at, SchoolHuntRoutes.zone(at)) != YARD and elapsed - _last_yard > (73.0 if _yard_seen else 12.0)


func priority(elapsed: float) -> int:
	if _by_kind[YARD] < 5 and elapsed < 24.0:
		return YARD
	if _by_kind[BASEMENT] < 3 and elapsed < 100.0:
		return BASEMENT
	if _by_kind[YARD] < 10 and elapsed < 155.0:
		return YARD
	if _by_kind[UPPER] < 5 and elapsed < 180.0:
		return UPPER
	return ANY


func frontier(from: Vector3, area_filter: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var floor_id := key(from).y
	for cell: Vector3i in destinations:
		var choices: Array = destinations[cell]
		if explored.has(cell) or choices.is_empty():
			continue
		var goal: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
		var at: Vector3 = goal.at
		if area_filter != ANY and area(at, goal.zone) != area_filter:
			continue
		var distance := from.distance_to(at)
		if distance < 9.0 or distance > 135.0:
			continue
		# Сначала исследуем компактные группы клеток, оставляя разброс между раундами.
		var travel := distance + (13.0 if floor_id != cell.y else 0.0)
		var score := novelty(at) * 1.75 - travel * 0.36 + rng.randf_range(0.0, 11.0)
		result.append({"goal": goal, "score": score})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
	return result


func novelty(at: Vector3) -> float:
	if coverage() >= TARGET:
		return 0.0
	var cell := key(at)
	var score := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var neighbor := cell + Vector3i(dx, 0, dz)
			if cells.has(neighbor) and not explored.has(neighbor):
				score += 5.0 if dx == 0 and dz == 0 else 1.35
	return score
