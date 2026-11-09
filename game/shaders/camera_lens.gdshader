shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 turn_px = vec2(0.0);
uniform float edge_px = 0.0;
uniform bool extra_taps = false;
uniform vec2 sun_uv = vec2(0.5);
uniform float sunlight = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 off_center = 2.0 * uv - 1.0;
	float edge = smoothstep(0.55, 1.18, length(off_center * vec2(0.86, 0.91)));
	vec2 step_uv = (turn_px * mix(0.36, 1.0, edge) + off_center * edge * edge_px) * SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	if (dot(step_uv, step_uv) > 0.00000008) {
		vec3 sides = textureLod(screen_tex, uv - step_uv, 0.0).rgb;
		sides += textureLod(screen_tex, uv + step_uv, 0.0).rgb;
		if (extra_taps) {
			vec3 inner = textureLod(screen_tex, uv - step_uv * 0.48, 0.0).rgb;
			inner += textureLod(screen_tex, uv + step_uv * 0.48, 0.0).rgb;
			c = c * 0.42 + inner * 0.19 + sides * 0.10;
		} else {
			c = c * 0.58 + sides * 0.21;
		}
	}
	if (sunlight > 0.003) {
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 from_sun = (uv - sun_uv) * vec2(aspect, 1.0);
		float d = length(from_sun);
		float angle = atan(from_sun.y, from_sun.x + 0.00001);
		float rays = pow(0.5 + 0.5 * cos(12.0 * angle + 0.62 * sin(5.0 * angle)), 3.0);
		float veil = exp(-7.0 * d) * (0.42 + 0.31 * rays) + 0.36 * exp(-38.0 * d);
		c += vec3(1.0, 0.74, 0.42) * sunlight * veil;
	}
	COLOR = vec4(c * (1.0 - 0.014 * edge * min(edge_px, 3.0)), 1.0);
}
