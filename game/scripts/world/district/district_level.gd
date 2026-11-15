class_name DistrictLevel
## Дворы Заречья: five-storey panel blocks around the existing street plan.

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
var spawn := Vector3(12, GY + 0.05, 48.0)
var spawn_yaw := 0.0
var rng := RandomNumberGenerator.new()
var tiles := {}               # Vector2i -> VoxelVolume
var _occ := PackedByteArray()
var _heights := PackedFloat32Array()
var _map_surface: Texture2D
var buildings := {}           # name -> VoxelObject (used by cinematics)
var vehicles: Array[VoxelVehicle] = []
var hide_spots: Array[Dictionary] = []
var portal_sites: Array[Dictionary] = []
var secret_rooms: Array[Dictionary] = []
var pharmacy_cross := Vector3.ZERO
var roof_route := PackedVector3Array()
var lilacs: Array[Vector3] = []
var _fence_obstacles: Array[VoxelObject] = []


func _init(w: VoxelWorld) -> void:
	world = w
	rng.seed = 1964
	_occ.resize(OCC_N * OCC_N)


func build() -> void:
	var t0 := Time.get_ticks_msec()
	await _stage("Рельеф и улицы", 16)
	_terrain()
	_ground_layout()
	DistrictSecretMap.dig(self)
	await _spawn_tiles()
	print("[district] terrain %d ms" % (Time.get_ticks_msec() - t0))
	await _stage("Пятиэтажки и квартиры", 52)
	_water()
	await _buildings()
	print("[district] buildings %d ms" % (Time.get_ticks_msec() - t0))
	await _stage("Дворы и транспорт", 79)
	_courtyards()
	_street()
	_railway()
	_parked_cars()
	_traffic()
	await _stage("Озеленение и окружение", 90)
	_vegetation()
	Backdrop.build(world, GY, HALF, HALF + 4.0, 77)
	print("[district] total %d ms, %d objects" % [Time.get_ticks_msec() - t0, world.objects.size()])


func _stage(title: String, percent: float) -> void:
	GameState.loading_status(title, percent)
	await world.get_tree().process_frame


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
			# Keep flat terrain mergeable. The shader supplies variation on each voxel.
			v.fill_columns(Vector3i.ZERO, Vector3i(TILE, 0, TILE), region.get_data().to_float32_array(), 0.0, 1.0, layers, 0)
			# Wet banks and the riverbed.
			v.replace(Vector3i(0, 16, 0), Vector3i(TILE, GROUND - 1, TILE), grass, VoxMat.id("sand"))
			v.replace(Vector3i(0, 0, 0), Vector3i(TILE, 16, TILE), grass, VoxMat.id("mud"))
			v.fill_box(Vector3i(0, 0, 0), Vector3i(TILE, 4, TILE), VoxMat.id("bedrock"))
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


