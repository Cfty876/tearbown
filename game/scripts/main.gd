extends Node3D
## Entry point: input map, lighting/post-processing, world, level, player, HUD.
## The level comes from GameState (main menu) or --level=district|proto.
## Command line (after --): --bench runs the scripted benchmark, --tour takes
## screenshots from fixed viewpoints, --shots=<dir> sets the screenshot folder,
## --cinematic=<all|shot> plays the fly-throughs, --quit exits when a scripted
## run is over, --quality=<0..3>.

var world: VoxelWorld
var player: Player
var hud: Hud
var env: Environment
var sun: DirectionalLight3D
var lens: CameraLens
var heightfield: GPUParticlesCollisionHeightField3D
var quality := Quality.LOW
var args := {}
var level  # TestLevel or DistrictLevel


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_setup_input()
	VoxMat.setup()
	var district := GameState.level == GameState.LEVEL_DISTRICT
	var online := GameState.level == GameState.LEVEL_HIDE and WebSession.connected
	var pocket := GameState.level == GameState.LEVEL_POCKET
	var compact := online or pocket
	_setup_environment(district)

	world = VoxelWorld.new()
	world.name = "World"
	if online:
		world.network_role = 1 if WebSession.is_host else 2
	add_child(world)
	var t0 := Time.get_ticks_msec()
	if compact:
		level = HideLevel.new(world, pocket)
	else:
		level = DistrictLevel.new(world) if district else TestLevel.new(world)
	level.build()
	world.impacts_after_ms = Time.get_ticks_msec() + 3000
	world.sfx.ambient(district)
	print("[level] %s built in %d ms, %d objects; chunks %d, boxes %d, chunk total %d ms (physics part %d ms)" % [
		GameState.level, Time.get_ticks_msec() - t0, world.objects.size(), VoxelObject.prof.chunks, VoxelObject.prof.boxes,
		VoxelObject.prof.mesh_usec / 1000, VoxelObject.prof.phys_usec / 1000])

	player = Player.new()
	player.name = "Player"
	player.touch_mode = TouchControls.available()
	add_child(player)
	player.global_position = level.spawn
	player.spawn_point = level.spawn
	player.border = HideLevel.HALF - 0.6 if compact else (DistrictLevel.HALF - 0.6 if district else 39.4)
	if district:
		player.look_at_dir(level.spawn_yaw, 0.0)
	elif online and not WebSession.is_host:
		player.look_at_dir(PI, 0.0)
	world.player = player
	world.limit_distant_physics = OS.has_feature("web") and not online
	if world.limit_distant_physics:
		world.update_prop_activity()

	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		heightfield = GPUParticlesCollisionHeightField3D.new()
		heightfield.size = Vector3(206, 40, 206) if district else Vector3(84, 30, 84)
		heightfield.position = Vector3(0, 12, 0)
		heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
		add_child(heightfield)

	lens = CameraLens.new()
	lens.world = world
	lens.sun = sun
	add_child(lens)

	hud = Hud.new()
	hud.player = player
	hud.world = world
	add_child(hud)
	var pause_menu := PauseMenu.new()
	pause_menu.lens = lens
	pause_menu.touch_mode = player.touch_mode
	add_child(pause_menu)
	pause_menu.quality_changed.connect(func(preset: int):
		quality = preset
		GameState.quality = preset
		GameState.save_graphics()
		_apply_quality())
	if player.touch_mode:
		var mobile_ui := CanvasLayer.new()
		mobile_ui.layer = 16
		add_child(mobile_ui)
		var touch := TouchControls.new()
		touch.player = player
		touch.inventory = hud._inventory
		touch.pause = pause_menu
		mobile_ui.add_child(touch)

	quality = GameState.quality
	if args.has("quality"):
		quality = clampi(int(args.quality), 0, 3)
	_apply_quality()
	get_window().size_changed.connect(func(): Quality.apply_resolution(quality, get_viewport()))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if player.touch_mode else Input.MOUSE_MODE_CAPTURED
	if online:
		var round := NetworkHide.new()
		round.player = player
		round.world = world
		round.pause_menu = pause_menu
		add_child(round)
		return
	if args.has("no_occlusion"):
		get_viewport().use_occlusion_culling = false

	if GameState.cinematic != "":
		var c := Cinematic.new()
		c.main = self
		c.shot = GameState.cinematic
		c.quit_when_done = args.has("quit")
		c.shot_dir = args.get("shots", "")
		c.titles = args.has("titles")
		add_child(c)
	elif args.has("audit"):
		var au := CollisionAudit.new()
		au.main = self
		au.quit_when_done = args.has("quit")
		add_child(au)
	elif args.has("bench") or args.has("tour") or args.has("drive") or args.has("tools") or args.has("crater") or args.has("dtour") or args.has("glass"):
		var b := Bench.new()
		b.main = self
		b.mode = "tour" if args.has("tour") else ("drive" if args.has("drive") else ("tools" if args.has("tools") else ("crater" if args.has("crater") else ("dtour" if args.has("dtour") else ("glass" if args.has("glass") else "bench")))))
		b.shot_dir = args.get("shots", "user://shots")
		b.quit_when_done = args.has("quit")
		add_child(b)
	else:
		if not player.touch_mode:
			hud.message("F1 — справка, Esc — пауза", 4.0)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("quality"):
		quality = (quality + 1) % 4
		GameState.quality = quality
		GameState.save_graphics()
		_apply_quality()
		hud.message("Качество: " + Quality.NAMES[quality])
	elif e.is_action_pressed("reset_level") and not WebSession.connected:
		get_tree().reload_current_scene()
	elif e.is_action_pressed("bench") and not has_node("Bench") and GameState.level == GameState.LEVEL_PROTO:
		var b := Bench.new()
		b.name = "Bench"
		b.main = self
		b.shot_dir = "user://shots"
		add_child(b)


