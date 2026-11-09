class_name Build
## Procedural voxel prefab library. Everything in the level is generated from these
## builders, so every wall, prop and tree is real, destructible voxel matter.

const VS := 0.1


static func vol(size: Vector3i) -> VoxelVolume:
	var v := VoxelVolume.new()
	v.setup(size)
	v.set_palette(VoxMat.palette)
	return v


static func place(parent: Node, v: VoxelVolume, bottom_center: Vector3, static_mode: bool, yaw_deg := 0.0, label := "", csize := Vector3i(32, 32, 32)) -> VoxelObject:
	var size := Vector3(v.get_size()) * VS
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var origin := bottom_center - basis * Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	var o := VoxelObject.new()
	o.setup(v, static_mode, csize)
	o.label = label
	o.transform = Transform3D(basis, origin)
	parent.add_child(o)
	return o


## Box spanning [u0,u1) x [y0,y1) x [d0,d1) where depth d runs along `axis` (0 = x, 2 = z).
static func box_uvd(axis: int, u0: int, u1: int, y0: int, y1: int, d0: int, d1: int) -> Array:
	if axis == 2:
		return [Vector3i(u0, y0, d0), Vector3i(u1, y1, d1)]
	return [Vector3i(d0, y0, u0), Vector3i(d1, y1, u1)]


static func fill_uvd(v: VoxelVolume, axis: int, u0: int, u1: int, y0: int, y1: int, d0: int, d1: int, value: int) -> void:
	var b := box_uvd(axis, u0, u1, y0, y1, d0, d1)
	v.fill_box(b[0], b[1], value)


## Window with frame, cross mullions, glass and a sill. outward = -1 if the outside
## of the wall is towards lower depth.
static func window(v: VoxelVolume, axis: int, d0: int, t: int, u0: int, y0: int, w: int, h: int, frame := "wood_dark", outward := -1) -> void:
	fill_uvd(v, axis, u0, u0 + w, y0, y0 + h, d0, d0 + t, 0)
	var mid := d0 + t / 2
	var fr := VoxMat.id(frame)
	fill_uvd(v, axis, u0, u0 + w, y0, y0 + h, mid, mid + 1, fr)
	fill_uvd(v, axis, u0 + 1, u0 + w - 1, y0 + 1, y0 + h - 1, mid, mid + 1, VoxMat.id("glass"))
	if w >= 8:
		fill_uvd(v, axis, u0 + w / 2, u0 + w / 2 + 1, y0, y0 + h, mid, mid + 1, fr)
	if h >= 10:
		fill_uvd(v, axis, u0, u0 + w, y0 + h / 2, y0 + h / 2 + 1, mid, mid + 1, fr)
	var s0 := d0 - 1 if outward < 0 else d0
	var s1 := d0 + t if outward < 0 else d0 + t + 1
	fill_uvd(v, axis, u0 - 1, u0 + w + 1, y0 - 1, y0, s0, s1, VoxMat.id("concrete"))


static func door(v: VoxelVolume, axis: int, d0: int, t: int, u0: int, y0: int, w: int, h: int, lintel := "wood_dark") -> void:
	fill_uvd(v, axis, u0, u0 + w, y0, y0 + h, d0, d0 + t, 0)
	fill_uvd(v, axis, u0 - 1, u0 + w + 1, y0 + h, y0 + h + 2, d0, d0 + t, VoxMat.id(lintel))


## Rectangular walls, outer bounds [x0,x1) x [z0,z1), thickness t.
static func walls(v: VoxelVolume, x0: int, z0: int, x1: int, z1: int, y0: int, y1: int, t: int, kind: String, seed: int) -> void:
	_wall_fill(v, Vector3i(x0, y0, z0), Vector3i(x1, y1, z0 + t), 0, kind, seed)
	_wall_fill(v, Vector3i(x0, y0, z1 - t), Vector3i(x1, y1, z1), 0, kind, seed + 1)
	_wall_fill(v, Vector3i(x0, y0, z0 + t), Vector3i(x0 + t, y1, z1 - t), 2, kind, seed + 2)
	_wall_fill(v, Vector3i(x1 - t, y0, z0 + t), Vector3i(x1, y1, z1 - t), 2, kind, seed + 3)


static func _wall_fill(v: VoxelVolume, a: Vector3i, b: Vector3i, long_axis: int, kind: String, seed: int) -> void:
	match kind:
		"brick":
			v.fill_bricks(a, b, long_axis, 3, 1, VoxMat.ids("brick"), -1, seed)
		"brick_dark":
			v.fill_bricks(a, b, long_axis, 3, 1, VoxMat.ids("brick_dark"), -1, seed)
		"concrete":
			v.fill_box_noise(a, b, VoxMat.ids("concrete"), seed)
		"plaster":
			v.fill_box_noise(a, b, VoxMat.ids("plaster"), seed)
		_:
			# Vertical planks of a wood swatch, e.g. "wood_red".
			v.fill_planks(a, b, 1, long_axis, 2, VoxMat.ids(kind), seed)


