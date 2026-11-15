shader_type canvas_item;
render_mode unshaded;

uniform bool dense = false;

void fragment() {
	float left = 1.0 - smoothstep(0.05, 0.64, UV.x);
	float bottom = smoothstep(0.65, 1.0, UV.y);
	float rim = smoothstep(0.4, 0.9, length(UV - vec2(0.53, 0.43)));
	float alpha = dense ? 0.88 + bottom * 0.09 : clamp(0.08 + left * 0.63 + bottom * 0.72 + rim * 0.12, 0.0, 0.94);
	COLOR = vec4(0.035, 0.052, 0.073, alpha);
}
