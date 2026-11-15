shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform float progress = 0.0;

void fragment() {
	vec2 pos = UV * 2.0 - 1.0;
	float radius = length(pos);
	float front = mix(0.28, 0.88, progress);
	float falloff = max(0.0, 1.0 - progress);
	float ridge = exp(-pow((radius - front) * 35.0, 2.0));
	float dust = exp(-pow((radius - front + 0.07) * 11.0, 2.0));
	float break_up = 0.62 + 0.21 * sin(atan(pos.y, pos.x + 0.0001) * 31.0 + radius * 9.0);
	ALBEDO = mix(vec3(0.46, 0.35, 0.25), vec3(0.92, 0.69, 0.43), ridge);
	ALPHA = (ridge * 0.35 + dust * 0.26) * falloff * falloff * break_up;
}
