class_name DistrictProps
## Street furniture, playground, fences, railway, vegetation and vehicles of the
## microdistrict map. All builders return plain voxel volumes (voxel origin at
## the corner, y up); vehicles face -x like Build.car.

const VS := 0.1


# ---------------------------------------------------------------- playground

static func swing(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(34, 26, 16))
	var f := VoxMat.id(["metal_blue", "metal_red", "metal_green"][seed % 3])
	for x in [1, 32]:
		Build.line(v, Vector3(x, 0, 1), Vector3(x, 24, 8), 2, f)
		Build.line(v, Vector3(x, 0, 15), Vector3(x, 24, 8), 2, f)
	v.fill_box(Vector3i(0, 24, 7), Vector3i(34, 26, 9), f)
	for sx in [8, 22]:
		for cx in [sx, sx + 5]:
			v.fill_box(Vector3i(cx, 7, 8), Vector3i(cx + 1, 24, 9), VoxMat.id("metal_dark"))
		v.fill_planks(Vector3i(sx - 1, 6, 6), Vector3i(sx + 7, 7, 11), 0, 2, 2, VoxMat.ids("wood_red"), seed)
	return v


static func slide(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(40, 24, 14))
	var c := VoxMat.id(["plastic_yellow", "plastic_red", "plastic_blue"][seed % 3])
	var m := VoxMat.id("metal_blue")
	for p in [Vector2i(2, 2), Vector2i(12, 2), Vector2i(2, 11), Vector2i(12, 11)]:
		v.fill_box(Vector3i(p.x, 0, p.y), Vector3i(p.x + 1, 22, p.y + 1), m)
	v.fill_box(Vector3i(2, 12, 2), Vector3i(13, 13, 12), VoxMat.id("wood"))
	v.fill_box(Vector3i(2, 13, 2), Vector3i(13, 21, 3), m)
	for k in 6:
		v.fill_box(Vector3i(0, 2 * k + 1, 4), Vector3i(2, 2 * k + 2, 10), VoxMat.id("wood"))
	for x in range(13, 39):
		var y := int(12.0 - (x - 13) * 11.0 / 25.0)
		v.fill_box(Vector3i(x, y, 4), Vector3i(x + 1, y + 1, 10), c)
		v.fill_box(Vector3i(x, y + 1, 4), Vector3i(x + 1, y + 3, 5), c)
		v.fill_box(Vector3i(x, y + 1, 9), Vector3i(x + 1, y + 3, 10), c)
	v.fill_box(Vector3i(36, 0, 6), Vector3i(37, 2, 8), m)
	return v


static func carousel(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(26, 14, 26))
	var c := VoxMat.id(["plastic_red", "plastic_yellow"][seed % 2])
	v.fill_cylinder(Vector3(13, 2, 13), 12.0, 1, 1, c)
	v.fill_cylinder(Vector3(13, 0, 13), 1.5, 14, 1, VoxMat.id("metal_dark"))
	for k in 4:
		var a := k * PI * 0.5
		var p := Vector3(13 + cos(a) * 10, 3, 13 + sin(a) * 10)
		Build.line(v, p, Vector3(13, 12, 13), 1, VoxMat.id("metal_blue"))
	return v


static func sandbox(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(32, 26, 32))
	v.fill_planks(Vector3i(0, 0, 0), Vector3i(32, 4, 32), 0, 1, 2, VoxMat.ids("wood_light"), seed)
	v.fill_box(Vector3i(2, 0, 2), Vector3i(30, 4, 30), 0)
	v.fill_box_noise(Vector3i(2, 0, 2), Vector3i(30, 3, 30), VoxMat.ids("sand"), seed)
	v.fill_box(Vector3i(15, 0, 15), Vector3i(17, 20, 17), VoxMat.id("wood_dark"))
	for k in 6:
		var r := 13 - k * 2
		v.fill_cylinder(Vector3(16, 20 + k, 16), r, 1, 1, VoxMat.id("plastic_red") if k % 2 == 0 else VoxMat.id("pvc"))
	return v


static func climber(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(30, 22, 12))
	var m := VoxMat.id(["metal_green", "metal_red", "metal_blue"][seed % 3])
	for x in range(0, 30, 5):
		v.fill_box(Vector3i(x, 0, 0), Vector3i(x + 1, 21, 1), m)
		v.fill_box(Vector3i(x, 0, 11), Vector3i(x + 1, 21, 12), m)
	for y in range(3, 22, 4):
		v.fill_box(Vector3i(0, y, 0), Vector3i(26, y + 1, 1), m)
		v.fill_box(Vector3i(0, y, 11), Vector3i(26, y + 1, 12), m)
	for x in range(0, 30, 5):
		v.fill_box(Vector3i(x, 20, 0), Vector3i(x + 1, 21, 12), m)
	return v


