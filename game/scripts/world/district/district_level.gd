class_name DistrictLevel
## "Пригород": a small American town block, laid out after the original reference
## (top-down) shot. 204.8 x 204.8 m, every object destructible.
## Layout (meters, x east, z south, origin = map center):
##   river with a pier on the west, self storage + sheds north, FOOD MART NE with
##   parking, five brick walk-ups around a playground courtyard, PHARMACY SW,
##   auto repair and dumpster enclosure SE, main road with bus stops south,
##   side road east, chain-link fence and railway along the south edge.

const VS := 0.1
const SIZE := 2048
const TILE := 256
const GROUND := 20
const GY := 2.0
const HALF := SIZE * VS * 0.5
const OCC_N := 206
const WATER_Y := 1.62

## River centerline (x, z, half width) in meters.
const RIVER := [
	Vector3(-55, -108, 13), Vector3(-60, -88, 13), Vector3(-66, -70, 12), Vector3(-73, -52, 11),
	Vector3(-81, -34, 10), Vector3(-89, -16, 10), Vector3(-97, 2, 11), Vector3(-108, 16, 12),
]

var world: VoxelWorld
var _web := OS.has_feature("web")
var spawn := Vector3(12, GY + 0.05, 48.0)
var spawn_yaw := 0.0
var rng := RandomNumberGenerator.new()
var tiles := {}               # Vector2i -> VoxelVolume
var _occ := PackedByteArray()
var _heights := PackedFloat32Array()
var buildings := {}           # name -> VoxelObject (used by cinematics)
var vehicles: Array[VoxelVehicle] = []


func _init(w: VoxelWorld) -> void:
	world = w
	rng.seed = 1964
	_occ.resize(OCC_N * OCC_N)


func build() -> void:
	var t0 := Time.get_ticks_msec()
	_terrain()
	_ground_layout()
	_spawn_tiles()
	print("[district] terrain %d ms" % (Time.get_ticks_msec() - t0))
	_water()
	_buildings()
	print("[district] buildings %d ms" % (Time.get_ticks_msec() - t0))
	_courtyards()
	_street()
	_railway()
	_parked_cars()
	_traffic()
	_vegetation()
	Backdrop.build(world, GY, HALF, HALF + 4.0, 77)
	print("[district] total %d ms, %d objects" % [Time.get_ticks_msec() - t0, world.objects.size()])


# ================================================================== helpers

func _w(x: float, z: float, y := GY) -> Vector3:
	return Vector3(x, y, z)


func _vx(x: float) -> int:
	return int(floor((x + HALF) / VS))


## Fills a world-space rect [x0,x1) x [z0,z1) between voxel heights y0..y1 on all tiles.
func _fill(x0: float, z0: float, x1: float, z1: float, y0: int, y1: int, swatch: String, seed := 0) -> void:
	var values: PackedByteArray = VoxMat.ids(swatch) if swatch != "" else PackedByteArray()
	var a := Vector2i(_vx(x0), _vx(z0))
	var b := Vector2i(_vx(x1), _vx(z1))
	for tk: Vector2i in tiles:
		var o := tk * TILE
		var la := Vector3i(a.x - o.x, y0, a.y - o.y)
		var lb := Vector3i(b.x - o.x, y1, b.y - o.y)
		if lb.x <= 0 or lb.z <= 0 or la.x >= TILE or la.z >= TILE:
			continue
		var v: VoxelVolume = tiles[tk]
		if values.is_empty():
			v.fill_box(la, lb, 0)
		else:
			v.fill_box_noise(la, lb, values, seed)


func _occ_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	for z in range(maxi(int(z0 + HALF), 0), mini(int(ceil(z1 + HALF)), OCC_N)):
		for x in range(maxi(int(x0 + HALF), 0), mini(int(ceil(x1 + HALF)), OCC_N)):
			_occ[x + z * OCC_N] = 1


func _occ_free(x: float, z: float, r: float) -> bool:
	for zz in range(int(z - r + HALF), int(z + r + HALF) + 1):
		for xx in range(int(x - r + HALF), int(x + r + HALF) + 1):
			if xx < 0 or zz < 0 or xx >= OCC_N or zz >= OCC_N or _occ[xx + zz * OCC_N] != 0:
				return false
	return true


func _road(x0: float, z0: float, x1: float, z1: float) -> void:
	_fill(x0, z0, x1, z1, GROUND - 1, 32, "")
	_fill(x0, z0, x1, z1, GROUND - 4, GROUND - 1, "asphalt", int(x0 * 7 + z0))
	_occ_rect(x0, z0, x1, z1)
	# Patches and cracks make the asphalt look lived-in.
	var n := int((x1 - x0) * (z1 - z0) / 90.0)
	for k in n:
		var px := rng.randf_range(x0, x1 - 1.5)
		var pz := rng.randf_range(z0, z1 - 1.5)
		if rng.randf() < 0.6:
			_fill(px, pz, px + rng.randf_range(0.6, 2.5), pz + rng.randf_range(0.6, 2.0), GROUND - 2, GROUND - 1, "asphalt_patch", k)
		else:
			var horizontal := rng.randf() < 0.5
			_fill(px, pz, px + (rng.randf_range(1.5, 4) if horizontal else 0.1), pz + (0.1 if horizontal else rng.randf_range(1.5, 4)), GROUND - 2, GROUND - 1, "asphalt_patch", k)


