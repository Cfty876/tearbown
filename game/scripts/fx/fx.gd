class_name Fx
extends Node3D
## Particle and light effects. Every effect type is a small pool of one-shot
## Particle emitters that get restarted in place, so nothing is allocated per hit.

var _pools := {}
var _lights: Array[OmniLight3D] = []
var _light_t := PackedFloat32Array()
var _light_e := PackedFloat32Array()
var _light_d := PackedFloat32Array()
var _light_idx := 0
var _rings: Array[MeshInstance3D] = []
var _blast_cores: Array[MeshInstance3D] = []
var _ring_tweens: Array[Tween] = []
var _ring_idx := 0

static var soft_tex: Texture2D
static var smoke_tex: Texture2D


func _ready() -> void:
	if soft_tex == null:
		soft_tex = _make_soft_texture()
	if smoke_tex == null:
		smoke_tex = _make_smoke_texture()
	_pools["fireball"] = _make_pool(6, _fireball_setup)
	_pools["smoke"] = _make_pool(8, _smoke_setup)
	_pools["sparks"] = _make_pool(8, _sparks_setup)
	_pools["dust"] = _make_pool(16, _dust_setup)
	_pools["impact_sparks"] = _make_pool(6, _impact_sparks_setup)
	_pools["spray"] = _make_pool(6, _spray_setup)
	_pools["muzzle"] = _make_pool(4, _muzzle_setup)
	_pools["foam"] = _make_pool(6, _foam_setup)
	_pools["dustcloud"] = _make_pool(8, _dustcloud_setup)
	for i in 6:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = i < 2
		l.omni_attenuation = 1.6
		add_child(l)
		_lights.append(l)
	_light_t.resize(6)
	_light_d.resize(6)
	_light_e.resize(6)
	_ring_tweens.resize(3)
	var disc := QuadMesh.new()
	disc.orientation = PlaneMesh.FACE_Y
	var billboard := QuadMesh.new()
	for i in 3:
		var ring := MeshInstance3D.new()
		ring.mesh = disc
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/blast_ring.gdshader")
		ring.material_override = mat
		ring.hide()
		add_child(ring)
		_rings.append(ring)
		var core := MeshInstance3D.new()
		core.mesh = billboard
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flame := ShaderMaterial.new()
		flame.shader = preload("res://shaders/blast_core.gdshader")
		flame.set_shader_parameter("density_tex", smoke_tex)
		core.material_override = flame
		core.hide()
		add_child(core)
		_blast_cores.append(core)
	if not OS.has_feature("web"):
		_warmup.call_deferred()


## Emits every effect once far below the map so particle pipelines compile during
## loading instead of stalling the first explosion.
func _warmup() -> void:
	for pool_name in _pools:
		_emit(pool_name, Vector3(0, -80, 0), 0.1)
	flash(Vector3(0, -80, 0), Color.WHITE, 0.1, 1.0, 0.05)


static func _make_soft_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


static func _make_smoke_texture() -> Texture2D:
	const RES := 80
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 726
	noise.frequency = 0.075
	for y in RES:
		for x in RES:
			var center := Vector2(x, y) / (RES - 1.0) * 2.0 - Vector2.ONE
			var detail := noise.get_noise_2d(x, y)
			var edge := center.length() + detail * 0.21
			var density := (1.0 - smoothstep(0.21, 0.96, edge)) * (0.75 + detail * 0.42)
			var color := 0.88 + detail * 0.12
			img.set_pixel(x, y, Color(color, color, color, density))
	return ImageTexture.create_from_image(img)


