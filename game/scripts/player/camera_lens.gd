class_name CameraLens
extends CanvasLayer

const OPTICS := preload("res://shaders/camera_lens.gdshader")
const FOCUS_RANGE := 82.0
const SUN_RANGE := 160.0

var world: VoxelWorld
var sun: DirectionalLight3D
var _quad: ColorRect
var _material: ShaderMaterial
var _attributes := CameraAttributesPractical.new()
var _camera: Camera3D
var _last_forward := Vector3.ZERO
var _last_eye := Vector3.ZERO
var _turn := Vector2.ZERO
var _focus := 18.0
var _focus_target := 18.0
var _ray_timer := 0.0
var _sunlight := 0.0
var _sun_target := 0.0
var _sun_uv := Vector2(0.5, 0.5)
var _quality := Quality.LOW
var _lens := true
var _motion := true
var _auto_focus := false
var _sun_rays := false
var _can_dof := true


func _ready() -> void:
	layer = 1
	_can_dof = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_quad = ColorRect.new()
	_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = OPTICS
	_quad.material = _material
	add_child(_quad)


func configure(quality: int, use_lens: bool, use_motion: bool) -> void:
	_quality = quality
	_lens = use_lens and DisplayServer.get_name() != "headless"
	_motion = use_motion and DisplayServer.get_name() != "headless"
	_auto_focus = GameState.autofocus and _can_dof and DisplayServer.get_name() != "headless"
	_sun_rays = GameState.sun_rays and DisplayServer.get_name() != "headless"
	_ray_timer = 0.0
	_last_forward = Vector3.ZERO
	_turn = Vector2.ZERO
	if not _sun_rays:
		_sun_target = 0.0
		_sunlight = 0.0
	_attributes.dof_blur_far_enabled = _auto_focus
	_attributes.dof_blur_amount = [0.025, 0.034, 0.043, 0.05][_quality]
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(
		RenderingServer.DOF_BOKEH_HEXAGON if _quality >= Quality.HIGH else RenderingServer.DOF_BOKEH_BOX)
	RenderingServer.camera_attributes_set_dof_blur_quality(
		RenderingServer.DOF_BLUR_QUALITY_VERY_LOW if _quality <= Quality.MEDIUM else RenderingServer.DOF_BLUR_QUALITY_LOW,
		false)
	_material.set_shader_parameter("edge_px", [2.2, 3.4, 4.1, 5.0][_quality] * GameState.edge_strength if _lens else 0.0)
	_material.set_shader_parameter("extra_taps", _quality >= Quality.HIGH)
	_material.set_shader_parameter("turn_px", Vector2.ZERO)
	_material.set_shader_parameter("sunlight", _sunlight)
	_quad.visible = _lens
	set_process(_lens or _motion or _auto_focus or _sun_rays)
	set_physics_process(_auto_focus or _sun_rays)


func _physics_process(delta: float) -> void:
	_ray_timer -= delta
	if _ray_timer > 0.0 or not is_instance_valid(_camera):
		return
	_ray_timer = 0.16 if _quality <= Quality.MEDIUM else 0.12
	var origin := _camera.global_position
	var facing := -_camera.global_basis.z
	if _auto_focus:
		var right := _camera.global_basis.x * 0.028
		var distances := PackedFloat32Array()
		for offset in [Vector3.ZERO, -right, right]:
			var ray: Vector3 = (facing + offset).normalized()
			var hit := world.raycast(origin, origin + ray * FOCUS_RANGE)
			distances.append(39.0 if hit.is_empty() else origin.distance_to(hit.position))
		distances.sort()
		_focus_target = clampf(distances[1], 4.0, 46.0)
	if not _sun_rays:
		return
	var light_dir := sun.global_basis.z.normalized()
	_sun_target = 0.0
	if facing.dot(light_dir) <= 0.02:
		return
	var target := origin + light_dir * SUN_RANGE
	var viewport_size := get_viewport().get_visible_rect().size
	var uv := _camera.unproject_position(target) / viewport_size
	if uv.x < -0.19 or uv.x > 1.19 or uv.y < -0.19 or uv.y > 1.19:
		return
	var visible := float(world.raycast(origin, target).is_empty())
	if _quality >= Quality.MEDIUM:
		var side := _camera.global_basis.x * 0.38
		for offset in [-side, side]:
			visible += float(world.raycast(origin + offset, target + offset).is_empty())
		visible /= 3.0
	_sun_target = visible * (0.21 if _quality <= Quality.MEDIUM else 0.29)


func _process(delta: float) -> void:
	var active := get_viewport().get_camera_3d()
	if not is_instance_valid(active):
		_quad.hide()
		return
	if active != _camera:
		if is_instance_valid(_camera) and _camera.attributes == _attributes:
			_camera.attributes = null
		_camera = active
		_camera.attributes = _attributes
		_last_forward = Vector3.ZERO
		_ray_timer = 0.0
	var basis := _camera.global_basis
	var forward := -basis.z
	var eye := _camera.global_position
	var goal := Vector2.ZERO
	if _motion and _last_forward != Vector3.ZERO and eye.distance_squared_to(_last_eye) < 12.0:
		var local := basis.transposed() * _last_forward
		var direction := Vector2(local.x, -local.y)
		var angle := atan2(direction.length(), -local.z)
		if angle < 0.65:
			var rate := angle / maxf(delta, 0.003)
			var radius: float = [5.0, 6.5, 8.0, 9.5][_quality] * GameState.motion_strength
			goal = direction.normalized() * radius * smoothstep(0.80, 5.7, rate)
	_last_forward = forward
	_last_eye = eye
	_turn = _turn.lerp(goal, 1.0 - exp((-25.0 if goal.length_squared() > _turn.length_squared() else -14.0) * delta))
	if _auto_focus:
		var speed := 4.6 if _focus_target < _focus else 2.6
		_focus = lerpf(_focus, _focus_target, 1.0 - exp(-speed * delta))
		_attributes.dof_blur_far_distance = _focus + maxf(2.6, _focus * 0.2)
		_attributes.dof_blur_far_transition = clampf(9.0 + _focus * 0.72, 12.0, 42.0)
	if _sun_rays:
		var sun_world := eye + sun.global_basis.z * SUN_RANGE
		var facing_sun := not _camera.is_position_behind(sun_world)
		if facing_sun:
			_sun_uv = _camera.unproject_position(sun_world) / get_viewport().get_visible_rect().size
		_sunlight = lerpf(_sunlight, _sun_target if facing_sun else 0.0, 1.0 - exp(-7.0 * delta))
		_material.set_shader_parameter("sun_uv", _sun_uv)
		_material.set_shader_parameter("sunlight", _sunlight)
	_material.set_shader_parameter("turn_px", _turn)
	_quad.visible = _lens or _sunlight > 0.004 or _turn.length_squared() > 0.09
