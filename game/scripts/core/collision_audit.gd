class_name CollisionAudit
extends Node
## Finds "invisible walls": casts a dense grid of rays at player height over the
## whole map and checks every physics hit against the voxel data and the chunk
## meshes. Runs on the intact map, then again after a round of explosions once
## the rebuild queue is empty. Run: -- --level=district --audit --quit

var main: Node
var quit_when_done := false
var _t := 0.0
var _stage := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 5
	var p: Player = main.player
	p.god_mode = true
	p.set_physics_process(false)
	p.tools.input_enabled = false
	p.global_position = Vector3(0, -40, 0)


func _process(delta: float) -> void:
	_t += delta
	var w := VoxelWorld.instance
	if _stage == 0 and _t > 2.0:
		_audit("intact")
		var half := _half()
		for k in 40:
			var p := Vector3(_rng.randf_range(-half, half), 2.0 + _rng.randf_range(0.5, 6.0), _rng.randf_range(-half, half))
			w.explode(p, _rng.randf_range(1.5, 2.6), 7.0)
		_stage = 1
		_t = 0.0
	elif _stage == 1 and _t > 8.0 and w.pending_rebuilds() == 0:
		_audit("after_blasts")
		_stage = 2
		if quit_when_done:
			get_tree().quit()


func _half() -> float:
	return DistrictLevel.HALF - 0.5 if GameState.level == GameState.LEVEL_DISTRICT else 39.5


const COARSE := ["tree", "reeds", "hedge", "flowers", "bush"]


func _audit(name: String) -> void:
	var w := VoxelWorld.instance
	var half := _half()
	var total := 0
	var coarse := 0
	var no_voxel := {}
	var no_mesh := {}
	var samples: Array[String] = []
	var gy := 2.0
	for axis in 2:
		var k := -half
		while k < half:
			for h in [gy + 0.35, gy + 1.0, gy + 1.7]:
				var a := Vector3(-half - 1, h, k) if axis == 0 else Vector3(k, h, -half - 1)
				var b := Vector3(half + 1, h, k) if axis == 0 else Vector3(k, h, half + 1)
				var ex: Array[RID] = []
				for n in 80:
					var hit := w.raycast(a, b, Layers.SOLID, ex)
					if hit.is_empty():
						break
					ex.append(hit.rid)
					var o := hit.collider as VoxelObject
					if o == null:
						continue
					total += 1
					var v := Vector3i((o.to_voxel(hit.position - hit.normal * 0.04)).floor())
					var solid := o.volume.get_voxel(v) != 0
					if not solid:
						# Accept a hit on the shared face of two voxels.
						for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
							if o.volume.get_voxel(v + d) != 0 and (o.to_global((Vector3(v + d) + Vector3(0.5, 0.5, 0.5)) * VoxelObject.VS)).distance_to(hit.position) < 0.1:
								solid = true
								break
					if not solid:
						if o.label in COARSE:
							coarse += 1
							continue
						no_voxel[o.label] = no_voxel.get(o.label, 0) + 1
						if samples.size() < 12:
							samples.append("%s %s at %s" % ["static" if o.static_mode else "dynamic", o.label, hit.position.snapped(Vector3.ONE * 0.1)])
						continue
					var key := Vector3i(v.x / o.chunk_size.x, v.y / o.chunk_size.y, v.z / o.chunk_size.z)
					var c = o._chunks.get(key)
					if c == null or c.mi == null or c.mi.mesh == null or not c.mi.is_visible_in_tree():
						no_mesh[o.label] = no_mesh.get(o.label, 0) + 1
						if samples.size() < 12:
							samples.append("no mesh: %s %s chunk %s at %s" % ["static" if o.static_mode else "dynamic", o.label, key, hit.position.snapped(Vector3.ONE * 0.1)])
			k += 1.5
	print("[audit] %s: %d hits, %d coarse foliage, no voxel %s, no mesh %s" % [name, total, coarse, no_voxel, no_mesh])
	for s in samples:
		print("[audit]   ", s)
