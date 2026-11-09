#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// Material ids are shared with scripts/voxel/voxel_materials.gd.
enum VoxelMaterial {
	MAT_NONE = 0,
	MAT_GLASS = 1,
	MAT_WOOD = 2,
	MAT_PLASTER = 3,
	MAT_BRICK = 4,
	MAT_CONCRETE = 5,
	MAT_METAL = 6,
	MAT_HARDMETAL = 7,
	MAT_FOLIAGE = 8,
	MAT_DIRT = 9,
	MAT_ROCK = 10,
	MAT_PLASTIC = 11,
	MAT_UNBREAKABLE = 12,
	MAT_EMISSIVE = 13,
	MAT_COUNT = 32,
};

enum VoxelMaterialFlags {
	MATF_TRANSPARENT = 1,
	MATF_ANCHOR = 2, // voxels of this material hold a static structure in place
	MATF_COARSE = 4, // collision built at half resolution (foliage)
};

// 256-entry palette shared by every volume of a scene. Index 0 is empty.
class VoxelPalette : public RefCounted {
	GDCLASS(VoxelPalette, RefCounted)

public:
	Color linear[256];
	Color srgb[256];
	uint8_t material[256] = {};
	float strength[MAT_COUNT] = {};
	float density[MAT_COUNT] = {};
	uint8_t flags[MAT_COUNT] = {};
	uint8_t pattern[256] = {}; // shader color pattern id, written to UV.y

	VoxelPalette();

	void set_entry(int p_index, const Color &p_srgb, int p_material, int p_pattern = 0);
	int get_pattern(int p_index) const;
	Color get_color(int p_index) const;
	int get_material(int p_index) const;
	void set_material_props(int p_material, float p_strength, float p_density, int p_flags);
	float get_strength(int p_material) const;
	float get_density(int p_material) const;
	int get_flags(int p_material) const;

	inline bool is_transparent(uint8_t v) const { return (flags[material[v]] & MATF_TRANSPARENT) != 0; }
	inline bool is_anchor(uint8_t v) const { return (flags[material[v]] & MATF_ANCHOR) != 0; }
	inline bool is_coarse(uint8_t v) const { return (flags[material[v]] & MATF_COARSE) != 0; }

protected:
	static void _bind_methods();
};

// Dense voxel grid, one byte (palette index) per voxel.
// Layout: index = x + sx * (y + sy * z).
class VoxelVolume : public RefCounted {
	GDCLASS(VoxelVolume, RefCounted)

	int sx = 0, sy = 0, sz = 0;
	std::vector<uint8_t> data;
	int solid_count = 0;
	bool anchor_bottom = false;
	Ref<VoxelPalette> palette;


	inline int idx(int x, int y, int z) const { return x + sx * (y + sy * z); }
	inline bool inside(int x, int y, int z) const { return x >= 0 && y >= 0 && z >= 0 && x < sx && y < sy && z < sz; }
	inline uint8_t at(int x, int y, int z) const { return inside(x, y, z) ? data[idx(x, y, z)] : 0; }
	void clip_box(Vector3i &r_from, Vector3i &r_to) const;
	inline void write(int i, uint8_t v) {
		uint8_t old = data[i];
		solid_count += (v != 0) - (old != 0);
		data[i] = v;
	}
	Ref<VoxelVolume> extract_indices(const std::vector<int> &p_indices, Vector3i &r_offset);

protected:
	static void _bind_methods();

public:
	void setup(const Vector3i &p_size);
	Vector3i get_size() const { return Vector3i(sx, sy, sz); }
	void set_palette(const Ref<VoxelPalette> &p_palette) { palette = p_palette; }
	Ref<VoxelPalette> get_palette() const { return palette; }
	void set_anchor_bottom(bool p_enable) { anchor_bottom = p_enable; }
	bool get_anchor_bottom() const { return anchor_bottom; }
	int get_solid_count() const { return solid_count; }

	int get_voxel(const Vector3i &p) const { return at(p.x, p.y, p.z); }
	void set_voxel(const Vector3i &p, int p_value);
	PackedByteArray get_data() const;
	void set_data(const PackedByteArray &p_data);

	// Procedural fills. Boxes are [from, to) and clipped to the volume.
	void fill_box(const Vector3i &p_from, const Vector3i &p_to, int p_value);
	void fill_box_noise(const Vector3i &p_from, const Vector3i &p_to, const PackedByteArray &p_values, int p_seed);
	void fill_bricks(const Vector3i &p_from, const Vector3i &p_to, int p_long_axis, int p_brick_len, int p_brick_h, const PackedByteArray &p_values, int p_mortar, int p_seed);
	void fill_planks(const Vector3i &p_from, const Vector3i &p_to, int p_run_axis, int p_stack_axis, int p_width, const PackedByteArray &p_values, int p_seed);
	void fill_sphere(const Vector3 &p_center, float p_radius, int p_value);
	void fill_ellipsoid_noise(const Vector3 &p_center, const Vector3 &p_radii, const PackedByteArray &p_values, float p_fill_chance, float p_roughness, int p_seed);
	void fill_cylinder(const Vector3 &p_base, float p_radius, int p_height, int p_axis, int p_value);
	void fill_columns(const Vector3i &p_from, const Vector3i &p_size_xz, const PackedFloat32Array &p_heights, float p_base, float p_scale, const PackedByteArray &p_layers, int p_seed);
	void replace(const Vector3i &p_from, const Vector3i &p_to, int p_old, int p_new);
	void copy_from(const Ref<VoxelVolume> &p_src, const Vector3i &p_offset, bool p_skip_empty);

	// Rendering / physics data for one chunk region.
	Array build_mesh(const Vector3i &p_min, const Vector3i &p_size, float p_voxel_size) const;
	PackedFloat32Array build_boxes(const Vector3i &p_min, const Vector3i &p_size, float p_voxel_size) const;

	// Destruction.
	Dictionary carve_sphere(const Vector3 &p_center, float p_radius, float p_power, float p_jitter, float p_debris_chance, int p_max_debris, int p_seed);
	Dictionary paint_sphere(const Vector3 &p_center, float p_radius, const PackedByteArray &p_remap, float p_chance, int p_seed);
	Array split_islands(const Vector3i &p_region_min, const Vector3i &p_region_max);
	int dbg_pops = 0;
	int dbg_searches = 0;
	Vector2i get_split_stats() const { return Vector2i(dbg_searches, dbg_pops); }

	// Queries.
	Dictionary compute_mass(float p_voxel_size) const;
	Array get_bounds() const; // [min, max_exclusive] or [] when empty
	Vector3i crop();
	PackedInt32Array material_histogram(const Vector3i &p_from, const Vector3i &p_to) const;
	Vector3i find_surface_voxel(const Vector3i &p_center, int p_radius, int p_material, int p_seed) const;
};

} // namespace godot
