class_name Sfx
extends Node3D
## Procedurally synthesized sound effects (no audio assets needed) played
## through a pool of 3D players.

const RATE := 22050
const POOL := 48
const RELEASE_SIREN := preload("res://audio/breakpoint_siren.wav")
const RELEASE_BELL := preload("res://audio/breakpoint_bell.wav")
const MELODY := [293.66, 0.0, 440.0, 349.23, 0.0, 392.0, 261.63, 0.0, 329.63, 0.0, 349.23, 220.0, 0.0, 261.63, 0.0, 0.0]
static var _music_stream: AudioStreamWAV

var _streams := {}
var _players: Array[AudioStreamPlayer3D] = []
var _idx := 0
var _loops := {}
var _rng := RandomNumberGenerator.new()
var _ui: Array[AudioStreamPlayer] = []
var _ui_idx := 0
var _horn_players: Array[AudioStreamPlayer3D] = []
var _gate_speaker: AudioStreamPlayer3D
var _school_bell: AudioStreamPlayer
var _goal_bell: AudioStreamPlayer
var _goal_timer: Timer
var _distance_update := 0.0
var _wind_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _bird_time := 120.0
var _outdoor_check := 0.0
var _outdoors := true


func _ready() -> void:
	_rng.seed = 42
	_streams["explosion"] = _make(2.4, _explosion)
	_streams["hammer"] = _make(0.35, _hammer)
	_streams["shotgun"] = _make(0.7, _shotgun)
	_streams["impact"] = _make(0.25, _impact)
	_streams["thud"] = _make(0.2, _thud)
	_streams["glass"] = _make(0.6, _glass)
	_streams["metal"] = _make(0.8, _metal)
	_streams["rocket"] = _make(0.9, _rocket)
	_streams["throw"] = _make(0.25, _whoosh)
	_streams["click"] = _make(0.06, _click)
	_streams["transit"] = _make(0.62, _transit)
	_streams["extinguisher"] = _make(1.0, _hiss, true)
	_streams["spray"] = _make(1.0, _spray, true)
	_streams["spray_clue"] = _make(0.46, _spray)
	_streams["fire"] = _make(2.0, _crackle, true)
	_streams["engine"] = _make(1.0, _engine, true)
	_streams["collapse"] = _make(3.6, _collapse)
	_streams["crumble"] = _make(0.6, _crumble)
	_streams["wood_break"] = _make(0.45, _wood_break)
	_streams["tree_fall"] = _make(1.4, _tree_fall)
	for surface in ["stone", "wood", "dirt", "metal"]:
		for variant in 2:
			var key := "step_%s_%d" % [surface, variant]
			_streams[key] = _make(0.23, _step.bind(surface, variant))
		for variant in 3:
			_streams["runstep_%s_%d" % [surface, variant]] = _make(0.27, _run_step.bind(surface, variant))
	var horn := _make(0.73, _horn)
	for i in 2:
		var speaker := AudioStreamPlayer3D.new()
		speaker.stream = horn
		speaker.unit_size = 14.0
		speaker.max_distance = 140.0
		speaker.attenuation_filter_cutoff_hz = 8000.0
		add_child(speaker)
		_horn_players.append(speaker)
	_streams["cloth_rip"] = _make(0.42, _fabric)
	_streams["hide_slide"] = _make(0.31, _fabric)
	_streams["hide_wood"] = _make(0.27, _wood_break)
	_streams["hurt"] = _make(0.3, _hurt)
	_streams["wind"] = _make(9.0, _wind, true)
	_streams["birds"] = _make(3.0, _birds)
	_streams["rifle"] = _make(0.55, _rifle)
	_streams["sniper"] = _make(1.4, _sniper)
	_streams["whiz"] = _make(0.28, _whiz)
	_streams["hitmark"] = _make(0.08, _hitmark)
	_streams["kill"] = _make(0.4, _kill)
	_streams["reload"] = _make(0.7, _reload)
	_streams["pin"] = _make(0.35, _pin)
	_streams["dry"] = _make(0.08, _click)
	for i in 6:
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui.append(u)
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 140.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players.append(p)


