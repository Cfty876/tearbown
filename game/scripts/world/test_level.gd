class_name TestLevel
## Builds the prototype test map: an 80x80 m industrial yard (after the reference
## shots) with brick house, red barn, brick tower, pylon, garage, greenhouse,
## vehicles, explosive tanks, stacks of crates and a forest edge.

const VS := 0.1
const SIZE := 800          # terrain voxels per side
const GROUND := 20         # terrain top in voxels (2.0 m)
const GY := GROUND * VS

var world: VoxelWorld
var spawn := Vector3(0, GY + 0.05, 25)
var rng := RandomNumberGenerator.new()
var _heights := PackedFloat32Array()


func _init(w: VoxelWorld) -> void:
	world = w
	rng.seed = 2024


func build() -> void:
	_terrain()
	Backdrop.build(world, GY, SIZE * VS * 0.5, 43.0, 77)
	_buildings()
	_props()
	_nature()


func _w(x: float, z: float) -> Vector3:
	return Vector3(x, GY, z)


# ------------------------------------------------------------------ terrain

func _terrain() -> void:
	var v := Build.vol(Vector3i(SIZE, 32, SIZE))
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var lo := 200
	var img := Image.create(lo, lo, false, Image.FORMAT_RF)
	for y in lo:
		for x in lo:
			var nx := absf(x / float(lo - 1) * 2.0 - 1.0)
			var ny := absf(y / float(lo - 1) * 2.0 - 1.0)
			# Mounds ring the yard and fall back to ground level at the map border,
			# where the far ground plane continues.
			var m := maxf(nx, ny)
			var edge := smoothstep(0.62, 0.82, m) * (1.0 - smoothstep(0.9, 1.0, m))
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(edge * (0.25 + 0.75 * n), 0, 0))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	var heights := img.get_data().to_float32_array()
	var layers := PackedByteArray()
	layers.append(VoxMat.id("grass"))
	for i in 5:
		layers.append(VoxMat.id("dirt"))
	layers.append(VoxMat.id("rock"))
	v.fill_columns(Vector3i.ZERO, Vector3i(SIZE, 0, SIZE), heights, GROUND, 11.0, layers, 0 if OS.has_feature("web") else 3)
	_heights = heights
	# gravel yard in the middle, dirt patches, asphalt road with markings
	_patch(v, -32, -32, 32, 14, "gravel", 1)
	_patch(v, 6, -20, 22, -4, "dirt", 1)
	_patch(v, -26, -2, -18, 6, "dirt", 1)
	var rz0 := _vz(16.0)
	var rz1 := _vz(21.0)
	v.fill_box(Vector3i(0, GROUND, rz0 - 6), Vector3i(SIZE, 32, rz1 + 6), 0)
	v.fill_box_noise(Vector3i(0, GROUND - 3, rz0), Vector3i(SIZE, GROUND, rz1), VoxMat.ids("asphalt"), 5)
	for x in range(0, SIZE, 40):
		v.fill_box_noise(Vector3i(x, GROUND - 1, (rz0 + rz1) / 2), Vector3i(x + 22, GROUND, (rz0 + rz1) / 2 + 2), VoxMat.ids("road_line"), 6)
	v.fill_box_noise(Vector3i(0, 0, 0), Vector3i(SIZE, 4, SIZE), VoxMat.ids("bedrock"), 1)
	var o := Build.place(world, v, Vector3(0, 0, 0), true, 0.0, "terrain", Vector3i(64, 32, 64))
	o.position = Vector3(-SIZE * VS * 0.5, 0, -SIZE * VS * 0.5)


func _vx(x: float) -> int:
	return int((x + SIZE * VS * 0.5) / VS)


func _vz(z: float) -> int:
	return int((z + SIZE * VS * 0.5) / VS)


func _patch(v: VoxelVolume, x0: float, z0: float, x1: float, z1: float, swatch: String, depth: int) -> void:
	v.fill_box_noise(Vector3i(_vx(x0), GROUND - depth, _vz(z0)), Vector3i(_vx(x1), GROUND, _vz(z1)), VoxMat.ids(swatch), _vx(x0))


