class_name FireSystem
extends Node3D
## Voxel fire: burning points live on flammable surface voxels, spread to nearby
## flammable voxels, eat through them (which can cut supports and drop pieces) and
## leave charred voxels behind. All flames share one particle system fed by an
## emission-point texture, so hundreds of fires cost a single draw.

const MAX_FIRES := 160
const TICK := 0.2
const VS := VoxelObject.VS

var fires: Array[FirePoint] = []
var sync_burn_cells := false
var burn_updates: Array = []
var _surface_flames: Array[Dictionary] = []
var _keys := {}
var _t := 0.0
var _flames
var _smoke
var _points_img: Image
var _points_tex: ImageTexture
var _lights: Array[OmniLight3D] = []
var _particle_budget := 1.0
var _light_budget := 3


class FirePoint:
	var obj: VoxelObject
	var v: Vector3i
	var mat: int
	var age := 0.0
	var life := 4.0


func _ready() -> void:
	_points_img = Image.create(MAX_FIRES, 1, false, Image.FORMAT_RGBF)
	_points_tex = ImageTexture.create_from_image(_points_img)
	_flames = _make_emitter(true)
	_smoke = _make_emitter(false)
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.22)
		l.omni_range = 7.0
		l.shadow_enabled = i == 0
		l.visible = false
		add_child(l)
		_lights.append(l)
	if not OS.has_feature("web"):
		# Compile the flame/smoke pipelines during loading.
		_points_img.set_pixel(0, 0, Color(0, -80, 0))
		_points_tex.update(_points_img)
		for p in [_flames, _smoke]:
			(p.process_material as ParticleProcessMaterial).emission_point_count = 1
			p.emitting = true


func _make_emitter(flame: bool) -> GeometryInstance3D:
	var p := GPUParticles3D.new()
	p.amount = 520 if flame else 260
	p.lifetime = 0.9 if flame else 3.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 200, 400))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	m.emission_point_texture = _points_tex
	m.emission_point_count = 0
	m.direction = Vector3.UP
	m.spread = 14.0 if flame else 25.0
	m.gravity = Vector3(0.1, 2.6 if flame else 1.2, 0.05)
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.9
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.angle_max = 360.0
	if flame:
		m.scale_min = 0.18
		m.scale_max = 0.42
		m.scale_curve = Fx.curve([Vector2(0, 0.6), Vector2(0.3, 1.0), Vector2(1, 0.1)])
		m.color_ramp = Fx.ramp([Color(5, 3.2, 1.2, 0.0), Color(5, 2.2, 0.5, 1.0), Color(2.5, 0.6, 0.1, 0.7), Color(0.3, 0.05, 0.0, 0.0)], [0.0, 0.1, 0.5, 1.0])
		p.material_override = Fx.particle_material(true, false)
	else:
		m.scale_min = 0.5
		m.scale_max = 1.2
		m.scale_curve = Fx.curve([Vector2(0, 0.4), Vector2(1, 1.6)])
		m.color_ramp = Fx.ramp([Color(0.1, 0.09, 0.08, 0.0), Color(0.12, 0.1, 0.09, 0.45), Color(0.3, 0.28, 0.26, 0.0)], [0.0, 0.2, 1.0])
		p.material_override = Fx.particle_material(false, true)
	p.process_material = m
	p.draw_pass_1 = QuadMesh.new()
	var emitter: GeometryInstance3D = Fx.web_emitter(p) if OS.has_feature("web") else p
	add_child(emitter)
	return emitter


func count() -> int:
	return fires.size()


func set_visual_budget(particles: float, lights: int, shadows: bool) -> void:
	_particle_budget = particles
	for p in [_flames, _smoke]:
		if p is CPUParticles3D:
			p.amount = maxi(2, roundi(float(p.get_meta("base_amount")) * particles))
	_light_budget = clampi(lights, 1, _lights.size())
	for i in _lights.size():
		_lights[i].shadow_enabled = shadows and i == 0
		if i >= _light_budget:
			_lights[i].hide()


func _key(obj: VoxelObject, v: Vector3i) -> String:
	return "%d:%d:%d:%d" % [obj.get_instance_id(), v.x, v.y, v.z]


func ignite(obj: VoxelObject, v: Vector3i) -> bool:
	if fires.size() >= MAX_FIRES or not is_instance_valid(obj):
		return false
	var idx := obj.volume.get_voxel(v)
	if idx == 0:
		return false
	var mat := VoxMat.material_of(idx)
	if not mat in VoxMat.FLAMMABLE:
		return false
	var k := _key(obj, v)
	if _keys.has(k):
		return false
	var f := FirePoint.new()
	f.obj = obj
	f.v = v
	f.mat = mat
	f.life = randf_range(2.5, 5.0) if mat == VoxMat.FOLIAGE else randf_range(4.0, 8.0)
	fires.append(f)
	_keys[k] = true
	return true


