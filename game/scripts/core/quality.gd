class_name Quality
## Graphics presets (F4 cycles them).

enum { LOW, MEDIUM, HIGH, ULTRA }
const NAMES := ["Ноутбук", "Среднее", "Высокое", "Ультра"]
const HEIGHTS := [648.0, 720.0, 864.0, 1080.0]


static func apply(level: int, env: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_enabled = forward_plus and level >= MEDIUM
	env.ssil_enabled = forward_plus and level >= HIGH
	env.ssr_enabled = forward_plus and level >= ULTRA
	env.volumetric_fog_enabled = forward_plus and level >= HIGH
	var web := OS.has_feature("web")
	env.glow_enabled = level >= MEDIUM and not web
	sun.shadow_enabled = not (web and level == LOW and GameState.level != GameState.LEVEL_HIDE)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if level == LOW else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level < ULTRA else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	sun.directional_shadow_max_distance = ([24.0, 34.0, 46.0, 60.0] if web else [38.0, 58.0, 86.0, 120.0])[level]
	sun.light_angular_distance = 0.0 if level <= MEDIUM else 0.6
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 3072, 4096][level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([1, 1, 2, 3][level] as RenderingServer.ShadowQuality)
	vp.use_taa = forward_plus and level >= HIGH
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if vp.use_taa or web else Viewport.SCREEN_SPACE_AA_FXAA
	vp.msaa_3d = Viewport.MSAA_DISABLED
	apply_resolution(level, vp)
	if env.ssao_enabled:
		RenderingServer.environment_set_ssao_quality([0, 1, 2, 3][level] as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 2, 50.0, 300.0)


static func apply_resolution(level: int, vp: Viewport) -> void:
	var height := float((vp as Window).size.y) if vp is Window else vp.get_visible_rect().size.y
	var max_height: float = [360.0, 540.0, 648.0, 720.0][level] if OS.has_feature("web") else HEIGHTS[level]
	vp.scaling_3d_scale = minf(1.0, max_height / maxf(height, 1.0))
