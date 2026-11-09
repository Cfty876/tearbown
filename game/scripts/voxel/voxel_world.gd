class_name VoxelWorld
extends Node3D
## Owns every VoxelObject and runs the destruction pipeline:
## carve -> island split -> new bodies -> debris/fx, plus a time-budgeted remesh queue.

const VS := VoxelObject.VS
const REBUILD_BUDGET_USEC := 7000
const MIN_ISLAND_VOXELS := 6      # smaller pieces turn into debris cubes
const MAX_DYNAMIC_OBJECTS := 450

static var instance: VoxelWorld

## Voxels were removed or a body was released around `pos` (bots' nav grid listens).
signal geometry_changed(pos: Vector3, radius: float)
signal network_blast(pos: Vector3, radius: float)

var objects: Array[VoxelObject] = []
var debris: DebrisSystem
var fx: Fx
var sfx: Sfx
var fire: FireSystem
var player: Player
var network_role := 0 # 0 solo, 1 host, 2 replica
var network_objects := {}
var network_dirty := {}
var network_removed: Array[int] = []
var limit_distant_physics := false
var _prop_timer := 0.0
var _next_network_id := 1

var _rebuild_queue := {}           # VoxelObject -> true
var _impacts: Array = []
var _pending_explosives := {}      # VoxelObject -> seconds left
var impacts_after_ms := 0
var stats := {"rebuilds": 0, "rebuild_usec": 0, "rebuild_max_usec": 0, "islands": 0, "explosions": 0,
	"explode_max_usec": 0, "island_max_usec": 0, "debris_usec": 0, "fire_usec": 0}


func _init() -> void:
	instance = self


func _ready() -> void:
	debris = DebrisSystem.new()
	add_child(debris)
	fx = Fx.new()
	add_child(fx)
	sfx = Sfx.new()
	add_child(sfx)
	fire = FireSystem.new()
	add_child(fire)


func _exit_tree() -> void:
	# Shapes are cached across objects; release them with the world.
	for s in VoxelObject._shape_cache.values():
		PhysicsServer3D.free_rid(s)
	VoxelObject._shape_cache.clear()


func register(o: VoxelObject) -> void:
	objects.append(o)
	if network_role != 0:
		if o.network_id == 0:
			o.network_id = _next_network_id
		_next_network_id = maxi(_next_network_id, o.network_id + 1)
		network_objects[o.network_id] = o
		if network_role == 1:
			network_dirty[o.network_id] = true


func unregister(o: VoxelObject) -> void:
	objects.erase(o)
	_rebuild_queue.erase(o)
	_pending_explosives.erase(o)
	if o.network_id > 0:
		network_objects.erase(o.network_id)
		network_dirty.erase(o.network_id)
		if network_role == 1:
			network_removed.append(o.network_id)


func queue_rebuild(o: VoxelObject) -> void:
	_rebuild_queue[o] = true
	if network_role == 1:
		network_dirty[o.network_id] = true


func dynamic_count() -> int:
	var n := 0
	for o in objects:
		if not o.static_mode:
			n += 1
	return n


func _process(delta: float) -> void:
	if limit_distant_physics:
		_prop_timer -= delta
		if _prop_timer <= 0.0:
			_prop_timer = 0.25
			update_prop_activity()
	if network_role != 2:
		_process_impacts()
		_process_explosives(delta)
	_process_rebuilds()


func update_prop_activity() -> void:
	var at := player.global_position
	for o in objects:
		if o.static_mode or o.held:
			continue
		var limit := 34.0 if o.freeze else 40.0
		var should_freeze := o.global_position.distance_squared_to(at) > limit * limit
		if should_freeze != o.freeze:
			o.freeze = should_freeze


func _process_rebuilds() -> void:
	if _rebuild_queue.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var done := 0
	var budget := 3400 if OS.has_feature("web") else REBUILD_BUDGET_USEC
	for o: VoxelObject in _rebuild_queue.keys():
		if not is_instance_valid(o):
			_rebuild_queue.erase(o)
			continue
		while o.rebuild_next():
			done += 1
			if Time.get_ticks_usec() - t0 > budget:
				break
		if not o.has_dirty():
			_rebuild_queue.erase(o)
		if Time.get_ticks_usec() - t0 > budget:
			break
	stats.rebuilds = done
	stats.rebuild_usec = Time.get_ticks_usec() - t0
	stats.rebuild_max_usec = maxi(stats.rebuild_max_usec, stats.rebuild_usec)


