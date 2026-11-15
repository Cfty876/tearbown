class_name SchoolPursuitPolicy
extends Resource

enum { BURST, COVER, SHORTCUT, FEINT, DETOUR }
const ACTIONS := 5
const STATES := 150
const PATH := "res://scripts/world/school/school_pursuit_policy.tres"
const SHORTCUT_LINKS := ["stairs", "shaft", "pipe", "ladder", "booth", "lift", "ventilation"]
const RUN_MIN := 6.15
const RUN_FAST := 7.55


static func run_speed(action: int, stamina: float) -> float:
	var top := RUN_FAST if action == BURST else 7.32
	return lerpf(RUN_MIN, top, smoothstep(0.0, 0.75, stamina))

@export var training_situations := 0
@export var scores := PackedFloat32Array()


static func scenario(trigger: int, terrain: int, energy: int, closing: bool) -> int:
	return (((trigger * 5 + terrain) * 3 + energy) * 2 + int(closing))


static func terrain_at(at: Vector3, indoors: bool, sheltered: bool, shortcut: bool) -> int:
	if shortcut:
		return 4
	if at.y < -2.0:
		return 3
	if sheltered:
		return 2
	return int(indoors)


func ranked(state: int, rng: RandomNumberGenerator) -> Array[int]:
	var actions: Array[int] = [BURST, COVER, SHORTCUT, FEINT, DETOUR]
	if scores.size() != STATES * ACTIONS:
		return actions
	var ratings := PackedFloat32Array()
	for action: int in actions:
		ratings.append(scores[state * ACTIONS + action] + rng.randf_range(-0.14, 0.14))
	actions.sort_custom(func(a: int, b: int): return ratings[a] > ratings[b])
	return actions
