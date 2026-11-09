#include "voxel_volume.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

namespace {

inline uint32_t hash3(int x, int y, int z, uint32_t s) {
	uint32_t h = s * 0x9E3779B1u ^ (uint32_t)x * 0x85EBCA77u ^ (uint32_t)y * 0xC2B2AE3Du ^ (uint32_t)z * 0x27D4EB2Fu;
	h ^= h >> 15;
	h *= 0x2C1B3C6Du;
	h ^= h >> 12;
	h *= 0x297A2D39u;
	h ^= h >> 15;
	return h;
}

inline float hashf(int x, int y, int z, uint32_t s) {
	return (hash3(x, y, z, s) & 0xFFFFFF) / 16777216.0f;
}

template <typename T, typename P>
P to_packed(const std::vector<T> &v) {
	P out;
	out.resize((int64_t)v.size());
	if (!v.empty()) {
		memcpy(out.ptrw(), v.data(), v.size() * sizeof(T));
	}
	return out;
}

// Island search scratch (see split_islands).
std::vector<uint32_t> g_stamps;
uint32_t g_stamp_gen = 0;

} // namespace

// ---------------------------------------------------------------- VoxelPalette

VoxelPalette::VoxelPalette() {
	for (int i = 0; i < 256; i++) {
		linear[i] = Color(1, 0, 1);
		srgb[i] = Color(1, 0, 1);
	}
	for (int m = 0; m < MAT_COUNT; m++) {
		strength[m] = 1.0f;
		density[m] = 1000.0f;
	}
}

void VoxelPalette::set_entry(int p_index, const Color &p_srgb, int p_material, int p_pattern) {
	ERR_FAIL_INDEX(p_index, 256);
	ERR_FAIL_INDEX(p_material, MAT_COUNT);
	srgb[p_index] = p_srgb;
	linear[p_index] = p_srgb.srgb_to_linear();
	material[p_index] = (uint8_t)p_material;
	pattern[p_index] = (uint8_t)p_pattern;
}

int VoxelPalette::get_pattern(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, 256, 0);
	return pattern[p_index];
}

Color VoxelPalette::get_color(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, 256, Color());
	return srgb[p_index];
}

int VoxelPalette::get_material(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, 256, 0);
	return material[p_index];
}

void VoxelPalette::set_material_props(int p_material, float p_strength, float p_density, int p_flags) {
	ERR_FAIL_INDEX(p_material, MAT_COUNT);
	strength[p_material] = p_strength;
	density[p_material] = p_density;
	flags[p_material] = (uint8_t)p_flags;
}

float VoxelPalette::get_strength(int p_material) const {
	ERR_FAIL_INDEX_V(p_material, MAT_COUNT, 0.0f);
	return strength[p_material];
}

float VoxelPalette::get_density(int p_material) const {
	ERR_FAIL_INDEX_V(p_material, MAT_COUNT, 0.0f);
	return density[p_material];
}

int VoxelPalette::get_flags(int p_material) const {
	ERR_FAIL_INDEX_V(p_material, MAT_COUNT, 0);
	return flags[p_material];
}

void VoxelPalette::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_entry", "index", "color", "material", "pattern"), &VoxelPalette::set_entry, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_pattern", "index"), &VoxelPalette::get_pattern);
	ClassDB::bind_method(D_METHOD("get_color", "index"), &VoxelPalette::get_color);
	ClassDB::bind_method(D_METHOD("get_material", "index"), &VoxelPalette::get_material);
	ClassDB::bind_method(D_METHOD("set_material_props", "material", "strength", "density", "flags"), &VoxelPalette::set_material_props);
	ClassDB::bind_method(D_METHOD("get_strength", "material"), &VoxelPalette::get_strength);
	ClassDB::bind_method(D_METHOD("get_density", "material"), &VoxelPalette::get_density);
	ClassDB::bind_method(D_METHOD("get_flags", "material"), &VoxelPalette::get_flags);
}

// ---------------------------------------------------------------- VoxelVolume basics

void VoxelVolume::setup(const Vector3i &p_size) {
	sx = MAX(p_size.x, 1);
	sy = MAX(p_size.y, 1);
	sz = MAX(p_size.z, 1);
	data.assign((size_t)sx * sy * sz, 0);
	solid_count = 0;
}

