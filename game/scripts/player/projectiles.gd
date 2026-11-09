class_name Projectiles
## Thrown pipe bombs and rockets.

const VS_MODEL := 0.025


static func pipe_bomb_model() -> MeshInstance3D:
	var v := VoxModel.volume(Vector3i(5, 14, 5))
	v.fill_cylinder(Vector3(2.5, 1, 2.5), 2.3, 12, 1, VoxMat.id("metal"))
	v.fill_cylinder(Vector3(2.5, 0, 2.5), 2.5, 2, 1, VoxMat.id("metal_dark"))
	v.fill_cylinder(Vector3(2.5, 11, 2.5), 2.5, 2, 1, VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(2, 13, 2), Vector3i(3, 14, 3), VoxMat.id("plastic_white"))
	return VoxModel.instance(v, VS_MODEL, Vector3(2.5, 7, 2.5).floor())


static func rocket_model() -> MeshInstance3D:
	var v := VoxModel.volume(Vector3i(5, 5, 20))
	v.fill_cylinder(Vector3(2.5, 2.5, 3), 2.2, 17, 2, VoxMat.id("metal_green"))
	v.fill_cylinder(Vector3(2.5, 2.5, 0), 1.4, 3, 2, VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(0, 2, 17), Vector3i(5, 3, 20), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(2, 0, 17), Vector3i(3, 5, 20), VoxMat.id("metal_dark"))
	return VoxModel.instance(v, VS_MODEL, Vector3(2, 2, 10))


class PipeBomb:
	extends RigidBody3D
	var fuse := 3.0
	var blast_radius := 1.7
	var blast_power := 6.0
	var _blink := 0.0
	var _light: OmniLight3D

	func _ready() -> void:
		collision_layer = Layers.PROJECTILE
		collision_mask = Layers.STATIC | Layers.DYNAMIC
		mass = 1.2
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.12, 0.34, 0.12)
		s.shape = b
		add_child(s)
		add_child(Projectiles.pipe_bomb_model())
		_light = OmniLight3D.new()
		_light.light_color = Color(1, 0.2, 0.1)
		_light.omni_range = 1.5
		_light.light_energy = 0.0
		_light.position.y = 0.2
		add_child(_light)
		continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.2
		pm.friction = 0.9
		physics_material_override = pm

	func _process(delta: float) -> void:
		fuse -= delta
		_blink += delta * (4.0 + (3.0 - fuse) * 6.0)
		_light.light_energy = 2.5 if fmod(_blink, 1.0) < 0.3 else 0.0
		if fuse <= 0.0:
			var p := global_position
			queue_free()
			VoxelWorld.instance.explode(p, blast_radius, blast_power)


class Rocket:
	extends Node3D
	var velocity := Vector3.ZERO
	var life := 6.0
	var shooter_rid := RID()
	var blast_radius := 2.2
	var blast_power := 7.0
	var _trail
	var _light: OmniLight3D

	func _ready() -> void:
		var m := Projectiles.rocket_model()
		add_child(m)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.6, 0.3)
		_light.light_energy = 3.0
		_light.omni_range = 4.0
		_light.position.z = 0.3
		add_child(_light)
		var trail := GPUParticles3D.new()
		trail.amount = 160
		trail.lifetime = 2.2
		trail.local_coords = false
		trail.position.z = 0.28
		trail.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, 1)
		pm.spread = 10.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.5
		pm.gravity = Vector3(0, 0.6, 0)
		pm.damping_min = 1.0
		pm.damping_max = 2.0
		pm.scale_min = 0.25
		pm.scale_max = 0.5
		pm.scale_curve = Fx.curve([Vector2(0, 0.3), Vector2(1, 1.8)])
		pm.color_ramp = Fx.ramp([Color(4, 2, 0.8, 1), Color(0.6, 0.55, 0.5, 0.5), Color(0.75, 0.73, 0.7, 0.0)], [0.0, 0.08, 1.0])
		trail.process_material = pm
		trail.draw_pass_1 = QuadMesh.new()
		trail.material_override = Fx.particle_material(false, false)
		_trail = Fx.web_emitter(trail) if OS.has_feature("web") else trail
		add_child(_trail)

	func _physics_process(delta: float) -> void:
		life -= delta
		velocity += Vector3.DOWN * 1.5 * delta
		var from := global_position
		var to := from + velocity * delta
		var ex: Array[RID] = [shooter_rid]
		var hit := VoxelWorld.instance.raycast(from, to, Layers.SOLID | Layers.PLAYER, ex)
		if not hit.is_empty() or life <= 0.0:
			var p: Vector3 = hit.position if not hit.is_empty() else to
			_detach_trail()
			queue_free()
			VoxelWorld.instance.explode(p, blast_radius, blast_power)
			return
		global_position = to
		if velocity.length_squared() > 0.01:
			look_at(to + velocity, Vector3.UP)

	func _detach_trail() -> void:
		# Let the smoke trail linger after the rocket is gone.
		var t = _trail
		var xf: Transform3D = t.global_transform
		remove_child(t)
		VoxelWorld.instance.add_child(t)
		t.global_transform = xf
		t.emitting = false
		t.get_tree().create_timer(t.lifetime + 0.2).timeout.connect(t.queue_free)
