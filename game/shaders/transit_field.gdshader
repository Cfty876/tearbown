shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float phase = 0.0;

void fragment() {
	vec2 uv = UV;
	float envelope = smoothstep(0.0, 0.1, uv.x) * smoothstep(0.0, 0.1, 1.0 - uv.x)
		* smoothstep(0.0, 0.13, uv.y) * smoothstep(0.0, 0.08, 1.0 - uv.y);
	float ribbon = sin(uv.x * 13.0 + TIME * 2.2 + phase) * 0.018;
	float beam = exp(-abs(uv.y - fract(TIME * 0.42 + phase) - ribbon) * 48.0);
	float threads = pow(0.5 + 0.5 * sin(uv.x * 64.0 + uv.y * 11.0 - TIME * 1.4), 7.0);
	float border = exp(-min(uv.x, 1.0 - uv.x) * 13.0);
	ALBEDO = tint.rgb;
	ALPHA = envelope * (0.04 + threads * 0.12 + beam * 0.54 + border * 0.40);
}
