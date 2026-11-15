class_name DistrictVoice
extends Node

const SAMPLE_RATE := 16000
const FRAMES_PER_PACKET := 800
const BUS := "DistrictVoiceCapture"

var round_number := 0
var allowed := false
var public_address := false
var _capture := AudioEffectCapture.new()
var _microphone: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _recording := false
var _bus := -1
var _input_frames := 0


func _ready() -> void:
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, BUS)
	AudioServer.set_bus_volume_db(_bus, -80.0)
	_capture.buffer_length = 0.20
	AudioServer.add_bus_effect(_bus, _capture)
	_input_frames = roundi(AudioServer.get_mix_rate() * FRAMES_PER_PACKET / SAMPLE_RATE)
	_microphone = AudioStreamPlayer.new()
	_microphone.stream = AudioStreamMicrophone.new()
	_microphone.bus = BUS
	add_child(_microphone)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.22
	var output := AudioStreamPlayer.new()
	output.stream = generator
	add_child(output)
	output.play()
	_playback = output.get_stream_playback() as AudioStreamGeneratorPlayback


func _exit_tree() -> void:
	if is_instance_valid(_microphone):
		_microphone.stop()
	if _bus >= 0 and AudioServer.get_bus_name(_bus) == BUS:
		AudioServer.remove_bus(_bus)


func _process(_delta: float) -> void:
	var pressed := allowed and WebSession.connected and Input.is_action_pressed("voice_chat")
	if pressed != _recording:
		_recording = pressed
		if pressed:
			_capture.clear_buffer()
			_microphone.play()
		else:
			_microphone.stop()
	if not _recording or _capture.get_frames_available() < _input_frames:
		return
	var frames := _capture.get_buffer(_input_frames)
	if frames.size() < _input_frames:
		return
	var bytes := PackedByteArray()
	bytes.resize(FRAMES_PER_PACKET)
	var peak := 0.0
	for i in FRAMES_PER_PACKET:
		var sample := frames[int(i * _input_frames / float(FRAMES_PER_PACKET))]
		var mono := (sample.x + sample.y) * 0.5
		peak = maxf(peak, absf(mono))
		bytes[i] = clampi(roundi(mono * 153.0 + 128.0), 0, 255)
	if peak > 0.006:
		WebSession.send({"k": "district_voice", "round": round_number,
			"audio": Marshalls.raw_to_base64(bytes), "pa": public_address}, false)


func receive(packet: Dictionary) -> void:
	if not is_instance_valid(_playback) or int(packet.get("round", -1)) != round_number:
		return
	var encoded := str(packet.get("audio", ""))
	if encoded.length() != 1068 or not _playback.can_push_buffer(FRAMES_PER_PACKET):
		return
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.size() != FRAMES_PER_PACKET:
		return
	var frames := PackedVector2Array()
	frames.resize(FRAMES_PER_PACKET)
	var pa := bool(packet.get("pa", false))
	var low := 0.0
	var filtered := 0.0
	for i in FRAMES_PER_PACKET:
		var sample := (float(bytes[i]) - 128.0) / 153.0
		if pa:
			low = lerpf(low, sample, 0.095)
			filtered = lerpf(filtered, sample - low, 0.48)
			sample = tanh(filtered * 2.25) * 0.82
		frames[i] = Vector2(sample, sample)
	_playback.push_buffer(frames)
