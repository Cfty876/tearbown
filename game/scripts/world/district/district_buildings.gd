class_name DistrictBuildings
## Buildings of the American town map. Every builder returns a Dictionary
## with the voxel volume plus metadata the level uses for decoration
## (entrances for benches, lamp voxels for lights, interior box for occlusion).
## Volume axes: x along the building, y up, z across; "front" = entrance side.

const VS := 0.1

# Five storey brick walk-up apartment block, all sizes in voxels.
const SEC := 150      # section (one entrance) length
const BAY := 30       # window module
const DEPTH := 120
const FH := 28        # storey height
const PL := 10        # plinth / basement height
const FLOORS := 5
const MX := 4
const MF := 16        # front margin (awnings, steps)
const MB := 14        # back margin (fire escapes)
const T := 3          # wall thickness

const CURTAINS := ["curtain_red", "curtain_green", "curtain_beige"]
const AWNINGS := ["awning_green", "awning_maroon", "awning_navy"]


static func apartment_block(sections: int, seed: int, brick := "brick") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var L := sections * SEC
	var top := PL + FLOORS * FH
	var v := Build.vol(Vector3i(L + MX * 2, top + 40, MF + DEPTH + MB))
	var x0 := MX
	var x1 := MX + L
	var z0 := MF
	var z1 := MF + DEPTH
	var con := VoxMat.ids("concrete")
	var stone := VoxMat.id("stone")
	var lamps: Array[Vector3i] = []
	var entrances: Array[Vector3] = []
	var awning := VoxMat.id(AWNINGS[seed % AWNINGS.size()])

	# Stone base, brick walls, slabs, roof, cornice and parapet.
	_ring(v, x0, z0, x1, z1, 0, PL, T, VoxMat.id("concrete_dark"))
	v.fill_box_noise(Vector3i(x0 + T, PL - 3, z0 + T), Vector3i(x1 - T, PL, z1 - T), con, seed)
	_brick_ring(v, x0, z0, x1, z1, PL, top, T, brick, seed)
	for f in range(1, FLOORS):
		var y := PL + f * FH
		v.fill_box_noise(Vector3i(x0 + T, y - 3, z0 + T), Vector3i(x1 - T, y, z1 - T), con, seed + f)
	v.fill_box_noise(Vector3i(x0, top, z0), Vector3i(x1, top + 3, z1), VoxMat.ids("roof_bitumen"), seed)
	# Belt course above the ground floor and a projecting cornice.
	_ring(v, x0 - 1, z0 - 1, x1 + 1, z1 + 1, PL + FH - 2, PL + FH, 1, stone)
	_ring(v, x0 - 2, z0 - 2, x1 + 2, z1 + 2, top, top + 3, 2, stone)
	_brick_ring(v, x0, z0, x1, z1, top + 3, top + 7, 2, brick, seed + 3)
	v.fill_box(Vector3i(x0, top + 7, z0), Vector3i(x1, top + 8, z0 + 2), stone)
	v.fill_box(Vector3i(x0, top + 7, z1 - 2), Vector3i(x1, top + 8, z1), stone)

	# Interior: longitudinal bearing wall and transverse walls.
	var zm := z0 + 62
	v.fill_box_noise(Vector3i(x0 + T, PL, zm), Vector3i(x1 - T, top, zm + 3), con, seed + 7)
	for k in range(1, sections * 5):
		var x := x0 + k * BAY
		var heavy := k % 5 == 0 or k % 5 == 2 or k % 5 == 3
		v.fill_box_noise(Vector3i(x - 1, PL, z0 + T), Vector3i(x + 1, top, z1 - T), con if heavy else VoxMat.ids("plaster"), seed + k)

	var zf := z0 + T
	var zi := zf + 48
	for s in sections:
		var sx := x0 + s * SEC
		var bx := sx + 2 * BAY       # stair bay
		var bxc := bx + BAY / 2
		for f in FLOORS:
			var fy := PL + f * FH
			for b in 5:
				var x := sx + b * BAY
				# Doors through the bearing wall and between rooms.
				v.fill_box(Vector3i(x + 10, fy, zm), Vector3i(x + 19, fy + 21, zm + 3), 0)
				if b == 1 or b == 4:
					v.fill_box(Vector3i(x - 1, fy, z0 + 38), Vector3i(x + 1, fy + 21, z0 + 47), 0)
					v.fill_box(Vector3i(x - 1, fy, zm + 20), Vector3i(x + 1, fy + 21, zm + 29), 0)
			# Apartment doors off the landing.
			v.fill_box(Vector3i(bx - 1, fy, zi - 11), Vector3i(bx + 1, fy + 21, zi - 2), 0)
			v.fill_box(Vector3i(bx + BAY - 1, fy, zi - 11), Vector3i(bx + BAY + 1, fy + 21, zi - 2), 0)
		_stairs(v, bx, zf, zi, seed + s)

		# Entrance: open wooden door, stone stoop, fabric awning with a lamp.
		v.fill_box(Vector3i(bxc - 6, 2, z0), Vector3i(bxc + 6, 24, z0 + T), 0)
		v.fill_box(Vector3i(bxc - 7, 24, z0), Vector3i(bxc + 7, 26, z0 + 1), stone)
		v.fill_planks(Vector3i(bxc - 7, 2, z0 - 7), Vector3i(bxc - 6, 24, z0), 1, 2, 2, VoxMat.ids("wood_dark"), seed)
		for k in 3:
			v.fill_box_noise(Vector3i(bxc - 9 + k, 0, z0 - 8 + k * 2), Vector3i(bxc + 9 - k, 2 + k, z0), VoxMat.ids("stone"), seed + k)
		for k in 4:
			v.fill_box(Vector3i(bxc - 11, 30 - k, z0 - 3 * (k + 1)), Vector3i(bxc + 11, 31 - k, z0 - 3 * k), awning)
		v.fill_box(Vector3i(bxc - 11, 25, z0 - 12), Vector3i(bxc + 11, 27, z0 - 11), awning)
		v.fill_box(Vector3i(bxc - 1, 26, z0 - 1), Vector3i(bxc + 1, 27, z0), VoxMat.id("lamp"))
		lamps.append(Vector3i(bxc, 26, z0 - 1))
		entrances.append(Vector3(bxc, 0, z0 - 16))
		# Street number above the door.
		var num := str(100 + seed * 20 + s * 2)
		VoxelFont.draw(v, num, Vector3i(bxc + VoxelFont.text_width(num) / 2, 38, z0 - 1), Vector3i(-1, 0, 0), VoxMat.id("sign_glow"))

	# Windows with stone sills and lintels, fire escapes and window AC units.
	for s in sections:
		for b in 5:
			var cx := x0 + s * SEC + b * BAY + BAY / 2
			var stair := b == 2
			var escape := b == 1 or (b == 3 and sections > 3 and s % 2 == 1)
			for f in FLOORS:
				var fy := PL + f * FH
				if stair:
					# Landing windows (none above the door, where the street number is).
					if f >= 1 and f < FLOORS - 1:
						Build.window(v, 2, z0, T, cx - 5, fy + 17, 10, 10, "pvc", -1)
				else:
					Build.window(v, 2, z0, T, cx - 6, fy + 6, 12, 17, "pvc", -1)
					v.fill_box(Vector3i(cx - 7, fy + 23, z0 - 1), Vector3i(cx + 7, fy + 24, z0), stone)
					_window_life(v, rng, cx - 6, fy + 6, 12, 17, z0 + T - 1)
					if f >= 1 and rng.randf() < 0.14:
						_window_ac(v, cx, fy, z0, -1)
				Build.window(v, 2, z1 - T, T, cx - 6, fy + 6, 12, 17, "pvc", 1)
				v.fill_box(Vector3i(cx - 7, fy + 23, z1), Vector3i(cx + 7, fy + 24, z1 + 1), stone)
				_window_life(v, rng, cx - 6, fy + 6, 12, 17, z1 - T)
				if escape and f >= 1:
					_fire_escape_level(v, cx, fy, z1)
				elif f >= 1 and rng.randf() < 0.18:
					_window_ac(v, cx, fy, z1, 1)
				if rng.randf() < 0.03:
					_dish(v, Vector3i(cx - 11, fy + 18, z1))
			# Basement vents.
			v.fill_box(Vector3i(cx - 3, 4, z0), Vector3i(cx + 3, 7, z0 + T), 0)
			v.fill_box(Vector3i(cx - 3, 4, z1 - T), Vector3i(cx + 3, 7, z1), 0)
	# Gable end windows.
	for f in FLOORS:
		var fy := PL + f * FH
		for zz in [z0 + 22, z1 - 36]:
			Build.window(v, 0, x0, T, zz, fy + 6, 12, 17, "pvc", -1)
			Build.window(v, 0, x1 - T, T, zz, fy + 6, 12, 17, "pvc", 1)

	# Downspouts.
	for k in sections + 1:
		var x := clampi(x0 + k * SEC, x0 + 1, x1 - 2)
		v.fill_box(Vector3i(x, 0, z0 - 1), Vector3i(x + 1, top, z0), VoxMat.id("metal_dark"))
		v.fill_box(Vector3i(x, 0, z1), Vector3i(x + 1, top, z1 + 1), VoxMat.id("metal_dark"))

	# Roof: stair bulkheads, vents, AC units and sometimes a wooden water tank.
	var rt := top + 3
	for s in sections:
		var bx := x0 + s * SEC + 2 * BAY
		var brick_ids := VoxMat.ids(brick)
		v.fill_bricks(Vector3i(bx + 4, rt, zf + 6), Vector3i(bx + 26, rt + 20, zf + 28), 0, 3, 1, brick_ids, -1, seed + s)
		v.fill_box(Vector3i(bx + 6, rt, zf + 8), Vector3i(bx + 24, rt + 18, zf + 26), 0)
		v.fill_box(Vector3i(bx + 11, rt, zf + 6), Vector3i(bx + 19, rt + 17, zf + 8), VoxMat.id("door_metal"))
		v.fill_box_noise(Vector3i(bx + 3, rt + 20, zf + 5), Vector3i(bx + 27, rt + 22, zf + 29), con, seed)
		for vx in [x0 + s * SEC + 18, x0 + s * SEC + 128]:
			v.fill_box(Vector3i(vx, rt, zm - 3), Vector3i(vx + 6, rt + 6, zm + 3), VoxMat.id("metal"))
		for k in 2:
			var ax := x0 + s * SEC + 40 + k * 60 + rng.randi_range(-10, 10)
			var az := z0 + rng.randi_range(25, DEPTH - 35)
			v.fill_box(Vector3i(ax, rt, az), Vector3i(ax + 14, rt + 9, az + 11), VoxMat.id("metal_white"))
			v.fill_cylinder(Vector3(ax + 7, rt + 9, az + 5.5), 4.0, 1, 1, VoxMat.id("metal_dark"))
	if seed % 2 == 0:
		_water_tank(v, Vector3(x0 + SEC * 0.5 + 40, rt, z0 + DEPTH * 0.55))

	var interior := AABB(Vector3(x0 + T, PL, z0 + T) * VS, Vector3(L - 2 * T, top - PL, DEPTH - 2 * T) * VS)
	return {"volume": v, "lamps": lamps, "entrances": entrances, "interior": interior,
		"front_z": z0, "back_z": z1, "x0": x0, "x1": x1, "top": top}


