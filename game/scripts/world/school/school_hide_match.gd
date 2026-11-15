class_name SchoolHideMatch
extends Node

const HEAD_START := 14.0
const ROUND_LENGTH := 330.0
const FIRST_CLUE := 60.0
const STAIRS_REUSE := 24.0
const LOCKER_DWELL := Vector2(12.0, 24.0)
const LOCKER_TOTAL := 54.0
const OPENING_FLOORS := [-2, -1, 0, 1, 2, 3]
const TEAM_SYSTEM := "Ты Шорох, товарищ по команде прячущихся в игре BREAKPOINT на карте Школа № 120. Отвечай по-русски коротко и естественно. Давай конкретные советы по игре, используя только реальные инструменты и маршруты. На другие вопросы отвечай прямо. Не обещай выполнить действие, если игра ещё не подтвердила команду. Есть двор, подвал, четыре этажа и переходы между корпусами."
const PLAN_SYSTEM := "You control the runner in a voxel hide-and-seek game. Choose only A, B or C. Prefer a safe margin; while chased, break sight. During exploration prefer the requested sector. Prefer a locker when the hunter is far and there is time before the horn."
const TACTICS := [
	{"name": "бегун", "rest": Vector2(0, 0), "cover": 0.7, "horn": 0.89, "roam": 0.64},
	{"name": "диверсант", "rest": Vector2(0.8, 3.5), "cover": 1.2, "horn": 0.62, "roam": 0.48},
	{"name": "маскировщик", "rest": Vector2(2.4, 6.4), "cover": 2.4, "horn": 0.75, "roam": 0.23},
	{"name": "любитель обходов", "rest": Vector2(0.4, 2.4), "cover": 1.5, "horn": 0.79, "roam": 0.55},
]

static var _last_openings: Array[String] = []
static var _last_tactic := -1
static var _last_floor := -20
var world: VoxelWorld
var school: SchoolLevel
var hud: Hud
var pause_menu: PauseMenu
var network: NetworkHide
var _opening_floor := -20
var _team_floor := -20
var _next_team_attempt := 0.0
var _hide_clock := 0.0
var _ordered_route_deadline := 0.0
var _ordered_route_started := false
var _sector_entered := -100.0
var _next_sector_change := 13.0
var _sector_history: Array[int] = []
var _movement_since_locker := 60.0
var _locker_visits := 0
var _locker_seconds := 0.0
var routes: SchoolHuntRoutes
var bot: VoxelAvatar
var phase := "loading"
var tactic := {}
var elapsed := 0.0
var clue_count := 0
var stunts_done := 0
var hidden_spot := -1
var combat_health := 100
var clue_zone := ""
var checked_spots := {}

var _rng := RandomNumberGenerator.new()
var _path := PackedInt64Array()
var _path_index := 0
var _goal := {}
var _passage := {}
var _passage_index := 0
var _passage_edge := Vector2i(-1, -1)
var _passage_retreat := false
var _lift_stage := 0
var _lift_started := 0.0
var _stairs_used := {}
var _landing_at := Vector3.INF
var _landing_until := 0.0
var _blocked_nodes := {}
var _recent_nodes: Array[int] = []
var _zone_heat := {}
var _events_used := {}
var _trail: Array[Dictionary] = []
var _stand_until := 0.0
var _locker_until := 0.0
var _next_clue := 0.0
var _last_clue_at := 0.0
var _paint_source := Vector3.INF
var _next_stunt := 0.0
var _think_left := 0.0
var _trail_at := 0.0
var _blocked_for := 0.0
var _detours := 0
var _goal_until := 0.0
var _last_waypoint := Vector3.INF
var _backtrack := Vector3.INF
var _head_start := HEAD_START
var _last_danger := Vector3.INF
var _danger_until := 0.0
var _danger_kind := 0
var _flee_until := 0.0
var _stamina := 1.0
var _closing := false
var _observed_gap := INF
var _pursuit := 0
var _escape_style := SchoolPursuitPolicy.BURST
var _running_pose := false
var _last_pursuit_at := -100.0
var _last_retreat := -100.0
var _step_distance := 0.0
var _next_hunt_choice := 0.0
var _velocity := 0.0
var _ground_velocity := 0.0
var _quiet_step := false
var _cloak_until := 0.0
var _cloak_piece: Node3D
var _recorder: SchoolReplayRecorder
var _last_heard_player := -100.0
var _last_player_noise := ""
var _last_player_noise_at := Vector3.INF
var _board: RoundBoard
var _board_layer: CanvasLayer
var _layer: CanvasLayer
var _waiting_room: RoomRoundUi
var _door_lock := 0.0
var _check_shape := PhysicsShapeQueryParameters3D.new()
var _brain: SchoolBrain
var _last_locker_at := -100.0
var _used_lockers := {}
var _next_maneuver := 0.0
var _tool_ready := Vector3.ZERO
var _boost_until := 0.0
var _foam_at := 0.0
var _dodge_until := 0.0
var _dodge_heading := 0.0
var _horn_origin := Vector3.INF
var _horn_depart_until := 0.0
var _roam_until := 0.0
var _visited_zones := {}
var _chat: SchoolBotChat
var _next_language_plan := 18.0
var _language_plan := ""
var _language_applied := 0
var _last_seen_by_player := -100.0
var _language_previous := {}
var _survey := SchoolSurvey.new()
var _survey_at := 0.0
var _survey_retry := 0.0
var _progress_at := Vector3.INF
var _progress_time := 0.0


func prepare() -> void:
	var standalone := not is_instance_valid(network)
	var start_ms := Time.get_ticks_msec()
	_rng.randomize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot-seed=") and arg.get_slice("=", 1).is_valid_int():
			_rng.seed = int(arg.get_slice("=", 1))
	routes = SchoolHuntRoutes.new(world, school)
	await routes.build()
	if is_instance_valid(network) and int(network.rules.zone) > 0:
		_limit_routes()
	_survey.build(routes.covers.filter(func(cover: Dictionary): return _reachable(cover)))
	if ResourceLoader.exists(SchoolBrain.PATH):
		var brain := load(SchoolBrain.PATH) as SchoolBrain
		if brain != null and brain.valid():
			_brain = brain
	var profile := _rng.randi_range(0, TACTICS.size() - 1) if _last_tactic < 0 else (
		(_last_tactic + _rng.randi_range(1, TACTICS.size() - 1)) % TACTICS.size())
	_last_tactic = profile
	tactic = TACTICS[profile]
	var player := world.player
	if standalone:
		player.hides.search_all = true
		player.hides.search_requested.connect(_search_closet)
		player.movement_enabled = false
		player.tools.input_enabled = false
		world.population.local_allowed = false
		player.tools.refresh_slots()
	if standalone or network._is_seeker(WebSession.local_side):
		player.sound_emitted.connect(_heard_seeker_sound)
	world.geometry_changed.connect(_heard_damage)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.54
	_check_shape.shape = capsule
	_check_shape.collision_mask = Layers.SOLID
	bot = VoxelAvatar.new()
	bot.name = "HidingPlayer"
	add_child(bot)
	if standalone:
		_build_hud()
		_chat = SchoolBotChat.new()
		_chat.player = player
		_chat.pause_menu = pause_menu
		add_child(_chat)
	if routes.covers.is_empty():
		if standalone:
			_finish(false, "Маршруты недоступны")
		return
	if standalone:
		start_hide()
		_waiting_room = RoomRoundUi.new()
		_waiting_room.solo_player = player
		add_child(_waiting_room)
		_waiting_room.hide_phase(true)
	else:
		bot.hide()
	if not GameState.bot_record_batch.is_empty():
		_recorder = SchoolReplayRecorder.new()
		if not _recorder.begin(GameState.bot_record_batch, _rng.seed):
			_recorder = null
	if standalone:
		_chat.say("Я прячусь. Когда начнётся поиск, слушай шаги и гудок.")
		_update_hud()
	BotLanguage.warmup.call_deferred()
	print("[bot-hide] %d route points, %d reachable, %d shelters, %d route links, %d event stations in %d ms" % [
		routes.graph.get_point_count(), routes.reachable.size(), routes.covers.size(), routes.passages.size(),
		routes.stations.size(), Time.get_ticks_msec() - start_ms])
	if _brain != null:
		print("[bot-hide] fresh brain: ", _brain.rounds, " rounds, ", _brain.scenarios, " scenarios, ", routes.lockers.size(), " reachable lockers")


func start_hide() -> void:
	var opening := _opening()
	if opening.is_empty():
		return
	bot.global_position = routes.graph.get_point_position(int(opening.node))
	bot.show()
	_last_floor = _opening_floor
	_sector_history.append(_opening_floor)
	_next_sector_change = _rng.randf_range(13.0, 22.0)
	_last_openings.append(str(opening.zone))
	if _last_openings.size() > 3:
		_last_openings.pop_front()
	phase = "hide"
	_next_clue = FIRST_CLUE if _tool_available(PlayerTools.HORN) and (not is_instance_valid(network) or network.rules.bot_clues) else INF
	_next_stunt = _rng.randf_range(75.0, 96.0)
	_set_goal(opening)
	if is_instance_valid(network):
		var next := OPENING_FLOORS.filter(func(floor_id: int): return floor_id != _opening_floor)
		_team_floor = int(next[_rng.randi_range(0, next.size() - 1)])
		_next_team_attempt = 0.0


func _inside(at: Vector3) -> bool:
	return not is_instance_valid(network) or RoomRules.contains(at, world.player.border - 0.4)


func stop_network() -> void:
	phase = "done"
	_leave_cover()
	bot.hide()
	world.sfx.loop("bot_foam", "extinguisher", Vector3.ZERO, false)
	BotLanguage.cancel(get_instance_id())


func _tool_available(tool: int) -> bool:
	return not is_instance_valid(network) or network._tool_allowed(tool)


func _bot_side() -> int:
	return RoomRules.BOT_SIDE if is_instance_valid(network) else 1


func _hunter() -> Player:
	return network.nearest_hunter(bot.global_position) if is_instance_valid(network) else world.player


func _matches_floor(cover: Dictionary, floor_id: int) -> bool:
	if floor_id == -2:
		return SchoolSurvey.area(cover.at, str(cover.zone)) == SchoolSurvey.YARD
	if floor_id == -1:
		return SchoolSurvey.key(cover.at).y == -1
	return SchoolSurvey.key(cover.at).y == floor_id and "этаж" in str(cover.zone)


func team_instruction(question: String) -> String:
	var words := question.to_lower().strip_edges()
	var target := -20
	# Если игрок указал два места, берём из фразы часть, где он обращается к боту.
	for separator: String in [", а ты", " а ты", ", ты", ". ты"]:
		if separator in words:
			words = words.get_slice(separator, 1).strip_edges()
			break
	var direct := false
	for verb: String in ["иди", "пойди", "пойдем", "пойдём", "давай на", "спрячься", "прячься", "беги", "уходи", "оставайся", "а ты на"]:
		if verb in words:
			direct = true
			break
	if not direct and not (words.begins_with("ты ") and not words.ends_with("?")):
		return ""
	if "подвал" in words or "подзем" in words:
		target = -1
	elif "двор" in words or "улиц" in words or "стадион" in words:
		target = -2
	else:
		var numbers := [["перв", "1"], ["втор", "2"], ["трет", "3"], ["четв", "4"]]
		for floor_id in 4:
			if numbers[floor_id][0] in words or (numbers[floor_id][1] in words and "этаж" in words):
				target = floor_id
				break
	if target == -20:
		return ""
	if phase != "hide":
		return "Поиск уже начался. Место для укрытия можно выбрать в начале следующего раунда."
	_team_floor = target
	_next_team_attempt = 0.0
	_ordered_route_deadline = _hide_clock + 65.0
	_ordered_route_started = true
	if not _passage.is_empty() or _backtrack.is_finite():
		return "Закончу переход и пойду туда."
	if not _route_team_order():
		_next_team_attempt = 0.0
		return "Пока не вижу свободного пути туда. Попробую найти обход."
	var names := ["во двор", "в подвал", "на первый этаж", "на второй этаж", "на третий этаж", "на четвёртый этаж"]
	return "Договорились. Ухожу %s." % names[target + 2]