static func bench(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(18, 9, 6))
	var w := VoxMat.ids(["wood", "wood_red", "wood_light", "metal_green"][seed % 4])
	v.fill_planks(Vector3i(0, 4, 0), Vector3i(18, 5, 5), 0, 2, 1, w, seed)
	v.fill_planks(Vector3i(0, 5, 5), Vector3i(18, 9, 6), 0, 1, 1, w, seed)
	for x in [1, 15]:
		v.fill_box(Vector3i(x, 0, 0), Vector3i(x + 2, 4, 6), VoxMat.id("concrete"))
	return v


static func urn() -> VoxelVolume:
	var v := Build.vol(Vector3i(5, 7, 5))
	v.fill_cylinder(Vector3(2.5, 0, 2.5), 2.4, 7, 1, VoxMat.id("concrete"))
	v.fill_cylinder(Vector3(2.5, 2, 2.5), 1.4, 5, 1, 0)
	return v


static func trash_container(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(16, 13, 12))
	var c := VoxMat.id(["metal_green", "metal_blue", "metal_green", "metal_rust"][seed % 4])
	v.fill_box(Vector3i(0, 1, 0), Vector3i(16, 12, 12), c)
	v.fill_box(Vector3i(1, 2, 1), Vector3i(15, 12, 11), 0)
	var trash := PackedByteArray([VoxMat.id("tank_black"), VoxMat.id("pvc"), VoxMat.id("wood_light"), VoxMat.id("plastic_blue")])
	v.fill_box_noise(Vector3i(1, 2, 1), Vector3i(15, 9 + seed % 4, 11), trash, seed)
	v.fill_box(Vector3i(0, 12, 0), Vector3i(16, 13, 6), VoxMat.id("metal_dark"))
	for p in [Vector2i(1, 1), Vector2i(13, 1), Vector2i(1, 9), Vector2i(13, 9)]:
		v.fill_box(Vector3i(p.x, 0, p.y), Vector3i(p.x + 2, 1, p.y + 2), VoxMat.id("rubber"))
	return v


static func tire_planter(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(10, 6, 10))
	var c := VoxMat.id(["plastic_yellow", "plastic_red", "pvc", "plastic_blue", "plastic_green"][seed % 5])
	v.fill_cylinder(Vector3(5, 0, 5), 4.6, 3, 1, c)
	v.fill_cylinder(Vector3(5, 0, 5), 2.8, 3, 1, VoxMat.id("dirt"))
	v.fill_ellipsoid_noise(Vector3(5, 4, 5), Vector3(3, 2, 3), PackedByteArray([VoxMat.id("flower_red"), VoxMat.id("flower_yellow"), VoxMat.id("foliage")]), 0.8, 0.2, seed)
	return v


static func flower_bed(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(40, 6, 16))
	v.fill_box_noise(Vector3i(0, 0, 0), Vector3i(40, 3, 16), VoxMat.ids("concrete"), seed)
	v.fill_box(Vector3i(1, 1, 1), Vector3i(39, 3, 15), VoxMat.id("dirt"))
	v.fill_ellipsoid_noise(Vector3(20, 3, 8), Vector3(18, 3, 6), PackedByteArray([VoxMat.id("flower_red"), VoxMat.id("flower_yellow"), VoxMat.id("foliage"), VoxMat.id("leaf_dark")]), 0.75, 0.3, seed)
	return v


# ---------------------------------------------------------------- street

static func concrete_fence(length: int, seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 26, 3))
	v.fill_box(Vector3i(0, 0, 1), Vector3i(length, 24, 2), VoxMat.id("concrete_fence"))
	for x in range(0, length, 40):
		v.fill_box(Vector3i(x, 0, 0), Vector3i(mini(x + 3, length), 26, 3), VoxMat.id("concrete_dark"))
	v.fill_box(Vector3i(0, 24, 0), Vector3i(length, 25, 3), VoxMat.id("concrete"))
	# Diamond relief rows typical for PO-2 panels.
	for x in range(4, length - 3, 8):
		for y in [6, 14]:
			v.fill_box(Vector3i(x, y, 0), Vector3i(x + 3, y + 3, 1), VoxMat.id("concrete_fence"))
	return v


static func metal_fence(length: int, color: String) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 11, 2))
	var c := VoxMat.id(color)
	for x in range(0, length, 20):
		v.fill_box(Vector3i(x, 0, 0), Vector3i(x + 1, 11, 2), c)
	v.fill_box(Vector3i(0, 10, 0), Vector3i(length, 11, 1), c)
	v.fill_box(Vector3i(0, 2, 0), Vector3i(length, 3, 1), c)
	for x in range(0, length, 3):
		v.fill_box(Vector3i(x, 2, 0), Vector3i(x + 1, 10, 1), c)
	return v


static func sheet_fence(length: int, color: String) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 20, 3))
	v.fill_planks(Vector3i(0, 0, 1), Vector3i(length, 20, 2), 1, 0, 1, VoxMat.ids(color), 3)
	for x in range(0, length, 25):
		v.fill_box(Vector3i(x, 0, 2), Vector3i(x + 1, 20, 3), VoxMat.id("metal_dark"))
	return v