# ------------------------------------------------------------------ buildings

var house: VoxelObject

func _buildings() -> void:
	house = Build.place(world, Build.brick_house(11), _w(-14, -8), true, 180.0, "house")
	Build.house_lamps(house)
	var barn := Build.place(world, Build.barn(12), _w(13, -12), true, 180.0, "barn")
	Build.lamp_light(barn, Vector3i(3 + 21, 40, 3 + 3), Color(1.0, 0.8, 0.5), 1.6, 9.0)
	Build.place(world, Build.brick_tower(13), _w(-1, -27), true, 0.0, "tower")
	Build.place(world, Build.pylon(14), _w(-30, 9), true, 90.0, "pylon")
	var garage := Build.place(world, Build.garage(15), _w(26, 6), true, 90.0, "garage")
	Build.lamp_light(garage, Vector3i(35, 33, 31), Color(0.85, 0.92, 1.0), 1.8, 9.0)
	Build.place(world, Build.greenhouse(16), _w(-12, 11), true, 180.0, "greenhouse")
	Build.place(world, Build.picket_fence(180, 3), _w(-27, -2), true, 90.0, "fence")
	Build.place(world, Build.picket_fence(140, 4), _w(-2, -16), true, 0.0, "fence")
	Build.place(world, Build.brick_wall(160, 16, 5), _w(24, -2), true, 0.0, "wall")
	for x in [-24.0, 0.0, 24.0]:
		var lp := Build.place(world, Build.lamp_post(), _w(x, 21.6), true, 180.0, "lamp_post")
		Build.lamp_light(lp, Vector3i(10, 55, 1), Color(1.0, 0.78, 0.5), 3.0, 12.0)


# ------------------------------------------------------------------ props

func _dyn(v: VoxelVolume, pos: Vector3, yaw := 0.0, label := "") -> VoxelObject:
	return Build.place(world, v, pos, false, yaw, label)


