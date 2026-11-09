class_name VoxMat
## Shared voxel palette and material table.
## Material ids must match VoxelMaterial in native/src/voxel_volume.h.

const NONE := 0
const GLASS := 1
const WOOD := 2
const PLASTER := 3
const BRICK := 4
const CONCRETE := 5
const METAL := 6
const HARDMETAL := 7
const FOLIAGE := 8
const DIRT := 9
const ROCK := 10
const PLASTIC := 11
const UNBREAKABLE := 12
const EMISSIVE := 13

const F_TRANSPARENT := 1
const F_ANCHOR := 2
const F_COARSE := 4  # half-resolution collision (foliage)

const NAMES := {
	GLASS: "Стекло", WOOD: "Дерево", PLASTER: "Штукатурка", BRICK: "Кирпич",
	CONCRETE: "Бетон", METAL: "Металл", HARDMETAL: "Сталь", FOLIAGE: "Листва",
	DIRT: "Грунт", ROCK: "Камень", PLASTIC: "Пластик", UNBREAKABLE: "Основание",
	EMISSIVE: "Лампа",
}

## [strength, density kg/m3, flags]. Tool power vs strength decides what breaks:
## power >= strength removes fully, power >= strength/2 chips a smaller core.
## Densities are gameplay values: walls are 10 cm thick, so real densities would
## make every crate and barrel several times too heavy.
const PROPS := {
	GLASS: [0.3, 1500.0, F_TRANSPARENT],
	WOOD: [1.0, 400.0, 0],
	PLASTER: [0.8, 900.0, 0],
	BRICK: [3.0, 1500.0, 0],
	CONCRETE: [4.0, 1800.0, 0],
	METAL: [7.0, 1000.0, 0],
	HARDMETAL: [20.0, 2500.0, 0],
	FOLIAGE: [0.15, 80.0, F_COARSE],
	DIRT: [2.5, 1300.0, 0],
	ROCK: [8.0, 2000.0, 0],
	PLASTIC: [0.6, 500.0, 0],
	UNBREAKABLE: [1000000.0, 3000.0, F_ANCHOR],
	EMISSIVE: [0.3, 1000.0, 0],
}

const FLAMMABLE := [WOOD, FOLIAGE, PLASTIC]

## Shader color patterns (voxel.gdshader), stored per palette entry.
const P_NOISE := 0
const P_NOISE_MED := 1
const P_NOISE_HIGH := 2
const P_BRICK := 3
const P_PLANK := 4
const P_TILE := 5
const P_SMOOTH := 6
const P_CORRUGATED := 7

static var palette: VoxelPalette
## name -> PackedByteArray with the palette index of a swatch (one entry; color
## variation comes from the shader pattern, which keeps greedy meshing effective)
static var sets := {}
static var paint_remap := PackedByteArray()
static var char_remap := PackedByteArray()
static var burn_remap := PackedByteArray()
static var opaque_material: ShaderMaterial
static var glass_material: ShaderMaterial
static var debris_material: ShaderMaterial
static var _next := 1
static var _material_of := PackedByteArray()


