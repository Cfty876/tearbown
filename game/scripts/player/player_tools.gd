class_name PlayerTools
extends Node3D
## Tool belt attached to the camera: viewmodels, input handling and the effect of
## each tool on the voxel world.

enum { HAMMER, SHOTGUN, PIPEBOMB, ROCKET, SPRAY, EXTINGUISHER, BOARD, CLOTH, HORN, POSSESSOR, BOOMBOX }
const ALL_TOOLS: Array[int] = [HAMMER, SHOTGUN, PIPEBOMB, ROCKET, SPRAY, EXTINGUISHER, BOARD, CLOTH, HORN, BOOMBOX]
const HIDE_TOOLS: Array[int] = [SHOTGUN, SPRAY, BOARD, CLOTH, HORN, BOOMBOX]
const GADGET_START := BOOMBOX + 1
const NUMBERED_TOOLS := 9

const NAMES := ["Кувалда", "Дробовик", "Трубчатая бомба", "Ракетница", "Баллончик", "Огнетушитель", "Доска", "Полотно-хамелеон", "Гудок", "Резонатор", "Бумбокс"]
const HINTS := [
	"удар по прицелу, в том числе вниз по дороге",
	"широкий пробой дерева, бетона и стали",
	"бросок, взрыв через 3 с",
	"ракета, взрыв при попадании",
	"плотная узкая линия по поверхности",
	"тушит огонь · направь вниз для взлёта",
	"до 5 м · ЛКМ — две точки · колесо — ширина · Q/R — наклон",
	"ЛКМ — две точки · пропускает игрока, рвётся от выстрела",
	"короткий пространственный сигнал",
	"ЛКМ — вселиться в NPC в пределах 7,5 м",
	"ЛКМ — включить или выключить музыку",
]
const VS_MODEL := 0.019
const BASE_POS := Vector3(0.34, -0.3, -0.52)
const SHOTGUN_POWER := 1000000.0
const PAINT_RADIUS := 0.125
# The native brush retains 30% of the supplied chance at the rim.
const PAINT_COVERAGE := 3.4
const EXTINGUISHER_BURST := 2.8
const EXTINGUISHER_REFILL := 9.0

signal selection_changed(index: int)
signal slots_changed
signal horn_sounded(at: Vector3)

var player: Player
var _next_emitted_noise := 0
var input_enabled := true
## Scripted fire input for automated tests (bench --tools).
var sim_fire := false
var spraying := false
var remote_tap := false
var mirror_only := false
var utility_only := false
var room_tools := -1
var room_combat_locked := false
var hunt_tools_locked := false
var suppress_utility := false
var thrusting := false
var extinguisher_charge := 1.0
var _sim_was := false
var current := HAMMER
var previous := -1
var _last_standard := HAMMER
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
var _placement_anchor: VoxelObject
var _placement_point := Vector3.ZERO
var _placement_normal := Vector3.UP
var _placement_tint := Color.WHITE
var _placement_motif := 0
var _placement_material := VoxMat.NONE
var _placement_patch := ""
var _placement_tangent := Vector3.RIGHT
var _placement_up := Vector3.UP
var _placement_preview: MeshInstance3D
var _placement_width := 0.42
var _placement_roll := 0.0
var _last_paint := Vector3.INF
var _last_paint_object: VoxelObject
var boombox_view: BoomboxModel


func _ready() -> void:
	_models = [_hammer_model(), _shotgun_model(), _bomb_model(), _launcher_model(), _spray_model(), _extinguisher_model(),
		_board_model(), _cloth_model(), _horn_model(), Node3D.new(), _boombox_model()]
	for item in GameGadgets.TITLES.size():
		_models.append(Node3D.new())
	for m in _models:
		m.visible = false
		add_child(m)
		for c in m.get_children():
			if c is GeometryInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	select(HAMMER)


static func is_gadget(index: int) -> bool:
	return index >= GADGET_START


static func title_for(index: int) -> String:
	return GameGadgets.TITLES[index - GADGET_START] if is_gadget(index) else NAMES[index]


static func hint_for(index: int) -> String:
	return GameGadgets.TOOL_HINTS[index - GADGET_START] if is_gadget(index) else HINTS[index]


func gadget_charges(index: int) -> int:
	var world := VoxelWorld.instance
	if not is_gadget(index) or world.player != player or not is_instance_valid(world.gadgets):
		return 0
	return world.gadgets.inventories[world.gadgets.local_side][index - GADGET_START]


