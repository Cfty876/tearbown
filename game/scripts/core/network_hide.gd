class_name NetworkHide
extends Node

const FINISH_SECONDS := 5.0
const MAX_VOLUME := 1000000
const POSE_PAYLOAD_BYTES := 1150
var player: Player
var world: VoxelWorld
var pause_menu: PauseMenu
var transit: DistrictTransit
var school: SchoolLevel
var hud: Hud
var starts: Array[Vector3] = []
var weapons_enabled := true
var rules: Dictionary
var _actors: Dictionary[int, RoomActor] = {}
var _seekers: Array[int] = []
var _found: Array[int] = []
var _health: Array[int] = []
var _stun_until: Array[int] = []
var _next_seekers: Array[int] = []
var _stage: RoomRoundUi
var _match_started := false
var _win_seekers := false
var _barrier: RoomBarrier
var _ready_sides := {}
var _spawn_points: Array[Vector3] = []
var _bot: SchoolHideMatch
var _bot_chat: SchoolBotChat
var _bot_replica: RoomActor
var _bot_prepare_running := false
var _bot_reply_active := false
var _bot_conversations := {}
var _guest_bot_answer := ""
var _guest_question_round := -1
var _voice: DistrictVoice
var _dynamic := {}
var _phase := "wait"
var _remaining := 0.0
var _deadline_ms := 0
var _unlock_at := 0
var _round := 0
var _result := ""
var _pose_timer := 0.0
var _pose_serial := 0
var _state_timer := 0.0
var _fire_timer := 0.0
var _last_process_ms := 0
var _fire_visible := false
var _fire_last := false
var _tool_last := -1
var _layout_seed := -1
var _board: RoundBoard
var _sync_requested_at := {}
var _npc_timer := 0.0


func _ready() -> void:
	rules = WebSession.rules.duplicate()
	_health.resize(RoomRules.SIDES)
	_health.fill(100)
	_stun_until.resize(RoomRules.SIDES)
	_stun_until.fill(0)
	_pick_teams(1)
	_stage = RoomRoundUi.new()
	_stage.room = self
	add_child(_stage)
	player.god_mode = true
	player.interaction_enabled = false
	player.tools.mirror_only = not WebSession.is_host
	player.tools.input_enabled = false
	player.tools.utility_only = not weapons_enabled
	player.tools.horn_sounded.connect(func(at: Vector3):
		var data := {"k": "horn", "p": _pack(at), "round": _round}
		WebSession.send(data))
	world.construction.network_enabled = true
	world.gadgets.map_data.ping_requested.connect(func(at: Vector2, floor_id: int):
		if _can_act(WebSession.local_side):
			WebSession.send({"k": "map_ping", "x": at.x, "z": at.y, "floor": floor_id, "round": _round}))
	world.gadgets.requested.connect(_local_gadget)
	world.gadgets.confirmed.connect(func(event: Dictionary):
		if WebSession.is_host:
			WebSession.send({"k": "gadget_state", "event": event, "round": _round}))
	if is_instance_valid(world.population):
		world.population.local_side = WebSession.local_side
		world.population.local_allowed = false
		world.population.requested.connect(_local_npc)
		player.tools.refresh_slots()
		if WebSession.is_host:
			world.population.confirmed.connect(func(event: Dictionary):
				_align_npc_pose(event)
				WebSession.send({"k": "npc_state", "event": event, "round": _round}))
			world.population.exhausted.connect(func(side: int): _caught_side(side))
	world.fire.sync_burn_cells = true
	if is_instance_valid(player.hides):
		player.hides.search_requested.connect(_search)
	if is_instance_valid(world.secrets):
		world.secrets.local_side = WebSession.local_side
		world.secrets.action_requested.connect(_local_secret)
		if WebSession.is_host:
			world.secrets.weapon_hit_requested.connect(accept_weapon_hit)
		if world.secrets is SchoolSecrets and WebSession.is_host:
			world.secrets.football_scored.connect(func(event: Dictionary):
				WebSession.send({"k": "secret_state", "event": event, "round": _round}))
		if not OS.has_feature("web"):
			_voice = DistrictVoice.new()
			add_child(_voice)
	for side in WebSession.roster.size():
		if side != WebSession.local_side:
			_actors[side] = _make_actor(side)
	if is_instance_valid(school):
		if not WebSession.is_host:
			_bot_replica = _make_actor(RoomRules.BOT_SIDE, false)
		_bot_chat = SchoolBotChat.new()
		_bot_chat.player = player
		_bot_chat.pause_menu = pause_menu
		_bot_chat.teammate = true
		_bot_chat.team_system = SchoolHideMatch.TEAM_SYSTEM
		_bot_chat.can_open = func(): return bool(rules.bot) and _phase in ["hide", "seek"] and not _am_seeker() and WebSession.local_side not in _found
		_bot_chat.tactical_reply = _ask_bot
		_bot_chat.local_model = WebSession.is_host
		add_child(_bot_chat)
		if WebSession.is_host and rules.bot:
			BotLanguage.warmup.call_deferred()
	_apply_rules()
	player.camera.make_current()
	if WebSession.is_host:
		world.network_dirty.clear()
		world.network_blast.connect(func(at: Vector3, radius: float):
			WebSession.send({"k": "blast", "p": _pack(at), "r": radius, "round": _round}))
	else:
		world.fire.set_process(false)
		for object in world.objects:
			_freeze_replica(object)
	var canvas := CanvasLayer.new()
	canvas.layer = 32
	add_child(canvas)
	_board = RoundBoard.new()
	canvas.add_child(_board)
	WebSession.transport_restored.connect(_refresh_after_reconnect)
	WebSession.packet.connect(_receive)
	WebSession.drain()
	if WebSession.is_host:
		_ready_sides[0] = true
		_try_start()
	else:
		WebSession.send({"k": "ready"})


func _make_actor(side: int, proxy_enabled := true) -> RoomActor:
	var actor := RoomActor.new()
	actor.avatar = VoxelAvatar.new()
	actor.avatar.hide()
	add_child(actor.avatar)
	if not proxy_enabled:
		return actor
	actor.proxy = Player.new()
	var proxy := actor.proxy
	proxy.set_meta("room_side", side)
	proxy.god_mode = true
	proxy.show_body = false
	add_child(proxy)
	proxy.set_physics_process(false)
	proxy.set_process(false)
	proxy.set_process_unhandled_input(false)
	proxy.collision_layer = 0
	proxy.collision_mask = 0
	proxy.tools.hide()
	proxy.tools.input_enabled = false
	proxy.tools.room_tools = player.tools.room_tools
	proxy.tools.utility_only = not weapons_enabled
	proxy.tools.mirror_only = not WebSession.is_host
	proxy.tools.suppress_utility = true
	proxy.tools.set_process_unhandled_input(false)
	return actor