func _sidewalk(x0: float, z0: float, x1: float, z1: float) -> void:
	_fill(x0, z0, x1, z1, GROUND - 3, GROUND, "sidewalk", int(x0 * 3 + z1))
	_occ_rect(x0, z0, x1, z1)


func _mark(x0: float, z0: float, x1: float, z1: float, swatch := "road_line") -> void:
	_fill(x0, z0, x1, z1, GROUND - 2, GROUND - 1, swatch)


func _dashes_x(x0: float, x1: float, z: float, dash := 3.0, gap := 3.0) -> void:
	var x := x0
	while x < x1:
		_mark(x, z - 0.1, minf(x + dash, x1), z + 0.1)
		x += dash + gap


func _dashes_z(z0: float, z1: float, x: float, dash := 3.0, gap := 3.0) -> void:
	var z := z0
	while z < z1:
		_mark(x - 0.1, z, x + 0.1, minf(z + dash, z1))
		z += dash + gap


func _place(v: VoxelVolume, pos: Vector3, static_mode: bool, yaw := 0.0, label := "", csize := Vector3i(32, 32, 32)) -> VoxelObject:
	var o := Build.place(world, v, pos, static_mode, yaw, label, csize)
	if not static_mode:
		return o
	if v.get_solid_count() < 600:
		for c in o.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visibility_range_end = 150.0
	return o


func _lights(o: VoxelObject, lamps: Array, color: Color, energy: float, rng_m: float) -> void:
	for l in lamps:
		Build.lamp_light(o, l, color, energy, rng_m, false)


# ================================================================== terrain

func _river_info(x: float, z: float) -> Vector2:
	# Returns (distance to centerline, half width there).
	var best := 1e9
	var best_w := 10.0
	for i in RIVER.size() - 1:
		var a: Vector3 = RIVER[i]
		var b: Vector3 = RIVER[i + 1]
		var ab := Vector2(b.x - a.x, b.y - a.y)
		var ap := Vector2(x - a.x, z - a.y)
		var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := (ap - ab * t).length()
		if d < best:
			best = d
			best_w = lerpf(a.z, b.z, t)
	return Vector2(best, best_w)


func _terrain() -> void:
	var lo := 512
	var cell := SIZE * VS / lo
	var img := Image.create(lo, lo, false, Image.FORMAT_RF)
	img.fill(Color(GROUND, 0, 0))
	for py in range(0, int((30.0 + HALF) / cell)):
		for px in range(0, int((-35.0 + HALF) / cell)):
			var x := (px + 0.5) * cell - HALF
			var z := (py + 0.5) * cell - HALF
			var info := _river_info(x, z)
			var d := info.x
			var w := info.y
			var h := float(GROUND)
			if d < w:
				h = 9.0 + 5.0 * pow(d / w, 2.0)
			elif d < w + 5.0:
				h = lerpf(14.0, GROUND, smoothstep(0.0, 1.0, (d - w) / 5.0))
			img.set_pixel(px, py, Color(h, 0, 0))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	_heights = img.get_data().to_float32_array()
	var layers := PackedByteArray([VoxMat.id("grass"), VoxMat.id("dirt"), VoxMat.id("dirt"), VoxMat.id("dirt"), VoxMat.id("dirt"), VoxMat.id("rock")])
	var grass := VoxMat.id("grass")
	for tz in SIZE / TILE:
		for tx in SIZE / TILE:
			var v := Build.vol(Vector3i(TILE, 32, TILE))
			var region := img.get_region(Rect2i(tx * TILE, tz * TILE, TILE, TILE))
			# The shader supplies grass variation without splitting the mesh into individual quads.
			var strata_seed := 0 if _web else tx * 31 + tz
			v.fill_columns(Vector3i.ZERO, Vector3i(TILE, 0, TILE), region.get_data().to_float32_array(), 0.0, 1.0, layers, strata_seed)
			# Wet banks and the riverbed.
			v.replace(Vector3i(0, 16, 0), Vector3i(TILE, GROUND - 1, TILE), grass, VoxMat.id("sand"))
			v.replace(Vector3i(0, 0, 0), Vector3i(TILE, 16, TILE), grass, VoxMat.id("mud"))
			v.fill_box_noise(Vector3i(0, 0, 0), Vector3i(TILE, 4, TILE), VoxMat.ids("bedrock"), 1)
			tiles[Vector2i(tx, tz)] = v
	# The river is not buildable.
	for z in OCC_N:
		for x in OCC_N:
			var wx := x - HALF + 0.5
			var wz := z - HALF + 0.5
			if wx < -30.0 and wz < 30.0:
				var info := _river_info(wx, wz)
				if info.x < info.y + 2.0:
					_occ[x + z * OCC_N] = 1


func ground_height(x: float, z: float) -> float:
	var vx := clampi(_vx(x), 0, SIZE - 1)
	var vz := clampi(_vx(z), 0, SIZE - 1)
	return floorf(_heights[vx + vz * SIZE]) * VS


