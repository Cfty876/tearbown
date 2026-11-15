shader_type canvas_item;
void fragment() {
	float bar = smoothstep(0.0, 0.009, abs(UV.y - fract(TIME * 0.17)));
	float sync = step(0.985, sin(TIME * 2.9));
	vec2 uv = vec2(clamp(UV.x + (1.0 - bar) * sync * 0.007, 0.0, 1.0), UV.y);
	vec3 frame = texture(TEXTURE, uv).rgb;
	float luminance = dot(frame, vec3(0.213, 0.715, 0.072));
	float line = 0.94 + 0.06 * sin(UV.y * 1300.0);
	COLOR = vec4(mix(frame, luminance * vec3(0.75, 0.97, 0.95), 0.32) * line, 1.0);
}
