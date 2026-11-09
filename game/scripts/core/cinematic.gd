class_name Cinematic
extends Node
## Scripted fly-throughs of the district for video capture. Each shot is a
## Catmull-Rom camera path (position + look target keys) plus timed events:
## explosions, rockets, slow motion, a controlled demolition that drops the top
## floors of a panel block, a car ramming a shop, a tank car blast.
## Destruction carries over from shot to shot, so "all" tells a story.
## Record with: --write-movie <file.avi> --fixed-fps 60 -- --level=district --cinematic=all --quit

var main: Node
var shot := "all"
var quit_when_done := false

var cam: Camera3D
var _shots: Array = []
var _cur := -1
var _t := 0.0
var _events: Array = []
var _slow_left := 0.0
var _title: Label
var shot_dir := ""
var titles := false
var _frames := PackedFloat32Array()
var _shot_taken := false
var _shots_done := 0
const SHOT_AT := [0.3, 0.55, 0.85]
var _skip := 0


func _ready() -> void:
	var p: Player = main.player
	p.god_mode = true
	p.set_physics_process(false)
	p.set_process_unhandled_input(false)
	p.tools.input_enabled = false
	p.global_position = Vector3(0, -50, 0)
	main.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 800.0
	main.add_child(cam)
	cam.make_current()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.position = Vector2(70, 960)
	var layer := CanvasLayer.new()
	layer.add_child(_title)
	add_child(layer)
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
	_shots = _define()
	if shot != "all":
		_shots = _shots.filter(func(s): return s.name == shot)
	_next()


func _define() -> Array:
	var gy := DistrictLevel.GY
	return [
		{"name": "aerial", "title": "Пригород", "dur": 12.0, "fov": 55.0, "keys": [
			[0.0, Vector3(-95, 55, 95), Vector3(-15, 4, -10)],
			[6.0, Vector3(-30, 42, 82), Vector3(-5, 4, -15)],
			[12.0, Vector3(45, 46, 74), Vector3(5, 4, -22)]], "events": []},
		{"name": "street", "title": "Главная улица", "dur": 11.0, "fov": 60.0, "keys": [
			[0.0, Vector3(-75, gy + 1.6, 50.5), Vector3(-60, gy + 2.5, 38)],
			[5.5, Vector3(-10, gy + 1.8, 50.0), Vector3(5, gy + 3.5, 30)],
			[11.0, Vector3(42, gy + 2.2, 50.5), Vector3(56, gy + 3.5, 32)]], "events": []},
		{"name": "courtyard", "title": "Двор", "dur": 10.0, "fov": 62.0, "keys": [
			[0.0, Vector3(-17, gy + 1.5, 6), Vector3(-18, gy + 1.5, -15)],
			[5.0, Vector3(-14, gy + 8, 9), Vector3(-19, gy + 3, -20)],
			[10.0, Vector3(-2, gy + 24, 18), Vector3(-22, gy + 6, -32)]], "events": []},
		{"name": "river", "title": "Река", "dur": 9.0, "fov": 58.0, "keys": [
			[0.0, Vector3(-51, gy + 1.4, -68), Vector3(-66, gy - 0.3, -61)],
			[9.0, Vector3(-57, gy + 1.0, -56), Vector3(-78, gy - 0.4, -44)]], "events": []},
		{"name": "garages", "title": "Склады", "dur": 8.0, "fov": 60.0, "keys": [
			[0.0, Vector3(-47, gy + 3.0, -81.0), Vector3(-30, gy + 1.5, -83)],
			[8.0, Vector3(-40, gy + 2.6, -81.0), Vector3(-14, gy + 1.8, -85)]], "events": [
			[2.2, "rocket", Vector3(-44, gy + 2.8, -81.6), Vector3(-18, gy + 1.2, -85.6)],
			[2.8, "slowmo", 0.35, 2.0]]},
		{"name": "store", "title": "Супермаркет", "dur": 12.0, "fov": 55.0, "keys": [
			[0.0, Vector3(38, gy + 2.5, -44), Vector3(44, gy + 4, -70)],
			[6.0, Vector3(42, gy + 3.0, -50), Vector3(46, gy + 4, -71)],
			[12.0, Vector3(60, gy + 6, -50), Vector3(44, gy + 3, -73)]], "events": [
			[1.5, "rocket", Vector3(36, gy + 2.2, -45), Vector3(38, gy + 3.0, -69.8)],
			[2.1, "slowmo", 0.3, 2.6],
			[5.5, "explode", Vector3(55, gy + 1.2, -69.5), 2.6, 7.0],
			[7.0, "explode", Vector3(30, gy + 4.0, -69.5), 2.4, 7.0],
			[8.0, "rocket", Vector3(60, gy + 6, -49), Vector3(48, gy + 6.4, -76)]]},
		{"name": "collapse", "title": "Снос жилого дома", "dur": 17.0, "fov": 50.0, "keys": [
			[0.0, Vector3(-3, gy + 4, 75), Vector3(-3, gy + 8, 21)],
			[8.0, Vector3(4, gy + 6, 66), Vector3(-3, gy + 6, 21)],
			[17.0, Vector3(22, gy + 14, 62), Vector3(-6, gy + 4, 21)]], "events": [
			[2.5, "charges", "block5", 2.3],
			[2.55, "slowmo", 0.4, 3.0]]},
		{"name": "crash", "title": "Автосервис", "dur": 8.0, "fov": 58.0, "keys": [
			[0.0, Vector3(40, gy + 1.6, 46), Vector3(55, gy + 2, 40)],
			[8.0, Vector3(44, gy + 3.0, 44), Vector3(56, gy + 2, 36)]], "events": [
			[0.8, "ram", Vector3(56.5, gy - 0.05, 48.5), Vector3(56.5, gy, 34), 21.0],
			[1.6, "slowmo", 0.35, 1.6]]},
		{"name": "railway", "title": "Железная дорога", "dur": 10.0, "fov": 55.0, "keys": [
			[0.0, Vector3(-72, gy + 2.2, 84.2), Vector3(-26, gy + 2, 90)],
			[10.0, Vector3(-48, gy + 3.2, 83.8), Vector3(-21, gy + 2.5, 90.5)]], "events": [
			[1.5, "explode", Vector3(-22.2, gy + 2.6, 90.4), 2.2, 7.0],
			[1.55, "slowmo", 0.4, 2.0]]},
		{"name": "finale", "title": "", "dur": 13.0, "fov": 55.0, "keys": [
			[0.0, Vector3(20, 22, 60), Vector3(-5, 4, 10)],
			[6.5, Vector3(-40, 48, 70), Vector3(-5, 4, -15)],
			[13.0, Vector3(-95, 80, 85), Vector3(0, 4, -20)]], "events": []},
	]