## Gable roof with the ridge along x, 45 degree slope, eaves overhanging by `over`.
static func gable_roof(v: VoxelVolume, x0: int, x1: int, z0: int, z1: int, y_base: int, tiles: String, gable: String, over := 3, band := 3, seed := 0) -> int:
	var tile_ids := VoxMat.ids(tiles)
	var k := 0
	var top := y_base
	while true:
		var za := z0 - over + k
		var zb := z1 + over - k
		if zb - za <= 0:
			break
		var y := y_base + k
		top = y
		var bw := mini(band, (zb - za + 1) / 2)
		v.fill_box_noise(Vector3i(x0 - over, y, za), Vector3i(x1 + over, y + 1, za + bw), tile_ids, seed + k)
		v.fill_box_noise(Vector3i(x0 - over, y, zb - bw), Vector3i(x1 + over, y + 1, zb), tile_ids, seed + k + 77)
		# Gable end walls between the two roof planes.
		var ga := maxi(za + bw, z0)
		var gb := mini(zb - bw, z1)
		if gb > ga and gable != "":
			_wall_fill(v, Vector3i(x0, y, ga), Vector3i(x0 + 3, y + 1, gb), 2, gable, seed + 5)
			_wall_fill(v, Vector3i(x1 - 3, y, ga), Vector3i(x1, y + 1, gb), 2, gable, seed + 6)
		k += 1
	return top


## Thick line between two voxel-space points (beams, braces, branches).
static func line(v: VoxelVolume, a: Vector3, b: Vector3, thickness: int, value: int) -> void:
	var steps := ceili(a.distance_to(b) * 1.5) + 1
	var h := thickness / 2
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		v.fill_box(c - Vector3i(h, h, h), c - Vector3i(h, h, h) + Vector3i(thickness, thickness, thickness), value)


static func lamp_light(obj: VoxelObject, voxel: Vector3i, color := Color(1.0, 0.8, 0.55), energy := 2.0, rng := 9.0, shadow := false) -> void:
	var l := LampLight.new()
	l.obj = obj
	l.voxel = voxel
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.position = (Vector3(voxel) + Vector3(0.5, -0.6, 0.5)) * VS
	obj.add_child(l)


# ================================================================== buildings

## Two storey brick house with plaster interior, wooden floors, stairs and a tiled roof.
static func brick_house(seed: int) -> VoxelVolume:
	var M := 3                        # margin for sills and eaves
	var W := 120
	var D := 90
	var v := vol(Vector3i(W + M * 2, 112, D + M * 2))
	var x0 := M
	var z0 := M
	var x1 := M + W
	var z1 := M + D
	var t := 4
	v.fill_box_noise(Vector3i(x0 - 1, 0, z0 - 1), Vector3i(x1 + 1, 3, z1 + 1), VoxMat.ids("concrete"), seed)
	walls(v, x0, z0, x1, z1, 3, 64, t - 1, "brick", seed)
	# plaster lining
	walls(v, x0 + t - 1, z0 + t - 1, x1 - t + 1, z1 - t + 1, 3, 64, 1, "plaster", seed + 3)
	# decorative dark brick bands
	walls(v, x0, z0, x1, z1, 32, 34, 3, "brick_dark", seed + 9)
	walls(v, x0, z0, x1, z1, 62, 64, 3, "brick_dark", seed + 10)
	# floors
	v.fill_planks(Vector3i(x0 + t, 32, z0 + t), Vector3i(x1 - t, 35, z1 - t), 0, 2, 3, VoxMat.ids("wood"), seed)
	v.fill_planks(Vector3i(x0 + t, 62, z0 + t), Vector3i(x1 - t, 65, z1 - t), 0, 2, 3, VoxMat.ids("wood_light"), seed + 1)
	# beams under the first floor
	for bx in range(x0 + 14, x1 - 6, 18):
		v.fill_box(Vector3i(bx, 29, z0 + t), Vector3i(bx + 3, 32, z1 - t), VoxMat.id("wood_dark"))
	# stair well + stairs along z
	var sx0 := x1 - t - 22
	var sx1 := x1 - t - 4
	v.fill_box(Vector3i(sx0, 29, z1 - t - 38), Vector3i(sx1, 35, z1 - t - 2), 0)
	for i in 16:
		var y := 3 + i * 2
		var zf := z1 - t - 2 - 36 + i * 2
		v.fill_planks(Vector3i(sx0, y, zf), Vector3i(sx1, y + 2, zf + 3), 0, 1, 1, VoxMat.ids("wood_dark"), seed + i)
	# interior wall with door on the ground floor and upstairs
	v.fill_box_noise(Vector3i(x0 + 50, 3, z0 + t), Vector3i(x0 + 52, 32, z1 - t), VoxMat.ids("plaster_blue"), seed)
	v.fill_box(Vector3i(x0 + 50, 3, z0 + 40), Vector3i(x0 + 52, 24, z0 + 50), 0)
	v.fill_box_noise(Vector3i(x0 + 60, 35, z0 + t), Vector3i(x0 + 62, 62, z1 - t), VoxMat.ids("plaster_green"), seed)
	v.fill_box(Vector3i(x0 + 60, 35, z0 + 20), Vector3i(x0 + 62, 56, z0 + 30), 0)
	# windows (front/back along x, sides along z)
	for u in [x0 + 10, x0 + 34, x0 + 72, x0 + 96]:
		window(v, 2, z0, 4, u, 11, 14, 15, "wood_dark", -1)
		window(v, 2, z0, 4, u, 41, 14, 15, "wood_dark", -1)
		window(v, 2, z1 - 4, 4, u, 41, 14, 15, "wood_dark", 1)
	for u in [x0 + 10, x0 + 34]:
		window(v, 2, z1 - 4, 4, u, 11, 14, 15, "wood_dark", 1)
	for u in [z0 + 14, z0 + 60]:
		window(v, 0, x0, 4, u, 11, 14, 15, "wood_dark", -1)
		window(v, 0, x0, 4, u, 41, 14, 15, "wood_dark", -1)
		window(v, 0, x1 - 4, 4, u, 41, 14, 15, "wood_dark", 1)
	door(v, 2, z0, t, x0 + 54, 3, 11, 22)
	door(v, 0, x1 - t, t, z0 + 20, 3, 10, 22)
	var top := gable_roof(v, x0, x1, z0, z1, 64, "roof_tile", "brick", M, 3, seed)
	# chimney
	v.fill_bricks(Vector3i(x0 + 16, 60, z0 + 58), Vector3i(x0 + 24, mini(top + 8, 111), z0 + 66), 0, 3, 1, VoxMat.ids("brick_dark"), -1, seed)
	v.fill_box(Vector3i(x0 + 18, 64, z0 + 60), Vector3i(x0 + 22, mini(top + 8, 111), z0 + 64), 0)
	# ceiling lamps
	v.fill_box(Vector3i(x0 + 28, 31, z0 + 44), Vector3i(x0 + 31, 32, z0 + 47), VoxMat.id("lamp"))
	v.fill_box(Vector3i(x0 + 88, 31, z0 + 30), Vector3i(x0 + 91, 32, z0 + 33), VoxMat.id("lamp"))
	v.fill_box(Vector3i(x0 + 70, 61, z0 + 44), Vector3i(x0 + 73, 62, z0 + 47), VoxMat.id("lamp"))
	return v


