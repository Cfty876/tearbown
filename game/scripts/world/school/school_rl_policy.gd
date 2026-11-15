class_name SchoolRlPolicy
extends Resource

const PATH := "res://scripts/world/school/school_rl_policy.tres"
const INPUTS := 14
const HIDDEN := 16
const ACTIONS := 5

@export var training_steps := 0
@export var episode_count := 0
@export var input_layer := PackedFloat32Array()
@export var hidden_layer := PackedFloat32Array()
@export var output_layer := PackedFloat32Array()


static func observe(trigger: int, terrain: int, stamina: float, closing: bool, gap: float, can_feint: bool) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(INPUTS)
	values[trigger] = 1.0
	values[5 + terrain] = 1.0
	values[10] = clampf(stamina, 0.0, 1.0)
	values[11] = float(closing)
	values[12] = clampf(gap / 22.0, 0.0, 1.0)
	values[13] = float(can_feint)
	return values


func valid() -> bool:
	return training_steps > 0 and input_layer.size() == HIDDEN * (INPUTS + 1) \
		and hidden_layer.size() == HIDDEN * (HIDDEN + 1) and output_layer.size() == ACTIONS * (HIDDEN + 1)


func logits(observation: PackedFloat32Array) -> PackedFloat32Array:
	var first := _dense(observation, input_layer, HIDDEN, true)
	var second := _dense(first, hidden_layer, HIDDEN, true)
	return _dense(second, output_layer, ACTIONS, false)


func sample(observation: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var scores := logits(observation)
	var best := -INF
	var selected := 0
	for i in ACTIONS:
		# Sample tactics without making a repeat encounter deterministic.
		var value := scores[i] - log(-log(clampf(rng.randf(), 0.00001, 0.99999)))
		if value > best:
			best = value
			selected = i
	return selected


func _dense(input: PackedFloat32Array, weights: PackedFloat32Array, count: int, activate: bool) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(count)
	var columns := input.size() + 1
	for row in count:
		var offset := row * columns
		var result := weights[offset + columns - 1]
		for i in input.size():
			result += input[i] * weights[offset + i]
		output[row] = tanh(result) if activate else result
	return output
