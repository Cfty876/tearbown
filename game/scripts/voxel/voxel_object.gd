class_name VoxelObject
extends RigidBody3D
## A destructible voxel body. Static objects are frozen and anchored at their bottom
## layer (collision lives in one server-side static body per chunk, so an edit only
## rebuilds the touched chunks). Dynamic objects carry all chunk boxes as one compound.
## Object space: voxel (0,0,0) corner at the origin, VS meters per voxel.

const VS := 0.1
const IMPACT_MIN_DV := 2.6        # m/s velocity change that counts as a crash
const IMPACT_COOLDOWN_MS := 180
const SPAWN_GRACE_MS := 500

var volume: VoxelVolume
var network_id := 0
var static_mode := false
var chunk_size := Vector3i(32, 32, 32)
var label := ""
## Explosive props (propane tanks, barrels): radius in meters, 0 = inert.
var explosive_radius := 0.0
var explosive_power := 6.0
var exploded := false
var held := false
## Occlusion culling box for big buildings; dropped once the building is damaged
## so holes never hide what is behind them.
var occluder: Node3D
var spawn_ms := 0

var _chunks := {}           # Vector3i -> Chunk
var _dirty := {}            # Vector3i -> true
var _shapes_dirty := false
var _last_impact_ms := 0
var _damage := 0
var _grid := Vector3i.ONE

static var _shape_cache := {}  # Vector3i (box size in half-voxels) -> shape RID
static var prof := {"mesh_usec": 0, "phys_usec": 0, "boxes": 0, "chunks": 0}


class Chunk:
	var mi: MeshInstance3D
	var body := RID()
	var boxes := PackedFloat32Array()


func setup(vol: VoxelVolume, is_static: bool, csize := Vector3i(32, 32, 32)) -> VoxelObject:
	volume = vol
	static_mode = is_static
	chunk_size = csize
	volume.set_palette(VoxMat.palette)
	volume.set_anchor_bottom(is_static)
	return self


func _ready() -> void:
	spawn_ms = Time.get_ticks_msec()
	if static_mode:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		collision_layer = Layers.STATIC
		collision_mask = 0
	else:
		collision_layer = Layers.DYNAMIC
		collision_mask = Layers.STATIC | Layers.DYNAMIC | Layers.DEBRIS | Layers.PLAYER
		contact_monitor = true
		max_contacts_reported = 4
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		var pm := PhysicsMaterial.new()
		pm.friction = 0.8
		pm.bounce = 0.05
		physics_material_override = pm
		angular_damp = 0.15
		linear_damp = 0.02
	_grid = Vector3i(
		ceili(float(volume.get_size().x) / chunk_size.x),
		ceili(float(volume.get_size().y) / chunk_size.y),
		ceili(float(volume.get_size().z) / chunk_size.z))
	VoxelWorld.instance.register(self)
	rebuild_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for c: Chunk in _chunks.values():
			if c.body.is_valid():
				PhysicsServer3D.free_rid(c.body)


func _exit_tree() -> void:
	if VoxelWorld.instance:
		VoxelWorld.instance.unregister(self)


# ------------------------------------------------------------------ building

func rebuild_all() -> void:
	for z in _grid.z:
		for y in _grid.y:
			for x in _grid.x:
				_rebuild_chunk(Vector3i(x, y, z))
	_dirty.clear()
	_finish_rebuild()


func has_dirty() -> bool:
	return not _dirty.is_empty()


## Rebuilds one pending chunk; returns false when nothing is left.
func rebuild_next() -> bool:
	if _dirty.is_empty():
		return false
	var key: Vector3i = _dirty.keys()[0]
	var collision: bool = _dirty[key]
	_dirty.erase(key)
	_rebuild_chunk(key, collision)
	if _dirty.is_empty():
		_finish_rebuild()
	return true


## mesh_only: colors changed (paint, scorch), collision stays as it is.
func mark_dirty(vmin: Vector3i, vmax: Vector3i, mesh_only := false) -> void:
	var a := (vmin - Vector3i.ONE).max(Vector3i.ZERO) / chunk_size
	var b := ((vmax + Vector3i.ONE) / chunk_size).min(_grid - Vector3i.ONE)
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				var k := Vector3i(x, y, z)
				_dirty[k] = _dirty.get(k, false) or not mesh_only
	VoxelWorld.instance.queue_rebuild(self)