void VoxelVolume::set_voxel(const Vector3i &p, int p_value) {
	if (!inside(p.x, p.y, p.z)) {
		return;
	}
	write(idx(p.x, p.y, p.z), (uint8_t)p_value);
}

PackedByteArray VoxelVolume::get_data() const {
	return to_packed<uint8_t, PackedByteArray>(data);
}

void VoxelVolume::set_data(const PackedByteArray &p_data) {
	ERR_FAIL_COND_MSG(p_data.size() != (int64_t)data.size(), "VoxelVolume.set_data: size mismatch");
	memcpy(data.data(), p_data.ptr(), data.size());
	solid_count = 0;
	for (uint8_t v : data) {
		solid_count += v != 0;
	}
}

void VoxelVolume::clip_box(Vector3i &r_from, Vector3i &r_to) const {
	r_from.x = MAX(r_from.x, 0);
	r_from.y = MAX(r_from.y, 0);
	r_from.z = MAX(r_from.z, 0);
	r_to.x = MIN(r_to.x, sx);
	r_to.y = MIN(r_to.y, sy);
	r_to.z = MIN(r_to.z, sz);
}

// ---------------------------------------------------------------- Fills

void VoxelVolume::fill_box(const Vector3i &p_from, const Vector3i &p_to, int p_value) {
	Vector3i a = p_from, b = p_to;
	clip_box(a, b);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				write(idx(x, y, z), (uint8_t)p_value);
			}
		}
	}
}

void VoxelVolume::fill_box_noise(const Vector3i &p_from, const Vector3i &p_to, const PackedByteArray &p_values, int p_seed) {
	const int n = (int)p_values.size();
	ERR_FAIL_COND(n == 0);
	Vector3i a = p_from, b = p_to;
	clip_box(a, b);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				write(idx(x, y, z), p_values[hash3(x, y, z, p_seed) % n]);
			}
		}
	}
}

void VoxelVolume::fill_bricks(const Vector3i &p_from, const Vector3i &p_to, int p_long_axis, int p_brick_len, int p_brick_h, const PackedByteArray &p_values, int p_mortar, int p_seed) {
	const int n = (int)p_values.size();
	ERR_FAIL_COND(n == 0);
	const int bl = MAX(p_brick_len, 1);
	const int bh = MAX(p_brick_h, 1);
	Vector3i a = p_from, b = p_to;
	clip_box(a, b);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			const int row = (y - p_from.y) / bh;
			const int row_off = (row & 1) * (bl / 2 + (bl & 1));
			for (int x = a.x; x < b.x; x++) {
				const int along = (p_long_axis == 0 ? x - p_from.x : z - p_from.z) + row_off;
				const int depth = p_long_axis == 0 ? z : x;
				const int brick = along / bl;
				uint8_t v = p_values[hash3(brick, row, depth, p_seed) % n];
				if (p_mortar > 0) {
					const bool joint_v = (along % bl) == bl - 1;
					const bool joint_h = ((y - p_from.y) % bh) == bh - 1;
					if ((joint_v && bl > 2) || (joint_h && bh > 2)) {
						v = (uint8_t)p_mortar;
					}
				}
				write(idx(x, y, z), v);
			}
		}
	}
}

void VoxelVolume::fill_planks(const Vector3i &p_from, const Vector3i &p_to, int p_run_axis, int p_stack_axis, int p_width, const PackedByteArray &p_values, int p_seed) {
	const int n = (int)p_values.size();
	ERR_FAIL_COND(n == 0);
	ERR_FAIL_INDEX(p_run_axis, 3);
	ERR_FAIL_INDEX(p_stack_axis, 3);
	const int w = MAX(p_width, 1);
	Vector3i a = p_from, b = p_to;
	clip_box(a, b);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const int c[3] = { x, y, z };
				const int f[3] = { p_from.x, p_from.y, p_from.z };
				const int plank = (c[p_stack_axis] - f[p_stack_axis]) / w;
				const int shift = (int)(hash3(plank, 7, 3, p_seed) % 23u);
				const int seg = (c[p_run_axis] - f[p_run_axis] + shift) / 26;
				write(idx(x, y, z), p_values[hash3(plank, seg, 11, p_seed) % n]);
			}
		}
	}
}