func _ground_layout() -> void:
	# --- main road (south) and side road (east)
	_road(-HALF, 54, HALF, 68)
	_road(89, -HALF, 99, 54)
	_road(89, 68, 99, HALF)
	_mark(-HALF, 60.75, HALF, 60.9, "road_yellow")
	_mark(-HALF, 61.1, HALF, 61.25, "road_yellow")
	_dashes_x(-HALF, HALF, 57.5)
	_dashes_x(-HALF, HALF, 64.5)
	_mark(-HALF, 54.3, 89, 54.45)
	_mark(-HALF, 67.55, 89, 67.7)
	for zr in [Vector2(-HALF, 54), Vector2(68, HALF)]:
		_mark(93.75, zr.x, 93.9, zr.y, "road_yellow")
		_mark(94.1, zr.x, 94.25, zr.y, "road_yellow")
	# zebra crossings
	for zz in range(0, 14):
		_mark(-16, 54.4 + zz, -12, 54.9 + zz)
		_mark(80, 54.4 + zz, 84, 54.9 + zz)
	for xx in range(0, 10):
		_mark(89.3 + xx, 44, 89.8 + xx, 48)
	# sidewalks with curbs
	_sidewalk(-HALF, 50, 89, 54)
	_sidewalk(-HALF, 68, 89, 71.5)
	_sidewalk(85, -HALF, 89, 50)
	_sidewalk(99, -HALF, HALF, HALF)
	_fill(-HALF, 53.7, 89, 54, GROUND - 3, GROUND, "curb")
	_fill(-HALF, 68, 89, 68.3, GROUND - 3, GROUND, "curb")
	_fill(88.7, -HALF, 89, 50, GROUND - 3, GROUND, "curb")
	# --- inner roads
	_road(12, -56, 89, -51)              # along the Pyaterochka parking
	_road(22, -66, 78, -56)              # Pyaterochka parking
	for x in range(22, 79, 3):
		_mark(x, -66, x + 0.12, -62)
		_mark(x, -60, x + 0.12, -56)
	_road(-46, -101, -41, -36)           # west lane past the garages
	_road(-50, -86, 8, -80)              # between the garage rows
	_road(-46, -42, 13, -37)             # in front of block 1
	_road(-46, -37, -41, 13)             # west of the playground
	_road(6, -51, 11, 13)                # east of the playground
	_road(-88, 9, 89, 13)                # south courtyard road
	_road(54, -51, 59, 9)                # east courtyard lane
	_road(59, -44, 66, 6)                # east courtyard parking
	for z in range(-44, 7, 3):
		_mark(59, z, 63, z + 0.12)
	_road(-86, 31, -50, 47)              # Magnit parking
	_road(-60, 47, -54, 54)
	for x in range(-85, -51, 3):
		_mark(x, 31, x + 0.12, 35)
		_mark(x, 43, x + 0.12, 47)
	_road(44, 37, 66, 50)                # auto repair forecourt
	_fill(36, -41, 52, -25, GROUND - 1, GROUND, "asphalt", 3)    # basketball court
	_mark(36.3, -33.1, 51.7, -32.9)
	_occ_rect(36, -41, 52, -25)
	_road(44, 50, 52, 54)
	_fill(66, 30, 83, 45, GROUND - 3, GROUND, "concrete", 4)   # trash enclosure pad
	_occ_rect(66, 30, 83, 45)
	# --- sidewalks along buildings
	_sidewalk(-54, -52, 8, -46)          # block 1 front
	_sidewalk(-58, -46, -53, 1)          # block 2 front
	_sidewalk(13, -43, 17, 4)            # block 3 front
	_sidewalk(68, -47, 72, 15)           # block 4 front
	_sidewalk(-34, 13, 28, 15.5)         # block 5 front
	_sidewalk(22, -70, 70, -66)          # Pyaterochka front
	_sidewalk(-84, 30, -52, 31)          # Magnit front
	# --- playground: sand, worn paths
	_fill(-30, -27, -5, -4, GROUND - 2, GROUND, "sand", 9)
	_occ_rect(-30, -27, -5, -4)
	for k in 60:
		var t := k / 60.0
		var p1 := Vector2(-39, -35).lerp(Vector2(4, 7), t)
		var p2 := Vector2(-39, 7).lerp(Vector2(4, -35), t)
		for p in [p1, p2]:
			_fill(p.x - 0.7, p.y - 0.7, p.x + 0.7, p.y + 0.7, GROUND - 1, GROUND, "dirt", k)
	# worn dirt and gravel patches around the yard
	for k in 26:
		var px := rng.randf_range(-95, 95)
		var pz := rng.randf_range(-95, 48)
		_fill(px, pz, px + rng.randf_range(1, 4), pz + rng.randf_range(1, 3), GROUND - 1, GROUND, "dirt" if k % 2 == 0 else "gravel", k)
	# river bank path
	for i in RIVER.size() - 1:
		var a: Vector3 = RIVER[i]
		var b: Vector3 = RIVER[i + 1]
		for k in 20:
			var p := Vector2(a.x, a.y).lerp(Vector2(b.x, b.y), k / 20.0)
			var n := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
			var w := lerpf(a.z, b.z, k / 20.0)
			var q := p + n * (w + 7.5)
			if q.x > -HALF and q.y > -HALF:
				_fill(q.x - 0.8, q.y - 0.8, q.x + 0.8, q.y + 0.8, GROUND - 1, GROUND, "sand", k)


