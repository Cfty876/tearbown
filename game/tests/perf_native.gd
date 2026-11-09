extends SceneTree
## Headless micro-benchmark of the native voxel core.
## Run: godot --headless --path game --script res://tests/perf_native.gd


func _t(label: String, fn: Callable, reps := 10) -> float:
	var t0 := Time.get_ticks_usec()
	for i in reps:
		fn.call()
	var us := float(Time.get_ticks_usec() - t0) / reps
	print("%-38s %8.3f ms" % [label, us / 1000.0])
	return us


func _init() -> void:
	VoxMat.setup()
	var house := Build.brick_house(1)
	var tree := Build.pine_tree(5, 85)
	var terrain := Build.vol(Vector3i(64, 32, 64))
	terrain.fill_box_noise(Vector3i(0, 0, 0), Vector3i(64, 20, 64), VoxMat.ids("dirt"), 1)
	terrain.fill_box_noise(Vector3i(0, 19, 0), Vector3i(64, 20, 64), VoxMat.ids("grass"), 2)
	print("house voxels %d, tree voxels %d" % [house.get_solid_count(), tree.get_solid_count()])

	_t("mesh house chunk 32^3", func(): house.build_mesh(Vector3i(0, 0, 0), Vector3i(32, 32, 32), 0.1))
	_t("boxes house chunk 32^3", func(): house.build_boxes(Vector3i(0, 0, 0), Vector3i(32, 32, 32), 0.1))
	_t("mesh terrain chunk 64x32x64", func(): terrain.build_mesh(Vector3i.ZERO, Vector3i(64, 32, 64), 0.1))
	_t("boxes terrain chunk 64x32x64", func(): terrain.build_boxes(Vector3i.ZERO, Vector3i(64, 32, 64), 0.1))
	_t("mesh tree chunk 32^3 (foliage)", func(): tree.build_mesh(Vector3i(0, 32, 0), Vector3i(32, 32, 32), 0.1))
	var nb := tree.build_boxes(Vector3i(0, 32, 0), Vector3i(32, 32, 32), 0.1).size() / 6
	_t("boxes tree chunk 32^3 (%d boxes)" % nb, func(): tree.build_boxes(Vector3i(0, 32, 0), Vector3i(32, 32, 32), 0.1))
	var total := 0
	for z in 2:
		for y in 3:
			for x in 2:
				total += tree.build_boxes(Vector3i(x, y, z) * 32, Vector3i(32, 32, 32), 0.1).size() / 6
	print("tree total boxes: %d" % total)

	var arrays: Array = house.build_mesh(Vector3i(0, 0, 0), Vector3i(32, 32, 32), 0.1)
	_t("ArrayMesh from arrays", func():
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[0]))

	var h2 := Build.brick_house(1)
	_t("carve r=17 (bomb)", func(): h2.carve_sphere(Vector3(60, 20, 3), 17.0, 6.0, 0.4, 0.07, 36, 1), 1)
	_t("split_islands after carve", func(): h2.split_islands(Vector3i(40, 0, 0), Vector3i(80, 40, 20)), 1)
	var h3 := Build.brick_house(1)
	# Cut the whole ground floor ring to drop the upper storey.
	h3.fill_box(Vector3i(0, 20, 0), Vector3i(126, 24, 96), 0)
	var box := [[]]
	_t("split_islands big detach", func(): box[0] = h3.split_islands(Vector3i(0, 20, 0), Vector3i(125, 23, 95)), 1)
	var res: Array = box[0]
	print("  islands: %d, first count %d" % [res.size(), res[0].count if res.size() > 0 else 0])
	_t("compute_mass house", func(): house.compute_mass(0.1))
	quit()
