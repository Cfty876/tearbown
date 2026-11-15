class_name SchoolBrain
extends Resource
## Общий скрытый слой. Три выхода отвечают за план, маршрут и предмет.

const PATH := "res://scripts/world/school/school_brain.tres"
const INPUTS := 24
const HIDDEN := 32
const OUTPUTS := 14
const PLAN := 0
const ROUTE := 4
const TOOL := 9
enum { ROAM, LOCKER, DISTRACT, ESCAPE }

@export var rounds := 0
@export var scenarios := 0
@export var replay_rounds := 0
@export var replay_windows := 0
@export var input_layer := PackedFloat32Array()
@export var output_layer := PackedFloat32Array()


func valid() -> bool:
	return input_layer.size() == HIDDEN * (INPUTS + 1) and output_layer.size() == OUTPUTS * (HIDDEN + 1)


func predict(observation: PackedFloat32Array) -> PackedFloat32Array:
	var hidden := _dense(observation, input_layer, HIDDEN)
	for i in hidden.size():
		hidden[i] = tanh(hidden[i])
	return _dense(hidden, output_layer, OUTPUTS)


func _dense(observation: PackedFloat32Array, weights: PackedFloat32Array, size: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var stride := observation.size() + 1
	result.resize(size)
	for i in size:
		var offset := i * stride
		var total := weights[offset + stride - 1]
		for j in observation.size():
			total += observation[j] * weights[offset + j]
		result[i] = total
	return result


static func rank(logits: PackedFloat32Array, start: int, count: int, rng: RandomNumberGenerator) -> Array[int]:
	var order: Array[int] = []
	var scores := PackedFloat32Array()
	for i in count:
		order.append(i)
		scores.append(logits[start + i] + rng.randf_range(-0.32, 0.32))
	order.sort_custom(func(a: int, b: int): return scores[a] > scores[b])
	return order