static func _brick_ring(v: VoxelVolume, x0: int, z0: int, x1: int, z1: int, y0: int, y1: int, t: int, swatch: String, seed: int) -> void:
	var b := VoxMat.ids(swatch)
	v.fill_bricks(Vector3i(x0, y0, z0), Vector3i(x1, y1, z0 + t), 0, 3, 1, b, -1, seed)
	v.fill_bricks(Vector3i(x0, y0, z1 - t), Vector3i(x1, y1, z1), 0, 3, 1, b, -1, seed + 1)
	v.fill_bricks(Vector3i(x0, y0, z0), Vector3i(x0 + t, y1, z1), 2, 3, 1, b, -1, seed + 2)
	v.fill_bricks(Vector3i(x1 - t, y0, z0), Vector3i(x1, y1, z1), 2, 3, 1, b, -1, seed + 3)


## One level of a black steel fire escape on the back facade: platform, railing
## and a diagonal stair down to the level below (drop ladder at the bottom).
static func _fire_escape_level(v: VoxelVolume, cx: int, fy: int, z1: int) -> void:
	var m := VoxMat.id("metal_dark")
	v.fill_box(Vector3i(cx - 14, fy - 1, z1), Vector3i(cx + 14, fy, z1 + 10), m)
	v.fill_box(Vector3i(cx - 14, fy + 9, z1 + 9), Vector3i(cx + 14, fy + 10, z1 + 10), m)
	for x in range(cx - 14, cx + 15, 4):
		v.fill_box(Vector3i(x, fy, z1 + 9), Vector3i(x + 1, fy + 9, z1 + 10), m)
	v.fill_box(Vector3i(cx - 14, fy, z1), Vector3i(cx - 13, fy + 10, z1 + 10), m)
	v.fill_box(Vector3i(cx + 13, fy, z1), Vector3i(cx + 14, fy + 10, z1 + 10), m)
	Build.line(v, Vector3(cx - 11, fy - 1, z1 + 5), Vector3(cx + 9, fy - FH + 1, z1 + 5), 2, m)
	if fy - FH <= PL + 1:
		for y in range(fy - FH - 10, fy - FH, 3):
			v.fill_box(Vector3i(cx + 8, y, z1 + 4), Vector3i(cx + 12, y + 1, z1 + 6), m)
		v.fill_box(Vector3i(cx + 8, fy - FH - 10, z1 + 4), Vector3i(cx + 9, fy - FH, z1 + 6), m)
		v.fill_box(Vector3i(cx + 11, fy - FH - 10, z1 + 4), Vector3i(cx + 12, fy - FH, z1 + 6), m)