func map_surface() -> Texture2D:
	if is_instance_valid(_map_surface):
		return _map_surface
	const PIXELS := 256
	var terrain := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	var tints := {}
	var layers := {
		"grass": Color("#3f5140"), "dirt": Color("#545442"), "sand": Color("#7e7355"),
		"asphalt": Color("#514f4b"), "asphalt_patch": Color("#494b47"), "sidewalk": Color("#78766b"),
		"curb": Color("#929087"), "road_line": Color("#a6a69b"), "road_yellow": Color("#bd9d62"),
		"concrete": Color("#686c62"), "gravel": Color("#6e6e60"), "mud": Color("#524e40"),
	}
	for name: String in layers:
		for swatch in VoxMat.ids(name):
			tints[swatch] = layers[name]
	for py in PIXELS:
		var z := py * SIZE / PIXELS + SIZE / PIXELS / 2
		for px in PIXELS:
			var x := px * SIZE / PIXELS + SIZE / PIXELS / 2
			var tile: VoxelVolume = tiles[Vector2i(x / TILE, z / TILE)]
			var cell := Vector3i(x % TILE, GROUND + 3, z % TILE)
			var swatch := tile.get_voxel(cell)
			while swatch == 0 and cell.y > 0:
				cell.y -= 1
				swatch = tile.get_voxel(cell)
			var tint: Color = tints.get(swatch, Color("#454d3e"))
			var wx := float(x) * VS - HALF
			var wz := float(z) * VS - HALF
			if wx > -125.0 and wx < -35.0 and wz > -110.0 and wz < 30.0 and float(cell.y + 1) * VS <= WATER_Y:
				tint = Color("#3d666a") if cell.y >= 13 else Color("#32565e")
			terrain.set_pixel(px, py, tint)
	var image_area := Rect2i(0, 0, PIXELS, PIXELS)
	for object in world.objects:
		if not is_instance_valid(object) or not object.is_tree:
			continue
		var center := object.world_center()
		var pixel := Vector2i((Vector2(center.x, center.z) + Vector2.ONE * HALF) * (PIXELS / (HALF * 2.0)))
		terrain.fill_rect(Rect2i(pixel - Vector2i.ONE, Vector2i(3, 3)).intersection(image_area), Color("#354733"))
		terrain.fill_rect(Rect2i(pixel - Vector2i.ONE, Vector2i(2, 2)).intersection(image_area), Color("#6f8861"))
	_map_surface = ImageTexture.create_from_image(terrain)
	return _map_surface


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
	for booth: Vector3 in DistrictSecretProps.BOOTHS:
		_sidewalk(booth.x - 1.3, booth.z - 1.3, booth.x + 1.3, booth.z + 1.3)
	var cellar := DistrictSecretMap.DOGHOUSE
	_sidewalk(cellar.x - 1.5, cellar.y - 1.5, cellar.x + 1.5, cellar.y + 2.1)
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
	var done := 0
	for tk: Vector2i in tiles:
		var o := VoxelObject.new()
		o.setup(tiles[tk], true, Vector3i(128, 32, 128))
		o.label = "ground"
		o.position = Vector3(tk.x * TILE * VS - HALF, 0, tk.y * TILE * VS - HALF)
		world.add_child(o)
		done += 1
		if done % 8 == 0:
			await _stage("Воксельные участки", 20.0 + 28.0 * done / tiles.size())


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
	for spot: Dictionary in info.hides:
		spot["building"] = o
		hide_spots.append(spot)
	_add_portal_sites(o, info.portals)
	_add_doors(o, info.doors)
	for secret: Dictionary in info.secrets:
		secret["building"] = o
		secret_rooms.append(secret)
	if name == "block1":
		var x := float(info.x1) - 16.0
		var z := float(info.back_z)
		var top := float(info.top)
		roof_route = PackedVector3Array([
			o.to_global(Vector3(x, 0.2, z + 10) * VS),
			o.to_global(Vector3(x, top + 11, z + 10) * VS),
			o.to_global(Vector3(x, top + 11, z - 8) * VS),
			o.to_global(Vector3(x, top + 3.1, z - 8) * VS)])
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
		lilacs.append(Vector3(wp.x, GY, wp.z) + side * 5.5 + out * 0.1)
		_place(DistrictProps.bench(rng.randi()), Vector3(wp.x, GY, wp.z) + side * 2.6 + out * 0.6, false, yaw + 180.0, "bench")
		_place(DistrictProps.urn(), Vector3(wp.x, GY, wp.z) + side * 4.2, false, 0.0, "urn")
		if rng.randf() < 0.7:
			_place(DistrictProps.flower_bed(rng.randi()), Vector3(wp.x, GY, wp.z) - side * 4.5 + out * 0.4, true, yaw, "flowers")
		if rng.randf() < 0.6:
			_place(DistrictProps.mailbox(), Vector3(wp.x, GY, wp.z) - side * 7.5 + out * 0.8, false, yaw, "mailbox")
	return o


func _add_portal_sites(building: VoxelObject, sites: Array) -> void:
	for point: Vector3 in sites:
		portal_sites.append({"at": building.to_global(point * VS), "inside": true, "yaw": building.rotation.y})


func _add_doors(building: VoxelObject, doors: Array) -> void:
	for door: Dictionary in doors:
		DistrictDoor.install(world, building.to_global(Vector3(door.hinge) * VS), building.rotation.y + float(door.yaw), str(door.finish))