func _spawn_tiles() -> void:
	for tk: Vector2i in tiles:
		var o := VoxelObject.new()
		o.setup(tiles[tk], true, Vector3i(128, 32, 128))
		o.label = "ground"
		o.position = Vector3(tk.x * TILE * VS - HALF, 0, tk.y * TILE * VS - HALF)
		world.add_child(o)


func _water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 140)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(-80, WATER_Y, -40)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	# Reeds along the shore, a pier and boats.
	for i in RIVER.size() - 1:
		var a: Vector3 = RIVER[i]
		var b: Vector3 = RIVER[i + 1]
		for k in 3:
			var t := (k + rng.randf()) / 3.0
			var p := Vector2(a.x, a.y).lerp(Vector2(b.x, b.y), t)
			var n := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
			var w := lerpf(a.z, b.z, t)
			for side in [-1.0, 1.0]:
				var q: Vector2 = p + n * side * (w + rng.randf_range(-0.5, 1.5))
				if absf(q.x) < HALF - 2 and absf(q.y) < HALF - 2:
					_place(DistrictProps.reeds(rng.randi()), Vector3(q.x, ground_height(q.x, q.y) - 0.1, q.y), true, rng.randf() * 360.0, "reeds")
	# Pier on the east bank, pointing into the water.
	var a2: Vector3 = RIVER[2]
	var b2: Vector3 = RIVER[3]
	var mid := Vector2(a2.x, a2.y).lerp(Vector2(b2.x, b2.y), 0.4)
	var nrm := Vector2(b2.y - a2.y, -(b2.x - a2.x)).normalized()  # points east
	var bank := mid + nrm * 11.0
	var dir := -nrm
	var center := bank + dir * 4.0
	var yaw := rad_to_deg(atan2(-dir.y, dir.x))
	_place(DistrictProps.pier(90, 5), Vector3(center.x, 0.05, center.y), true, yaw, "pier")
	for k in 2:
		var bp := bank + dir * (5.0 + k * 3.5) + Vector2(-dir.y, dir.x) * (3.0 if k == 0 else -3.2)
		_place(DistrictProps.rowboat(k), Vector3(bp.x, WATER_Y - 0.35, bp.y), false, yaw + 80.0 + k * 20.0, "boat")


# ================================================================== buildings

func _block(name: String, sections: int, center: Vector2, yaw: float, panel: String, seed: int) -> VoxelObject:
	var info := DistrictBuildings.apartment_block(sections, seed, panel)
	var o := _place(info.volume, _w(center.x, center.y), true, yaw, name, Vector3i(64, 64, 64))
	o.add_occluder(info.interior)
	_lights(o, info.lamps, Color(1.0, 0.8, 0.52), 1.4, 6.0)
	buildings[name] = o
	var vol: VoxelVolume = info.volume
	var size := Vector3(vol.get_size()) * VS
	var half_ext := Vector2(size.x, size.z) * 0.5
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var ext := (basis * Vector3(half_ext.x, 0, half_ext.y)).abs()
	_occ_rect(center.x - ext.x, center.y - ext.z, center.x + ext.x, center.y + ext.z)
	# Benches, urns and a flower bed at every entrance.
	for e: Vector3 in info.entrances:
		var wp := o.to_global(e * VS)
		var side := basis * Vector3(1, 0, 0)
		var out := basis * Vector3(0, 0, -1)
		_place(DistrictProps.bench(rng.randi()), Vector3(wp.x, GY, wp.z) + side * 2.6 + out * 0.6, false, yaw + 180.0, "bench")
		_place(DistrictProps.urn(), Vector3(wp.x, GY, wp.z) + side * 4.2, false, 0.0, "urn")
		if rng.randf() < 0.7:
			_place(DistrictProps.flower_bed(rng.randi()), Vector3(wp.x, GY, wp.z) - side * 4.5 + out * 0.4, true, yaw, "flowers")
		if rng.randf() < 0.6:
			_place(DistrictProps.mailbox(), Vector3(wp.x, GY, wp.z) - side * 7.5 + out * 0.8, false, yaw, "mailbox")
	return o