static func house_lamps(obj: VoxelObject) -> void:
	lamp_light(obj, Vector3i(3 + 29, 31, 3 + 45), Color(1.0, 0.82, 0.6), 2.2, 10.0, true)
	lamp_light(obj, Vector3i(3 + 89, 31, 3 + 31), Color(1.0, 0.82, 0.6), 2.0, 9.0)
	lamp_light(obj, Vector3i(3 + 71, 61, 3 + 45), Color(1.0, 0.82, 0.6), 2.0, 9.0)


## Red plank barn with corner posts, big door, loft and plank roof.
static func barn(seed: int) -> VoxelVolume:
	var M := 3
	var W := 80
	var D := 60
	var v := vol(Vector3i(W + M * 2, 80, D + M * 2))
	var x0 := M
	var z0 := M
	var x1 := M + W
	var z1 := M + D
	v.fill_box_noise(Vector3i(x0, 0, z0), Vector3i(x1, 2, z1), VoxMat.ids("concrete_dark"), seed)
	walls(v, x0, z0, x1, z1, 2, 44, 2, "wood_red", seed)
	for p in [Vector2i(x0, z0), Vector2i(x1 - 3, z0), Vector2i(x0, z1 - 3), Vector2i(x1 - 3, z1 - 3), Vector2i(x0 + 38, z0), Vector2i(x0 + 38, z1 - 3)]:
		v.fill_box(Vector3i(p.x, 2, p.y), Vector3i(p.x + 3, 44, p.y + 3), VoxMat.id("wood_dark"))
	walls(v, x0, z0, x1, z1, 42, 44, 3, "wood_dark", seed + 4)
	# loft over the back half
	v.fill_planks(Vector3i(x0 + 2, 26, z0 + 30), Vector3i(x1 - 2, 28, z1 - 2), 0, 2, 3, VoxMat.ids("wood"), seed)
	for bx in range(x0 + 10, x1 - 5, 16):
		v.fill_box(Vector3i(bx, 2, z0 + 30), Vector3i(bx + 2, 26, z0 + 32), VoxMat.id("wood_dark"))
	# big front door, back door, windows
	door(v, 2, z0, 2, x0 + 14, 2, 22, 30, "wood_dark")
	v.fill_planks(Vector3i(x0 + 40, 2, z0 - 1), Vector3i(x0 + 52, 30, z0), 1, 0, 2, VoxMat.ids("wood_grey"), seed)
	door(v, 2, z1 - 2, 2, x0 + 54, 2, 10, 22, "wood_dark")
	for u in [z0 + 10, z0 + 38]:
		window(v, 0, x0, 2, u, 14, 12, 12, "wood_light", -1)
		window(v, 0, x1 - 2, 2, u, 14, 12, 12, "wood_light", 1)
	window(v, 2, z1 - 2, 2, x0 + 18, 30, 10, 10, "wood_light", 1)
	gable_roof(v, x0, x1, z0, z1, 44, "wood_dark", "wood_red", M, 3, seed)
	v.fill_box(Vector3i(x0 + 20, 40, z0 + 2), Vector3i(x0 + 22, 41, z0 + 4), VoxMat.id("lamp"))
	return v


