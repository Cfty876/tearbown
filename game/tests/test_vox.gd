extends SceneTree
## Writes a small MagicaVoxel file (2 models in a scene graph) and loads it back.
## Run: godot --headless --path game --script res://tests/test_vox.gd


func _i32(b: PackedByteArray, v: int) -> void:
	var o := b.size()
	b.resize(o + 4)
	b.encode_s32(o, v)


func _str(b: PackedByteArray, s: String) -> void:
	var u := s.to_utf8_buffer()
	_i32(b, u.size())
	b.append_array(u)


func _dict(b: PackedByteArray, d: Dictionary) -> void:
	_i32(b, d.size())
	for k in d:
		_str(b, k)
		_str(b, d[k])


func _chunk(id: String, content: PackedByteArray, children := PackedByteArray()) -> PackedByteArray:
	var b := id.to_ascii_buffer()
	_i32(b, content.size())
	_i32(b, children.size())
	b.append_array(content)
	b.append_array(children)
	return b


func _init() -> void:
	VoxMat.setup()
	var kids := PackedByteArray()
	# model 0: 4x3x2 wood block (palette index 60), model 1: 2x2x5 glass column (index 3)
	for m in [[Vector3i(4, 3, 2), 60], [Vector3i(2, 2, 5), 3]]:
		var s: Vector3i = m[0]
		var c := PackedByteArray()
		_i32(c, s.x); _i32(c, s.y); _i32(c, s.z)
		kids.append_array(_chunk("SIZE", c))
		var xyzi := PackedByteArray()
		_i32(xyzi, s.x * s.y * s.z)
		for z in s.z:
			for y in s.y:
				for x in s.x:
					xyzi.append_array(PackedByteArray([x, y, z, m[1]]))
		kids.append_array(_chunk("XYZI", xyzi))
	# scene graph: T0 -> G1 -> (T2 -> S3 model 0), (T4 -> S5 model 1)
	var t := PackedByteArray()
	_i32(t, 0); _dict(t, {}); _i32(t, 1); _i32(t, -1); _i32(t, 0); _i32(t, 1); _dict(t, {})
	kids.append_array(_chunk("nTRN", t))
	var g := PackedByteArray()
	_i32(g, 1); _dict(g, {}); _i32(g, 2); _i32(g, 2); _i32(g, 4)
	kids.append_array(_chunk("nGRP", g))
	for n in [[2, 3, 0, "10 0 1", "wall"], [4, 5, 1, "-6 4 2", "dyn_column"]]:
		var tr := PackedByteArray()
		_i32(tr, n[0]); _dict(tr, {"_name": n[4]}); _i32(tr, n[1]); _i32(tr, -1); _i32(tr, 0); _i32(tr, 1); _dict(tr, {"_t": n[3]})
		kids.append_array(_chunk("nTRN", tr))
		var sh := PackedByteArray()
		_i32(sh, n[1]); _dict(sh, {}); _i32(sh, 1); _i32(sh, n[2]); _dict(sh, {})
		kids.append_array(_chunk("nSHP", sh))
	var rgba := PackedByteArray()
	for i in 256:
		rgba.append_array(PackedByteArray([i, 128, 255 - i, 255]))
	kids.append_array(_chunk("RGBA", rgba))
	var file := "VOX ".to_ascii_buffer()
	_i32(file, 150)
	file.append_array(_chunk("MAIN", PackedByteArray(), kids))
	var path := "user://test_scene.vox"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(file)
	f.close()

	var models := VoxLoader.load_models(path)
	var ok := models.size() == 2
	for m in models:
		var v: VoxelVolume = m.volume
		var mat := VoxMat.material_of(v.get_voxel(Vector3i.ZERO))
		print("model '%s' size %s offset %s voxels %d material %s" % [m.name, v.get_size(), m.offset, v.get_solid_count(), VoxMat.NAMES.get(mat, mat)])
	if ok:
		ok = models[0].name == "wall" and (models[0].volume as VoxelVolume).get_size() == Vector3i(4, 2, 3)
		ok = ok and VoxMat.material_of((models[0].volume as VoxelVolume).get_voxel(Vector3i.ZERO)) == VoxMat.WOOD
		ok = ok and VoxMat.material_of((models[1].volume as VoxelVolume).get_voxel(Vector3i.ZERO)) == VoxMat.GLASS
		ok = ok and models[0].offset == Vector3i(10 - 2, 1 - 1, 0 - 1)
	print("VOX TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