static func lamp_pole() -> VoxelVolume:
	var v := Build.vol(Vector3i(16, 92, 3))
	var c := VoxMat.id("concrete_dark")
	v.fill_box(Vector3i(1, 0, 0), Vector3i(4, 88, 3), c)
	v.fill_box(Vector3i(2, 88, 1), Vector3i(3, 92, 2), c)
	Build.line(v, Vector3(3, 84, 1), Vector3(14, 87, 1), 1, VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(11, 85, 0), Vector3i(15, 86, 3), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(12, 84, 0), Vector3i(14, 85, 3), VoxMat.id("lamp"))
	# Crossbar for overhead wires.
	v.fill_box(Vector3i(0, 76, 1), Vector3i(5, 77, 2), VoxMat.id("metal_dark"))
	return v


static func road_sign(kind: String) -> VoxelVolume:
	var v := Build.vol(Vector3i(13, 34, 2))
	v.fill_box(Vector3i(6, 0, 1), Vector3i(7, 26, 2), VoxMat.id("metal"))
	var white := VoxMat.id("pvc")
	match kind:
		"stop":
			# Red octagon with a white legend bar.
			var red := VoxMat.id("brand_red")
			for row in 11:
				var inset := (3 - row) if row < 3 else maxi(0, row - 7)
				v.fill_box(Vector3i(1 + inset, 23 + row, 0), Vector3i(12 - inset, 24 + row, 1), red)
			v.fill_box(Vector3i(3, 27, 0), Vector3i(10, 30, 1), white)
		"crossing":
			# Yellow diamond with a dark walker.
			var yel := VoxMat.id("plastic_yellow")
			for row in 11:
				var half := 5 - absi(row - 5)
				v.fill_box(Vector3i(6 - half, 23 + row, 0), Vector3i(7 + half, 24 + row, 1), yel)
			v.fill_box(Vector3i(6, 25, 0), Vector3i(7, 31, 1), VoxMat.id("tank_black"))
			v.fill_box(Vector3i(5, 27, 0), Vector3i(8, 28, 1), VoxMat.id("tank_black"))
		"bus":
			v.fill_box(Vector3i(2, 24, 0), Vector3i(11, 32, 1), white)
			v.fill_box(Vector3i(3, 26, 0), Vector3i(10, 30, 1), VoxMat.id("metal_blue"))
			v.fill_box(Vector3i(4, 25, 0), Vector3i(5, 26, 1), VoxMat.id("tank_black"))
			v.fill_box(Vector3i(8, 25, 0), Vector3i(9, 26, 1), VoxMat.id("tank_black"))
		_:
			v.fill_box(Vector3i(3, 24, 0), Vector3i(10, 31, 1), white)
	return v


static func kiosk(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(40, 28, 23))
	Build.walls(v, 0, 0, 40, 22, 0, 24, 1, "concrete", seed)
	v.fill_box(Vector3i(0, 24, 0), Vector3i(40, 26, 22), VoxMat.id("metal_white"))
	v.fill_box(Vector3i(2, 8, 21), Vector3i(38, 20, 22), VoxMat.id("glass"))
	v.fill_box(Vector3i(0, 15, 21), Vector3i(40, 24, 22), VoxMat.id("plastic_blue"))
	VoxelFont.draw(v, "NEWS", Vector3i(9, 23, 22), Vector3i(1, 0, 0), VoxMat.id("sign_glow"))
	return v


# ---------------------------------------------------------------- railway

static func railway(length: int, seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 8, 72))
	var bal := VoxMat.ids("ballast")
	for k in 4:
		v.fill_box_noise(Vector3i(0, k, 2 + k * 2), Vector3i(length, k + 1, 70 - k * 2), bal, seed + k)
	for track in [20, 50]:
		for x in range(1, length, 6):
			v.fill_box_noise(Vector3i(x, 4, track - 13), Vector3i(x + 3, 5, track + 13), VoxMat.ids("wood_dark"), seed + x)
		for side in [-8, 8]:
			v.fill_box(Vector3i(0, 5, track + side), Vector3i(length, 7, track + side + 1), VoxMat.id("rail"))
	return v