func _apply_quality() -> void:
	Quality.apply(quality, env, sun, get_viewport())
	var particles: float = [0.5, 0.72, 1.0, 1.0][quality]
	if OS.has_feature("web"):
		var district := GameState.level == GameState.LEVEL_DISTRICT
		var view_ranges := [72.0, 105.0, 155.0, 200.0] if district else [64.0, 82.0, 95.0, 110.0]
		player.camera.far = view_ranges[quality]
		if GameState.level != GameState.LEVEL_HIDE:
			env.fog_mode = Environment.FOG_MODE_DEPTH
			env.fog_depth_begin = player.camera.far * 0.68
			env.fog_depth_end = player.camera.far * 0.98
		particles *= 0.56
		world.debris.set_budget([110, 160, 220, 300][quality])
	else:
		world.debris.set_budget([300, 460, 700, 700][quality])
	var particle_shadows := quality >= Quality.HIGH and not OS.has_feature("web")
	world.fire.set_visual_budget(particles, [1, 2, 3, 3][quality], particle_shadows)
	world.fx.set_visual_budget(particles, particle_shadows)
	if heightfield:
		heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_2048 if quality >= Quality.HIGH and GameState.level == GameState.LEVEL_DISTRICT else GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	lens.configure(quality, GameState.lens_effects, GameState.motion_blur)
	hud.quality_name = Quality.NAMES[quality]


# ------------------------------------------------------------------ setup

func _setup_environment(district: bool) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.47, 0.55)
	sky_mat.sky_horizon_color = Color(0.86, 0.74, 0.58)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.22, 0.2, 0.17)
	sky_mat.ground_horizon_color = Color(0.78, 0.68, 0.55)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.08
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if OS.has_feature("web") else Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if OS.has_feature("web"):
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.75, 0.79, 0.84)
		env.ambient_light_sky_contribution = 0.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.8, 0.72, 0.62)
	env.fog_density = 0.0018
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.35
	env.volumetric_fog_density = 0.0065
	env.volumetric_fog_albedo = Color(0.92, 0.85, 0.76)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.2
	env.volumetric_fog_ambient_inject = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26, -138, 0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 2.6
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 110.0
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
	if district:
		# Golden hour over the district, like the reference shots.
		sun.rotation_degrees = Vector3(-19, -125, 0)
		sun.light_color = Color(1.0, 0.77, 0.52)
		sun.light_energy = 2.8
		env.fog_density = 0.0007
		env.volumetric_fog_density = 0.0026
		env.fog_aerial_perspective = 0.25
		env.volumetric_fog_length = 120.0


func _setup_input() -> void:
	if InputMap.has_action("move_forward"):
		return  # already set up by an earlier scene
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("crouch", KEY_CTRL)
	_key("crouch", KEY_C)
	_key("grab", KEY_E)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	for i in 7:
		_key("tool_%d" % (i + 1), KEY_1 + i)
	_key("tool_inventory", KEY_TAB)
	_key("toggle_help", KEY_F1)
	_key("toggle_stats", KEY_F3)
	_key("quality", KEY_F4)
	_key("reset_level", KEY_F5)
	_key("bench", KEY_F6)


func _key(action: String, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
