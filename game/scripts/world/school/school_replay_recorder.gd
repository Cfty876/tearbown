class_name SchoolReplayRecorder
extends RefCounted
## Запись игровых состояний и действий для проверки и обучения.

const ROOT := "user://school_replays"
const BATCH_SIZE := 5
const SAMPLE_TIME := 0.1
const SCHEMA := 1

var path := ""
var _file: FileAccess
var _pending := ""
var _clock := 0.0
var _sample_at := 0.0
var _flush_at := 4.0
var _samples := 0
var _sprints := 0
var _slow_search := 0
var _checks := 0
var _seen := 0


static func root_dir() -> String:
	var custom := OS.get_environment("BREAKPOINT_REPLAY_DIR")
	return custom if custom.is_absolute_path() else ROOT


static func batch() -> String:
	var index := ConfigFile.new()
	if index.load(root_dir().path_join("session.cfg")) != OK:
		return ""
	var id := str(index.get_value("recording", "batch", ""))
	return id if id.is_valid_filename() and id.begins_with("series-") else ""


static func completed(id: String) -> int:
	if id.is_empty():
		return 0
	var count := 0
	for name in DirAccess.get_files_at(root_dir().path_join(id)):
		if name.begins_with("round-") and name.ends_with("-done.jsonl"):
			count += 1
	return count


static func open_batch() -> String:
	var active := batch()
	if not active.is_empty() and completed(active) < BATCH_SIZE:
		return active
	active = "series-%d-%05d" % [int(Time.get_unix_time_from_system()), randi_range(10000, 99999)]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_dir().path_join(active))) != OK:
		return ""
	var index := ConfigFile.new()
	index.set_value("recording", "batch", active)
	return active if index.save(root_dir().path_join("session.cfg")) == OK else ""


static func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_dir()))
	OS.shell_open(ProjectSettings.globalize_path(root_dir()))


static func history() -> Array:
	var settings := ConfigFile.new()
	if settings.load(root_dir().path_join("seeker.cfg")) != OK:
		return []
	var value: Variant = settings.get_value("practice", "rounds", [])
	return value if value is Array else []


func begin(id: String, seed_value: int) -> bool:
	if id.is_empty():
		return false
	var folder := root_dir().path_join(id)
	var name := "round-%02d-%d-%05d" % [completed(id) + 1, int(Time.get_unix_time_from_system()), randi_range(10000, 99999)]
	path = folder.path_join(name)
	_pending = path + ".part"
	_file = FileAccess.open(_pending, FileAccess.WRITE)
	if _file == null:
		return false
	event("header", {"schema": SCHEMA, "map": "school", "seed": str(seed_value), "batch": id,
		"walk": Player.WALK, "sprint": Player.SPRINT, "sample_hz": 10})
	return true


func event(kind: String, data: Dictionary = {}) -> void:
	if _file != null:
		_checks += int(kind == "check_locker")
		_file.store_line(JSON.stringify({"type": kind, "time": snappedf(_clock, 0.001), "data": data}))


func frame(hunt: Node, delta: float) -> void:
	if _file == null:
		return
	_clock += delta
	if _clock < _sample_at:
		return
	_sample_at += SAMPLE_TIME
	var player: Player = hunt.world.player
	var avatar: VoxelAvatar = hunt.bot
	var seen: bool = hunt.seeker_can_see()
	if hunt.phase == "seek":
		_samples += 1
		_sprints += int(player.is_sprinting() and Vector2(player.velocity.x, player.velocity.z).length() > 5.8)
		_slow_search += int(player.crouching)
		_seen += int(seen)
	var target: Vector3 = hunt._goal.get("at", Vector3.INF)
	event("frame", {"phase": hunt.phase, "elapsed": snappedf(hunt.elapsed, 0.01),
		"player": {"pos": vec(player.global_position), "vel": vec(player.velocity), "view": vec(player.aim_dir()),
			"run": player.is_sprinting(), "crouch": player.crouching, "ground": player.is_on_floor(),
			"vehicle": is_instance_valid(player.vehicle), "tool": player.tools.current, "hp": player.health,
			"hide": player.hide_spot, "fire": Input.is_action_pressed("fire") and not player.navigation_menu_open},
		"bot": {"pos": vec(avatar.global_position), "yaw": snappedf(avatar.rotation.y, 0.01),
			"speed": snappedf(hunt._velocity, 0.01), "run": hunt._running_pose, "hide": hunt.hidden_spot,
			"passage": hunt._passage.get("kind", ""), "target": vec(target),
			"zone": SchoolHuntRoutes.zone(avatar.global_position), "seen": seen, "concealed": hunt._cloak_active()}})
	if _clock >= _flush_at:
		_flush_at = _clock + 4.0
		_file.flush()


func finish(outcome: String, seconds: float) -> bool:
	if _file == null:
		return false
	var profile := {"seconds": snappedf(seconds, 0.001), "outcome": outcome, "samples": _samples,
		"sprint": float(_sprints) / maxi(1, _samples), "crouch": float(_slow_search) / maxi(1, _samples),
		"seen": float(_seen) / maxi(1, _samples), "lockers": _checks}
	event("result", profile)
	_file.flush()
	var result := _file.get_error()
	_file.close()
	_file = null
	if result != OK:
		return false
	path += "-partial.jsonl" if outcome == "interrupted" else "-done.jsonl"
	var saved := DirAccess.rename_absolute(ProjectSettings.globalize_path(_pending), ProjectSettings.globalize_path(path)) == OK
	if saved and outcome != "interrupted" and _samples >= 30:
		var records := history()
		records.append(profile)
		while records.size() > BATCH_SIZE:
			records.pop_front()
		var settings := ConfigFile.new()
		settings.set_value("practice", "rounds", records)
		settings.save(root_dir().path_join("seeker.cfg"))
	return saved


static func vec(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)] if at.is_finite() else []