func _buildings() -> void:
	_block("block1", 4, Vector2(-23, -58), 180.0, "brick", 1)
	_block("block2", 3, Vector2(-64, -22), -90.0, "brick_brown", 2)
	_block("block3", 3, Vector2(23, -20), 90.0, "brick_tan", 3)
	_block("block4", 4, Vector2(78, -16), 90.0, "brick", 4)
	_block("block5", 4, Vector2(-3, 21), 0.0, "brick_brown", 5)

	var p := DistrictBuildings.store(440, 190, 60, "foodmart", 11)
	var po := _place(p.volume, _w(46, -79), true, 0.0, "foodmart", Vector3i(64, 64, 64))
	po.add_occluder(p.interior)
	_lights(po, p.lamps, Color(0.92, 0.96, 1.0), 1.6, 9.0)
	buildings["foodmart"] = po
	_occ_rect(23, -89, 69, -68)

	var m := DistrictBuildings.store(280, 140, 55, "pharmacy", 12)
	var mo := _place(m.volume, _w(-68, 23), true, 0.0, "pharmacy", Vector3i(64, 64, 64))
	mo.add_occluder(m.interior)
	_lights(mo, m.lamps, Color(0.92, 0.96, 1.0), 1.6, 9.0)
	buildings["pharmacy"] = mo
	_occ_rect(-83, 15, -53, 31)

	var r := DistrictBuildings.auto_shop(13)
	var ro := _place(r.volume, _w(55.5, 31), true, 0.0, "autoshop", Vector3i(64, 64, 64))
	_lights(ro, r.lamps, Color(1.0, 0.8, 0.55), 1.4, 7.0)
	buildings["autoshop"] = ro
	_occ_rect(49.5, 25, 61.5, 37)
	for k in 5:
		var tp := Vector3(48.5 + k * 1.3, GY, 38.3 + (k % 2) * 0.9)
		var tv := Build.vol(Vector3i(10, 10, 10))
		DistrictBuildings._tire(tv, Vector3(5, 0, 5), 2 + k % 3)
		_place(tv, tp, false, 0.0, "tires")

	var g1 := DistrictBuildings.garage_row(13, 21)
	_place(g1.volume, _w(-17, -89.2), true, 0.0, "storage", Vector3i(64, 32, 64))
	var sign := Build.vol(Vector3i(80, 22, 2))
	sign.fill_box(Vector3i(0, 0, 1), Vector3i(2, 22, 2), VoxMat.id("metal_dark"))
	sign.fill_box(Vector3i(78, 0, 1), Vector3i(80, 22, 2), VoxMat.id("metal_dark"))
	sign.fill_box(Vector3i(1, 10, 0), Vector3i(79, 21, 1), VoxMat.id("pvc"))
	VoxelFont.draw(sign, "SELF STORAGE", Vector3i(75, 18, 0), Vector3i(-1, 0, 0), VoxMat.id("door_orange"))
	_place(sign, _w(-17, -92.5, GY + 2.9), true, 0.0, "sign")
	var g2 := DistrictBuildings.garage_row(12, 22)
	_place(g2.volume, _w(-14, -76.3), true, 180.0, "storage", Vector3i(64, 32, 64))
	_occ_rect(-38, -93, 4, -72)
	for sp in [Vector2(-50, -91), Vector2(-50, -76), Vector2(45, -11), Vector2(47, 4)]:
		_place(DistrictBuildings.shed(rng.randi()), _w(sp.x, sp.y), true, rng.randf_range(-5, 5) + (90.0 if sp.x > 0 else 0.0), "shed")
		_occ_rect(sp.x - 2, sp.y - 2, sp.x + 2, sp.y + 2)

	_place(DistrictBuildings.bus_stop(1), _w(12, 52.2), true, 0.0, "bus_stop")
	_place(DistrictBuildings.bus_stop(2), _w(72, 69.8), true, 180.0, "bus_stop")
	_place(DistrictProps.kiosk(3), _w(20, 52.5), true, 0.0, "kiosk")
	_place(DistrictProps.road_sign("bus"), _w(8.5, 53.4), true, 0.0, "sign")
	_place(DistrictProps.road_sign("bus"), _w(76, 68.6), true, 180.0, "sign")
	for st in [[Vector2(-53.2, 50.6), 0.0], [Vector2(53.2, 50.6), 0.0], [Vector2(88.3, -57.8), 90.0], [Vector2(88.3, 7.8), 90.0], [Vector2(11.8, -50.6), 0.0]]:
		_place(DistrictProps.road_sign("stop"), _w(st[0].x, st[0].y), true, st[1], "sign")
	for s in [Vector2(-17, 53.4), Vector2(-11, 68.6), Vector2(79, 53.4), Vector2(85, 68.6), Vector2(88.2, 43)]:
		_place(DistrictProps.road_sign("crossing"), _w(s.x, s.y), true, 0.0 if s.y < 60 else 180.0, "sign")


# ================================================================== courtyards

