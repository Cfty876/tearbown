class_name PlayerTools
extends Node3D
## Tool belt attached to the camera: viewmodels, input handling and the effect of
## each tool on the voxel world.

enum { HAMMER, SHOTGUN, PIPEBOMB, ROCKET, TORCH, SPRAY, EXTINGUISHER }

const NAMES := ["Кувалда", "Дробовик", "Трубчатая бомба", "Ракетница", "Горелка", "Баллончик", "Огнетушитель"]
const HINTS := [
	"ломает дерево, стекло, штукатурку",
	"дробь: мягкие материалы, сколы кирпича",
	"бросок, взрыв через 3 с",
	"ракета, взрыв при попадании",
	"режет всё, кроме стали; поджигает дерево",
	"рисует по любой поверхности",
	"тушит огонь",
]
const VS_MODEL := 0.019
const BASE_POS := Vector3(0.34, -0.3, -0.52)

signal selection_changed(index: int)

var player: Player
var input_enabled := true
## Scripted fire input for automated tests (bench --tools).
var sim_fire := false
var remote_tap := false
var mirror_only := false
var _sim_was := false
var current := HAMMER
var _models: Array[Node3D] = []
var _cooldown := 0.0
var _swing := 0.0
var _hammer_hit_pending := -1.0
var _recoil := 0.0
var _tick := 0.0
var _sway := Vector2.ZERO
var _switch := 0.0
var _inventory_open := false
var _fire_blocked := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_models = [_hammer_model(), _shotgun_model(), _bomb_model(), _launcher_model(), _torch_model(), _spray_model(), _extinguisher_model()]
	for m in _models:
		m.visible = false
		add_child(m)
		for c in m.get_children():
			if c is GeometryInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	select(HAMMER)


func select(i: int) -> void:
	i = wrapi(i, 0, NAMES.size())
	if i == current and _models[i].visible:
		return
	_models[current].visible = false
	current = i
	_models[current].position = BASE_POS + Vector3(0.02, -0.24, 0.06)
	_models[current].rotation = Vector3(0.32, -0.19, 0.14)
	_models[current].visible = true
	_switch = 1.0
	_swing = 0.0
	_recoil = 0.0
	_hammer_hit_pending = -1.0
	selection_changed.emit(current)


func set_inventory_open(opened: bool) -> void:
	_inventory_open = opened
	if opened:
		_hammer_hit_pending = -1.0
	else:
		_fire_blocked = true