static func setup() -> void:
	if palette != null:
		return
	palette = VoxelPalette.new()
	_material_of.resize(256)
	for m in PROPS:
		var p: Array = PROPS[m]
		palette.set_material_props(m, p[0], p[1], p[2])

	_swatch("glass", Color(0.62, 0.78, 0.84), GLASS, P_SMOOTH)
	_swatch("wood", Color(0.56, 0.39, 0.23), WOOD, P_PLANK)
	_swatch("wood_dark", Color(0.34, 0.23, 0.14), WOOD, P_PLANK)
	_swatch("wood_grey", Color(0.52, 0.48, 0.42), WOOD, P_PLANK)
	_swatch("wood_red", Color(0.50, 0.17, 0.12), WOOD, P_PLANK)
	_swatch("wood_light", Color(0.74, 0.60, 0.40), WOOD, P_PLANK)
	_swatch("plaster", Color(0.86, 0.83, 0.75), PLASTER, P_NOISE)
	_swatch("plaster_blue", Color(0.52, 0.63, 0.68), PLASTER, P_NOISE)
	_swatch("plaster_green", Color(0.58, 0.66, 0.52), PLASTER, P_NOISE)
	_swatch("brick", Color(0.62, 0.28, 0.19), BRICK, P_BRICK)
	_swatch("brick_dark", Color(0.42, 0.21, 0.16), BRICK, P_BRICK)
	_swatch("mortar", Color(0.66, 0.62, 0.56), BRICK, P_NOISE)
	_swatch("roof_tile", Color(0.36, 0.34, 0.33), BRICK, P_TILE)
	_swatch("concrete", Color(0.63, 0.62, 0.59), CONCRETE, P_NOISE)
	_swatch("concrete_dark", Color(0.45, 0.45, 0.44), CONCRETE, P_NOISE)
	_swatch("asphalt", Color(0.23, 0.23, 0.24), CONCRETE, P_NOISE_MED)
	_swatch("road_line", Color(0.85, 0.84, 0.78), CONCRETE, P_NOISE)
	_swatch("metal", Color(0.50, 0.52, 0.55), METAL, P_NOISE)
	_swatch("metal_rust", Color(0.46, 0.27, 0.16), METAL, P_NOISE_HIGH)
	_swatch("metal_red", Color(0.74, 0.16, 0.10), METAL, P_NOISE)
	_swatch("metal_yellow", Color(0.92, 0.70, 0.12), METAL, P_NOISE)
	_swatch("metal_blue", Color(0.22, 0.36, 0.58), METAL, P_CORRUGATED)
	_swatch("metal_green", Color(0.26, 0.40, 0.31), METAL, P_CORRUGATED)
	_swatch("metal_white", Color(0.84, 0.84, 0.82), METAL, P_NOISE)
	_swatch("metal_dark", Color(0.20, 0.21, 0.23), METAL, P_NOISE)
	_swatch("hardmetal", Color(0.26, 0.27, 0.29), HARDMETAL, P_NOISE)
	_swatch("foliage", Color(0.27, 0.40, 0.16), FOLIAGE, P_NOISE_HIGH)
	_swatch("pine", Color(0.16, 0.29, 0.17), FOLIAGE, P_NOISE_HIGH)
	_swatch("grass", Color(0.31, 0.44, 0.17), DIRT, P_NOISE_HIGH)
	_swatch("dirt", Color(0.40, 0.31, 0.21), DIRT, P_NOISE_MED)
	_swatch("gravel", Color(0.52, 0.50, 0.46), DIRT, P_NOISE_HIGH)
	_swatch("rock", Color(0.46, 0.45, 0.43), ROCK, P_NOISE_MED)
	_swatch("plastic_orange", Color(0.92, 0.45, 0.10), PLASTIC, P_SMOOTH)
	_swatch("plastic_white", Color(0.88, 0.88, 0.86), PLASTIC, P_SMOOTH)
	_swatch("plastic_blue", Color(0.12, 0.30, 0.68), PLASTIC, P_SMOOTH)
	_swatch("rubber", Color(0.09, 0.09, 0.10), PLASTIC, P_NOISE)
	_swatch("bedrock", Color(0.22, 0.21, 0.20), UNBREAKABLE, P_NOISE_MED)
	_swatch("lamp", Color(1.0, 0.86, 0.62), EMISSIVE, P_SMOOTH)
	# District (Russian microdistrict) swatches.
	_swatch("panel_beige", Color(0.80, 0.73, 0.60), CONCRETE, P_NOISE)
	_swatch("panel_grey", Color(0.72, 0.71, 0.68), CONCRETE, P_NOISE)
	_swatch("panel_cream", Color(0.86, 0.80, 0.66), CONCRETE, P_NOISE)
	_swatch("panel_seam", Color(0.54, 0.51, 0.46), CONCRETE, P_NOISE)
	_swatch("plinth", Color(0.47, 0.46, 0.43), CONCRETE, P_NOISE_MED)
	_swatch("roof_bitumen", Color(0.25, 0.25, 0.26), CONCRETE, P_NOISE_MED)
	_swatch("pvc", Color(0.91, 0.91, 0.89), PLASTIC, P_SMOOTH)
	_swatch("window_light", Color(1.0, 0.78, 0.50), EMISSIVE, P_SMOOTH)
	_swatch("curtain_red", Color(0.55, 0.22, 0.18), PLASTIC, P_NOISE)
	_swatch("curtain_green", Color(0.33, 0.45, 0.30), PLASTIC, P_NOISE)
	_swatch("curtain_beige", Color(0.78, 0.70, 0.55), PLASTIC, P_NOISE)
	_swatch("door_metal", Color(0.36, 0.22, 0.15), METAL, P_NOISE)
	_swatch("sandwich", Color(0.83, 0.84, 0.83), METAL, P_CORRUGATED)
	_swatch("brand_red", Color(0.86, 0.12, 0.10), PLASTIC, P_SMOOTH)
	_swatch("brand_green", Color(0.12, 0.55, 0.25), PLASTIC, P_SMOOTH)
	_swatch("sign_glow", Color(0.98, 0.97, 0.94), EMISSIVE, P_SMOOTH)
	_swatch("silicate_brick", Color(0.84, 0.82, 0.76), BRICK, P_BRICK)
	_swatch("plaster_yellow", Color(0.86, 0.75, 0.52), PLASTER, P_NOISE)
	_swatch("sand", Color(0.80, 0.70, 0.50), DIRT, P_NOISE_MED)
	_swatch("mud", Color(0.30, 0.25, 0.18), DIRT, P_NOISE_MED)
	_swatch("sidewalk", Color(0.60, 0.59, 0.56), CONCRETE, P_TILE)
	_swatch("curb", Color(0.70, 0.69, 0.66), CONCRETE, P_NOISE)
	_swatch("asphalt_patch", Color(0.17, 0.17, 0.18), CONCRETE, P_NOISE_MED)
	_swatch("ballast", Color(0.43, 0.41, 0.38), DIRT, P_NOISE_HIGH)
	_swatch("rail", Color(0.42, 0.37, 0.33), HARDMETAL, P_NOISE)
	_swatch("birch_bark", Color(0.88, 0.87, 0.82), WOOD, P_NOISE)
	_swatch("birch_mark", Color(0.16, 0.15, 0.14), WOOD, P_NOISE)
	_swatch("birch_leaf", Color(0.46, 0.58, 0.24), FOLIAGE, P_NOISE_HIGH)
	_swatch("leaf_dark", Color(0.22, 0.36, 0.14), FOLIAGE, P_NOISE_HIGH)
	_swatch("reed", Color(0.52, 0.55, 0.30), FOLIAGE, P_NOISE_HIGH)
	_swatch("flower_red", Color(0.85, 0.22, 0.16), FOLIAGE, P_NOISE)
	_swatch("flower_yellow", Color(0.95, 0.80, 0.22), FOLIAGE, P_NOISE)
	_swatch("plastic_red", Color(0.82, 0.16, 0.12), PLASTIC, P_SMOOTH)
	_swatch("plastic_green", Color(0.20, 0.62, 0.25), PLASTIC, P_SMOOTH)
	_swatch("plastic_yellow", Color(0.95, 0.78, 0.15), PLASTIC, P_SMOOTH)
	_swatch("metal_brown", Color(0.42, 0.26, 0.17), METAL, P_NOISE_MED)
	_swatch("metal_teal", Color(0.20, 0.48, 0.48), METAL, P_NOISE_MED)
	_swatch("tank_black", Color(0.12, 0.12, 0.13), METAL, P_NOISE)
	_swatch("concrete_fence", Color(0.66, 0.65, 0.62), CONCRETE, P_TILE)
	# American town swatches.
	_swatch("brick_tan", Color(0.70, 0.52, 0.36), BRICK, P_BRICK)
	_swatch("brick_brown", Color(0.48, 0.30, 0.22), BRICK, P_BRICK)
	_swatch("stone", Color(0.80, 0.76, 0.68), CONCRETE, P_NOISE)
	_swatch("stucco", Color(0.84, 0.77, 0.63), PLASTER, P_NOISE)
	_swatch("awning_green", Color(0.15, 0.38, 0.24), PLASTIC, P_CORRUGATED)
	_swatch("awning_maroon", Color(0.46, 0.12, 0.14), PLASTIC, P_CORRUGATED)
	_swatch("awning_navy", Color(0.14, 0.20, 0.38), PLASTIC, P_CORRUGATED)
	_swatch("door_orange", Color(0.92, 0.48, 0.12), METAL, P_CORRUGATED)
	_swatch("road_yellow", Color(0.92, 0.72, 0.15), CONCRETE, P_NOISE)
	_swatch("maple_red", Color(0.68, 0.18, 0.10), FOLIAGE, P_NOISE_HIGH)
	_swatch("maple_orange", Color(0.86, 0.45, 0.12), FOLIAGE, P_NOISE_HIGH)
	_swatch("maple_yellow", Color(0.86, 0.68, 0.20), FOLIAGE, P_NOISE_HIGH)
	# Reserved swatches keep existing palette indices stable.
	_swatch("uni_blue", Color(0.20, 0.27, 0.40), PLASTIC, P_NOISE_MED)
	_swatch("uni_red", Color(0.45, 0.16, 0.13), PLASTIC, P_NOISE_MED)
	_swatch("vest_tan", Color(0.55, 0.50, 0.38), PLASTIC, P_NOISE)
	_swatch("vest_dark", Color(0.17, 0.17, 0.16), PLASTIC, P_NOISE)
	_swatch("helmet_blue", Color(0.26, 0.33, 0.42), PLASTIC, P_NOISE)
	_swatch("helmet_red", Color(0.36, 0.30, 0.22), PLASTIC, P_NOISE)
	_swatch("skin", Color(0.82, 0.62, 0.48), PLASTIC, P_SMOOTH)
	_swatch("skin_dark", Color(0.52, 0.36, 0.26), PLASTIC, P_SMOOTH)
	_swatch("boot", Color(0.14, 0.12, 0.10), PLASTIC, P_NOISE)
	_swatch("band_blue", Color(0.15, 0.55, 0.95), EMISSIVE, P_SMOOTH)
	_swatch("band_red", Color(0.95, 0.25, 0.12), EMISSIVE, P_SMOOTH)

	# Spray paint and scorch variants: one entry per material, same material id.
	var paint_color := Color(0.98, 0.80, 0.10)
	paint_remap.resize(256)
	char_remap.resize(256)
	burn_remap.resize(256)
	for i in 256:
		paint_remap[i] = i
		char_remap[i] = i
		burn_remap[i] = i
	var used := _next
	var paint_of := _paint_of
	var char_of := _char_of
	for m in [WOOD, PLASTER, BRICK, CONCRETE, METAL, HARDMETAL, DIRT, ROCK, PLASTIC, FOLIAGE]:
		paint_of[m] = _entry(paint_color.darkened(0.05 if m == METAL else 0.0), m, P_NOISE)
		var base := Color(0.10, 0.08, 0.06)
		match m:
			PLASTER, CONCRETE, ROCK: base = Color(0.24, 0.23, 0.22)
			BRICK: base = Color(0.22, 0.13, 0.10)
			METAL, HARDMETAL: base = Color(0.15, 0.14, 0.13)
			FOLIAGE: base = Color(0.13, 0.11, 0.07)
		char_of[m] = _entry(base, m, P_NOISE_HIGH)
	for i in range(1, used):
		var m := int(_material_of[i])
		if paint_of.has(m):
			paint_remap[i] = paint_of[m]
			char_remap[i] = char_of[m]
		if m in FLAMMABLE:
			burn_remap[i] = 0
	for m in char_of:
		if m in FLAMMABLE:
			burn_remap[char_of[m]] = 0
			burn_remap[paint_of[m]] = 0
		paint_remap[char_of[m]] = paint_of[m]

	_build_materials()