## Square brick tower with wooden floors and a crenellated top.
static func brick_tower(seed: int) -> VoxelVolume:
	var S := 30
	var H := 150
	var v := vol(Vector3i(S + 4, H + 6, S + 4))
	v.fill_box_noise(Vector3i(0, 0, 0), Vector3i(S + 4, 4, S + 4), VoxMat.ids("concrete"), seed)
	walls(v, 2, 2, S + 2, S + 2, 4, H, 3, "brick", seed)
	for y in range(30, H - 10, 30):
		v.fill_planks(Vector3i(5, y, 5), Vector3i(S - 1, y + 2, S - 1), 0, 2, 3, VoxMat.ids("wood"), seed + y)
		walls(v, 2, 2, S + 2, S + 2, y - 2, y, 3, "brick_dark", seed + y)
		window(v, 2, 2, 3, 12, y + 8, 8, 12, "wood_dark", -1)
		window(v, 0, S - 1, 3, 12, y + 8, 8, 12, "wood_dark", 1)
	door(v, 2, 2, 3, 11, 4, 10, 20)
	# crown + crenellations
	walls(v, 1, 1, S + 3, S + 3, H, H + 2, 4, "brick_dark", seed)
	for i in range(1, S + 3, 6):
		v.fill_box(Vector3i(i, H + 2, 1), Vector3i(i + 3, H + 5, 4), VoxMat.id("brick_dark"))
		v.fill_box(Vector3i(i, H + 2, S), Vector3i(i + 3, H + 5, S + 3), VoxMat.id("brick_dark"))
		v.fill_box(Vector3i(1, H + 2, i), Vector3i(4, H + 5, i + 3), VoxMat.id("brick_dark"))
		v.fill_box(Vector3i(S, H + 2, i), Vector3i(S + 3, H + 5, i + 3), VoxMat.id("brick_dark"))
	# spray-painted demolition X like in the references
	var paint := VoxMat.paint_remap
	for k in 24:
		for d in 2:
			for off in [Vector3i(4 + k, 60 + k + d, 1), Vector3i(27 - k, 60 + k + d, 1)]:
				var cur := v.get_voxel(off + Vector3i(0, 0, 1))
				if cur != 0:
					v.set_voxel(off + Vector3i(0, 0, 1), paint[cur])
	return v


## Flat-roof concrete garage with a sheet metal door and a shelf.
static func garage(seed: int) -> VoxelVolume:
	var W := 70
	var D := 60
	var H := 34
	var v := vol(Vector3i(W + 2, H + 4, D + 2))
	v.fill_box_noise(Vector3i(1, 0, 1), Vector3i(W + 1, 2, D + 1), VoxMat.ids("concrete_dark"), seed)
	walls(v, 1, 1, W + 1, D + 1, 2, H, 4, "concrete", seed)
	v.fill_box_noise(Vector3i(0, H, 0), Vector3i(W + 2, H + 4, D + 2), VoxMat.ids("concrete"), seed + 1)
	for bx in range(10, W - 5, 15):
		v.fill_box(Vector3i(bx, H - 3, 5), Vector3i(bx + 3, H, D - 3), VoxMat.id("metal_rust"))
	door(v, 2, 1, 4, 12, 2, 40, 26, "concrete_dark")
	# roll door hanging half open (thin metal, cuttable with the torch)
	v.fill_planks(Vector3i(12, 16, 2), Vector3i(52, 28, 3), 0, 1, 2, VoxMat.ids("metal_white"), seed)
	window(v, 0, W - 3, 4, 20, 14, 16, 10, "metal_dark", 1)
	window(v, 2, D - 3, 4, 30, 14, 16, 10, "metal_dark", 1)
	# shelf along the back wall
	for y in [8, 16, 24]:
		v.fill_box(Vector3i(8, y, D - 10), Vector3i(48, y + 1, D - 3), VoxMat.id("wood"))
	for x in [8, 27, 47]:
		v.fill_box(Vector3i(x, 2, D - 10), Vector3i(x + 1, 25, D - 3), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(34, H - 1, 30), Vector3i(37, H, 33), VoxMat.id("lamp"))
	return v


## Glass greenhouse with a white metal frame and planters.
static func greenhouse(seed: int) -> VoxelVolume:
	var W := 50
	var D := 34
	var v := vol(Vector3i(W + 2, 50, D + 2))
	v.fill_box_noise(Vector3i(1, 0, 1), Vector3i(W + 1, 2, D + 1), VoxMat.ids("concrete"), seed)
	var g := VoxMat.id("glass")
	var f := VoxMat.id("metal_white")
	v.fill_box(Vector3i(1, 2, 1), Vector3i(W + 1, 26, D + 1), g)
	v.fill_box(Vector3i(2, 2, 2), Vector3i(W, 26, D), 0)
	for x in range(1, W + 1, 7):
		v.fill_box(Vector3i(x, 2, 1), Vector3i(x + 1, 26, 2), f)
		v.fill_box(Vector3i(x, 2, D), Vector3i(x + 1, 26, D + 1), f)
	for z in range(1, D + 1, 7):
		v.fill_box(Vector3i(1, 2, z), Vector3i(2, 26, z + 1), f)
		v.fill_box(Vector3i(W, 2, z), Vector3i(W + 1, 26, z + 1), f)
	v.fill_box(Vector3i(1, 25, 1), Vector3i(W + 1, 26, D + 1), f)
	v.fill_box(Vector3i(2, 25, 2), Vector3i(W, 26, D), 0)
	# glass gable roof with frame ribs
	for k in 18:
		var za := 1 + k
		var zb := D + 1 - k
		if zb - za <= 1:
			break
		v.fill_box(Vector3i(1, 26 + k, za), Vector3i(W + 1, 27 + k, za + 1), g)
		v.fill_box(Vector3i(1, 26 + k, zb - 1), Vector3i(W + 1, 27 + k, zb), g)
		v.fill_box(Vector3i(1, 26 + k, za), Vector3i(2, 27 + k, zb), g)
		v.fill_box(Vector3i(W, 26 + k, za), Vector3i(W + 1, 27 + k, zb), g)
		for x in range(1, W + 1, 7):
			v.fill_box(Vector3i(x, 26 + k, za), Vector3i(x + 1, 27 + k, za + 1), f)
			v.fill_box(Vector3i(x, 26 + k, zb - 1), Vector3i(x + 1, 27 + k, zb), f)
	door(v, 2, 1, 1, 21, 2, 8, 18, "metal_white")
	# planters with plants
	for row in [6, D - 10]:
		v.fill_planks(Vector3i(6, 2, row), Vector3i(W - 4, 7, row + 5), 0, 1, 2, VoxMat.ids("wood_grey"), seed)
		v.fill_box_noise(Vector3i(7, 6, row + 1), Vector3i(W - 5, 7, row + 4), VoxMat.ids("dirt"), seed)
		for px in range(9, W - 6, 6):
			v.fill_ellipsoid_noise(Vector3(px, 10, row + 2.5), Vector3(3, 4, 2.5), VoxMat.ids("foliage"), 0.85, 0.3, seed + px)
	return v


