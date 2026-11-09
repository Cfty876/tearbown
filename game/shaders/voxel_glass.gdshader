shader_type spatial;
// Glass voxels: clearly readable as glass (tint, dust, smudges, strong fresnel
// reflection) so windows and storefronts never feel like invisible walls.
render_mode cull_back, blend_mix, depth_draw_opaque, specular_schlick_ggx;

uniform float voxel_size = 0.1;
uniform float opacity = 0.42;
uniform vec3 tint : source_color = vec3(0.55, 0.72, 0.74);

varying vec3 obj_pos;
varying vec3 obj_nrm;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 vp = obj_pos / voxel_size;
	// Dust collects towards the bottom of each pane, plus blotchy smudges.
	float dust = noise3(vp * 0.35) * 0.6 + noise3(vp * 1.7) * 0.4;
	dust = smoothstep(0.45, 0.95, dust);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = mix(tint * COLOR.rgb * 0.7, vec3(0.62, 0.6, 0.55), dust * 0.6);
	ALPHA = clamp(opacity + fres * 0.45 + dust * 0.22, 0.0, 0.95);
	ROUGHNESS = 0.03 + dust * 0.45;
	METALLIC = 0.0;
	SPECULAR = 1.0;
}