func tool_slots() -> Array[int]:
	var base := HIDE_TOOLS if utility_only else ALL_TOOLS
	var world := VoxelWorld.instance
	if not is_instance_valid(world) or not is_instance_valid(world.gadgets):
		return base
	var slots: Array[int] = base.duplicate()
	if world.player == player and is_instance_valid(world.boombox) and world.boombox.is_placed():
		slots.erase(BOOMBOX)
	if world.player == player and is_instance_valid(world.population) and world.population.local_allowed:
		slots.append(POSSESSOR)
	if room_tools >= 0:
		slots = slots.filter(func(id: int): return (room_tools & (1 << id)) != 0)
	if slots.is_empty():
		slots.append(HAMMER)
	for item in GameGadgets.TITLES.size():
		if world.player == player and gadget_charges(GADGET_START + item) > 0:
			slots.append(GADGET_START + item)
	return slots


func refresh_slots() -> void:
	var available := tool_slots()
	if current not in available:
		var fallback := previous
		if fallback not in available:
			fallback = _last_standard if _last_standard in available else available[0]
		select(fallback)
		_fire_blocked = Input.is_action_pressed("fire")
	if previous not in available:
		previous = -1
	slots_changed.emit()


func slot_label(index: int, slots: Array[int] = []) -> String:
	var ordered := tool_slots() if slots.is_empty() else slots
	return "%02d" % (ordered.find(index) + 1)


func _cycle_tool(step: int) -> void:
	var slots := tool_slots()
	select(slots[posmod(slots.find(current) + step, slots.size())])


