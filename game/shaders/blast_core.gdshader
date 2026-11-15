shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D density_tex : filter_linear, repeat_disable;
uniform float progress = 0.0;

void vertex() {
	MODELVIEW_MATRIX = mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		VIEW_MATRIX * MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float stretch = 1.0 - 0.18 * progress;
	vec2 drift = vec2(sin(UV.y * 17.0 + progress * 6.0), cos(UV.x * 16.0 - progress * 5.0)) * 0.055;
	vec2 sample_uv = p * vec2(1.0, stretch) + 0.5 + drift;
	float density = texture(density_tex, sample_uv).a;
	float detail = texture(density_tex, UV + drift * 0.7).r;
	float heat = smoothstep(0.17, 0.82, density + (detail - 0.91) * 2.8 - progress * 0.55);
	vec3 dark = vec3(0.16, 0.107, 0.076);
	vec3 hot = mix(vec3(1.0, 0.26, 0.022), vec3(1.0, 0.83, 0.42), heat * heat);
	ALBEDO = mix(dark, hot, heat * (1.0 - progress * 0.43));
	ALPHA = smoothstep(0.06, 0.70, density) * (1.0 - smoothstep(0.44, 1.0, progress));
}