func _buildings() -> void:
	var blocks := [
		["block1", 4, Vector2(-23, -58), 180.0, "panel_grey"],
		["block2", 3, Vector2(-64, -22), -90.0, "panel_beige"],
		["block3", 3, Vector2(23, -20), 90.0, "panel_cream"],
		["block4", 4, Vector2(78, -16), 90.0, "panel_grey"],
		["block5", 4, Vector2(-3, 21), 0.0, "panel_beige"],
	]
	for i in blocks.size():
		var b: Array = blocks[i]
		_block(b[0], b[1], b[2], b[3], b[4], i + 1)
		await _stage("Пятиэтажка %d / %d" % [i + 1, blocks.size()], 53 + 4 * i)

	var p := DistrictBuildings.store(440, 190, 60, "foodmart", 11)
	var po := _place(p.volume, _w(46, -79), true, 0.0, "foodmart", Vector3i(64, 64, 64))
	po.add_occluder(p.interior)
	_lights(po, p.lamps, Color(0.92, 0.96, 1.0), 1.6, 9.0)
	buildings["foodmart"] = po
	_add_portal_sites(po, p.portals)
	_add_doors(po, p.doors)
	_occ_rect(23, -89, 69, -68)

	var m := DistrictBuildings.store(280, 140, 55, "pharmacy", 12)
	DistrictSecretMap.cut_floor(m.volume, Vector2(-68, 23), DistrictSecretMap.PHARMACY)
	var mo := _place(m.volume, _w(-68, 23), true, 0.0, "pharmacy", Vector3i(64, 64, 64))
	pharmacy_cross = mo.to_global(Vector3(m.cross) * VS)
	mo.add_occluder(m.interior)
	_lights(mo, m.lamps, Color(0.92, 0.96, 1.0), 1.6, 9.0)
	buildings["pharmacy"] = mo
	_add_portal_sites(mo, m.portals)
	_add_doors(mo, m.doors)
	_occ_rect(-83, 15, -53, 31)

	var r := DistrictBuildings.auto_shop(13)
	DistrictSecretMap.cut_floor(r.volume, Vector2(55.5, 31), DistrictSecretMap.SHOP)
	var ro := _place(r.volume, _w(55.5, 31), true, 0.0, "autoshop", Vector3i(64, 64, 64))
	_lights(ro, r.lamps, Color(1.0, 0.8, 0.55), 1.4, 7.0)
	buildings["autoshop"] = ro
	_add_portal_sites(ro, r.portals)
	_occ_rect(49.5, 25, 61.5, 37)
	for k in 5:
		var tp := Vector3(48.5 + k * 1.3, GY, 38.3 + (k % 2) * 0.9)
		var tv := Build.vol(Vector3i(10, 10, 10))
		DistrictBuildings._tire(tv, Vector3(5, 0, 5), 2 + k % 3)
		_place(tv, tp, false, 0.0, "tires")

	var g1 := DistrictBuildings.garage_row(13, 21)
	_fence_obstacles.append(_place(g1.volume, _w(-17, -89.2), true, 0.0, "storage", Vector3i(64, 32, 64)))
	var sign := Build.vol(Vector3i(80, 22, 2))
	sign.fill_box(Vector3i(0, 0, 1), Vector3i(2, 22, 2), VoxMat.id("metal_dark"))
	sign.fill_box(Vector3i(78, 0, 1), Vector3i(80, 22, 2), VoxMat.id("metal_dark"))
	sign.fill_box(Vector3i(1, 10, 0), Vector3i(79, 21, 1), VoxMat.id("pvc"))
	VoxelFont.draw(sign, "ГАРАЖИ", Vector3i(57, 18, 0), Vector3i(-1, 0, 0), VoxMat.id("door_orange"))
	_place(sign, _w(-17, -92.5, GY + 2.9), true, 0.0, "sign")
	var g2 := DistrictBuildings.garage_row(12, 22)
	_fence_obstacles.append(_place(g2.volume, _w(-14, -76.3), true, 180.0, "storage", Vector3i(64, 32, 64)))
	_occ_rect(-38, -93, 4, -72)
	_occ_rect(8, -88, 22, -78)
	for sp in [Vector2(-43.8, -88.9), Vector2(-50, -76), Vector2(45, -11), Vector2(47, 4)]:
		_fence_obstacles.append(_place(DistrictBuildings.shed(rng.randi()), _w(sp.x, sp.y), true,
			rng.randf_range(-5, 5) + (90.0 if sp.x > 0 else 0.0), "shed"))
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
	for b in [Vector3(-31, 0, -14), Vector3(-31, 0, -18), Vector3(-4, 0, -15), Vector3(-17, 0, -3), Vector3(-23.8, 0, -27.6)]:
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
	for p in [Vector2(-30, -44.5), Vector2(-12, -44.5), Vector2(-50, -30), Vector2(-50, -10), Vector2(15, -30), Vector2(16.4, -11.9), Vector2(70, -30), Vector2(71.4, 2.1), Vector2(-20, 14.3), Vector2(10, 14.3)]:
		_place(DistrictProps.bench(rng.randi()), _w(p.x, p.y), false, 0.0 if absf(p.y) > 40 or p.y > 10 else 90.0, "bench")
	for p in [Vector2(-40, -45), Vector2(-48, -6), Vector2(12, -25), Vector2(66, -20), Vector2(-40, 14), Vector2(30, 14), Vector2(52, -60), Vector2(-60, 32)]:
		var lp := _place(Build.lamp_post(), _w(p.x, p.y), true, rng.randf() * 360.0, "lamp_post")
		Build.lamp_light(lp, Vector3i(10, 55, 1), Color(1.0, 0.78, 0.5), 2.2, 11.0)