func _next() -> void:
	_report()
	_cur += 1
	_frames.clear()
	_shot_taken = false
	_shots_done = 0
	_t = 0.0
	Engine.time_scale = 1.0
	_slow_left = 0.0
	if _cur >= _shots.size():
		_finish()
		return
	var s: Dictionary = _shots[_cur]
	_events = (s.events as Array).duplicate()
	cam.fov = s.fov
	_title.text = s.title if titles else ""
	_title.modulate.a = 0.0
	_apply_camera(0.0)


func _finish() -> void:
	Engine.time_scale = 1.0
	if quit_when_done:
		get_tree().quit()
	else:
		GameState.to_menu()


func _process(delta: float) -> void:
	if _cur < 0 or _cur >= _shots.size():
		return
	# Camera moves in real time even while the world runs in slow motion.
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	if _skip > 0:
		_skip -= 1
	elif _t > 0.5:
		_frames.append(real * 1000.0)
	if _slow_left > 0.0:
		_slow_left -= real
		if _slow_left <= 0.0:
			Engine.time_scale = 1.0
	while not _events.is_empty() and _t >= _events[0][0]:
		_fire(_events.pop_front())
	var s: Dictionary = _shots[_cur]
	var a := clampf(minf(_t - 0.4, s.dur - 0.6 - _t) * 1.5, 0.0, 1.0)
	_title.modulate.a = a * (1.0 if _t < 4.0 else clampf(5.0 - _t, 0.0, 1.0))
	_apply_camera(_t)
	if shot_dir != "" and _shots_done < SHOT_AT.size() and _t > s.dur * SHOT_AT[_shots_done]:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_dir.path_join("cine_%s_%d.png" % [s.name, _shots_done]))
		_shots_done += 1
		_skip = 2
	if _t >= s.dur:
		_next()