func ignite_near(obj: VoxelObject, world_pos: Vector3, radius: float, n: int) -> void:
	if not is_instance_valid(obj):
		return
	var c := obj.to_voxel(world_pos)
	var cv := Vector3i(floori(c.x), floori(c.y), floori(c.z))
	var r := maxi(1, roundi(radius / VS))
	for k in n:
		for mat in VoxMat.FLAMMABLE:
			var v := obj.volume.find_surface_voxel(cv, r, mat, randi())
			if v.x >= 0 and ignite(obj, v):
				break


func surface_flames(at: Vector3) -> void:
	for i in 8:
		if _surface_flames.size() >= 40:
			break
		var offset := Vector3(cos(i * TAU / 8.0), 0, sin(i * TAU / 8.0)) * (0.45 if i % 2 else 1.0)
		var sample := at + offset
		var hit := VoxelWorld.instance.raycast(sample + Vector3.UP * 0.55, sample - Vector3.UP * 1.2)
		if not hit.is_empty():
			_surface_flames.append({"at": hit.position + Vector3.UP * 0.10, "remaining": 4.0})


func extinguish(pos: Vector3, radius: float) -> int:
	var removed := 0
	for i in range(_surface_flames.size() - 1, -1, -1):
		if pos.distance_squared_to(_surface_flames[i].at) < radius * radius:
			_surface_flames.remove_at(i)
			removed += 1
	for i in range(fires.size() - 1, -1, -1):
		var f := fires[i]
		if not is_instance_valid(f.obj) or _world_pos(f).distance_to(pos) < radius:
			_remove(i)
			removed += 1
	return removed


func extinguish_jet(origin: Vector3, end: Vector3, direction: Vector3) -> void:
	var length := origin.distance_to(end) + 0.36
	for i in range(_surface_flames.size() - 1, -1, -1):
		var patch: Vector3 = _surface_flames[i].at
		if Geometry3D.get_closest_point_to_segment(patch, origin, end).distance_squared_to(patch) < 0.48:
			_surface_flames.remove_at(i)
	for i in range(fires.size() - 1, -1, -1):
		var fire := fires[i]
		if not is_instance_valid(fire.obj):
			_remove(i)
			continue
		var offset := _world_pos(fire) - origin
		var distance := offset.dot(direction)
		if distance < -0.2 or distance > length:
			continue
		var radius := 0.45 + distance * 0.085
		if (offset - direction * distance).length_squared() < radius * radius:
			_remove(i)


func has_fire_in(obj: VoxelObject) -> bool:
	for f in fires:
		if f.obj == obj:
			return true
	return false


## Fires whose voxel moved into a newly split piece follow it.
func transfer(src: VoxelObject, dst: VoxelObject, offset: Vector3i) -> void:
	for f in fires:
		if f.obj == src and src.volume.get_voxel(f.v) == 0:
			var nv := f.v - offset
			if dst.volume.get_voxel(nv) != 0:
				_keys.erase(_key(src, f.v))
				f.obj = dst
				f.v = nv
				_keys[_key(dst, nv)] = true


func _remove(i: int) -> void:
	var f := fires[i]
	if is_instance_valid(f.obj):
		_keys.erase(_key(f.obj, f.v))
	else:
		_keys.clear()
		for g in fires:
			if g != f and is_instance_valid(g.obj):
				_keys[_key(g.obj, g.v)] = true
	fires.remove_at(i)


func _world_pos(f: FirePoint) -> Vector3:
	return f.obj.to_global((Vector3(f.v) + Vector3(0.5, 0.9, 0.5)) * VS)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += delta
	if _t >= TICK:
		_t -= TICK
		_tick()
	_update_visuals()
	VoxelWorld.instance.stats.fire_usec = Time.get_ticks_usec() - t0


func _tick() -> void:
	for i in range(_surface_flames.size() - 1, -1, -1):
		_surface_flames[i].remaining -= TICK
		if _surface_flames[i].remaining <= 0.0:
			_surface_flames.remove_at(i)
	var pl: Player = VoxelWorld.instance.player
	if pl:
		var pp := pl.global_position + Vector3(0, 0.6, 0)
		for f in fires:
			if is_instance_valid(f.obj) and _world_pos(f).distance_squared_to(pp) < 1.7:
				pl.damage(3.0)
				break
	var i := fires.size() - 1
	while i >= 0:
		var f := fires[i]
		if not is_instance_valid(f.obj) or f.obj.is_queued_for_deletion() or f.obj.volume.get_voxel(f.v) == 0:
			_remove(i)
			i -= 1
			continue
		f.age += TICK
		var vol := f.obj.volume
		if randf() < 0.2 and fires.size() < MAX_FIRES:
			var mat: int = f.mat if randf() < 0.8 else VoxMat.FLAMMABLE.pick_random()
			var nv := vol.find_surface_voxel(f.v, 2, mat, randi())
			if nv.x >= 0:
				ignite(f.obj, nv)
		if randf() < 0.05:
			_spread_to_neighbors(f)
		if f.age >= f.life:
			_burn(f)
			_remove(i)
		i -= 1


