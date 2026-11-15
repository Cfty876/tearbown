class_name SchoolLevel
extends RefCounted

const HALF := 80.0
const GROUND := 2.0
const LEVEL_HEIGHT := 3.8
const BASEMENT := -3.9
const WING_X := [-29, 10]
const ROWS := [0, 140, 230, 350, 480, 600]
const LIFT := Vector2(55.5, -11.8)
const ACID := Vector3(-12.4, 6.0, -22.5)
const HOOP := Vector3(50.0, 11.95, -8.0)
const FILM := Vector3(46.3, 9.8, 15.5)
const ATTIC := Vector3(-24.7, 13.6, 23.7)
const DUCT := Vector3(-13.2, 6.0, -10.5)
const MONITOR := Vector3(-6.3, 3.6, 2.2)
const RADIO := Vector3(-26.2, 10.9, 12.8)
const LOBBY_HATCH := Vector2(-3, 2)
const BOILER_HATCH := Vector2(50, -52)
const WARDROBE := Vector3(-20.0, -3.7, 4.5)
const CAMERA_NAMES := ["Коридор А", "Коридор Б", "Главный вход", "Школьный двор"]
const NPC_CLASS_SLOTS := [Vector4i(0, 0, 1, 0), Vector4i(1, 0, 0, 0), Vector4i(1, 1, 0, 0),
	Vector4i(1, 2, 0, 0), Vector4i(1, 3, 1, 0)]

const WEST_ROOMS := [
	[["stairs", "commons", "open", "music", "office"], ["class", "wood", "open", "class", "office"]],
	[["stairs", "physics", "open", "teachers", "director"], ["chem", "prep", "open", "it", "server"]],
	[["stairs", "bio", "open", "radio", "archive"], ["music", "class", "open", "reading", "library"]],
	[["stairs", "weather", "open", "archive", "dovecote"], ["chess", "photo", "open", "archive", "art"]],
]
const EAST_ROOMS := [
	[["class", "office", "open", "commons", "medical"], ["metal", "class", "open", "class", "stairs"]],
	[["class", "class", "open", "class", "teachers"], ["class", "it", "open", "class", "stairs"]],
	[["bio", "art", "open", "reading", "class"], ["music", "class", "open", "art", "stairs"]],
	[["weather", "class", "open", "photo", "archive"], ["art", "class", "open", "chess", "stairs"]],
]

var world: VoxelWorld
var spawn := Vector3(0.0, 2.08, 34.5)
var second_spawn := Vector3(-30.0, 2.08, -44.0)
var wings := {}
var annex := {}
var yard_lights: Array[OmniLight3D] = []
var warning_points: Array[Vector3] = []
var rooms: Array[Dictionary] = []
var _fixtures := {}
var hide_spots: Array[Dictionary] = []
var interior_lights: Array[OmniLight3D] = []
var basements := {}
var greenhouse_cover: Array[Vector3] = []
var campus: SchoolCampus
var entry_doors: Array[DistrictDoor] = []
var restroom_doors: Array[DistrictDoor] = []
var restroom_links := {}
var npc_classes: Array[Dictionary] = []
var npc_jobs := {}


func _init(voxel_world: VoxelWorld) -> void:
	world = voxel_world


func build() -> void:
	var conflicts := SchoolGrid.validate()
	assert(conflicts.is_empty(), "Intersecting school buildings: %s" % [conflicts])
	await _stage("Школьный квартал и стадион", 19)
	campus = SchoolCampus.new()
	SchoolYard.ground(self)
	for f in 4:
		await _stage("Учебные корпуса · этаж %d" % (f + 1), 32 + f * 9)
		_wing(0, f)
		_wing(1, f)
		_bridge(f)
		_annex(f)
	_roofs()
	_entry()
	await _stage("Котельная, мастерские и теплица", 72)
	SchoolYard.build(self)
	Backdrop.build(world, GROUND, HALF, HALF + 4.0, 120)
	await _stage("Убежище, тир и теплотрасса", 85)
	SchoolBasement.build(self)
	await _stage("Проверка маршрутов", 94)