static func particle_material(additive: bool, lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var web := OS.has_feature("web")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit and not web else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex
	m.roughness = 1.0
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = not web
	m.proximity_fade_distance = 0.6
	return m


static func ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _make_pool(n: int, setup: Callable) -> Array:
	var arr: Array[GeometryInstance3D] = []
	for i in n:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
		var quad := QuadMesh.new()
		p.draw_pass_1 = quad
		setup.call(p)
		var emitter: GeometryInstance3D = web_emitter(p) if OS.has_feature("web") else p
		add_child(emitter)
		arr.append(emitter)
	return [arr, 0]


static func web_emitter(source: GPUParticles3D) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.convert_from_particles(source)
	emitter.material_override = source.material_override
	emitter.cast_shadow = source.cast_shadow
	emitter.transform = source.transform
	emitter.fixed_fps = 30
	emitter.amount = maxi(2, roundi(float(source.amount) * 0.32))
	emitter.set_meta("base_amount", emitter.amount)
	source.free()
	return emitter


## Basis whose +Y points along dir (particle systems emit along local +Y).
static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func _emit(pool_name: String, pos: Vector3, scale_f := 1.0, dir := Vector3.UP):
	var pool: Array = _pools[pool_name]
	var arr: Array = pool[0]
	var i: int = pool[1]
	pool[1] = (i + 1) % arr.size()
	var p = arr[i]
	p.global_transform = Transform3D(basis_y(dir).scaled(Vector3.ONE * scale_f), pos)
	p.restart()
	p.emitting = true
	return p


# ------------------------------------------------------------------ setups

func _fireball_setup(p: GPUParticles3D) -> void:
	p.amount = 10
	p.lifetime = 0.49
	p.explosiveness = 0.95
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.35
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 3.5
	m.damping_min = 4.0
	m.damping_max = 8.0
	m.gravity = Vector3(0, 2.0, 0)
	m.scale_min = 0.29
	m.scale_max = 0.69
	m.scale_curve = curve([Vector2(0, 0.4), Vector2(0.25, 1.0), Vector2(1, 0.6)])
	m.color_ramp = ramp([Color(5, 4, 2.5, 1), Color(4, 1.6, 0.4, 0.9), Color(1.2, 0.3, 0.08, 0.6), Color(0.1, 0.05, 0.03, 0)], [0.0, 0.25, 0.6, 1.0])
	m.angle_min = 0.0
	m.angle_max = 360.0
	p.process_material = m
	var flame := particle_material(true, false)
	flame.albedo_color = Color(0.93, 0.32, 0.055, 0.78)
	flame.albedo_texture = smoke_tex
	p.material_override = flame


func _smoke_setup(p: GPUParticles3D) -> void:
	p.amount = 34
	p.lifetime = 3.6
	p.explosiveness = 0.85
	p.randomness = 0.4
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.9
	m.direction = Vector3.UP
	m.spread = 70.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 4.5
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.gravity = Vector3(0.25, 0.9, 0.1)
	m.scale_min = 1.6
	m.scale_max = 3.2
	m.scale_curve = curve([Vector2(0, 0.35), Vector2(0.3, 0.8), Vector2(1, 1.0)])
	m.color_ramp = ramp([Color(0.32, 0.29, 0.26, 0.0), Color(0.30, 0.27, 0.24, 0.75), Color(0.42, 0.40, 0.37, 0.5), Color(0.5, 0.48, 0.45, 0.0)], [0.0, 0.08, 0.5, 1.0])
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = -20.0
	m.angular_velocity_max = 20.0
	p.process_material = m
	var smoke_material := particle_material(false, true)
	smoke_material.albedo_texture = smoke_tex
	smoke_material.albedo_color = Color(0.36, 0.31, 0.28, 0.73)
	p.material_override = smoke_material
	p.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 40, 40))


func _sparks_setup(p: GPUParticles3D) -> void:
	p.amount = 70
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.randomness = 0.5
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.4
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 5.0
	m.initial_velocity_max = 17.0
	m.gravity = Vector3(0, -9.8, 0)
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.scale_min = 0.027
	m.scale_max = 0.075
	m.color_ramp = ramp([Color(6, 3.5, 1.2, 1), Color(3, 0.9, 0.2, 1), Color(0.6, 0.1, 0.02, 0)], [0.0, 0.5, 1.0])
	m.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	m.collision_bounce = 0.3
	m.collision_friction = 0.3
	p.process_material = m
	var embers := particle_material(true, false)
	embers.albedo_color = Color(1.0, 0.44, 0.09)
	p.material_override = embers
	p.collision_base_size = 0.05


func _dust_setup(p: GPUParticles3D) -> void:
	p.amount = 12
	p.lifetime = 1.8
	p.explosiveness = 0.9
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.15
	m.direction = Vector3.UP
	m.spread = 90.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.8
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.gravity = Vector3(0, -0.4, 0)
	m.scale_min = 0.25
	m.scale_max = 0.6
	m.scale_curve = curve([Vector2(0, 0.4), Vector2(1, 1.0)])
	m.color_ramp = ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)], [0.0, 0.1, 1.0])
	m.angle_max = 360.0
	p.process_material = m
	p.material_override = particle_material(false, true)