func _route_team_order() -> bool:
	if _ordered_route_started and _team_floor >= 1 and bot.global_position.y < 2.9:
		var from_ground := bot.global_position
		var in_wing := absf(from_ground.x) > 10.8 and absf(from_ground.x) < 28.5 and absf(from_ground.z) < 27.9
		var in_lobby := absf(from_ground.x) < 9.4 and from_ground.z > -5.5 and from_ground.z < 12.05
		if not in_wing and not in_lobby and _plan_school_entry(from_ground):
			return true
	var options: Array[Dictionary] = []
	var from := bot.global_position
	for cover: Dictionary in routes.covers:
		if int(cover.spot) < 0 and int(cover.quality) > 0 and _reachable(cover) and _matches_floor(cover, _team_floor):
			var score := from.distance_to(cover.at) - float(cover.quality) * 1.7 + _rng.randf_range(0.0, 8.0)
			options.append({"cover": cover, "score": score})
	options.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) < float(b.score))
	for candidate in options.slice(0, 48):
		var cover: Dictionary = candidate.cover.duplicate()
		cover["ordered_floor"] = _team_floor
		cover["team_order"] = true
		if _set_goal(cover):
			_roam_until = elapsed + 55.0
			_team_floor = -20
			_sector_entered = elapsed
			return true
	return false


func _plan_school_entry(from: Vector3) -> bool:
	var id := routes.entry_inside
	if id < 0 or int(_goal.get("node", -1)) == id and not _path.is_empty():
		return false
	var at := routes.graph.get_point_position(id)
	if from.distance_squared_to(at) < 10.0:
		return false
	var goal := {"node": id, "at": at, "spot": -1, "quality": 0,
		"zone": SchoolHuntRoutes.zone(at), "tour": true, "order_entry": true}
	if not _set_goal(goal):
		return false
	_next_team_attempt = INF
	return true


func _limit_routes() -> void:
	for id in routes.graph.get_point_ids():
		if not _inside(routes.graph.get_point_position(id)):
			routes.graph.set_point_disabled(id)
	for edge: Vector2i in routes.passages.keys():
		for at: Vector3 in routes.passages[edge].path:
			if not _inside(at):
				routes.graph.disconnect_points(edge.x, edge.y, false)
				routes.passages.erase(edge)
				break
	routes.reachable.clear()
	routes._walk_component(routes.nearest(school.spawn, 5.0, true))


func _reachable(cover: Dictionary) -> bool:
	return _inside(cover.at) and routes.reachable.has(int(cover.node))


func _opening() -> Dictionary:
	var by_floor := {}
	for cover: Dictionary in routes.covers:
		var at: Vector3 = cover.at
		var ground_distance := Vector2(at.x - school.spawn.x, at.z - school.spawn.z).length_squared()
		if not _reachable(cover) or (absf(at.y - school.spawn.y) < 1.4 and ground_distance < 13.0 * 13.0) or int(cover.quality) == 0 or int(cover.spot) >= 0:
			continue
		var floor_id := SchoolSurvey.key(at).y
		if SchoolSurvey.area(at, str(cover.zone)) == SchoolSurvey.YARD:
			floor_id = -2
		if floor_id in OPENING_FLOORS:
			if not by_floor.has(floor_id):
				by_floor[floor_id] = []
			by_floor[floor_id].append(cover)
	var available := by_floor.keys()
	if available.size() > 1:
		available.erase(_last_floor)
	if available.is_empty():
		return {}
	_opening_floor = int(available[_rng.randi_range(0, available.size() - 1)])
	var choices: Array = by_floor[_opening_floor]
	var fresh := choices.filter(func(cover: Dictionary): return cover.zone not in _last_openings)
	if not fresh.is_empty():
		choices = fresh
	var best := -INF
	var selected: Dictionary = choices[0]
	for i in mini(70, choices.size()):
		var candidate: Dictionary = choices[_rng.randi_range(0, choices.size() - 1)]
		var score := float(candidate.quality) * float(tactic.cover) + _rng.randf_range(0.0, 12.0)
		if score > best:
			best = score
			selected = candidate
	return selected


func _physics_process(delta: float) -> void:
	if phase in ["loading", "done"] or not is_instance_valid(bot) or (is_instance_valid(network) and world.gadgets.frozen_for(RoomRules.BOT_SIDE)):
		return
	if world.gadgets.clock_active():
		world.sfx.loop("bot_foam", "extinguisher", bot.global_position, false)
		return
	if phase == "hide":
		_hide_clock += delta
		if not is_instance_valid(network):
			_head_start -= delta
			if _head_start <= 0.0:
				begin_seek()
				_chat.say("Время пошло. Попробуй меня поймать!")
				if is_instance_valid(_waiting_room):
					_waiting_room.open_door(true)
					_door_lock = _waiting_room.door_duration_ms() * 0.001
				else:
					world.player.movement_enabled = true
					world.player.tools.input_enabled = true
	else:
		if _door_lock > 0.0:
			_door_lock -= delta
			if _door_lock <= 0.0:
				world.player.movement_enabled = true
				world.player.tools.input_enabled = true
		elapsed += delta
		if not is_instance_valid(network) and elapsed >= ROUND_LENGTH:
			_finish(false)
			return
		if elapsed >= _next_clue and (hidden_spot < 0 or elapsed >= _locker_until):
			_emit_clue()
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = _rng.randf_range(0.25, 0.42)
		_think()
	_velocity = 0.0
	_quiet_step = false
	var from := bot.global_position
	if _backtrack.is_finite():
		_backtrack_step(delta)
	elif hidden_spot < 0 and not _cloak_active() and not _path.is_empty():
		_move(delta)
	else:
		_ground_velocity = 0.0
	var moved := from.distance_to(bot.global_position)
	_movement_since_locker += moved
	var moving_speed := minf(moved / maxf(delta, 0.001), _velocity)
	var passage_kind: String = _passage.get("kind", "")
	_running_pose = (moving_speed > 4.35 or (passage_kind == "stairs" and _rushing())) \
		and passage_kind not in ["ladder", "shaft", "pipe"]
	var crouch_pose := _quiet_step or _cloak_active() or passage_kind in ["pipe", "ventilation"] or (not _rushing() and _path.is_empty() and int(_goal.get("quality", 0)) >= 2)
	if hidden_spot < 0:
		bot.pose(moving_speed, 0.0, crouch_pose, delta, _running_pose)
	_update_boost()
	if hidden_spot < 0 and moving_speed > 0.8 and phase == "seek" and passage_kind not in ["pipe", "ladder", "shaft"]:
		_step_distance += moving_speed * delta
		if _step_distance >= (1.85 if _running_pose else (1.15 if crouch_pose else 1.48)):
			_step_distance = 0.0
			if bot.global_position.distance_squared_to(world.player.global_position) < 26.0 * 26.0:
				var floor_hit := world.raycast(bot.global_position + Vector3.UP * 0.24, bot.global_position - Vector3.UP * 0.5)
				var floor_object := floor_hit.get("collider") as VoxelObject
				var voxel := floor_object.voxel_at_hit(floor_hit.position, floor_hit.normal) if is_instance_valid(floor_object) else 0
				world.sfx.footstep(VoxMat.material_of(voxel) if voxel > 0 else VoxMat.CONCRETE,
					bot.global_position, _running_pose, crouch_pose)
	else:
		_step_distance = 0.0
	if _trail_at <= elapsed and _velocity > 0.4:
		_trail_at = elapsed + 0.32
		_trail.append({"at": bot.global_position, "yaw": bot.rotation.y, "time": elapsed})
		if _trail.size() > 12:
			_trail.pop_front()
	if _recorder != null:
		_recorder.frame(self, delta)
	var progress_time := elapsed if phase == "seek" else _hide_clock
	if progress_time >= _survey_at:
		_survey_at = progress_time + 0.36
		_survey.reveal(bot.global_position)
		_survey.watch_sector(bot.global_position, elapsed)
		_check_route_progress(progress_time)


func begin_seek() -> void:
	phase = "seek"
	_survey_at = 0.0
	_progress_time = 0.0
	_next_team_attempt = 0.0
	_stand_until = 0.0


func _process(_delta: float) -> void:
	if not is_instance_valid(network) and phase != "loading" and phase != "done":
		_update_hud()


func _think() -> void:
	var route_clock := elapsed if phase == "seek" else _hide_clock
	if _team_floor != -20 and _passage.is_empty() and not _backtrack.is_finite() and hidden_spot < 0 and route_clock >= _next_team_attempt:
		_next_team_attempt = route_clock + 1.4
		_route_team_order()
	if hidden_spot >= 0:
		if not _closet_intact(hidden_spot):
			_leave_cover()
			_stand_until = elapsed
		elif phase != "seek" or elapsed < _locker_until:
			return
		else:
			_leave_cover()
	if _cloak_active():
		if not seeker_can_see():
			return
		_cloak_until = elapsed
	for node: int in _blocked_nodes.keys():
		if float(_blocked_nodes[node]) < elapsed:
			routes.graph.set_point_disabled(node, not _inside(routes.graph.get_point_position(node)))
			_blocked_nodes.erase(node)
	if phase == "seek":
		_perceive()
	var gap := bot.global_position.distance_to(_last_danger)
	var threat := phase == "seek" and elapsed < _danger_until and gap < 22.0
	var was_rushing := _rushing()
	var engaged := threat and (was_rushing or _closing or _danger_kind == 2 or gap < (14.0 if _danger_kind == 3 else 9.0))
	var player := _hunter()
	var player_gap := player.global_position.distance_to(bot.global_position) if is_instance_valid(player) else INF
	var intercepting := player_gap < 7.5 and seeker_can_see()
	if bool(_goal.get("order_entry", false)) and not engaged and not _path.is_empty():
		return
	if bool(_goal.get("team_order", false)) and not engaged and not intercepting:
		if not _path.is_empty() and elapsed < _goal_until:
			return
		if _path.is_empty() and elapsed < _sector_entered + 24.0:
			return
	if phase == "seek" and bool(_goal.get("exit_school", false)) and not _path.is_empty() and elapsed < _goal_until:
		if not intercepting or _safe_escape_prefix(_path, _path_index):
			_flee_until = maxf(_flee_until, elapsed + 2.0)
			return
	if phase == "seek" and not intercepting and not (engaged and gap < 9.0) and elapsed >= _survey_retry and _passage.is_empty() \
			and not _backtrack.is_finite() and elapsed > 14.0 and _survey.needs_yard(elapsed, bot.global_position):
		_survey_retry = elapsed + 3.0
		if _choose_tour(SchoolSurvey.YARD):
			return
	if phase == "seek" and bool(_goal.get("tour", false)) and not _path.is_empty() and elapsed < _goal_until:
		var route_threat := intercepting or (engaged and gap < 12.0 and not _safe_escape_prefix(_path, _path_index))
		if not route_threat or elapsed < _last_retreat + 0.8:
			return
	if phase == "seek" and _passage.is_empty() and not _clearing_landing() \
			and (elapsed >= _next_language_plan or (engaged and elapsed + 5.0 < _next_language_plan)) \
			and BotLanguage.state == "ready" and (not is_instance_valid(_chat) or not _chat._waiting) and not BotLanguage.busy():
		_request_language_plan(engaged or player_gap < 18.0)
	if engaged:
		_flee_until = maxf(_flee_until, elapsed + 3.1)
	if not _passage.is_empty() or _backtrack.is_finite():
		return
	if engaged:
		if not _path.is_empty() and elapsed >= _next_maneuver \
				and (BotLanguage.state != "ready" or gap < 4.4):
			_use_maneuver(gap)
		# Уходим с площадки прежде, чем слух на соседнем этаже изменит маршрут.
		if not _path.is_empty() and _clearing_landing() and not (_danger_kind == 2 and gap < 4.0):
			return
		if was_rushing and not _path.is_empty() and gap > 4.4 and _safe_escape_prefix(_path, _path_index):
			return
		if elapsed >= _last_retreat + (0.48 if _path.is_empty() else 1.05):
			_last_retreat = elapsed
			if _start_pursuit(gap):
				return
		if _path.is_empty():
			_stand_until = elapsed
	if not _path.is_empty():
		if elapsed < _goal_until:
			return
		_abandon_goal()
	if phase == "hide" and not _goal.is_empty():
		return
	if phase == "seek" and elapsed < _sector_entered + 24.0 and not engaged:
		return
	if elapsed < _next_hunt_choice:
		return
	_next_hunt_choice = elapsed + 0.35
	if phase == "seek" and elapsed >= _survey_retry and elapsed >= _stand_until:
		if elapsed >= _next_sector_change and not engaged:
			_next_sector_change = elapsed + _rng.randf_range(31.0, 49.0)
			if _select_new_floor():
				return
		var target_area := _survey.priority(elapsed)
		if target_area != SchoolSurvey.ANY and not intercepting:
			_survey_retry = elapsed + 2.2
			if _choose_tour(target_area):
				return
	if phase == "seek" and elapsed >= _stand_until and elapsed >= _horn_depart_until and elapsed >= _next_stunt and elapsed > _danger_until and stunts_done < 3:
		if _choose_stunt():
			return
	if elapsed >= _stand_until:
		_tactical_choice(elapsed < _horn_depart_until)


