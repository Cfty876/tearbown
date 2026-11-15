extends Node

signal settings_changed

const LEVEL_PROTO := "proto"
const LEVEL_DISTRICT := "district"
const LEVEL_HIDE := "hide"
const LEVEL_SCHOOL := "school"
const GRAPHICS_FILE := "user://graphics.cfg"
const MAPS := {
	LEVEL_DISTRICT: ["Дворы Заречья", "Пятиэтажки, дворы и проходные подъезды", "res://ui/map_district.jpg"],
	LEVEL_PROTO: ["Полигон", "Дом, мастерские и зона испытаний", "res://ui/map_proto.jpg"],
	LEVEL_SCHOOL: ["Школа № 120", "Сумерки в школьном квартале. Четыре этажа, стадион и подземелья", "res://ui/map_school.jpg"],
	LEVEL_HIDE: ["Арена", "Компактная карта для быстрых раундов", "res://ui/map_pocket.jpg"],
}


func room_map_allowed(map: String) -> bool:
	return MAPS.has(map)


func map_info(map: String) -> Array:
	return MAPS.get(map, MAPS[LEVEL_DISTRICT])


func developer_tools() -> bool:
	return OS.has_feature("editor") or OS.has_feature("dev_tools")


var level := LEVEL_DISTRICT
var cinematic := ""
var bot_hide := false
var bot_record_batch := ""
var quality := Quality.LOW
var adaptive_resolution := true
var lens_effects := true
var autofocus := true
var sun_rays := true
var motion_blur := true
var edge_strength := 0.75
var motion_strength := 0.65
var cinematic_fx := false
var music_volume := 0.25
var fullscreen := true
var vsync := true
var fps_limit := 60
var mouse_speed := 1.0
var fov := 78.0
var invert_y := false
var master_volume := 0.85
var bindings := {}
var map_options := MapStyle.DEFAULTS.duplicate()
var _loading: CanvasLayer
var _loading_panel: Control
var _progress: ProgressBar
var _loading_text: Label


func _ready() -> void:
	if OS.has_feature("web") and TouchControls.available():
		lens_effects = false
	var saved := ConfigFile.new()
	if saved.load(GRAPHICS_FILE) == OK:
		quality = clampi(int(saved.get_value("graphics", "quality", quality)), 0, 3)
		adaptive_resolution = bool(saved.get_value("graphics", "adaptive_resolution", adaptive_resolution))
		lens_effects = bool(saved.get_value("graphics", "lens_effects", lens_effects))
		autofocus = bool(saved.get_value("graphics", "autofocus", autofocus))
		sun_rays = bool(saved.get_value("graphics", "sun_rays", sun_rays))
		motion_blur = bool(saved.get_value("graphics", "motion_blur", motion_blur))
		edge_strength = clampf(float(saved.get_value("graphics", "edge_strength", edge_strength)), 0.1, 1.5)
		motion_strength = clampf(float(saved.get_value("graphics", "motion_strength", motion_strength)), 0.1, 1.5)
		cinematic_fx = bool(saved.get_value("graphics", "cinematic_fx", cinematic_fx))
		fullscreen = bool(saved.get_value("display", "fullscreen", fullscreen))
		vsync = bool(saved.get_value("display", "vsync", vsync))
		fps_limit = int(saved.get_value("display", "fps_limit", fps_limit))
		mouse_speed = clampf(float(saved.get_value("controls", "sensitivity", mouse_speed)), 0.25, 3.0)
		fov = clampf(float(saved.get_value("controls", "fov", fov)), 60.0, 110.0)
		invert_y = bool(saved.get_value("controls", "invert_y", invert_y))
		bindings = saved.get_value("controls", "keys", {}) as Dictionary
		master_volume = clampf(float(saved.get_value("audio", "master", master_volume)), 0.0, 1.0)
		music_volume = clampf(float(saved.get_value("audio", "music", music_volume)), 0.0, 1.0)
		map_options = MapStyle.settings(saved.get_value("map", "options", {}) as Dictionary)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"level":
				level = kv[1] if kv.size() > 1 else LEVEL_DISTRICT
				if level == "pocket":
					level = LEVEL_SCHOOL
			"cinematic":
				cinematic = kv[1] if kv.size() > 1 else "all"
			"quality" when kv.size() > 1:
				quality = clampi(int(kv[1]), 0, 3)
			"no-lens":
				lens_effects = false
				autofocus = false
				sun_rays = false
			"no-motion-blur":
				motion_blur = false
			"windowed":
				fullscreen = false
	GameControls.install(bindings)
	get_window().title = "BREAKPOINT — Дворы Заречья"
	apply_preferences()