## Railway tank car (black, explosive) or a boxcar, facing x.
static func wagon(tank: bool, seed: int) -> VoxelVolume:
	var L := 120
	var v := Build.vol(Vector3i(L, 44, 32))
	var md := VoxMat.id("metal_dark")
	v.fill_box(Vector3i(4, 6, 6), Vector3i(L - 4, 9, 26), md)
	for bx in [14, L - 26]:
		v.fill_box(Vector3i(bx, 0, 7), Vector3i(bx + 12, 6, 25), md)
		for wx in [bx + 3, bx + 9]:
			v.fill_cylinder(Vector3(wx, 3, 7), 3.0, 2, 2, VoxMat.id("rail"))
			v.fill_cylinder(Vector3(wx, 3, 23), 3.0, 2, 2, VoxMat.id("rail"))
	if tank:
		var c := VoxMat.id("tank_black")
		v.fill_cylinder(Vector3(6, 22, 16), 13.0, L - 12, 0, c)
		v.fill_cylinder(Vector3(6, 22, 16), 11.5, L - 12, 0, 0)
		v.fill_cylinder(Vector3(6, 22, 16), 13.0, 2, 0, c)
		v.fill_cylinder(Vector3(L - 8, 22, 16), 13.0, 2, 0, c)
		v.fill_cylinder(Vector3(L / 2.0, 34, 16), 4.0, 6, 1, c)
		v.fill_box(Vector3i(20, 20, 3), Vector3i(L - 20, 24, 4), VoxMat.id("plastic_yellow"))
	else:
		var c := VoxMat.ids("metal_brown")
		v.fill_planks(Vector3i(4, 9, 2), Vector3i(L - 4, 40, 30), 1, 0, 2, c, seed)
		v.fill_box(Vector3i(5, 10, 3), Vector3i(L - 5, 39, 29), 0)
		v.fill_box(Vector3i(L / 2 - 14, 10, 29), Vector3i(L / 2 + 14, 37, 30), VoxMat.id("metal_rust"))
	return v


# ---------------------------------------------------------------- river

static func pier(length: int, seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 28, 30))
	for x in range(0, length, 20):
		for z in [1, 27]:
			v.fill_box(Vector3i(x, 0, z), Vector3i(x + 2, 22, z + 2), VoxMat.id("wood_dark"))
	v.fill_planks(Vector3i(0, 20, 0), Vector3i(length, 22, 30), 2, 0, 2, VoxMat.ids("wood_grey"), seed)
	for x in range(0, length, 4):
		if (x / 4 + seed) % 9 == 0:
			v.fill_box(Vector3i(x, 20, 0), Vector3i(x + 2, 22, 30), 0)
	return v


static func rowboat(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(36, 7, 13))
	var w := VoxMat.ids(["wood_grey", "metal_green", "wood_red"][seed % 3])
	for x in 36:
		var t := absf(x - 18.0) / 18.0
		var half := int(6.0 * (1.0 - t * t))
		if half < 1:
			continue
		v.fill_box_noise(Vector3i(x, 0, 6 - half), Vector3i(x + 1, 6, 7 + half), w, seed + x)
		if half > 2:
			v.fill_box(Vector3i(x, 1, 7 - half), Vector3i(x + 1, 6, 6 + half), 0)
	v.fill_box(Vector3i(16, 3, 2), Vector3i(20, 4, 11), VoxMat.id("wood"))
	return v


static func reeds(seed: int) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := Build.vol(Vector3i(30, 18, 30))
	for k in 70:
		var x := rng.randi_range(0, 29)
		var z := rng.randi_range(0, 29)
		var h := rng.randi_range(7, 17)
		v.fill_box(Vector3i(x, 0, z), Vector3i(x + 1, h, z + 1), VoxMat.id("reed"))
		if rng.randf() < 0.3:
			v.fill_box(Vector3i(x, h - 3, z), Vector3i(x + 1, h, z + 1), VoxMat.id("wood_dark"))
	return v


# ---------------------------------------------------------------- trees

static func birch(seed: int) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var h := rng.randi_range(70, 95)
	var v := Build.vol(Vector3i(44, h + 14, 44))
	var lean := Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
	var base := Vector3(22, 0, 22)
	var tip := base + Vector3(0, h * 0.8, 0) + lean
	Build.line(v, base, tip, 3, VoxMat.id("birch_bark"))
	# Black marks on the bark.
	for k in 40:
		var t := rng.randf()
		var p := base.lerp(tip, t) + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var q := Vector3i(p.floor())
		if v.get_voxel(q) == VoxMat.id("birch_bark"):
			v.set_voxel(q, VoxMat.id("birch_mark"))
	for b in 6:
		var a := rng.randf() * TAU
		var y0 := h * rng.randf_range(0.4, 0.75)
		var from := base.lerp(tip, y0 / (h * 0.8))
		var to := from + Vector3(cos(a) * 9.0, rng.randf_range(4, 10), sin(a) * 9.0)
		Build.line(v, from, to, 1, VoxMat.id("birch_bark"))
		v.fill_ellipsoid_noise(to + Vector3(0, -1, 0), Vector3(7, 9, 7), VoxMat.ids("birch_leaf"), 0.88, 0.45, seed + b)
	v.fill_ellipsoid_noise(tip + Vector3(0, 2, 0), Vector3(9, 14, 9), VoxMat.ids("birch_leaf"), 0.9, 0.4, seed + 50)
	return v