func _unhandled_input(e: InputEvent) -> void:
	for k in NAMES.size():
		if e.is_action_pressed("tool_%d" % (k + 1)):
			select(k)
	if e is InputEventMouseButton and e.pressed:
		if player.grabbed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			player.grab_scroll(0.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(current - 1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(current + 1)
	if e is InputEventMouseMotion:
		_sway += e.relative * 0.0004


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_switch = maxf(_switch - delta * 4.4, 0.0)
	if _fire_blocked and not Input.is_action_pressed("fire") and not Input.is_action_just_pressed("fire"):
		_fire_blocked = false
	var captured := (
		input_enabled and not _inventory_open and not _fire_blocked
		and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or player.touch_mode)
	)
	var fire_pressed := captured and Input.is_action_just_pressed("fire")
	var fire_held := captured and (Input.is_action_pressed("fire") or fire_pressed)
	if sim_fire:
		fire_pressed = not _sim_was
		fire_held = true
	_sim_was = sim_fire
	if remote_tap:
		fire_pressed = true
		fire_held = true
		remote_tap = false

	if player.grabbed:
		if fire_pressed:
			player.release_grab(true)
		fire_pressed = false
		fire_held = false

	match current:
		HAMMER:
			if fire_held and _cooldown <= 0.0:
				_cooldown = 0.42
				_swing = 1.0
				if not mirror_only:
					_hammer_hit_pending = 0.11
		SHOTGUN:
			if fire_pressed and _cooldown <= 0.0:
				_cooldown = 0.75
				_fire_shotgun()
		PIPEBOMB:
			if fire_pressed and _cooldown <= 0.0:
				_cooldown = 0.5
				_throw_bomb()
		ROCKET:
			if fire_pressed and _cooldown <= 0.0:
				_cooldown = 1.1
				_fire_rocket()
	_continuous(TORCH, fire_held, delta, 0.05, _torch_tick, "torch")
	_continuous(SPRAY, fire_held, delta, 0.05, _spray_tick, "spray")
	_continuous(EXTINGUISHER, fire_held, delta, 0.06, _extinguish_tick, "spray")

	if _hammer_hit_pending > 0.0:
		_hammer_hit_pending -= delta
		if _hammer_hit_pending <= 0.0:
			_hammer_hit()
	_animate(delta)


func _continuous(tool: int, held: bool, delta: float, interval: float, fn: Callable, snd: String) -> void:
	var key := "tool_%d_%d" % [get_instance_id(), tool]
	var active := current == tool and held
	VoxelWorld.instance.sfx.loop(key, snd, global_position, active, -8.0 if tool == TORCH else -12.0)
	if not active:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = interval
		fn.call()


func muzzle_pos() -> Vector3:
	return global_transform * Vector3(0.24, -0.16, -0.75)


# ------------------------------------------------------------------ actions

func _hammer_hit() -> void:
	var hit := player.aim_ray(2.7)
	if hit.is_empty():
		return
	var obj := hit.collider as VoxelObject
	var w := VoxelWorld.instance
	if obj == null:
		return
	var vox := obj.voxel_at_hit(hit.position, hit.normal)
	var n := w.damage_at(obj, hit.position - hit.normal * 0.05, 0.33, 1.3, player.aim_dir() * 140.0, 0.3, 10)
	player.shake(0.15)
	var mat := VoxMat.material_of(vox) if vox > 0 else 0
	if n > 0:
		w.sfx.play("glass" if mat == VoxMat.GLASS else "hammer", hit.position, 0.0, _rng.randf_range(0.85, 1.1))
	elif mat == VoxMat.METAL or mat == VoxMat.HARDMETAL:
		w.sfx.play("metal", hit.position, -4.0, _rng.randf_range(0.9, 1.2))
		w.fx.sparks(hit.position, hit.normal)
	else:
		w.sfx.play("thud", hit.position, 0.0)
		w.fx.dust(hit.position, Color(0.7, 0.68, 0.64), 0.5)


func _fire_shotgun() -> void:
	var w := VoxelWorld.instance
	_recoil = 1.0
	player.shake(0.25)
	w.sfx.play("shotgun", global_position, 2.0, _rng.randf_range(0.95, 1.05))
	w.fx.muzzle(muzzle_pos(), player.aim_dir())
	if mirror_only:
		return
	var basis := player.camera.global_basis
	for i in 10:
		var spread := Vector2(_rng.randfn(0, 0.035), _rng.randfn(0, 0.035))
		var dir := (-basis.z + basis.x * spread.x + basis.y * spread.y).normalized()
		var from := player.camera.global_position
		var ex: Array[RID] = [player.get_rid()]
		var hit := w.raycast(from, from + dir * 90.0, Layers.SOLID, ex)
		if hit.is_empty():
			continue
		var obj := hit.collider as VoxelObject
		if obj:
			w.damage_at(obj, hit.position - hit.normal * 0.03, 0.15, 2.4, dir * 30.0, 0.35, 3)


func _throw_bomb() -> void:
	_swing = 0.6
	if mirror_only:
		VoxelWorld.instance.sfx.play("throw", global_position, -4.0)
		return
	var b := Projectiles.PipeBomb.new()
	VoxelWorld.instance.add_child(b)
	b.global_position = player.camera.global_position + player.aim_dir() * 0.6 + Vector3.DOWN * 0.1
	b.linear_velocity = player.aim_dir() * 11.0 + player.velocity * 0.5 + Vector3.UP * 1.5
	b.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
	VoxelWorld.instance.sfx.play("throw", b.global_position, -4.0)


func _fire_rocket() -> void:
	_recoil = 1.4
	player.shake(0.3)
	VoxelWorld.instance.sfx.play("rocket", muzzle_pos(), 2.0)
	if mirror_only:
		VoxelWorld.instance.fx.muzzle(muzzle_pos(), player.aim_dir())
		return
	var r := Projectiles.Rocket.new()
	r.shooter_rid = player.get_rid()
	VoxelWorld.instance.add_child(r)
	var dir := player.aim_dir()
	r.global_position = muzzle_pos()
	# Aim at what the crosshair points to, not parallel to the camera ray.
	var hit := player.aim_ray(300.0)
	if not hit.is_empty():
		dir = (hit.position - r.global_position).normalized()
	r.velocity = dir * 38.0
	r.look_at(r.global_position + dir, Vector3.UP)


func _torch_tick() -> void:
	var w := VoxelWorld.instance
	var hit := player.aim_ray(1.9)
	if hit.is_empty():
		return
	var obj := hit.collider as VoxelObject
	if obj == null:
		return
	w.fx.sparks(hit.position, hit.normal)
	w.fx.flash(hit.position + hit.normal * 0.1, Color(0.5, 0.75, 1.0), 2.5, 2.5, 0.08)
	if mirror_only:
		return
	w.damage_at(obj, hit.position - hit.normal * 0.06, 0.14, 9.0, Vector3.ZERO, 0.0, 0)
	if _rng.randf() < 0.12:
		w.fire.ignite_near(obj, hit.position, 0.25, 1)
	if is_instance_valid(obj):
		obj.paint(hit.position, 0.3, VoxMat.char_remap, 0.25)


func _spray_tick() -> void:
	var w := VoxelWorld.instance
	w.fx.spray(muzzle_pos(), player.aim_dir())
	if mirror_only:
		return
	var hit := player.aim_ray(5.0)
	if hit.is_empty():
		return
	var obj := hit.collider as VoxelObject
	if obj:
		obj.paint(hit.position - hit.normal * 0.05, 0.36, VoxMat.paint_remap, 0.55)


func _extinguish_tick() -> void:
	var w := VoxelWorld.instance
	var dir := player.aim_dir()
	w.fx.foam(muzzle_pos(), dir)
	if mirror_only:
		return
	var hit := player.aim_ray(7.0)
	var end: Vector3 = hit.position if not hit.is_empty() else player.camera.global_position + dir * 7.0
	var from := player.camera.global_position
	for k in 4:
		w.fire.extinguish(from.lerp(end, (k + 1) / 4.0), 1.2)


# ------------------------------------------------------------------ viewmodels

func _animate(delta: float) -> void:
	var m := _models[current]
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var t := Time.get_ticks_msec() * 0.001
	var bob := Vector3(sin(t * 7.0) * 0.008, absf(cos(t * 7.0)) * 0.01, 0) * clampf(hv / 5.0, 0, 1.4) if player.is_on_floor() else Vector3.ZERO
	var rise := _switch * _switch
	var pos := BASE_POS + bob + Vector3(-_sway.x, _sway.y, 0) + Vector3(0.02, -0.24, 0.06) * rise
	var rot := Vector3(0.32, -0.19, 0.14) * rise
	if _swing > 0.0:
		_swing = maxf(_swing - delta * 3.0, 0.0)
		var s := sin((1.0 - _swing) * PI)
		rot.x = -s * 1.4
		pos += Vector3(-0.08, 0.05, -0.12) * s
	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta * 6.0, 0.0)
		rot.x += _recoil * 0.25
		pos.z += _recoil * 0.08
	if current == TORCH and not _inventory_open and not _fire_blocked and Input.is_action_pressed("fire"):
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.002
	m.position = pos
	m.rotation = rot