func select(i: int) -> void:
	var available := tool_slots()
	if i not in available:
		return
	if i == current and _models[i].visible:
		return
	cancel_placement()
	if _models[current].visible:
		previous = current if current in available else -1
	_models[current].visible = false
	current = i
	if is_gadget(i):
		if _models[i].get_child_count() == 0:
			_models[i].add_child(VoxelWorld.instance.gadgets.viewmodel(i - GADGET_START))
	else:
		_last_standard = i
		if i == POSSESSOR and _models[i].get_child_count() == 0:
			_models[i].add_child(_possessor_model())
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
	if not input_enabled or not (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or player.touch_mode):
		return
	if e.is_action_pressed("previous_tool") and previous >= 0:
		select(previous)
		get_viewport().set_input_as_handled()
		return
	if current == BOOMBOX and e.is_action_pressed("cassette_library") and not player.dead and not player.vehicle and not suppress_utility and not _inventory_open:
		VoxelWorld.instance.boombox.open_library()
		get_viewport().set_input_as_handled()
		return
	if current == BOOMBOX and e.is_action_pressed("place_boombox") and not suppress_utility and not _inventory_open and not player.navigation_menu_open:
		VoxelWorld.instance.boombox.place()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_placement_preview):
		if e.is_action_pressed("build_rotate_left") or e.is_action_pressed("build_rotate_right"):
			_placement_roll += deg_to_rad(15.0) * (-1 if e.is_action_pressed("build_rotate_left") else 1)
			get_viewport().set_input_as_handled()
			return
		if e is InputEventMouseButton and e.pressed:
			match e.button_index:
				MOUSE_BUTTON_RIGHT: cancel_placement()
				MOUSE_BUTTON_WHEEL_UP: _resize_placement(0.1)
				MOUSE_BUTTON_WHEEL_DOWN: _resize_placement(-0.1)
				_: return
			get_viewport().set_input_as_handled()
			return
	for k in NUMBERED_TOOLS:
		if e.is_action_pressed("tool_%d" % (k + 1)):
			select(k)
	if e is InputEventMouseButton and e.pressed:
		if player.grabbed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			player.grab_scroll(0.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_tool(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_tool(1)
	if e is InputEventMouseMotion:
		_sway += e.relative * 0.0004


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_switch = maxf(_switch - delta * 4.4, 0.0)
	if _fire_blocked and not Input.is_action_pressed("fire") and not Input.is_action_just_pressed("fire"):
		_fire_blocked = false
	var captured := (
		input_enabled and not _inventory_open and not _fire_blocked
		and not player.navigation_menu_open and not player.transit_active
		and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or player.touch_mode)
	)
	var fire_pressed := captured and Input.is_action_just_pressed("fire")
	var fire_held := captured and (Input.is_action_pressed("fire") or fire_pressed)
	if sim_fire:
		fire_pressed = not _sim_was
		fire_held = true
	_sim_was = sim_fire
	if not captured and not sim_fire and not remote_tap:
		_hammer_hit_pending = -1.0
	if remote_tap:
		fire_pressed = true
		fire_held = true
		remote_tap = false

	if player.grabbed:
		if fire_pressed:
			player.release_grab(true)
		fire_pressed = false
		fire_held = false
	if (room_combat_locked and current in [HAMMER, SHOTGUN, PIPEBOMB, ROCKET]) or player.dead or player.clock_locked() or player.vehicle or is_instance_valid(player.possessed_npc) or (player.hide_spot >= 0 and current not in [HORN, BOOMBOX]) or (hunt_tools_locked and current in [SHOTGUN, SPRAY]):
		fire_pressed = false
		fire_held = false
	if current != EXTINGUISHER or player.vehicle:
		extinguisher_charge = minf(1.0, extinguisher_charge + delta / EXTINGUISHER_REFILL)
	elif fire_held:
		fire_held = extinguisher_charge > 0.0
		if fire_held:
			extinguisher_charge = maxf(0.0, extinguisher_charge - delta / EXTINGUISHER_BURST)
	thrusting = current == EXTINGUISHER and fire_held and not suppress_utility
	if fire_held and current in [SPRAY, EXTINGUISHER] and Time.get_ticks_msec() >= _next_emitted_noise:
		_next_emitted_noise = Time.get_ticks_msec() + 650
		player.sound_emitted.emit(player.global_position, 15.0 if current == SPRAY else 18.0,
			"spray" if current == SPRAY else "foam")

	match current:
		HAMMER:
			if fire_held and _cooldown <= 0.0:
				_cooldown = 0.42
				_swing = 1.0
				if not mirror_only:
					_hammer_hit_pending = 0.16
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
		BOARD, CLOTH:
			if fire_pressed and not suppress_utility:
				_place_action()
		HORN:
			if fire_pressed and _cooldown <= 0.0 and not suppress_utility:
				_cooldown = 1.6
				_recoil = 0.25
				var at := player.global_position + Vector3.UP * 1.3
				VoxelWorld.instance.sfx.play_horn(at, true)
				horn_sounded.emit(at)
				player.sound_emitted.emit(at, 58.0, "horn")
		POSSESSOR:
			if fire_pressed and not suppress_utility and _cooldown <= 0.0 and is_instance_valid(VoxelWorld.instance.population):
				_cooldown = 0.55
				_recoil = 0.34
				VoxelWorld.instance.population.fire_tool(player)
		BOOMBOX:
			var box := VoxelWorld.instance.boombox
			if is_instance_valid(box):
				boombox_view.meter(box.local.playing, box.local_bands, box.on_air())
				if fire_pressed and not suppress_utility and _cooldown <= 0.0:
					_cooldown = 0.32
					_recoil = 0.22
					box.toggle()
		_:
			if fire_pressed and is_gadget(current) and not suppress_utility:
				_swing = 0.38
				VoxelWorld.instance.gadgets.use(current - GADGET_START)
	if current != SPRAY or not fire_held:
		_last_paint = Vector3.INF
	_continuous(SPRAY, fire_held, delta, 0.038, _spray_tick, "spray")
	_continuous(EXTINGUISHER, fire_held, delta, 0.065, _extinguish_tick, "extinguisher")
	if is_instance_valid(_placement_preview):
		_placement_preview.global_transform = _placement_transform()

	if room_combat_locked:
		_hammer_hit_pending = -1.0
	if _hammer_hit_pending > 0.0:
		_hammer_hit_pending -= delta
		if _hammer_hit_pending <= 0.0:
			_hammer_hit()
	_animate(delta)


func _continuous(tool: int, held: bool, delta: float, interval: float, fn: Callable, snd: String) -> void:
	var key := "tool_%d_%d" % [get_instance_id(), tool]
	var active := current == tool and held
	if tool == SPRAY:
		spraying = active
	var volume := (0.0 if suppress_utility else -10.0) if tool == SPRAY else -12.0
	VoxelWorld.instance.sfx.loop(key, snd, player.global_position + Vector3.UP * 1.3, active, volume)
	if not active:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = interval
		fn.call()


func muzzle_pos() -> Vector3:
	var model := _models[current].get_child(0) as Node3D
	match current:
		SHOTGUN: return model.to_global(Vector3(0.0, 0.049, -0.504))
		ROCKET: return model.to_global(Vector3(0.0, 0.0, -0.494))
		SPRAY: return model.to_global(Vector3(0.0, 0.195, -0.065))
		EXTINGUISHER: return model.to_global(Vector3(0.0, 0.221, -0.260))
	return global_transform * Vector3(0.25, -0.17, -0.78)


# ------------------------------------------------------------------ actions

func _hammer_hit() -> void:
	var w := VoxelWorld.instance
	var from := player.camera.global_position
	var to := from + player.aim_dir() * 3.25
	var mask := Layers.SOLID | Layers.CLOTH | Layers.SECRET
	var hit := w.population.trace(from, to, mask, [player.get_rid()]) if is_instance_valid(w.population) else player.aim_ray(3.25, mask)
	var struck := {}
	if _combat_impact(from, to if hit.is_empty() else hit.position, struck):
		return
	if hit.is_empty():
		return
	if hit.collider is SchoolNpc:
		w.population.weapon_hit(hit.collider, player, HAMMER, from)
		return
	var obj := hit.collider as VoxelObject
	if is_instance_valid(w.secrets) and w.secrets.hit_target(hit, false, player):
		return
	if hit.collider is ToolConstruction.FabricSurface:
		hit.collider.strike()
		return
	if obj == null:
		return
	var vox := obj.voxel_at_hit(hit.position, hit.normal)
	var mat := VoxMat.material_of(vox) if vox > 0 else 0
	if mat == VoxMat.GLASS:
		w.damage_glass(obj, hit.position, hit.normal, false)
		player.shake(0.11)
		return
	var downward: bool = hit.normal.y > 0.52 and player.aim_dir().y < -0.36
	var traps: SchoolTraps = w.secrets.traps if w.secrets is SchoolSecrets else null
	var power := (7.0 if downward else 3.4) * (traps.hammer_multiplier() if traps else 1.0)
	var n := w.damage_at(obj, hit.position - hit.normal * (0.18 if downward else 0.09),
		0.5 if downward else 0.38, power, player.aim_dir() * 160.0, 0.28, 12)
	player.shake(0.15)
	if n > 0:
		if traps:
			traps.spend_hammer_boost()
		w.sfx.play("glass" if mat == VoxMat.GLASS else "hammer", hit.position, 0.0, _rng.randf_range(0.85, 1.1))
	elif mat == VoxMat.METAL or mat == VoxMat.HARDMETAL:
		w.sfx.play("metal", hit.position, -4.0, _rng.randf_range(0.9, 1.2))
		w.fx.sparks(hit.position, hit.normal)
	else:
		w.sfx.play("thud", hit.position, 0.0)
		w.fx.dust(hit.position, Color(0.7, 0.68, 0.64), 0.5)
	player.sound_emitted.emit(hit.position, 21.0, "impact")


func _combat_impact(from: Vector3, to: Vector3, struck: Dictionary) -> bool:
	var world := VoxelWorld.instance
	var match_room := world.get_parent().get_node_or_null("NetworkHide") as NetworkHide
	if is_instance_valid(match_room):
		var hit := match_room.combat_trace(player, from, to)
		if not hit.is_empty():
			var side := int(hit.side)
			if not struck.has(side):
				struck[side] = true
				match_room.combat_damage(player, side, current, from)
			return true
	elif is_instance_valid(player.bot_hunt) and player.bot_hunt.combat_trace(from, to).is_finite():
		if not struck.has(0):
			struck[0] = true
			player.bot_hunt.take_weapon_hit(current, from)
		return true
	return false


func _attack_round() -> int:
	var room := VoxelWorld.instance.get_parent().get_node_or_null("NetworkHide") as NetworkHide
	return room._round if is_instance_valid(room) else -1


func _fire_shotgun() -> void:
	var w := VoxelWorld.instance
	_recoil = 1.0
	player.shake(0.25)
	w.sfx.play("shotgun", global_position, 2.0, _rng.randf_range(0.95, 1.05))
	player.sound_emitted.emit(global_position, 47.0, "shot")
	w.fx.muzzle(muzzle_pos(), player.aim_dir())
	if mirror_only:
		return
	var basis := player.camera.global_basis
	var glass_hit := false
	var secret_hits := {}
	var people_hit := {}
	var population := w.population
	for i in 5:
		var spread := Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * (i - 1) / 4.0) * 0.045
		var dir := (-basis.z + basis.x * spread.x + basis.y * spread.y).normalized()
		var from := player.camera.global_position
		var ex: Array[RID] = [player.get_rid()]
		var mask := Layers.SOLID | Layers.CLOTH | Layers.SECRET | Layers.BOOMBOX
		if is_instance_valid(w.boombox):
			var own_box := w.boombox.shooter_box(player)
			if is_instance_valid(own_box):
				ex.append(own_box.get_rid())
		var to := from + dir * 45.0
		var hit := population.trace(from, to, mask, ex) if is_instance_valid(population) else w.raycast(from, to, mask, ex)
		if _combat_impact(from, to if hit.is_empty() else hit.position, people_hit):
			continue
		if hit.is_empty():
			continue
		var collider: Object = hit.collider
		if collider is StaticBody3D and collider.collision_layer == Layers.BOOMBOX:
			w.boombox.shotgun_hit(collider, player)
			continue
		if collider is SchoolNpc:
			if not secret_hits.has(collider):
				secret_hits[collider] = true
				var holder: int = collider.holder
				if holder < 0 or not people_hit.has(holder):
					population.weapon_hit(collider, player, SHOTGUN, from)
					if holder >= 0:
						people_hit[holder] = true
			continue
		if is_instance_valid(w.gadgets) and w.gadgets.is_dispenser_hit(hit):
			if not secret_hits.has(collider):
				secret_hits[collider] = true
				w.gadgets.shoot_dispenser(player, hit)
			continue
		if is_instance_valid(w.secrets):
			if secret_hits.has(collider):
				continue
			if w.secrets.hit_target(hit, true, player):
				secret_hits[collider] = true
				continue
		if hit.collider is ToolConstruction.FabricSurface:
			hit.collider.strike()
			continue
		if utility_only:
			continue
		var obj := hit.collider as VoxelObject
		if obj:
			if VoxMat.material_of(obj.voxel_at_hit(hit.position, hit.normal)) == VoxMat.GLASS:
				if not glass_hit:
					w.damage_glass(obj, hit.position, hit.normal, true)
					glass_hit = true
				continue
			var center: Vector3 = hit.position - hit.normal * (0.20 if i == 0 else 0.08)
			w.damage_at(obj, center, 0.43 if i == 0 else 0.17, SHOTGUN_POWER, dir * 58.0, 0.26, 8 if i == 0 else 2)
			if i == 0 and GameState.cinematic_fx:
				w.fx.sparks(hit.position, hit.normal)