# ================================================================== street

func _street() -> void:
	for x in range(-96, 90, 18):
		var lamp_x := 16.1 if x == 12 else float(x)
		var n := _place(DistrictProps.lamp_pole(), _w(lamp_x, 52.6), true, 90.0, "pole")
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
		var c := (p0 + p1) * 0.5
		if absf(c.x) < HALF - 1 and absf(c.y) < HALF - 1:
			_river_fence(p0, p1, i)
	_place(DistrictProps.chain_link(524), _w(-15.2, -95.5), true, 0.0, "fence")
	_place(DistrictProps.chain_link(227), _w(-41.5, -84.05), true, 90.0, "fence")
	for z in range(-95, 100, 24):
		_place(DistrictProps.utility_pole(), _w(100.8, z), true, 90.0, "pole")
	for x in range(-90, 90, 34):
		_place(DistrictProps.fire_hydrant(x), _w(x + 7.0, 50.7), false, 0.0, "hydrant")
	for p in [Vector2(-50, -45), Vector2(16, -30), Vector2(70, -5), Vector2(-18.6, 14.5), Vector2(66, 36), Vector2(-48, 30)]:
		_place(DistrictProps.fire_hydrant(int(p.x)), _w(p.x, p.y), false, 0.0, "hydrant")
	_place(DistrictProps.mailbox(), _w(16.5, 51.5), false, 0.0, "mailbox")
	_place(DistrictProps.flag_pole(), _w(20, -67.5), true, 0.0, "flag")
	_place(DistrictProps.flag_pole(), _w(64, 36.5), true, 0.0, "flag")
	_place(DistrictProps.flag_pole(), _w(-50.5, 30.5), true, 0.0, "flag")


func _river_fence(from: Vector2, to: Vector2, seed: int) -> void:
	var spans: Array[Vector2] = [Vector2(0.0, 1.0)]
	var obstacles := buildings.values()
	obstacles.append_array(_fence_obstacles)
	for building: VoxelObject in obstacles:
		var blocked := _building_interval(from, to, building)
		if not blocked.is_finite():
			continue
		var remaining: Array[Vector2] = []
		for span in spans:
			if span.y <= blocked.x or span.x >= blocked.y:
				remaining.append(span)
				continue
			if span.x < blocked.x:
				remaining.append(Vector2(span.x, blocked.x))
			if span.y > blocked.y:
				remaining.append(Vector2(blocked.y, span.y))
		spans = remaining
	var direction := to - from
	var yaw := rad_to_deg(atan2(-direction.y, direction.x))
	for span in spans:
		var len := floori(direction.length() * (span.y - span.x) / VS)
		if len < 8:
			continue
		var center := from.lerp(to, (span.x + span.y) * 0.5)
		_place(Build.picket_fence(len, seed), _w(center.x, center.y), true, yaw, "fence")


