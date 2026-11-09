// Meshing and collision decomposition for VoxelVolume chunks.

#include "voxel_volume.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <cstring>

using namespace godot;

namespace {

template <typename T, typename P>
P to_packed(const std::vector<T> &v) {
	P out;
	out.resize((int64_t)v.size());
	if (!v.empty()) {
		memcpy(out.ptrw(), v.data(), v.size() * sizeof(T));
	}
	return out;
}

struct MeshBuffers {
	std::vector<Vector3> verts;
	std::vector<Vector3> normals;
	std::vector<Color> colors;
	std::vector<Vector2> uvs;
	std::vector<int32_t> indices;

	void reserve(size_t quads) {
		verts.reserve(quads * 4);
		normals.reserve(quads * 4);
		colors.reserve(quads * 4);
		uvs.reserve(quads * 4);
		indices.reserve(quads * 6);
	}

	Array to_arrays() const {
		Array arrays;
		if (verts.empty()) {
			return arrays;
		}
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = to_packed<Vector3, PackedVector3Array>(verts);
		arrays[Mesh::ARRAY_NORMAL] = to_packed<Vector3, PackedVector3Array>(normals);
		arrays[Mesh::ARRAY_COLOR] = to_packed<Color, PackedColorArray>(colors);
		arrays[Mesh::ARRAY_TEX_UV] = to_packed<Vector2, PackedVector2Array>(uvs);
		arrays[Mesh::ARRAY_INDEX] = to_packed<int32_t, PackedInt32Array>(indices);
		return arrays;
	}
};

// Greedy box merge over an occupancy grid (x runs, then z rows, then y layers).
// Cell (x,y,z) covers voxels [x*scale, (x+1)*scale) clipped to `limit`.
void greedy_boxes(std::vector<uint8_t> &todo, int nx, int ny, int nz, int scale, const Vector3i &offset, const Vector3i &limit, float vs, std::vector<float> &out) {
	auto T = [&](int x, int y, int z) -> uint8_t & { return todo[x + (size_t)nx * (y + (size_t)ny * z)]; };
	for (int y = 0; y < ny; y++) {
		for (int z = 0; z < nz; z++) {
			for (int x = 0; x < nx; x++) {
				if (!T(x, y, z)) {
					continue;
				}
				int x1 = x;
				while (x1 + 1 < nx && T(x1 + 1, y, z)) {
					x1++;
				}
				int z1 = z;
				while (z1 + 1 < nz) {
					bool ok = true;
					for (int xx = x; xx <= x1 && ok; xx++) {
						ok = T(xx, y, z1 + 1) != 0;
					}
					if (!ok) {
						break;
					}
					z1++;
				}
				int y1 = y;
				while (y1 + 1 < ny) {
					bool ok = true;
					for (int zz = z; zz <= z1 && ok; zz++) {
						for (int xx = x; xx <= x1 && ok; xx++) {
							ok = T(xx, y1 + 1, zz) != 0;
						}
					}
					if (!ok) {
						break;
					}
					y1++;
				}
				for (int yy = y; yy <= y1; yy++) {
					for (int zz = z; zz <= z1; zz++) {
						for (int xx = x; xx <= x1; xx++) {
							T(xx, yy, zz) = 0;
						}
					}
				}
				const int ax = x * scale, ay = y * scale, az = z * scale;
				const int bx = MIN((x1 + 1) * scale, limit.x);
				const int by = MIN((y1 + 1) * scale, limit.y);
				const int bz = MIN((z1 + 1) * scale, limit.z);
				const float hx = (bx - ax) * 0.5f, hy = (by - ay) * 0.5f, hz = (bz - az) * 0.5f;
				out.push_back((offset.x + ax + hx) * vs);
				out.push_back((offset.y + ay + hy) * vs);
				out.push_back((offset.z + az + hz) * vs);
				out.push_back(hx * vs);
				out.push_back(hy * vs);
				out.push_back(hz * vs);
			}
		}
	}
}

} // namespace

