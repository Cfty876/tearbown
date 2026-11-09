shader_type spatial;
// River surface: depth-tinted, glossy, procedurally rippled. Fades out against
// the shore using the depth buffer so banks look wet instead of clipped.
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.26, 0.33, 0.26);
uniform vec3 deep_color : source_color = vec3(0.05, 0.10, 0.11);
uniform float depth_scale = 0.9;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 wpos;

float wave(vec2 p, vec2 dir, float freq, float speed) {
	return sin(dot(p, dir) * freq + TIME * speed);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float e = 0.06;
	float h0 = wave(p, vec2(0.8, 0.6), 1.7, 1.1) + 0.6 * wave(p, vec2(-0.3, 0.95), 2.9, 1.7) + 0.3 * wave(p, vec2(0.6, -0.8), 6.1, 2.3);
	float hx = wave(p + vec2(e, 0.0), vec2(0.8, 0.6), 1.7, 1.1) + 0.6 * wave(p + vec2(e, 0.0), vec2(-0.3, 0.95), 2.9, 1.7) + 0.3 * wave(p + vec2(e, 0.0), vec2(0.6, -0.8), 6.1, 2.3);
	float hz = wave(p + vec2(0.0, e), vec2(0.8, 0.6), 1.7, 1.1) + 0.6 * wave(p + vec2(0.0, e), vec2(-0.3, 0.95), 2.9, 1.7) + 0.3 * wave(p + vec2(0.0, e), vec2(0.6, -0.8), 6.1, 2.3);
	vec3 n = normalize(vec3(-(hx - h0) / e * 0.02, 1.0, -(hz - h0) / e * 0.02));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 behind = upos.xyz / upos.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);
	float t = clamp(water_depth * depth_scale, 0.0, 1.0);
	ALBEDO = mix(shallow_color, deep_color, t);
	ALPHA = clamp(0.35 + t * 0.6, 0.0, 0.94) * smoothstep(0.0, 0.12, water_depth);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
