shader_type spatial;
// Single-voxel debris cubes drawn through a MultiMesh; instance color = linear palette color.
render_mode cull_back, diffuse_burley;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