## Lattice power pylon with cross arms.
static func pylon(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(100, 168, 44))
	var m := VoxMat.id("metal")
	var md := VoxMat.id("metal_dark")
	var cx := 50.0
	var cz := 22.0
	var base := 18.0
	var top := 5.0
	var H := 150.0
	v.fill_box_noise(Vector3i(28, 0, 0), Vector3i(72, 3, 44), VoxMat.ids("concrete"), seed)
	for sxn in [-1.0, 1.0]:
		for szn in [-1.0, 1.0]:
			var a := Vector3(cx + sxn * base, 3, cz + szn * base)
			var b := Vector3(cx + sxn * top, H, cz + szn * top)
			line(v, a, b, 3, md)
	# X bracing on each face
	var levels := [3.0, 28.0, 52.0, 74.0, 94.0, 112.0, 128.0, 142.0, H]
	for li in levels.size() - 1:
		var y0: float = levels[li]
		var y1: float = levels[li + 1]
		var w0 := lerpf(base, top, (y0 - 3.0) / (H - 3.0))
		var w1 := lerpf(base, top, (y1 - 3.0) / (H - 3.0))
		for face in 4:
			var ax := face % 2 == 0
			var s := -1.0 if face < 2 else 1.0
			var p00: Vector3
			var p01: Vector3
			var p10: Vector3
			var p11: Vector3
			if ax:
				p00 = Vector3(cx - w0, y0, cz + s * w0)
				p01 = Vector3(cx + w0, y0, cz + s * w0)
				p10 = Vector3(cx - w1, y1, cz + s * w1)
				p11 = Vector3(cx + w1, y1, cz + s * w1)
			else:
				p00 = Vector3(cx + s * w0, y0, cz - w0)
				p01 = Vector3(cx + s * w0, y0, cz + w0)
				p10 = Vector3(cx + s * w1, y1, cz - w1)
				p11 = Vector3(cx + s * w1, y1, cz + w1)
			line(v, p00, p11, 2, m)
			line(v, p01, p10, 2, m)
			line(v, p10, p11, 2, m)
	# cross arms with insulators
	for ay in [118, 140]:
		var span := 46 if ay == 118 else 36
		line(v, Vector3(cx - span, ay, cz - 2), Vector3(cx + span, ay, cz - 2), 3, md)
		line(v, Vector3(cx - span, ay, cz + 2), Vector3(cx + span, ay, cz + 2), 3, md)
		for sgn in [-1, 1]:
			line(v, Vector3(cx + sgn * span, ay, cz), Vector3(cx + sgn * 8, ay + 12, cz), 2, m)
			var ix := int(cx + sgn * (span - 3))
			v.fill_box(Vector3i(ix - 1, ay - 8, int(cz) - 1), Vector3i(ix + 2, ay - 1, int(cz) + 2), VoxMat.id("plastic_white"))
	return v


# ================================================================== nature

static func pine_tree(seed: int, height := 80, r := 16, trunk := 1.8) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := vol(Vector3i(r * 2 + 4, height + 8, r * 2 + 4))
	var c := Vector3(r + 2, 0, r + 2)
	v.fill_cylinder(c, trunk, height - 6, 1, VoxMat.id("wood_dark"))
	var y := height * 0.17
	var layer := 0
	while y < height:
		var t := (y - height * 0.17) / (height * 0.83)
		var rad := lerpf(float(r), 2.0, t) * rng.randf_range(0.85, 1.05)
		var k := float(r) / 16.0
		v.fill_ellipsoid_noise(Vector3(c.x, y + 3.0 * k, c.z), Vector3(rad, 4.5 * k, rad), VoxMat.ids("pine"), 0.985, 0.35, seed + layer)
		y += lerpf(7.0, 5.0, t) * k
		layer += 1
	v.fill_ellipsoid_noise(Vector3(c.x, height + 2, c.z), Vector3(2.5, 5, 2.5) * maxf(float(r) / 16.0, 0.5), VoxMat.ids("pine"), 0.98, 0.2, seed + 99)
	return v