void VoxelVolume::fill_sphere(const Vector3 &p_center, float p_radius, int p_value) {
	Vector3i a((int)std::floor(p_center.x - p_radius), (int)std::floor(p_center.y - p_radius), (int)std::floor(p_center.z - p_radius));
	Vector3i b((int)std::ceil(p_center.x + p_radius) + 1, (int)std::ceil(p_center.y + p_radius) + 1, (int)std::ceil(p_center.z + p_radius) + 1);
	clip_box(a, b);
	const float r2 = p_radius * p_radius;
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const Vector3 d = Vector3(x + 0.5f, y + 0.5f, z + 0.5f) - p_center;
				if (d.length_squared() <= r2) {
					write(idx(x, y, z), (uint8_t)p_value);
				}
			}
		}
	}
}

void VoxelVolume::fill_ellipsoid_noise(const Vector3 &p_center, const Vector3 &p_radii, const PackedByteArray &p_values, float p_fill_chance, float p_roughness, int p_seed) {
	const int n = (int)p_values.size();
	ERR_FAIL_COND(n == 0);
	Vector3i a((int)std::floor(p_center.x - p_radii.x), (int)std::floor(p_center.y - p_radii.y), (int)std::floor(p_center.z - p_radii.z));
	Vector3i b((int)std::ceil(p_center.x + p_radii.x) + 1, (int)std::ceil(p_center.y + p_radii.y) + 1, (int)std::ceil(p_center.z + p_radii.z) + 1);
	clip_box(a, b);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const Vector3 d = (Vector3(x + 0.5f, y + 0.5f, z + 0.5f) - p_center) / p_radii;
				// Coarse 3-voxel noise cells give lumpy, leafy silhouettes.
				const float coarse = hashf(x / 3, y / 3, z / 3, p_seed + 17);
				const float limit = 1.0f - p_roughness * coarse;
				if (d.length() > limit) {
					continue;
				}
				// Holes only near the surface: interior gaps would add hidden faces.
				if (d.length() > limit * 0.8f && hashf(x, y, z, p_seed) > p_fill_chance) {
					continue;
				}
				write(idx(x, y, z), p_values[hash3(x, y, z, p_seed + 5) % n]);
			}
		}
	}
}

void VoxelVolume::fill_cylinder(const Vector3 &p_base, float p_radius, int p_height, int p_axis, int p_value) {
	ERR_FAIL_INDEX(p_axis, 3);
	const int u = (p_axis + 1) % 3;
	const int v = (p_axis + 2) % 3;
	const float base[3] = { p_base.x, p_base.y, p_base.z };
	const float r2 = p_radius * p_radius;
	const int r = (int)std::ceil(p_radius) + 1;
	const int start = (int)std::floor(base[p_axis]);
	for (int h = 0; h < p_height; h++) {
		for (int j = -r; j <= r; j++) {
			for (int i = -r; i <= r; i++) {
				int c[3];
				c[p_axis] = start + h;
				c[u] = (int)std::floor(base[u]) + i;
				c[v] = (int)std::floor(base[v]) + j;
				const float du = c[u] + 0.5f - base[u];
				const float dv = c[v] + 0.5f - base[v];
				if (du * du + dv * dv <= r2 && inside(c[0], c[1], c[2])) {
					write(idx(c[0], c[1], c[2]), (uint8_t)p_value);
				}
			}
		}
	}
}

void VoxelVolume::fill_columns(const Vector3i &p_from, const Vector3i &p_size_xz, const PackedFloat32Array &p_heights, float p_base, float p_scale, const PackedByteArray &p_layers, int p_seed) {
	const int nx = p_size_xz.x;
	const int nz = p_size_xz.z;
	const int nl = (int)p_layers.size();
	ERR_FAIL_COND(nl == 0);
	ERR_FAIL_COND(p_heights.size() < (int64_t)nx * nz);
	for (int lz = 0; lz < nz; lz++) {
		for (int lx = 0; lx < nx; lx++) {
			const int x = p_from.x + lx;
			const int z = p_from.z + lz;
			const int h = (int)std::floor(p_base + p_heights[lx + lz * nx] * p_scale);
			const int top = p_from.y + h - 1;
			for (int y = MAX(p_from.y, 0); y <= top && y < sy; y++) {
				if (!inside(x, y, z)) {
					continue;
				}
				int depth = top - y;
				// Ragged layer borders so strata do not look ruler-straight.
				if (p_seed != 0 && hashf(x, y, z, p_seed) < 0.3f) {
					depth += 1;
				}
				write(idx(x, y, z), p_layers[MIN(depth, nl - 1)]);
			}
		}
	}
}