func _check_route_progress(progress_time := -1.0) -> void:
	var clock := progress_time if progress_time >= 0.0 else elapsed
	if _path.is_empty() or hidden_spot >= 0 or _cloak_active() or not _passage.is_empty():
		_progress_at = bot.global_position
		_progress_time = clock
		return
	if bot.global_position.distance_squared_to(_progress_at) > 0.62 * 0.62:
		_progress_at = bot.global_position
		_progress_time = clock
	elif clock - _progress_time > 1.25 and _path_index < _path.size():
		_progress_time = clock
		_bypass(_path[_path_index])
		_think_left = 0.0


func _select_new_floor() -> bool:
	var from := bot.global_position
	var floor_id := -2 if SchoolSurvey.area(from, SchoolHuntRoutes.zone(from)) == SchoolSurvey.YARD else SchoolSurvey.key(from).y
	var candidates: Array = OPENING_FLOORS.duplicate()
	candidates.erase(floor_id)
	for recent in _sector_history:
		if candidates.size() > 1:
			candidates.erase(recent)
	for count in candidates.size():
		var target_id := int(candidates.pop_at(_rng.randi_range(0, candidates.size() - 1)))
		var options: Array[Dictionary] = []
		for cover: Dictionary in routes.covers:
			var at: Vector3 = cover.at
			if int(cover.spot) >= 0 or not _reachable(cover) or not _matches_floor(cover, target_id) or at.distance_squared_to(from) < 49.0:
				continue
			var score := float(cover.quality) * 3.0 + _survey.novelty(at) - from.distance_to(at) * 0.17 + _rng.randf_range(0.0, 8.0)
			options.append({"cover": cover, "score": score})
		options.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
		for option in options.slice(0, 12):
			var cover: Dictionary = option.cover.duplicate()
			cover["tour"] = true
			if _set_goal(cover):
				_sector_history.append(target_id)
				if _sector_history.size() > 3:
					_sector_history.pop_front()
				return true
	return false


func _choose_tour(area: int) -> bool:
	var feet := bot.global_position
	if area == SchoolSurvey.YARD and routes.entry_exit >= 0 and absf(feet.x) < 5.5 and feet.y < 2.7 and feet.z > 6.0 and feet.z < 12.5:
		var exit := routes.graph.get_point_position(routes.entry_exit)
		if _set_goal({"node": routes.entry_exit, "at": exit, "spot": -1, "tour": true, "exit_school": true, "zone": SchoolHuntRoutes.zone(exit)}):
			return true
	var options := _survey.frontier(feet, area, _rng).slice(0, 14)
	if options.size() < 8:
		options.append_array(_goal_options(false, SchoolPursuitPolicy.DETOUR, area).slice(0, 12))
	for option in options:
		var target: Dictionary = option.goal.duplicate()
		if int(target.node) in _recent_nodes or (elapsed < _danger_until and _last_danger.distance_squared_to(target.at) < 144.0):
			continue
		target["tour"] = true
		if area == SchoolSurvey.YARD and SchoolSurvey.area(feet, SchoolHuntRoutes.zone(feet)) != SchoolSurvey.YARD:
			target["exit_school"] = true
		if _set_goal(target):
			_record("explore", {"area": area, "target": SchoolReplayRecorder.vec(target.at)})
			return true
	return false


func _pursuit_context(gap: float) -> Dictionary:
	var node := routes.nearest(bot.global_position, 2.6, false, true)
	var shortcut := false
	if node >= 0:
		for neighbor: int in routes.graph.get_point_connections(node):
			var link: Dictionary = routes.passages.get(Vector2i(node, neighbor), {})
			if link.get("kind", "") in SchoolPursuitPolicy.SHORTCUT_LINKS:
				shortcut = true
				break
	var trigger := 2 if hidden_spot >= 0 else (4 if elapsed - _last_pursuit_at < 9.0 else (3 if _danger_kind == 3 else (1 if _danger_kind == 2 else 0)))
	var terrain := SchoolPursuitPolicy.terrain_at(bot.global_position, "этаж" in SchoolHuntRoutes.zone(bot.global_position),
		hidden_spot >= 0 or int(_goal.get("quality", 0)) > 1, shortcut)
	var can_feint := elapsed >= FIRST_CLUE and gap >= 5.8 and stunts_done < 3 and elapsed >= _next_stunt - 10.0
	return {"node": node, "shortcut": shortcut, "feint": can_feint,
		"obs": SchoolRlPolicy.observe(trigger, terrain, _stamina, _closing, gap, can_feint)}


func _start_pursuit(gap: float, training_action := -2) -> bool:
	var context := _pursuit_context(gap)
	var node: int = context.node
	var actions := [SchoolPursuitPolicy.DETOUR, SchoolPursuitPolicy.COVER, SchoolPursuitPolicy.SHORTCUT,
		SchoolPursuitPolicy.BURST, SchoolPursuitPolicy.FEINT]
	if training_action == -2 and _brain != null:
		actions = SchoolBrain.rank(_brain.predict(_brain_observation(context)), SchoolBrain.ROUTE, SchoolPursuitPolicy.ACTIONS, _rng)
	var preferred := training_action
	if preferred >= 0:
		actions.erase(preferred)
		actions.push_front(preferred)
	for action: int in actions:
		if (action == SchoolPursuitPolicy.SHORTCUT and not context.shortcut) or (action == SchoolPursuitPolicy.FEINT and not context.feint):
			continue
		if _choose_goal(true, action):
			_begin_sprint(action)
			return true
		if _backtrack.is_finite():
			return false
	if node >= 0 and _dodge(node):
		_begin_sprint(SchoolPursuitPolicy.BURST)
		return true
	return false


func _begin_sprint(action: int) -> void:
	_escape_style = action
	_flee_until = maxf(_flee_until, elapsed + _rng.randf_range(5.5, 8.5))
	_pursuit += 1
	_last_pursuit_at = elapsed
	if action == SchoolPursuitPolicy.FEINT and elapsed >= FIRST_CLUE and stunts_done < 3 and elapsed >= _next_stunt - 10.0:
		_local_distraction()
		_next_stunt = elapsed + _rng.randf_range(40.0, 65.0)


func _rushing() -> bool:
	if phase == "hide":
		return bool(_goal.get("team_order", false)) or bool(_goal.get("order_entry", false))
	return phase == "seek" and elapsed < maxf(_flee_until, maxf(_roam_until, maxf(_horn_depart_until, _boost_until)))


func _ground_speed(quiet := false) -> float:
	return Player.CROUCH_SPEED if quiet else (Player.SPRINT if _rushing() else Player.WALK)


func _brain_observation(context: Dictionary, tools := 0, can_locker := false) -> PackedFloat32Array:
	var observation: PackedFloat32Array = context.obs.duplicate()
	var cover := 1.0 if hidden_spot >= 0 else (0.5 if int(_goal.get("quality", 0)) > 1 else 0.0)
	var sector := SchoolHuntRoutes.zone(bot.global_position)
	observation.append_array(PackedFloat32Array([
		float(elapsed < _danger_until and _danger_kind == 2),
		cover, float(clue_count > 0 and elapsed - _last_clue_at < 15.0), elapsed / ROUND_LENGTH,
		float(can_locker), float(elapsed < _horn_depart_until),
		float((tools & 1) != 0), float((tools & 2) != 0), float((tools & 4) != 0),
		float(elapsed - float(_visited_zones.get(sector, -100.0)) < 20.0),
	]))
	return observation


func _use_maneuver(gap: float, requested := -1) -> void:
	_next_maneuver = elapsed + _rng.randf_range(2.1, 3.6)
	var tools := 1 if _tool_available(PlayerTools.EXTINGUISHER) and elapsed >= _tool_ready.x and gap < 13.5 else 0
	var placement := {}
	if gap >= 5.2 and (elapsed >= _tool_ready.y or elapsed >= _tool_ready.z):
		placement = _cover_placement()
		if not placement.is_empty():
			if _tool_available(PlayerTools.BOARD) and elapsed >= _tool_ready.y and placement.narrow:
				tools |= 2
			if _tool_available(PlayerTools.CLOTH) and elapsed >= _tool_ready.z:
				tools |= 4
	var actions := [SchoolManeuverPolicy.BOOST, SchoolManeuverPolicy.DODGE, SchoolManeuverPolicy.BOARD,
		SchoolManeuverPolicy.CLOAK, SchoolManeuverPolicy.RUN]
	if _brain != null:
		actions = SchoolBrain.rank(_brain.predict(_brain_observation(_pursuit_context(gap), tools)),
			SchoolBrain.TOOL, SchoolManeuverPolicy.ACTIONS, _rng)
	if requested >= 0:
		actions.erase(requested)
		actions.push_front(requested)
	for action: int in actions:
		if not SchoolManeuverPolicy.available(action, tools):
			continue
		match action:
			SchoolManeuverPolicy.RUN:
				return
			SchoolManeuverPolicy.DODGE:
				_dodge_until = elapsed + 1.1
				_dodge_heading = _rng.randf_range(0.0, TAU)
				_record("dodge")
				return
			SchoolManeuverPolicy.BOOST:
				_boost_until = elapsed + 1.0
				_tool_ready.x = elapsed + 14.0
				_record("foam")
				return
			SchoolManeuverPolicy.BOARD, SchoolManeuverPolicy.CLOAK:
				if _place_cover(placement, action == SchoolManeuverPolicy.CLOAK):
					return


func _cover_placement() -> Dictionary:
	var current := bot.global_position
	for i in range(_trail.size() - 1, -1, -1):
		var past: Vector3 = _trail[i].at
		var away := (current - past).slide(Vector3.UP)
		if absf(current.y - past.y) > 0.35 or away.length_squared() < 4.0 or away.length_squared() > 20.0:
			continue
		if past.distance_squared_to(_last_danger) >= current.distance_squared_to(_last_danger):
			continue
		if past.distance_squared_to(world.player.global_position) < 2.0 * 2.0:
			continue
		var normal := away.normalized()
		var across := Vector3.UP.cross(normal)
		var height := past + Vector3.UP * 0.86
		if not world.raycast(height, current + Vector3.UP * 0.86).is_empty():
			continue
		var floor_hit := world.raycast(past + Vector3.UP * 0.28, past - Vector3.UP * 0.5)
		if floor_hit.is_empty():
			continue
		var sides := [
			world.raycast(height, height + across * 2.0),
			world.raycast(height, height - across * 2.0)]
		var widths := Vector2(2.0, 2.0)
		for side in 2:
			if not sides[side].is_empty():
				widths[side] = height.distance_to(sides[side].position)
		if minf(widths.x, widths.y) < 0.42:
			continue
		var source: Dictionary = floor_hit
		if minf(widths.x, widths.y) < 1.65:
			source = sides[0 if widths.x < widths.y else 1]
		return {"at": past, "normal": normal, "across": across, "widths": widths,
			"narrow": widths.x + widths.y < 3.3, "source": source}
	return {}