func _wrap(mi: MeshInstance3D, offset: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	mi.position = offset
	mi.rotation = rot
	n.add_child(mi)
	return n


func _hammer_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(14, 34, 6))
	v.fill_planks(Vector3i(6, 0, 2), Vector3i(8, 28, 4), 1, 0, 1, VoxMat.ids("wood"), 3)
	v.fill_box(Vector3i(6, 0, 2), Vector3i(8, 6, 4), VoxMat.id("rubber"))
	v.fill_box(Vector3i(0, 26, 0), Vector3i(14, 33, 6), VoxMat.id("metal"))
	v.fill_box(Vector3i(0, 27, 1), Vector3i(14, 32, 5), VoxMat.id("metal_white"))
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(7, 6, 3)), Vector3.ZERO, Vector3(-0.35, 0.1, 0.25))


func _shotgun_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(4, 7, 34))
	v.fill_box(Vector3i(1, 4, 0), Vector3i(3, 6, 18), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(1, 2, 4), Vector3i(3, 4, 14), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(0, 3, 16), Vector3i(4, 7, 24), VoxMat.id("metal"))
	v.fill_planks(Vector3i(1, 0, 22), Vector3i(3, 6, 34), 2, 1, 2, VoxMat.ids("wood"), 9)
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(2, 4, 20)), Vector3(0, 0.02, 0))