func _building_interval(from: Vector2, to: Vector2, building: VoxelObject) -> Vector2:
	const FENCE_CLEARANCE := 0.8
	var a := building.to_local(_w(from.x, from.y))
	var delta := building.to_local(_w(to.x, to.y)) - a
	var size := Vector3(building.volume.get_size()) * VS
	var first := 0.0
	var last := 1.0
	for axis: int in [0, 2]:
		var edge := size[axis] + FENCE_CLEARANCE
		if absf(delta[axis]) < 0.001:
			if a[axis] < -FENCE_CLEARANCE or a[axis] > edge:
				return Vector2.INF
			continue
		var near_t := (-FENCE_CLEARANCE - a[axis]) / delta[axis]
		var far_t := (edge - a[axis]) / delta[axis]
		first = maxf(first, minf(near_t, far_t))
		last = minf(last, maxf(near_t, far_t))
		if first >= last:
			return Vector2.INF
	return Vector2(first, last)


func _railway() -> void:
	var start := 0
	for k in 5:
		var length := 410 - k % 2
		var x := -HALF + (start + length * 0.5) * VS
		_place(DistrictProps.railway(length, k), _w(x, 89.0), true, 0.0, "railway", Vector3i(64, 32, 72))
		_place(DistrictProps.chain_link(length), _w(x, 81.0), true, 0.0, "fence")
		start += length
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
	var c := _place(Build.car(color, rng.randi()), pos, false, yaw, label)
	vehicles.append(VoxelVehicle.attach(c, Build.car_hubs(), Vector3(-1, 0, 0)))
	return c


func _parked_cars() -> void:
	var slots: Array[Vector3] = [
		Vector3(26.5, -63.7, -90), Vector3(38.5, -63.7, -90),
		Vector3(62.5, -63.7, -90), Vector3(74.5, -58.3, 90),
		Vector3(-80.5, 33.2, -90), Vector3(-68.5, 33.2, -90),
		Vector3(-77.5, 44.5, 90), Vector3(-65.5, 44.5, 90),
		Vector3(61.6, -36.5, 0), Vector3(61.6, -18.5, 0), Vector3(61.6, -0.5, 0),
		Vector3(63.0, 43.0, 90),
	]
	for slot in slots:
		_car(Vector3(slot.x, GY - 0.08, slot.y), slot.z)


func _traffic() -> void:
	var road_y := GY - 0.08
	var bus := DistrictProps.school_bus(1)
	var bo := _place(bus.volume, Vector3(-80, road_y, 64.6), false, 180.0, "bus")
	var bv := VoxelVehicle.attach(bo, bus.hubs, Vector3(-1, 0, 0), 0.45)
	TrafficDriver.attach(bv, [Vector3(-80, 0, 64.6), Vector3(100, 0, 64.6)], 8.0)
	var mo := _place(DistrictProps.taxi(3), Vector3(70, road_y, 57.4), false, 0.0, "taxi")
	var mv := VoxelVehicle.attach(mo, Build.car_hubs(), Vector3(-1, 0, 0))
	TrafficDriver.attach(mv, [Vector3(70, 0, 57.4), Vector3(-100, 0, 57.4)], 10.0)
	var co := _car(Vector3(96.5, road_y, 76.5), -90.0, "traffic")
	TrafficDriver.attach(co.get_node("Vehicle"), [Vector3(96.5, 0, 76.5), Vector3(96.5, 0, -100)], 11.0)


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
	o.is_tree = kind != "bush"
	for c in o.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.visibility_range_end = 90.0 if kind == "bush" else 175.0
			if kind == "bush":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Scatters trees inside a zone wherever the occupancy grid is free.
func _scatter(x0: float, z0: float, x1: float, z1: float, count: int, spacing: float, kinds: Array) -> void:
	if WebSession.connected:
		count = maxi(2, roundi(count * 0.44))
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
