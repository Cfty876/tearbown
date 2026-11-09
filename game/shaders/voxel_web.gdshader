shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform float voxel_size = 0.1;
varying vec3 voxel_position;
varying vec3 voxel_normal;
varying flat vec2 material_pattern;

void vertex() {
	voxel_position = VERTEX / voxel_size;
	voxel_normal = NORMAL;
	material_pattern = UV;
}

void fragment() {
	vec3 axis = abs(voxel_normal);
	vec3 cell = floor(voxel_position - voxel_normal * 0.5);
	vec3 subcell = fract(voxel_position);
	vec3 borders = min(subcell, 1.0 - subcell);
	float edge = axis.x > 0.5 ? min(borders.y, borders.z) :
		(axis.y > 0.5 ? min(borders.x, borders.z) : min(borders.x, borders.y));
	float detail = 1.0 - smoothstep(0.25, 0.8, length(fwidth(voxel_position)));
	if (abs(material_pattern.y - 3.0) < 0.5) {
		float row = axis.y > 0.5 ? cell.z : cell.y;
		float along = axis.x > 0.5 ? cell.z : cell.x;
		cell = vec3(floor((along + mod(row, 2.0) * 1.5) / 3.0), row, 0.0);
	}
	vec3 noise = fract(cell * 0.1031);
	noise += dot(noise, noise.zyx + 31.32);
	float grain = fract((noise.x + noise.y) * noise.z) - 0.5;
	float shade = 1.0 + detail * (grain * 0.19 - 0.14 * (1.0 - smoothstep(0.0, 0.16, edge)));
	ALBEDO = COLOR.rgb * shade * mix(0.50, 1.0, COLOR.a);
	ROUGHNESS = 0.86;
	EMISSION = COLOR.rgb * (4.0 * step(12.5, material_pattern.x));
}