func pending_rebuilds() -> int:
	return _rebuild_queue.size()


# ------------------------------------------------------------------ queries

## Sphere vs object bounds (in object space, so rotated bodies are exact enough).
## Physics shape queries saturate on objects made of hundreds of boxes, this does not.
func objects_in_sphere(pos: Vector3, radius: float, mask := Layers.SOLID) -> Array[VoxelObject]:
	var out: Array[VoxelObject] = []
	for o in objects:
		if not is_instance_valid(o) or o.is_queued_for_deletion():
			continue
		if o.static_mode and not (mask & Layers.STATIC):
			continue
		if not o.static_mode and not (mask & Layers.DYNAMIC):
			continue
		var lp := o.global_transform.affine_inverse() * pos
		var size := Vector3(o.volume.get_size()) * VS
		var q := lp.clamp(Vector3.ZERO, size)
		if q.distance_squared_to(lp) <= radius * radius:
			out.append(o)
	return out


func raycast(from: Vector3, to: Vector3, mask := Layers.SOLID, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)


# ------------------------------------------------------------------ destruction API

## Local damage (hammer, bullets, torch). Returns removed voxel count.
func damage_at(obj: VoxelObject, pos: Vector3, radius: float, power: float, impulse := Vector3.ZERO, debris_chance := 0.15, max_debris := 8) -> int:
	if not is_instance_valid(obj):
		return 0
	var res := obj.carve(pos, radius, power, 0.25, debris_chance, max_debris)
	var n: int = res.count
	if n > 0:
		_spawn_debris(obj, res, pos, 1.5)
		fx.dust(pos, _dust_color(res), clampf(n / 30.0, 0.3, 1.5))
		_break_sound(res, pos, clampf(-16.0 + n * 0.25, -16.0, -2.0))
		geometry_changed.emit(pos, radius + 0.6)
	if impulse != Vector3.ZERO and not obj.static_mode and is_instance_valid(obj):
		if limit_distant_physics:
			obj.freeze = false
		obj.apply_impulse(impulse, pos - obj.global_position)
	return n


func explode(pos: Vector3, radius: float, power: float) -> void:
	if network_role == 2:
		return
	var t0 := Time.get_ticks_usec()
	stats.explosions += 1
	fx.explosion(pos, radius)
	if network_role == 1:
		network_blast.emit(pos, radius)
	sfx.play("explosion", pos, 6.0 + radius * 2.0, 0.9 + randf() * 0.2)
	if player and player.has_method("shake"):
		var d := player.global_position.distance_to(pos)
		player.shake(clampf(radius * 1.6 / maxf(d, 1.0), 0.0, 1.0))

	for obj in objects_in_sphere(pos, radius * 1.15):
		if not is_instance_valid(obj):
			continue
		var res := obj.carve(pos, radius, power, 0.45, 0.07, 36)
		if res.count > 0:
			_spawn_debris(obj, res, pos, 9.0)
		if is_instance_valid(obj) and obj.volume.get_solid_count() > 0:
			fire.ignite_near(obj, pos, radius * 0.9, 3)

	# Shockwave after carving so freshly released pieces get pushed too.
	_shockwave.call_deferred(pos, radius, power)

	if is_instance_valid(player):
		player.apply_blast(pos, radius * 2.0, power)
	geometry_changed.emit(pos, radius * 1.5 + 0.5)
	stats.explode_max_usec = maxi(stats.explode_max_usec, Time.get_ticks_usec() - t0)


func _shockwave(pos: Vector3, radius: float, power: float) -> void:
	var reach := radius * 2.6
	for obj in objects_in_sphere(pos, reach, Layers.DYNAMIC):
		if not is_instance_valid(obj) or obj.static_mode:
			continue
		var c := obj.world_center()
		var d := c.distance_to(pos)
		var f := clampf(1.0 - d / reach, 0.0, 1.0)
		if f <= 0.0:
			continue
		var dir := (c - pos).normalized() if d > 0.01 else Vector3.UP
		dir = (dir + Vector3.UP * 0.35).normalized()
		var dv := minf(power * 2.6 * f, power * 520.0 * f / obj.mass)
		if limit_distant_physics:
			obj.freeze = false
		obj.apply_central_impulse(dir * dv * obj.mass)
		obj.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * dv * obj.mass * 0.05)
	debris.blast(pos, reach, power)