func _throw_bomb() -> void:
	_swing = 0.6
	if mirror_only:
		VoxelWorld.instance.sfx.play("throw", global_position, -4.0)
		return
	var b := Projectiles.PipeBomb.new()
	b.source = player
	b.attack_round = _attack_round()
	VoxelWorld.instance.add_child(b)
	b.global_position = player.camera.global_position + player.aim_dir() * 0.6 + Vector3.DOWN * 0.1
	b.linear_velocity = player.aim_dir() * 11.0 + player.velocity * 0.5 + Vector3.UP * 1.5
	b.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
	VoxelWorld.instance.sfx.play("throw", b.global_position, -4.0)


func _fire_rocket() -> void:
	_recoil = 1.4
	player.shake(0.3)
	VoxelWorld.instance.sfx.play("rocket", muzzle_pos(), 2.0)
	player.sound_emitted.emit(muzzle_pos(), 48.0, "shot")
	VoxelWorld.instance.fx.muzzle(muzzle_pos(), player.aim_dir(), true)
	if mirror_only:
		return
	var r := Projectiles.Rocket.new()
	r.source = player
	r.attack_round = _attack_round()
	r.shooter_rid = player.get_rid()
	VoxelWorld.instance.add_child(r)
	var dir := player.aim_dir()
	r.global_position = muzzle_pos()
	# Aim at what the crosshair points to, not parallel to the camera ray.
	var hitscan := player.camera.global_position
	var hit := player.aim_ray(300.0)
	var target: Vector3 = hit.get("position", hitscan + dir * 300.0)
	var room := VoxelWorld.instance.get_parent().get_node_or_null("NetworkHide") as NetworkHide
	if is_instance_valid(room):
		target = room.combat_trace(player, hitscan, target).get("at", target)
	elif is_instance_valid(player.bot_hunt):
		var located := player.bot_hunt.combat_trace(hitscan, target)
		if located.is_finite():
			target = located
	if not hit.is_empty() or target.distance_squared_to(hitscan) < 89999.0:
		if (target - r.global_position).dot(dir) < 0.04:
			r.global_position = target - dir * 0.14
		dir = (target - r.global_position).normalized()
	r.velocity = dir * 38.0
	r.look_at(r.global_position + dir, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)