static func _window_ac(v: VoxelVolume, cx: int, fy: int, z: int, outward: int) -> void:
	var za := z - 4 if outward < 0 else z
	v.fill_box(Vector3i(cx - 4, fy + 6, za), Vector3i(cx + 4, fy + 11, za + 4), VoxMat.id("plastic_white"))
	var grill := za if outward < 0 else za + 3
	v.fill_box(Vector3i(cx - 3, fy + 7, grill), Vector3i(cx + 3, fy + 10, grill + 1), VoxMat.id("metal_dark"))


## Classic wooden rooftop water tank on steel legs.
static func _water_tank(v: VoxelVolume, base: Vector3) -> void:
	var m := VoxMat.id("metal_dark")
	var b := Vector3i(base.floor())
	for d in [Vector2i(-7, -7), Vector2i(7, -7), Vector2i(-7, 7), Vector2i(7, 7)]:
		v.fill_box(b + Vector3i(d.x, 0, d.y), b + Vector3i(d.x + 2, 12, d.y + 2), m)
	v.fill_box(b + Vector3i(-9, 12, -9), b + Vector3i(10, 13, 10), m)
	v.fill_cylinder(base + Vector3(1, 13, 1), 9.5, 16, 1, VoxMat.id("wood_grey"))
	v.fill_cylinder(base + Vector3(1, 14, 1), 8.0, 15, 1, 0)
	for k in 3:
		v.fill_cylinder(base + Vector3(1, 15 + k * 5, 1), 9.8, 1, 1, m)
	for k in 6:
		v.fill_cylinder(base + Vector3(1, 29 + k, 1), 9.5 - k * 1.6, 1, 1, VoxMat.id("roof_tile"))


