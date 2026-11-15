class_name SchoolHidePolicy
extends Resource

enum { WAIT, MOVE, DECOY }
const ACTIONS := 3
const STATES := 72
const PATH := "res://scripts/world/school/school_hide_policy.tres"

@export var training_rounds := 0
@export var values := PackedFloat32Array()


static func situation(danger: int, cover: int, fresh_clue: bool, stationary: bool, late: bool) -> int:
	return ((((danger * 3 + cover) * 2 + int(fresh_clue)) * 2 + int(stationary)) * 2 + int(late))


static func baseline(state: int, rng: RandomNumberGenerator) -> int:
	var danger := state / 24
	var cover := state / 8 % 3
	var fresh := state / 4 % 2 == 1
	if danger >= 1:
		return MOVE
	if fresh or cover == 0:
		return MOVE if rng.randf() < 0.77 else DECOY
	return WAIT if rng.randf() < 0.67 else MOVE


func choose(state: int, rng: RandomNumberGenerator, exploration: float, allow_decoy := true, allow_wait := true) -> int:
	var actions: Array[int] = [MOVE]
	if allow_wait:
		actions.append(WAIT)
	if allow_decoy:
		actions.append(DECOY)
	if values.size() != STATES * ACTIONS:
		var fallback := baseline(state, rng)
		return fallback if fallback in actions else MOVE
	if rng.randf() < exploration:
		return actions[rng.randi_range(0, actions.size() - 1)]
	var best := -INF
	var chosen := MOVE
	for action: int in actions:
		var draw := clampf(rng.randf(), 0.0001, 0.9999)
		var score := float(values[state * ACTIONS + action]) - log(-log(draw))
		if score > best:
			best = score
			chosen = action
	return chosen