void VoxelVolume::replace(const Vector3i &p_from, const Vector3i &p_to, int p_old, int p_new) {
	Vector3i a = p_from, b = p_to;
	clip_box(a, b);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const int i = idx(x, y, z);
				if (data[i] == p_old) {
					write(i, (uint8_t)p_new);
				}
			}
		}
	}
}

void VoxelVolume::copy_from(const Ref<VoxelVolume> &p_src, const Vector3i &p_offset, bool p_skip_empty) {
	ERR_FAIL_COND(p_src.is_null());
	const VoxelVolume *s = p_src.ptr();
	for (int z = 0; z < s->sz; z++) {
		for (int y = 0; y < s->sy; y++) {
			for (int x = 0; x < s->sx; x++) {
				const uint8_t v = s->data[s->idx(x, y, z)];
				if (p_skip_empty && v == 0) {
					continue;
				}
				const int dx = x + p_offset.x, dy = y + p_offset.y, dz = z + p_offset.z;
				if (inside(dx, dy, dz)) {
					write(idx(dx, dy, dz), v);
				}
			}
		}
	}
}

// ---------------------------------------------------------------- Destruction

// Removes voxels inside a jittered sphere (all units are voxels). Each material
// resists by strength: power >= strength removes in the full radius, power down
// to half the strength chips a smaller core, anything weaker is untouched.
Dictionary VoxelVolume::carve_sphere(const Vector3 &p_center, float p_radius, float p_power, float p_jitter, float p_debris_chance, int p_max_debris, int p_seed) {
	Dictionary res;
	ERR_FAIL_COND_V(palette.is_null(), res);
	const VoxelPalette *pal = palette.ptr();

	float radius_for_mat[MAT_COUNT];
	for (int m = 0; m < MAT_COUNT; m++) {
		const float st = MAX(pal->strength[m], 0.0001f);
		const float q = p_power / st;
		float f = 0.0f;
		if (q >= 1.0f) {
			f = 1.0f;
		} else if (q >= 0.5f) {
			f = (q - 0.5f) * 2.0f * 0.75f;
		}
		radius_for_mat[m] = p_radius * f;
	}

	const float reach = p_radius * (1.0f + p_jitter);
	Vector3i a((int)std::floor(p_center.x - reach), (int)std::floor(p_center.y - reach), (int)std::floor(p_center.z - reach));
	Vector3i b((int)std::ceil(p_center.x + reach) + 1, (int)std::ceil(p_center.y + reach) + 1, (int)std::ceil(p_center.z + reach) + 1);
	clip_box(a, b);

	std::vector<Vector3> debris_pos;
	std::vector<uint8_t> debris_idx;
	int count = 0;
	Vector3i dmin(INT32_MAX, INT32_MAX, INT32_MAX), dmax(-1, -1, -1);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const int i = idx(x, y, z);
				const uint8_t v = data[i];
				if (!v) {
					continue;
				}
				const float re = radius_for_mat[pal->material[v]];
				if (re <= 0.0f) {
					continue;
				}
				float dist = (Vector3(x + 0.5f, y + 0.5f, z + 0.5f) - p_center).length();
				dist *= 1.0f + (hashf(x, y, z, p_seed) - 0.5f) * p_jitter;
				if (dist > re) {
					continue;
				}
				write(i, 0);
				count++;
				dmin = Vector3i(MIN(dmin.x, x), MIN(dmin.y, y), MIN(dmin.z, z));
				dmax = Vector3i(MAX(dmax.x, x), MAX(dmax.y, y), MAX(dmax.z, z));
				if ((int)debris_pos.size() < p_max_debris && hashf(x, y, z, p_seed + 99) < p_debris_chance) {
					debris_pos.push_back(Vector3(x + 0.5f, y + 0.5f, z + 0.5f));
					debris_idx.push_back(v);
				}
			}
		}
	}
	res["count"] = count;
	res["min"] = dmin;
	res["max"] = dmax;
	res["debris_pos"] = to_packed<Vector3, PackedVector3Array>(debris_pos);
	res["debris_idx"] = to_packed<uint8_t, PackedByteArray>(debris_idx);
	return res;
}

