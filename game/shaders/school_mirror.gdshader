shader_type spatial;
render_mode cull_disabled, shadows_disabled;
void fragment() {
	bool hall = CAMERA_POSITION_WORLD.x > 16.85;
	ALBEDO = hall ? vec3(0.26, 0.35, 0.41) : vec3(0.49, 0.70, 0.77);
	ROUGHNESS = hall ? 0.12 : 0.25;
	METALLIC = hall ? 0.87 : 0.10;
	ALPHA = hall ? 0.99 : 0.13;
}