static func _ring(v: VoxelVolume, x0: int, z0: int, x1: int, z1: int, y0: int, y1: int, t: int, value: int) -> void:
	v.fill_box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z0 + t), value)
	v.fill_box(Vector3i(x0, y0, z1 - t), Vector3i(x1, y1, z1), value)
	v.fill_box(Vector3i(x0, y0, z0), Vector3i(x0 + t, y1, z1), value)
	v.fill_box(Vector3i(x1 - t, y0, z0), Vector3i(x1, y1, z1), value)


## Two flights per storey inside the stair bay, from the entrance hall up to the
## top floor landing.
static func _stairs(v: VoxelVolume, bx: int, zf: int, zi: int, seed: int) -> void:
	var con := VoxMat.ids("concrete")
	var xa0 := bx + 2
	var xa1 := bx + 15
	var xb1 := bx + 28
	# Entrance hall is lower than the ground floor; four steps lead up.
	v.fill_box(Vector3i(bx + 1, PL - 3, zf), Vector3i(bx + 29, PL, zf + 27), 0)
	v.fill_box_noise(Vector3i(bx + 1, 0, zf), Vector3i(bx + 29, 2, zf + 27), con, seed)
	for k in range(1, 5):
		v.fill_box_noise(Vector3i(xa0, 2, zf + 15 + 3 * (k - 1)), Vector3i(xb1, 2 + 2 * k, zf + 15 + 3 * k), con, seed + k)
	v.fill_box_noise(Vector3i(xa0, 2, zf + 27), Vector3i(xb1, PL, zi), con, seed + 9)
	for f in FLOORS - 1:
		var y0 := PL + f * FH
		# Opening in the slab above for the flights.
		v.fill_box(Vector3i(bx + 1, y0 + FH - 3, zf), Vector3i(bx + 29, y0 + FH, zi - 12), 0)
		v.fill_box_noise(Vector3i(xa0, y0 + 12, zf), Vector3i(xb1, y0 + 14, zf + 15), con, seed + f)
		for k in range(1, 8):
			var ta := y0 + 2 * k
			v.fill_box_noise(Vector3i(xa0, ta - 2, zi - 12 - 3 * k), Vector3i(xa1, ta, zi - 9 - 3 * k), con, seed + k)
			var tb := y0 + 14 + 2 * k
			v.fill_box_noise(Vector3i(xa1, tb - 2, zf + 12 + 3 * k), Vector3i(xb1, tb, zf + 15 + 3 * k), con, seed + k + 9)
		# Railing between the flights.
		v.fill_box(Vector3i(xa1, y0 + 2, zf + 15), Vector3i(xa1 + 1, y0 + 24, zi - 12), VoxMat.id("metal_dark"))