func _stage(title: String, progress: int) -> void:
	GameState.loading_status(title, progress)
	await world.get_tree().process_frame


func place(v: VoxelVolume, at: Vector3, label: String, chunk := Vector3i(64, 38, 64), yaw := 0.0) -> VoxelObject:
	var result := VoxelObject.new().setup(v, true, chunk)
	result.position = at
	result.rotation.y = yaw
	result.label = label
	world.add_child(result)
	for fixture_data: Dictionary in _fixtures.get(v, []):
		_bind_light(fixture_data, result)
	_fixtures.erase(v)
	return result


static func box(v: VoxelVolume, p: Vector3i, size: Vector3i, material: String) -> void:
	v.fill_box(p, p + size, 0 if material.is_empty() else VoxMat.id(material))


func fixture(v: VoxelVolume, cell: Vector3i, at: Vector3, tint: Color, energy: float, radius: float) -> LampLight:
	if VoxMat.material_of(v.get_voxel(cell)) != VoxMat.EMISSIVE:
		box(v, cell - Vector3i(2, 0, 1), Vector3i(5, 1, 3), "lamp")
	var lamp := _new_light(at, tint, energy, radius)
	if not _fixtures.has(v):
		_fixtures[v] = []
	_fixtures[v].append({"lamp": lamp, "voxel": cell})
	return lamp


func mount_light(obj: VoxelObject, cell: Vector3i, tint: Color, energy: float, radius: float) -> LampLight:
	var at := obj.to_global((Vector3(cell) + Vector3(0.5, -0.6, 0.5)) * VoxelObject.VS)
	var lamp := _new_light(at, tint, energy, radius)
	_bind_light({"lamp": lamp, "voxel": cell}, obj)
	return lamp


func _new_light(at: Vector3, tint: Color, energy: float, radius: float) -> LampLight:
	var lamp := LampLight.new()
	lamp.position = at
	lamp.light_color = tint
	lamp.light_energy = energy
	lamp.omni_range = radius
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 25.0
	lamp.distance_fade_length = 22.0
	return lamp


func _bind_light(data: Dictionary, obj: VoxelObject) -> void:
	var lamp: LampLight = data.lamp
	lamp.obj = obj
	lamp.voxel = data.voxel
	# Keep the power-control reference alive even when the fixture is removed.
	world.add_child(lamp)
	var local := obj.to_local(lamp.global_position)
	lamp.follow_offset = local