static func leafy_tree(seed: int) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := vol(Vector3i(44, 64, 44))
	var c := Vector3(22, 0, 22)
	v.fill_cylinder(c, 2.4, 30, 1, VoxMat.id("wood_dark"))
	var crown := Vector3(22, 42, 22)
	for b in 4:
		var ang := b * TAU / 4.0 + rng.randf_range(-0.4, 0.4)
		var tip := crown + Vector3(cos(ang) * 11.0, rng.randf_range(-4, 6), sin(ang) * 11.0)
		line(v, Vector3(22, 26, 22), tip, 2, VoxMat.id("wood_dark"))
		v.fill_ellipsoid_noise(tip, Vector3(9, 7, 9), VoxMat.ids("foliage"), 0.9, 0.4, seed + b)
	v.fill_ellipsoid_noise(crown + Vector3(0, 6, 0), Vector3(12, 9, 12), VoxMat.ids("foliage"), 0.9, 0.4, seed + 9)
	return v


static func bush(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(16, 10, 16))
	v.fill_ellipsoid_noise(Vector3(8, 3, 8), Vector3(7, 6, 7), VoxMat.ids("foliage"), 0.92, 0.45, seed)
	return v


# ================================================================== props

static func crate(n: int, seed: int) -> VoxelVolume:
	var v := vol(Vector3i(n, n, n))
	v.fill_planks(Vector3i.ZERO, Vector3i(n, n, n), 0, 1, 2, VoxMat.ids("wood_light"), seed)
	v.fill_box(Vector3i(1, 1, 1), Vector3i(n - 1, n - 1, n - 1), 0)
	# dark edge frame
	var d := VoxMat.id("wood")
	for a in [Vector3i(0, 0, 0), Vector3i(n - 1, 0, 0), Vector3i(0, 0, n - 1), Vector3i(n - 1, 0, n - 1)]:
		v.fill_box(a, a + Vector3i(1, n, 1), d)
	for a in [Vector3i(0, 0, 0), Vector3i(0, n - 1, 0), Vector3i(0, 0, n - 1), Vector3i(0, n - 1, n - 1)]:
		v.fill_box(a, a + Vector3i(n, 1, 1), d)
	for a in [Vector3i(0, 0, 0), Vector3i(n - 1, 0, 0), Vector3i(0, n - 1, 0), Vector3i(n - 1, n - 1, 0)]:
		v.fill_box(a, a + Vector3i(1, 1, n), d)
	return v


static func barrel(color: String) -> VoxelVolume:
	var v := vol(Vector3i(7, 10, 7))
	var c := Vector3(3.5, 0, 3.5)
	v.fill_cylinder(c, 3.3, 10, 1, VoxMat.id(color))
	v.fill_cylinder(Vector3(3.5, 1, 3.5), 2.3, 8, 1, 0)
	v.fill_cylinder(Vector3(3.5, 3, 3.5), 3.4, 1, 1, VoxMat.id("metal_dark"))
	v.fill_cylinder(Vector3(3.5, 7, 3.5), 3.4, 1, 1, VoxMat.id("metal_dark"))
	return v


## Horizontal propane tank on two feet (explosive).
static func propane_tank() -> VoxelVolume:
	var L := 26
	var v := vol(Vector3i(L, 11, 10))
	var red := VoxMat.id("metal_red")
	v.fill_cylinder(Vector3(3, 6, 5), 4.3, L - 6, 0, red)
	v.fill_sphere(Vector3(3.5, 6, 5), 4.3, red)
	v.fill_sphere(Vector3(L - 3.5, 6, 5), 4.3, red)
	v.fill_cylinder(Vector3(3, 6, 5), 3.2, L - 6, 0, 0)
	v.fill_box(Vector3i(5, 0, 3), Vector3i(7, 3, 7), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(L - 7, 0, 3), Vector3i(L - 5, 3, 7), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(L / 2 - 1, 10, 4), Vector3i(L / 2 + 2, 11, 6), VoxMat.id("metal"))
	return v


static func container(color: String, seed: int) -> VoxelVolume:
	var L := 60
	var H := 26
	var W := 24
	var v := vol(Vector3i(L, H, W))
	var ids := VoxMat.ids(color)
	v.fill_planks(Vector3i.ZERO, Vector3i(L, H, W), 1, 0, 2, ids, seed)
	v.fill_box(Vector3i(1, 1, 1), Vector3i(L - 1, H - 1, W - 1), 0)
	var d := VoxMat.id("metal_dark")
	for a in [Vector3i(0, 0, 0), Vector3i(L - 2, 0, 0), Vector3i(0, 0, W - 2), Vector3i(L - 2, 0, W - 2)]:
		v.fill_box(a, a + Vector3i(2, H, 2), d)
	v.fill_box(Vector3i(0, 0, 0), Vector3i(L, 2, W), d)
	v.fill_box(Vector3i(2, 0, 2), Vector3i(L - 2, 1, W - 2), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(0, H - 1, 0), Vector3i(L, H, W), ids[0])
	return v