func _process(delta: float) -> void:
	var active := WebSession.local_side not in _found
	var allowed := active and (_phase == "seek" or (_phase == "hide" and not _am_seeker())) \
		and (not _am_seeker() or Time.get_ticks_msec() >= _unlock_at)
	var frozen := world.gadgets.local_frozen() or stunned(WebSession.local_side)
	var can_act := allowed and not frozen and not pause_menu.is_open() and not player.navigation_menu_open
	var can_select := allowed and not frozen and not pause_menu.is_open()
	var can_watch := not active and bool(rules.free_spectate) and _phase == "seek" and not pause_menu.is_open() and not player.navigation_menu_open and not frozen
	player.movement_enabled = can_act or can_watch
	player.tools.input_enabled = can_select
	player.tools.hunt_tools_locked = _phase != "seek"
	player.tools.room_combat_locked = _phase != "seek" or not can_act
	if is_instance_valid(player.hides):
		player.hides.search_all = _am_seeker()
	if is_instance_valid(world.population):
		var can_disguise := allowed and not _am_seeker() and _tool_allowed(PlayerTools.POSSESSOR)
		if world.population.local_allowed != can_disguise:
			world.population.local_allowed = can_disguise
			player.tools.refresh_slots()
		if WebSession.is_host and _phase in ["hide", "seek", "done"]:
			_npc_timer -= delta
			if _npc_timer <= 0.0:
				_npc_timer = 0.15
				WebSession.send({"k": "npc_pose", "actors": world.population.snapshot(), "round": _round}, false)
	if is_instance_valid(world.secrets):
		world.secrets.can_shoot = _phase == "seek" and _am_seeker()
	if is_instance_valid(_voice):
		_voice.round_number = _round
		_voice.allowed = can_act
		_voice.public_address = world.secrets is SchoolSecrets and world.secrets.on_public_address()
	if not WebSession.is_host:
		_send_tool()
	var now := Time.get_ticks_msec()
	if world.gadgets.clock_active() and _last_process_ms > 0:
		_deadline_ms += now - _last_process_ms
	_last_process_ms = now
	_remaining = maxf(0.0, (_deadline_ms - now) * 0.001)
	if WebSession.is_host:
		_tick_round(delta)
	for side in _actors:
		var actor: RoomActor = _actors[side]
		_pose_avatar(actor, side, delta)
		actor.proxy.tools.room_combat_locked = _phase != "seek" or not _can_act(side)
		if not _can_act(side):
			actor.proxy.tools._hammer_hit_pending = -1.0
			actor.proxy.tools.sim_fire = false
			actor.proxy.tools.remote_tap = false
		if not WebSession.is_host and _tool_allowed(PlayerTools.SPRAY):
			actor.proxy.tools.select(PlayerTools.SPRAY)
			actor.proxy.tools.sim_fire = _phase == "seek" and now < actor.spray_until and side not in _found and not stunned(side)
	if _bot_replica != null:
		_pose_avatar(_bot_replica, RoomRules.BOT_SIDE, delta)
	if is_instance_valid(_bot) and is_instance_valid(_bot.bot):
		_bot.bot.visible = RoomRules.BOT_SIDE not in _found and _bot.hidden_spot < 0 \
			and (_phase in ["seek", "done"] or (_phase == "hide" and not _am_seeker()))
	var smoothing := 1.0 - exp(-15.0 * delta)
	for id in _dynamic:
		var object: VoxelObject = world.network_objects.get(id)
		if is_instance_valid(object):
			object.global_transform = object.global_transform.interpolate_with(_dynamic[id], smoothing)
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = 0.058
		_send_pose()
		_update_lockers()
		if WebSession.is_host:
			_flush_voxels(not weapons_enabled)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.5
		if WebSession.is_host:
			_send_state()
		elif _phase == "wait" and not WebSession.is_reconnecting():
			WebSession.send({"k": "ready"})
	_stage.update_countdown(stunned(WebSession.local_side))
	_update_label()


func _tick_round(delta: float) -> void:
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 0.25
		_send_fire()
	match _phase:
		"hide":
			if _remaining <= 0.0:
				_phase = "seek"
				_unlock_at = Time.get_ticks_msec() + _stage.door_duration_ms()
				_stage.open_door(_am_seeker())
				_set_remaining(float(rules.seek))
				if is_instance_valid(_bot):
					_bot.begin_seek()
				_send_state()
		"seek":
			_restore_seekers()
			if _remaining <= 0.0:
				_finish("Прячущиеся продержались")
		"done":
			if OS.has_feature("web") and _remaining <= 0.0:
				_start_round()


func _try_start() -> void:
	if _phase != "wait" or _ready_sides.size() != WebSession.roster.size() or _match_started:
		return
	if OS.has_feature("web") or WebSession.auto_rounds():
		_start_round()
	else:
		_phase = "brief"
		WebSession.send({"k": "briefing"})
		_stage.first_briefing()


func _start_round() -> void:
	if _bot_prepare_running:
		return
	_phase = "wait"
	_stage.clear()
	_round += 1
	_match_started = true
	if _next_seekers.is_empty():
		_pick_teams(_round)
	else:
		_seekers.assign(_next_seekers)
		_next_seekers.clear()
	_apply_rules()
	_found.clear()
	_health.fill(100)
	_stun_until.fill(0)
	_unlock_at = 0
	_sync_local_health()
	_win_seekers = false
	_bot_conversations.clear()
	_result = ""
	_layout_seed = randi()
	_reset_world()
	_spawn_points = _choose_spawns()
	_reset_player()
	if is_instance_valid(_bot):
		remove_child(_bot)
		_bot.queue_free()
		_bot = null
	if rules.bot and is_instance_valid(school):
		_bot_prepare_running = true
		_bot = SchoolHideMatch.new()
		_bot.world = world
		_bot.school = school
		_bot.hud = hud
		_bot.pause_menu = pause_menu
		_bot.network = self
		add_child(_bot)
		await _bot.prepare()
		_bot.start_hide()
		_bot_prepare_running = false
	_phase = "hide"
	_set_remaining(float(rules.hide))
	_greet_team()
	_stage.hide_phase(_am_seeker())
	print("[hide] round ", _round, " seekers ", _seekers, " hiders ", _hider_count())
	_send_state()


func suggested_seekers(options: Dictionary, round_id: int) -> Array[int]:
	var result: Array[int] = []
	var count := WebSession.roster.size()
	if count == 0:
		return result
	var offset := 0 if RoomRules.host_seeks(options) else count - int(options.seekers)
	if options.switch_roles and int(options.seekers) < count:
		offset += round_id - 1
	for slot in int(options.seekers):
		result.append(posmod(offset + slot, count))
	return result


func _pick_teams(round_id: int) -> void:
	_seekers = suggested_seekers(rules, round_id)