func _wing(side: int, f: int) -> void:
	var origin := SchoolGrid.origin("west" if side == 0 else "east", GROUND + LEVEL_HEIGHT * f)
	var v := Build.vol(Vector3i(190, 38, 600))
	box(v, Vector3i.ZERO, Vector3i(190, 2, 600), "concrete_dark")
	box(v, Vector3i(3, 1, 3), Vector3i(184, 1, 594), "wood_light")
	box(v, Vector3i(67, 1, 3), Vector3i(56, 1, 594), "stone")
	Build.walls(v, 0, 0, 190, 600, 2, 38, 3, "brick_tan", f + side * 9)
	for wall_x in [0, 187]:
		for z in range(20, 576, 34):
			Build.window(v, 0, wall_x, 3, z, 10, 23, 17, "metal_teal", -1 if wall_x == 0 else 1)
		for z in range(0, 600, 30):
			box(v, Vector3i(wall_x, 35, z), Vector3i(3, 3, mini(30, 600 - z)), "panel_grey")
		for z in range(7, 590, 34):
			box(v, Vector3i(0 if wall_x == 0 else 189, 2, z), Vector3i(1, 35, 3), "brick")
	for z in [0, 597]:
		if f == 0:
			Build.door(v, 2, z, 3, 83, 2, 24, 24, "metal_teal")
		else:
			Build.window(v, 2, z, 3, 74, 9, 42, 19, "metal_teal", 1 if z else -1)
	# End elevations have masonry piers and recessed panels around the entrance axis.
	for end_z in [0, 599]:
		for x in [6, 43, 140, 179]:
			box(v, Vector3i(x, 2, end_z), Vector3i(3, 33, 1), "panel_grey")
		for x in [12, 148]:
			box(v, Vector3i(x, 7, end_z), Vector3i(27, 20, 1), "brick")
			for y in range(9, 27, 4):
				box(v, Vector3i(x + 2, y, end_z), Vector3i(23, 1, 1), "brick_tan")
		box(v, Vector3i(0, 34, end_z), Vector3i(190, 2, 1), "metal_teal")
		if f == 0:
			var direction := Vector3i(1, 0, 0) if end_z > 0 else Vector3i(-1, 0, 0)
			VoxelFont.draw(v, "КОРПУС А" if side == 0 else "КОРПУС Б",
				Vector3i(66 if end_z > 0 else 122, 33, end_z), direction, VoxMat.id("metal_white"))
	var booths: Array[Dictionary] = []
	var homeroom := {}
	for col in 2:
		var partition := 67 if col == 0 else 120
		box(v, Vector3i(partition, 2, 3), Vector3i(3, 35, 594), "plaster")
		box(v, Vector3i(partition, 2, 3), Vector3i(3, 10, 594), "plaster_blue")
		var x0 := 3 if col == 0 else 123
		var x1 := 67 if col == 0 else 187
		var plan: Array = WEST_ROOMS[f][col] if side == 0 else EAST_ROOMS[f][col]
		for row in 5:
			var z0: int = maxi(3, ROWS[row])
			var z1: int = mini(597, ROWS[row + 1])
			var kind: String = plan[row]
			if row > 0:
				box(v, Vector3i(x0, 2, z0), Vector3i(x1 - x0, 35, 3), "plaster")
				z0 += 3
			if col == 1 and row == 3:
				booths = SchoolRestrooms.build(v, Rect2i(x0, z0, x1 - x0, z1 - z0), partition)
				for booth: Dictionary in booths:
					if booth.transit:
						var center: Vector2 = Vector2(booth.plan.area.get_center()) * VoxelObject.VS
						rooms.append({"type": "restroom", "floor": f + 1, "at": origin + Vector3(center.x, 0.21, center.y),
							"plan": booth.plan})
				continue
			var door_z := (z0 + z1) / 2 - 8
			if kind == "stairs":
				door_z = z0 + 67
			Build.door(v, 0, partition, 3, door_z, 2, 16, 23, "metal_teal")
			if kind == "open":
				box(v, Vector3i(partition, 2, z0 + 5), Vector3i(3, 30, z1 - z0 - 10), "")
			elif kind == "commons":
				Build.door(v, 0, partition, 3, door_z - 4, 2, 31, 27, "metal_teal")
				var side_door := 179 if side == 0 else 426
				Build.door(v, 0, 0, 3, side_door, 2, 29, 27, "metal_teal")
				var plan_area := Rect2i(x0, z0, x1 - x0, z1 - z0)
				var furnished := SchoolInteriors.commons(v, plan_area, door_z - 4, side_door)
				var center := origin + Vector3(float(x0 + x1) * 0.05, 0.21, float(z0 + z1) * 0.05)
				rooms.append({"type": kind, "floor": f + 1, "at": center, "plan": furnished})
				var label := "КОРПУС А" if side == 0 else "КОРПУС Б"
				var width := VoxelFont.text_width(label)
				var sign_z := side_door + 14 - width / 2
				box(v, Vector3i(0, 31, sign_z - 2), Vector3i(1, 7, width + 4), "metal_teal")
				VoxelFont.draw(v, label, Vector3i(0, 37, sign_z), Vector3i(0, 0, 1), VoxMat.id("metal_white"))
			elif kind == "stairs":
				_stairs(v, x0, x1, z0, f)
			else:
				var class_slot := Vector4i(side, f, col, row) in NPC_CLASS_SLOTS
				var furnishing := SchoolInteriors.furnish(v, kind, Rect2i(x0, z0, x1 - x0, z1 - z0), side, f, col, door_z, class_slot)
				if class_slot:
					homeroom = furnishing
				var room_center := origin + Vector3(float(x0 + x1) * 0.05, 0.21, float(z0 + z1) * 0.05)
				rooms.append({"type": kind, "floor": f + 1, "at": room_center, "plan": furnishing})
				var plaque := SchoolRooms.title(kind)
				var sign_width := mini(72, VoxelFont.text_width(plaque) + 6)
				var sign_z := clampi(door_z + 8 - sign_width / 2, z0 + 1, z1 - sign_width - 1)
				box(v, Vector3i(partition + (2 if col == 0 else 0), 26, sign_z), Vector3i(1, 7, sign_width), "metal_teal")
				VoxelFont.draw(v, plaque,
					Vector3i(partition + (3 if col == 0 else -1), 31, sign_z + (sign_width - 3 if col == 0 else 3)),
					Vector3i(0, 0, -1 if col == 0 else 1), VoxMat.id("metal_white"))
	if f == 1:
		box(v, Vector3i(84 if side == 0 else 85, 2, 0), Vector3i(21, 21, 3), "")
	# Wide portals through the inside of the H.
	var mouth := 187 if side == 0 else 0
	box(v, Vector3i(mouth, 2, 247), Vector3i(3, 29, 86), "")
	if f == 0 and side == 0:
		Build.door(v, 0, 0, 3, 301, 2, 30, 28, "metal_teal")
	if side == 1:
		box(v, Vector3i(187, 2, 265), Vector3i(3, 29, 49), "")
		if f == 0:
			box(v, Vector3i(67, 10, 515), Vector3i(3, 13, 15), "")
	if side == 0:
		if f in [0, 1]:
			var d := Vector3i(roundi((DUCT.x - origin.x) * 10), 0, roundi((DUCT.z - origin.z) * 10))
			if f == 1:
				box(v, d - Vector3i(6, 0, 6), Vector3i(12, 2, 12), "")
		if f == 1:
			box(v, Vector3i(151, 2, 140), Vector3i(15, 22, 3), "")
			SchoolInteriors.fume_cabinet(v)
		if f == 2:
			_shaft_hole(v, origin, Vector2(-15.2, -9.2), 6)
		if f == 0:
			box(v, Vector3i(3, 1, 3), Vector3i(64, 1, 592), "wood_light")
	if f == 3 and side == 0:
		SchoolInteriors.attic_trim(v)
	var corridor_locker := SchoolInteriors.corridor(v, side, f, homeroom)
	if not homeroom.is_empty():
		var area: Rect2i = homeroom.area
		var path_area := area.merge(Rect2i(70, area.position.y, 50, area.size.y))
		homeroom["routes"] = SchoolNpcRoutes.new(v, origin, path_area)
		npc_classes.append(homeroom)
	for z in [53, 163, 272, 390, 516, 574]:
		box(v, Vector3i(83, 36, z), Vector3i(23, 1, 3), "lamp")
		interior_lights.append(fixture(v, Vector3i(94, 36, z), origin + Vector3(9.4, 3.25, z * 0.1), Color("#dbe5fa"), 1.24, 7.8))
		if z in [53, 272, 516]:
			warning_points.append(origin + Vector3(6.7, 2.58, z * 0.1))
	for z in [80, 190, 422, 544]:
		for x in [3.5, 15.7]:
			interior_lights.append(fixture(v, Vector3i(roundi(x * 10), 36, z), origin + Vector3(x, 3.22, z * 0.1), Color("#f6d4a0"), 1.35, 7.4))
	var wing := place(v, origin, "Учебный корпус %d · этаж %d" % [side + 1, f + 1])
	wings[Vector2i(side, f)] = wing
	corridor_locker["building"] = wing
	hide_spots.append(corridor_locker)
	SchoolRestrooms.install(self, booths, origin, side, f)
	for room in rooms:
		if room.floor != f + 1 or (room.at.x < 0) != (side == 0):
			continue
		for spot: Dictionary in room.plan.hides:
			spot["building"] = wing
			hide_spots.append(spot)


