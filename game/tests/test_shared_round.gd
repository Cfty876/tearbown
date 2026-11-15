extends SceneTree

var _failure := ""
var _room: Node
var _session: Node


func _initialize() -> void:
	_run.call_deferred()


func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _require(value: bool, reason: String) -> void:
	if not value and _failure.is_empty():
		_failure = reason


func _scene_ready() -> bool:
	if not is_instance_valid(current_scene) or paused:
		return false
	for child in current_scene.get_children():
		if child.has_method("nearest_hunter"):
			_room = child
			return true
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	_session = root.get_node("WebSession")
	var owner := args[0] == "host"
	var online := args[1] != "lan"
	var invite := "user://shared-round-qa-%s" % ("ws" if online else "lan")
	var confirm := invite + "-ok"
	if owner:
		for path: String in [invite, confirm, invite + "-object"]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var rules := {"hide": 16, "seek": 60, "hiders": 1, "seekers": 1}
		if online:
			_session.host_online("proto", rules, args[1])
		else:
			_session.host_lan("proto", rules)
		if not await _wait_until(func(): return _session.joined, 18.0):
			_done("host setup: " + _session.last_error)
			return
		_write(invite, _session.code if online else _session.code_for("127.0.0.1"))
		if not await _wait_until(func(): return _session.can_start(), 25.0):
			_done("guest did not enroll")
			return
		_session.begin_room()
	else:
		if not await _wait_until(func(): return FileAccess.file_exists(invite), 18.0):
			_done("room code missing")
			return
		_session.join_room(FileAccess.get_file_as_string(invite).strip_edges(), args[1] if online else "")
	if not await _wait_until(_scene_ready, 28.0):
		_done("map failed to load: " + _session.last_error)
		return
	if owner:
		if not await _wait_until(func(): return _room._phase == "brief", 10.0):
			_done("briefing failed")
			return
		var seekers: Array[int] = [0]
		_require(_room.launch_next(_room.rules, seekers), "role assignment failed")
	if not await _wait_until(func(): return _room._board._last_phase == "hide", 10.0):
		_done("hide phase did not reach the scoreboard")
		return
	_require(_room._board._hiders.text == "1" and _room._board._seekers.text == "1", "initial team counts")
	if owner:
		_room._deadline_ms = Time.get_ticks_msec() + 1200
	if not await _wait_until(func(): return _room._board._last_phase == "seek", 8.0):
		_done("seek phase did not reach scoreboard")
		return
	_require(_room._board._seconds >= 55 and _room._board._seconds <= 60, "authoritative search clock")
	if owner:
		await create_timer(1.0).timeout
		var id := 0
		for key: int in _room.world.network_objects:
			if key > 0 and is_instance_valid(_room.world.network_objects[key]):
				id = key
				break
		_require(id != 0 and _session.send({"k": "gone", "ids": [id], "round": _room._round - 1}), "old destruction packet sent")
		if id != 0:
			_write(invite + "-object", str(id))
		if not await _wait_until(func(): return FileAccess.file_exists(confirm), 8.0):
			_done("no guest acknowledgement")
			return
		var body: Node = _room.world.network_objects.get(id)
		if is_instance_valid(body):
			_room.world.network_removed.append(id)
			body.queue_free()
		await create_timer(1.8).timeout
		_room._caught_side(1)
		await create_timer(1.5).timeout
	else:
		if not await _wait_until(func(): return FileAccess.file_exists(invite + "-object"), 8.0):
			_done("destruction fixture missing")
			return
		var id := int(FileAccess.get_file_as_string(invite + "-object"))
		await create_timer(0.65).timeout
		_require(is_instance_valid(_room.world.network_objects.get(id)), "destruction from previous round rejected")
		_write(confirm, "ready")
		_require(await _wait_until(func(): return not is_instance_valid(_room.world.network_objects.get(id)), 7.0),
			"current-round removal replicated")
		_require(await _wait_until(func(): return _room._phase == "done", 8.0), "round result replicated")
		_require(_room._found.has(1) and _room._win_seekers, "authoritative catch and victory")
	_done(_failure)


func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _done(reason: String) -> void:
	print("[shared-round-qa] ", "OK" if reason.is_empty() else "FAIL " + reason)
	quit(int(not reason.is_empty()))