static func linden(seed: int) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := Build.vol(Vector3i(56, 84, 56))
	var c := Vector3(28, 0, 28)
	var th := rng.randi_range(30, 42)
	v.fill_cylinder(c, 2.8, th, 1, VoxMat.id("wood_dark"))
	var crown := Vector3(28, th + 18, 28)
	for b in 5:
		var a := b * TAU / 5.0 + rng.randf_range(-0.4, 0.4)
		var tip := crown + Vector3(cos(a) * 13.0, rng.randf_range(-6, 6), sin(a) * 13.0)
		Build.line(v, Vector3(28, th - 4, 28), tip, 2, VoxMat.id("wood_dark"))
		v.fill_ellipsoid_noise(tip, Vector3(11, 9, 11), VoxMat.ids("leaf_dark" if b % 2 == 0 else "foliage"), 0.9, 0.4, seed + b)
	v.fill_ellipsoid_noise(crown + Vector3(0, 8, 0), Vector3(15, 12, 15), VoxMat.ids("foliage"), 0.9, 0.4, seed + 9)
	return v


static func hedge(length: int, seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 12, 10))
	v.fill_ellipsoid_noise(Vector3(length * 0.5, 4, 5), Vector3(length * 0.5, 7, 5), VoxMat.ids("leaf_dark"), 0.93, 0.35, seed)
	return v


# ---------------------------------------------------------------- vehicles

## Hub centers (object space, meters) for the 4 wheels, front wheels first.
static func hubs(front_x: int, rear_x: int, width: int, hub_y: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for wx in [front_x, rear_x]:
		for wz in [1.5, width - 1.5]:
			out.append(Vector3(wx, hub_y, wz) * VS)
	return out


static func _wheels(v: VoxelVolume, xs: Array, width: int, r: float) -> void:
	for wx in xs:
		for wz in [0, width - 3]:
			v.fill_cylinder(Vector3(wx, r, wz), r - 0.1, 3, 2, VoxMat.id("rubber"))
			v.fill_cylinder(Vector3(wx, r, wz), r * 0.45, 3, 2, VoxMat.id("metal"))


## GAZelle: van (cargo) or yellow minibus taxi with side windows.
static func gazelle(minibus: bool, seed: int) -> Dictionary:
	var L := 54
	var W := 21
	var v := Build.vol(Vector3i(L, 26, W))
	var body := VoxMat.ids("plastic_yellow" if minibus else "metal_white")
	var g := VoxMat.id("glass")
	v.fill_box_noise(Vector3i(0, 3, 0), Vector3i(L, 24, W), body, seed)
	v.fill_box(Vector3i(1, 4, 1), Vector3i(L - 1, 23, W - 1), 0)
	# Hood + cab glass.
	v.fill_box(Vector3i(0, 14, 0), Vector3i(8, 24, W), 0)
	v.fill_box_noise(Vector3i(0, 3, 0), Vector3i(8, 13, W), body, seed + 1)
	v.fill_box(Vector3i(8, 13, 0), Vector3i(9, 22, W), g)
	v.fill_box(Vector3i(9, 13, 0), Vector3i(18, 21, 1), g)
	v.fill_box(Vector3i(9, 13, W - 1), Vector3i(18, 21, W), g)
	if minibus:
		for x in range(20, L - 4, 8):
			v.fill_box(Vector3i(x, 14, 0), Vector3i(x + 6, 21, 1), g)
			v.fill_box(Vector3i(x, 14, W - 1), Vector3i(x + 6, 21, W), g)
	v.fill_box(Vector3i(9, 4, 3), Vector3i(13, 11, 9), VoxMat.id("plastic_blue"))
	v.fill_box(Vector3i(0, 6, 2), Vector3i(1, 9, 5), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 6, W - 5), Vector3i(1, 9, W - 2), VoxMat.id("lamp"))
	v.fill_box(Vector3i(L - 1, 6, 2), Vector3i(L, 9, 4), VoxMat.id("metal_red"))
	v.fill_box(Vector3i(L - 1, 6, W - 4), Vector3i(L, 9, W - 2), VoxMat.id("metal_red"))
	v.fill_box(Vector3i(0, 3, 0), Vector3i(1, 5, W), VoxMat.id("metal_dark"))
	_wheels(v, [8, 44], W, 3.5)
	return {"volume": v, "hubs": hubs(8, 44, W, 3.5)}


