class_name VoxModel
## Small non-destructible voxel models (tool viewmodels, projectiles) meshed with
## the same native mesher and shader as the world, at a finer voxel size.

static var _materials := {}


static func material_for(vs: float) -> ShaderMaterial:
	var key := roundi(vs * 1000.0)
	if not _materials.has(key):
		var m := VoxMat.opaque_material.duplicate() as ShaderMaterial
		m.set_shader_parameter("voxel_size", vs)
		_materials[key] = m
	return _materials[key]


static func volume(size: Vector3i) -> VoxelVolume:
	var v := VoxelVolume.new()
	v.setup(size)
	v.set_palette(VoxMat.palette)
	return v


## Mesh with the origin moved to `pivot` (in voxels).
static func mesh(vol: VoxelVolume, vs: float, pivot: Vector3) -> ArrayMesh:
	var arrays: Array = vol.build_mesh(Vector3i.ZERO, vol.get_size(), vs)
	var m := ArrayMesh.new()
	var mat := material_for(vs)
	for k in 2:
		var a: Array = arrays[k]
		if a.is_empty():
			continue
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var off := pivot * vs
		for i in verts.size():
			verts[i] -= off
		a[Mesh.ARRAY_VERTEX] = verts
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.surface_set_material(m.get_surface_count() - 1, mat if k == 0 else VoxMat.glass_material)
	return m


static func instance(vol: VoxelVolume, vs: float, pivot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(vol, vs, pivot)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


## Half resolution copy (a 2x2x2 cell is solid when 3+ of its voxels are), for
## distant scenery meshed at twice the voxel size.
static func downsample(src: VoxelVolume) -> VoxelVolume:
	var s := src.get_size()
	var d := Vector3i((s.x + 1) / 2, (s.y + 1) / 2, (s.z + 1) / 2)
	var out := volume(d)
	for z in d.z:
		for y in d.y:
			for x in d.x:
				var n := 0
				var pick := 0
				for k in 8:
					var v := src.get_voxel(Vector3i(x * 2 + (k & 1), y * 2 + ((k >> 1) & 1), z * 2 + ((k >> 2) & 1)))
					if v != 0:
						n += 1
						pick = v
				if n >= 3:
					out.set_voxel(Vector3i(x, y, z), pick)
	return out