func _spray_tick() -> void:
	var w := VoxelWorld.instance
	var hit := player.aim_ray(5.0)
	if hit.is_empty() or not hit.collider is VoxelObject:
		_last_paint = Vector3.INF
		return
	if not suppress_utility and player.camera.global_position.distance_squared_to(hit.position) > 0.85 * 0.85:
		w.fx.spray(hit.position, hit.normal)
	if mirror_only and not utility_only:
		return
	var obj := hit.collider as VoxelObject
	var at: Vector3 = hit.position - hit.normal * 0.035
	if _last_paint_object == obj and _last_paint.is_finite() and _last_paint.distance_to(at) < 0.65:
		var steps := clampi(ceili(_last_paint.distance_to(at) / 0.075), 1, 9)
		for i in range(1, steps):
			obj.paint(_last_paint.lerp(at, float(i) / steps), PAINT_RADIUS, VoxMat.paint_remap, PAINT_COVERAGE)
	obj.paint(at, PAINT_RADIUS, VoxMat.paint_remap, PAINT_COVERAGE)
	_last_paint = at
	_last_paint_object = obj


func _extinguish_tick() -> void:
	var w := VoxelWorld.instance
	var dir := player.aim_dir()
	w.fx.foam(muzzle_pos(), dir)
	if mirror_only:
		return
	var hit := player.aim_ray(7.0)
	var end: Vector3 = hit.position if not hit.is_empty() else player.camera.global_position + dir * 7.0
	var from := player.camera.global_position
	w.fire.extinguish_jet(from, end, dir)