## Lit window, curtain or nothing behind the glass (d = depth just behind glass).
static func _window_life(v: VoxelVolume, rng: RandomNumberGenerator, u0: int, y0: int, w: int, h: int, d: int) -> void:
	var r := rng.randf()
	if r < 0.16:
		v.fill_box(Vector3i(u0 + 1, y0 + 1, d), Vector3i(u0 + w - 1, y0 + h - 1, d + 1), VoxMat.id("window_light"))
	elif r < 0.45:
		var c := VoxMat.id(CURTAINS[rng.randi() % CURTAINS.size()])
		var half := w / 2
		var left := rng.randf() < 0.5
		var a := u0 + 1 if left else u0 + half
		v.fill_box(Vector3i(a, y0 + 1, d), Vector3i(a + half - 1, y0 + h - 1, d + 1), c)



static func _dish(v: VoxelVolume, p: Vector3i) -> void:
	v.fill_cylinder(Vector3(p.x + 0.5, p.y + 0.5, p.z + 1), 2.6, 1, 2, VoxMat.id("metal_white"))
	v.fill_box(p + Vector3i(0, -2, 0), p + Vector3i(1, 0, 2), VoxMat.id("metal_dark"))


# ---------------------------------------------------------------- stores

## Store box: stucco or brick walls, brand band with glowing lettering,
## glass storefront, racks of goods, fridges, checkouts, roof HVAC units.
## brand: "foodmart" (supermarket) or "pharmacy". Front (storefront) faces +z.
static func store(W: int, D: int, H: int, brand: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := Build.vol(Vector3i(W + 4, H + 20, D + 18))
	var x0 := 2
	var x1 := 2 + W
	var z0 := 4
	var z1 := 4 + D
	var big := brand == "foodmart"
	var sand := VoxMat.id("stucco" if big else "brick_tan")
	var red := VoxMat.id("brand_red")
	var green := VoxMat.id("brand_green")
	var glow := VoxMat.id("sign_glow")
	v.fill_box_noise(Vector3i(x0, 0, z0), Vector3i(x1, 2, z1), VoxMat.ids("concrete"), seed)
	_ring(v, x0, z0, x1, z1, 2, H, 2, sand)
	v.fill_box_noise(Vector3i(x0, H, z0), Vector3i(x1, H + 2, z1), VoxMat.ids("roof_bitumen"), seed)
	_ring(v, x0, z0, x1, z1, H + 2, H + 5, 2, sand)

	# Storefront glass with mullions, entrance and canopy.
	var ex := x0 + (40 if big else W - 80)
	var g := VoxMat.id("glass")
	v.fill_box(Vector3i(x0 + 6, 7, z1 - 2), Vector3i(x1 - 6, H - 16, z1), 0)
	v.fill_box(Vector3i(x0 + 6, 7, z1 - 1), Vector3i(x1 - 6, H - 16, z1), g)
	for x in range(x0 + 6, x1 - 5, 24):
		v.fill_box(Vector3i(x, 7, z1 - 2), Vector3i(x + 1, H - 16, z1), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(ex, 2, z1 - 2), Vector3i(ex + 40, 30, z1), 0)
	v.fill_box(Vector3i(ex, 2, z1 - 1), Vector3i(ex + 12, 30, z1), g)
	v.fill_box(Vector3i(ex + 28, 2, z1 - 1), Vector3i(ex + 40, 30, z1), g)
	v.fill_box(Vector3i(ex - 1, 30, z1 - 2), Vector3i(ex + 41, 32, z1), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(ex - 6, 32, z1), Vector3i(ex + 46, 34, z1 + 12), green if big else red)
	# Lower stripe and the brand band.
	v.fill_box(Vector3i(x0, 2, z1), Vector3i(x1, 7, z1 + 1), VoxMat.id("stone"))
	v.fill_box(Vector3i(ex - 1, 2, z1), Vector3i(ex + 41, 7, z1 + 1), 0)
	v.fill_box(Vector3i(x0, H - 16, z1 - 1), Vector3i(x1, H + 5, z1 + 1), green if big else red)
	var band_top := H + 2
	var text := "FOOD MART" if big else "PHARMACY"
	var tw := VoxelFont.text_width(text, 2)
	var tx := (x0 + x1) / 2 - tw / 2 + 10
	VoxelFont.draw(v, text, Vector3i(tx, band_top - 2, z1 + 1), Vector3i(1, 0, 0), glow, 2)
	# Logo square left of the lettering: a red apple for the grocer, a green cross
	# for the pharmacy.
	var logo_x := tx - 22
	v.fill_box(Vector3i(logo_x, band_top - 18, z1 + 1), Vector3i(logo_x + 16, band_top - 2, z1 + 2), glow)
	if big:
		v.fill_sphere(Vector3(logo_x + 8, band_top - 11, z1 + 2), 5.0, red)
		v.fill_box(Vector3i(logo_x + 8, band_top - 6, z1 + 2), Vector3i(logo_x + 9, band_top - 3, z1 + 3), VoxMat.id("wood_dark"))
		v.fill_box(Vector3i(logo_x + 9, band_top - 5, z1 + 2), Vector3i(logo_x + 12, band_top - 4, z1 + 3), green)
	else:
		v.fill_box(Vector3i(logo_x + 6, band_top - 15, z1 + 2), Vector3i(logo_x + 10, band_top - 5, z1 + 3), green)
		v.fill_box(Vector3i(logo_x + 3, band_top - 12, z1 + 2), Vector3i(logo_x + 13, band_top - 8, z1 + 3), green)

	# Interior: racks with goods, fridges along the back, checkouts.
	var goods := PackedByteArray([VoxMat.id("plastic_red"), VoxMat.id("plastic_green"), VoxMat.id("plastic_yellow"),
		VoxMat.id("plastic_blue"), VoxMat.id("plastic_white"), VoxMat.id("plastic_orange"), VoxMat.id("wood_light")])
	var mw := VoxMat.id("metal_white")
	var rack_x1 := x1 - 50 if big else x1 - 20
	var rack_x0 := x0 + 14 if big else x0 + 50
	for rz in range(z0 + 26, z1 - 40, 22):
		v.fill_box(Vector3i(rack_x0, 2, rz), Vector3i(rack_x1, 3, rz + 6), mw)
		for y in [8, 14]:
			v.fill_box(Vector3i(rack_x0, y, rz), Vector3i(rack_x1, y + 1, rz + 6), mw)
		v.fill_box_noise(Vector3i(rack_x0, 3, rz), Vector3i(rack_x1, 6, rz + 6), goods, seed + rz)
		v.fill_box_noise(Vector3i(rack_x0, 9, rz), Vector3i(rack_x1, 12, rz + 6), goods, seed + rz + 1)
		v.fill_box_noise(Vector3i(rack_x0, 15, rz), Vector3i(rack_x1, 18, rz + 6), goods, seed + rz + 2)
		v.fill_box(Vector3i(rack_x0, 3, rz + 2), Vector3i(rack_x1, 18, rz + 4), mw)
		for x in range(rack_x0, rack_x1, 30):
			v.fill_box(Vector3i(x, 2, rz), Vector3i(x + 1, 19, rz + 6), mw)
	v.fill_box(Vector3i(x0 + 4, 2, z0 + 2), Vector3i(x1 - 4, 22, z0 + 10), mw)
	v.fill_box_noise(Vector3i(x0 + 5, 4, z0 + 3), Vector3i(x1 - 5, 20, z0 + 9), goods, seed + 5)
	v.fill_box(Vector3i(x0 + 4, 4, z0 + 9), Vector3i(x1 - 4, 20, z0 + 10), g)
	for k in 3:
		var cx := ex + 50 + k * 22 if big else ex - 30 - k * 22
		v.fill_box(Vector3i(cx, 2, z1 - 34), Vector3i(cx + 6, 10, z1 - 20), VoxMat.id("plastic_white"))
		v.fill_box(Vector3i(cx, 10, z1 - 34), Vector3i(cx + 6, 11, z1 - 20), VoxMat.id("metal_dark"))
	var lamps: Array[Vector3i] = []
	for lx in range(x0 + 30, x1 - 20, 80):
		for lz in [z0 + 40, z1 - 40]:
			v.fill_box(Vector3i(lx, H - 1, lz), Vector3i(lx + 30, H, lz + 2), VoxMat.id("lamp"))
			lamps.append(Vector3i(lx + 15, H - 1, lz))
	# Back loading door and roof units.
	v.fill_planks(Vector3i(x1 - 40, 2, z0), Vector3i(x1 - 10, 30, z0 + 2), 0, 1, 2, VoxMat.ids("metal_white"), seed)
	for k in 4:
		var ux := x0 + 30 + k * (W - 60) / 3 + rng.randi_range(-8, 8)
		var uz := z0 + rng.randi_range(25, D - 50)
		v.fill_box(Vector3i(ux, H + 2, uz), Vector3i(ux + 22, H + 14, uz + 16), mw)
		v.fill_cylinder(Vector3(ux + 7, H + 14, uz + 8), 5.0, 1, 1, VoxMat.id("metal_dark"))
		v.fill_cylinder(Vector3(ux + 16, H + 14, uz + 8), 5.0, 1, 1, VoxMat.id("metal_dark"))
	var interior := AABB(Vector3(x0 + 2, 2, z0 + 2) * VS, Vector3(W - 4, H - 4, D - 4) * VS)
	return {"volume": v, "lamps": lamps, "interior": interior}


## Two storey auto repair shop with a tire service bay in front (front = +z).
static func auto_shop(seed: int) -> Dictionary:
	var v := Build.vol(Vector3i(114, 70, 112))
	var py := VoxMat.id("plaster_yellow")
	var con := VoxMat.ids("concrete")
	v.fill_box_noise(Vector3i(2, 0, 2), Vector3i(112, 2, 72), con, seed)
	_ring(v, 2, 2, 112, 72, 2, 62, 3, py)
	v.fill_box_noise(Vector3i(5, 30, 5), Vector3i(109, 33, 69), con, seed)
	v.fill_box_noise(Vector3i(2, 62, 2), Vector3i(112, 65, 72), VoxMat.ids("roof_bitumen"), seed)
	_ring(v, 2, 2, 112, 72, 65, 68, 2, py)
	for x in [14, 44, 74]:
		Build.window(v, 2, 2, 3, x, 40, 18, 14, "pvc", -1)
		Build.window(v, 2, 2, 3, x, 10, 18, 14, "pvc", -1)
	for z in [14, 44]:
		Build.window(v, 0, 2, 3, z, 40, 16, 14, "pvc", -1)
		Build.window(v, 0, 109, 3, z, 40, 16, 14, "pvc", 1)
		Build.window(v, 0, 109, 3, z, 10, 16, 14, "pvc", 1)
	# Inner stairs to the upper floor.
	for k in range(1, 15):
		v.fill_box_noise(Vector3i(8, 0, 10 + 3 * k), Vector3i(20, 2 * k + 2, 13 + 3 * k), con, seed + k)
	v.fill_box(Vector3i(8, 30, 13), Vector3i(20, 33, 56), 0)
	# Service bay annex (cinder block).
	var sb := VoxMat.ids("concrete")
	v.fill_bricks(Vector3i(2, 2, 72), Vector3i(112, 32, 102), 0, 3, 1, sb, -1, seed)
	v.fill_box(Vector3i(5, 2, 72), Vector3i(109, 32, 99), 0)
	v.fill_box_noise(Vector3i(2, 32, 72), Vector3i(112, 35, 102), VoxMat.ids("roof_bitumen"), seed)
	v.fill_box(Vector3i(36, 2, 99), Vector3i(80, 27, 102), 0)
	Build.window(v, 2, 99, 3, 86, 12, 16, 12, "pvc", 1)
	v.fill_box(Vector3i(12, 2, 99), Vector3i(22, 24, 102), 0)
	# Door from annex into the shop.
	v.fill_box(Vector3i(50, 2, 69), Vector3i(62, 24, 72), 0)
	# "AUTO REPAIR" board with the US flag, "TIRE SERVICE" over the bay.
	v.fill_box(Vector3i(8, 38, 72), Vector3i(106, 58, 73), VoxMat.id("pvc"))
	VoxelFont.draw(v, "AUTO REPAIR", Vector3i(12, 55, 73), Vector3i(1, 0, 0), VoxMat.id("brand_red"))
	VoxelFont.draw(v, "OPEN 7 DAYS", Vector3i(12, 46, 73), Vector3i(1, 0, 0), VoxMat.id("metal_blue"))
	_us_flag(v, Vector3i(84, 41, 73), 1)
	v.fill_box(Vector3i(20, 27, 102), Vector3i(96, 35, 103), VoxMat.id("metal_yellow"))
	VoxelFont.draw(v, "TIRE SERVICE", Vector3i(23, 34, 103), Vector3i(1, 0, 0), VoxMat.id("tank_black"))
	# Tires inside the annex.
	for k in 6:
		_tire(v, Vector3(30 + k * 12, 2, 86), 2 + k % 3)
	return {"volume": v, "lamps": [Vector3i(56, 26, 101)], "interior": AABB(Vector3(5, 2, 5) * VS, Vector3(104, 58, 64) * VS)}


static func _tire(v: VoxelVolume, p: Vector3, stack: int) -> void:
	for k in stack:
		v.fill_cylinder(p + Vector3(0, k * 3, 0), 4.4, 3, 1, VoxMat.id("rubber"))
		v.fill_cylinder(p + Vector3(0, k * 3, 0), 2.2, 3, 1, 0)


## Row of self-storage units with orange roll-up doors (doors on +z). Returns the
## voxel x centers of units left open.
static func garage_row(n: int, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var GW := 32
	var GD := 60
	var GH := 26
	var v := Build.vol(Vector3i(n * GW + 2, GH + 4, GD + 12))
	var wall := VoxMat.ids("sandwich")
	var door := VoxMat.ids("door_orange")
	var open: Array[int] = []
	v.fill_bricks(Vector3i(0, 0, 0), Vector3i(n * GW + 2, GH, 2), 0, 3, 1, wall, -1, seed)
	for i in n + 1:
		v.fill_bricks(Vector3i(i * GW, 0, 0), Vector3i(i * GW + 2, GH, GD), 2, 3, 1, wall, -1, seed + i)
	v.fill_box_noise(Vector3i(0, GH, 0), Vector3i(n * GW + 2, GH + 2, GD + 2), VoxMat.ids("concrete"), seed)
	v.fill_box_noise(Vector3i(0, GH + 2, 0), Vector3i(n * GW + 2, GH + 3, GD + 2), VoxMat.ids("roof_bitumen"), seed)
	for i in n:
		var x := i * GW + 2
		v.fill_bricks(Vector3i(x, 22, GD - 2), Vector3i(x + GW - 2, GH, GD), 0, 3, 1, wall, -1, seed + i)
		var state := rng.randf()
		if state < 0.22:
			open.append(x + GW / 2)
			# Door rolled half way up.
			v.fill_planks(Vector3i(x + 1, 13, GD - 2), Vector3i(x + GW - 3, 22, GD - 1), 0, 1, 1, door, seed + i)
			var junk := PackedByteArray([VoxMat.id("wood"), VoxMat.id("rubber"), VoxMat.id("metal_rust"), VoxMat.id("plastic_blue")])
			v.fill_box_noise(Vector3i(x + 2, 0, 3), Vector3i(x + 12, 8, 14), junk, seed + i)
		else:
			v.fill_planks(Vector3i(x + 1, 0, GD - 2), Vector3i(x + GW - 3, 22, GD - 1), 0, 1, 1, door, seed + i)
			v.fill_box(Vector3i(x + GW / 2 - 2, 1, GD - 1), Vector3i(x + GW / 2 + 2, 2, GD), VoxMat.id("metal_dark"))
		# Unit number.
		VoxelFont.draw(v, str(i + 1 + seed % 3 * 20), Vector3i(x + 3, 25, GD), Vector3i(1, 0, 0), VoxMat.id("pvc"))
	return {"volume": v, "open": open}


static func shed(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(34, 32, 30))
	Build.walls(v, 2, 2, 32, 28, 0, 22, 2, "wood_grey", seed)
	Build.door(v, 2, 26, 2, 12, 0, 9, 18, "wood_dark")
	for k in 9:
		v.fill_box(Vector3i(0, 22 + k, 0 + k), Vector3i(34, 23 + k, 30 - k), VoxMat.id("metal_rust") if k % 2 == 0 else VoxMat.id("metal"))
	return v


static func bus_stop(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(44, 38, 20))
	var md := VoxMat.id("metal_dark")
	v.fill_box_noise(Vector3i(0, 0, 0), Vector3i(44, 1, 20), VoxMat.ids("concrete"), seed)
	for p in [Vector2i(1, 2), Vector2i(41, 2), Vector2i(1, 17), Vector2i(41, 17)]:
		v.fill_box(Vector3i(p.x, 1, p.y), Vector3i(p.x + 2, 26, p.y + 1), md)
	v.fill_box(Vector3i(3, 4, 2), Vector3i(41, 24, 3), VoxMat.id("glass"))
	v.fill_box(Vector3i(1, 4, 3), Vector3i(2, 24, 17), VoxMat.id("glass"))
	v.fill_box(Vector3i(42, 4, 3), Vector3i(43, 24, 17), VoxMat.id("glass"))
	v.fill_box(Vector3i(0, 26, 0), Vector3i(44, 28, 20), VoxMat.id("metal_blue"))
	v.fill_planks(Vector3i(6, 8, 4), Vector3i(38, 9, 9), 0, 2, 2, VoxMat.ids("wood"), seed)
	for x in [8, 35]:
		v.fill_box(Vector3i(x, 1, 5), Vector3i(x + 1, 8, 6), md)
	v.fill_box(Vector3i(1, 28, 0), Vector3i(43, 37, 1), VoxMat.id("pvc"))
	# Lettering faces the road side (+z).
	VoxelFont.draw(v, "BUS", Vector3i(13, 35, 1), Vector3i(1, 0, 0), VoxMat.id("metal_blue"))
	return v


## Stars and stripes, 19 x 14 voxels, facing +z at origin (bottom-left).
static func _us_flag(v: VoxelVolume, o: Vector3i, depth: int) -> void:
	var red := VoxMat.id("brand_red")
	var white := VoxMat.id("pvc")
	for row in 14:
		var c := red if (row / 2) % 2 == 0 else white
		v.fill_box(o + Vector3i(0, row, 0), o + Vector3i(19, row + 1, depth), c)
	v.fill_box(o + Vector3i(0, 6, 0), o + Vector3i(8, 14, depth), VoxMat.id("metal_blue"))
	for sy in range(7, 14, 2):
		for sx in range(1, 8, 2):
			v.set_voxel(o + Vector3i(sx, sy, depth - 1), white)
