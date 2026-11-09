class_name Sfx
extends Node3D
## Procedurally synthesized sound effects (no audio assets needed) played
## through a pool of 3D players.

const RATE := 22050
const POOL := 48

var _streams := {}
var _players: Array[AudioStreamPlayer3D] = []
var _idx := 0
var _loops := {}
var _rng := RandomNumberGenerator.new()
var _ui: Array[AudioStreamPlayer] = []
var _ui_idx := 0


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
	_streams["torch"] = _make(1.0, _hiss, true)
	_streams["spray"] = _make(1.0, _spray, true)
	_streams["fire"] = _make(2.0, _crackle, true)
	_streams["engine"] = _make(1.0, _engine, true)
	_streams["collapse"] = _make(3.6, _collapse)
	_streams["crumble"] = _make(0.6, _crumble)
	_streams["wood_break"] = _make(0.45, _wood_break)
	_streams["step"] = _make(0.12, _step)
	_streams["hurt"] = _make(0.3, _hurt)
	_streams["wind"] = _make(4.0, _wind, true)
	_streams["birds"] = _make(6.0, _birds, true)
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


func play(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _players[_idx]
	_idx = (_idx + 1) % POOL
	p.stream = _streams[name]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Non-positional sound (hit markers, kill confirmations, whizzes at the ear).
func play_ui(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _ui[_ui_idx]
	_ui_idx = (_ui_idx + 1) % _ui.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Looping sounds (torch, spray, fire) keyed by an owner id.
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
	p.volume_db = volume_db
	p.pitch_scale = pitch
	if p.stream != _streams[name]:
		p.stream = _streams[name]
	if not p.playing:
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


## Non-positional ambience (wind, birds) for outdoor maps.
func ambient(on: bool) -> void:
	for n in ["wind", "birds"]:
		var p: AudioStreamPlayer = get_node_or_null("amb_" + n)
		if p == null:
			p = AudioStreamPlayer.new()
			p.name = "amb_" + n
			p.stream = _streams[n]
			p.volume_db = -20.0 if n == "wind" else -17.0
			add_child(p)
		if on and not p.playing:
			p.play()
		elif not on:
			p.stop()


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


func _step(t: float, _len: float, st: Dictionary) -> float:
	return _lowpass(st, "lp", _noise(), 0.12) * exp(-t * 40.0) * 2.0


func _hurt(t: float, _len: float, st: Dictionary) -> float:
	return (sin(TAU * 70.0 * t) * 0.9 + _lowpass(st, "lp", _noise(), 0.2) * 0.6) * exp(-t * 12.0)


func _wind(t: float, len: float, st: Dictionary) -> float:
	var gust := 0.6 + 0.4 * sin(TAU * t / len) * sin(TAU * t * 2.0 / len + 1.0)
	return _lowpass(st, "lp", _noise(), 0.015) * 3.0 * gust


func _birds(t: float, _len: float, st: Dictionary) -> float:
	if st["phase"] <= 0.0 and _rng.randf() < 0.00012:
		st["phase"] = 0.18
		st["prev"] = _rng.randf_range(2200.0, 4200.0)
	if st["phase"] > 0.0:
		st["phase"] -= 1.0 / RATE
		var k: float = 1.0 - st["phase"] / 0.18
		var f: float = st["prev"] * (1.0 + 0.35 * sin(k * PI * 3.0))
		st["hp"] += TAU * f / RATE
		return sin(st["hp"]) * sin(k * PI) * 0.25
	return 0.0


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
