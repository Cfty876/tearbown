shader_type sky;

float noise_cell(vec2 p) {
	vec2 g = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(g, vec2(117.2, 71.9))) * 43581.2);
	float b = fract(sin(dot(g + vec2(1.0, 0.0), vec2(117.2, 71.9))) * 43581.2);
	float c = fract(sin(dot(g + vec2(0.0, 1.0), vec2(117.2, 71.9))) * 43581.2);
	float d = fract(sin(dot(g + vec2(1.0), vec2(117.2, 71.9))) * 43581.2);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	float h = max(EYEDIR.y, 0.0);
	float overhead = smoothstep(0.0, 0.72, h);
	vec3 horizon = vec3(0.27, 0.35, 0.47);
	vec3 zenith = vec3(0.052, 0.096, 0.17);
	vec3 color = mix(horizon, zenith, overhead);
	vec2 p = EYEDIR.xz * vec2(2.8, 5.4) / (0.22 + h);
	float mist = noise_cell(p) * 0.65 + noise_cell(p * 2.1 + 6.7) * 0.25 + noise_cell(p * 4.4) * 0.10;
	float bank = smoothstep(0.31, 0.68, mist) * smoothstep(0.015, 0.24, h);
	color = mix(color, mix(vec3(0.25, 0.31, 0.41), vec3(0.10, 0.16, 0.26), overhead), bank * 0.78);
	color = mix(color, vec3(0.04, 0.066, 0.10), smoothstep(0.0, 0.27, -EYEDIR.y));
	COLOR = color;
}