func trigger_explosive(obj: VoxelObject, delay: float) -> void:
	if obj.exploded or _pending_explosives.has(obj):
		return
	_pending_explosives[obj] = delay


func _process_explosives(delta: float) -> void:
	if _pending_explosives.is_empty():
		return
	for obj: VoxelObject in _pending_explosives.keys():
		if not is_instance_valid(obj):
			_pending_explosives.erase(obj)
			continue
		_pending_explosives[obj] -= delta
		if _pending_explosives[obj] <= 0.0:
			_pending_explosives.erase(obj)
			if obj.exploded:
				continue
			obj.exploded = true
			var c := obj.world_center()
			var r := obj.explosive_radius
			var p := obj.explosive_power
			fire.ignite_near(obj, c, r, 2)
			explode(c, r, p)


## Turns an island cut out of `src` into its own body (or debris if tiny).
func spawn_island(src: VoxelObject, island: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var vol: VoxelVolume = island.volume
	var off: Vector3i = island.offset
	var count: int = island.count
	stats.islands += 1
	var xform := src.global_transform * Transform3D(Basis.IDENTITY, Vector3(off) * VS)
	var base_vel := Vector3.ZERO
	var base_ang := Vector3.ZERO
	if not src.static_mode:
		base_vel = src.linear_velocity
		base_ang = src.angular_velocity

	if count < MIN_ISLAND_VOXELS or dynamic_count() >= MAX_DYNAMIC_OBJECTS:
		_island_to_debris(vol, xform, base_vel, count)
		return

	var obj := VoxelObject.new()
	# Whole storeys breaking off get big chunks to keep the draw count sane.
	obj.setup(vol, false, Vector3i(64, 64, 64) if count > 40000 else Vector3i(32, 32, 32))
	obj.label = src.label + "_piece"
	obj.transform = xform
	if src.explosive_radius > 0.0 and not src.exploded:
		obj.explosive_radius = src.explosive_radius * clampf(float(count) / maxf(src.voxel_count() + count, 1.0), 0.4, 1.0)
		obj.explosive_power = src.explosive_power
	add_child(obj)
	var com_w := obj.to_global(obj.center_of_mass)
	if not src.static_mode:
		obj.linear_velocity = base_vel + base_ang.cross(com_w - src.to_global(src.center_of_mass))
		obj.angular_velocity = base_ang
	if fire.has_fire_in(src):
		fire.transfer(src, obj, off)
	geometry_changed.emit(obj.world_center(), Vector3(vol.get_size()).length() * VS * 0.5 + 0.5)
	if count > 2500:
		var c := obj.world_center()
		sfx.play("collapse", c, clampf(count / 3000.0, 2.0, 14.0), randf_range(0.85, 1.05))
		fx.dust_cloud(c, clampf(count / 20000.0, 0.7, 3.0))
	stats.island_max_usec = maxi(stats.island_max_usec, Time.get_ticks_usec() - t0)


func _island_to_debris(vol: VoxelVolume, xform: Transform3D, vel: Vector3, count: int) -> void:
	var b: Array = vol.get_bounds()
	if b.is_empty():
		return
	var mn: Vector3i = b[0]
	var mx: Vector3i = b[1]
	var emitted := 0
	for z in range(mn.z, mx.z):
		for y in range(mn.y, mx.y):
			for x in range(mn.x, mx.x):
				var v := vol.get_voxel(Vector3i(x, y, z))
				if v == 0:
					continue
				if emitted < 12:
					var p := xform * ((Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * VS)
					debris.spawn(p, VoxMat.color_of(v).srgb_to_linear() * randf_range(0.82, 1.12), VS, vel + Vector3(randf_range(-0.5, 0.5), randf_range(0, 0.6), randf_range(-0.5, 0.5)))
					emitted += 1


func _spawn_debris(obj: VoxelObject, res: Dictionary, center: Vector3, speed: float) -> void:
	var dp: PackedVector3Array = res.debris_pos
	var di: PackedByteArray = res.debris_idx
	if dp.is_empty():
		return
	var xf := obj.global_transform
	var base_vel := Vector3.ZERO if obj.static_mode else obj.linear_velocity
	var glass := 0
	for i in dp.size():
		var p := xf * (dp[i] * VS)
		var dir := (p - center)
		dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
		var v := base_vel + (dir + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.7), randf_range(-0.4, 0.4))) * speed * randf_range(0.3, 1.0)
		var idx := di[i]
		var size := VS * (1.0 if randf() < 0.75 else 2.0)
		debris.spawn(p, VoxMat.color_of(idx).srgb_to_linear() * randf_range(0.82, 1.12), size, v)
		if VoxMat.material_of(idx) == VoxMat.GLASS:
			glass += 1
	if glass > 0:
		sfx.play("glass", center, 0.0, randf_range(0.9, 1.2))