func _stairs(v: VoxelVolume, x0: int, x1: int, z0: int, f: int) -> void:
	var mid := (x0 + x1) / 2
	if f > 0:
		box(v, Vector3i(x0 + 4, 0, z0 + 8), Vector3i(x1 - x0 - 8, 2, 52), "")
	if f == 3:
		box(v, Vector3i(x0 + 3, 0, z0 + 57), Vector3i(mid - x0 - 4, 2, 3), "concrete")
		for x in range(x0 + 3, mid - 2, 4):
			box(v, Vector3i(x, 2, z0 + 57), Vector3i(1, 11, 2), "metal_teal")
		box(v, Vector3i(x0 + 2, 12, z0 + 57), Vector3i(mid - x0 - 3, 2, 2), "wood_dark")
		return
	for step in 10:
		var z := z0 + 56 - step * 4
		var h := 2 + roundi((step + 1) * 1.9)
		box(v, Vector3i(x0 + 4, h - 2, z), Vector3i(mid - x0 - 5, 2, 4), "concrete")
		box(v, Vector3i(mid - 2, h, z), Vector3i(1, 8, 1), "metal_teal")
		box(v, Vector3i(mid - 2, h + 8, z), Vector3i(2, 2, 4), "wood_dark")
		var zr := z0 + 23 + step * 4
		var hr := 21 + roundi((step + 1) * 1.9)
		box(v, Vector3i(mid + 1, hr - 2, zr), Vector3i(x1 - mid - 5, 2, 4), "concrete")
		if step < 8:
			box(v, Vector3i(mid + 1, hr, zr), Vector3i(1, 8, 1), "metal_teal")
			box(v, Vector3i(mid + 1, hr + 8, zr), Vector3i(2, 2, 4), "wood_dark")
	box(v, Vector3i(x0 + 4, 19, z0 + 9), Vector3i(x1 - x0 - 8, 2, 15), "concrete")