func _rebuild_chunk(key: Vector3i, collision := true) -> void:
	var t0 := Time.get_ticks_usec()
	_rebuild_chunk_inner(key, collision)
	prof.chunks += 1
	prof.mesh_usec += Time.get_ticks_usec() - t0


func _rebuild_chunk_inner(key: Vector3i, collision: bool) -> void:
	var cmin := key * chunk_size
	var arrays: Array = volume.build_mesh(cmin, chunk_size, VS)
	var opaque: Array = arrays[0]
	var glass: Array = arrays[1]
	var c: Chunk = _chunks.get(key)
	if opaque.is_empty() and glass.is_empty():
		if c != null:
			if c.mi:
				c.mi.queue_free()
			if c.body.is_valid():
				PhysicsServer3D.free_rid(c.body)
			_chunks.erase(key)
			_shapes_dirty = true
		return
	if c == null:
		c = Chunk.new()
		_chunks[key] = c
	var mesh := ArrayMesh.new()
	if not opaque.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, opaque)
		mesh.surface_set_material(mesh.get_surface_count() - 1, VoxMat.opaque_material)
	if not glass.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass)
		mesh.surface_set_material(mesh.get_surface_count() - 1, VoxMat.glass_material)
	if c.mi == null:
		c.mi = MeshInstance3D.new()
		c.mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not static_mode and volume.get_solid_count() < 400:
			c.mi.visibility_range_end = 140.0
		add_child(c.mi)
	c.mi.mesh = mesh
	if not collision and c.boxes.size() > 0:
		return

	var t0 := Time.get_ticks_usec()
	c.boxes = volume.build_boxes(cmin, chunk_size, VS)
	prof.boxes += c.boxes.size() / 6
	if static_mode:
		_rebuild_static_body(c)
	else:
		_shapes_dirty = true
	prof.phys_usec += Time.get_ticks_usec() - t0


func _rebuild_static_body(c: Chunk) -> void:
	if not c.body.is_valid():
		c.body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(c.body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(c.body, Layers.STATIC)
		PhysicsServer3D.body_set_collision_mask(c.body, 0)
		PhysicsServer3D.body_attach_object_instance_id(c.body, get_instance_id())
		PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
	# Jolt rebuilds a body's compound shape on every add while the body is in a
	# space (quadratic: 2000 boxes take ~300 ms), so shapes go in while detached.
	PhysicsServer3D.body_set_space(c.body, RID())
	PhysicsServer3D.body_clear_shapes(c.body)
	_add_boxes(c.body, c.boxes)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	PhysicsServer3D.body_set_space(c.body, get_world_3d().space)


func _add_boxes(body: RID, b: PackedFloat32Array) -> void:
	for i in range(0, b.size(), 6):
		PhysicsServer3D.body_add_shape(body, _box_shape(b[i + 3], b[i + 4], b[i + 5]),
			Transform3D(Basis.IDENTITY, Vector3(b[i], b[i + 1], b[i + 2])))


func _finish_rebuild() -> void:
	if volume.get_solid_count() == 0:
		queue_free()
		return
	if static_mode or not _shapes_dirty:
		return
	_shapes_dirty = false
	# Same detach trick as static chunks; motion state is carried over by hand.
	var rid := get_rid()
	var xf := global_transform
	var lv := linear_velocity
	var av := angular_velocity
	var space := get_world_3d().space
	PhysicsServer3D.body_set_space(rid, RID())
	PhysicsServer3D.body_clear_shapes(rid)
	for c: Chunk in _chunks.values():
		_add_boxes(rid, c.boxes)
	PhysicsServer3D.body_set_space(rid, space)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lv)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, av)
	# Re-adding to the space may leave the body asleep; a fresh piece must fall.
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	update_mass()


func update_mass() -> void:
	var m: Dictionary = volume.compute_mass(VS)
	mass = maxf(m.mass, 0.2)
	center_of_mass = m.com


static func _box_shape(hx: float, hy: float, hz: float) -> RID:
	var key := Vector3i(roundi(hx * 2.0 / VS), roundi(hy * 2.0 / VS), roundi(hz * 2.0 / VS))
	var s: RID = _shape_cache.get(key, RID())
	if not s.is_valid():
		s = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(s, Vector3(hx, hy, hz))
		_shape_cache[key] = s
	return s


# ------------------------------------------------------------------ queries

