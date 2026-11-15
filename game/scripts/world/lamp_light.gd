class_name LampLight
extends OmniLight3D
## The power switch controls visibility. The emissive voxel controls output.

var obj: VoxelObject
var voxel := Vector3i.ZERO
var follow_offset := Vector3.INF
var _t := 0.0
var _rated_energy := 0.0


func _ready() -> void:
	_rated_energy = light_energy
	_update_output()


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.16:
		return
	_t = 0.0
	_update_output()


func _update_output() -> void:
	var intact := is_instance_valid(obj) and VoxMat.material_of(obj.volume.get_voxel(voxel)) == VoxMat.EMISSIVE
	var output := _rated_energy if intact else 0.0
	if not is_equal_approx(light_energy, output):
		light_energy = output
	if intact and follow_offset.is_finite():
		global_position = obj.to_global(follow_offset)
