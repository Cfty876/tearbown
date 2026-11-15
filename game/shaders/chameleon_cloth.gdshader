shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 fabric_tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D borrowed_patch : source_color, filter_nearest, repeat_disable;
uniform bool has_patch = false;
uniform int motif = 0;
uniform int source_material = 0;
uniform vec4 print_axes = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 print_origin = vec2(0.0);
varying vec2 cloth_m;

void vertex() {
	cloth_m = VERTEX.xy;
}

float grain_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(37.13, 83.17))) * 43758.55);
}

float seam(vec2 p, vec2 cell_size) {
	vec2 edge = abs(fract(p / cell_size) - 0.5);
	return smoothstep(0.43, 0.5, max(edge.x, edge.y));
}

float material_print(vec2 p, int material, int pattern) {
	vec2 cell = floor(p);
	float grain = grain_hash(cell) - 0.5;
	if (material == 4 || pattern == 3) { // Brick: staggered mortar joints.
		float row = floor(p.y);
		return grain * 0.09 - 0.18 * seam(p + vec2(mod(row, 2.0) * 1.5, 0.0), vec2(3.0, 1.0));
	}
	if (material == 2) { // Wood: voxel-grain knots and slat edges.
		vec2 slat = floor(vec2(cell.x * 0.5, cell.y * 0.16));
		return (grain_hash(slat) - 0.5) * 0.15 - 0.08 * step(0.86, fract(p.x * 0.5)) + grain * 0.04;
	}
	if (material == 1) { // Glass: smoky pane grid with stepped glints.
		return 0.07 * step(0.78, fract((cell.x + cell.y) / 9.0)) - seam(p, vec2(7.0, 9.0)) * 0.12;
	}
	if (material == 3) { // Plaster: broad, soft paint patches.
		return (grain_hash(floor(cell / 3.0)) - 0.5) * 0.085 + grain * 0.045;
	}
	if (material == 5) { // Concrete: panel seams or masonry tiles.
		vec2 block = pattern == 5 ? vec2(2.0) : vec2(8.0, 6.0);
		return grain * 0.085 - seam(p, block) * 0.13;
	}
	if (material == 6) { // Metal: rolled sheet ribs or brushed strips.
		float rib = mod(cell.x, 2.0);
		return pattern == 7 ? (rib - 0.5) * 0.19 : (grain_hash(vec2(cell.x, floor(cell.y / 7.0))) - 0.5) * 0.11;
	}
	if (material == 7) { // Steel: dark plates with small rivet heads.
		vec2 rivet = mod(cell, vec2(5.0, 6.0));
		float head = float(rivet.x < 1.0 && rivet.y < 1.0);
		return head * 0.14 + grain * 0.055 - seam(p, vec2(10.0, 12.0)) * 0.09;
	}
	if (material == 8) { // Foliage: overlapping blocky clusters.
		float clump = grain_hash(floor((cell + vec2(mod(floor(cell.y / 2.0), 2.0), 0.0)) / 2.0));
		return (clump - 0.5) * 0.22 + grain * 0.10;
	}
	if (material == 9) { // Soil: small stones and earth flecks.
		return grain * 0.18 + step(0.91, grain_hash(cell + 7.0)) * 0.10 - 0.04;
	}
	if (material == 10) { // Stone: short stepped mineral strata.
		float layer = floor((cell.y + floor(cell.x / 3.0)) / 2.0);
		return (grain_hash(vec2(floor(cell.x / 4.0), layer)) - 0.5) * 0.18 + grain * 0.055;
	}
	if (material == 11) { // Plastic: fine molded squares or fabric ridges.
		return pattern == 7 ? (mod(cell.x, 2.0) - 0.5) * 0.13 : grain * 0.045 - seam(p, vec2(3.0, 4.0)) * 0.065;
	}
	if (material == 12) { // Bedrock: offset slabs with rough edges.
		return grain * 0.13 - seam(p + vec2(mod(floor(cell.y / 4.0), 2.0) * 2.0, 0.0), vec2(4.0)) * 0.10;
	}
	if (material == 13) { // Lit panels: subdued segmented diffuser.
		return 0.05 * mod(cell.y, 2.0) - seam(p, vec2(4.0, 3.0)) * 0.11;
	}
	return grain * 0.065;
}

void fragment() {
	vec2 woven = cloth_m * 63.0;
	float thread = sin(woven.x * 6.283) * sin(woven.y * 6.283);
	float fold = sin(cloth_m.x * 23.0 + UV.y * 2.0);
	float hem = 1.0 - smoothstep(0.0, 0.025, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	vec2 projected = vec2(dot(cloth_m, print_axes.xy), dot(cloth_m, print_axes.zw)) + print_origin;
	vec2 patch_uv = 1.0 - abs(mod(projected * 2.0 + 0.5, 2.0) - 1.0);
	vec3 material_color = fabric_tint.rgb;
	if (has_patch) {
		material_color = mix(material_color, texture(borrowed_patch, patch_uv).rgb, 0.62);
	}
	vec2 p = projected * 10.0;
	float detail_fade = 1.0 - smoothstep(0.52, 1.3, length(fwidth(p)));
	float print_detail = material_print(p, source_material, motif) * detail_fade;
	vec3 dyed_color = material_color * vec3(0.965, 0.94, 0.92);
	ALBEDO = dyed_color * (0.99 + print_detail + thread * 0.015 + fold * 0.025 - hem * 0.12);
	ROUGHNESS = 0.97;
}