func _apply_camera(t: float) -> void:
	var keys: Array = _shots[_cur].keys
	var n := keys.size()
	if n == 1:
		cam.global_position = keys[0][1]
		cam.look_at(keys[0][2], Vector3.UP)
		return
	var i := 0
	while i < n - 2 and t > keys[i + 1][0]:
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var u := clampf((t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
	var pos := _catmull(keys, i, u, 1)
	var look := _catmull(keys, i, u, 2)
	cam.global_position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)


static func _catmull(keys: Array, i: int, u: float, k: int) -> Vector3:
	var n := keys.size()
	var p0: Vector3 = keys[maxi(i - 1, 0)][k]
	var p1: Vector3 = keys[i][k]
	var p2: Vector3 = keys[mini(i + 1, n - 1)][k]
	var p3: Vector3 = keys[mini(i + 2, n - 1)][k]
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


func _fire(e: Array) -> void:
	var w := VoxelWorld.instance
	match e[1]:
		"explode":
			w.explode(e[2], e[3], e[4])
		"rocket":
			var r := Projectiles.Rocket.new()
			w.add_child(r)
			r.global_position = e[2]
			var dir: Vector3 = (e[3] - e[2]).normalized()
			r.velocity = dir * 38.0
			r.look_at(r.global_position + dir, Vector3.UP)
			w.sfx.play("rocket", e[2], 2.0)
		"slowmo":
			Engine.time_scale = e[2]
			_slow_left = e[3]
		"charges":
			_demolish(e[2], e[3])
		"ram":
			_ram(e[2], e[3], e[4])


## Controlled demolition: cuts the whole ground floor of a building at `height`
## meters above the ground; everything above becomes one falling body.
func _demolish(name: String, height: float) -> void:
	var lvl = main.level
	if not lvl.buildings.has(name):
		return
	var o: VoxelObject = lvl.buildings[name]
	if not is_instance_valid(o):
		return
	var size := Vector3(o.volume.get_size()) * VoxelObject.VS
	var pts: Array[Vector3] = []
	var x := 0.4
	while x < size.x - 0.2:
		var z := 1.4
		while z < size.z - 1.2:
			pts.append(o.to_global(Vector3(x, height, z)))
			# The balcony side loses a second storey so the block tips over that way.
			if z > size.z * 0.55:
				pts.append(o.to_global(Vector3(x, height + 2.6, z)))
			if z > size.z * 0.7:
				pts.append(o.to_global(Vector3(x, height + 5.2, z)))
			z += 1.25
		x += 1.25
	# Vertical cuts at the section joints split the block into falling slabs.
	var sections := int(round((size.x - 0.6) / 15.0))
	for s in range(1, sections):
		var sx := 0.3 + s * 15.0
		var y := height
		while y < size.y - 1.0:
			var z := 1.4
			while z < size.z - 1.2:
				pts.append(o.to_global(Vector3(sx, y, z)))
				z += 1.3
			y += 1.3
	o.carve_batch(pts, 1.1, 14.0)
	var w := VoxelWorld.instance
	for k in 8:
		var t := (k + 0.5) / 8.0
		for zz in [1.6, size.z - 1.4]:
			var p := o.to_global(Vector3(size.x * t, height, zz))
			w.fx.explosion(p, 1.6)
	w.sfx.play("explosion", o.to_global(size * 0.5), 12.0, 0.8)
	w.sfx.play("collapse", o.to_global(size * 0.5), 10.0)


func _ram(from: Vector3, to: Vector3, speed: float) -> void:
	var dir := (to - from).normalized()
	# Car models face -x: yaw that turns -x into dir.
	var yaw := rad_to_deg(atan2(dir.z, -dir.x))
	var c := Build.place(VoxelWorld.instance, Build.car("metal_red", 7), from, false, yaw, "ram_car")
	c.linear_velocity = dir * speed


func _report() -> void:
	if _cur < 0 or _cur >= _shots.size() or _frames.size() < 10:
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	var avg := total / _frames.size()
	var p99 := sorted[int(sorted.size() * 0.99) - 1]
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("[cine] %-10s avg %6.1f fps | 1%% low %6.1f fps | max %6.1f ms | draws %d, %.1fM tris | phys %.1f ms | objects %d dyn %d debris %d" % [
		_shots[_cur].name, 1000.0 / avg, 1000.0 / p99, sorted[sorted.size() - 1], draws, prims / 1e6,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		VoxelWorld.instance.objects.size(), VoxelWorld.instance.dynamic_count(), VoxelWorld.instance.debris.active_count])