// Greedy mesher with per-vertex ambient occlusion. Faces merge when palette index
// and all four AO values match. Color variation (bricks, planks, noise) is done in
// the shader from the pattern id, so walls collapse into a handful of quads.
// Vertex COLOR = linear palette color with AO in alpha; UV = (material, pattern).
Array VoxelVolume::build_mesh(const Vector3i &p_min, const Vector3i &p_size, float p_voxel_size) const {
	Array result;
	result.resize(2);
	result[0] = Array();
	result[1] = Array();
	ERR_FAIL_COND_V(palette.is_null(), result);
	const VoxelPalette *pal = palette.ptr();

	const int n[3] = { MIN(p_size.x, sx - p_min.x), MIN(p_size.y, sy - p_min.y), MIN(p_size.z, sz - p_min.z) };
	if (n[0] <= 0 || n[1] <= 0 || n[2] <= 0) {
		return result;
	}

	uint8_t trans[256];
	for (int i = 0; i < 256; i++) {
		trans[i] = i != 0 && pal->is_transparent((uint8_t)i);
	}

	// Padded copy (1 voxel border) removes bounds checks from the hot loop.
	const int px = n[0] + 2, py = n[1] + 2, pz = n[2] + 2;
	const size_t pcount = (size_t)px * py * pz;
	std::vector<uint8_t> pad(pcount, 0);
	std::vector<uint8_t> occ(pcount, 0);
	bool any = false;
	for (int z = 0; z < pz; z++) {
		const int vz = p_min.z + z - 1;
		if (vz < 0 || vz >= sz) {
			continue;
		}
		for (int y = 0; y < py; y++) {
			const int vy = p_min.y + y - 1;
			if (vy < 0 || vy >= sy) {
				continue;
			}
			const int x0 = MAX(0, 1 - p_min.x);
			const int x1 = MIN(px, sx - p_min.x + 1);
			if (x1 <= x0) {
				continue;
			}
			const size_t dst = (size_t)px * (y + (size_t)py * z);
			const uint8_t *src = &data[idx(p_min.x + x0 - 1, vy, vz)];
			memcpy(&pad[dst + x0], src, x1 - x0);
			for (int x = x0; x < x1; x++) {
				const uint8_t v = pad[dst + x];
				occ[dst + x] = v != 0 && !trans[v];
				any |= v != 0;
			}
		}
	}
	if (!any) {
		return result;
	}

	const int stride[3] = { 1, px, px * py };
	MeshBuffers opaque, glass;
	opaque.reserve(1024);
	std::vector<uint32_t> mask;

	static const int corner_du[4] = { -1, 1, 1, -1 };
	static const int corner_dv[4] = { -1, -1, 1, 1 };

	for (int a = 0; a < 3; a++) {
		const int u = (a + 1) % 3;
		const int v = (a + 2) % 3;
		const int nu = n[u], nv = n[v], na = n[a];
		const int su = stride[u], sv = stride[v], sa = stride[a];
		mask.assign((size_t)nu * nv, 0);
		int co1[4], co2[4], co3[4];
		for (int k = 0; k < 4; k++) {
			co1[k] = corner_du[k] * su;
			co2[k] = corner_dv[k] * sv;
			co3[k] = co1[k] + co2[k];
		}
		for (int sign = -1; sign <= 1; sign += 2) {
			Vector3 normal;
			normal[a] = (real_t)sign;
			const int front = sign * sa;
			for (int d = 0; d < na; d++) {
				const int base = (d + 1) * sa + su + sv;
				bool any_face = false;
				for (int j = 0; j < nv; j++) {
					int pi = base + j * sv;
					uint32_t *mrow = &mask[(size_t)j * nu];
					for (int i = 0; i < nu; i++, pi += su) {
						const uint8_t vox = pad[pi];
						uint32_t key = 0;
						if (vox) {
							const uint8_t nb = pad[pi + front];
							if (nb == 0 || (trans[nb] && !trans[vox])) {
								uint32_t ao_bits = 0xFFu << 8; // all corners unoccluded
								if (!trans[vox]) {
									ao_bits = 0;
									const int f = pi + front;
									for (int k = 0; k < 4; k++) {
										const int s1 = occ[f + co1[k]];
										const int s2 = occ[f + co2[k]];
										const int cr = occ[f + co3[k]];
										const int ao = (s1 && s2) ? 0 : 3 - (s1 + s2 + cr);
										ao_bits |= (uint32_t)ao << (8 + 2 * k);
									}
								}
								key = vox | ao_bits;
								any_face = true;
							}
						}
						mrow[i] = key;
					}
				}
				if (!any_face) {
					continue;
				}
				for (int j = 0; j < nv; j++) {
					uint32_t *mrow = &mask[(size_t)j * nu];
					for (int i = 0; i < nu;) {
						const uint32_t key = mrow[i];
						if (!key) {
							i++;
							continue;
						}
						int w = 1;
						while (i + w < nu && mrow[i + w] == key) {
							w++;
						}
						int h = 1;
						while (j + h < nv) {
							const uint32_t *r = &mask[(size_t)(j + h) * nu + i];
							bool ok = true;
							for (int k = 0; k < w; k++) {
								if (r[k] != key) {
									ok = false;
									break;
								}
							}
							if (!ok) {
								break;
							}
							h++;
						}
						for (int hh = 0; hh < h; hh++) {
							memset(&mask[(size_t)(j + hh) * nu + i], 0, sizeof(uint32_t) * w);
						}

						const uint8_t vox = key & 0xFF;
						MeshBuffers &mb = trans[vox] ? glass : opaque;
						int b3[3];
						b3[a] = p_min[a] + d + (sign > 0 ? 1 : 0);
						b3[u] = p_min[u] + i;
						b3[v] = p_min[v] + j;
						const Vector3 p0((real_t)b3[0], (real_t)b3[1], (real_t)b3[2]);
						Vector3 du, dv;
						du[u] = (real_t)w;
						dv[v] = (real_t)h;
						const Vector3 corners[4] = { p0, p0 + du, p0 + du + dv, p0 + dv };
						int ao[4];
						for (int k = 0; k < 4; k++) {
							ao[k] = (key >> (8 + 2 * k)) & 3;
						}
						const int start = (int)mb.verts.size();
						const Color col = pal->linear[vox];
						const Vector2 uv((real_t)pal->material[vox], (real_t)pal->pattern[vox]);
						for (int k = 0; k < 4; k++) {
							mb.verts.push_back(corners[k] * p_voxel_size);
							mb.normals.push_back(normal);
							mb.colors.push_back(Color(col.r, col.g, col.b, ao[k] / 3.0f));
							mb.uvs.push_back(uv);
						}
						// Flip the diagonal so AO interpolates without the classic seam artifact.
						int tri[6];
						if (ao[0] + ao[2] >= ao[1] + ao[3]) {
							const int t[6] = { 0, 1, 2, 0, 2, 3 };
							memcpy(tri, t, sizeof(t));
						} else {
							const int t[6] = { 1, 2, 3, 1, 3, 0 };
							memcpy(tri, t, sizeof(t));
						}
						// Godot treats clockwise triangles as front facing.
						if (sign > 0) {
							std::swap(tri[1], tri[2]);
							std::swap(tri[4], tri[5]);
						}
						for (int k = 0; k < 6; k++) {
							mb.indices.push_back(start + tri[k]);
						}
						i += w;
					}
				}
			}
		}
	}

	result[0] = opaque.to_arrays();
	result[1] = glass.to_arrays();
	return result;
}