static func car(color: String, seed: int) -> VoxelVolume:
	var L := 42
	var W := 19
	var v := vol(Vector3i(L, 16, W))
	var body := VoxMat.ids(color)
	var g := VoxMat.id("glass")
	# lower body shell
	v.fill_box_noise(Vector3i(0, 3, 0), Vector3i(L, 9, W), body, seed)
	v.fill_box(Vector3i(1, 4, 1), Vector3i(L - 1, 9, W - 1), 0)
	v.fill_box(Vector3i(1, 3, 1), Vector3i(L - 1, 4, W - 1), VoxMat.id("metal_dark"))
	# cabin
	v.fill_box(Vector3i(11, 9, 0), Vector3i(31, 15, W), g)
	v.fill_box(Vector3i(12, 9, 1), Vector3i(30, 14, W - 1), 0)
	v.fill_box_noise(Vector3i(11, 15, 0), Vector3i(31, 16, W), body, seed + 1)
	for px in [11, 20, 30]:
		v.fill_box(Vector3i(px, 9, 0), Vector3i(px + 1, 15, W), body[0])
		v.fill_box(Vector3i(px, 9, 1), Vector3i(px + 1, 15, W - 1), 0)
	# hood + trunk tops
	v.fill_box_noise(Vector3i(0, 8, 0), Vector3i(11, 9, W), body, seed + 2)
	v.fill_box_noise(Vector3i(31, 8, 0), Vector3i(L, 9, W), body, seed + 3)
	# seats
	v.fill_box(Vector3i(14, 4, 3), Vector3i(17, 10, 8), VoxMat.id("plastic_blue"))
	v.fill_box(Vector3i(14, 4, 11), Vector3i(17, 10, 16), VoxMat.id("plastic_blue"))
	# lights and bumpers
	v.fill_box(Vector3i(0, 6, 2), Vector3i(1, 8, 5), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 6, W - 5), Vector3i(1, 8, W - 2), VoxMat.id("lamp"))
	v.fill_box(Vector3i(L - 1, 6, 2), Vector3i(L, 8, 5), VoxMat.id("metal_red"))
	v.fill_box(Vector3i(L - 1, 6, W - 5), Vector3i(L, 8, W - 2), VoxMat.id("metal_red"))
	v.fill_box(Vector3i(0, 3, 0), Vector3i(1, 5, W), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(L - 1, 3, 0), Vector3i(L, 5, W), VoxMat.id("metal_dark"))
	# wheels
	for wx in [7, L - 8]:
		for wz in [0, W - 3]:
			v.fill_cylinder(Vector3(wx, 3.5, wz), 3.4, 3, 2, VoxMat.id("rubber"))
			v.fill_cylinder(Vector3(wx, 3.5, wz), 1.5, 3, 2, VoxMat.id("metal"))
	return v


## Wheel hub centers of car() in object space, front wheels first.
static func car_hubs() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for wx in [7, 34]:
		for wz in [1.5, 17.5]:
			out.append(Vector3(wx, 3.5, wz) * VS)
	return out


static func excavator(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(90, 50, 34))
	var y := VoxMat.ids("metal_yellow")
	var dk := VoxMat.id("metal_dark")
	# tracks
	for tz in [0, 24]:
		v.fill_box(Vector3i(2, 0, tz), Vector3i(42, 7, tz + 10), dk)
		v.fill_box(Vector3i(4, 2, tz + 1), Vector3i(40, 6, tz + 9), VoxMat.id("metal"))
		for i in range(3, 42, 4):
			v.fill_box(Vector3i(i, 0, tz), Vector3i(i + 1, 1, tz + 10), VoxMat.id("rubber"))
	v.fill_box(Vector3i(14, 7, 8), Vector3i(30, 10, 26), dk)
	# house + counterweight
	v.fill_box_noise(Vector3i(4, 10, 4), Vector3i(40, 20, 30), y, seed)
	v.fill_box(Vector3i(5, 11, 5), Vector3i(39, 19, 29), 0)
	v.fill_box_noise(Vector3i(0, 10, 4), Vector3i(6, 20, 30), VoxMat.ids("metal_dark"), seed)
	# cabin
	v.fill_box(Vector3i(26, 20, 4), Vector3i(40, 34, 16), VoxMat.id("glass"))
	v.fill_box(Vector3i(27, 20, 5), Vector3i(39, 33, 15), 0)
	v.fill_box_noise(Vector3i(26, 34, 4), Vector3i(40, 35, 16), y, seed + 1)
	for p in [Vector2i(26, 4), Vector2i(39, 4), Vector2i(26, 15), Vector2i(39, 15)]:
		v.fill_box(Vector3i(p.x, 20, p.y), Vector3i(p.x + 1, 34, p.y + 1), y[0])
	v.fill_box(Vector3i(30, 20, 8), Vector3i(34, 25, 12), VoxMat.id("rubber"))
	# boom and stick
	for k in 3:
		line(v, Vector3(36, 18, 20 + k), Vector3(62, 44, 20 + k), 4, y[0])
	for k in 3:
		line(v, Vector3(62, 44, 20 + k), Vector3(80, 16, 20 + k), 3, y[0])
	line(v, Vector3(46, 28, 18), Vector3(58, 40, 18), 2, VoxMat.id("metal"))
	# bucket
	v.fill_box(Vector3i(76, 4, 15), Vector3i(88, 16, 29), dk)
	v.fill_box(Vector3i(77, 6, 16), Vector3i(87, 16, 28), 0)
	for tx in range(77, 88, 3):
		v.fill_box(Vector3i(tx, 2, 16), Vector3i(tx + 1, 4, 28), VoxMat.id("metal"))
	return v


