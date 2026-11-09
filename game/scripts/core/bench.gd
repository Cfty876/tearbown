class_name Bench
extends Node
## Scripted benchmark (F6 or --bench) and screenshot tour (--tour).
## Bench phases: idle view, staged demolition, aftermath, stress barrage, settle.
## Reports avg FPS, 1% low and frames over 16.7 ms per phase to stdout and
## user://bench.txt; screenshots go to shot_dir.

var main: Node
var mode := "bench"
var shot_dir := "user://shots"
var quit_when_done := false

var _t := 0.0
var _phase := -1
var _phases: Array = []
var _frames := PackedFloat32Array()
var _report := PackedStringArray()
var _events: Array = []
var _shots_taken := {}
var _rng := RandomNumberGenerator.new()
var _phys_max := 0.0
var _skip := 0
var _proc_max := 0.0


func _ready() -> void:
	_rng.seed = 99
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var p: Player = main.player
	p.god_mode = true
	p.set_process_unhandled_input(false)
	p.tools.input_enabled = false
	if mode != "drive" and mode != "glass":
		p.set_physics_process(false)
	if mode == "glass":
		# Sprint into the glass back wall of a bus stop: the glass must give way.
		_phases = [
			["g_start", 0.5, Vector3(12, 3.67, 49.6), Vector3(12, 3.6, 60)],
			["g_run", 3.0, null, null, ["move_forward", "sprint"]],
		]
	elif mode == "drive":
		for o in VoxelWorld.instance.objects:
			if o.has_node("Vehicle"):
				p.enter_vehicle(o.get_node("Vehicle"))
				break
		# name, seconds, camera from, camera target, held actions
		_phases = [
			["drive_idle", 1.5, null, null, []],
			["drive_accel", 4.0, null, null, ["move_forward"]],
			["drive_turn", 2.5, null, null, ["move_forward", "move_left"]],
			["drive_brake", 2.0, null, null, ["jump"]],
			["drive_back", 2.5, null, null, ["move_back"]],
		]
	elif mode == "dtour":
		_phases = [
			["d_spawn", 2.0, Vector3(12, 3.65, 48), Vector3(12, 3.5, 30)],
			["d_entrance", 2.0, Vector3(-0.5, 3.6, -45.5), Vector3(-0.5, 3.2, -51.5)],
			["d_stair", 2.0, Vector3(-0.2, 7.4, -57.2), Vector3(-1.0, 7.0, -52.5)],
			["d_roof", 2.0, Vector3(-20, 19.6, -56), Vector3(-15, 3, -15)],
			["d_garages", 2.0, Vector3(-28, 3.6, -82.5), Vector3(-5, 3, -83)],
			["d_river", 2.0, Vector3(-52, 3.6, -70), Vector3(-68, 2, -60)],
			["d_parking", 2.0, Vector3(45, 3.6, -50), Vector3(46, 4, -75)],
			["d_magnit", 2.0, Vector3(-68, 3.6, 50), Vector3(-68, 4, 25)],
			["d_road", 2.0, Vector3(5, 3.6, 49.5), Vector3(25, 3, 62)],
		]
	elif mode == "crater":
		var c := Vector3(2, 2.0, 11)
		_phases = [
			["crater_blast", 2.0, c + Vector3(0, 6, 5), c],
			["crater_view", 1.5, c + Vector3(0, 4.5, 3.5), c + Vector3(0, -1, 0)],
		]
		_events.append([0.3, c, 2.0, 7.0])
		_events.append([0.9, c + Vector3(0, -0.8, 0), 2.0, 7.0])
	elif mode == "tools":
		var at := Vector3(-12, 3.4, -1.9)
		var wall := Vector3(-12, 3.1, -3.4)
		_phases = [
			["t_hammer", 1.6, at, wall, [], PlayerTools.HAMMER, "fire"],
			["t_shotgun", 1.2, at + Vector3(0, 0, 3), wall, [], PlayerTools.SHOTGUN, "fire"],
			["t_torch", 2.0, at + Vector3(1.5, 0, -0.4), wall + Vector3(1.5, 0, 0), [], PlayerTools.TORCH, "fire"],
			["t_spray", 1.5, at + Vector3(-2.5, 0, 1), wall + Vector3(-2.5, 0, 0), [], PlayerTools.SPRAY, "fire"],
			["t_bomb", 4.0, at + Vector3(0, 0, 6), wall + Vector3(0, -1, 0), [], PlayerTools.PIPEBOMB, "fire"],
			["t_rocket", 2.5, at + Vector3(6, 0.5, 9), wall + Vector3(4, 1, 0), [], PlayerTools.ROCKET, "fire"],
			["t_extinguisher", 1.2, at + Vector3(2, 0, 4), wall, [], PlayerTools.EXTINGUISHER, "fire"],
			["t_grab", 1.5, Vector3(3, 3.2, 9.0), Vector3(3, 2.4, 6.4), [], PlayerTools.HAMMER, "grab"],
			["t_after", 2.0, at + Vector3(2, 1.5, 7), wall, [], PlayerTools.HAMMER],
		]
	elif mode == "tour":
		_phases = [
			["view_spawn", 2.5, Vector3(0, 3.7, 26), Vector3(0, 2.5, 0)],
			["view_house", 2.5, Vector3(-4, 3.2, 6), Vector3(-14, 4.5, -8)],
			["view_barn", 2.5, Vector3(4, 3.0, 2), Vector3(13, 4.0, -12)],
			["view_tower", 2.5, Vector3(8, 6.0, -6), Vector3(-1, 9.0, -27)],
			["view_yard", 2.5, Vector3(-30, 16.0, 30), Vector3(0, 2.0, -4)],
			["view_interior", 2.5, Vector3(-10, 3.4, -10), Vector3(-18, 2.6, -6)],
		]
		for i in PlayerTools.NAMES.size():
			_phases.append(["tool_%d" % (i + 1), 0.8, Vector3(2, 3.6, 12), Vector3(-6, 3.0, -4), [], i])
	else:
		_phases = [
			["warmup", 2.0, Vector3(6, 6.5, 22), Vector3(-2, 3.0, -8)],
			["idle", 5.0, Vector3(6, 6.5, 22), Vector3(-2, 3.0, -8)],
			["demolition", 12.0, Vector3(6, 6.5, 22), Vector3(-2, 3.0, -8)],
			["aftermath", 6.0, Vector3(6, 6.5, 22), Vector3(-2, 3.0, -8)],
			["stress", 6.0, Vector3(-4, 12.0, 26), Vector3(0, 2.0, -6)],
			["settle", 6.0, Vector3(-4, 12.0, 26), Vector3(0, 2.0, -6)],
		]
		var targets := [
			Vector3(-14, 2.6, -3.4), Vector3(-19, 2.6, -3.4), Vector3(-9, 2.6, -3.4),
			Vector3(-14, 5.5, -3.4), Vector3(13, 2.4, -8.8), Vector3(10, 4.0, -8.8),
			Vector3(-1, 2.5, -25.4), Vector3(0.3, 2.5, -25.6), Vector3(-2.3, 2.5, -25.6),
			Vector3(3, 2.5, 6), Vector3(-3, 3.0, 3), Vector3(-5, 2.6, -4),
			Vector3(7, 2.4, -17), Vector3(-12, 2.6, 9.4), Vector3(-30, 2.3, 7.2),
			Vector3(-30, 2.3, 10.8), Vector3(8, 3.0, -0.8), Vector3(16, 2.5, -1.2),
			Vector3(24.5, 2.6, 6), Vector3(19, 2.5, 3),
		]
		for i in targets.size():
			_events.append([2.0 + 5.0 + 0.3 + 0.55 * i, targets[i], 2.0, 6.5])
		var stress_start := 2.0 + 5.0 + 12.0 + 6.0
		for i in 30:
			var p2 := Vector3(_rng.randf_range(-22, 22), 2.6, _rng.randf_range(-24, 12))
			_events.append([stress_start + i * 0.12, p2, 1.8, 6.0])
	_next_phase()