func play(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 6.0) -> void:
	if is_instance_valid(_school_bell) and _school_bell.playing and _masked_by_school_bell(name):
		return
	var p := _players[_idx]
	_idx = (_idx + 1) % POOL
	p.stream = _streams[name]
	p.unit_size = unit_size
	p.global_position = pos
	p.set_meta("source_db", volume_db)
	shape_distance(p, volume_db, listener_position())
	p.pitch_scale = pitch
	p.play()


func play_horn(pos: Vector3, local := false) -> void:
	var speaker := _horn_players[0 if local else 1]
	speaker.global_position = pos
	var level := -2.5 if local else 0.0
	speaker.set_meta("source_db", level)
	shape_distance(speaker, level, listener_position())
	speaker.play()


func install_gate_alarm(at: Vector3) -> void:
	_gate_speaker = AudioStreamPlayer3D.new()
	_gate_speaker.stream = _alarm_audio("res://audio/siren.mp3", RELEASE_SIREN, false)
	_gate_speaker.unit_size = 37.0
	_gate_speaker.max_distance = 205.0
	_gate_speaker.max_db = 2.0
	_gate_speaker.attenuation_filter_cutoff_hz = 6200.0
	add_child(_gate_speaker)
	_gate_speaker.global_position = at
	_gate_speaker.set_meta("source_db", 1.0)


func play_gate_alarm() -> void:
	if not _gate_speaker.playing:
		shape_distance(_gate_speaker, 1.0, listener_position())
		_gate_speaker.play()


func stop_gate_alarm() -> void:
	_gate_speaker.stop()


func listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if is_instance_valid(camera) else Vector3.INF


static func shape_distance(speaker: AudioStreamPlayer3D, level: float, listener: Vector3) -> void:
	var distance := speaker.global_position.distance_to(listener) if listener.is_finite() else 0.0
	var far := smoothstep(4.0, maxf(24.0, speaker.max_distance * 0.56), distance)
	speaker.attenuation_filter_cutoff_hz = lerpf(18000.0, 1250.0, far)
	speaker.attenuation_filter_db = lerpf(-3.0, -23.0, far)
	speaker.volume_db = level - far * 5.0


func _update_spatial(speaker: AudioStreamPlayer3D, at: Vector3) -> void:
	if is_instance_valid(speaker) and speaker.playing:
		shape_distance(speaker, float(speaker.get_meta("source_db", 0.0)), at)


static func siren_duration() -> float:
	return _alarm_audio("res://audio/siren.mp3", RELEASE_SIREN, false).get_length()


static func _alarm_audio(local_path: String, bundled: AudioStreamWAV, loop: bool) -> AudioStream:
	# Пользовательские записи доступны в рабочем проекте. В публичной сборке используются штатные звуки.
	if GameState.developer_tools() and ResourceLoader.exists(local_path):
		var original := load(local_path) as AudioStreamMP3
		if original != null:
			var recording := original.duplicate() as AudioStreamMP3
			recording.loop = loop
			return recording
	if not loop:
		return bundled
	var recording := bundled.duplicate() as AudioStreamWAV
	recording.loop_mode = AudioStreamWAV.LOOP_FORWARD
	recording.loop_end = recording.data.size() >> 1
	return recording


func install_school_bell() -> void:
	_streams["school_yard_siren"] = _alarm_audio("res://audio/siren.mp3", RELEASE_SIREN, true)
	_streams["school_pump"] = _make(2.0, _pump, true)
	_streams["school_drip"] = _make(0.35, _drip)

	_school_bell = AudioStreamPlayer.new()
	_school_bell.stream = _alarm_audio("res://audio/school_bell.mp3", RELEASE_BELL, true)
	_school_bell.volume_db = -3.0
	add_child(_school_bell)
	_goal_bell = AudioStreamPlayer.new()
	_goal_bell.stream = _alarm_audio("res://audio/school_bell.mp3", RELEASE_BELL, false)
	_goal_bell.volume_db = -8.0
	add_child(_goal_bell)
	_goal_timer = _stop_timer(_goal_bell.stop)


