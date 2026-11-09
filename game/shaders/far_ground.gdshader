shader_type spatial;
// Ground outside the destructible map: flat plane shaded like voxel grass
// (world-space 10 cm cells with per-cell tint) so the border is seamless.
render_mode cull_disabled, diffuse_burley;

uniform vec3 grass_color : source_color = vec3(0.31, 0.44, 0.17);
uniform vec3 dirt_color : source_color = vec3(0.40, 0.31, 0.21);
uniform float voxel_size = 0.1;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 vp = wpos.xz / voxel_size;
	vec2 cell = floor(vp);
	float h = hash12(cell) - 0.5;
	float patch = hash12(floor(cell / 37.0) + 11.0);
	vec3 c = mix(grass_color, dirt_color, smoothstep(0.75, 0.95, patch) * 0.6);
	c *= 1.0 + h * 0.32;
	vec2 e = min(fract(vp), 1.0 - fract(vp));
	float px = max(length(fwidth(vp)), 1e-4);
	float grid = (1.0 - smoothstep(0.0, max(0.09, px * 1.5), min(e.x, e.y))) * (1.0 - smoothstep(0.12, 0.45, px));
	ALBEDO = c * (1.0 - 0.16 * grid);
	ROUGHNESS = 0.97;
	SPECULAR = 0.25;
}