func launch_next(options: Dictionary, seekers: Array[int]) -> bool:
	if not WebSession.is_host or _phase not in ["brief", "done"]:
		return false
	var next := RoomRules.normalized(GameState.level, options)
	var count := WebSession.roster.size()
	if RoomRules.human_count(next) != count or seekers.size() != int(next.seekers):
		return false
	var unique := {}
	for side in seekers:
		if side < 0 or side >= count or unique.has(side):
			return false
		unique[side] = true
	rules = next
	_next_seekers = seekers.duplicate()
	_start_round()
	return true


func _apply_rules() -> void:
	var half := RoomRules.half(GameState.level, int(rules.zone))
	player.border = half
	WebSession.rules = rules.duplicate()
	player.tools.room_tools = int(rules.tools)
	player.tools.refresh_slots()
	for actor: RoomActor in _actors.values():
		actor.proxy.tools.room_tools = int(rules.tools)
		actor.proxy.tools.refresh_slots()
	world.gadgets.dispenser_enabled = bool(rules.gadgets)
	if is_instance_valid(_barrier):
		remove_child(_barrier)
		_barrier.queue_free()
		_barrier = null
	if int(rules.zone) > 0:
		_barrier = RoomBarrier.new()
		_barrier.build(half)
		add_child(_barrier)


func _am_seeker() -> bool:
	return _is_seeker(WebSession.local_side)


func _is_seeker(side: int) -> bool:
	return side in _seekers


func nearest_hunter(at: Vector3) -> Player:
	var nearest: Player
	var distance := INF
	for side in _seekers:
		var source := _player_for(side)
		if not is_instance_valid(source):
			continue
		var current := at.distance_squared_to(source.global_position)
		if current < distance:
			distance = current
			nearest = source
	return nearest


func _player_for(side: int) -> Player:
	if side == WebSession.local_side:
		return player
	var actor: RoomActor = _actors.get(side)
	return actor.proxy if actor != null and actor.seen else null


func _hider_count() -> int:
	return WebSession.roster.size() - _seekers.size() + int(bool(rules.bot))


func can_attack(source: Player) -> bool:
	var side := _side_of(source)
	return attack_is_current(-1) and side >= 0 and _can_act(side)


func attack_is_current(round_id: int) -> bool:
	return WebSession.is_host and _phase == "seek" and (round_id < 0 or round_id == _round)


func _side_of(source: Player) -> int:
	return WebSession.local_side if source == player else int(source.get_meta("room_side", -1))


func opponents(a: int, b: int) -> bool:
	return _is_seeker(a) != _is_seeker(b)


func stunned(side: int) -> bool:
	return _stun_until[side] > Time.get_ticks_msec()


func combat_hp(side: int) -> int:
	return _health[side]


func _combat_targets(side: int) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for other in WebSession.roster.size():
		if other == side or not opponents(side, other) or other in _found or _health[other] <= 0:
			continue
		var target := _player_for(other)
		if not is_instance_valid(target):
			continue
		if is_instance_valid(world.population) and world.population.disguise(other) >= 0:
			continue
		targets.append({"side": other, "feet": target.global_position,
			"crouch": target.hide_spot >= 0 or bool(target.get_meta("room_crouch", target.crouching))})
	if _is_seeker(side) and rules.bot and RoomRules.BOT_SIDE not in _found and is_instance_valid(_bot) and is_instance_valid(_bot.bot):
		targets.append({"side": RoomRules.BOT_SIDE, "feet": _bot.bot.global_position, "crouch": _bot.hidden_spot >= 0 or _bot._quiet_step})
	return targets


func combat_trace(source: Player, from: Vector3, to: Vector3) -> Dictionary:
	if not can_attack(source):
		return {}
	var best := {}
	var distance := INF
	for target in _combat_targets(_side_of(source)):
		var at := HideCombat.contact(from, to, target.feet, target.crouch)
		var next := at.distance_squared_to(from)
		if next < distance:
			distance = next
			best = {"side": target.side, "at": at}
	return best


func combat_blast(source: Player, at: Vector3, radius: float, attack_round: int) -> void:
	if not attack_is_current(attack_round) or _side_of(source) < 0:
		return
	for target in _combat_targets(_side_of(source)):
		if HideCombat.blast_reaches(world, at, target.feet, radius):
			_damage_from_side(_side_of(source), int(target.side))


func combat_damage(source: Player, target: int) -> void:
	if can_attack(source):
		_damage_from_side(_side_of(source), target)


func _damage_from_side(side: int, target: int) -> void:
	if _phase != "seek" or target < 0 or target >= _health.size() or not opponents(side, target) or _health[target] <= 0:
		return
	_health[target] = maxi(0, _health[target] - HideCombat.HIT)
	if target == RoomRules.BOT_SIDE and is_instance_valid(_bot):
		_bot._leave_cover()
		_bot._stand_until = _bot.elapsed
		var attacker := _player_for(side)
		if is_instance_valid(attacker):
			_bot._notice(attacker.global_position, 7.0, 2)
	if _health[target] == 0:
		if _is_seeker(target):
			_stun_until[target] = Time.get_ticks_msec() + roundi(HideCombat.STUN_TIME * 1000.0)
			if target == WebSession.local_side:
				_disable_found_player()
		else:
			_caught_side(target)
	_sync_local_health()
	_send_state()


func _restore_seekers() -> void:
	var now := Time.get_ticks_msec()
	var changed := false
	for side in _seekers:
		if _stun_until[side] > 0 and _stun_until[side] <= now:
			_stun_until[side] = 0
			_health[side] = 100
			changed = true
	if changed:
		_sync_local_health()
		_send_state()


func _sync_local_health() -> void:
	var health := float(_health[WebSession.local_side])
	if health < player.health:
		player.shake(0.34)
	player.health = health


func _caught_side(side: int) -> void:
	if _phase != "seek" or _is_seeker(side) or side in _found:
		return
	_found.append(side)
	if side == RoomRules.BOT_SIDE and is_instance_valid(_bot):
		_bot.stop_network()
	elif side == WebSession.local_side:
		_disable_found_player()
	if _found.size() >= _hider_count():
		_finish("Все прячущиеся найдены")
	else:
		_send_state()


func _disable_found_player() -> void:
	player.tools.sim_fire = false
	player.tools.remote_tap = false
	player.tools._hammer_hit_pending = -1.0
	if player.vehicle:
		player.exit_vehicle(true)
	player.release_grab(false)
	player.tools.cancel_placement()
	if rules.free_spectate and player.hide_spot >= 0 and is_instance_valid(player.hides):
		player.hides.reset_player()
		player.global_position = player.spawn_point
		player.reset_physics_interpolation()


func _search(spot_id: int) -> void:
	if _phase != "seek" or not _am_seeker():
		return
	if WebSession.is_host:
		_search_as(spot_id, WebSession.local_side)
	else:
		WebSession.send({"k": "search", "spot": spot_id, "round": _round})


