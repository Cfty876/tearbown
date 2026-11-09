extends Node
## Autoload "GameState": what the main scene should load.

const LEVEL_PROTO := "proto"
const LEVEL_DISTRICT := "district"
const LEVEL_HIDE := "hide"
const LEVEL_POCKET := "pocket"
const GRAPHICS_FILE := "user://graphics.cfg"
var level := LEVEL_DISTRICT
## Empty for normal play, "all" or a shot name to run the cinematic fly-throughs.
var cinematic := ""
var quality := Quality.LOW
var lens_effects := true
var motion_blur := true


func _ready() -> void:
	if OS.has_feature("web") and TouchControls.available():
		lens_effects = false
	var saved := ConfigFile.new()
	if saved.load(GRAPHICS_FILE) == OK:
		quality = clampi(int(saved.get_value("graphics", "quality", quality)), 0, 3)
		lens_effects = bool(saved.get_value("graphics", "lens_effects", lens_effects))
		motion_blur = bool(saved.get_value("graphics", "motion_blur", motion_blur))
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"level":
				level = kv[1] if kv.size() > 1 else LEVEL_DISTRICT
			"cinematic":
				cinematic = kv[1] if kv.size() > 1 else "all"
			"quality" when kv.size() > 1:
				quality = clampi(int(kv[1]), 0, 3)
			"no-lens":
				lens_effects = false
			"no-motion-blur":
				motion_blur = false


func save_graphics() -> void:
	var saved := ConfigFile.new()
	saved.set_value("graphics", "quality", quality)
	saved.set_value("graphics", "lens_effects", lens_effects)
	saved.set_value("graphics", "motion_blur", motion_blur)
	saved.save(GRAPHICS_FILE)


func start(new_level: String, cine := "") -> void:
	level = new_level
	cinematic = cine
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func to_menu() -> void:
	if WebSession.connected:
		WebSession.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func exit_game() -> void:
	if OS.has_feature("web"):
		WebSession.leave()
		JavaScriptBridge.eval("location.reload()")
	else:
		get_tree().quit()