func _place_cover(placement: Dictionary, fabric: bool) -> bool:
	var at: Vector3 = placement.at
	if not _tool_available(PlayerTools.CLOTH if fabric else PlayerTools.BOARD) or not _inside(at):
		return false
	var across: Vector3 = placement.across
	var normal: Vector3 = placement.normal
	var widths: Vector2 = placement.widths.clamp(Vector2(0.42, 0.42), Vector2(1.25, 1.25))
	var source: Dictionary = placement.source
	var anchor := source.collider as VoxelObject
	var voxel := anchor.voxel_at_hit(source.position, source.normal) if is_instance_valid(anchor) else 0
	var color := VoxMat.color_of(voxel) if voxel > 0 else Color("#8b806d")
	var material := VoxMat.material_of(voxel) if voxel > 0 else VoxMat.CONCRETE
	var transform: Transform3D
	var motif := 0
	var patch := ""
	var mapping: Array = []
	if fabric:
		transform = _fabric_transform(placement)
		if not bool(placement.get("narrow", false)) or not _screen_blocks_view(transform, bot.global_position):
			return false
		if voxel > 0:
			var surface_normal: Vector3 = source.normal
			var tangent := (Vector3.FORWARD if absf(surface_normal.y) > 0.9 else Vector3.UP).cross(surface_normal).normalized()
			var up := surface_normal.cross(tangent).normalized()
			var basis := transform.basis.orthonormalized()
			var offset: Vector3 = transform.origin - source.position
			motif = VoxMat.palette.get_pattern(voxel)
			patch = ToolConstruction.sample_patch(anchor, source.position, surface_normal, tangent, up, color)
			mapping = [basis.x.dot(tangent), basis.y.dot(tangent), basis.x.dot(up), basis.y.dot(up), offset.dot(tangent), offset.dot(up)]
	else:
		var center := at + Vector3.UP * 0.59
		transform = ToolConstruction.shape_between(center - across * maxf(0.22, widths.y - 0.04),
			center + across * maxf(0.22, widths.x - 0.04), normal, 0.79, 0.0)
	var piece_id := world.construction._next_id
	if not world.construction.submit(fabric, transform, color, anchor, bot.global_position, motif, patch, mapping, material):
		return false
	if fabric:
		_tool_ready.z = elapsed + 33.0
		_cloak_piece = world.construction.placed_piece(piece_id)
		_cloak_until = elapsed + _rng.randf_range(4.0, 7.0)
	else:
		_tool_ready.y = elapsed + 24.0
	world.sfx.play("hide_slide" if fabric else "hide_wood", at, -11.0)
	_record("cloak" if fabric else "board", {"pos": SchoolReplayRecorder.vec(at), "material": material})
	return true


func _fabric_transform(placement: Dictionary) -> Transform3D:
	var at: Vector3 = placement.at
	var across: Vector3 = placement.across
	var normal: Vector3 = placement.normal
	var widths: Vector2 = placement.widths.clamp(Vector2(0.42, 0.42), Vector2(1.25, 1.25))
	var center := at + across * ((widths.x - widths.y) * 0.5)
	return ToolConstruction.shape_between(center + Vector3.UP * 0.10, center + Vector3.UP * 1.92,
		normal, widths.x + widths.y, 0.0)


func _screen_blocks_view(transform: Transform3D, at: Vector3) -> bool:
	var inverse := transform.affine_inverse()
	var hunter := _hunter()
	if not is_instance_valid(hunter):
		return false
	var eye := inverse * hunter.camera.global_position
	for height: float in [0.45, 1.25]:
		var body: Vector3 = inverse * (at + Vector3.UP * height)
		if eye.z * body.z >= 0.0:
			return false
		var crossing := eye.lerp(body, eye.z / (eye.z - body.z))
		if absf(crossing.x) > 0.46 or absf(crossing.y) > 0.48:
			return false
	return true


func _concealment_site(at: Vector3) -> Dictionary:
	var seeker := _hunter()
	var hunter := seeker.global_position if is_instance_valid(seeker) else Vector3.INF
	var away := (at - hunter).slide(Vector3.UP)
	if away.length_squared() < 8.0 * 8.0 or absf(at.y - hunter.y) > 2.6:
		return {}
	var normal := away.normalized()
	var across := Vector3.UP.cross(normal)
	var screen := at - normal * 1.18
	var middle := screen + Vector3.UP * 0.84
	if not world.raycast(middle, at + Vector3.UP * 0.84).is_empty():
		return {}
	var foot := routes.floor_at(screen, 0.31)
	if not foot.is_finite():
		return {}
	var left := world.raycast(middle, middle + across * 1.62)
	var right := world.raycast(middle, middle - across * 1.62)
	if left.is_empty() and right.is_empty():
		return {}
	var widths := Vector2(middle.distance_to(left.position) if not left.is_empty() else 1.25,
		middle.distance_to(right.position) if not right.is_empty() else 1.25)
	if minf(widths.x, widths.y) < 0.44:
		return {}
	var source := left if not left.is_empty() and (right.is_empty() or widths.x <= widths.y) else right
	if not source.collider is VoxelObject:
		return {}
	return {"at": foot, "normal": normal, "across": across, "widths": widths, "narrow": true, "source": source}


func _cloak_active() -> bool:
	return elapsed < _cloak_until and is_instance_valid(_cloak_piece) and not _cloak_piece.is_queued_for_deletion() \
		and (not is_instance_valid(_hunter()) or bot.global_position.distance_squared_to(_hunter().global_position) > 5.5 * 5.5)


func _update_boost() -> void:
	var active := phase == "seek" and elapsed < _boost_until and _velocity > 0.0 and _passage.is_empty()
	var at := bot.global_position + Vector3.UP * 0.69
	world.sfx.loop("bot_foam", "extinguisher", at, active, -14.0)
	if active and elapsed >= _foam_at:
		_foam_at = elapsed + 0.095
		var behind := bot.global_basis.z
		world.fx.foam(at + behind * 0.34, behind)
		world.fire.extinguish_jet(at, at + behind * 2.0, behind)


func _dodge(start: int) -> bool:
	var current := bot.global_position
	var frontier := PackedInt64Array([start])
	var depth := {start: 0}
	var choices: Array[Dictionary] = []
	var cursor := 0
	while cursor < frontier.size() and cursor < 116:
		var origin := frontier[cursor]
		cursor += 1
		if int(depth[origin]) >= 7:
			continue
		for neighbor: int in routes.graph.get_point_connections(origin):
			var edge := Vector2i(origin, neighbor)
			if depth.has(neighbor) or routes.graph.is_point_disabled(neighbor) or _stair_on_cooldown(edge):
				continue
			if _clearing_landing() and routes.passages.get(edge, {}).get("kind") == "stairs":
				continue
			depth[neighbor] = int(depth[origin]) + 1
			frontier.append(neighbor)
			var at := routes.graph.get_point_position(neighbor)
			var distance := current.distance_to(at)
			var safety := minf(25.0, at.distance_to(_last_danger))
			var score := safety + distance * 0.52 - (4.0 if neighbor in _recent_nodes else 0.0)
			if distance >= 1.1:
				choices.append({"node": neighbor, "at": at, "spot": -1, "score": score})
	choices.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
	for choice in choices.slice(0, 7):
		if _set_goal(choice):
			return true
	return false


func _safe_escape_prefix(path: PackedInt64Array, from: int) -> bool:
	if not _last_danger.is_finite() or from >= path.size():
		return true
	var initial := bot.global_position.distance_to(_last_danger)
	var near := initial
	var limit := mini(path.size(), from + 10)
	var progress := 0.0
	for i in range(from, limit):
		var next := routes.graph.get_point_position(path[i])
		var distance := next.distance_to(_last_danger)
		near = minf(near, distance)
		progress = maxf(progress, distance - initial)
	return near >= maxf(1.85, initial - 2.45) and (limit - from < 3 or progress > 0.65)


func _tactical_choice(urgent: bool) -> bool:
	var danger := _danger_kind if elapsed < _danger_until else 0
	var can_decoy := phase == "seek" and elapsed >= FIRST_CLUE and stunts_done < 3 and elapsed > _next_stunt - 8.0
	var can_locker := phase == "seek" and not urgent and danger == 0 and elapsed >= _last_locker_at + 32.0 \
		and _next_clue - elapsed > LOCKER_DWELL.x + 4.0
	if phase == "seek" and not urgent:
		var gap := bot.global_position.distance_to(_last_danger)
		var plan := SchoolBrain.ROAM
		if _brain != null:
			var output := _brain.predict(_brain_observation(_pursuit_context(gap), 0, can_locker))
			plan = SchoolBrain.rank(output, SchoolBrain.PLAN, 4, _rng)[0]
		if can_locker and _rng.randf() < (0.31 if plan == SchoolBrain.LOCKER else 0.09) and _target_locker():
			return true
		if can_decoy and plan == SchoolBrain.DISTRACT:
			if _choose_stunt():
				return true
		if danger == 0 and elapsed >= _survey_retry:
			_survey_retry = elapsed + 7.0
			var utility := _utility_goal()
			if not utility.is_empty() and _set_goal(utility):
				return true
			if _survey.coverage() < SchoolSurvey.TARGET and _choose_tour(SchoolSurvey.ANY):
				return true
		var style := SchoolPursuitPolicy.DETOUR if plan in [SchoolBrain.ROAM, SchoolBrain.ESCAPE] else SchoolPursuitPolicy.COVER
		return _choose_goal(false, style)
	return _choose_goal(false)


func _request_language_plan(chase := false) -> void:
	_next_language_plan = elapsed + (4.2 if chase else _rng.randf_range(8.0, 13.0))
	var player := _hunter()
	if not is_instance_valid(player):
		return
	var origin := bot.global_position
	var hunter := player.global_position
	var driving := is_instance_valid(player.vehicle) and is_instance_valid(player.vehicle.body)
	var hunter_motion := player.vehicle.body.linear_velocity if driving else player.velocity
	var gap := origin.distance_to(hunter)
	var to_bot := origin + Vector3.UP * 1.05 - player.camera.global_position
	var visible := seeker_can_see()
	if visible:
		_last_seen_by_player = elapsed
	var forecast := hunter_motion.slide(Vector3.UP).limit_length(8.5)
	if visible and forecast.length_squared() < 1.0:
		forecast = to_bot.slide(Vector3.UP).normalized() * 4.2
	var intercept := hunter + forecast * 2.6
	var obstruction := world.raycast(hunter + Vector3.UP, intercept + Vector3.UP, Layers.STATIC)
	if not obstruction.is_empty():
		intercept = Vector3(obstruction.position) - Vector3.UP
	var options := _language_routes(chase, hunter, intercept)
	if options.size() < 2:
		return
	var survey_goal := _survey.priority(elapsed)
	var prompt := "Mode %s. Requested sector %s. Horn in %ds. Runner %s. Hunter %s, velocity %s, sees runner %s, intercept %s.\n" % [
		"chase" if chase else "explore", ["any", "yard", "basement", "upper"][survey_goal],
		roundi(maxf(0.0, _next_clue - elapsed)) if is_finite(_next_clue) else -1, origin.round(), hunter.round(), hunter_motion.round(), visible, intercept.round()]
	prompt += "Hunter facing %s, tool %d, crouch %s, vehicle %s, sprint %s. Runner sector %s. Seconds %d.\n" % [
		player.aim_dir().snapped(Vector3.ONE * 0.1), player.tools.current, bool(player.get_meta("room_crouch", player.crouching)),
		driving, player.is_sprinting(), SchoolHuntRoutes.zone(origin), int(network._remaining if is_instance_valid(network) else ROUND_LENGTH - elapsed)]
	var elevator := (world.secrets as SchoolSecrets).elevator
	prompt += "Hunter health %d, sector %s. Explored %.0f percent. Lift stop %d, moving %s.\n" % [
		player.health, SchoolHuntRoutes.zone(hunter), _survey.coverage() * 100.0, elevator.stop, elevator.busy]
	if elapsed - _last_seen_by_player < 12.0 and not visible:
		prompt += "Hunter saw runner recently.\n"
	if elapsed - _last_heard_player < 8.0:
		prompt += "Recent hunter sound: %s at %s.\n" % [_last_player_noise, _last_player_noise_at.round()]
	if chase and not _language_previous.is_empty() and elapsed - float(_language_previous.time) < 12.0:
		var previous_origin: Vector3 = _language_previous.at
		prompt += "Previous plan moved %.0fm and changed separation by %+.0fm.\n" % [
			previous_origin.distance_to(origin), gap - float(_language_previous.gap)]
	var codes := "ABC".left(options.size())
	var decision_options: Array[Dictionary] = []
	for i in options.size():
		var option: Dictionary = options[i]
		var goal: Vector3 = option.goal.at
		prompt += "%s: %s, target %s, danger margin %.0fm, length %.0fm.\n" % [
			codes[i], option.label, goal.round(), option.margin, option.length]
		if _recorder != null:
			decision_options.append({"key": codes[i], "label": option.label, "target": SchoolReplayRecorder.vec(goal),
				"route": option.style, "tool": option.tool, "margin": option.margin, "length": option.length})
	var requested_at := elapsed
	var plan := await BotLanguage.generate(get_instance_id(), [
		{"role": "system", "content": PLAN_SYSTEM}, {"role": "user", "content": prompt}], 4, "[" + codes + "]")
	_record("qwen", {"choice": plan, "options": decision_options, "context": prompt, "system": PLAN_SYSTEM, "chase": chase})
	if not is_instance_valid(player) or phase != "seek" or elapsed - requested_at > (3.8 if chase else 5.0) or plan.length() != 1 or plan not in codes:
		return
	_language_plan = plan
	if not _passage.is_empty() or _clearing_landing() or hidden_spot >= 0 or elapsed < _horn_depart_until:
		return
	if not chase and elapsed < _danger_until and bot.global_position.distance_to(_last_danger) < 12.0:
		return
	var selection: Dictionary = options[codes.find(plan)]
	if not _path.is_empty():
		var committed := bool(_goal.get("team_order", false)) or bool(_goal.get("tour", false)) or int(_goal.get("spot", -1)) >= 0 or _goal.has("utility")
		if (committed and not chase) or (bool(_goal.get("exit_school", false)) and _safe_escape_prefix(_path, _path_index)):
			return
	if chase and bot.global_position.distance_to(player.global_position) < 12.0:
		_notice(player.global_position, 3.0, 2 if visible else 1)
	if not _set_goal(selection.goal, false, chase):
		return
	_language_applied += 1
	_record("qwen_applied", {"choice": plan, "target": SchoolReplayRecorder.vec(selection.goal.at), "chase": chase})
	if chase:
		_begin_sprint(int(selection.style))
		_language_previous = {"at": bot.global_position, "gap": bot.global_position.distance_to(player.global_position), "time": elapsed}
		if elapsed >= _next_maneuver:
			_use_maneuver(bot.global_position.distance_to(player.global_position), int(selection.tool))