func _search_as(spot_id: int, side: int) -> void:
	var source := _player_for(side)
	if not is_instance_valid(source) or not _is_seeker(side) or not _can_act(side) or not is_instance_valid(player.hides) \
			or not player.hides._accessible(spot_id, source.global_position):
		return
	for target in WebSession.roster.size():
		if _is_seeker(target) or target in _found:
			continue
		var hider := _player_for(target)
		if is_instance_valid(hider) and hider.hide_spot == spot_id:
			if target == WebSession.local_side:
				_leave_checked_locker(spot_id)
			else:
				WebSession.send_to_side(target, {"k": "open_locker", "spot": spot_id, "round": _round})
			break
	if is_instance_valid(_bot) and spot_id == _bot.hidden_spot:
		_bot._leave_cover()
		_bot._stand_until = _bot.elapsed
		_bot._notice(source.global_position, 8.0, 2)
	if is_instance_valid(_bot):
		_bot.checked_spots[spot_id] = true


func _leave_checked_locker(spot_id: int) -> void:
	if is_instance_valid(player.hides) and player.hide_spot == spot_id:
		player.hides.interact()
		world.sfx.play("hide_wood", player.global_position, -5.0)


func _reset_world() -> void:
	if is_instance_valid(transit):
		transit.arrange(_layout_seed)
	if is_instance_valid(world.secrets):
		world.secrets.reset_round(_layout_seed)
	player.tools.cancel_placement()
	world.construction.round_number = _round
	world.construction.clear_round()
	world.gadgets.reset_round()
	world.boombox.reset_round(_round)
	get_tree().call_group("hud", "clear_horn")
	if is_instance_valid(world.population):
		world.population.round_reset()
	if is_instance_valid(player.hides):
		player.hides.reset_player()
		player.hides.set_remote_spots([])
	for actor: RoomActor in _actors.values():
		actor.seen = false
		actor.step = -1
		actor.hidden = -1
		actor.proxy.hide_spot = -1
		actor.proxy.tools.sim_fire = false
		actor.spray_until = 0
	if _bot_replica != null:
		_bot_replica.seen = false
		_bot_replica.hidden = -1


func _choose_spawns() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var used: Array[Vector3] = []
	for side in WebSession.roster.size():
		var base := starts[0 if _is_seeker(side) else 1]
		base.x = clampf(base.x, -player.border + 3.0, player.border - 3.0)
		base.z = clampf(base.z, -player.border + 3.0, player.border - 3.0)
		var chosen := base
		for i in 40:
			var angle := i * 2.39996
			var offset := Vector3(cos(angle), 0, sin(angle)) * sqrt(i) * 0.9
			var at := player._clear_exit(base + offset + Vector3.UP * 0.8)
			if not RoomRules.contains(at, player.border - 0.7):
				continue
			if used.any(func(prior: Vector3): return prior.distance_squared_to(at) < 1.8 * 1.8):
				continue
			chosen = at
			break
		used.append(chosen)
		result.append(chosen)
	return result


func _reset_player() -> void:
	if player.vehicle:
		player.exit_vehicle(true)
	player.transit_active = false
	player.release_grab(false)
	player.position = _spawn_points[WebSession.local_side]
	player.spawn_point = player.position
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.look_at_dir(0.0 if _am_seeker() else PI, 0.0)
	_fire_last = false
	_tool_last = -1
	for side in _actors:
		var actor: RoomActor = _actors[side]
		actor.at = _spawn_points[side]
		actor.avatar.position = actor.at


func _finish(reason: String) -> void:
	_phase = "done"
	_set_remaining(FINISH_SECONDS)
	_win_seekers = _found.size() >= _hider_count()
	_result = reason
	_stage.show_result(_win_seekers)
	if is_instance_valid(_bot):
		_bot.stop_network()
	for actor: RoomActor in _actors.values():
		actor.proxy.tools.sim_fire = false
	_send_state()


func _send_state(side := -1) -> void:
	if _phase == "wait":
		return
	var positions: Array = []
	for at in _spawn_points:
		positions.append(_pack(at))
	var stuns: Array[int] = []
	for deadline in _stun_until:
		stuns.append(maxi(0, deadline - Time.get_ticks_msec()))
	var state := {"k": "state", "phase": _phase, "t": _remaining, "round": _round,
		"seekers": _seekers, "found": _found, "result": _result, "layout": _layout_seed, "spawns": positions,
		"rules": rules, "health": _health, "stuns": stuns, "seekers_won": _win_seekers}
	if side > 0:
		WebSession.send_to_side(side, state)
	else:
		WebSession.send(state)


func _set_remaining(seconds: float) -> void:
	_remaining = seconds
	_deadline_ms = Time.get_ticks_msec() + roundi(seconds * 1000.0)


func _greet_team() -> void:
	if is_instance_valid(_bot_chat):
		_bot_chat.close_chat()
		if rules.bot and not _am_seeker():
			_bot_chat.say("Ухожу искать укрытие.")


func _update_label() -> void:
	var role := "ИЩУЩИЙ" if _am_seeker() else "ПРЯЧУЩИЙСЯ"
	if WebSession.local_side in _found:
		role = "ТЕБЯ НАШЛИ"
	var state := "reconnect" if WebSession.is_reconnecting() and _phase in ["hide", "seek"] else _phase
	_board.visible = not pause_menu.is_open()
	if _board.visible:
		_board.refresh(state, _remaining, float(rules.hide if _phase == "hide" else rules.seek),
			_hider_count() - _found.size(), _seekers.size(), role)
	if is_instance_valid(_bot_chat):
		if not _bot_chat._available() and _bot_chat.opened:
			_bot_chat.close_chat()
		_bot_chat.set_round_clock(_phase, int(float(rules.seek) - _remaining) if _phase == "seek" else 0, ceili(_remaining))


func _refresh_after_reconnect() -> void:
	if WebSession.is_host:
		_send_state()
	else:
		WebSession.send({"k": "sync_round"})


func _tool_allowed(tool: int) -> bool:
	return tool >= 0 and tool < PlayerTools.NAMES.size() and (int(rules.tools) & (1 << tool)) != 0


func _can_act(side: int) -> bool:
	return side not in _found and not stunned(side) and not world.gadgets.frozen_for(side) \
		and (not _is_seeker(side) or Time.get_ticks_msec() >= _unlock_at) \
		and (_phase == "seek" or (_phase == "hide" and not _is_seeker(side)))


func _pack(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _unpack(v: Variant) -> Vector3:
	if not v is Array or v.size() != 3:
		return Vector3.INF
	for element in v:
		if not (element is float or element is int):
			return Vector3.INF
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


func _xform(o: Node3D) -> Array:
	var q := o.global_basis.get_rotation_quaternion()
	return [_pack(o.global_position), [snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)]]


func _decode_xform(data: Array) -> Transform3D:
	var q: Array = data[1]
	return Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), _unpack(data[0]))