// Palette remap inside a sphere (spray paint, scorch marks). Chance fades with distance.
Dictionary VoxelVolume::paint_sphere(const Vector3 &p_center, float p_radius, const PackedByteArray &p_remap, float p_chance, int p_seed) {
	Dictionary res;
	ERR_FAIL_COND_V(p_remap.size() != 256, res);
	Vector3i a((int)std::floor(p_center.x - p_radius), (int)std::floor(p_center.y - p_radius), (int)std::floor(p_center.z - p_radius));
	Vector3i b((int)std::ceil(p_center.x + p_radius) + 1, (int)std::ceil(p_center.y + p_radius) + 1, (int)std::ceil(p_center.z + p_radius) + 1);
	clip_box(a, b);
	const uint8_t *remap = p_remap.ptr();
	int count = 0;
	Vector3i dmin(INT32_MAX, INT32_MAX, INT32_MAX), dmax(-1, -1, -1);
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const int i = idx(x, y, z);
				const uint8_t v = data[i];
				if (!v || remap[v] == v) {
					continue;
				}
				const float dist = (Vector3(x + 0.5f, y + 0.5f, z + 0.5f) - p_center).length();
				if (dist > p_radius) {
					continue;
				}
				const float chance = p_chance * (1.0f - 0.7f * dist / MAX(p_radius, 0.001f));
				if (hashf(x, y, z, p_seed) > chance) {
					continue;
				}
				write(i, remap[v]);
				count++;
				dmin = Vector3i(MIN(dmin.x, x), MIN(dmin.y, y), MIN(dmin.z, z));
				dmax = Vector3i(MAX(dmax.x, x), MAX(dmax.y, y), MAX(dmax.z, z));
			}
		}
	}
	res["count"] = count;
	res["min"] = dmin;
	res["max"] = dmax;
	return res;
}

Ref<VoxelVolume> VoxelVolume::extract_indices(const std::vector<int> &p_indices, Vector3i &r_offset) {
	Vector3i mn(INT32_MAX, INT32_MAX, INT32_MAX), mx(-1, -1, -1);
	for (int i : p_indices) {
		const int x = i % sx;
		const int t = i / sx;
		const int y = t % sy;
		const int z = t / sy;
		mn = Vector3i(MIN(mn.x, x), MIN(mn.y, y), MIN(mn.z, z));
		mx = Vector3i(MAX(mx.x, x), MAX(mx.y, y), MAX(mx.z, z));
	}
	Ref<VoxelVolume> out;
	out.instantiate();
	out->setup(mx - mn + Vector3i(1, 1, 1));
	out->palette = palette;
	for (int i : p_indices) {
		const int x = i % sx;
		const int t = i / sx;
		const int y = t % sy;
		const int z = t / sy;
		out->write(out->idx(x - mn.x, y - mn.y, z - mn.z), data[i]);
		write(i, 0);
	}
	r_offset = mn;
	return out;
}