// Collision boxes for a chunk: 6 floats per box (center xyz, half extents xyz) in
// meters. Materials flagged coarse (foliage) are merged on a 2x grid: a coarse cell
// is solid when at least 2 of its 8 voxels are, which cuts tree box counts ~5x.
PackedFloat32Array VoxelVolume::build_boxes(const Vector3i &p_min, const Vector3i &p_size, float p_voxel_size) const {
	const int nx = MIN(p_size.x, sx - p_min.x);
	const int ny = MIN(p_size.y, sy - p_min.y);
	const int nz = MIN(p_size.z, sz - p_min.z);
	if (nx <= 0 || ny <= 0 || nz <= 0) {
		return PackedFloat32Array();
	}
	const VoxelPalette *pal = palette.ptr();
	uint8_t coarse[256] = {};
	if (pal) {
		for (int i = 1; i < 256; i++) {
			coarse[i] = pal->is_coarse((uint8_t)i);
		}
	}
	const int cx = (nx + 1) / 2, cy = (ny + 1) / 2, cz = (nz + 1) / 2;
	std::vector<uint8_t> todo((size_t)nx * ny * nz, 0);
	std::vector<uint8_t> ctodo;
	bool any_fine = false, any_coarse = false;
	for (int z = 0; z < nz; z++) {
		for (int y = 0; y < ny; y++) {
			const uint8_t *row = &data[idx(p_min.x, p_min.y + y, p_min.z + z)];
			uint8_t *dst = &todo[(size_t)nx * (y + (size_t)ny * z)];
			for (int x = 0; x < nx; x++) {
				const uint8_t v = row[x];
				if (!v) {
					continue;
				}
				if (coarse[v]) {
					if (!any_coarse) {
						ctodo.assign((size_t)cx * cy * cz, 0);
						any_coarse = true;
					}
					ctodo[(x / 2) + (size_t)cx * ((y / 2) + (size_t)cy * (z / 2))]++;
				} else {
					dst[x] = 1;
					any_fine = true;
				}
			}
		}
	}
	std::vector<float> out;
	if (any_fine) {
		greedy_boxes(todo, nx, ny, nz, 1, p_min, Vector3i(nx, ny, nz), p_voxel_size, out);
	}
	if (any_coarse) {
		for (uint8_t &c : ctodo) {
			c = c >= 2;
		}
		greedy_boxes(ctodo, cx, cy, cz, 2, p_min, Vector3i(nx, ny, nz), p_voxel_size, out);
	}
	return to_packed<float, PackedFloat32Array>(out);
}