var _prop_tick := 0
var _prop_cursor := 0


func _send_pose() -> void:
	if _phase == "wait":
		return
	_pose_serial += 1
	var packet := {"k": "pose", "s": _pose_serial, "p": _pack(player.position), "y": player.rotation.y,
		"x": player.head.rotation.x, "c": player.crouching, "hide": player.hide_spot, "round": _round,
		"run": player.is_sprinting(), "step": [player.footstep_serial, player.footstep_material, player.footstep_running],
		"spray": player.tools.spraying}
	if is_instance_valid(world.population):
		packet["disguise"] = world.population.disguise(WebSession.local_side)
	if WebSession.is_host:
		if world.secrets is SchoolSecrets:
			packet["football"] = _xform(world.secrets.football)
		if is_instance_valid(_bot) and is_instance_valid(_bot.bot):
			packet["bot"] = [_pack(_bot.bot.global_position), _bot.bot.rotation.y, _bot._running_pose, _bot.hidden_spot, _bot.phase != "done"]
		_prop_tick = (_prop_tick + 1) % 2
		if weapons_enabled and _prop_tick == 0:
			var moving := _moving_props(POSE_PAYLOAD_BYTES - JSON.stringify(packet).length() - 16)
			if not moving.is_empty():
				packet["dynamic"] = moving
	WebSession.send(packet, false)


func _moving_props(budget: int) -> Array:
	var moving: Array = []
	var count := world.objects.size()
	for i in count:
		_prop_cursor %= count
		var object: VoxelObject = world.objects[_prop_cursor]
		if is_instance_valid(object) and not object.static_mode and not object.freeze:
			var item := [object.network_id, _xform(object)]
			budget -= JSON.stringify(item).length() + 1
			if budget < 0:
				break
			moving.append(item)
		_prop_cursor += 1
	return moving


func _send_tool() -> void:
	var tool := player.tools.current
	if not _tool_allowed(tool) or PlayerTools.is_gadget(tool) or tool in [PlayerTools.POSSESSOR, PlayerTools.BOOMBOX] or is_instance_valid(player.possessed_npc):
		tool = -1
	var locked := (player.tools.hunt_tools_locked and tool == PlayerTools.SPRAY) or player.tools.room_combat_locked
	var fire := tool >= 0 and player.tools.input_enabled and not locked and not player.transit_active \
		and not player.tools._inventory_open and not player.tools._fire_blocked and Input.is_action_pressed("fire")
	if fire == _fire_last and tool == _tool_last:
		return
	if WebSession.send({"k": "tool", "fire": fire, "tool": tool, "round": _round, "p": _pack(player.position),
		"y": player.rotation.y, "x": player.head.rotation.x}):
		_fire_last = fire
		_tool_last = tool


func _read_pose(data: Dictionary, side: int) -> bool:
	var actor: RoomActor = _actors.get(side)
	if actor == null:
		return false
	var serial := int(data.get("s", -1))
	var at := _unpack(data.get("p"))
	if serial <= actor.serial or not RoomRules.contains(at, player.border + 0.05) or at.y < -32.0 or at.y > 65.0:
		return false
	var yaw := float(data.get("y", 0.0))
	var pitch := float(data.get("x", 0.0))
	if not is_finite(yaw) or not is_finite(pitch):
		return false
	var hidden := int(data.get("hide", -1))
	if not is_instance_valid(player.hides) or hidden < 0 or hidden >= player.hides.spots.size():
		hidden = -1
	if _is_seeker(side):
		hidden = -1
	var disguise := int(data.get("disguise", -1))
	if is_instance_valid(world.population) and disguise != world.population.disguise(side):
		return false
	if not actor.seen or actor.at.distance_squared_to(at) > 64.0:
		actor.avatar.position = at
	var previous := actor.at
	actor.at = at
	actor.yaw = yaw
	actor.pitch = clampf(pitch, -1.53, 1.53)
	actor.crouch = bool(data.get("c", false))
	actor.running = bool(data.get("run", false)) and not actor.crouch
	actor.serial = serial
	actor.hidden = hidden
	var proxy := actor.proxy
	proxy.velocity = ((at - previous) / 0.058).limit_length(15.0) if actor.seen else Vector3.ZERO
	proxy.set_meta("room_running", actor.running)
	proxy.set_meta("room_crouch", actor.crouch)
	proxy.position = at
	proxy.hide_spot = hidden
	proxy.head.position.y = Player.CROUCH_EYE if actor.crouch else Player.STAND_EYE
	proxy.look_at_dir(yaw, actor.pitch)
	actor.seen = true
	actor.spray_until = Time.get_ticks_msec() + 260 if bool(data.get("spray", false)) else 0
	if is_instance_valid(world.population):
		world.population.remote_poses[side] = {"at": at, "yaw": yaw, "pitch": actor.pitch}
	if WebSession.roster.size() == 2:
		world.boombox.remote_position = at
	var step: Variant = data.get("step")
	if step is Array and step.size() == 3 and (step[0] is int or step[0] is float) and (step[1] is int or step[1] is float) and step[2] is bool:
		var index := int(step[0])
		if index > actor.step:
			if actor.step >= 0 and _phase == "seek" and hidden < 0 and disguise < 0:
				if at.distance_squared_to(player.global_position) < 900.0:
					world.sfx.footstep(clampi(int(step[1]), 0, VoxMat.EMISSIVE), at, step[2], actor.crouch)
				if is_instance_valid(_bot) and _is_seeker(side):
					_bot._heard_seeker_sound(at, 16.0 if actor.running else 10.0, "step")
			actor.step = index
	return true


func _update_lockers() -> void:
	if not is_instance_valid(player.hides):
		return
	var spots: Array[int] = []
	for side in _actors:
		var actor: RoomActor = _actors[side]
		if actor.seen and actor.hidden >= 0 and side not in _found:
			spots.append(actor.hidden)
	var bot_spot := _bot.hidden_spot if is_instance_valid(_bot) else (_bot_replica.hidden if _bot_replica != null else -1)
	if bot_spot >= 0 and RoomRules.BOT_SIDE not in _found:
		spots.append(bot_spot)
	player.hides.set_remote_spots(spots)


func _pose_avatar(actor: RoomActor, side: int, delta: float) -> void:
	var avatar := actor.avatar
	var before := avatar.position
	var smooth := 1.0 - exp(-15.0 * delta)
	avatar.position = avatar.position.lerp(actor.at, smooth)
	avatar.rotation.y = lerp_angle(avatar.rotation.y, actor.yaw, smooth)
	avatar.pose(minf(before.distance_to(avatar.position) / maxf(delta, 0.001), 9.5), actor.pitch, actor.crouch, delta, actor.running)
	avatar.visible = actor.seen and actor.hidden < 0 and side not in _found and (_phase in ["seek", "done"] or (_phase == "hide" and not _am_seeker()))
	if is_instance_valid(world.population) and world.population.disguise(side) >= 0:
		avatar.hide()