## PAZ city bus: white with a blue stripe, window band, doors on the right side.
static func paz_bus(seed: int) -> Dictionary:
	var L := 72
	var W := 24
	var v := Build.vol(Vector3i(L, 31, W))
	var white := VoxMat.ids("metal_white")
	var g := VoxMat.id("glass")
	v.fill_box_noise(Vector3i(0, 4, 0), Vector3i(L, 30, W), white, seed)
	v.fill_box(Vector3i(1, 5, 1), Vector3i(L - 1, 29, W - 1), 0)
	v.fill_box(Vector3i(0, 10, 0), Vector3i(L, 13, W), VoxMat.id("metal_blue"))
	v.fill_box(Vector3i(1, 5, 1), Vector3i(L - 1, 29, W - 1), 0)
	for x in range(4, L - 4, 9):
		v.fill_box(Vector3i(x, 14, 0), Vector3i(x + 7, 25, 1), g)
		v.fill_box(Vector3i(x, 14, W - 1), Vector3i(x + 7, 25, W), g)
	v.fill_box(Vector3i(0, 13, 2), Vector3i(1, 27, W - 2), g)
	v.fill_box(Vector3i(L - 1, 16, 4), Vector3i(L, 26, W - 4), g)
	# Doors on the right (+z when driving -x): dark glass strips.
	for dx in [6, 44]:
		v.fill_box(Vector3i(dx, 4, W - 1), Vector3i(dx + 10, 26, W), VoxMat.id("tank_black"))
	for x in range(6, L - 6, 6):
		v.fill_box(Vector3i(x, 5, 4), Vector3i(x + 3, 11, 9), VoxMat.id("plastic_red"))
		v.fill_box(Vector3i(x, 5, W - 9), Vector3i(x + 3, 11, W - 4), VoxMat.id("plastic_red"))
	v.fill_box(Vector3i(0, 6, 2), Vector3i(1, 9, 5), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 6, W - 5), Vector3i(1, 9, W - 2), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 26, 4), Vector3i(1, 29, W - 4), VoxMat.id("sign_glow"))
	_wheels(v, [12, 58], W, 4.5)
	return {"volume": v, "hubs": hubs(12, 58, W, 4.5)}


## Delivery truck with a box body (brand stripe).
static func box_truck(seed: int) -> Dictionary:
	var L := 66
	var W := 24
	var v := Build.vol(Vector3i(L, 36, W))
	var cab := VoxMat.ids("metal_white")
	var g := VoxMat.id("glass")
	v.fill_box_noise(Vector3i(0, 4, 1), Vector3i(16, 24, W - 1), cab, seed)
	v.fill_box(Vector3i(1, 5, 2), Vector3i(15, 23, W - 2), 0)
	v.fill_box(Vector3i(0, 13, 2), Vector3i(1, 22, W - 2), g)
	v.fill_box(Vector3i(3, 13, 1), Vector3i(13, 21, 2), g)
	v.fill_box(Vector3i(3, 13, W - 2), Vector3i(13, 21, W - 1), g)
	v.fill_box(Vector3i(15, 3, 3), Vector3i(L, 5, W - 3), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(17, 5, 0), Vector3i(L, 35, W), VoxMat.id("pvc"))
	v.fill_box(Vector3i(18, 6, 1), Vector3i(L - 1, 34, W - 1), 0)
	v.fill_box(Vector3i(17, 10, 0), Vector3i(L, 14, W), VoxMat.id("metal_blue"))
	v.fill_box(Vector3i(17, 14, 0), Vector3i(L, 16, W), VoxMat.id("brand_red"))
	v.fill_box(Vector3i(0, 6, 3), Vector3i(1, 9, 6), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 6, W - 6), Vector3i(1, 9, W - 3), VoxMat.id("lamp"))
	_wheels(v, [9, 54], W, 4.5)
	return {"volume": v, "hubs": hubs(9, 54, W, 4.5)}


# ---------------------------------------------------------------- americana

static func fire_hydrant(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(5, 8, 5))
	var c := VoxMat.id("metal_red" if seed % 3 != 0 else "metal_yellow")
	v.fill_cylinder(Vector3(2.5, 0, 2.5), 2.4, 1, 1, c)
	v.fill_cylinder(Vector3(2.5, 1, 2.5), 1.6, 6, 1, c)
	v.fill_cylinder(Vector3(2.5, 7, 2.5), 1.0, 1, 1, VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(0, 4, 2), Vector3i(5, 5, 3), c)
	return v


static func mailbox() -> VoxelVolume:
	var v := Build.vol(Vector3i(6, 12, 6))
	var b := VoxMat.id("metal_blue")
	for p in [Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 4), Vector2i(4, 4)]:
		v.fill_box(Vector3i(p.x, 0, p.y), Vector3i(p.x + 1, 3, p.y + 1), b)
	v.fill_box(Vector3i(0, 3, 0), Vector3i(6, 10, 6), b)
	v.fill_cylinder(Vector3(0, 10, 3), 3.0, 6, 0, b)
	v.fill_box(Vector3i(1, 8, 0), Vector3i(5, 9, 1), VoxMat.id("metal_dark"))
	return v


static func flag_pole() -> VoxelVolume:
	var v := Build.vol(Vector3i(22, 82, 3))
	v.fill_box(Vector3i(0, 0, 0), Vector3i(3, 2, 3), VoxMat.id("concrete"))
	v.fill_box(Vector3i(1, 0, 1), Vector3i(2, 80, 2), VoxMat.id("metal_white"))
	v.fill_sphere(Vector3(1.5, 80.5, 1.5), 1.2, VoxMat.id("metal_yellow"))
	DistrictBuildings._us_flag(v, Vector3i(2, 64, 1), 1)
	return v