func _input(event: InputEvent) -> void:
	if not OS.has_feature("web") and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		fullscreen = not fullscreen
		save_graphics()
		get_viewport().set_input_as_handled()


func apply_preferences() -> void:
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var window := get_window()
		var desired := Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		if window.mode != desired:
			window.mode = desired
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))
	AudioServer.set_bus_mute(0, master_volume == 0.0)


func save_graphics() -> void:
	apply_preferences()
	var saved := ConfigFile.new()
	saved.set_value("graphics", "quality", quality)
	saved.set_value("graphics", "adaptive_resolution", adaptive_resolution)
	saved.set_value("graphics", "lens_effects", lens_effects)
	saved.set_value("graphics", "autofocus", autofocus)
	saved.set_value("graphics", "sun_rays", sun_rays)
	saved.set_value("graphics", "motion_blur", motion_blur)
	saved.set_value("graphics", "edge_strength", edge_strength)
	saved.set_value("graphics", "motion_strength", motion_strength)
	saved.set_value("graphics", "cinematic_fx", cinematic_fx)
	saved.set_value("display", "fullscreen", fullscreen)
	saved.set_value("display", "vsync", vsync)
	saved.set_value("display", "fps_limit", fps_limit)
	saved.set_value("controls", "sensitivity", mouse_speed)
	saved.set_value("controls", "fov", fov)
	saved.set_value("controls", "invert_y", invert_y)
	saved.set_value("controls", "keys", bindings)
	saved.set_value("audio", "master", master_volume)
	saved.set_value("audio", "music", music_volume)
	saved.set_value("map", "options", map_options)
	saved.save(GRAPHICS_FILE)
	settings_changed.emit()


func start(new_level: String, cine := "", hunt_bot := false, record_bot := false) -> void:
	if is_instance_valid(_loading):
		return
	level = LEVEL_SCHOOL if new_level == "pocket" else new_level
	bot_hide = hunt_bot and level == LEVEL_SCHOOL and not WebSession.connected
	bot_record_batch = SchoolReplayRecorder.open_batch() if bot_hide and record_bot else ""
	get_window().title = "BREAKPOINT — " + str(map_info(level)[0])
	cinematic = cine
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	var result := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if result != OK:
		finish_loading()


func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 100
	_loading.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_loading)
	_loading_panel = Control.new()
	_loading.add_child(_loading_panel)
	_loading_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var map: Array = map_info(level)
	var cover := MenuStyle.cover(MenuStyle.image(map[2]))
	_loading_panel.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color("#10161c9e")
	_loading_panel.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_loading_panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 110
	box.offset_right = -110
	box.offset_top = -300
	box.offset_bottom = -76
	box.add_child(MenuStyle.label("BREAKPOINT   /   ПОДГОТОВКА КАРТЫ", 24, MenuStyle.GOLD))
	box.add_child(MenuStyle.label(map[0], 68))
	_loading_text = MenuStyle.label("Загрузка сцены", 23)
	box.add_child(_loading_text)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 9
	_progress.add_theme_stylebox_override("background", MenuStyle.panel(Color("#131820"), Color.TRANSPARENT, 4))
	_progress.add_theme_stylebox_override("fill", MenuStyle.panel(MenuStyle.GOLD, Color.TRANSPARENT, 4))
	box.add_child(_progress)
	loading_status("Загрузка сцены", 5)


func loading_status(status: String, percent: float) -> void:
	if is_instance_valid(_loading):
		_loading_text.text = "%s     %d%%" % [status, int(percent)]
		_progress.value = percent


func finish_loading() -> void:
	if not is_instance_valid(_loading):
		return
	_loading.queue_free()
	_loading = null


func to_menu() -> void:
	finish_loading()
	WebSession.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func exit_game() -> void:
	WebSession.leave()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		get_tree().quit()
