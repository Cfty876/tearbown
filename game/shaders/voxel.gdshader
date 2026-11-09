shader_type spatial;
// Opaque voxel surfaces from VoxelVolume.build_mesh().
// COLOR.rgb = linear palette color, COLOR.a = baked vertex AO,
// UV.x = material id, UV.y = color pattern id (see VoxMat.P_*).
// Per-voxel color variation (bricks, planks, noise) is reconstructed here from the
// object-space voxel coordinate, so the mesher can merge whole walls into big quads
// while every voxel still gets its own shade and a soft voxel grid.
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float voxel_size = 0.1;
uniform float edge_darken = 0.16;
uniform float ao_strength = 0.62;

varying vec3 obj_pos;
varying vec3 obj_nrm;
varying flat vec2 mat_pat;

// roughness, metallic, specular, emission per material id (see VoxMat).
const vec4 MAT[14] = vec4[](
	vec4(0.9, 0.0, 0.5, 0.0),   // 0 none
	vec4(0.05, 0.0, 0.8, 0.0),  // 1 glass
	vec4(0.85, 0.0, 0.3, 0.0),  // 2 wood
	vec4(0.92, 0.0, 0.3, 0.0),  // 3 plaster
	vec4(0.88, 0.0, 0.35, 0.0), // 4 brick
	vec4(0.9, 0.0, 0.35, 0.0),  // 5 concrete
	vec4(0.45, 0.6, 0.5, 0.0),  // 6 metal
	vec4(0.35, 0.8, 0.5, 0.0),  // 7 hard metal
	vec4(0.8, 0.0, 0.35, 0.0),  // 8 foliage
	vec4(0.97, 0.0, 0.25, 0.0), // 9 dirt
	vec4(0.85, 0.0, 0.35, 0.0), // 10 rock
	vec4(0.45, 0.0, 0.5, 0.0),  // 11 plastic
	vec4(0.95, 0.0, 0.3, 0.0),  // 12 unbreakable
	vec4(0.3, 0.0, 0.5, 4.0)    // 13 emissive
);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	mat_pat = UV;
}

// Signed brightness offset for the voxel `cell` on a face with abs normal `an`.
float pattern_shade(int pat, vec3 cell, vec3 an) {
	float fine = hash13(cell) - 0.5;
	bool top = an.y > 0.5;
	float hz = an.x > 0.5 ? cell.z : cell.x;    // horizontal in-plane axis of a side face
	float depth = an.x > 0.5 ? cell.x : cell.z; // axis through the wall
	if (pat == 0) {
		return fine * 0.11;
	} else if (pat == 1) {
		return fine * 0.2;
	} else if (pat == 2) {
		return fine * 0.32;
	} else if (pat == 3) {
		// Running-bond bricks, 3 voxels long, offset every other course.
		float row = top ? cell.z : cell.y;
		float along = top ? cell.x : hz;
		float b = floor((along + mod(row, 2.0) * 1.5) / 3.0);
		float brick = hash13(vec3(b, row, top ? cell.y : depth) + 17.0) - 0.5;
		return brick * 0.32 + fine * 0.05;
	} else if (pat == 4) {
		// Boards 2 voxels wide: vertical on walls, along x on floors and tops.
		float plank = top ? floor(cell.z / 2.0) : floor(hz / 2.0);
		float run = top ? cell.x : cell.y;
		float seg = floor((run + floor(hash13(vec3(plank, 3.0, depth)) * 23.0)) / 26.0);
		float board = hash13(vec3(plank, seg, top ? cell.y : depth) + 5.0) - 0.5;
		float grain = hash13(vec3(plank, run, 9.0)) - 0.5;
		return board * 0.26 + grain * 0.05;
	} else if (pat == 5) {
		vec3 t = floor(cell / 2.0);
		return (hash13(t + 3.0) - 0.5) * 0.18 + fine * 0.04;
	} else if (pat == 6) {
		return fine * 0.03;
	} else {
		// Corrugated sheet: alternating light and dark vertical ribs.
		float rib = top ? 0.0 : (mod(hz, 2.0) < 1.0 ? 0.07 : -0.07);
		return rib + fine * 0.05;
	}
}

void fragment() {
	vec3 vp = obj_pos / voxel_size;
	vec3 cell = floor(vp - obj_nrm * 0.5);
	vec3 an = abs(obj_nrm);
	int pat = int(mat_pat.y + 0.5);
	// Distance to the voxel border along the two in-plane axes.
	vec3 f = fract(vp);
	vec3 e = min(f, 1.0 - f);
	float edge_d = an.x > 0.5 ? min(e.y, e.z) : (an.y > 0.5 ? min(e.x, e.z) : min(e.x, e.y));
	// Fade the grid out when voxels shrink below a few pixels to avoid moire.
	float px = max(length(fwidth(vp)), 1e-4);
	float detail = 1.0 - smoothstep(0.36, 0.88, px);
	float shade = 1.0;
	if (detail > 0.0) {
		shade += pattern_shade(pat, cell, an) * detail;
	}
	vec3 albedo = COLOR.rgb * shade;
	float grid_fade = 1.0 - smoothstep(0.12, 0.45, px);
	float edge = 1.0 - edge_darken * grid_fade * (1.0 - smoothstep(0.0, max(0.09, px * 1.5), edge_d));

	float ao = COLOR.a;
	ao = mix(1.0 - ao_strength, 1.0, ao * ao * (3.0 - 2.0 * ao));

	int m = clamp(int(mat_pat.x + 0.5), 0, 13);
	vec4 props = MAT[m];
	float h = detail > 0.0 ? (hash13(cell + 41.0) - 0.5) * detail : 0.0;
	ALBEDO = albedo * edge * mix(1.0, ao, 0.35);
	AO = ao;
	AO_LIGHT_AFFECT = 0.45;
	ROUGHNESS = clamp(props.x + h * 0.12, 0.02, 1.0);
	METALLIC = props.y;
	SPECULAR = props.z;
	EMISSION = albedo * props.w;
}