func _language_routes(chase: bool, hunter: Vector3, intercept: Vector3) -> Array[Dictionary]:
	var start := routes.nearest(bot.global_position, 3.65, true, true)
	var result: Array[Dictionary] = []
	if start < 0:
		return result
	var gap := bot.global_position.distance_to(hunter)
	var style := SchoolPursuitPolicy.DETOUR
	if _brain != null:
		var context := _pursuit_context(gap)
		var output := _brain.predict(_brain_observation(context))
		style = SchoolBrain.rank(output, SchoolBrain.ROUTE, SchoolPursuitPolicy.ACTIONS, _rng)[0]
	var area := _survey.priority(elapsed) if not chase and _path.is_empty() else SchoolSurvey.ANY
	var samples := _goal_options(chase, style, area)
	if samples.size() < 2:
		samples = _goal_options(chase, style)
	if not chase:
		var utility := _utility_goal()
		if not utility.is_empty():
			samples.insert(mini(2, samples.size()), {"goal": utility})
		if _next_clue - elapsed > LOCKER_DWELL.x + 4.0:
			var lockers := _locker_options()
			if not lockers.is_empty():
				samples.insert(mini(1, samples.size()), lockers[0])
		if elapsed >= _tool_ready.z:
			for item in samples.slice(0, 12):
				if int(item.goal.spot) >= 0 or int(item.goal.quality) == 0:
					continue
				var site := _concealment_site(item.goal.at)
				if not site.is_empty() and _screen_blocks_view(_fabric_transform(site), item.goal.at):
					var shelter: Dictionary = item.goal.duplicate()
					shelter["cloak"] = true
					samples.insert(mini(2, samples.size()), {"goal": shelter})
					break
		if elapsed >= FIRST_CLUE and stunts_done < 3 and elapsed >= _next_stunt:
			for station in routes.stations:
				var at: Vector3 = station.at
				if not _events_used.has(station.key) and at.distance_squared_to(bot.global_position) < 34.0 * 34.0:
					var target := {"node": station.node, "at": at, "spot": -1, "event": station.key,
						"zone": SchoolHuntRoutes.zone(at)}
					samples.insert(mini(2, samples.size()), {"goal": target})
					break
	var zones := {}
	var tools: Array[int] = [SchoolManeuverPolicy.DODGE]
	if chase and elapsed >= _next_maneuver:
		if elapsed >= _tool_ready.x and gap < 13.5:
			tools.push_front(SchoolManeuverPolicy.BOOST)
		if gap >= 5.2 and (elapsed >= _tool_ready.y or elapsed >= _tool_ready.z):
			var placement := _cover_placement()
			if not placement.is_empty():
				if placement.narrow and elapsed >= _tool_ready.y:
					tools.append(SchoolManeuverPolicy.BOARD)
				if elapsed >= _tool_ready.z:
					tools.append(SchoolManeuverPolicy.CLOAK)
	if _brain != null and tools.size() > 1:
		var mask := 0
		for tool in tools:
			if tool >= SchoolManeuverPolicy.BOOST:
				mask |= 1 << (tool - SchoolManeuverPolicy.BOOST)
		var preferences := _brain.predict(_brain_observation(_pursuit_context(gap), mask))
		var order := SchoolBrain.rank(preferences, SchoolBrain.TOOL, SchoolManeuverPolicy.ACTIONS, _rng)
		tools.sort_custom(func(a: int, b: int): return order.find(a) < order.find(b))
	for candidate in samples.slice(0, 22):
		var goal: Dictionary = candidate.goal
		var key := str(SchoolSurvey.key(goal.at)) if area != SchoolSurvey.ANY else str(goal.zone)
		key += " · locker" if int(goal.spot) >= 0 else (" · special" if goal.has("event") or goal.has("cloak") or goal.has("utility") else "")
		if zones.has(key) or (int(goal.spot) >= 0 and not _locker_allowed(int(goal.spot))):
			continue
		var path := routes.graph.get_id_path(start, int(goal.node))
		if path.size() < 3 or not _route_clear(path) or (chase and not _safe_escape_prefix(path, 0)):
			continue
		var margin := INF
		var length := 0.0
		var shortcut := false
		var lift_route := false
		var duct_route := false
		var previous := routes.graph.get_point_position(start)
		for i in range(1, path.size()):
			var point := routes.graph.get_point_position(path[i])
			length += point.distance_to(previous)
			var link: Dictionary = routes.passages.get(Vector2i(path[i - 1], path[i]), {})
			shortcut = shortcut or link.get("kind", "") in ["pipe", "booth", "shaft"]
			lift_route = lift_route or link.get("kind", "") == "lift"
			duct_route = duct_route or link.get("kind", "") == "ventilation"
			if length > 3.0 and length < 27.0:
				margin = minf(margin, point.distance_to(hunter.lerp(intercept, clampf(length / 18.0, 0.0, 1.0))))
			previous = point
		if chase and margin < 2.2:
			continue
		zones[key] = true
		var tool := tools[result.size() % tools.size()]
		var sector: String = ["interior", "yard", "basement", "upper"][SchoolSurvey.area(goal.at, str(goal.zone))]
		var label := ("locker" if int(goal.spot) >= 0 else ("secret passage" if shortcut else "run with turns")) + " in " + sector
		if lift_route or duct_route:
			label += " via " + ("elevator" if lift_route else "ventilation")
		if goal.has("event"):
			label = "divert hunter with a school device"
		elif goal.has("cloak"):
			label = "hide behind a wall-matched chameleon screen"
		elif goal.has("utility"):
			label = "interact with " + str(goal.utility)
		if chase:
			label += ["", " + dodge", " + foam boost", " + board behind", " + concealment"][tool]
		result.append({"goal": goal, "label": label, "margin": minf(margin, 35.0), "length": length,
			"style": SchoolPursuitPolicy.SHORTCUT if shortcut else style, "tool": tool})
		if result.size() == 3:
			break
	return result


func _utility_goal() -> Dictionary:
	if elapsed < 28.0 or seeker_can_see():
		return {}
	var traps := (world.secrets as SchoolSecrets).traps
	for key in ["lobby_hatch", "guard_key", "director_key", "safe", "picture", "mains"]:
		if not traps.bot_utility_ready(key, 1):
			continue
		var target := routes.utility_approach(key)
		if not target.is_empty() and bot.global_position.distance_squared_to(target.at) < 32.0 * 32.0:
			return target
	return {}


func _perceive() -> void:
	var player := _hunter()
	if not is_instance_valid(player):
		return
	var relative := player.global_position - bot.global_position
	var distance := relative.length()
	var crouching := bool(player.get_meta("room_crouch", player.crouching))
	var motion := absf(player.vehicle.speed) if player.vehicle else player.velocity.length()
	var coming := player.velocity.dot(-relative.normalized()) > 0.65 or distance + 0.16 < _observed_gap
	if player.hide_spot >= 0 or player.dead or hidden_spot >= 0:
		if (hidden_spot >= 0 and not player.dead and motion > 0.85 and absf(relative.y) < 2.15
				and distance < (4.9 if crouching else (11.5 if player.is_sprinting() else 8.9))):
			_closing = coming
			_observed_gap = distance
			_notice(player.global_position, 5.5)
		return
	var eye := bot.global_position + Vector3.UP * 1.30
	var to := player.camera.global_position - eye
	if (distance < 29.0 and -bot.global_basis.z.dot(to.normalized()) > 0.26 and world.raycast(eye, eye + to, Layers.SOLID | Layers.CLOTH).is_empty()
			and not world.secrets.obscures(eye, eye + to)):
		_closing = coming
		_observed_gap = distance
		_notice(player.global_position, 8.0, 2)
		return
	var hearing := 6.0 if crouching else (16.0 if player.is_sprinting() or player.vehicle else 10.0)
	if motion > 1.7 and distance < hearing and absf(to.y) < 2.8:
		_closing = coming
		_observed_gap = distance
		_notice(player.global_position, 5.0)
	elif elapsed >= _danger_until:
		_observed_gap = INF
		_closing = false


func _heard_damage(at: Vector3, radius: float) -> void:
	if _recorder != null:
		_record("damage", {"pos": SchoolReplayRecorder.vec(at), "radius": radius})
	if phase == "seek" and hidden_spot < 0 and bot.global_position.distance_squared_to(at) < pow(minf(22.0, 9.0 + radius * 2.5), 2.0):
		_notice(at, 6.0, 3)


func _heard_seeker_sound(at: Vector3, range_metres: float, kind: String) -> void:
	if phase != "seek" or not is_instance_valid(bot):
		return
	if _recorder != null:
		_record("player_sound", {"kind": kind, "pos": SchoolReplayRecorder.vec(at), "range": range_metres})
	if elapsed - _last_heard_player < (0.8 if kind == "step" else 0.18):
		return
	var distance := bot.global_position.distance_to(at)
	if distance > range_metres:
		return
	var ear := bot.global_position + Vector3.UP * 1.25
	if not world.raycast(ear, at + Vector3.UP * 0.75, Layers.STATIC).is_empty():
		range_metres *= 0.70 if kind in ["horn", "shot"] else 0.46
	if absf(bot.global_position.y - at.y) > 2.6:
		range_metres *= 0.72
	if distance > range_metres:
		return
	_last_heard_player = elapsed
	_last_player_noise = kind
	_last_player_noise_at = at
	_record("heard_player", {"kind": kind, "pos": SchoolReplayRecorder.vec(at), "distance": snappedf(distance, 0.1)})
	if hidden_spot >= 0:
		return
	if elapsed >= _danger_until or _danger_kind != 2:
		_notice(at, 4.8 if kind == "step" else 7.0, 1)
	_flee_until = maxf(_flee_until, elapsed + (4.8 if kind == "step" else 7.5))
	_next_language_plan = minf(_next_language_plan, elapsed)
	_stand_until = elapsed
	_cloak_until = elapsed
	_think_left = 0.0
	_next_hunt_choice = elapsed