func _impact_sparks_setup(p: GPUParticles3D) -> void:
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.8
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 6.0
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.025
	m.scale_max = 0.06
	m.color_ramp = ramp([Color(8, 6, 3, 1), Color(4, 1.2, 0.2, 1), Color(1, 0.2, 0.0, 0)], [0.0, 0.4, 1.0])
	m.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	m.collision_bounce = 0.4
	p.process_material = m
	p.material_override = particle_material(true, false)


func _spray_setup(p: GPUParticles3D) -> void:
	p.amount = 3
	p.lifetime = 0.11
	p.explosiveness = 0.9
	(p.draw_pass_1 as QuadMesh).size = Vector2(0.13, 0.13)
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 24.0
	m.initial_velocity_min = 0.45
	m.initial_velocity_max = 0.95
	m.gravity = Vector3.ZERO
	m.damping_min = 6.0
	m.damping_max = 9.0
	m.scale_min = 0.08
	m.scale_max = 0.20
	m.scale_curve = curve([Vector2(0, 0.3), Vector2(1, 1.0)])
	m.color_ramp = ramp([Color(1.0, 0.82, 0.12, 0.0), Color(1.0, 0.82, 0.12, 0.23), Color(1.0, 0.85, 0.2, 0.0)], [0.0, 0.15, 1.0])
	p.process_material = m
	p.material_override = particle_material(false, false)


func _foam_setup(p: GPUParticles3D) -> void:
	p.amount = 16
	p.lifetime = 0.8
	p.explosiveness = 0.6
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 7.0
	m.initial_velocity_max = 10.0
	m.gravity = Vector3(0, -2.0, 0)
	m.damping_min = 3.0
	m.damping_max = 5.0
	m.scale_min = 0.04
	m.scale_max = 0.1
	m.scale_curve = curve([Vector2(0, 0.3), Vector2(1, 1.6)])
	m.color_ramp = ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.6), Color(0.9, 0.92, 0.95, 0.0)], [0.0, 0.12, 1.0])
	p.process_material = m
	p.material_override = particle_material(false, true)


func _dustcloud_setup(p: GPUParticles3D) -> void:
	p.amount = 30
	p.lifetime = 4.3
	p.explosiveness = 0.9
	p.randomness = 0.5
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(3.0, 0.4, 3.0)
	m.direction = Vector3.UP
	m.spread = 80.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 5.0
	m.damping_min = 1.2
	m.damping_max = 2.4
	m.gravity = Vector3(0.2, 0.35, 0.1)
	m.scale_min = 2.0
	m.scale_max = 4.5
	m.scale_curve = curve([Vector2(0, 0.3), Vector2(0.4, 0.9), Vector2(1, 1.2)])
	m.color_ramp = ramp([Color(0.55, 0.5, 0.44, 0.0), Color(0.52, 0.48, 0.42, 0.7), Color(0.6, 0.57, 0.52, 0.0)], [0.0, 0.1, 1.0])
	m.angle_max = 360.0
	p.process_material = m
	var dust := particle_material(false, true)
	dust.albedo_color = Color(0.54, 0.43, 0.32, 0.58)
	dust.albedo_texture = smoke_tex
	p.material_override = dust
	p.visibility_aabb = AABB(Vector3(-30, -6, -30), Vector3(60, 40, 60))


func _muzzle_setup(p: GPUParticles3D) -> void:
	p.amount = 10
	p.lifetime = 0.12
	p.explosiveness = 1.0
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 14.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 8.0
	m.scale_min = 0.1
	m.scale_max = 0.25
	m.color_ramp = ramp([Color(8, 5, 2, 1), Color(2, 0.6, 0.1, 0)], [0.0, 1.0])
	p.process_material = m
	p.material_override = particle_material(true, false)


# ------------------------------------------------------------------ public