# ------------------------------------------------------------------ construction

func cancel_placement() -> void:
	if is_instance_valid(_placement_preview):
		_placement_preview.queue_free()
	_placement_preview = null
	_placement_anchor = null


func _resize_placement(amount: float) -> void:
	var fabric := current == CLOTH
	_placement_width = clampf(_placement_width + amount, 0.25 if not fabric else 0.8, ToolConstruction.MAX_BOARD_WIDTH if not fabric else 2.8)


func _place_action() -> void:
	var w := VoxelWorld.instance
	var fabric := current == CLOTH
	if is_instance_valid(_placement_preview):
		var xf := _placement_transform()
		var mapping := _pattern_mapping(xf) if fabric and not _placement_patch.is_empty() else []
		if w.construction.submit(fabric, xf, _placement_tint, _placement_anchor, player.global_position,
				_placement_motif, _placement_patch, mapping, _placement_material):
			cancel_placement()
		else:
			get_tree().call_group("hud", "message", "Уведи край от себя и от первой точки", 2.0)
		return
	var hit := player.aim_ray(ToolConstruction.RANGE)
	if hit.is_empty():
		get_tree().call_group("hud", "message", "Наведи прицел на поверхность для первой точки", 2.0)
		return
	_placement_anchor = hit.collider as VoxelObject
	_placement_point = hit.position
	_placement_normal = hit.normal
	_placement_tint = Color("#a99b85")
	_placement_motif = 0
	_placement_material = VoxMat.NONE
	_placement_patch = ""
	if is_instance_valid(_placement_anchor):
		var voxel := _placement_anchor.voxel_at_hit(hit.position, hit.normal)
		if voxel > 0:
			_placement_tint = VoxMat.color_of(voxel)
			if fabric:
				_placement_motif = VoxMat.palette.get_pattern(voxel)
				_placement_material = VoxMat.material_of(voxel)
				_placement_patch = _sample_pattern(hit.position, hit.normal)
				var inverse := _placement_anchor.global_basis.inverse()
				_placement_tangent = inverse * _placement_tangent
				_placement_up = inverse * _placement_up
		_placement_point = _placement_anchor.to_local(_placement_point)
		_placement_normal = _placement_anchor.global_basis.inverse() * _placement_normal
	_placement_width = 1.65 if fabric else 0.34
	_placement_roll = 0.0
	_placement_preview = MeshInstance3D.new()
	_placement_preview.mesh = QuadMesh.new() if fabric else BoxMesh.new()
	_placement_preview.material_override = w.construction.preview_material(fabric, _placement_tint)
	_placement_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(_placement_preview)
	_placement_preview.global_transform = _placement_transform()
	w.sfx.play_ui("click", -11.0)
	get_tree().call_group("hud", "message", "ЛКМ — закрепить   ·   колесо — ширина   ·   %s/%s — наклон   ·   ПКМ — отмена" %
		[GameControls.key_name("build_rotate_left"), GameControls.key_name("build_rotate_right")], 5.0)


func _placement_transform() -> Transform3D:
	var first := _placement_point
	var normal := _placement_normal
	if is_instance_valid(_placement_anchor):
		first = _placement_anchor.to_global(first)
		normal = (_placement_anchor.global_basis * normal).normalized()
	var hit := player.aim_ray(ToolConstruction.RANGE)
	var endpoint: Vector3 = hit.get("position", player.camera.global_position + player.aim_dir() * ToolConstruction.RANGE)
	var max_length := ToolConstruction.MAX_LENGTH if current == CLOTH else ToolConstruction.MAX_BOARD_LENGTH
	var last := first + (endpoint - first).limit_length(max_length)
	return ToolConstruction.shape_between(first, last, normal, _placement_width, _placement_roll)


func _sample_pattern(at: Vector3, normal: Vector3) -> String:
	var axis := Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
	var tangent := axis.cross(normal).normalized()
	var up := normal.cross(tangent).normalized()
	_placement_tangent = tangent
	_placement_up = up
	return ToolConstruction.sample_patch(_placement_anchor, at, normal, tangent, up, _placement_tint)