func _notice(at: Vector3, duration: float, kind := 1) -> void:
	if kind == 3 and _danger_kind == 2 and elapsed + 5.5 < _danger_until:
		return
	_last_danger = at
	_danger_until = elapsed + duration
	_danger_kind = kind
	_zone_heat[SchoolHuntRoutes.zone(at)] = elapsed + 47.0


func _choose_goal(escape: bool, style := SchoolPursuitPolicy.BURST) -> bool:
	var options := _goal_options(escape, style)
	for option: Dictionary in options.slice(0, 13):
		if _set_goal(option.goal, false, escape, style == SchoolPursuitPolicy.SHORTCUT):
			return true
		if _backtrack.is_finite():
			return false
	if not escape and _clearing_landing():
		var start := routes.nearest(bot.global_position, 3.65, true, true)
		if start >= 0:
			return _dodge(start)
	return false


func _goal_options(escape: bool, style: int, area := SchoolSurvey.ANY) -> Array[Dictionary]:
	var current := bot.global_position
	var current_zone := SchoolHuntRoutes.zone(current)
	var departing := elapsed < _horn_depart_until
	var min_distance := 14.0 if _clearing_landing() else (10.0 if escape else 13.0)
	var options: Array[Dictionary] = []
	for i in 110:
		var pool := routes.covers
		if area == SchoolSurvey.YARD and not routes.outdoor_covers.is_empty():
			pool = routes.outdoor_covers
		elif area == SchoolSurvey.BASEMENT and not routes.basement_covers.is_empty():
			pool = routes.basement_covers
		elif i % 5 == 1 and not routes.outdoor_covers.is_empty():
			pool = routes.outdoor_covers
		elif i % 5 == 3 and not routes.basement_covers.is_empty():
			pool = routes.basement_covers
		var candidate := pool[_rng.randi_range(0, pool.size() - 1)]
		var node: int = candidate.node
		var at: Vector3 = candidate.at
		if area != SchoolSurvey.ANY and SchoolSurvey.area(at, str(candidate.zone)) != area:
			continue
		if _blocked_nodes.has(node) or node in _recent_nodes or at.distance_squared_to(current) < min_distance * min_distance:
			continue
		if int(candidate.spot) >= 0 and (escape or not _locker_allowed(int(candidate.spot))):
			continue
		var distance := at.distance_to(current)
		if distance > (56.0 if escape else 123.0):
			continue
		var score := _rng.randf_range(0.0, 16.0) + float(candidate.quality) * float(tactic.cover)
		score += _survey.novelty(at) * (0.55 if escape else 1.8)
		if area != SchoolSurvey.ANY:
			score -= distance * 0.21
		if candidate.zone != current_zone:
			score += 5.0
		if candidate.zone != current_zone and (at.y < -2.0 or (at.y < 4.0 and "этаж" not in str(candidate.zone))):
			score += 4.0
		if not escape and absf(at.y - current.y) < 1.0:
			score += 2.0
		score -= clampf(20.0 - (elapsed - float(_visited_zones.get(candidate.zone, -100.0))), 0.0, 20.0) * 0.41
		if departing:
			var horn_gap := at.distance_to(_horn_origin)
			if horn_gap < 12.0:
				continue
			score += minf(horn_gap, 34.0) * 0.22
		if float(_zone_heat.get(candidate.zone, -1.0)) > elapsed:
			score -= 8.0
		if _last_danger.is_finite() and elapsed < _danger_until:
			score += minf(at.distance_to(_last_danger), 47.0) * (0.32 if escape else 0.14)
			if at.distance_squared_to(_last_danger) < (169.0 if escape else 49.0):
				continue
		if not escape and float(tactic.roam) >= 0.5:
			score += minf(distance, 55.0) * 0.11
		if escape:
			match style:
				SchoolPursuitPolicy.COVER: score += float(candidate.quality) * 4.1
				SchoolPursuitPolicy.SHORTCUT: score += absf(at.y - current.y) * 2.4
				SchoolPursuitPolicy.FEINT: score += minf(distance, 30.0) * 0.16
				SchoolPursuitPolicy.DETOUR: score += minf(distance, 39.0) * 0.24
		elif style == SchoolPursuitPolicy.COVER:
			score += float(candidate.quality) * 3.6 - distance * 0.08
		elif style == SchoolPursuitPolicy.DETOUR:
			score += minf(distance, 78.0) * 0.13
		options.append({"goal": candidate, "score": score})
	options.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
	return options


func _locker_allowed(id: int) -> bool:
	return id >= 0 and phase == "seek" and elapsed >= _last_locker_at + 50.0 and _movement_since_locker >= 35.0 \
		and _locker_visits < 3 and _locker_seconds <= LOCKER_TOTAL - LOCKER_DWELL.x and id != world.player.hide_spot and id != hidden_spot and not checked_spots.has(id) \
		and (not is_instance_valid(network) or id not in world.player.hides.remote_spots) \
		and elapsed >= float(_used_lockers.get(id, -100.0)) + 55.0 and _closet_intact(id)


func _target_locker() -> bool:
	for option: Dictionary in _locker_options().slice(0, 8):
		if _set_goal(option.goal):
			return true
	return false


func _locker_options() -> Array[Dictionary]:
	var at := bot.global_position
	var options: Array[Dictionary] = []
	for locker in routes.lockers:
		var target: Vector3 = locker.at
		var distance := target.distance_to(at)
		if distance < 3.0 or distance > 32.0 or not _locker_allowed(int(locker.spot)):
			continue
		if _last_danger.is_finite() and elapsed < _danger_until and target.distance_squared_to(_last_danger) < 18.0 * 18.0:
			continue
		var cost := distance + absf(target.y - at.y) * 3.2 + _rng.randf_range(0.0, 8.0)
		options.append({"goal": locker, "cost": cost})
	options.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.cost) < float(b.cost))
	return options


func _clearing_landing() -> bool:
	return elapsed < _landing_until and bot.global_position.distance_squared_to(_landing_at) < 11.0 * 11.0


func _stairs_key(edge: Vector2i) -> Vector2i:
	return Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))


func _stair_on_cooldown(edge: Vector2i) -> bool:
	return elapsed < float(_stairs_used.get(_stairs_key(edge), -1.0))


func _route_clear(path: PackedInt64Array) -> bool:
	if is_instance_valid(network):
		for node in path:
			if not _inside(routes.graph.get_point_position(node)):
				return false
	for i in range(1, path.size()):
		var edge := Vector2i(path[i - 1], path[i])
		if _stair_on_cooldown(edge):
			return false
		if is_instance_valid(network) and routes.passages.has(edge):
			for at: Vector3 in routes.passages[edge].path:
				if not _inside(at):
					return false
	return true


func _choose_stunt() -> bool:
	_next_stunt = elapsed + _rng.randf_range(40.0, 74.0)
	var start := routes.nearest(bot.global_position, 3.65, true, true)
	var options: Array[Dictionary] = []
	for station: Dictionary in routes.stations:
		var at: Vector3 = station.at
		if start < 0 or _events_used.has(station.key) or at.distance_squared_to(bot.global_position) > 42.0 * 42.0:
			continue
		var path := routes.graph.get_id_path(start, int(station.node))
		if not path.is_empty() and path.size() <= 39:
			options.append({"target": station, "cost": float(path.size()) + _rng.randf_range(0.0, 8.5)})
	options.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.cost) < float(b.cost))
	for option: Dictionary in options:
		var station: Dictionary = option.target
		if _set_goal({"node": station.node, "at": station.at, "spot": -1, "event": station.key}):
			return true
	_local_distraction()
	return true


func _set_goal(candidate: Dictionary, detour := false, escape := false, shortcut := false) -> bool:
	var start := routes.nearest(bot.global_position, 3.65, true, true)
	if start < 0 and _last_waypoint.is_finite() and _last_waypoint.distance_squared_to(bot.global_position) < 3.8:
		_backtrack = _last_waypoint
		return false
	var end: int = candidate.node
	if start < 0 or routes.graph.is_point_disabled(end):
		return false
	var planned := routes.graph.get_id_path(start, end)
	if planned.is_empty() or not _route_clear(planned) or (escape and not _safe_escape_prefix(planned, 0)):
		return false
	if shortcut:
		var uses_shortcut := false
		for i in range(1, mini(planned.size(), 12)):
			var link: Dictionary = routes.passages.get(Vector2i(planned[i - 1], planned[i]), {})
			if link.get("kind", "") in SchoolPursuitPolicy.SHORTCUT_LINKS:
				uses_shortcut = true
				break
		if not uses_shortcut:
			return false
	_leave_cover()
	_goal = candidate
	_path = planned
	if _recorder != null:
		_record("route", {"target": SchoolReplayRecorder.vec(candidate.at), "zone": candidate.get("zone", ""),
			"nodes": planned.size(), "escape": escape, "locker": candidate.spot})
	if phase == "seek" and not escape and not detour and elapsed >= _horn_depart_until:
		var quiet_destination := int(candidate.spot) >= 0 or candidate.has("cloak")
		var sprint := not quiet_destination or _rng.randf() < 0.88
		_roam_until = elapsed + clampf(planned.size() * 0.30 + 4.0, 6.0, 26.0) if sprint else elapsed
	if candidate.has("tour"):
		_roam_until = elapsed + clampf(planned.size() * 0.36 + 7.0, 10.0, 46.0)
	_path_index = 0
	_blocked_for = 0.0
	if not detour:
		_detours = 0
		_goal_until = elapsed + clampf(14.0 + float(planned.size()) * 0.53, 21.0, 47.0)
	_stand_until = elapsed + 1.0
	return true


func _leave_cover() -> void:
	if hidden_spot < 0:
		return
	if not is_instance_valid(network):
		world.player.hides.set_remote(-1)
	_record("leave_locker", {"id": hidden_spot})
	hidden_spot = -1
	_locker_until = 0.0
	bot.show()


func _move(delta: float) -> void:
	if not _passage.is_empty():
		_move_passage(delta)
		return
	while _path_index < _path.size():
		var id := _path[_path_index]
		var point := routes.graph.get_point_position(id)
		if bot.global_position.distance_squared_to(point) >= 0.15 * 0.15:
			break
		_last_waypoint = point
		if _path_index + 1 < _path.size():
			var edge := Vector2i(id, _path[_path_index + 1])
			var passage: Dictionary = routes.passages.get(edge, {})
			if not passage.is_empty():
				if _stair_on_cooldown(edge):
					_abandon_goal()
					_think_left = 0.0
					return
				_passage = passage
				_passage_index = 1
				_passage_edge = edge
				_passage_retreat = false
				_lift_stage = 0
				_lift_started = elapsed
				_path_index += 1
				_record("passage", {"kind": passage.kind, "from": id, "to": edge.y})
				return
		_path_index += 1
	if _path_index >= _path.size():
		_arrive()
		return
	var id := _path[_path_index]
	var point := routes.graph.get_point_position(id)
	var quiet := (int(_goal.get("spot", -1)) >= 0 or _goal.has("cloak")) and _path_index >= _path.size() - 2 \
		and elapsed >= maxf(_flee_until, _horn_depart_until)
	_quiet_step = quiet
	_ground_velocity = lerpf(_ground_velocity, _ground_speed(quiet), 1.0 - exp(-14.0 * delta))
	var speed := _ground_velocity
	var step := bot.global_position.move_toward(point, speed * delta)
	var direction := (point - bot.global_position).slide(Vector3.UP).normalized()
	if elapsed < _dodge_until and step.distance_squared_to(point) > 0.16:
		var side := direction.cross(Vector3.UP) * sin(elapsed * 10.0 + _dodge_heading) * speed * delta * 0.31
		var sidestep := routes.floor_at(step + side, 0.38)
		if sidestep.is_finite() and _advance_to(sidestep, false):
			_velocity = speed
			_blocked_for = 0.0
			return
	var floor := routes.floor_at(step, 0.43)
	if floor.is_finite() and _advance_to(floor, true):
		_velocity = speed
		_blocked_for = 0.0
		return
	for angle in [-0.66, 0.66]:
		var side := bot.global_position + direction.rotated(Vector3.UP, angle) * speed * delta
		var detour := routes.floor_at(side, 0.43)
		if detour.is_finite() and _advance_to(detour, false):
			_velocity = speed * 0.8
			break
	_blocked_for += delta
	if _blocked_for >= (0.57 if _rushing() else 0.83):
		_bypass(id)