func explosion(pos: Vector3, radius: float) -> void:
	var s := clampf(radius / 1.6, 0.5, 2.5)
	_emit("fireball", pos, s)
	_emit("smoke", pos + Vector3.UP * 0.2, s * 0.87)
	flash(pos + Vector3.UP * 0.2, Color(1.0, 0.62, 0.3), 9.0 * s, radius * 5.0, 0.24)
	if GameState.cinematic_fx:
		_emit("sparks", pos, s)
		_emit("dustcloud", pos, s * 0.95)
	_animate_blast(pos, radius)


func _animate_blast(pos: Vector3, radius: float) -> void:
	var i := _ring_idx
	_ring_idx = (_ring_idx + 1) % _rings.size()
	if _ring_tweens[i]:
		_ring_tweens[i].kill()
	var ring := _rings[i]
	var core := _blast_cores[i]
	var flame := core.material_override as ShaderMaterial
	flame.set_shader_parameter("progress", 0.0)
	core.global_position = pos + Vector3.UP * radius * 0.28
	core.scale = Vector3.ONE * radius * 0.42
	core.show()
	var animation := create_tween().set_parallel(true)
	animation.tween_property(core, "scale", Vector3.ONE * radius * 2.15, 0.61).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(core, "global_position:y", pos.y + radius * 0.73, 0.61)
	animation.tween_property(flame, "shader_parameter/progress", 1.0, 0.61)
	ring.visible = GameState.cinematic_fx
	if ring.visible:
		var mat := ring.material_override as ShaderMaterial
		mat.set_shader_parameter("progress", 0.0)
		ring.global_position = pos + Vector3.UP * 0.08
		ring.scale = Vector3.ONE * maxf(1.0, radius * 1.5)
		animation.tween_property(ring, "scale", Vector3.ONE * (radius * 5.6), 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		animation.tween_property(mat, "shader_parameter/progress", 1.0, 0.55)
	animation.chain().tween_callback(func():
		core.hide()
		ring.hide())
	_ring_tweens[i] = animation


func set_visual_budget(particles: float, shadows: bool) -> void:
	for key in ["smoke", "dustcloud", "dust", "sparks"]:
		for p in _pools[key][0]:
			if p is CPUParticles3D:
				p.amount = maxi(2, roundi(float(p.get_meta("base_amount")) * particles))
			else:
				p.amount_ratio = particles
	for i in _lights.size():
		_lights[i].shadow_enabled = shadows and i < 2


## Big rolling dust cloud for collapses and heavy impacts.
func dust_cloud(pos: Vector3, scale_f := 1.0) -> void:
	_emit("dustcloud", pos, scale_f)


func dust(pos: Vector3, color: Color, scale_f := 1.0) -> void:
	var p = _emit("dust", pos, scale_f)
	if p is CPUParticles3D:
		p.color = color
	else:
		(p.process_material as ParticleProcessMaterial).color = color


func sparks(pos: Vector3, normal: Vector3) -> void:
	_emit("impact_sparks", pos, 1.0, normal)


func spray(pos: Vector3, normal: Vector3) -> void:
	_emit("spray", pos + normal * 0.032, 1.0, normal)


func foam(pos: Vector3, dir: Vector3) -> void:
	_emit("foam", pos + dir.normalized() * 0.45, 1.0, dir)


func muzzle(pos: Vector3, dir: Vector3, heavy := false) -> void:
	_emit("muzzle", pos, 1.45 if heavy else 0.84, dir)
	flash(pos, Color(1.0, 0.74, 0.38), 5.5 if heavy else 2.8, 5.0, 0.07)
	if GameState.cinematic_fx:
		_emit("dust", pos + dir * 0.2, 0.58 if heavy else 0.33, dir)


func flash(pos: Vector3, color: Color, energy: float, rng: float, duration: float) -> void:
	var i := _light_idx
	_light_idx = (_light_idx + 1) % _lights.size()
	var l := _lights[i]
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.visible = true
	_light_t[i] = duration
	_light_d[i] = duration
	_light_e[i] = energy


func _process(delta: float) -> void:
	for i in _lights.size():
		if _light_t[i] <= 0.0:
			continue
		_light_t[i] -= delta
		var l := _lights[i]
		if _light_t[i] <= 0.0:
			l.visible = false
		else:
			var k := _light_t[i] / _light_d[i]
			l.light_energy = _light_e[i] * k * k