static func table(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(16, 8, 10))
	v.fill_planks(Vector3i(0, 7, 0), Vector3i(16, 8, 10), 0, 2, 2, VoxMat.ids("wood"), seed)
	for p in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 9), Vector2i(15, 9)]:
		v.fill_box(Vector3i(p.x, 0, p.y), Vector3i(p.x + 1, 7, p.y + 1), VoxMat.id("wood_dark"))
	return v


static func chair(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(5, 10, 5))
	v.fill_box(Vector3i(0, 4, 0), Vector3i(5, 5, 5), VoxMat.id("wood_light" if seed % 2 == 0 else "wood"))
	v.fill_box(Vector3i(0, 5, 4), Vector3i(5, 10, 5), VoxMat.id("wood"))
	for p in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)]:
		v.fill_box(Vector3i(p.x, 0, p.y), Vector3i(p.x + 1, 4, p.y + 1), VoxMat.id("wood_dark"))
	return v


static func shelf(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(18, 20, 5))
	for y in [0, 6, 12, 19]:
		v.fill_planks(Vector3i(0, y, 0), Vector3i(18, y + 1, 5), 0, 2, 2, VoxMat.ids("wood_grey"), seed + y)
	for x in [0, 17]:
		v.fill_box(Vector3i(x, 0, 0), Vector3i(x + 1, 20, 5), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(0, 0, 4), Vector3i(18, 20, 5), VoxMat.id("wood_grey"))
	# a few colored boxes and jars on the shelves
	v.fill_box(Vector3i(2, 1, 1), Vector3i(6, 4, 4), VoxMat.id("plastic_orange"))
	v.fill_box(Vector3i(10, 7, 1), Vector3i(13, 10, 3), VoxMat.id("plastic_blue"))
	v.fill_box(Vector3i(5, 13, 1), Vector3i(7, 16, 3), VoxMat.id("glass"))
	return v


static func plank(len: int, seed: int) -> VoxelVolume:
	var v := vol(Vector3i(len, 2, 4))
	v.fill_planks(Vector3i.ZERO, Vector3i(len, 2, 4), 0, 2, 4, VoxMat.ids("wood_light"), seed)
	return v


static func concrete_block(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(20, 8, 6))
	v.fill_box_noise(Vector3i(0, 0, 0), Vector3i(20, 8, 6), VoxMat.ids("concrete"), seed)
	v.fill_box(Vector3i(0, 5, 0), Vector3i(20, 8, 1), 0)
	v.fill_box(Vector3i(0, 5, 5), Vector3i(20, 8, 6), 0)
	v.fill_box(Vector3i(0, 0, 0), Vector3i(20, 1, 6), VoxMat.id("concrete_dark"))
	return v


static func brick_pile(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(9, 5, 6))
	v.fill_bricks(Vector3i.ZERO, Vector3i(9, 5, 6), 0, 3, 1, VoxMat.ids("brick"), -1, seed)
	return v


static func pallet(seed: int) -> VoxelVolume:
	var v := vol(Vector3i(12, 2, 10))
	v.fill_planks(Vector3i(0, 1, 0), Vector3i(12, 2, 10), 0, 2, 2, VoxMat.ids("wood_grey"), seed)
	for z in [0, 4, 8]:
		v.fill_box(Vector3i(0, 0, z), Vector3i(12, 1, z + 2), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(0, 1, 2), Vector3i(12, 2, 3), 0)
	v.fill_box(Vector3i(0, 1, 7), Vector3i(12, 2, 8), 0)
	return v


static func picket_fence(length: int, seed: int) -> VoxelVolume:
	var v := vol(Vector3i(length, 13, 2))
	var w := VoxMat.ids("wood_grey")
	for x in range(0, length, 3):
		v.fill_box_noise(Vector3i(x, 0, 1), Vector3i(x + 2, 11 + (x / 3) % 2, 2), w, seed + x)
	v.fill_box(Vector3i(0, 3, 0), Vector3i(length, 4, 1), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(0, 8, 0), Vector3i(length, 9, 1), VoxMat.id("wood_dark"))
	for x in range(0, length, 20):
		v.fill_box(Vector3i(x, 0, 0), Vector3i(x + 2, 13, 2), VoxMat.id("wood_dark"))
	return v


static func brick_wall(length: int, height: int, seed: int) -> VoxelVolume:
	var v := vol(Vector3i(length, height + 1, 4))
	v.fill_bricks(Vector3i(0, 0, 0), Vector3i(length, height, 4), 0, 3, 1, VoxMat.ids("brick"), -1, seed)
	v.fill_box_noise(Vector3i(0, height, 0), Vector3i(length, height + 1, 4), VoxMat.ids("concrete"), seed)
	for x in range(0, length, 24):
		v.fill_bricks(Vector3i(x, 0, 0), Vector3i(x + 4, height + 1, 4), 0, 2, 1, VoxMat.ids("brick_dark"), -1, seed)
	return v


static func lamp_post() -> VoxelVolume:
	var v := vol(Vector3i(14, 62, 4))
	v.fill_box(Vector3i(1, 0, 1), Vector3i(3, 60, 3), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(0, 0, 0), Vector3i(4, 3, 4), VoxMat.id("concrete"))
	v.fill_box(Vector3i(1, 58, 1), Vector3i(13, 60, 3), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(9, 56, 0), Vector3i(13, 58, 4), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(10, 55, 1), Vector3i(12, 56, 3), VoxMat.id("lamp"))
	return v