func _advance_to(at: Vector3, open_door: bool) -> bool:
	if not _inside(at):
		return false
	_check_shape.transform.origin = at + Vector3.UP * 0.78
	var blockers := world.get_world_3d().direct_space_state.intersect_shape(_check_shape, 4)
	for hit: Dictionary in blockers:
		var body := hit.collider as Node
		if open_door and body and body.has_node("DistrictDoor"):
			var door := body.get_node("DistrictDoor") as DistrictDoor
			if not door.opened:
				door.interact(bot.global_position, world.player.global_position)
	if not blockers.is_empty():
		return false
	_turn(at)
	bot.global_position = at
	return true


func _turn(at: Vector3) -> void:
	var direction := (at - bot.global_position).slide(Vector3.UP)
	if direction.length_squared() > 0.0005:
		bot.rotation.y = lerp_angle(bot.rotation.y, atan2(-direction.x, -direction.z), 0.22)


func _move_passage(delta: float) -> void:
	var points: PackedVector3Array = _passage.path
	var kind: String = _passage.kind
	if kind == "lift":
		_move_lift(delta, points[-1])
		return
	if _passage_index >= points.size():
		_finish_passage(kind)
		return
	var goal := points[_passage_index]
	if kind == "booth" and _passage_index == 2:
		if not _advance_to(goal, false):
			_bypass(_path[_path_index])
			return
		world.sfx.play("hide_slide", goal, -8.0)
		_passage_index += 1
		return
	if bot.global_position.distance_squared_to(goal) < 0.11 * 0.11:
		_passage_index += 1
		return
	var speed := 10.5 if kind == "pipe" else (3.45 if kind in ["ladder", "shaft", "ventilation"] else _ground_speed())
	var step := bot.global_position.move_toward(goal, delta * speed)
	if kind == "stairs":
		var chest := Vector3.UP * 0.89
		var stride := (goal - step).slide(Vector3.UP).normalized()
		var supported := routes.floor_at(step, 0.47).is_finite() or routes.floor_at(step + stride * 0.27, 0.47).is_finite()
		if not supported or not world.raycast(bot.global_position + chest, step + chest, Layers.STATIC).is_empty():
			_retreat_stairs(points)
			return
		_turn(step)
		bot.global_position = step
	elif kind in ["doorway", "entrance", "booth"]:
		if kind == "entrance" and absf(bot.global_position.z - 12.24) < 2.3:
			for leaf in school.entry_doors:
				if is_instance_valid(leaf) and is_instance_valid(leaf.body) and not leaf.opened:
					leaf.interact(bot.global_position, world.player.global_position)
		var chest := Vector3.UP * 0.82
		var obstruction := world.raycast(bot.global_position + chest, step + chest, Layers.STATIC)
		if not obstruction.is_empty():
			var body := obstruction.collider as Node
			var door := body.get_node_or_null("DistrictDoor") as DistrictDoor if is_instance_valid(body) else null
			if is_instance_valid(door) and not door.opened:
				door.interact(bot.global_position, world.player.global_position)
			_blocked_for += delta
			if _blocked_for > 1.15:
				_bypass(_path[_path_index])
			return
		var clearance_step := step
		if kind == "entrance":
			# На пороге капсула задевает вертикальную грань ступени раньше, чем
			# центр игрока до неё доходит. Поднимаем капсулу на высоту ступени.
			var forward := (goal - step).slide(Vector3.UP).normalized()
			var sill := routes.floor_at(step + forward * 0.22, 0.43)
			if sill.is_finite() and sill.y > step.y and sill.y - step.y <= 0.29:
				clearance_step.y = sill.y
		if not _advance_to(clearance_step, true):
			_blocked_for += delta
			if _blocked_for > 1.15:
				_bypass(_path[_path_index])
			return
	else:
		_turn(step)
		bot.global_position = step
	_velocity = speed
	_blocked_for = 0.0


func _request_lift(lift: SchoolElevator, floor: int, inside: bool) -> bool:
	if not is_instance_valid(network):
		return lift.request_for_bot(floor, bot.global_position, inside)
	var key := ("lift_floor/" if inside else "lift_call/") + str(floor)
	if not lift.can_move(key, floor, bot.global_position, world.player.global_position):
		return false
	var event := lift.controller.authorize(key, _bot_side(), bot.global_position, false, false, true)
	if event.is_empty():
		return false
	WebSession.send({"k": "secret_state", "event": event, "round": network._round})
	return true


func _move_lift(delta: float, exit: Vector3) -> void:
	var lift := (world.secrets as SchoolSecrets).elevator
	var source: int = _passage.from
	var destination: int = _passage.to
	if elapsed - _lift_started > 17.0 and not lift.busy and _lift_stage == 0:
		_bypass(_path[_path_index])
		return
	match _lift_stage:
		0:
			if lift.busy:
				return
			if lift.stop != source or not lift.doors_open:
				_request_lift(lift, source, false)
				return
			_lift_stage = 1
		1:
			if lift.busy:
				return
			if lift.stop != source or not lift.doors_open:
				_lift_stage = 0
				return
			if elapsed - _lift_started > 17.0:
				if _lift_walk(lift.landing(source), delta):
					_bypass(_path[_path_index])
				return
			var inside := lift.cabin_feet()
			if _lift_walk(inside, delta) and _request_lift(lift, destination, true):
				_lift_stage = 2
				_record("lift_ride", {"from": source, "to": destination})
		2:
			bot.global_position = lift.cabin_feet()
			if not lift.busy and lift.stop == destination and lift.doors_open:
				_lift_stage = 3
		3:
			if _lift_walk(exit, delta):
				_finish_passage("lift")


func _lift_walk(target: Vector3, delta: float) -> bool:
	if bot.global_position.distance_squared_to(target) <= 0.12 * 0.12:
		return true
	var speed := Player.WALK
	var step := bot.global_position.move_toward(target, speed * delta)
	if _advance_to(step, false):
		_velocity = speed
	return false


func _finish_passage(kind: String) -> void:
	if kind == "stairs" and _passage_edge.x >= 0:
		_stairs_used[_stairs_key(_passage_edge)] = elapsed + STAIRS_REUSE
		_landing_at = bot.global_position
		_landing_until = elapsed + 8.0
		_last_waypoint = _landing_at
	_passage = {}
	_passage_edge = Vector2i(-1, -1)
	# Индекс уже указывает на узел площадки. Оставляем его, чтобы _move
	# обнаружил следующий пролёт, если два перехода следуют подряд.
	if _passage_retreat:
		_passage_retreat = false
		_abandon_goal()
		_think_left = 0.0


func _retreat_stairs(points: PackedVector3Array) -> void:
	if _passage_edge.x >= 0:
		_stairs_used[_stairs_key(_passage_edge)] = elapsed + STAIRS_REUSE
	if _passage_retreat:
		_bypass(_path[_path_index])
		return
	var retreat := PackedVector3Array([bot.global_position])
	for i in range(_passage_index - 1, -1, -1):
		retreat.append(points[i])
	_passage = {"kind": "stairs", "path": retreat}
	_passage_index = 1
	_passage_retreat = true


func _bypass(id: int) -> void:
	var previous := _goal
	if previous.get("order_entry", false):
		_next_team_attempt = 0.0
	if previous.has("ordered_floor") and (_hide_clock < _ordered_route_deadline or elapsed < _sector_entered + 42.0):
		_team_floor = int(previous.ordered_floor)
		_next_team_attempt = 0.0
	_passage = {}
	_passage_edge = Vector2i(-1, -1)
	_passage_retreat = false
	_path.clear()
	_goal = {}
	_blocked_nodes[id] = elapsed + 28.0
	routes.graph.set_point_disabled(id, true)
	_detours += 1
	if previous.get("exit_school", false):
		_survey_retry = elapsed
	var distance := bot.global_position.distance_squared_to(_last_waypoint)
	if distance > 0.04 and distance < 3.2:
		if previous.has("event"):
			_local_distraction()
		if not previous.is_empty():
			_remember(int(previous.node))
		_backtrack = _last_waypoint
		_stand_until = elapsed
		return
	if _detours <= 3 and not previous.is_empty() and int(previous.node) != id and _set_goal(previous, true):
		if previous.has("ordered_floor"):
			_team_floor = -20
		return
	if previous.has("event"):
		_local_distraction()
	if not previous.is_empty():
		_remember(int(previous.node))
	_next_hunt_choice = elapsed + 0.55
	_stand_until = elapsed + 0.55


func _backtrack_step(delta: float) -> void:
	if bot.global_position.distance_squared_to(_backtrack) < 0.14 * 0.14:
		_backtrack = Vector3.INF
		_stand_until = elapsed
		return
	var speed := _ground_speed()
	var step := bot.global_position.move_toward(_backtrack, delta * speed)
	var floor := routes.floor_at(step)
	if floor.is_finite() and _advance_to(floor, false):
		_velocity = speed
	else:
		_backtrack = Vector3.INF
		_last_waypoint = Vector3.INF


func _abandon_goal() -> void:
	if not _goal.is_empty():
		_remember(int(_goal.node))
		if _goal.has("ordered_floor") and elapsed < _sector_entered + 42.0 and not seeker_can_see():
			_team_floor = int(_goal.ordered_floor)
		if _goal.has("event"):
			_local_distraction()
	_path.clear()
	_goal = {}
	_stand_until = elapsed


func _remember(node: int) -> void:
	_recent_nodes.append(node)
	if _recent_nodes.size() > 8:
		_recent_nodes.pop_front()


func _arrive() -> void:
	_path.clear()
	if _goal.is_empty():
		return
	_remember(int(_goal.node))
	if _goal.get("order_entry", false):
		_next_team_attempt = 0.0
		_think_left = 0.0
		_goal = {}
		return
	_visited_zones[SchoolHuntRoutes.zone(bot.global_position)] = elapsed
	if bool(_goal.get("team_order", false)):
		_sector_entered = elapsed
		_record("team_arrive", {"floor": _goal.ordered_floor, "at": SchoolReplayRecorder.vec(bot.global_position)})
	if elapsed < _horn_depart_until or _clearing_landing() or (elapsed < _danger_until and bot.global_position.distance_to(_last_danger) < 13.0):
		_goal = {}
		_think_left = 0.0
		_stand_until = elapsed
		return
	_stand_until = elapsed
	if _goal.has("event"):
		_trigger_stunt(str(_goal.event))
		_stand_until = elapsed
		return
	if _goal.has("utility"):
		_use_utility(str(_goal.utility))
		return
	if _goal.has("cloak"):
		var placement := _concealment_site(bot.global_position)
		if not placement.is_empty() and _place_cover(placement, true):
			return
		return
	var id: int = _goal.spot
	if _locker_allowed(id) and world.player.hides._accessible(id, bot.global_position):
		hidden_spot = id
		_last_locker_at = elapsed
		_locker_visits += 1
		_movement_since_locker = 0.0
		_used_lockers[id] = elapsed
		_record("hide_locker", {"id": id})
		var stay := _rng.randf_range(LOCKER_DWELL.x, minf(LOCKER_DWELL.y, LOCKER_TOTAL - _locker_seconds))
		_locker_seconds += stay
		_locker_until = elapsed + stay
		_stand_until = _locker_until
		if not is_instance_valid(network):
			world.player.hides.set_remote(id)
		bot.hide()
		if phase == "seek" and world.player.global_position.distance_squared_to(bot.global_position) < 11.0 * 11.0:
			world.sfx.play("hide_wood", bot.global_position, -10.0)


func _closet_intact(id: int) -> bool:
	var info := world.player.hides.spots[id]
	var building := info.building as VoxelObject
	if not is_instance_valid(building):
		return false
	if not bool(info.get("school", false)):
		return true
	var local: Vector3 = info.center
	local -= Basis(Vector3.UP, float(info.get("yaw", 0.0))).z * 5.0
	for y in [5.0, 12.0, 18.0]:
		if building.volume.get_voxel(Vector3i((local + Vector3.UP * y).floor())) == 0:
			return false
	return true