func _stop_timer(action: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(action)
	return timer


func goal_bell() -> void:
	if not _school_bell.playing:
		_goal_bell.play()
		_goal_timer.start(3.0)


func stop_goal_bell() -> void:
	_goal_timer.stop()
	_goal_bell.stop()


func school_bell(on: bool) -> void:
	if on:
		stop_goal_bell()
		var muted := {}
		for name: String in _streams:
			if _masked_by_school_bell(name):
				muted[_streams[name]] = true
		for speaker in _players:
			if speaker.playing and muted.has(speaker.stream):
				speaker.stop()
		_school_bell.play()
	else:
		_school_bell.stop()


func _masked_by_school_bell(name: String) -> bool:
	return name.begins_with("step_") or name.begins_with("runstep_") or name in ["hammer", "impact", "thud", "metal", "glass",
		"wood_break", "crumble", "collapse", "tree_fall", "cloth_rip"]





func _pump(t: float, _length: float, _state: Dictionary) -> float:
	return (sin(TAU * 48.0 * t) * 0.22 + sin(TAU * 96.0 * t) * 0.11) * (0.8 + 0.2 * sin(TAU * 1.5 * t))


func _drip(t: float, _length: float, _state: Dictionary) -> float:
	return sin(TAU * (920.0 * t + 1200.0 * t * t)) * exp(-t * 20.0) * 0.44


## Non-positional sound (hit markers, kill confirmations, whizzes at the ear).
func play_ui(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _ui[_ui_idx]
	_ui_idx = (_ui_idx + 1) % _ui.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Looping sounds keyed by an owner id.
func loop(key: String, name: String, pos: Vector3, on: bool, volume_db := -6.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer3D = _loops.get(key)
	if not on:
		if p and p.playing:
			p.stop()
		return
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		p.unit_size = 4.0
		add_child(p)
		_loops[key] = p
	p.global_position = pos
	if name == "spray":
		p.unit_size = 13.0
		p.max_distance = 55.0
	p.set_meta("source_db", volume_db)
	p.pitch_scale = pitch
	if p.stream != _streams[name]:
		p.stream = _streams[name]
	if not p.playing:
		shape_distance(p, volume_db, listener_position())
		p.play()


func _make(seconds: float, gen: Callable, looped := false) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var state := {"lp": 0.0, "lp2": 0.0, "hp": 0.0, "prev": 0.0, "phase": 0.0}
	for i in n:
		var t := float(i) / RATE
		var s: float = gen.call(t, seconds, state)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _transit(t: float, duration: float, _state: Dictionary) -> float:
	var envelope := pow(sin(PI * t / duration), 1.5)
	var phase := TAU * (195.0 * t + 360.0 * t * t)
	return envelope * (0.42 * sin(phase) + 0.18 * sin(phase * 1.51) + 0.09 * sin(phase * 2.03))


func _lowpass(st: Dictionary, key: String, x: float, k: float) -> float:
	st[key] = st[key] + (x - st[key]) * k
	return st[key]


func _explosion(t: float, _len: float, st: Dictionary) -> float:
	var env := exp(-t * 2.2) * minf(t * 300.0, 1.0)
	var rumble := _lowpass(st, "lp", _noise(), 0.05)
	var body := _lowpass(st, "lp2", _noise(), 0.25) * exp(-t * 9.0)
	var thump := sin(TAU * (48.0 - t * 18.0) * t) * exp(-t * 5.0)
	return (rumble * 3.2 + body * 0.9 + thump * 0.9) * env


func _hammer(t: float, _len: float, st: Dictionary) -> float:
	var thump := sin(TAU * 110.0 * t) * exp(-t * 28.0)
	var crack := _lowpass(st, "lp", _noise(), 0.4) * exp(-t * 45.0)
	return thump * 0.9 + crack * 0.8


func _shotgun(t: float, _len: float, st: Dictionary) -> float:
	var bang := _lowpass(st, "lp", _noise(), 0.55) * exp(-t * 14.0)
	var boom := _lowpass(st, "lp2", _noise(), 0.06) * exp(-t * 5.0) * 2.5
	return (bang + boom) * minf(t * 2000.0, 1.0)


func _impact(t: float, _len: float, st: Dictionary) -> float:
	var crunch := _lowpass(st, "lp", _noise(), 0.3) * exp(-t * 22.0)
	return crunch * 1.1 + sin(TAU * 80.0 * t) * exp(-t * 30.0) * 0.5


func _thud(t: float, _len: float, st: Dictionary) -> float:
	return _lowpass(st, "lp", _noise(), 0.08) * exp(-t * 25.0) * 2.5


func _glass(t: float, _len: float, st: Dictionary) -> float:
	var s := 0.0
	for k in 5:
		var f := 2400.0 + k * 830.0
		s += sin(TAU * f * t + k) * exp(-t * (9.0 + k * 3.0))
	var shards := (_noise() - _lowpass(st, "lp", _noise(), 0.2)) * exp(-t * 7.0)
	return s * 0.18 + shards * 0.5


func _metal(t: float, _len: float, _st: Dictionary) -> float:
	var s := 0.0
	var partials := [320.0, 787.0, 1310.0, 2100.0]
	for k in partials.size():
		s += sin(TAU * partials[k] * t) * exp(-t * (4.0 + k * 2.0)) / (k + 1)
	return s * 0.6 * minf(t * 3000.0, 1.0)


func _rocket(t: float, len: float, st: Dictionary) -> float:
	var env := minf(t * 20.0, 1.0) * (1.0 - t / len)
	return _lowpass(st, "lp", _noise(), 0.12 + t * 0.1) * env * 2.2


func _whoosh(t: float, len: float, st: Dictionary) -> float:
	var env := sin(PI * t / len)
	return _lowpass(st, "lp", _noise(), 0.08) * env * 1.5


func _click(t: float, _len: float, _st: Dictionary) -> float:
	return sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.5


func _hiss(_t: float, _len: float, st: Dictionary) -> float:
	var n := _noise()
	var hp := n - _lowpass(st, "lp", n, 0.15)
	return hp * 0.35 + _lowpass(st, "lp2", _noise(), 0.03) * 0.6


func _spray(_t: float, _len: float, st: Dictionary) -> float:
	var n := _noise()
	return (n - _lowpass(st, "lp", n, 0.35)) * 0.3


func _engine(t: float, _len: float, st: Dictionary) -> float:
	# 60 Hz firing pulse with harmonics plus a little exhaust noise.
	var s := 0.0
	for k in range(1, 7):
		s += sin(TAU * 60.0 * k * t + k * 0.7) / (k * 1.3)
	return s * 0.32 + _lowpass(st, "lp", _noise(), 0.1) * 0.25


func _crackle(t: float, _len: float, st: Dictionary) -> float:
	var bed := _lowpass(st, "lp", _noise(), 0.04) * 0.6
	var pop := 0.0
	if _rng.randf() < 0.0015:
		st["phase"] = 1.0
	if st["phase"] > 0.01:
		pop = _noise() * st["phase"]
		st["phase"] *= 0.985
	return bed + pop * 0.7 + sin(t) * 0.0


func ambient(outside_map: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if outside_map:
		_wind_player = AudioStreamPlayer.new()
		_wind_player.stream = _streams["wind"]
		_wind_player.volume_db = -24.0
		add_child(_wind_player)
		_wind_player.play()
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	GameState.settings_changed.connect(_update_music)
	_update_music()


func _update_music() -> void:
	if GameState.music_volume < 0.005:
		_music_player.stop()
		return
	if _music_stream == null:
		_music_stream = _make(24.0, _music, true)
	if _music_player.stream != _music_stream:
		_music_player.stream = _music_stream
	_music_player.volume_db = -21.0 + linear_to_db(GameState.music_volume)
	if not _music_player.playing:
		_music_player.play()


func _process(delta: float) -> void:
	_distance_update -= delta
	if _distance_update <= 0.0:
		_distance_update = 0.12
		var listener := listener_position()
		for speaker in _players:
			_update_spatial(speaker, listener)
		for speaker in _horn_players:
			_update_spatial(speaker, listener)
		for speaker: AudioStreamPlayer3D in _loops.values():
			_update_spatial(speaker, listener)
		_update_spatial(_gate_speaker, listener)
	if _wind_player == null:
		return
	var world := get_parent() as VoxelWorld
	if world.player == null:
		return
	var at := world.player.global_position + Vector3.UP * 1.6
	_outdoor_check -= delta
	if _outdoor_check <= 0.0:
		_outdoor_check = 0.7
		_outdoors = world.raycast(at, at + Vector3.UP * 15.0, Layers.STATIC).is_empty()
	_wind_player.volume_db = lerpf(_wind_player.volume_db, -24.0 if _outdoors else -45.0, minf(1.0, delta * 2.2))
	_bird_time -= delta
	if _bird_time <= 0.0:
		_bird_time += 120.0
		if _outdoors:
			var offset := Vector3(randf_range(-12.0, 12.0), 7.0, randf_range(-12.0, 12.0))
			play("birds", at + offset, -13.0, randf_range(0.91, 1.08))


func _collapse(t: float, len: float, st: Dictionary) -> float:
	var env := minf(t * 4.0, 1.0) * exp(-t * 0.9) * (0.7 + 0.3 * sin(t * 9.0))
	var rumble := _lowpass(st, "lp", _noise(), 0.03) * 4.0
	var grit := _lowpass(st, "lp2", _noise(), 0.3) * (0.3 if _rng.randf() < 0.02 else 0.05)
	return (rumble + grit) * env


func _crumble(t: float, _len: float, st: Dictionary) -> float:
	var grains := _noise() * (1.0 if _rng.randf() < 0.08 else 0.15)
	return (_lowpass(st, "lp", grains, 0.25) * 2.2 + _lowpass(st, "lp2", _noise(), 0.05) * 1.2) * exp(-t * 6.0)


func _wood_break(t: float, _len: float, st: Dictionary) -> float:
	var crack := _noise() * (1.0 if fmod(t, 0.07) < 0.004 else 0.2)
	return (_lowpass(st, "lp", crack, 0.5) * 1.4 + sin(TAU * 140.0 * t) * 0.4) * exp(-t * 8.0)


func _tree_fall(t: float, len: float, st: Dictionary) -> float:
	var n := _noise()
	var bark := _lowpass(st, "lp", n, 0.3)
	var snap := exp(-t * 24.0) + 0.58 * exp(-absf(t - 0.22) * 28.0) + 0.38 * exp(-absf(t - 0.48) * 32.0)
	var leaves := (n - bark) * smoothstep(0.16, 0.62, t) * (1.0 - smoothstep(0.78, len, t))
	return bark * snap * 0.97 + leaves * 0.18


func footstep(material: int, at: Vector3, running: bool, crouch: bool, own := false) -> void:
	var surface := "stone"
	if material == VoxMat.WOOD:
		surface = "wood"
	elif material in [VoxMat.DIRT, VoxMat.FOLIAGE]:
		surface = "dirt"
	elif material in [VoxMat.METAL, VoxMat.HARDMETAL]:
		surface = "metal"
	var clip := "runstep_%s_%d" % [surface, randi_range(0, 2)] if running else "step_%s_%d" % [surface, randi_range(0, 1)]
	var volume := -20.0 if crouch else (-8.0 if running else -12.0)
	if own:
		volume -= 13.0 if crouch else 16.0
	play(clip, at, volume, randf_range(0.94, 1.06), 7.0)
	if not own and GameState.level == GameState.LEVEL_SCHOOL and at.x > 35.0 and at.x < 57.8 and at.z > -14.8 and at.z < 0.95 and at.y > 5.8 and at.y < 9.3:
		get_tree().create_timer(0.14, false).timeout.connect(func():
			play("step_wood_0", at + Vector3(2.5, 1.2, -1.0), -24.0, 0.86))


func _run_step(t: float, _len: float, st: Dictionary, surface: String, variant: int) -> float:
	var noise := _noise()
	var sole := _lowpass(st, "lp", noise, 0.065)
	var grain := _lowpass(st, "lp2", noise, 0.31) - sole
	var strike := smoothstep(0.0, 0.008, t) * exp(-t * 33.0)
	var lift := t - (0.057 + float(variant) * 0.013)
	var scrape := smoothstep(0.0, 0.018, lift) * exp(-maxf(lift, 0.0) * 38.0)
	var heel := sin(TAU * (72.0 + variant * 8.0) * t - 104.0 * t * t) * strike
	match surface:
		"dirt": return (sole * 0.95 + grain * 0.49) * (strike + scrape * 0.43) + heel * 0.25
		"wood": return sole * strike + heel * 0.55 + grain * scrape * 0.40 + sin(TAU * 164.0 * t) * strike * 0.20
		"metal": return sole * strike + heel * 0.36 + grain * scrape * 0.30 + sin(TAU * (300.0 + variant * 39.0) * t) * strike * 0.27
	return sole * strike + heel * 0.48 + grain * (strike * 0.45 + scrape * 0.35)


func _step(t: float, _len: float, st: Dictionary, surface: String, variant: int) -> float:
	var n := _noise()
	var low := _lowpass(st, "lp", n, 0.09)
	var slap := exp(-t * 41.0) + 0.27 * exp(-absf(t - (0.063 + 0.018 * variant)) * 66.0)
	var heel := sin(TAU * (87.0 * t - t * t * 60.0)) * exp(-t * 30.0)
	match surface:
		"dirt": return (low * 1.08 + (n - low) * 0.13) * slap + heel * 0.16
		"wood": return low * 0.77 * slap + heel * 0.48 + sin(TAU * 198.0 * t) * exp(-t * 35.0) * 0.20
		"metal": return low * 0.62 * slap + sin(TAU * (400.0 + variant * 46.0) * t) * exp(-t * 23.0) * 0.22 + heel * 0.33
	return (n * 0.16 + low * 0.90) * slap + heel * 0.26


func _hurt(t: float, _len: float, st: Dictionary) -> float:
	return (sin(TAU * 70.0 * t) * 0.9 + _lowpass(st, "lp", _noise(), 0.2) * 0.6) * exp(-t * 12.0)


func _wind(t: float, len: float, st: Dictionary) -> float:
	var gust := 0.67 + 0.28 * sin(TAU * t / len) * sin(TAU * t * 2.0 / len + 1.0)
	var n := _noise()
	var air := _lowpass(st, "lp", n, 0.012) * 2.4
	var leaves := (_lowpass(st, "lp2", n, 0.15) - air * 0.19) * (0.26 + 0.12 * sin(TAU * t * 5.0 / len))
	return (air + leaves) * gust


func _birds(t: float, _len: float, _st: Dictionary) -> float:
	for i in 3:
		var local := t - (0.37 + 0.49 * i + 0.08 * i * i)
		if local >= 0.0 and local < 0.31:
			var k := local / 0.31
			var phase := TAU * ((1450.0 + i * 100.0) * local + 540.0 * local * local)
			return (sin(phase) + 0.13 * sin(phase * 2.0)) * pow(sin(k * PI), 1.8) * (0.23 - i * 0.037)
	return 0.0


func _music(t: float, _len: float, _st: Dictionary) -> float:
	var index := int(t / 1.5)
	var note: float = MELODY[index % MELODY.size()]
	var local := fmod(t, 1.5)
	var piano := 0.0
	if note > 0.0:
		var phase := TAU * note * local
		var envelope := smoothstep(0.0, 0.06, local) * (1.0 - smoothstep(1.0, 1.5, local)) * exp(-local * 1.35)
		piano = (sin(phase) + sin(phase * 2.01) * 0.16 + sin(phase * 3.01) * 0.05) * envelope * 0.31
	var wave := sin(TAU * t / 6.0) * 0.09 + 0.15
	var pad := (sin(TAU * 73.4167 * t) + sin(TAU * 110.0 * t) * 0.62 + sin(TAU * 130.8333 * t) * 0.32) * wave
	return (piano + pad) * smoothstep(0.0, 0.55, t) * (1.0 - smoothstep(23.5, 24.0, t))


func _horn(t: float, len: float, st: Dictionary) -> float:
	var sustain := smoothstep(0.004, 0.029, t) * (1.0 - smoothstep(len - 0.12, len, t))
	var rise := 0.0036 * (1.0 - exp(-t * 62.0))
	var low := _horn_reed(TAU * 404.0 * (t + rise))
	var high := _horn_reed(TAU * 497.0 * (t + rise * 0.91) + 0.65)
	var attack := _lowpass(st, "lp", _noise(), 0.28) * exp(-t * 64.0) * 0.10
	return tanh(low * 0.85 + high * 0.70 + attack) * sustain * 0.98


func _horn_reed(phase: float) -> float:
	return sin(phase) * 0.81 + sin(phase * 2.0 + 0.3) * 0.34 + sin(phase * 3.0 + 0.7) * 0.24 + sin(phase * 5.0) * 0.11


func _fabric(t: float, len: float, st: Dictionary) -> float:
	var n := _noise()
	var strands := 0.56 + 0.28 * sin(t * 91.0) + 0.16 * sin(t * 148.0)
	return (_lowpass(st, "lp", n, 0.25) * 1.25 + n * 0.25) * strands * sin(PI * t / len) * exp(-t * 4.0)


func _rifle(t: float, _len: float, st: Dictionary) -> float:
	var n := _noise()
	var crack := (n - _lowpass(st, "hp", n, 0.3)) * exp(-t * 70.0) * 1.4
	var body := _lowpass(st, "lp", _noise(), 0.22) * exp(-t * 15.0) * 1.2
	var boom := _lowpass(st, "lp2", _noise(), 0.035) * exp(-t * 6.5) * 2.2
	return (crack + body + boom + sin(TAU * 95.0 * t) * exp(-t * 35.0) * 0.6) * minf(t * 4000.0, 1.0)


func _sniper(t: float, _len: float, st: Dictionary) -> float:
	var n := _noise()
	var crack := (n - _lowpass(st, "hp", n, 0.25)) * exp(-t * 45.0) * 1.6
	var boom := _lowpass(st, "lp2", _noise(), 0.03) * exp(-t * 3.2) * 3.0
	var body := _lowpass(st, "lp", _noise(), 0.18) * exp(-t * 9.0)
	# Slap-back echo off the buildings.
	var echo := 0.0
	if t > 0.32:
		echo = _lowpass(st, "prev", _noise(), 0.06) * exp(-(t - 0.32) * 5.0) * 0.9
	return (crack + boom + body + echo) * minf(t * 4000.0, 1.0)


func _whiz(t: float, len: float, st: Dictionary) -> float:
	var env := pow(sin(PI * t / len), 3.0)
	var n := _noise()
	var band := _lowpass(st, "lp", n - _lowpass(st, "lp2", n, 0.08), 0.35)
	st["phase"] += TAU * lerpf(1500.0, 650.0, t / len) / RATE
	return (band * 1.6 + sin(st["phase"]) * 0.25) * env


func _hitmark(t: float, _len: float, _st: Dictionary) -> float:
	return (sin(TAU * 2900.0 * t) * 0.5 + sin(TAU * 1700.0 * t) * 0.3) * exp(-t * 110.0)


func _kill(t: float, _len: float, _st: Dictionary) -> float:
	var a := sin(TAU * 1320.0 * t) * exp(-t * 14.0)
	var b := sin(TAU * 1980.0 * t) * exp(-maxf(t - 0.07, 0.0) * 12.0) * (1.0 if t > 0.07 else 0.0)
	return (a + b) * 0.35


func _reload(t: float, _len: float, _st: Dictionary) -> float:
	var s := 0.0
	for ti in [0.0, 0.2, 0.47]:
		if t >= ti:
			var k: float = t - ti
			s += (_noise() * 0.7 + sin(TAU * 900.0 * k)) * exp(-k * 160.0)
	return s * 0.6


func _pin(t: float, _len: float, _st: Dictionary) -> float:
	return (sin(TAU * 3100.0 * t) + sin(TAU * 4700.0 * t) * 0.5) * exp(-t * 18.0) * 0.3