static func basketball_hoop() -> VoxelVolume:
	var v := Build.vol(Vector3i(14, 34, 14))
	v.fill_box(Vector3i(6, 0, 0), Vector3i(8, 28, 2), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(6, 26, 0), Vector3i(8, 28, 6), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(1, 24, 6), Vector3i(13, 33, 7), VoxMat.id("pvc"))
	v.fill_box(Vector3i(5, 25, 6), Vector3i(9, 29, 7), VoxMat.id("brand_red"))
	v.fill_box(Vector3i(6, 26, 6), Vector3i(8, 28, 7), VoxMat.id("pvc"))
	v.fill_cylinder(Vector3(7, 24, 10), 3.0, 1, 1, VoxMat.id("plastic_orange"))
	v.fill_cylinder(Vector3(7, 24, 10), 2.0, 1, 1, 0)
	return v


static func picnic_table(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(18, 8, 14))
	var w := VoxMat.ids("wood_grey" if seed % 2 == 0 else "wood")
	v.fill_planks(Vector3i(0, 7, 4), Vector3i(18, 8, 10), 0, 2, 2, w, seed)
	v.fill_planks(Vector3i(0, 4, 0), Vector3i(18, 5, 3), 0, 2, 3, w, seed + 1)
	v.fill_planks(Vector3i(0, 4, 11), Vector3i(18, 5, 14), 0, 2, 3, w, seed + 2)
	for x in [2, 15]:
		Build.line(v, Vector3(x, 0, 1), Vector3(x, 7, 7), 1, VoxMat.id("wood_dark"))
		Build.line(v, Vector3(x, 0, 13), Vector3(x, 7, 7), 1, VoxMat.id("wood_dark"))
	return v


## Chain-link fence: steel posts, top rail and a see-through wire grid.
static func chain_link(length: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(length, 20, 2))
	var m := VoxMat.id("metal")
	for x in range(0, length, 25):
		v.fill_box(Vector3i(x, 0, 0), Vector3i(x + 1, 20, 2), VoxMat.id("metal_dark"))
	v.fill_box(Vector3i(0, 19, 0), Vector3i(length, 20, 1), m)
	for x in range(0, length, 2):
		v.fill_box(Vector3i(x, 0, 1), Vector3i(x + 1, 19, 2), m)
	for y in range(1, 19, 3):
		v.fill_box(Vector3i(0, y, 1), Vector3i(length, y + 1, 2), m)
	return v


## Wooden utility pole with a crossarm, insulators and a transformer can.
static func utility_pole() -> VoxelVolume:
	var v := Build.vol(Vector3i(26, 102, 3))
	v.fill_cylinder(Vector3(13, 0, 1.5), 1.4, 100, 1, VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(1, 90, 1), Vector3i(25, 92, 2), VoxMat.id("wood_dark"))
	for x in [2, 8, 18, 24]:
		v.fill_box(Vector3i(x, 92, 1), Vector3i(x + 1, 94, 2), VoxMat.id("plastic_white"))
	v.fill_cylinder(Vector3(15.5, 78, 1.5), 1.8, 6, 1, VoxMat.id("metal"))
	return v


static func maple(seed: int) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := Build.vol(Vector3i(56, 84, 56))
	var c := Vector3(28, 0, 28)
	var th := rng.randi_range(26, 36)
	v.fill_cylinder(c, 2.6, th, 1, VoxMat.id("wood_dark"))
	var leaves := ["maple_red", "maple_orange", "maple_yellow", "foliage", "leaf_dark"]
	var kind: String = leaves[seed % leaves.size()]
	var crown := Vector3(28, th + 18, 28)
	for b in 5:
		var a := b * TAU / 5.0 + rng.randf_range(-0.4, 0.4)
		var tip := crown + Vector3(cos(a) * 12.0, rng.randf_range(-5, 6), sin(a) * 12.0)
		Build.line(v, Vector3(28, th - 4, 28), tip, 2, VoxMat.id("wood_dark"))
		var lk: String = kind if rng.randf() < 0.75 else leaves[rng.randi() % 3]
		v.fill_ellipsoid_noise(tip, Vector3(10, 9, 10), VoxMat.ids(lk), 0.92, 0.4, seed + b)
	v.fill_ellipsoid_noise(crown + Vector3(0, 7, 0), Vector3(14, 12, 14), VoxMat.ids(kind), 0.92, 0.4, seed + 9)
	return v


