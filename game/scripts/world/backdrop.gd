class_name Backdrop
## Scenery beyond the playable area: an endless voxel-shaded ground plane and a
## ring of instanced pine trees. Sectors let the renderer cull out-of-view trees.
## Trees use coarse 25 cm voxels (a quarter of the triangles of map trees) and
## only the inner ring casts shadows.

const TREE_VS := 0.25
const SECTOR_COUNT := 12


static func build(parent: Node3D, ground_y: float, map_half: float, inner_radius: float, seed: int) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/far_ground.gdshader")
	var ground := MeshInstance3D.new()
	ground.mesh = _ground_ring(map_half, 800.0, mat)
	ground.position = Vector3(0, ground_y - 0.005, 0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(ground)
	if OS.has_feature("web"):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var meshes: Array[Mesh] = []
	for k in 3:
		var r := 6 + k
		meshes.append(VoxModel.mesh(Build.pine_tree(seed + k * 31, 30 + k * 5, r, 0.9), TREE_VS, Vector3(r + 2, 0, r + 2)))
	# Leafy trees and maples at half resolution (20 cm voxels) for variety.
	meshes.append(VoxModel.mesh(VoxModel.downsample(DistrictProps.linden(seed + 5)), 0.2, Vector3(14, 0, 14)))
	meshes.append(VoxModel.mesh(VoxModel.downsample(DistrictProps.maple(seed + 6)), 0.2, Vector3(14, 0, 14)))
	_ring(parent, meshes, rng, ground_y, inner_radius, inner_radius + 30.0, 110, true)
	_ring(parent, meshes, rng, ground_y, inner_radius + 30.0, inner_radius + 140.0, 130, false)


## Flat ground around the map with a square hole over the destructible terrain;
## a full plane would show through craters as grass without collision.
static func _ground_ring(inner: float, outer: float, mat: Material) -> ArrayMesh:
	var strips := [
		Rect2(-outer, -outer, outer * 2.0, outer - inner),
		Rect2(-outer, inner, outer * 2.0, outer - inner),
		Rect2(-outer, -inner, outer - inner, inner * 2.0),
		Rect2(inner, -inner, outer - inner, inner * 2.0),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r: Rect2 in strips:
		var a := Vector3(r.position.x, 0, r.position.y)
		var b := Vector3(r.end.x, 0, r.position.y)
		var c := Vector3(r.end.x, 0, r.end.y)
		var d := Vector3(r.position.x, 0, r.end.y)
		for p in [a, b, c, a, c, d]:
			st.add_vertex(p)
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


static func _ring(parent: Node3D, meshes: Array[Mesh], rng: RandomNumberGenerator, ground_y: float, r0: float, r1: float, per_mesh: int, shadows: bool) -> void:
	for mesh in meshes:
		var sectors: Array[Array] = []
		for i in SECTOR_COUNT:
			sectors.append([])
		for i in per_mesh:
			var p := Vector3.ZERO
			while true:
				var a := rng.randf() * TAU
				var r := lerpf(r0, r1, pow(rng.randf(), 1.3))
				p = Vector3(cos(a) * r, ground_y - 0.15, sin(a) * r)
				# Keep the square map itself clear.
				if maxf(absf(p.x), absf(p.z)) > r0 - 2.0:
					break
			var s := rng.randf_range(0.8, 1.3)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
			var sector := posmod(floori(atan2(p.z, p.x) * SECTOR_COUNT / TAU), SECTOR_COUNT)
			sectors[sector].append(Transform3D(b, p))
		for transforms in sectors:
			if transforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = transforms.size()
			for i in transforms.size():
				mm.set_instance_transform(i, transforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