func _courtyards() -> void:
	# Playground.
	_place(DistrictProps.swing(1), _w(-25, -21), true, 0.0, "swing")
	_place(DistrictProps.swing(2), _w(-11, -23), true, 90.0, "swing")
	_place(DistrictProps.slide(0), _w(-13, -12), true, 30.0, "slide")
	_place(DistrictProps.carousel(0), _w(-20, -14), true, 0.0, "carousel")
	_place(DistrictProps.sandbox(1), _w(-26, -9), true, 0.0, "sandbox")
	_place(DistrictProps.climber(2), _w(-9, -6), true, 0.0, "climber")
	_place(DistrictProps.climber(0), _w(-35, -30), true, 90.0, "bars")
	for e in [Vector2(-25, -21), Vector2(-11, -23), Vector2(-13, -12), Vector2(-20, -14), Vector2(-26, -9), Vector2(-9, -6), Vector2(-35, -30)]:
		_occ_rect(e.x - 3, e.y - 3, e.x + 3, e.y + 3)
	for b in [Vector3(-31, 0, -14), Vector3(-31, 0, -18), Vector3(-4, 0, -15), Vector3(-17, 0, -3), Vector3(-21, 0, -28)]:
		_place(DistrictProps.bench(rng.randi()), _w(b.x, b.z), false, 90.0 if absf(b.x + 17) > 10 else 0.0, "bench")
	for k in 6:
		var a := k * TAU / 6.0 + 0.3
		_place(DistrictProps.picnic_table(k), _w(-17.5 + cos(a) * 17.0, -15.5 + sin(a) * 13.0), false, rad_to_deg(a), "picnic")
	# Low green fence around the playground lawn.
	for f in [[Vector2(-38, -36), 0.0, 180], [Vector2(-38, 6.5), 0.0, 180], [Vector2(-38.5, -35), -90.0, 200]]:
		var start: Vector2 = f[0]
		var len: int = f[2]
		var yaw: float = f[1]
		var d := Vector3(cos(deg_to_rad(yaw)), 0, -sin(deg_to_rad(yaw)))
		_place(DistrictProps.metal_fence(len, "metal_green"), _w(start.x, start.y) + d * len * VS * 0.5, true, yaw, "fence")
	# Basketball court by block 4.
	_place(DistrictProps.basketball_hoop(), _w(44, -40.3), true, 0.0, "hoop")
	_place(DistrictProps.basketball_hoop(), _w(44, -25.7), true, 180.0, "hoop")
	_place(DistrictProps.chain_link(160), _w(44, -41.6), true, 0.0, "fence")
	for b in [Vector2(40, -14), Vector2(48, -40), Vector2(36, -2)]:
		_place(DistrictProps.bench(rng.randi()), _w(b.x, b.y), false, rng.randf() * 360.0, "bench")
	# Trash enclosure: sheet fence on three sides and containers.
	_place(DistrictProps.sheet_fence(140, "metal_green"), _w(74.5, 31), true, 0.0, "fence")
	_place(DistrictProps.sheet_fence(120, "metal_green"), _w(67.6, 37.5), true, -90.0, "fence")
	_place(DistrictProps.sheet_fence(120, "metal_green"), _w(81.4, 37.5), true, -90.0, "fence")
	for k in 4:
		_place(DistrictProps.trash_container(k), _w(70 + k * 2.7, 33.5), false, rng.randf_range(-6, 6), "container")
	for k in 6:
		var bag := Build.vol(Vector3i(5, 4, 5))
		bag.fill_ellipsoid_noise(Vector3(2.5, 1.5, 2.5), Vector3(2.4, 2, 2.4), PackedByteArray([VoxMat.id("tank_black"), VoxMat.id("rubber")]), 0.95, 0.2, k)
		_place(bag, _w(69 + rng.randf() * 10, 38 + rng.randf() * 4), false, rng.randf() * 360.0, "trash")
	# Pallets and boxes behind the shops.
	for k in 6:
		_place(Build.pallet(k), _w(26 + k * 1.5, -91.5), false, 0.0, "pallet")
		_place(Build.crate(rng.randi_range(6, 9), k), _w(26 + k * 1.5, -91.5, GY + 0.25), false, rng.randf() * 30.0, "crate")
	for k in 4:
		_place(Build.crate(rng.randi_range(6, 8), k + 9), _w(-50.5 + k * 1.1, 33.5), false, rng.randf() * 40.0, "crate")
	# Benches and lamps along the paths.
	for p in [Vector2(-30, -44.5), Vector2(-12, -44.5), Vector2(-50, -30), Vector2(-50, -10), Vector2(15, -30), Vector2(15, -10), Vector2(70, -30), Vector2(70, 0), Vector2(-20, 14.3), Vector2(10, 14.3)]:
		_place(DistrictProps.bench(rng.randi()), _w(p.x, p.y), false, 0.0 if absf(p.y) > 40 or p.y > 10 else 90.0, "bench")
	for p in [Vector2(-40, -45), Vector2(-48, -6), Vector2(12, -25), Vector2(66, -20), Vector2(-40, 14), Vector2(30, 14), Vector2(52, -60), Vector2(-60, 32)]:
		var lp := _place(Build.lamp_post(), _w(p.x, p.y), true, rng.randf() * 360.0, "lamp_post")
		Build.lamp_light(lp, Vector3i(10, 55, 1), Color(1.0, 0.78, 0.5), 2.2, 11.0)


# ================================================================== street

