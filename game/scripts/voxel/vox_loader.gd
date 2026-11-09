class_name VoxLoader
## MagicaVoxel .vox import for building maps in an external voxel editor.
## Materials come from palette index ranges, Teardown-style, so a level artist
## picks the material by painting with the right palette row:
##   1-8 glass, 9-24 foliage, 25-40 dirt, 41-56 rock, 57-72 wood, 73-88 brick,
##   89-104 plaster, 105-120 metal, 121-136 hard metal, 137-152 plastic,
##   153-168 concrete, 169-176 light (emissive), 177-184 unbreakable, rest concrete.
## Scene graph translations (nTRN/nGRP/nSHP) are applied; rotations are ignored.
## MagicaVoxel is Z-up: vox (x, y, z) maps to (x, z, -y) here.


static func material_for_index(i: int) -> int:
	if i <= 8: return VoxMat.GLASS
	if i <= 24: return VoxMat.FOLIAGE
	if i <= 40: return VoxMat.DIRT
	if i <= 56: return VoxMat.ROCK
	if i <= 72: return VoxMat.WOOD
	if i <= 88: return VoxMat.BRICK
	if i <= 104: return VoxMat.PLASTER
	if i <= 120: return VoxMat.METAL
	if i <= 136: return VoxMat.HARDMETAL
	if i <= 152: return VoxMat.PLASTIC
	if i <= 168: return VoxMat.CONCRETE
	if i <= 176: return VoxMat.EMISSIVE
	if i <= 184: return VoxMat.UNBREAKABLE
	return VoxMat.CONCRETE


## Returns [{volume: VoxelVolume, offset: Vector3i (voxels, scene space), name: String}].
static func load_models(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("VoxLoader: cannot open %s" % path)
		return []
	if f.get_buffer(4).get_string_from_ascii() != "VOX ":
		push_error("VoxLoader: %s is not a .vox file" % path)
		return []
	f.get_32()  # version
	var sizes: Array[Vector3i] = []
	var voxels: Array[PackedByteArray] = []
	var colors := PackedColorArray()
	colors.resize(256)
	for i in 256:
		colors[i] = Color(0.6, 0.6, 0.6)
	var transforms := {}   # node id -> [translation Vector3i, child id, name]
	var groups := {}       # node id -> child ids
	var shapes := {}       # node id -> model ids
	while f.get_position() < f.get_length():
		var id := f.get_buffer(4).get_string_from_ascii()
		var content := f.get_32()
		var children := f.get_32()
		var start := f.get_position()
		match id:
			"MAIN":
				continue  # children follow directly
			"SIZE":
				sizes.append(Vector3i(f.get_32(), f.get_32(), f.get_32()))
			"XYZI":
				var n := f.get_32()
				voxels.append(f.get_buffer(n * 4))
			"RGBA":
				for i in 256:
					var c := f.get_buffer(4)
					# Palette entry i+1 is stored at position i.
					if i < 255:
						colors[i + 1] = Color8(c[0], c[1], c[2], c[3])
			"nTRN":
				var node := f.get_32()
				var attrs := _read_dict(f)
				var child := f.get_32()
				f.get_32()  # reserved
				f.get_32()  # layer
				var frames := f.get_32()
				var t := Vector3i.ZERO
				for k in frames:
					var fd := _read_dict(f)
					if k == 0 and fd.has("_t"):
						var p: PackedStringArray = (fd["_t"] as String).split(" ")
						t = Vector3i(int(p[0]), int(p[1]), int(p[2]))
				transforms[node] = [t, child, attrs.get("_name", "")]
			"nGRP":
				var node := f.get_32()
				_read_dict(f)
				var n := f.get_32()
				var kids := []
				for k in n:
					kids.append(f.get_32())
				groups[node] = kids
			"nSHP":
				var node := f.get_32()
				_read_dict(f)
				var n := f.get_32()
				var models := []
				for k in n:
					models.append(f.get_32())
					_read_dict(f)
				shapes[node] = models
		f.seek(start + content + (0 if id == "MAIN" else children))

	var placed := []  # [model id, translation, name]
	if transforms.has(0):
		_walk(0, Vector3i.ZERO, "", transforms, groups, shapes, placed)
	else:
		for m in sizes.size():
			placed.append([m, Vector3i.ZERO, "model_%d" % m])

	var out := []
	for item in placed:
		var m: int = item[0]
		if m >= sizes.size():
			continue
		var s := sizes[m]
		var vol := VoxelVolume.new()
		vol.setup(Vector3i(s.x, s.z, s.y))
		vol.set_palette(VoxMat.palette)
		var remap := {}
		var data := voxels[m]
		for i in range(0, data.size(), 4):
			var ci := data[i + 3]
			if not remap.has(ci):
				remap[ci] = VoxMat.entry_for(colors[ci], material_for_index(ci))
			vol.set_voxel(Vector3i(data[i], data[i + 2], s.y - 1 - data[i + 1]), remap[ci])
		# Translations point at the model center in MagicaVoxel.
		var t: Vector3i = item[1]
		var center := Vector3i(t.x, t.z, -t.y)
		var offset := center - Vector3i(s.x / 2, s.z / 2, s.y / 2)
		out.append({"volume": vol, "offset": offset, "name": item[2]})
	return out


static func _walk(node: int, t: Vector3i, name: String, transforms: Dictionary, groups: Dictionary, shapes: Dictionary, out: Array) -> void:
	if transforms.has(node):
		var tr: Array = transforms[node]
		var n: String = tr[2] if tr[2] != "" else name
		_walk(tr[1], t + tr[0], n, transforms, groups, shapes, out)
	elif groups.has(node):
		for c in groups[node]:
			_walk(c, t, name, transforms, groups, shapes, out)
	elif shapes.has(node):
		for m in shapes[node]:
			out.append([m, t, name])


static func _read_dict(f: FileAccess) -> Dictionary:
	var d := {}
	var n := f.get_32()
	for i in n:
		var k := f.get_buffer(f.get_32()).get_string_from_utf8()
		var v := f.get_buffer(f.get_32()).get_string_from_utf8()
		d[k] = v
	return d


## Loads a .vox scene and spawns one VoxelObject per model. Objects whose name
## starts with "dyn" become dynamic bodies, everything else is anchored static.
static func spawn(parent: Node, path: String, origin: Vector3) -> Array[VoxelObject]:
	var objs: Array[VoxelObject] = []
	for m in load_models(path):
		var vol: VoxelVolume = m.volume
		var dynamic: bool = (m.name as String).begins_with("dyn")
		var o := VoxelObject.new()
		o.setup(vol, not dynamic)
		o.label = m.name
		o.position = origin + Vector3(m.offset) * VoxelObject.VS
		parent.add_child(o)
		objs.append(o)
	return objs