func _align_npc_pose(event: Dictionary) -> void:
	var actor: RoomActor = _actors.get(int(event.get("side", -1)))
	var at := _unpack(event.get("at"))
	if actor == null or not at.is_finite():
		return
	actor.at = at
	actor.proxy.position = at
	actor.avatar.position = at


func _local_npc(action: String, id: int, direction: Vector3) -> void:
	if WebSession.is_host:
		_share_npc(action, id, 0, direction)
	else:
		WebSession.send({"k": "npc_request", "action": action, "id": id, "dir": _pack(direction), "round": _round})


func _share_npc(action: String, id: int, side: int, direction: Vector3) -> void:
	var source := _player_for(side)
	if not is_instance_valid(source) or not direction.is_finite() or not _can_act(side) or _is_seeker(side) or not _tool_allowed(PlayerTools.POSSESSOR):
		return
	world.population.authorize(action, id, side, source.global_position, source.camera.global_position, direction)


func _local_gadget(action: String, slot: int) -> void:
	if WebSession.is_host:
		_share_gadget(action, slot, 0)
	else:
		WebSession.send({"k": "gadget_request", "action": action, "slot": slot, "round": _round})


func _share_gadget(action: String, slot: int, side: int) -> void:
	var source := _player_for(side)
	if is_instance_valid(source) and _can_act(side):
		world.gadgets.authorize(action, slot, side, source.global_position, source.camera.global_position, source.aim_dir())


func _local_secret(key: String, shot: bool) -> void:
	if WebSession.is_host:
		_share_secret(key, 0, player.global_position, shot)
	else:
		WebSession.send({"k": "secret_request", "key": key, "shot": shot, "round": _round})


func accept_weapon_hit(key: String, source: Player) -> void:
	if WebSession.is_host:
		var side := 0 if source == player else int(source.get_meta("room_side", -1))
		if side >= 0:
			_share_secret(key, side, source.global_position, true, true)


func _share_secret(key: String, side: int, at: Vector3, shot: bool, verified := false) -> void:
	if not _can_act(side) or (shot and (_phase != "seek" or not verified)):
		return
	if world.secrets is SchoolSecrets:
		var hunter := nearest_hunter(at)
		world.secrets.other_player_position = hunter.global_position if is_instance_valid(hunter) and hunter != _player_for(side) else Vector3.INF
	var event := world.secrets.authorize(key, side, at, shot, false, verified)
	if not event.is_empty():
		WebSession.send({"k": "secret_state", "event": event, "round": _round})


func _ask_bot(question: String) -> String:
	if WebSession.is_host:
		if _bot_reply_active:
			return "Дай секунду закончить предыдущий ответ."
		_bot_reply_active = true
		var answer := await _bot_answer(question, 0)
		_bot_reply_active = false
		return answer
	if not WebSession.send({"k": "bot_question", "q": question, "round": _round}):
		return "Связь с создателем комнаты потеряна."
	_guest_question_round = _round
	_guest_bot_answer = ""
	var deadline := Time.get_ticks_msec() + 22000
	while _guest_bot_answer.is_empty() and _guest_question_round == _round and WebSession.connected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_guest_question_round = -1
	return _guest_bot_answer if not _guest_bot_answer.is_empty() else "Шорох занят. Попробуй ещё раз."


func _bot_answer(question: String, side: int) -> String:
	if not is_instance_valid(_bot):
		return "Готовлюсь к раунду."
	var answer := _bot.team_instruction(question)
	if not answer.is_empty():
		return answer
	var lower := question.to_lower()
	if "сколько" in lower and ("врем" in lower or "остал" in lower):
		return "До конца этого этапа %d с." % ceili(_remaining)
	BotLanguage.warmup()
	var deadline := Time.get_ticks_msec() + 9500
	while Time.get_ticks_msec() < deadline and (BotLanguage.state in ["loading", "verifying"] or BotLanguage.busy()):
		await get_tree().process_frame
	if BotLanguage.state in ["loading", "verifying"]:
		return "Модель ещё загружается. Напиши снова через несколько секунд."
	if BotLanguage.state != "ready":
		return "Выбери для меня двор, подвал или этаж. Для свободного чата установи Qwen в одиночном меню школы у создателя комнаты."
	if not is_instance_valid(_bot) or not is_instance_valid(_bot.bot):
		return "Раунд закончился."
	var context := SchoolHideMatch.TEAM_SYSTEM + " Сейчас %s. Есть %d секунд. Находишься в зоне %s." % [
		"фора" if _phase == "hide" else "поиск", ceili(_remaining), SchoolHuntRoutes.zone(_bot.bot.global_position)]
	var messages: Array = [
		{"role": "system", "content": context},
		{"role": "user", "content": "Как нам действовать вдвоём, если искатель рядом?"},
		{"role": "assistant", "content": "Разойдёмся по разным путям. Я побегу через переход, а ты уходи за угол. Гудок выдаст место, поэтому подождём, пока он уйдёт."},
		{"role": "user", "content": "Что интересного в этой школе?"},
		{"role": "assistant", "content": "Есть лифт, стадион и подвальные проходы. Если я займусь верхними этажами, у нас будет два разных пути отхода."},
	]
	var previous: Array = _bot_conversations.get(side, [])
	messages.append_array(previous)
	messages.append({"role": "user", "content": question})
	var round_id := _round
	var reply := await BotLanguage.generate(get_instance_id(), messages, 64)
	if is_instance_valid(_bot_chat):
		reply = _bot_chat._clean(reply)
	if reply.is_empty():
		reply = "Разойдёмся по двум зонам. Если искатель рядом, сначала уйди за угол и только потом меняй этаж."
	if round_id == _round:
		previous.append({"role": "user", "content": question})
		previous.append({"role": "assistant", "content": reply})
		_bot_conversations[side] = previous.slice(maxi(0, previous.size() - 6))
	return reply


func _reply_to_remote(side: int, question: String, round_id: int) -> void:
	_bot_reply_active = true
	var answer := await _bot_answer(question, side)
	_bot_reply_active = false
	if _round == round_id and _phase in ["hide", "seek"] and side not in _found and not _is_seeker(side):
		WebSession.send_to_side(side, {"k": "bot_answer", "text": answer, "round": round_id})


func bot_horn(at: Vector3) -> void:
	if _am_seeker():
		get_tree().call_group("hud", "show_horn", at)
	WebSession.send({"k": "bot_horn", "p": _pack(at), "round": _round})