func _spread_to_neighbors(f: FirePoint) -> void:
	var p := _world_pos(f)
	for o in VoxelWorld.instance.objects_in_sphere(p, 0.35):
		if o != f.obj:
			ignite_near(o, p, 0.35, 1)


func _burn(f: FirePoint) -> void:
	var obj := f.obj
	var secrets := VoxelWorld.instance.secrets
	if is_instance_valid(secrets) and secrets.protected(obj, _world_pos(f), 0.28):
		return
	var burn_seed := randi()
	var char_seed := randi()
	if _burn_cell(obj, f.v, burn_seed, char_seed) and sync_burn_cells and obj.network_id != 0:
		burn_updates.append([obj.network_id, f.v.x, f.v.y, f.v.z, burn_seed, char_seed])
	var vol := obj.volume
	# Keep eating into the material next to the burnt hole.
	if is_instance_valid(obj) and fires.size() < MAX_FIRES:
		var nv := vol.find_surface_voxel(f.v, 2, f.mat, randi())
		if nv.x >= 0:
			ignite(obj, nv)


func _burn_cell(obj: VoxelObject, cell: Vector3i, burn_seed: int, char_seed: int) -> bool:
	var c := Vector3(cell) + Vector3.ONE * 0.5
	var res: Dictionary = obj.volume.paint_sphere(c, 1.7, VoxMat.burn_remap, 0.85, burn_seed)
	var ch: Dictionary = obj.volume.paint_sphere(c, 2.8, VoxMat.char_remap, 0.55, char_seed)
	if ch.count > 0:
		obj.mark_dirty(ch.min, ch.max, true)
	if res.count > 0:
		if sync_burn_cells:
			obj.mark_dirty(res.min, res.max)
		else:
			obj.after_edit(res.min, res.max)
	return ch.count > 0 or res.count > 0


func apply_remote_burns(updates: Array) -> void:
	for entry in updates:
		if not entry is Array or entry.size() != 6:
			continue
		var object := VoxelWorld.instance.network_objects.get(int(entry[0])) as VoxelObject
		if is_instance_valid(object):
			_burn_cell(object, Vector3i(int(entry[1]), int(entry[2]), int(entry[3])), int(entry[4]), int(entry[5]))


func visual_positions() -> PackedVector3Array:
	var points := PackedVector3Array()
	for patch in _surface_flames:
		points.append(patch.at)
	for f in fires:
		if is_instance_valid(f.obj):
			points.append(_world_pos(f))
	return points


func _update_visuals() -> void:
	show_fire(visual_positions())


func show_fire(points: PackedVector3Array) -> void:
	var valid := mini(points.size(), MAX_FIRES)
	if valid == 0:
		_flames.emitting = false
		_smoke.emitting = false
		for l in _lights:
			l.visible = false
		VoxelWorld.instance.sfx.loop("fire", "fire", Vector3.ZERO, false)
		return
	var data := PackedFloat32Array()
	data.resize(MAX_FIRES * 3)
	var centroid := Vector3.ZERO
	for k in valid:
		var p := points[k]
		data[k * 3] = p.x
		data[k * 3 + 1] = p.y
		data[k * 3 + 2] = p.z
		centroid += p
	if not OS.has_feature("web"):
		_points_img.set_data(MAX_FIRES, 1, false, Image.FORMAT_RGBF, data.to_byte_array())
		_points_tex.update(_points_img)
	for p in [_flames, _smoke]:
		if p is CPUParticles3D:
			p.emission_points = points
		else:
			(p.process_material as ParticleProcessMaterial).emission_point_count = valid
			p.amount_ratio = clampf(float(valid) / 40.0, 0.15, 1.0) * _particle_budget
		p.emitting = true
	centroid /= valid
	var t := Time.get_ticks_msec() * 0.001
	for li in _light_budget:
		var l := _lights[li]
		var fi := (li * valid) / _light_budget
		if fi >= valid:
			l.visible = false
			continue
		l.visible = true
		l.global_position = Vector3(data[fi * 3], data[fi * 3 + 1] + 0.3, data[fi * 3 + 2])
		l.light_energy = (1.6 + sin(t * 23.0 + li * 2.1) * 0.35 + sin(t * 41.0 + li) * 0.25) * clampf(valid / 6.0, 0.4, 1.6)
	VoxelWorld.instance.sfx.loop("fire", "fire", centroid, true, clampf(-14.0 + valid * 0.3, -14.0, 0.0))