func _pattern_mapping(xf: Transform3D) -> Array:
	if not is_instance_valid(_placement_anchor):
		return []
	var basis := xf.basis.orthonormalized()
	var u := (_placement_anchor.global_basis * _placement_tangent).normalized()
	var v := (_placement_anchor.global_basis * _placement_up).normalized()
	var offset := xf.origin - _placement_anchor.to_global(_placement_point)
	return [basis.x.dot(u), basis.y.dot(u), basis.x.dot(v), basis.y.dot(v), offset.dot(u), offset.dot(v)]


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
	if current == BOOMBOX:
		var inspect := boombox_view.insertion_pose()
		pos += Vector3(-0.11, 0.14, -0.06) * inspect
		rot.x -= 0.13 * inspect
	if _swing > 0.0:
		_swing = maxf(_swing - delta * 3.0, 0.0)
		var phase := 1.0 - _swing
		if current == HAMMER:
			var draw_back := smoothstep(0.0, 0.23, phase) * (1.0 - smoothstep(0.25, 0.47, phase))
			var impact := smoothstep(0.23, 0.48, phase) * (1.0 - smoothstep(0.53, 1.0, phase))
			rot += Vector3(draw_back * 0.65 - impact * 1.46, -impact * 0.27, draw_back * 0.18 - impact * 0.28)
			pos += Vector3(-0.19, 0.10, -0.19) * impact
		else:
			var s := sin(phase * PI)
			rot.x = -s * 1.4
			pos += Vector3(-0.08, 0.05, -0.12) * s
	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta * 6.0, 0.0)
		rot.x += _recoil * 0.25
		pos.z += _recoil * 0.08
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
	var v := VoxModel.volume(Vector3i(9, 14, 57))
	var dark := VoxMat.id("metal_dark")
	var steel := VoxMat.id("metal")
	v.fill_cylinder(Vector3(4.5, 10.5, 0), 2.6, 39, 2, dark)
	v.fill_cylinder(Vector3(4.5, 10.5, 0), 1.55, 4, 2, 0)
	v.fill_cylinder(Vector3(4.5, 6.6, 6), 1.8, 23, 2, steel)
	v.fill_box(Vector3i(1, 5, 29), Vector3i(8, 12, 42), steel)
	v.fill_box(Vector3i(7, 8, 32), Vector3i(8, 11, 38), dark)
	v.fill_box(Vector3i(4, 13, 1), Vector3i(5, 14, 3), VoxMat.id("road_yellow"))
	v.fill_box(Vector3i(2, 2, 32), Vector3i(3, 6, 38), dark)
	v.fill_box(Vector3i(2, 2, 34), Vector3i(7, 3, 38), dark)
	v.fill_planks(Vector3i(1, 4, 12), Vector3i(8, 9, 25), 2, 1, 2, VoxMat.ids("wood_dark"), 9)
	for z in range(14, 25, 3):
		v.fill_box(Vector3i(1, 4, z), Vector3i(8, 5, z + 1), dark)
	v.fill_planks(Vector3i(2, 1, 41), Vector3i(7, 9, 57), 2, 1, 2, VoxMat.ids("wood"), 7)
	v.fill_box(Vector3i(2, 0, 55), Vector3i(7, 9, 57), VoxMat.id("rubber"))
	return _wrap(VoxModel.instance(v, 0.014, Vector3(4.5, 7, 36)), Vector3(0, 0.02, 0))


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


func _spray_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(14, 29, 15))
	var teal := VoxMat.id("metal_teal")
	var steel := VoxMat.id("metal_white")
	var dark := VoxMat.id("metal_dark")
	v.fill_cylinder(Vector3(7, 0, 8), 6.5, 23, 1, teal)
	v.fill_cylinder(Vector3(7, 0, 8), 6.8, 2, 1, steel)
	v.fill_cylinder(Vector3(7, 21, 8), 6.6, 2, 1, steel)
	v.fill_cylinder(Vector3(7, 23, 8), 4.8, 3, 1, steel)
	v.fill_cylinder(Vector3(7, 25, 8), 2.6, 4, 1, VoxMat.id("plastic_white"))
	v.fill_box(Vector3i(6, 26, 3), Vector3i(8, 28, 7), dark)
	v.fill_box(Vector3i(2, 7, 11), Vector3i(12, 17, 13), VoxMat.id("pvc"))
	v.fill_box(Vector3i(2, 8, 12), Vector3i(12, 11, 13), VoxMat.id("road_yellow"))
	for y in [12, 14]:
		v.fill_box(Vector3i(4, y, 12), Vector3i(10, y + 1, 13), dark)
	return _wrap(VoxModel.instance(v, 0.013, Vector3(7, 12, 8)), Vector3.ZERO, Vector3(-0.20, 0.10, 0.15))