// Finds pieces that lost their connection after an edit inside [region_min, region_max].
// Anchored volumes (anchor_bottom): any piece not connected to the bottom layer or an
// anchor material is cut off. Free volumes: everything except the largest piece is cut off.
// Searches are depth-first with downward neighbors first, and stop as soon as an anchor
// (or a piece already proven anchored) is reached, so intact buildings cost very little.
Array VoxelVolume::split_islands(const Vector3i &p_region_min, const Vector3i &p_region_max) {
	Array out;
	if (solid_count == 0 || palette.is_null()) {
		return out;
	}
	const VoxelPalette *pal = palette.ptr();
	// One scratch buffer shared by all volumes: generations only grow, so stamps
	// left by other volumes always read as "unvisited" for this call.
	if (g_stamps.size() < data.size()) {
		g_stamps.resize(data.size(), 0);
	}
	if (g_stamp_gen > 0xF0000000u) {
		std::fill(g_stamps.begin(), g_stamps.end(), 0);
		g_stamp_gen = 0;
	}
	std::vector<uint32_t> &stamps = g_stamps;
	uint32_t &stamp_gen = g_stamp_gen;
	const uint32_t gen_start = stamp_gen + 1;
	const bool anchored_mode = anchor_bottom;

	Vector3i a = p_region_min - Vector3i(1, 1, 1);
	Vector3i b = p_region_max + Vector3i(2, 2, 2);
	clip_box(a, b);

	// Open set as a bucket queue keyed by height: the lowest voxel is expanded
	// first, so a search heads straight for the ground instead of wandering
	// through the structure. Free volumes use a single bucket (plain DFS).
	std::vector<std::vector<int>> buckets(anchored_mode ? sy : 1);
	int lowest = 0;
	int highest = 0;
	int queued = 0;
	auto push = [&](int i, int y) {
		const int b = anchored_mode ? y : 0;
		buckets[b].push_back(i);
		lowest = MIN(lowest, b);
		highest = MAX(highest, b);
		queued++;
	};
	auto pop = [&]() -> int {
		while (buckets[lowest].empty()) {
			lowest++;
		}
		const int i = buckets[lowest].back();
		buckets[lowest].pop_back();
		queued--;
		return i;
	};
	auto reset = [&]() {
		if (queued > 0) {
			for (int b = lowest; b <= highest; b++) {
				buckets[b].clear();
			}
		}
		queued = 0;
		lowest = (int)buckets.size() - 1;
		highest = 0;
	};
	std::vector<int> comp;
	std::vector<std::vector<int>> found;
	const int sxy = sx * sy;
	int explored_total = 0;
	bool any_major = false;
	// Free volumes: a search that has claimed more than half of all voxels is the
	// main body for sure, so it stops there and plays the role of the anchor.
	const int half = solid_count / 2 + 1;
	dbg_pops = 0;
	dbg_searches = 0;

	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const int s = idx(x, y, z);
				if (!data[s] || stamps[s] >= gen_start) {
					continue;
				}
				const uint32_t label = ++stamp_gen;
				dbg_searches++;
				reset();
				comp.clear();
				push(s, y);
				stamps[s] = label;
				bool anchored = false;
				while (queued > 0 && !anchored) {
					const int i = pop();
					dbg_pops++;
					comp.push_back(i);
					const int cx = i % sx;
					const int t = i / sx;
					const int cy = t % sy;
					const int cz = t / sy;
					if (anchored_mode ? (cy == 0 || pal->is_anchor(data[i])) : ((int)comp.size() + queued >= half)) {
						anchored = true;
						break;
					}
					const int nbs[6][4] = {
						{ cx, cy + 1, cz, i + sx },
						{ cx + 1, cy, cz, i + 1 },
						{ cx - 1, cy, cz, i - 1 },
						{ cx, cy, cz + 1, i + sxy },
						{ cx, cy, cz - 1, i - sxy },
						{ cx, cy - 1, cz, i - sx },
					};
					for (int k = 0; k < 6; k++) {
						if (!inside(nbs[k][0], nbs[k][1], nbs[k][2])) {
							continue;
						}
						const int ni = nbs[k][3];
						if (!data[ni]) {
							continue;
						}
						const uint32_t st = stamps[ni];
						if (st == label) {
							continue;
						}
						if (st >= gen_start) {
							// Reached a piece explored earlier in this call. Floating pieces are
							// explored completely, so anything reachable from here is anchored
							// (or, for free volumes, part of the main body).
							anchored = true;
							break;
						}
						stamps[ni] = label;
						push(ni, nbs[k][1]);
					}
				}
				if (anchored) {
					any_major = true;
				} else {
					explored_total += (int)comp.size();
					found.push_back(comp);
				}
			}
		}
	}

	if (!anchored_mode && !any_major && !found.empty()) {
		// Keep the biggest piece in place (the voxels never explored count as one piece).
		size_t keep = 0;
		for (size_t k = 1; k < found.size(); k++) {
			if (found[k].size() > found[keep].size()) {
				keep = k;
			}
		}
		const int rest = solid_count - explored_total;
		if ((int)found[keep].size() >= rest) {
			found.erase(found.begin() + keep);
		}
	}

	for (const std::vector<int> &island : found) {
		Vector3i offset;
		Ref<VoxelVolume> vol = extract_indices(island, offset);
		Dictionary d;
		d["volume"] = vol;
		d["offset"] = offset;
		d["count"] = (int)island.size();
		out.push_back(d);
	}
	return out;
}

// ---------------------------------------------------------------- Queries

