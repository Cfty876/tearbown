shader_type spatial;
render_mode cull_back, blend_mix, specular_disabled;

uniform vec3 tint : source_color = vec3(0.57, 0.73, 0.75);

void fragment() {
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(tint * COLOR.rgb, tint, fresnel * 0.55);
	ALPHA = 0.37 + 0.45 * fresnel * fresnel;
	ROUGHNESS = 0.19;
}