func _dust_color(res: Dictionary) -> Color:
	var di: PackedByteArray = res.debris_idx
	if di.is_empty():
		return Color(0.6, 0.57, 0.52)
	return VoxMat.color_of(di[0]).lerp(Color(0.7, 0.68, 0.64), 0.4)


# ------------------------------------------------------------------ crash damage

func queue_impact(a: VoxelObject, other: Object, pos: Vector3, impulse: float, dv: float) -> void:
	# Props settle for a moment after the level loads; that is not a crash.
	if Time.get_ticks_msec() < impacts_after_ms:
		return
	if _impacts.size() < 24:
		_impacts.append([a, other, pos, impulse, dv])


func _process_impacts() -> void:
	if _impacts.is_empty():
		return
	var list := _impacts
	_impacts = []
	for it in list:
		var a: VoxelObject = it[0]
		if not is_instance_valid(a):
			continue
		var other = it[1]
		var pos: Vector3 = it[2]
		var j: float = it[3]
		var dv: float = it[4]
		# Heavier and faster hits break harder materials and wider areas.
		# Whole storeys slamming down crush concrete; small things only chip.
		var heavy := clampf(a.mass / 20000.0, 0.0, 4.5)
		var fast := clampf((dv - 6.0) * 0.15, 0.0, 1.5)
		var power := clampf(0.25 + j / 1800.0 + dv * 0.06, 0.0, 2.6 + heavy + fast)
		var radius := clampf(0.12 + j / 9000.0, 0.12, 0.45 + heavy * 0.25 + fast * 0.3)
		var hit_any := false
		if other is VoxelObject and is_instance_valid(other):
			hit_any = damage_at(other, pos, radius, power, Vector3.ZERO, 0.2, 6) > 0 or hit_any
		hit_any = damage_at(a, pos, radius * 0.8, power * 0.8, Vector3.ZERO, 0.2, 6) > 0 or hit_any
		if is_instance_valid(a) and a.explosive_radius > 0.0 and dv > 9.0:
			trigger_explosive(a, 0.05)
		if is_instance_valid(a) and a.mass > 1500.0 and dv > 2.5:
			fx.dust_cloud(pos, clampf(a.mass / 12000.0, 0.5, 2.5))
		var vol := clampf(-18.0 + j / 120.0, -18.0, 4.0)
		sfx.play("impact" if hit_any else "thud", pos, vol, randf_range(0.8, 1.15))


var _last_break_ms := 0

## Material-specific break sound for the voxels a carve removed.
func _break_sound(res: Dictionary, pos: Vector3, volume_db: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_break_ms < 70:
		return
	_last_break_ms = now
	var di: PackedByteArray = res.debris_idx
	if di.is_empty():
		return
	match VoxMat.material_of(di[0]):
		VoxMat.WOOD, VoxMat.FOLIAGE, VoxMat.PLASTIC:
			sfx.play("wood_break", pos, volume_db, randf_range(0.85, 1.2))
		VoxMat.METAL, VoxMat.HARDMETAL:
			sfx.play("metal", pos, volume_db - 4.0, randf_range(0.9, 1.3))
		VoxMat.GLASS:
			sfx.play("glass", pos, volume_db, randf_range(0.9, 1.2))
		_:
			sfx.play("crumble", pos, volume_db, randf_range(0.85, 1.15))