func _bomb_model() -> Node3D:
	var n := Node3D.new()
	var mi := Projectiles.pipe_bomb_model()
	mi.rotation = Vector3(0.3, 0, -0.2)
	mi.scale = Vector3.ONE * 0.62
	mi.position = Vector3(0.02, 0.03, 0.0)
	n.add_child(mi)
	return n


func _launcher_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(8, 12, 44))
	v.fill_cylinder(Vector3(4, 8, 0), 3.6, 44, 2, VoxMat.id("metal_green"))
	v.fill_cylinder(Vector3(4, 8, 0), 2.2, 44, 2, 0)
	v.fill_cylinder(Vector3(4, 8, 0), 3.9, 3, 2, VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(3, 0, 24), Vector3i(5, 5, 28), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(1, 10, 18), Vector3i(7, 12, 22), VoxMat.id("metal_dark"))
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(4, 8, 26)), Vector3(0.0, 0.08, 0.05))


func _torch_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(8, 10, 26))
	v.fill_cylinder(Vector3(4, 4, 8), 3.6, 16, 2, VoxMat.id("metal_red"))
	v.fill_box(Vector3i(3, 3, 0), Vector3i(5, 5, 9), VoxMat.id("metal"))
	v.fill_box(Vector3i(3, 3, 0), Vector3i(5, 5, 2), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(3, 8, 10), Vector3i(5, 10, 14), VoxMat.id("metal_dark"))
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(4, 4, 14)), Vector3.ZERO)


func _spray_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(7, 16, 7))
	v.fill_cylinder(Vector3(3.5, 0, 3.5), 3.2, 12, 1, VoxMat.id("metal_yellow"))
	v.fill_cylinder(Vector3(3.5, 12, 3.5), 2.2, 3, 1, VoxMat.id("plastic_white"))
	v.fill_box(Vector3i(3, 14, 0), Vector3i(4, 15, 4), VoxMat.id("rubber"))
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(3, 6, 3)), Vector3(0, 0, 0), Vector3(-0.2, 0, 0))


func _extinguisher_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(9, 24, 14))
	v.fill_cylinder(Vector3(4.5, 0, 9.5), 4.2, 19, 1, VoxMat.id("metal_red"))
	v.fill_box(Vector3i(3, 19, 7), Vector3i(6, 22, 12), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(4, 20, 0), Vector3i(5, 21, 8), VoxMat.id("rubber"))
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(4, 10, 8)), Vector3(0, -0.04, 0), Vector3(-0.1, 0, 0))
