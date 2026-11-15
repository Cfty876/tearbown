shader_type spatial;
render_mode cull_back, shadows_disabled;
varying float eye_distance;
void vertex() {
	eye_distance = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz + vec3(0.0, 0.45, 0.0));
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	ALPHA = mix(0.23, 1.0, smoothstep(0.60, 1.07, eye_distance));
}