func _look(from: Vector3, at: Vector3) -> void:
	var p: Player = main.player
	p.global_position = from - Vector3(0, 1.62, 0)
	p.velocity = Vector3.ZERO
	var d := (at - from).normalized()
	p.look_at_dir(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


func _next_phase() -> void:
	if _phase >= 0:
		_record(_phases[_phase][0])
	_phase += 1
	_frames.clear()
	if _phase >= _phases.size():
		_finish()
		return
	var ph: Array = _phases[_phase]
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		Input.action_release(a)
	if ph.size() > 4:
		for a in ph[4]:
			Input.action_press(a)
	if ph[2] != null:
		_look(ph[2], ph[3])
	var pl0: Player = main.player
	pl0.tools.sim_fire = false
	pl0.tools._sim_was = false
	if pl0.grabbed:
		pl0.release_grab(true)
	if ph.size() > 5:
		pl0.tools.select(ph[5])
	if ph.size() > 6:
		pl0.tools.input_enabled = true
		if ph[6] == "fire":
			pl0.tools.sim_fire = true
		elif ph[6] == "grab":
			pl0.try_grab()
			print("[bench] grab -> ", pl0.grabbed.label if pl0.grabbed else "nothing")


func _process(delta: float) -> void:
	if _phase < 0 or _phase >= _phases.size():
		return
	_t += delta
	# The frame after a screenshot includes the PNG readback; keep it out of the stats.
	if _skip > 0:
		_skip -= 1
	else:
		_frames.append(delta * 1000.0)
	if _skip == 0:
		_phys_max = maxf(_phys_max, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_proc_max = maxf(_proc_max, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	while not _events.is_empty() and _t >= _events[0][0]:
		var e: Array = _events.pop_front()
		VoxelWorld.instance.explode(e[1], e[2], e[3])
	var ph: Array = _phases[_phase]
	var start := 0.0
	for i in _phase:
		start += _phases[i][1]
	var local := _t - start
	var name: String = ph[0]
	if local > ph[1] * 0.8 and not _shots_taken.has(name):
		_shots_taken[name] = true
		_shot(name)
	if local >= ph[1]:
		_next_phase()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join("%s.png" % name)
	img.save_png(path)
	_skip = 2
	print("[bench] screenshot ", ProjectSettings.globalize_path(path))


func _record(name: String) -> void:
	if _frames.is_empty() or name == "warmup":
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	var over := 0
	for f in _frames:
		total += f
		if f > 16.7:
			over += 1
	var avg := total / _frames.size()
	var p99 := sorted[int(sorted.size() * 0.99) - 1] if sorted.size() > 1 else sorted[0]
	var w: VoxelWorld = VoxelWorld.instance
	var line := "%-11s avg %6.1f fps (%5.2f ms) | 1%% low %6.1f fps | max %6.1f ms | >16.7ms: %d/%d | objects %d dyn %d debris %d fires %d" % [
		name, 1000.0 / avg, avg, 1000.0 / p99, sorted[sorted.size() - 1], over, _frames.size(),
		w.objects.size(), w.dynamic_count(), w.debris.active_count, w.fire.count()]
	if name == "crater_view":
		var hit := VoxelWorld.instance.raycast(Vector3(2, 6, 11), Vector3(2, -5, 11))
		line += " | ray in crater hits %s at y=%.2f" % [(hit.collider as VoxelObject).label if not hit.is_empty() else "NOTHING", hit.position.y if not hit.is_empty() else -99.0]
	var pl: Player = main.player
	if mode == "glass":
		line += " | player at %s" % pl.global_position.snapped(Vector3.ONE * 0.1)
	if pl.vehicle and is_instance_valid(pl.vehicle):
		line += " | car %.1f km/h at %s" % [pl.vehicle.speed * 3.6, pl.vehicle.body.global_position.snapped(Vector3.ONE * 0.1)]
	_report.append(line)
	print("[bench] ", line)
	var st: Dictionary = w.stats
	var prof := "            cpu max: physics %.1f ms | explode %.1f ms, island %.1f ms, rebuild %.1f ms" % [
		_phys_max, st.explode_max_usec / 1000.0, st.island_max_usec / 1000.0, st.rebuild_max_usec / 1000.0]
	_report.append(prof)
	print("[bench] ", prof)
	st.explode_max_usec = 0
	st.island_max_usec = 0
	st.rebuild_max_usec = 0
	_phys_max = 0.0
	_proc_max = 0.0


func _finish() -> void:
	var hdr := "Bench %s | %s | %s | %dx%d | quality %s" % [
		mode, Time.get_datetime_string_from_system(), RenderingServer.get_video_adapter_name(),
		get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y,
		Quality.NAMES[main.quality]]
	var f := FileAccess.open("user://bench.txt", FileAccess.WRITE)
	if f:
		f.store_line(hdr)
		for l in _report:
			f.store_line(l)
	print("[bench] ", hdr)
	print("[bench] done, report at ", ProjectSettings.globalize_path("user://bench.txt"))
	if quit_when_done:
		get_tree().quit()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var p: Player = main.player
	p.set_physics_process(true)
	p.set_process_unhandled_input(true)
	p.tools.input_enabled = true
	main.hud.message("Бенчмарк завершён: " + (_report[_report.size() - 1].substr(0, 40) if not _report.is_empty() else ""), 5.0)
	queue_free()