func _props() -> void:
	# House interior (house is rotated 180 deg, so place via its transform).
	var floor_y := 3
	for p in [[Vector3i(25, floor_y, 30), 0.0], [Vector3i(85, floor_y, 60), 90.0]]:
		_dyn(Build.table(rng.randi()), house.to_global(Vector3(p[0]) * VS), p[1], "table")
	for p in [Vector3i(21, floor_y, 20), Vector3i(31, floor_y, 20), Vector3i(25, floor_y, 40), Vector3i(78, floor_y, 46)]:
		_dyn(Build.chair(rng.randi()), house.to_global(Vector3(p) * VS), rng.randf() * 360.0, "chair")
	_dyn(Build.shelf(3), house.to_global(Vector3(30, floor_y, 86) * VS), 180.0, "shelf")
	_dyn(Build.shelf(4), house.to_global(Vector3(30, 35, 86) * VS), 180.0, "shelf")
	_dyn(Build.table(5), house.to_global(Vector3(30, 35, 40) * VS), 0.0, "table")
	_dyn(Build.crate(8, 7), house.to_global(Vector3(70, 35, 30) * VS), 10.0, "crate")

	# Crate pyramid
	var c0 := Vector3(3, GY, 6)
	for row in 3:
		for i in 3 - row:
			var p := c0 + Vector3((i - (2 - row) * 0.5) * 0.92, row * 0.9, 0)
			_dyn(Build.crate(9, rng.randi()), p, rng.randf_range(-4, 4), "crate")
	for i in 6:
		_dyn(Build.crate(rng.randi_range(6, 10), rng.randi()), _w(rng.randf_range(10, 18), rng.randf_range(-24, -18)), rng.randf() * 90.0, "crate")

	# Jenga plank tower
	var j0 := _w(-3, 3)
	for layer in 10:
		for k in 3:
			var off := (k - 1) * 0.45
			var p := j0 + Vector3(0, layer * 0.205, 0)
			if layer % 2 == 0:
				p.z += off
				_dyn(Build.plank(24, layer * 3 + k), p, 0.0, "plank")
			else:
				p.x += off
				_dyn(Build.plank(24, layer * 3 + k), p, 90.0, "plank")

	# Explosive propane tanks (reference: red tanks around the yard)
	for p in [_w(-5, -4), _w(7, -17), _w(-23, -1), _w(19, 3), _w(-8, -16)]:
		var t := _dyn(Build.propane_tank(), p, rng.randf() * 180.0, "propane")
		t.explosive_radius = 2.6
		t.explosive_power = 6.5
	# Barrels: red ones are explosive
	for i in 9:
		var red := i % 3 == 0
		var b := _dyn(Build.barrel("metal_red" if red else ("metal_blue" if i % 3 == 1 else "metal_rust")),
			_w(12.0 + (i % 3) * 0.75, 1.2 + (i / 3) * 0.75), rng.randf() * 90.0, "barrel")
		if red:
			b.explosive_radius = 2.0
			b.explosive_power = 6.0

	# Containers (two stacked) and concrete barriers
	_dyn(Build.container("metal_green", 1), _w(8, -2), 0.0, "container")
	_dyn(Build.container("metal_blue", 2), _w(8, -2 + 0.02), 0.0, "container").position.y += 2.62
	_dyn(Build.container("metal_rust", 3), _w(-20, -18), 70.0, "container")
	for i in 5:
		_dyn(Build.concrete_block(i), _w(-14 + i * 2.2, 15.2), rng.randf_range(-6, 6), "barrier")

	# Vehicles
	for c in [["metal_blue", _w(6, 17.6), 0.0], ["metal_red", _w(-19, 19.6), 182.0]]:
		var car := _dyn(Build.car(c[0], rng.randi()), c[1], c[2], "car")
		VoxelVehicle.attach(car, Build.car_hubs(), Vector3(-1, 0, 0))
	_dyn(Build.excavator(3), _w(26, -9), 200.0, "excavator")

	# Brick piles and pallets near the tower
	for i in 4:
		_dyn(Build.pallet(i), _w(4 + i * 1.4, -22), 0.0, "pallet")
		_dyn(Build.brick_pile(i), _w(4 + i * 1.4, -22) + Vector3(0, 0.2, 0), 0.0, "bricks")


# ------------------------------------------------------------------ nature

func _nature() -> void:
	# Pine forest around the edge of the yard.
	var placed := 0
	var attempts := 0
	while placed < 28 and attempts < 400:
		attempts += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(31.0, 37.0)
		var p := Vector2(cos(a), sin(a)) * r
		if absf(p.y - 18.5) < 4.0:
			continue  # keep the road clear
		_place_tree(Build.pine_tree(rng.randi(), rng.randi_range(70, 95)), p)
		placed += 1
	for p in [Vector2(-24, -14), Vector2(-4, 12), Vector2(20, 14), Vector2(-30, 24)]:
		_place_tree(Build.leafy_tree(rng.randi()), p)
	for p in [Vector2(-22, -1.5), Vector2(-6, -1.8), Vector2(-21.5, -14.5), Vector2(-7, -14.5), Vector2(2, -14),
			Vector2(-3, 9), Vector2(5, 11), Vector2(12, 9), Vector2(-18, 14), Vector2(-25, 4), Vector2(3, -27),
			Vector2(-5, -28), Vector2(30, -14), Vector2(31, 14)]:
		_place_tree(Build.bush(rng.randi()), p)


func _place_tree(v: VoxelVolume, p: Vector2) -> void:
	# Sit trees slightly into the ground so they follow the edge mounds.
	var y := _ground_height(p) - 0.1
	Build.place(world, v, Vector3(p.x, y, p.y), true, rng.randf() * 360.0, "tree")


func _ground_height(p: Vector2) -> float:
	var x := clampi(_vx(p.x), 0, SIZE - 1)
	var z := clampi(_vz(p.y), 0, SIZE - 1)
	return floorf(GROUND + _heights[x + z * SIZE] * 11.0) * VS