func _receive(data: Dictionary) -> void:
	var kind := str(data.get("k", ""))
	var side := int(data.get("_side", 0))
	if kind == "ready" and WebSession.is_host and side > 0:
		_ready_sides[side] = true
		_try_start()
		return
	if kind == "sync_round" and WebSession.is_host and side > 0:
		var now := Time.get_ticks_msec()
		if now >= int(_sync_requested_at.get(side, 0)):
			_sync_requested_at[side] = now + 1500
			_send_state(side)
		return
	if not WebSession.is_host and kind == "state":
		_receive_state(data)
		return
	if not WebSession.is_host and kind == "briefing" and _round == 0:
		_phase = "brief"
		_stage.first_briefing()
		return
	if data.has("round") and int(data.round) != _round:
		return
	if kind == "pose":
		if not _read_pose(data, side):
			return
		if WebSession.is_host:
			var relay := data.duplicate()
			relay.erase("dynamic")
			relay.erase("football")
			relay.erase("bot")
			WebSession.broadcast(relay, false, side, side)
		elif side == 0:
			_receive_world_pose(data)
		return
	if WebSession.is_host:
		_receive_client(data, kind, side)
	else:
		_receive_host(data, kind, side)


func _receive_state(data: Dictionary) -> void:
	var new_round := int(data.get("round", 0))
	if new_round < _round or not data.get("spawns") is Array or data.spawns.size() != WebSession.roster.size():
		return
	var changed := new_round != _round
	var previous_phase := _phase
	if changed and data.get("rules") is Dictionary:
		rules = RoomRules.normalized(GameState.level, data.rules)
		_apply_rules()
	_seekers.assign(data.get("seekers", []))
	var newly_found: bool = not changed and WebSession.local_side not in _found and WebSession.local_side in data.get("found", [])
	_found.assign(data.get("found", []))
	if newly_found:
		_disable_found_player()
	_layout_seed = int(data.get("layout", -1))
	_phase = str(data.get("phase", "wait"))
	_result = str(data.get("result", ""))
	if data.get("health") is Array and data.health.size() == RoomRules.SIDES and data.get("stuns") is Array and data.stuns.size() == RoomRules.SIDES:
		_health.assign(data.health)
		var was_stunned := stunned(WebSession.local_side)
		var now := Time.get_ticks_msec()
		for side in _stun_until.size():
			var left := int(data.stuns[side])
			if left > 0 and _stun_until[side] == 0:
				_stun_until[side] = now + left
			elif left == 0:
				_stun_until[side] = 0
		if not was_stunned and stunned(WebSession.local_side):
			_disable_found_player()
		_sync_local_health()
	_set_remaining(float(data.get("t", 0.0)))
	if changed:
		_round = new_round
		_spawn_points.clear()
		for at in data.spawns:
			_spawn_points.append(_unpack(at))
		_reset_world()
		_reset_player()
		_greet_team()
		_stage.clear()
		if _phase == "hide":
			_stage.hide_phase(_am_seeker())
	if _phase == "seek" and previous_phase == "hide":
		_unlock_at = Time.get_ticks_msec() + _stage.door_duration_ms()
		_stage.open_door(_am_seeker())
	elif _phase == "done" and previous_phase != "done":
		_win_seekers = bool(data.get("seekers_won", false))
		_stage.show_result(_win_seekers)


func _receive_world_pose(data: Dictionary) -> void:
	if world.secrets is SchoolSecrets and data.has("football"):
		world.secrets.football.receive_pose(_decode_xform(data.football))
	for entry in data.get("dynamic", []):
		_dynamic[int(entry[0])] = _decode_xform(entry[1])
	if _bot_replica != null and data.get("bot") is Array and data.bot.size() == 5:
		_bot_replica.at = _unpack(data.bot[0])
		if not _bot_replica.seen:
			_bot_replica.avatar.position = _bot_replica.at
		_bot_replica.yaw = float(data.bot[1])
		_bot_replica.running = bool(data.bot[2])
		_bot_replica.hidden = int(data.bot[3])
		_bot_replica.seen = bool(data.bot[4])


func _receive_signal(data: Dictionary, kind: String, side: int) -> bool:
	var actor: RoomActor = _actors.get(side)
	if actor == null or not actor.seen or not _can_act(side):
		return false
	var now := Time.get_ticks_msec()
	if kind == "map_ping":
		var at := Vector2(float(data.get("x", INF)), float(data.get("z", INF)))
		var floor_id := int(data.get("floor", -20))
		if now - actor.ping_at < 550 or not world.gadgets.map_data.validate_ping(at, floor_id):
			return false
		actor.ping_at = now
		world.gadgets.map_data.remote_ping(at, floor_id)
	else:
		var source := _unpack(data.get("p"))
		if not _tool_allowed(PlayerTools.HORN) or not source.is_finite() or source.distance_squared_to(actor.at) > 144.0 or now - actor.horn_at < 1250:
			return false
		actor.horn_at = now
		world.sfx.play_horn(source)
		get_tree().call_group("hud", "show_horn", source)
		if is_instance_valid(_bot) and _is_seeker(side):
			_bot._heard_seeker_sound(source, 30.0, "horn")
	return true


func _receive_client(data: Dictionary, kind: String, side: int) -> void:
	var actor: RoomActor = _actors.get(side)
	if actor == null:
		return
	match kind:
		"map_ping", "horn":
			if _receive_signal(data, kind, side):
				WebSession.broadcast(data, true, side, side)
		"district_voice":
			if is_instance_valid(_voice) and _can_act(side):
				_voice.receive(data)
				WebSession.broadcast(data, false, side, side)
		"search":
			if _phase == "seek":
				_search_as(int(data.get("spot", -1)), side)
		"tool":
			var tool := int(data.get("tool", -1))
			var proxy_tools := actor.proxy.tools
			var fire := bool(data.get("fire", false)) and actor.seen and _can_act(side) and _tool_allowed(tool) and tool in proxy_tools.tool_slots() \
				and tool not in [PlayerTools.HORN, PlayerTools.POSSESSOR, PlayerTools.BOOMBOX, PlayerTools.BOARD, PlayerTools.CLOTH] \
				and (_phase == "seek" or tool not in [PlayerTools.SHOTGUN, PlayerTools.SPRAY]) \
				and (not is_instance_valid(world.population) or world.population.disguise(side) < 0)
			if fire:
				var origin := _unpack(data.get("p"))
				var yaw := float(data.get("y", INF))
				var pitch := float(data.get("x", INF))
				if origin.is_finite() and actor.at.distance_squared_to(origin) < 9.0 and is_finite(yaw) and is_finite(pitch):
					actor.proxy.position = origin
					actor.proxy.look_at_dir(yaw, clampf(pitch, -1.53, 1.53))
				proxy_tools.select(tool)
				if tool == PlayerTools.SHOTGUN and not proxy_tools.sim_fire and is_instance_valid(_bot) and _is_seeker(side):
					_bot._heard_seeker_sound(actor.at, 38.0, "shot")
			proxy_tools.remote_tap = fire and not proxy_tools.sim_fire
			proxy_tools.sim_fire = fire
		"place_request":
			var tool := PlayerTools.CLOTH if bool(data.get("cloth", false)) else PlayerTools.BOARD
			if _can_act(side) and actor.seen and _tool_allowed(tool):
				world.construction.receive(data, actor.at)
		"door_request":
			var door := _find_door(data)
			if is_instance_valid(door) and _can_act(side) and actor.seen:
				door.interact(actor.at, player.global_position)
		"gadget_request":
			_share_gadget(str(data.get("action", "")), int(data.get("slot", -1)), side)
		"npc_request":
			if is_instance_valid(world.population):
				_share_npc(str(data.get("action", "")), int(data.get("id", -1)), side, _unpack(data.get("dir")))
		"secret_request":
			if is_instance_valid(world.secrets) and actor.seen:
				_share_secret(str(data.get("key", "")), side, actor.at, bool(data.get("shot", false)))
		"bot_question":
			var question := str(data.get("q", "")).strip_edges().left(240)
			var now := Time.get_ticks_msec()
			if rules.bot and not question.is_empty() and _can_act(side) and not _is_seeker(side) and now >= actor.question_at + 1200:
				if _bot_reply_active:
					WebSession.send_to_side(side, {"k": "bot_answer", "text": "Дай секунду закончить предыдущий ответ.", "round": _round})
					return
				actor.question_at = now
				_reply_to_remote(side, question, _round)