Dictionary VoxelVolume::compute_mass(float p_voxel_size) const {
	Dictionary res;
	ERR_FAIL_COND_V(palette.is_null(), res);
	const VoxelPalette *pal = palette.ptr();
	const double vv = (double)p_voxel_size * p_voxel_size * p_voxel_size;
	double mass = 0.0;
	double cx = 0.0, cy = 0.0, cz = 0.0;
	for (int z = 0; z < sz; z++) {
		for (int y = 0; y < sy; y++) {
			for (int x = 0; x < sx; x++) {
				const uint8_t v = data[idx(x, y, z)];
				if (!v) {
					continue;
				}
				const double m = pal->density[pal->material[v]] * vv;
				mass += m;
				cx += (x + 0.5) * m;
				cy += (y + 0.5) * m;
				cz += (z + 0.5) * m;
			}
		}
	}
	res["mass"] = mass;
	res["count"] = solid_count;
	if (mass > 0.0) {
		res["com"] = Vector3((real_t)(cx / mass * p_voxel_size), (real_t)(cy / mass * p_voxel_size), (real_t)(cz / mass * p_voxel_size));
	} else {
		res["com"] = Vector3();
	}
	return res;
}

Array VoxelVolume::get_bounds() const {
	Array out;
	Vector3i mn(INT32_MAX, INT32_MAX, INT32_MAX), mx(-1, -1, -1);
	for (int z = 0; z < sz; z++) {
		for (int y = 0; y < sy; y++) {
			for (int x = 0; x < sx; x++) {
				if (data[idx(x, y, z)]) {
					mn = Vector3i(MIN(mn.x, x), MIN(mn.y, y), MIN(mn.z, z));
					mx = Vector3i(MAX(mx.x, x), MAX(mx.y, y), MAX(mx.z, z));
				}
			}
		}
	}
	if (mx.x < 0) {
		return out;
	}
	out.push_back(mn);
	out.push_back(mx + Vector3i(1, 1, 1));
	return out;
}

Vector3i VoxelVolume::crop() {
	Array bounds = get_bounds();
	if (bounds.is_empty()) {
		return Vector3i();
	}
	const Vector3i mn = bounds[0];
	const Vector3i mx = bounds[1];
	const Vector3i ns = mx - mn;
	if (ns == get_size()) {
		return Vector3i();
	}
	std::vector<uint8_t> nd((size_t)ns.x * ns.y * ns.z);
	for (int z = 0; z < ns.z; z++) {
		for (int y = 0; y < ns.y; y++) {
			for (int x = 0; x < ns.x; x++) {
				nd[x + (size_t)ns.x * (y + (size_t)ns.y * z)] = data[idx(x + mn.x, y + mn.y, z + mn.z)];
			}
		}
	}
	sx = ns.x;
	sy = ns.y;
	sz = ns.z;
	data.swap(nd);
	return mn;
}

PackedInt32Array VoxelVolume::material_histogram(const Vector3i &p_from, const Vector3i &p_to) const {
	PackedInt32Array out;
	out.resize(MAT_COUNT);
	out.fill(0);
	if (palette.is_null()) {
		return out;
	}
	Vector3i a = p_from, b = p_to;
	clip_box(a, b);
	int32_t *w = out.ptrw();
	for (int z = a.z; z < b.z; z++) {
		for (int y = a.y; y < b.y; y++) {
			for (int x = a.x; x < b.x; x++) {
				const uint8_t v = data[idx(x, y, z)];
				if (v) {
					w[palette->material[v]]++;
				}
			}
		}
	}
	return out;
}

// Random voxel of a material near p_center that touches air (used by fire spread).
// Returns (-1,-1,-1) when nothing is found.
Vector3i VoxelVolume::find_surface_voxel(const Vector3i &p_center, int p_radius, int p_material, int p_seed) const {
	if (palette.is_null()) {
		return Vector3i(-1, -1, -1);
	}
	const int span = p_radius * 2 + 1;
	for (int attempt = 0; attempt < 24; attempt++) {
		const uint32_t h = hash3(p_center.x, p_center.y + attempt * 31, p_center.z, p_seed + attempt);
		const int x = p_center.x + (int)(h % span) - p_radius;
		const int y = p_center.y + (int)((h / span) % span) - p_radius;
		const int z = p_center.z + (int)((h / (span * span)) % span) - p_radius;
		const uint8_t v = at(x, y, z);
		if (!v || palette->material[v] != p_material) {
			continue;
		}
		if (!at(x + 1, y, z) || !at(x - 1, y, z) || !at(x, y + 1, z) || !at(x, y - 1, z) || !at(x, y, z + 1) || !at(x, y, z - 1)) {
			return Vector3i(x, y, z);
		}
	}
	return Vector3i(-1, -1, -1);
}