## Yellow school bus (faces -x like the cars), hubs for VoxelVehicle.
static func school_bus(seed: int) -> Dictionary:
	var L := 92
	var W := 25
	var v := Build.vol(Vector3i(L, 31, W))
	var y := VoxMat.ids("metal_yellow")
	var g := VoxMat.id("glass")
	var blk := VoxMat.id("tank_black")
	# Hood in front, box body behind.
	v.fill_box_noise(Vector3i(0, 4, 2), Vector3i(12, 15, W - 2), y, seed)
	v.fill_box_noise(Vector3i(12, 4, 0), Vector3i(L, 30, W), y, seed + 1)
	v.fill_box(Vector3i(13, 5, 1), Vector3i(L - 1, 29, W - 1), 0)
	v.fill_box(Vector3i(0, 4, 2), Vector3i(1, 6, W - 2), VoxMat.id("metal_dark"))
	for k in 2:
		v.fill_box(Vector3i(12, 10 + k * 4, 0), Vector3i(L, 11 + k * 4, W), blk)
	for x in range(16, L - 4, 8):
		v.fill_box(Vector3i(x, 17, 0), Vector3i(x + 6, 25, 1), g)
		v.fill_box(Vector3i(x, 17, W - 1), Vector3i(x + 6, 25, W), g)
	v.fill_box(Vector3i(12, 15, 2), Vector3i(13, 27, W - 2), g)
	v.fill_box(Vector3i(14, 4, W - 1), Vector3i(20, 26, W), blk)
	# Lettering on both sides, readable from outside.
	VoxelFont.draw(v, "SCHOOL BUS", Vector3i(40, 29, W - 1), Vector3i(1, 0, 0), blk)
	VoxelFont.draw(v, "SCHOOL BUS", Vector3i(L - 30, 29, 0), Vector3i(-1, 0, 0), blk)
	v.fill_box(Vector3i(0, 8, 3), Vector3i(1, 11, 6), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 8, W - 6), Vector3i(1, 11, W - 3), VoxMat.id("lamp"))
	v.fill_box(Vector3i(12, 26, 0), Vector3i(13, 29, W), VoxMat.id("metal_red"))
	_wheels(v, [10, 76], W, 4.5)
	return {"volume": v, "hubs": hubs(10, 76, W, 4.5)}


## Pickup truck: cab and an open bed.
static func pickup(color: String, seed: int) -> Dictionary:
	var L := 50
	var W := 20
	var v := Build.vol(Vector3i(L, 18, W))
	var body := VoxMat.ids(color)
	var g := VoxMat.id("glass")
	v.fill_box_noise(Vector3i(0, 4, 0), Vector3i(L, 10, W), body, seed)
	v.fill_box(Vector3i(1, 5, 1), Vector3i(13, 10, W - 1), 0)
	v.fill_box_noise(Vector3i(0, 9, 0), Vector3i(13, 10, W), body, seed + 1)
	v.fill_box(Vector3i(13, 10, 0), Vector3i(27, 17, W), g)
	v.fill_box(Vector3i(14, 10, 1), Vector3i(26, 16, W - 1), 0)
	v.fill_box_noise(Vector3i(13, 17, 0), Vector3i(27, 18, W), body, seed + 2)
	v.fill_box(Vector3i(26, 10, 0), Vector3i(27, 17, W), body[0])
	v.fill_box(Vector3i(28, 6, 1), Vector3i(L - 1, 10, W - 1), 0)
	v.fill_box(Vector3i(17, 5, 3), Vector3i(20, 11, 9), VoxMat.id("plastic_blue"))
	v.fill_box(Vector3i(17, 5, 11), Vector3i(20, 11, 17), VoxMat.id("plastic_blue"))
	v.fill_box(Vector3i(0, 6, 2), Vector3i(1, 8, 5), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 6, W - 5), Vector3i(1, 8, W - 2), VoxMat.id("lamp"))
	v.fill_box(Vector3i(0, 3, 0), Vector3i(1, 5, W), VoxMat.id("metal"))
	v.fill_box(Vector3i(L - 1, 6, 2), Vector3i(L, 8, 4), VoxMat.id("metal_red"))
	v.fill_box(Vector3i(L - 1, 6, W - 4), Vector3i(L, 8, W - 2), VoxMat.id("metal_red"))
	_wheels(v, [8, 40], W, 3.8)
	return {"volume": v, "hubs": hubs(8, 40, W, 3.8)}


## Yellow taxi: the regular sedan with a checker stripe and a roof sign.
static func taxi(seed: int) -> VoxelVolume:
	var car := Build.car("plastic_yellow", seed)
	var s := Build.vol(car.get_size() + Vector3i(0, 3, 0))
	s.copy_from(car, Vector3i.ZERO, true)
	s.fill_box(Vector3i(17, 16, 6), Vector3i(25, 18, 13), VoxMat.id("pvc"))
	for x in range(12, 31, 4):
		s.fill_box(Vector3i(x, 7, 0), Vector3i(x + 2, 8, 1), VoxMat.id("tank_black"))
		s.fill_box(Vector3i(x, 7, 18), Vector3i(x + 2, 8, 19), VoxMat.id("tank_black"))
	return s