func _find_door(data: Dictionary) -> DistrictDoor:
	var object := world.network_objects.get(int(data.get("id", -1))) as VoxelObject
	return object.get_node_or_null("DistrictDoor") as DistrictDoor if is_instance_valid(object) else null


func _receive_host(data: Dictionary, kind: String, side: int) -> void:
	match kind:
		"map_ping", "horn":
			_receive_signal(data, kind, side)
		"district_voice":
			if is_instance_valid(_voice):
				_voice.receive(data)
		"open_locker":
			_leave_checked_locker(int(data.get("spot", -1)))
		"bot_answer":
			if _guest_question_round == _round and not _am_seeker():
				_guest_bot_answer = str(data.get("text", "")).left(240)
		"bot_horn":
			var at := _unpack(data.get("p"))
			if at.is_finite():
				world.sfx.play_horn(at)
				if _am_seeker():
					get_tree().call_group("hud", "show_horn", at)
		"gadget_state":
			world.gadgets.apply_event(data.event)
		"npc_state":
			if is_instance_valid(world.population):
				world.population.apply_event(data.event)
				_align_npc_pose(data.event)
		"npc_pose":
			if is_instance_valid(world.population):
				world.population.read_snapshot(data.actors)
		"secret_state":
			if is_instance_valid(world.secrets):
				world.secrets.apply_event(data.event)
		"door_set":
			var door := _find_door(data)
			if is_instance_valid(door):
				door.set_open(bool(data.get("open", false)), float(data.get("turn", 0.0)))
		"place", "place_gone":
			world.construction.receive(data, Vector3.ZERO)
		"burn_cells":
			world.fire.apply_remote_burns(data.cells)
		"blast":
			var at := _unpack(data.get("p"))
			var radius := clampf(float(data.get("r", 1.0)), 0.1, 5.0)
			world.fx.explosion(at, radius)
			world.sfx.play("explosion", at, 6.0 + radius * 2.0)
			player.shake(clampf(radius * 1.6 / maxf(player.global_position.distance_to(at), 1.0), 0.0, 1.0))
		"gone":
			for id in data.get("ids", []):
				var object: VoxelObject = world.network_objects.get(int(id))
				_dynamic.erase(int(id))
				if is_instance_valid(object):
					object.queue_free()
		"vox":
			_apply_voxels(data)
		"fire":
			var points := PackedVector3Array()
			for at in data.get("points", []).slice(0, FireSystem.MAX_FIRES):
				points.append(_unpack(at))
			world.fire.show_fire(points)


func _exit_tree() -> void:
	BotLanguage.cancel(get_instance_id())


func _send_fire() -> void:
	if not world.fire.burn_updates.is_empty() and WebSession.send({"k": "burn_cells", "cells": world.fire.burn_updates, "round": _round}):
		world.fire.burn_updates.clear()
	var points := world.fire.visual_positions()
	if points.is_empty() and not _fire_visible:
		return
	var packed: Array = []
	for at in points:
		packed.append(_pack(at))
	if WebSession.send({"k": "fire", "points": packed, "round": _round}):
		_fire_visible = not points.is_empty()


func _flush_voxels(boards_only := false) -> void:
	var removed: Array[int] = world.network_removed
	var dirty := world.network_dirty.keys()
	if boards_only:
		removed = removed.filter(func(id: int): return id < 0)
		dirty = dirty.filter(func(id: int): return id < 0)
	if not removed.is_empty() and WebSession.send({"k": "gone", "ids": removed, "round": _round}):
		if boards_only:
			world.network_removed = world.network_removed.filter(func(id: int): return id > 0)
		else:
			world.network_removed.clear()
	for id in dirty.slice(0, 3):
		var o: VoxelObject = world.network_objects.get(id)
		if not is_instance_valid(o):
			world.network_dirty.erase(id)
			continue
		var raw := o.volume.get_data()
		if raw.size() > MAX_VOLUME:
			world.network_dirty.erase(id)
			continue
		var dim := o.volume.get_size()
		var packet := {
			"k": "vox", "round": _round, "id": id, "dim": [dim.x, dim.y, dim.z],
			"static": o.static_mode, "transform": _xform(o),
			"bytes": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_FASTLZ)),
		}
		if WebSession.send(packet):
			world.network_dirty.erase(id)


func _apply_voxels(packet: Dictionary) -> void:
	var id := int(packet.get("id", 0))
	if id == 0 or id > 10000 or (id < 0 and not world.network_objects.has(id)):
		return
	var d := _unpack(packet.get("dim"))
	var dim := Vector3i(d)
	var size := dim.x * dim.y * dim.z
	if dim.x <= 0 or dim.y <= 0 or dim.z <= 0 or size > MAX_VOLUME:
		return
	var compressed := Marshalls.base64_to_raw(str(packet.get("bytes", "")))
	var raw := compressed.decompress(size, FileAccess.COMPRESSION_FASTLZ)
	if raw.size() != size:
		return
	var o: VoxelObject = world.network_objects.get(id)
	if is_instance_valid(o):
		if o.volume.get_size() != dim:
			return
		o.volume.set_data(raw)
		o.mark_dirty(Vector3i.ZERO, dim - Vector3i.ONE)
	else:
		var v := Build.vol(dim)
		v.set_data(raw)
		o = VoxelObject.new()
		o.network_id = id
		o.setup(v, bool(packet.get("static", false)))
		o.transform = _decode_xform(packet["transform"])
		world.add_child(o)
		_freeze_replica(o)


func _freeze_replica(o: VoxelObject) -> void:
	if not o.static_mode:
		o.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		o.freeze = true