func to_voxel(world_pos: Vector3) -> Vector3:
	return to_local(world_pos) / VS


func voxel_to_world(v: Vector3) -> Vector3:
	return to_global(v * VS)


## Palette index of the voxel just inside the surface hit by a ray.
func voxel_at_hit(pos: Vector3, normal: Vector3) -> int:
	var v := to_voxel(pos - normal * (VS * 0.4))
	return volume.get_voxel(Vector3i(floori(v.x), floori(v.y), floori(v.z)))


func world_center() -> Vector3:
	if static_mode:
		return to_global(Vector3(volume.get_size()) * VS * 0.5)
	return to_global(center_of_mass)


func voxel_count() -> int:
	return volume.get_solid_count()


# ------------------------------------------------------------------ destruction

## Carves a sphere (world units). Returns the native result with debris samples.
func carve(world_pos: Vector3, radius: float, power: float, jitter := 0.3, debris_chance := 0.05, max_debris := 24) -> Dictionary:
	var res: Dictionary = volume.carve_sphere(to_voxel(world_pos), radius / VS, power, jitter, debris_chance, max_debris, randi())
	var n: int = res.count
	if n > 0:
		_damage += n
		if occluder and _damage > 120:
			occluder.queue_free()
			occluder = null
		after_edit(res.min, res.max)
		if explosive_radius > 0.0 and _damage >= 3:
			VoxelWorld.instance.trigger_explosive(self, randf_range(0.08, 0.25))
	return res


func paint(world_pos: Vector3, radius: float, remap: PackedByteArray, chance: float) -> int:
	var res: Dictionary = volume.paint_sphere(to_voxel(world_pos), radius / VS, remap, chance, randi())
	var n: int = res.count
	if n > 0:
		mark_dirty(res.min, res.max, true)
	return n


## Re-meshes the edited region and releases pieces that lost their support.
func after_edit(vmin: Vector3i, vmax: Vector3i) -> void:
	mark_dirty(vmin, vmax)
	var islands: Array = volume.split_islands(vmin, vmax)
	for island: Dictionary in islands:
		var off: Vector3i = island.offset
		var isz: Vector3i = (island.volume as VoxelVolume).get_size()
		mark_dirty(off, off + isz)
		VoxelWorld.instance.spawn_island(self, island)


# ------------------------------------------------------------------ crash damage

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var n := state.get_contact_count()
	if n == 0 or held:
		return
	var now := Time.get_ticks_msec()
	var cooldown := IMPACT_COOLDOWN_MS if mass < 20000.0 else 70
	if now - _last_impact_ms < cooldown or now - spawn_ms < SPAWN_GRACE_MS:
		return
	var best := -1
	var best_j := 0.0
	var speed := state.linear_velocity.length()
	for i in n:
		if speed > 4.5 and mass > 25.0:
			var col := state.get_contact_collider_object(i)
			if col is Player:
				# Heavy fast pieces hurt (falling walls, cars).
				(col as Player).damage.call_deferred(clampf((speed - 4.5) * mass / 35.0, 0.0, 120.0))
				_last_impact_ms = now
				return
		var j := state.get_contact_impulse(i).length()
		if j > best_j:
			best_j = j
			best = i
	if best < 0:
		return
	var dv := best_j / mass
	if dv < IMPACT_MIN_DV or best_j < 25.0:
		return
	_last_impact_ms = now
	VoxelWorld.instance.queue_impact(self, state.get_contact_collider_object(best),
		state.get_contact_collider_position(best), best_j, dv)


## Adds a box occluder for the solid interior of a building (object space AABB).
func add_occluder(box: AABB) -> void:
	var oi := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = box.size
	oi.occluder = bo
	oi.position = box.get_center()
	add_child(oi)
	occluder = oi


## Carves many spheres at once and runs the support check a single time
## (controlled demolitions). Returns the number of removed voxels.
func carve_batch(points: Array[Vector3], radius: float, power: float) -> int:
	var total := 0
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var mx := Vector3i(-1, -1, -1)
	for p in points:
		var res: Dictionary = volume.carve_sphere(to_voxel(p), radius / VS, power, 0.25, 0.0, 0, randi())
		if res.count > 0:
			total += res.count
			mn = mn.min(res.min)
			mx = mx.max(res.max)
	if total > 0:
		_damage += total
		if occluder:
			occluder.queue_free()
			occluder = null
		after_edit(mn, mx)
	return total