// ---------------------------------------------------------------- Bindings

void VoxelVolume::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "size"), &VoxelVolume::setup);
	ClassDB::bind_method(D_METHOD("get_size"), &VoxelVolume::get_size);
	ClassDB::bind_method(D_METHOD("set_palette", "palette"), &VoxelVolume::set_palette);
	ClassDB::bind_method(D_METHOD("get_palette"), &VoxelVolume::get_palette);
	ClassDB::bind_method(D_METHOD("set_anchor_bottom", "enable"), &VoxelVolume::set_anchor_bottom);
	ClassDB::bind_method(D_METHOD("get_anchor_bottom"), &VoxelVolume::get_anchor_bottom);
	ClassDB::bind_method(D_METHOD("get_solid_count"), &VoxelVolume::get_solid_count);
	ClassDB::bind_method(D_METHOD("get_voxel", "pos"), &VoxelVolume::get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "pos", "value"), &VoxelVolume::set_voxel);
	ClassDB::bind_method(D_METHOD("get_data"), &VoxelVolume::get_data);
	ClassDB::bind_method(D_METHOD("set_data", "data"), &VoxelVolume::set_data);

	ClassDB::bind_method(D_METHOD("fill_box", "from", "to", "value"), &VoxelVolume::fill_box);
	ClassDB::bind_method(D_METHOD("fill_box_noise", "from", "to", "values", "seed"), &VoxelVolume::fill_box_noise);
	ClassDB::bind_method(D_METHOD("fill_bricks", "from", "to", "long_axis", "brick_len", "brick_h", "values", "mortar", "seed"), &VoxelVolume::fill_bricks);
	ClassDB::bind_method(D_METHOD("fill_planks", "from", "to", "run_axis", "stack_axis", "width", "values", "seed"), &VoxelVolume::fill_planks);
	ClassDB::bind_method(D_METHOD("fill_sphere", "center", "radius", "value"), &VoxelVolume::fill_sphere);
	ClassDB::bind_method(D_METHOD("fill_ellipsoid_noise", "center", "radii", "values", "fill_chance", "roughness", "seed"), &VoxelVolume::fill_ellipsoid_noise);
	ClassDB::bind_method(D_METHOD("fill_cylinder", "base", "radius", "height", "axis", "value"), &VoxelVolume::fill_cylinder);
	ClassDB::bind_method(D_METHOD("fill_columns", "from", "size_xz", "heights", "base", "scale", "layers", "seed"), &VoxelVolume::fill_columns);
	ClassDB::bind_method(D_METHOD("replace", "from", "to", "old_value", "new_value"), &VoxelVolume::replace);
	ClassDB::bind_method(D_METHOD("copy_from", "src", "offset", "skip_empty"), &VoxelVolume::copy_from);

	ClassDB::bind_method(D_METHOD("build_mesh", "min", "size", "voxel_size"), &VoxelVolume::build_mesh);
	ClassDB::bind_method(D_METHOD("build_boxes", "min", "size", "voxel_size"), &VoxelVolume::build_boxes);

	ClassDB::bind_method(D_METHOD("carve_sphere", "center", "radius", "power", "jitter", "debris_chance", "max_debris", "seed"), &VoxelVolume::carve_sphere);
	ClassDB::bind_method(D_METHOD("paint_sphere", "center", "radius", "remap", "chance", "seed"), &VoxelVolume::paint_sphere);
	ClassDB::bind_method(D_METHOD("split_islands", "region_min", "region_max"), &VoxelVolume::split_islands);
	ClassDB::bind_method(D_METHOD("get_split_stats"), &VoxelVolume::get_split_stats);

	ClassDB::bind_method(D_METHOD("compute_mass", "voxel_size"), &VoxelVolume::compute_mass);
	ClassDB::bind_method(D_METHOD("get_bounds"), &VoxelVolume::get_bounds);
	ClassDB::bind_method(D_METHOD("crop"), &VoxelVolume::crop);
	ClassDB::bind_method(D_METHOD("material_histogram", "from", "to"), &VoxelVolume::material_histogram);
	ClassDB::bind_method(D_METHOD("find_surface_voxel", "center", "radius", "material", "seed"), &VoxelVolume::find_surface_voxel);
}