static func _entry(c: Color, mat: int, pattern := P_NOISE) -> int:
	assert(_next < 256, "palette full")
	var i := _next
	_next += 1
	palette.set_entry(i, c, mat, pattern)
	_material_of[i] = mat
	return i


static func _swatch(name: String, base: Color, mat: int, pattern: int) -> void:
	var arr := PackedByteArray()
	arr.append(_entry(base, mat, pattern))
	sets[name] = arr


static var _imported := {}
static var _paint_of := {}
static var _char_of := {}


## Palette entry for an imported color/material pair (.vox files). Allocates a new
## entry while the palette has room, otherwise reuses the closest existing color
## of the same material.
static func entry_for(c: Color, mat: int) -> int:
	var key := "%d:%s" % [mat, c.to_html(false)]
	if _imported.has(key):
		return _imported[key]
	var idx := -1
	if _next < 250:
		idx = _entry(c, mat, P_NOISE)
		if _paint_of.has(mat):
			paint_remap[idx] = _paint_of[mat]
			char_remap[idx] = _char_of[mat]
		if mat in FLAMMABLE:
			burn_remap[idx] = 0
	else:
		var best := INF
		for i in range(1, _next):
			if _material_of[i] != mat:
				continue
			var o := palette.get_color(i)
			var d := Vector3(o.r - c.r, o.g - c.g, o.b - c.b).length_squared()
			if d < best:
				best = d
				idx = i
		if idx < 0:
			idx = id("concrete")
	_imported[key] = idx
	return idx


## First index of a swatch (solid fills).
static func id(name: String) -> int:
	return sets[name][0]


static func ids(name: String) -> PackedByteArray:
	return sets[name]


static func material_of(index: int) -> int:
	return _material_of[index]


static func color_of(index: int) -> Color:
	return palette.get_color(index)


static func _build_materials() -> void:
	opaque_material = ShaderMaterial.new()
	var web := OS.has_feature("web")
	opaque_material.shader = load("res://shaders/voxel_web.gdshader" if web else "res://shaders/voxel.gdshader")
	glass_material = ShaderMaterial.new()
	glass_material.shader = load("res://shaders/voxel_glass_web.gdshader" if web else "res://shaders/voxel_glass.gdshader")
	debris_material = ShaderMaterial.new()
	debris_material.shader = load("res://shaders/debris.gdshader")
