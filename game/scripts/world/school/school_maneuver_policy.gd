class_name SchoolManeuverPolicy
extends Resource
## Таблица тактик, обученная на графе школьных секторов.

enum { RUN, DODGE, BOOST, BOARD, CLOAK, ACTIONS }
const PATH := "res://scripts/world/school/school_maneuvers.tres"
const STATES := 3 * 3 * 2 * 8

@export var training_rounds := 0
@export var values := PackedFloat32Array()


static func situation(terrain: int, gap: float, closing: bool, tools: int) -> int:
	var range_band := 0 if gap < 5.0 else (1 if gap < 10.0 else 2)
	return ((terrain * 3 + range_band) * 2 + int(closing)) * 8 + tools


static func terrain(zone: String) -> int:
	return 2 if zone == "подземелье" else (1 if "этаж" in zone else 0)


static func available(action: int, tools: int) -> bool:
	return action < BOOST or (tools & (1 << (action - BOOST))) != 0


func ranked(state: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var scores := PackedFloat32Array()
	var choices := PackedInt32Array()
	for action in ACTIONS:
		if not available(action, state % 8):
			continue
		var value := values[state * ACTIONS + action] if values.size() == STATES * ACTIONS else 0.0
		var score := value + rng.randf_range(-0.65, 0.65)
		var index := 0
		while index < scores.size() and score <= scores[index]:
			index += 1
		scores.insert(index, score)
		choices.insert(index, action)
	return choices
