class_name HideCombat
extends RefCounted

const HIT := 20
const STUN_TIME := 5.0

# Длительность, амплитуда видимой реакции и встряска камеры.
static func reaction(weapon: int) -> Vector3:
	match weapon:
		PlayerTools.HAMMER: return Vector3(0.37, 0.41, 0.40)
		PlayerTools.SHOTGUN: return Vector3(0.24, 0.27, 0.34)
		PlayerTools.PIPEBOMB: return Vector3(0.43, 0.31, 0.46)
		PlayerTools.ROCKET: return Vector3(0.48, 0.39, 0.50)
		_: return Vector3(0.30, 0.25, 0.34)


# Две перекрывающиеся сферы повторяют торс и голову воксельного персонажа.
static func contact(from: Vector3, to: Vector3, feet: Vector3, crouched: bool) -> Vector3:
	var line := to - from
	var distance := line.length()
	if distance < 0.001:
		return Vector3.INF
	var direction := line / distance
	var best := distance + 1.0
	for height: float in ([0.44, 0.84] if crouched else [0.75, 1.33]):
		var offset := feet + Vector3.UP * height - from
		var along := offset.dot(direction)
		var miss_squared := offset.length_squared() - along * along
		if miss_squared > 0.44 * 0.44:
			continue
		var inset := sqrt(maxf(0.0, 0.44 * 0.44 - miss_squared))
		if along + inset >= 0.0:
			best = minf(best, maxf(0.0, along - inset))
	return from + direction * best if best <= distance else Vector3.INF


static func blast_reaches(world: VoxelWorld, from: Vector3, feet: Vector3, radius: float) -> bool:
	var center := feet + Vector3.UP * 0.78
	return center.distance_squared_to(from) <= radius * radius and world.raycast(from, center, Layers.SOLID | Layers.CLOTH).is_empty()