func _bridge(f: int) -> void:
	var y := GROUND + LEVEL_HEIGHT * f
	var main := Build.vol(Vector3i(200, 38, 120))
	box(main, Vector3i.ZERO, Vector3i(200, 2, 120), "concrete")
	for z in [0, 117]:
		box(main, Vector3i(0, 2, z), Vector3i(200, 36, 3), "panel_grey")
		for x in [8, 42, 76, 110, 144, 172]:
			Build.window(main, 2, z, 3, x, 9, 22, 20, "metal_teal", -1 if z == 0 else 1)
	if f == 0:
		Build.door(main, 2, 117, 3, 81, 2, 38, 29, "metal_dark")
		Build.door(main, 2, 0, 3, 81, 2, 38, 28, "metal_dark")
		for x in [63, 130]:
			box(main, Vector3i(x, 2, 103), Vector3i(4, 10, 8), "metal_dark")
			box(main, Vector3i(x, 10, 104), Vector3i(6, 1, 1), "metal")
		box(main, Vector3i(18, 2, 77), Vector3i(35, 8, 10), "wood_dark")
		SchoolInteriors.guard_lobby(main)
		SchoolRooms.chair(main, Vector3i(44, 2, 97), "wood")
		_shaft_hole(main, Vector3(-10, y, -6), LOBBY_HATCH)

	else:
		for x in range(20, 186, 26):
			SchoolRooms.locker(main, Vector3i(x, 2, 7), "metal_blue")

	if f > 0:
		for x in [9, 152]:
			SchoolRooms.desk(main, Vector3i(x, 2, 91), 32, 7, "wood_dark", 5)
			box(main, Vector3i(x, 7, 97), Vector3i(32, 5, 1), "wood")
			SchoolDetails.classroom_detail(main, Vector3i(x + 4, 2, 21), "art" if f == 3 else "bio")
		VoxelFont.draw(main, "ЭТАЖ %d" % (f + 1), Vector3i(75, 30, 116), Vector3i(1, 0, 0), VoxMat.id("metal_teal"))
	for x in [-6.0, 0.0, 6.0]:
		interior_lights.append(fixture(main, Vector3i(roundi((x + 10.0) * 10.0), 36, 60),
			Vector3(x, y + 3.28, 0), Color("#bbd7f4"), 1.38, 10.0))
	place(main, SchoolGrid.origin("bridge", y), "Переход · этаж %d" % (f + 1))
	var corridor := Build.vol(Vector3i(60, 38, 50))
	box(corridor, Vector3i.ZERO, Vector3i(60, 2, 50), "concrete")
	for z in [0, 48]:
		box(corridor, Vector3i(0, 2, z), Vector3i(60, 36, 2), "panel_grey")
		Build.window(corridor, 2, z, 2, 10, 10, 36, 19, "metal_teal", 1 if z else -1)
	interior_lights.append(fixture(corridor, Vector3i(30, 36, 25), Vector3(32, y + 3.28, 0),
		Color("#bbd7f4"), 1.38, 10.0))
	place(corridor, SchoolGrid.origin("sports_bridge", y), "Галерея спорткорпуса")
	for x in [-6.0, 0.0, 6.0, 32.0]:
		warning_points.append(Vector3(x, y + 2.75, 2.25))