func _street() -> void:
	for x in range(-96, 90, 18):
		var n := _place(DistrictProps.lamp_pole(), _w(x, 52.6), true, 90.0, "pole")
		Build.lamp_light(n, Vector3i(13, 84, 1), Color(1.0, 0.75, 0.45), 3.0, 14.0)
		_place(DistrictProps.lamp_pole(), _w(x + 9, 69.6), true, -90.0, "pole")
	for z in range(-96, 50, 18):
		var n := _place(DistrictProps.lamp_pole(), _w(87, z), true, 0.0, "pole")
		Build.lamp_light(n, Vector3i(13, 84, 1), Color(1.0, 0.75, 0.45), 3.0, 14.0)
	# Hedges and a low fence between block 5 and the main road.
	for x in range(-36, 30, 6):
		_place(DistrictProps.hedge(55, rng.randi()), _w(x + 3, 47.5), true, 0.0, "hedge")
	_place(DistrictProps.metal_fence(660, "metal_dark"), _w(-3, 48.9), true, 0.0, "fence")
	# Fence along the river bank path and around the garage yard.
	for i in RIVER.size() - 1:
		var a: Vector3 = RIVER[i]
		var b: Vector3 = RIVER[i + 1]
		var n := Vector2(b.y - a.y, -(b.x - a.x)).normalized()  # east bank
		var p0 := Vector2(a.x, a.y) + n * (a.z + 10.0)
		var p1 := Vector2(b.x, b.y) + n * (b.z + 10.0)
		if p0.y > 10.0:
			continue
		var d := p1 - p0
		var len := int(d.length() / VS)
		var c := (p0 + p1) * 0.5
		if absf(c.x) < HALF - 1 and absf(c.y) < HALF - 1:
			_place(Build.picket_fence(len, i), Vector3(c.x, GY, c.y), true, rad_to_deg(atan2(-d.y, d.x)), "fence")
	_place(DistrictProps.chain_link(560), _w(-17, -95.5), true, 0.0, "fence")
	_place(DistrictProps.chain_link(240), _w(-41.5, -84), true, 90.0, "fence")
	for z in range(-95, 100, 24):
		_place(DistrictProps.utility_pole(), _w(100.8, z), true, 90.0, "pole")
	for x in range(-90, 90, 34):
		_place(DistrictProps.fire_hydrant(x), _w(x + 7.0, 50.7), false, 0.0, "hydrant")
	for p in [Vector2(-50, -45), Vector2(16, -30), Vector2(70, -5), Vector2(-20, 14.5), Vector2(66, 36), Vector2(-48, 30)]:
		_place(DistrictProps.fire_hydrant(int(p.x)), _w(p.x, p.y), false, 0.0, "hydrant")
	_place(DistrictProps.mailbox(), _w(16.5, 51.5), false, 0.0, "mailbox")
	_place(DistrictProps.flag_pole(), _w(20, -67.5), true, 0.0, "flag")
	_place(DistrictProps.flag_pole(), _w(64, 36.5), true, 0.0, "flag")
	_place(DistrictProps.flag_pole(), _w(-50.5, 30.5), true, 0.0, "flag")


func _railway() -> void:
	for k in 5:
		var x := -HALF + 20.48 + k * 40.96
		_place(DistrictProps.railway(410, k), _w(x, 89.0), true, 0.0, "railway", Vector3i(64, 32, 72))
		_place(DistrictProps.chain_link(410), _w(x, 81.0), true, 0.0, "fence")
	_occ_rect(-HALF, 80, HALF, 96)
	var x0 := -60.0
	for k in 5:
		var tank := k != 2
		var w := _place(DistrictProps.wagon(tank, k), _w(x0 + k * 12.6, 90.4, GY + 0.72), false, 0.0, "wagon")
		if tank and k == 3:
			w.explosive_radius = 4.0
			w.explosive_power = 7.0


# ================================================================== vehicles

const CAR_COLORS := ["metal_white", "metal_white", "metal", "metal", "metal_dark", "tank_black", "metal_red", "metal_blue", "metal_green", "pvc", "metal_teal"]


func _car(pos: Vector3, yaw: float, label := "car") -> VoxelObject:
	var color: String = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	if label == "car" and rng.randf() < 0.3:
		# Pickups are as common as sedans in an American lot.
		var pk := DistrictProps.pickup(color, rng.randi())
		var po := _place(pk.volume, pos, false, yaw, "pickup")
		vehicles.append(VoxelVehicle.attach(po, pk.hubs, Vector3(-1, 0, 0), 0.38))
		return po
	var c := _place(Build.car(color, rng.randi()), pos, false, yaw, label)
	vehicles.append(VoxelVehicle.attach(c, Build.car_hubs(), Vector3(-1, 0, 0)))
	return c


func _parked_cars() -> void:
	var road_y := GY - 0.1
	var parking_step := 6 if _web else 3
	for x in range(23, 77, parking_step):
		if rng.randf() < 0.68:
			_car(Vector3(x + 1.5, road_y, -64.0), -90.0)
		if rng.randf() < 0.55:
			_car(Vector3(x + 1.5, road_y, -58.0), 90.0)
	for x in range(-85, -52, parking_step):
		if rng.randf() < 0.7:
			_car(Vector3(x + 1.5, road_y, 33.2), -90.0)
		if rng.randf() < 0.4:
			_car(Vector3(x + 1.5, road_y, 45.0), 90.0)
	for z in range(-44, 6, parking_step):
		if rng.randf() < 0.7:
			_car(Vector3(62.5, road_y, z + 1.5), 0.0)
	for z in range(-32, 10, 6):
		if rng.randf() < 0.65:
			_car(Vector3(-42.2, road_y, z), 90.0)
	for x in range(-40, 6, 6):
		if rng.randf() < 0.55:
			_car(Vector3(x, road_y, -41.0), 0.0)
	for x in [-30.0, -5.0, 20.0]:
		_car(Vector3(x, road_y, 10.2), 180.0)
	_car(Vector3(-30, road_y, -82.0), 5.0)
	_car(Vector3(47, road_y, 41), 90.0)
	var t := DistrictProps.box_truck(1)
	var to := _place(t.volume, Vector3(73.0, road_y, -80.0), false, -90.0, "truck")
	vehicles.append(VoxelVehicle.attach(to, t.hubs, Vector3(-1, 0, 0), 0.45))
	var gz := DistrictProps.gazelle(false, 2)
	var go := _place(gz.volume, Vector3(-36.0, road_y, -83.0), false, 0.0, "van")
	vehicles.append(VoxelVehicle.attach(go, gz.hubs, Vector3(-1, 0, 0)))