func _trigger_stunt(key: String) -> void:
	var secrets := world.secrets as SchoolSecrets
	var point: Vector3 = secrets._controls[key].global_position if secrets._controls.has(key) else secrets._action_pos(key)
	var hit := world.raycast(bot.global_position + Vector3.UP * 1.24, point, DistrictSecrets.MASK)
	var applied := {}
	if hit.is_empty() or secrets._target_key(hit) == key:
		applied = secrets.authorize(key, _bot_side() if is_instance_valid(network) else 0, bot.global_position, false, false, true)
	if applied.is_empty():
		_local_distraction()
		return
	if is_instance_valid(network):
		WebSession.send({"k": "secret_state", "event": applied, "round": network._round})
	_events_used[key] = true
	stunts_done += 1
	_flee_until = maxf(_flee_until, elapsed + 6.0)
	_record("device", {"id": key, "pos": SchoolReplayRecorder.vec(point)})


func _use_utility(key: String) -> bool:
	var secrets := world.secrets as SchoolSecrets
	if not secrets.traps.bot_utility_ready(key, _bot_side()) or not routes.can_use_station(key, bot.global_position):
		return false
	var event := secrets.authorize(key, _bot_side(), bot.global_position, false, false, true)
	if event.is_empty():
		return false
	if is_instance_valid(network):
		WebSession.send({"k": "secret_state", "event": event, "round": network._round})
	if key == "lobby_hatch":
		routes.add_bunker_routes()
	_record("utility", {"key": key, "pos": SchoolReplayRecorder.vec(bot.global_position)})
	_next_language_plan = elapsed
	return true


func _local_distraction() -> void:
	var at := bot.global_position
	var direction := Vector3.FORWARD.rotated(Vector3.UP, bot.rotation.y + _rng.randf_range(-PI, PI))
	var tapped := false
	for object in world.objects_in_sphere(at + Vector3.UP * 0.68, 2.8, Layers.DYNAMIC):
		if object.freeze or object.mass > 38.0 or object.held or object.has_node("Vehicle"):
			continue
		var center := object.world_center()
		var hit := world.raycast(at + Vector3.UP * 0.82, center)
		if hit.get("collider") == object:
			object.apply_central_impulse((direction * 2.0 + Vector3.UP * 0.25) * object.mass)
			at = center
			tapped = true
			break
	var obstruction := world.raycast(at + Vector3.UP * 0.85, at + Vector3.UP * 0.85 + direction * 2.8)
	if not tapped and not obstruction.is_empty():
		at = obstruction.position
	world.sfx.play("metal", at, -2.0, _rng.randf_range(0.79, 1.16))
	stunts_done += 1
	_flee_until = maxf(_flee_until, elapsed + 6.0)
	_stand_until = elapsed
	_record("decoy", {"pos": SchoolReplayRecorder.vec(at)})


func _emit_clue() -> void:
	if elapsed < FIRST_CLUE:
		return
	_next_clue = elapsed + _rng.randf_range(30.0, 60.0)
	_last_clue_at = elapsed
	clue_count += 1
	var at := bot.global_position
	var paint := _tool_available(PlayerTools.SPRAY) and clue_count > 1 and _rng.randf() >= float(tactic.horn) and _paint_mark()
	if paint:
		_record("signal", {"kind": "paint", "pos": SchoolReplayRecorder.vec(_paint_source)})
		_depart_from_signal(_paint_source)
		return
	var source := at + Vector3.UP * 1.3
	world.sfx.play_horn(source)
	if is_instance_valid(network):
		network.bot_horn(source)
	else:
		hud.show_horn(source)
	_record("signal", {"kind": "horn", "pos": SchoolReplayRecorder.vec(at)})
	if is_instance_valid(_chat) and (clue_count == 1 or _rng.randf() < 0.42):
		_chat.say("Слышал? Это я. Пока дойдёшь до метки, я уже сменю место.")
	clue_zone = SchoolHuntRoutes.zone(at)
	_depart_from_signal(at)


func _depart_from_signal(at: Vector3) -> void:
	_horn_origin = at
	_horn_depart_until = elapsed + 9.0
	_stand_until = elapsed
	_next_hunt_choice = elapsed
	_leave_cover()
	_cloak_until = elapsed
	var already_leaving := bool(_goal.get("exit_school", false)) and not _path.is_empty()
	if _passage.is_empty() and not already_leaving:
		_abandon_goal()
		if not _choose_goal(false, SchoolPursuitPolicy.DETOUR):
			var start := routes.nearest(bot.global_position, 3.65, true, true)
			if start >= 0:
				_dodge(start)
	_think_left = 0.0


func _paint_mark() -> bool:
	var sample := {"at": bot.global_position, "yaw": bot.rotation.y, "time": elapsed}
	if not _trail.is_empty() and elapsed - float(_trail[-1].time) < 6.0:
		sample = _trail[maxi(0, _trail.size() - _rng.randi_range(1, mini(5, _trail.size())))]
	var at: Vector3 = sample.at
	var forward := Vector3.FORWARD.rotated(Vector3.UP, float(sample.yaw))
	var hit := world.raycast(at + Vector3.UP * 0.38, at - Vector3.UP * 0.50, Layers.STATIC)
	if hit.is_empty() or not hit.collider is VoxelObject:
		return false
	var body := hit.collider as VoxelObject
	var mark: Vector3 = hit.position - Vector3.UP * 0.035
	var side := forward.cross(Vector3.UP)
	var changed := 0
	for i in range(-3, 4):
		changed += body.paint(mark + forward * (float(i) * 0.12), 0.115, VoxMat.paint_remap, 3.6)
	for i in 4:
		for sign_value in [-1.0, 1.0]:
			changed += body.paint(mark + forward * (0.36 - i * 0.09) + side * (i * 0.09 * sign_value),
				0.115, VoxMat.paint_remap, 3.6)
	if changed <= 0:
		return false
	clue_zone = SchoolHuntRoutes.zone(at)
	_paint_source = at
	world.sfx.play("spray_clue", at + Vector3.UP * 0.42, -3.0)
	return true


func seeker_can_see() -> bool:
	if not is_instance_valid(bot) or hidden_spot >= 0:
		return false
	var player := _hunter()
	if not is_instance_valid(player) or player.dead or player.hide_spot >= 0:
		return false
	var eye := player.camera.global_position
	var at := bot.global_position + Vector3.UP * 1.05
	var line := at - eye
	return line.length_squared() < 32.0 * 32.0 and player.aim_dir().dot(line.normalized()) > 0.54 \
		and world.raycast(eye, at, Layers.SOLID | Layers.CLOTH).is_empty() and not world.secrets.obscures(eye, at)


func combat_trace(from: Vector3, to: Vector3) -> Vector3:
	if phase != "seek" or _door_lock > 0.0 or not is_instance_valid(bot):
		return Vector3.INF
	return HideCombat.contact(from, to, bot.global_position, hidden_spot >= 0 or _quiet_step)


func combat_blast(at: Vector3, radius: float) -> void:
	if phase == "seek" and HideCombat.blast_reaches(world, at, bot.global_position, radius):
		take_weapon_hit()


func take_weapon_hit() -> void:
	if phase != "seek":
		return
	combat_health = maxi(0, combat_health - HideCombat.HIT)
	if combat_health == 0:
		_finish(true)
		return
	world.sfx.play("thud", bot.global_position, -8.0)
	hud.message("Шорох · %d здоровья" % combat_health, 1.2)
	_leave_cover()
	_stand_until = elapsed
	_notice(world.player.global_position, 8.0, 2)
	_think_left = 0.0





func _search_closet(id: int) -> void:
	if phase != "seek":
		return
	_record("check_locker", {"id": id, "found": id == hidden_spot})
	checked_spots[id] = true
	if id == hidden_spot:
		_leave_cover()
		_stand_until = elapsed
		_notice(world.player.global_position, 8.0, 2)
		_think_left = 0.0
	world.sfx.play("hide_wood", world.player.global_position, -12.0)


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 13
	add_child(_layer)
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 32
	add_child(_board_layer)
	_board = RoundBoard.new()
	_board_layer.add_child(_board)


func _input(event: InputEvent) -> void:
	if _recorder == null or phase != "seek" or world.player.navigation_menu_open or pause_menu.is_open() or event.is_echo():
		return
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "fire",
		"grab", "teleport", "secret_shot", "place_boombox"]:
		if event.is_action(action):
			_record("player_input", {"action": action, "pressed": event.is_pressed(), "tool": world.player.tools.current})


func _record(kind: String, data: Dictionary = {}) -> void:
	if _recorder != null:
		_recorder.event(kind, data)


func _update_hud() -> void:
	var time := _head_start if phase == "hide" else maxf(0.0, ROUND_LENGTH - elapsed)
	_chat.set_round_clock(phase, floori(elapsed), ceili(time))
	var role := "ПРЯТКИ С БОТОМ"
	if phase == "seek" and combat_health < 100:
		role += "  ·  ЗДОРОВЬЕ БОТА %d" % combat_health
	if _recorder != null:
		role += "  ·  ● REC"
	_board.visible = not pause_menu.is_open()
	if _board.visible:
		_board.refresh(phase, time, HEAD_START if phase == "hide" else ROUND_LENGTH, 1, 1, role)


func _finish(found: bool, reason := "") -> void:
	var recorded := false
	if _recorder != null:
		recorded = _recorder.finish(("caught" if found else "survived") if reason.is_empty() else "interrupted", elapsed)
	world.sfx.loop("bot_foam", "extinguisher", Vector3.ZERO, false)
	BotLanguage.cancel(get_instance_id())
	if is_instance_valid(_chat):
		_chat.close_chat()
		if reason.is_empty():
			_chat.say("Поймал! Хороший поиск." if found else "Время вышло. В следующий раз сменю тактику.")
	phase = "done"
	_leave_cover()
	if is_instance_valid(bot):
		bot.visible = found
	world.player.movement_enabled = false
	world.player.tools.input_enabled = false
	world.player.navigation_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_board.hide()
	if is_instance_valid(_waiting_room):
		_waiting_room.queue_free()
	var overlay := ColorRect.new()
	overlay.color = Color("#0d141bce")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 540
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#151e26f7")))
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 15)
	panel.add_child(body)
	var title := reason if not reason.is_empty() else ("Победа ищущего" if found else "Победа прячущегося")
	body.add_child(MenuStyle.label(title, 42, MenuStyle.GOLD if found else Color("#91e5d9")))
	if not bool(GameState.map_options.reduced_motion):
		panel.modulate.a = 0.0
		create_tween().tween_property(panel, "modulate:a", 1.0, 0.42)
	body.add_child(MenuStyle.label("Время %02d:%02d  ·  Подсказок %d" % [int(elapsed) / 60, int(elapsed) % 60, clue_count],
		20, MenuStyle.MUTED))
	body.add_child(MenuStyle.label("Проверено укрытий %d" % checked_spots.size(), 18, MenuStyle.MUTED))
	body.add_child(MenuStyle.label("Бот исследовал %d%% доступной территории" % roundi(_survey.coverage() * 100.0), 18, MenuStyle.GOLD))
	var batch := GameState.bot_record_batch
	var count := SchoolReplayRecorder.completed(batch)
	if not batch.is_empty():
		body.add_child(MenuStyle.label("Записано раундов · %d из 5" % count if recorded else "Не удалось сохранить запись", 18, MenuStyle.GOLD))
		body.add_child(MenuStyle.button("Открыть папку записей", SchoolReplayRecorder.open_folder, false, 48))
	var keep_recording := not batch.is_empty() and count < SchoolReplayRecorder.BATCH_SIZE
	body.add_child(MenuStyle.button("Следующий раунд с записью" if keep_recording else "Новый раунд",
		func(): GameState.start(GameState.LEVEL_SCHOOL, "", true, keep_recording), true))
	body.add_child(MenuStyle.button("Главное меню", GameState.to_menu))


func _exit_tree() -> void:
	if _recorder != null:
		_recorder.finish("interrupted", elapsed)
	BotLanguage.cancel(get_instance_id())