func _extinguisher_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(22, 38, 32))
	var red := VoxMat.id("metal_red")
	var rubber := VoxMat.id("rubber")
	var white := VoxMat.id("pvc")
	var steel := VoxMat.id("metal")
	v.fill_cylinder(Vector3(11, 2, 21), 8.8, 26, 1, red)
	v.fill_cylinder(Vector3(11, 0, 21), 9.1, 4, 1, rubber)
	v.fill_cylinder(Vector3(11, 27, 21), 7.2, 3, 1, red)
	v.fill_cylinder(Vector3(11, 30, 21), 4.6, 3, 1, red)
	v.fill_box(Vector3i(8, 32, 18), Vector3i(15, 35, 24), steel)
	v.fill_box(Vector3i(8, 35, 20), Vector3i(14, 37, 30), rubber)
	v.fill_box(Vector3i(10, 34, 7), Vector3i(13, 36, 19), rubber)
	v.fill_box(Vector3i(8, 32, 0), Vector3i(15, 37, 8), rubber)
	v.fill_box(Vector3i(9, 33, 0), Vector3i(14, 36, 2), 0)
	v.fill_box(Vector3i(13, 33, 23), Vector3i(19, 35, 25), VoxMat.id("road_yellow"))
	v.fill_box(Vector3i(5, 10, 26), Vector3i(17, 21, 29), white)
	v.fill_box(Vector3i(6, 18, 28), Vector3i(16, 20, 29), red)
	for y in [11, 13, 15]:
		v.fill_box(Vector3i(7, y, 28), Vector3i(15, y + 1, 29), rubber)
	return _wrap(VoxModel.instance(v, 0.013, Vector3(11, 17, 20)), Vector3(0, -0.035, 0), Vector3(-0.20, -0.12, 0.09))


func _board_model() -> Node3D:
	var v := ToolConstruction.board_volume(Vector3i(10, 33, 4))
	return _wrap(VoxModel.instance(v, VS_MODEL, Vector3(5, 22, 2)), Vector3.ZERO, Vector3(PI * 0.5 - 0.17, 0.22, 0.24))


func _cloth_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(13, 14, 24))
	v.fill_cylinder(Vector3(6.5, 7, 0), 6.0, 24, 2, VoxMat.id("awning_green"))
	v.fill_cylinder(Vector3(6.5, 7, 0), 2.6, 24, 2, VoxMat.id("curtain_beige"))
	v.fill_cylinder(Vector3(6.5, 7, 0), 1.2, 24, 2, 0)
	for z in [3, 18]:
		v.fill_cylinder(Vector3(6.5, 7, z), 6.2, 2, 2, VoxMat.id("rubber"))
	return _wrap(VoxModel.instance(v, 0.015, Vector3(6.5, 7, 14)), Vector3.ZERO, Vector3(-0.23, 0.27, 0.16))


func _horn_model() -> Node3D:
	var v := VoxModel.volume(Vector3i(15, 21, 24))
	var red := VoxMat.id("metal_red")
	var brass := VoxMat.id("metal_yellow")
	v.fill_cylinder(Vector3(7.5, 0, 16), 5.5, 13, 1, red)
	v.fill_cylinder(Vector3(7.5, 12, 16), 3.6, 5, 1, VoxMat.id("metal"))
	for z in 17:
		var radius := lerpf(7.0, 2.1, float(z) / 16.0)
		v.fill_cylinder(Vector3(7.5, 14, z), radius, 1, 2, brass)
		if z < 13:
			v.fill_cylinder(Vector3(7.5, 14, z), radius - 1.25, 1, 2, 0)
	return _wrap(VoxModel.instance(v, 0.016, Vector3(7.5, 8, 17)), Vector3.ZERO, Vector3(-0.18, 0.11, 0.0))


func _boombox_model() -> Node3D:
	var wrap := Node3D.new()
	boombox_view = BoomboxModel.new()
	boombox_view.held = true
	boombox_view.position = Vector3(-0.09, 0.025, -0.04)
	boombox_view.rotation = Vector3(0.13, 0.20, 0.04)
	wrap.add_child(boombox_view)
	return wrap


func _possessor_model() -> Node3D:
	var volume := Build.vol(Vector3i(16, 24, 35))
	var at := SchoolLevel.box
	at.call(volume, Vector3i(3, 10, 5), Vector3i(10, 8, 24), "metal_dark")
	at.call(volume, Vector3i(5, 1, 20), Vector3i(6, 11, 6), "rubber")
	at.call(volume, Vector3i(4, 10, 23), Vector3i(8, 9, 6), "metal_teal")
	at.call(volume, Vector3i(4, 19, 16), Vector3i(8, 2, 9), "metal")
	at.call(volume, Vector3i(5, 21, 17), Vector3i(6, 1, 7), "glass")
	at.call(volume, Vector3i(6, 22, 19), Vector3i(4, 1, 3), "lamp")
	for x in [2, 12]:
		at.call(volume, Vector3i(x, 12, 0), Vector3i(2, 4, 18), "metal_teal")
		at.call(volume, Vector3i(x, 13, 0), Vector3i(2, 2, 3), "lamp")
	for z in [8, 12, 16, 20]:
		at.call(volume, Vector3i(12, 13, z), Vector3i(2, 3, 1), "metal_yellow")
	return _wrap(VoxModel.instance(volume, 0.014, Vector3(8, 12, 25)), Vector3.ZERO, Vector3(-0.12, 0.12, 0.03))