func _traffic() -> void:
	var road_y := GY - 0.08
	var bus := DistrictProps.school_bus(1)
	var bo := _place(bus.volume, Vector3(-80, road_y, 64.6), false, 180.0, "bus")
	var bv := VoxelVehicle.attach(bo, bus.hubs, Vector3(-1, 0, 0), 0.45)
	TrafficDriver.attach(bv, [Vector3(-80, 0, 64.6), Vector3(100, 0, 64.6)], 8.0)
	var mo := _place(DistrictProps.taxi(3), Vector3(70, road_y, 57.4), false, 0.0, "taxi")
	var mv := VoxelVehicle.attach(mo, Build.car_hubs(), Vector3(-1, 0, 0))
	TrafficDriver.attach(mv, [Vector3(70, 0, 57.4), Vector3(-100, 0, 57.4)], 10.0)
	var co := _car(Vector3(96.5, road_y, 90.0), -90.0, "traffic")
	TrafficDriver.attach(co.get_node("Vehicle"), [Vector3(96.5, 0, 90), Vector3(96.5, 0, -100)], 11.0)
	var co2 := _car(Vector3(91.5, road_y, -95.0), 90.0, "traffic")
	TrafficDriver.attach(co2.get_node("Vehicle"), [Vector3(91.5, 0, -95), Vector3(91.5, 0, 100)], 10.0)
	var co3 := _car(Vector3(-40, road_y, 57.4), 0.0, "traffic")
	TrafficDriver.attach(co3.get_node("Vehicle"), [Vector3(-40, 0, 57.4), Vector3(-100, 0, 57.4)], 12.0)


# ================================================================== vegetation

func _tree(x: float, z: float, kind: String) -> void:
	var v: VoxelVolume
	match kind:
		"maple": v = DistrictProps.maple(rng.randi())
		"linden": v = DistrictProps.linden(rng.randi())
		"pine": v = Build.pine_tree(rng.randi(), rng.randi_range(75, 100))
		"bush": v = Build.bush(rng.randi())
	var sz := v.get_size()
	var cs := Vector3i(maxi(sz.x, 32), maxi(sz.y, 32), maxi(sz.z, 32))
	var o := _place(v, Vector3(x, ground_height(x, z) - 0.1, z), true, rng.randf() * 360.0, "tree", cs)
	for c in o.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.visibility_range_end = 90.0 if kind == "bush" else 175.0
			if kind == "bush":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Scatters trees inside a zone wherever the occupancy grid is free.
func _scatter(x0: float, z0: float, x1: float, z1: float, count: int, spacing: float, kinds: Array) -> void:
	if _web:
		count = maxi(2, roundi(count * 0.22))
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 25:
		tries += 1
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		if not _occ_free(x, z, spacing * 0.5):
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		_tree(x, z, kind)
		_occ_rect(x - spacing * 0.4, z - spacing * 0.4, x + spacing * 0.4, z + spacing * 0.4)
		placed += 1


func _vegetation() -> void:
	var leafy := ["maple", "maple", "linden", "linden", "pine"]
	var forest := ["pine", "pine", "maple", "linden"]
	_scatter(-HALF + 1, -HALF + 1, HALF - 1, -94, 60, 4.0, forest)       # north edge
	_scatter(-HALF + 1, -HALF + 1, -58, 50, 110, 3.6, forest)             # west of and along the river
	_scatter(-HALF + 1, 71.5, HALF - 1, 80, 80, 3.6, leafy)              # between main road and fence
	_scatter(-HALF + 1, 96, HALF - 1, HALF - 1, 30, 4.0, forest)         # behind the railway
	_scatter(-52, -50, 12, -44, 16, 4.5, leafy)                          # in front of block 1
	_scatter(-56, -36, -47, 8, 16, 4.0, leafy)                           # by block 2
	_scatter(-39, -35, 4, 7, 24, 4.5, leafy)                             # playground lawn
	_scatter(28, -48, 56, 8, 40, 4.0, leafy)                             # east courtyard
	_scatter(-50, 28, 45, 49, 40, 4.0, leafy)                            # south lawn
	_scatter(13, -66, 22, 8, 16, 4.0, leafy)                             # between roads
	_scatter(70, -68, 88, -47, 14, 4.0, leafy)                            # by Pyaterochka
	_scatter(-HALF + 1, 13, -84, 54, 18, 4.0, leafy)
	_scatter(-HALF + 1, -94, -46, -60, 20, 4.0, forest)                 # NW corner by the garages
	_scatter(4, -100, 89, -89, 20, 4.0, leafy)                           # behind Pyaterochka
	_scatter(60, 14, 88, 50, 14, 4.0, leafy)                             # around the auto repair
	_scatter(84, -HALF + 1, 89, 50, 14, 3.5, leafy)                       # along the side road
	_scatter(-60, -70, 20, -64, 16, 3.5, leafy)                          # behind block 1
	_scatter(-HALF + 1, -HALF + 1, HALF - 1, HALF - 1, 190, 2.2, ["bush"])