func _entry() -> void:
	var entry := Build.vol(Vector3i(112, 65, 64))
	box(entry, Vector3i.ZERO, Vector3i(112, 2, 64), "stone")
	for x in [0, 108]:
		box(entry, Vector3i(x, 2, 0), Vector3i(4, 38, 64), "brick_tan")
		Build.window(entry, 0, x, 4, 8, 9, 42, 26, "metal_teal", -1 if x == 0 else 1)
	for x in [0, 71]:
		box(entry, Vector3i(x, 2, 60), Vector3i(41, 38, 4), "brick_tan")
		Build.window(entry, 2, 60, 4, x + 5, 8, 31, 23, "metal_teal", 1)
	box(entry, Vector3i(41, 27, 60), Vector3i(30, 3, 4), "metal_teal")
	box(entry, Vector3i(0, 40, 0), Vector3i(112, 4, 64), "concrete_dark")
	box(entry, Vector3i(0, 31, 59), Vector3i(112, 9, 5), "metal_teal")
	for x in [1, 108]:
		box(entry, Vector3i(x, 44, 0), Vector3i(3, 9, 64), "metal_dark")
	box(entry, Vector3i(0, 44, 61), Vector3i(112, 9, 3), "metal_dark")
	for x in range(8, 110, 9):
		box(entry, Vector3i(x, 2, 36), Vector3i(5, 1, 2), "metal_dark")
	for x in [17, 86]:
		box(entry, Vector3i(x, 39, 14), Vector3i(9, 1, 29), "lamp")
	VoxelFont.draw(entry, "ГЛАВНЫЙ ВХОД", Vector3i(23, 38, 63), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	for x in [21, 90]:
		interior_lights.append(fixture(entry, Vector3i(x, 39, 30), Vector3(-5.6 + x * 0.1, 5.54, 9.0),
			Color("#ffe5c1"), 1.45, 9.6))
	place(entry, Vector3(-5.6, GROUND, 6.0), "Главный вход")
	for side in [-1.0, 1.0]:
		var leaf := Build.vol(Vector3i(13, 24, 3))
		box(leaf, Vector3i(0, 0, 1), Vector3i(13, 24, 1), "metal_teal")
		box(leaf, Vector3i(2, 8, 1), Vector3i(9, 14, 1), "glass")
		box(leaf, Vector3i(6, 8, 1), Vector3i(1, 14, 1), "metal_teal")
		for z in [0, 2]:
			box(leaf, Vector3i(1, 1, z), Vector3i(11, 2, 1), "metal_dark")
			box(leaf, Vector3i(2, 5, z), Vector3i(8, 1, 1), "metal")
			box(leaf, Vector3i(9, 8, z), Vector3i(2, 6, 1), "metal_yellow")
		var door := DistrictDoor.install_leaf(world, Vector3(side * 1.34, 2.24, 12.24),
			0.0 if side < 0.0 else PI, leaf)
		entry_doors.append(door)


func _annex(f: int) -> void:
	var at := SchoolGrid.origin("annex", GROUND + LEVEL_HEIGHT * f)
	var v := Build.vol(Vector3i(230, 38, 340))
	Build.walls(v, 0, 0, 230, 340, 2, 38, 3, "brick", 120 + f)
	for z in [0, 337]:
		for x in [21, 71, 121, 171]:
			Build.window(v, 2, z, 3, x, 10, 31, 19, "metal_teal", 1 if z else -1)
	for x in [0, 227]:
		for z in [23, 70, 178, 227, 276]:
			Build.window(v, 0, x, 3, z, 10, 32, 18, "metal_teal", 1 if x else -1)
	box(v, Vector3i(0, 2, 126), Vector3i(3, 25, 49), "")
	box(v, Vector3i(3, 2, 160), Vector3i(224, 36, 3), "plaster_blue")
	Build.door(v, 2, 160, 3, 9, 2, 18, 24, "metal_teal")
	box(v, Vector3i.ZERO, Vector3i(230, 2, 340), "concrete")
	if f == 0:
		SchoolRooms.canteen(v)
		SchoolRooms.pool(v)
		Build.door(v, 2, 337, 3, 25, 2, 25, 25)
		Build.door(v, 0, 227, 3, 35, 2, 24, 24)
	elif f == 1:
		SchoolRooms.gym(v)
		SchoolRooms.changing(v)
		SchoolRooms.desk(v, Vector3i(179, 2, 79), 27, 8, "wood_light", 10)
		VoxelFont.draw(v, "БУФЕТ", Vector3i(177, 17, 88), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	elif f == 2:
		box(v, Vector3i(3, 0, 3), Vector3i(224, 2, 157), "")
		# The third-floor landing is a gallery overlooking the double-height court.
		box(v, Vector3i(3, 0, 124), Vector3i(27, 2, 36), "metal_dark")
		box(v, Vector3i(29, 0, 140), Vector3i(198, 2, 20), "metal_dark")
		box(v, Vector3i(29, 2, 140), Vector3i(198, 10, 1), "metal_teal")
		box(v, Vector3i(29, 2, 124), Vector3i(1, 9, 16), "metal_teal")
		box(v, Vector3i(4, 2, 124), Vector3i(21, 9, 1), "metal_teal")
		for x in [55, 125, 191]:
			box(v, Vector3i(x, 22, 3), Vector3i(4, 3, 156), "metal_dark")
		box(v, Vector3i(12, 22, 133), Vector3i(184, 3, 9), "metal_dark")
		SchoolRooms.theatre(v)
	else:
		SchoolRooms.studio(v)
		# Technical room above the lift and the projection gallery.
		box(v, Vector3i(27, 0, 172), Vector3i(160, 2, 103), "")
		box(v, Vector3i(27, 2, 275), Vector3i(160, 9, 1), "metal_teal")
		for x in [44, 88, 132, 174]:
			box(v, Vector3i(x, 0, 181), Vector3i(3, 2, 93), "metal_dark")
	_shaft_hole(v, at, LIFT)
	var lx := int(round((LIFT.x - at.x) * 10.0))
	var lz := int(round((LIFT.y - at.z) * 10.0))
	for x in [lx - 11, lx + 10]:
		box(v, Vector3i(x, 2, lz - 10), Vector3i(1, 35, 20), "metal_dark")
	box(v, Vector3i(lx - 10, 2, lz - 11), Vector3i(21, 35, 1), "metal_dark")
	box(v, Vector3i(lx - 11, 25, lz + 10), Vector3i(22, 13, 2), "metal_dark")
	if f == 2:
		var landing_z := lz + 10
		box(v, Vector3i(lx - 16, 0, landing_z), Vector3i(32, 2, 160 - landing_z), "metal_dark")
		for x in [lx - 16, lx + 15]:
			box(v, Vector3i(x, 2, landing_z + 5), Vector3i(1, 9, 138 - landing_z), "metal_teal")
	var floor_y := at.y + 0.2
	if f == 0:
		npc_jobs["cook"] = SchoolNpcRoutes.new(v, at, Rect2i(104, 4, 121, 148))
	for pos in [Vector2(39, -5), Vector2(47, -8), Vector2(42, 4), Vector2(49, 11), Vector2(55, 16)]:
		interior_lights.append(fixture(v, Vector3i(roundi((pos.x - at.x) * 10), 36, roundi((pos.y - at.z) * 10)), Vector3(pos.x, floor_y + 3.18, pos.y), Color("#c5dafa" if f in [1, 3] else "#ffe1ac"), 1.35, 9.0))
	annex[f] = place(v, at, "Спорткорпус · этаж %d" % (f + 1))
	warning_points.append(Vector3(37.2, floor_y + 2.8, -1.7))


static func _shaft_hole(v: VoxelVolume, origin: Vector3, point: Vector2, half := 10) -> void:
	var cell := Vector3i(roundi((point.x - origin.x) * 10), 0, roundi((point.y - origin.z) * 10))
	box(v, cell - Vector3i(half, 0, half), Vector3i(half * 2, 2, half * 2), "")


func _roofs() -> void:
	var y := GROUND + LEVEL_HEIGHT * 4
	for side in 2:
		var v := Build.vol(Vector3i(190, 12, 600))
		box(v, Vector3i.ZERO, Vector3i(190, 3, 600), "roof_bitumen")
		for x in [0, 188]:
			box(v, Vector3i(x, 3, 0), Vector3i(2, 7, 600), "panel_grey")
		for z in [0, 598]:
			box(v, Vector3i(0, 3, z), Vector3i(190, 7, 2), "panel_grey")
		for z in [60, 220, 415]:
			box(v, Vector3i(41, 3, z), Vector3i(15, 6, 13), "metal_dark")

		for z in range(24, 470, 38):
			box(v, Vector3i(6, 2, z), Vector3i(178, 1, 1), "metal_dark")
		for z in [110, 300]:
			box(v, Vector3i(120, 3, z), Vector3i(30, 3, 43), "metal_dark")
			box(v, Vector3i(122, 6, z + 2), Vector3i(26, 2, 39), "glass")
			for dz in range(3, 42, 8):
				box(v, Vector3i(121, 7, z + dz), Vector3i(28, 1, 1), "metal_teal")
		if side == 0:
			var x := roundi((ATTIC.x - WING_X[0]) * 10.0)
			var z := roundi((ATTIC.z + 29.0) * 10.0)
			box(v, Vector3i(x - 6, 0, z - 6), Vector3i(12, 3, 12), "")
		place(v, Vector3(WING_X[side], y, -29), "Крыша корпуса")
	var bridge := Build.vol(Vector3i(200, 3, 120))
	box(bridge, Vector3i.ZERO, bridge.get_size(), "roof_bitumen")
	place(bridge, Vector3(-10, y, -6), "Крыша перехода")
	var gallery := Build.vol(Vector3i(60, 3, 50))
	box(gallery, Vector3i.ZERO, gallery.get_size(), "roof_bitumen")
	place(gallery, SchoolGrid.origin("sports_bridge", y), "Крыша галереи спорткорпуса")
	var annex_top := Build.vol(Vector3i(230, 10, 340))
	box(annex_top, Vector3i.ZERO, Vector3i(230, 3, 340), "roof_bitumen")
	place(annex_top, Vector3(35, y, -15), "Крыша спорткорпуса")
	var loft := Build.vol(Vector3i(37, 26, 34))
	Build.walls(loft, 0, 0, 37, 34, 0, 24, 2, "wood_dark", 77)
	Build.door(loft, 2, 32, 2, 12, 0, 13, 21, "wood_light")
	Build.gable_roof(loft, 0, 37, 0, 34, 20, "roof_tile", "wood_dark", 0, 2, 18)
	for x in [4, 12, 20, 28]:
		box(loft, Vector3i(x, 11, 0), Vector3i(4, 5, 3), "")
		box(loft, Vector3i(x, 10, 2), Vector3i(5, 1, 7), "wood_light")
	place(loft, Vector3(ATTIC.x - 1.85, y + 0.3, ATTIC.z - 1.7), "Голубятня")
	var tin := Build.vol(Vector3i(74, 12, 51))
	for x in 74:
		var h := mini(x, 73 - x) / 4 + 1
		box(tin, Vector3i(x, h - 1, 0), Vector3i(1, 1, 51), "metal" if x % 6 == 0 else "metal_dark")
	place(tin, Vector3(-28, y + 0.3, 25.8), "Скат жестяной крыши")
