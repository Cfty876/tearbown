class_name DistrictSecretProps
extends RefCounted

const GARAGE_EXIT := Vector3(12, 2.11, -79.1)
const BOOTHS := [Vector3(-49.0, 2.0, 24.5), Vector3(81.0, 2.0, -61.0)]
const BOOTH_YAWS := [0.0, -PI * 0.5]
const VENDING := Vector3(-57.5, 2.0, 31.35)
const ROOF_STATION := Vector3(-42, 17.3, -61.3)
const GATE_SIREN := Vector3(9.7, 4.94, -79.48)


static func box(volume: VoxelVolume, at: Vector3i, size: Vector3i, swatch: String) -> void:
	volume.fill_box(at, at + size, 0 if swatch.is_empty() else VoxMat.id(swatch))


static func model(parent: Node3D, volume: VoxelVolume, at: Vector3, solid := false,
		yaw := 0.0, label := "") -> Node3D:
	var size := Vector3(volume.get_size())
	if solid:
		var prop := VoxelObject.new().setup(volume, true, Vector3i(64, 32, 64))
		prop.position = at - Basis(Vector3.UP, yaw) * Vector3(size.x * 0.05, 0, size.z * 0.05)
		prop.rotation.y = yaw
		prop.label = label
		parent.add_child(prop)
		return prop
	var mesh := MeshInstance3D.new()
	mesh.mesh = VoxModel.mesh(volume, 0.1, Vector3(size.x * 0.5, 0, size.z * 0.5))
	mesh.position = at
	mesh.rotation.y = yaw
	mesh.visibility_range_end = 125.0
	parent.add_child(mesh)
	return mesh


static func garage(parent: Node3D) -> void:
	var volume := Build.vol(Vector3i(64, 37, 68))
	box(volume, Vector3i.ZERO, Vector3i(64, 1, 68), "concrete")
	box(volume, Vector3i(22, 0, 22), Vector3i(20, 1, 20), "")
	box(volume, Vector3i(0, 1, 0), Vector3i(64, 33, 2), "brick")
	box(volume, Vector3i(0, 1, 2), Vector3i(2, 33, 66), "brick")
	box(volume, Vector3i(62, 1, 2), Vector3i(2, 33, 66), "brick")
	box(volume, Vector3i(0, 27, 64), Vector3i(64, 7, 4), "metal_dark")
	box(volume, Vector3i(0, 34, 0), Vector3i(64, 3, 68), "roof_bitumen")
	for z in range(20, 44, 2):
		for x in [20, 42]:
			box(volume, Vector3i(x, 0, z), Vector3i(2, 1, 2),
				"metal_yellow" if z % 4 == 0 else "metal_dark")
	for x in [5, 54]:
		box(volume, Vector3i(x, 1, 27), Vector3i(4, 26, 4), "metal_yellow")
		box(volume, Vector3i(x, 1, 5), Vector3i(6, 10, 16), "metal_teal")
		box(volume, Vector3i(x, 10, 5), Vector3i(7, 1, 16), "wood_dark")
	for x in [10, 45]:
		box(volume, Vector3i(x, 33, 43), Vector3i(9, 1, 3), "lamp")
	box(volume, Vector3i(9, 27, 67), Vector3i(46, 7, 1), "metal_white")
	VoxelFont.draw(volume, "ГАРАЖ", Vector3i(20, 32, 67), Vector3i(1, 0, 0), VoxMat.id("metal_dark"))
	model(parent, volume, Vector3(12, 2, -83), true, 0.0, "garage_pit")
	var siren := Build.vol(Vector3i(18, 11, 12))
	box(siren, Vector3i(2, 3, 0), Vector3i(14, 5, 4), "metal_dark")
	box(siren, Vector3i(3, 2, 3), Vector3i(12, 8, 5), "metal_red")
	box(siren, Vector3i(0, 1, 7), Vector3i(18, 9, 4), "metal_red")
	box(siren, Vector3i(2, 3, 10), Vector3i(14, 5, 2), "tank_black")
	for x in [3, 6, 9, 12, 15]:
		box(siren, Vector3i(x, 3, 11), Vector3i(1, 5, 1), "metal")
	box(siren, Vector3i(8, 8, 10), Vector3i(2, 2, 1), "plastic_orange")
	var horn := VoxModel.instance(siren, 0.036, Vector3(9, 5, 6))
	horn.position = GATE_SIREN
	parent.add_child(horn)


static func bunker(parent: Node3D) -> void:
	var room := Build.vol(Vector3i(62, 20, 17))
	box(room, Vector3i(0, 0, 0), Vector3i(17, 17, 10), "metal_green")
	for leaf in [1, 9]:
		box(room, Vector3i(leaf, 1, 10), Vector3i(7, 15, 1), "metal_teal")
		box(room, Vector3i(leaf + 4, 7, 11), Vector3i(1, 3, 1), "metal_yellow")
	for x in [22, 47]:
		box(room, Vector3i(x, 0, 2), Vector3i(2, 14, 14), "metal_dark")
	for height in [1, 6, 11]:
		box(room, Vector3i(22, height, 2), Vector3i(27, 1, 14), "wood_light")
		for i in 4:
			box(room, Vector3i(24 + 5 * i, height + 1, 7), Vector3i(4, 3, 7),
				["wood", "metal_green", "metal_dark"][(i + height) % 3])
	box(room, Vector3i(0, 17, 0), Vector3i(28, 3, 1), "metal_yellow")
	model(parent, room, Vector3(-79.3, DistrictSecretMap.FLOOR, 18.0), true, 0.0, "civil_defense_supply")
	var placard := Build.vol(Vector3i(54, 8, 1))
	box(placard, Vector3i.ZERO, placard.get_size(), "metal_dark")
	VoxelFont.draw(placard, "УКРЫТИЕ", Vector3i(3, 6, 0), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	model(parent, placard, Vector3(-82.83, -1.26, 20.5), false, PI * 0.5)
	for item in [[Vector3(54.07, -1.28, 30.82), "ВЫХОД"], [Vector3(12.0, -1.28, -83.85), "ГАРАЖ"]]:
		var signboard := Build.vol(Vector3i(29, 8, 1))
		box(signboard, Vector3i.ZERO, signboard.get_size(), "metal_dark")
		VoxelFont.draw(signboard, item[1], Vector3i(2, 6, 0), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
		model(parent, signboard, item[0], false, PI if item[1] == "ВЫХОД" else 0.0)


static func cabinet() -> VoxelVolume:
	var v := Build.vol(Vector3i(20, 22, 20))
	box(v, Vector3i.ZERO, Vector3i(20, 1, 20), "metal_dark")
	box(v, Vector3i(0, 1, 4), Vector3i(20, 20, 1), "metal_teal")
	for x in [0, 19]:
		box(v, Vector3i(x, 1, 4), Vector3i(1, 20, 11), "metal_white")
	for y in [3, 8, 13, 20]:
		box(v, Vector3i(0, y, 4), Vector3i(20, 1, 11), "metal_white")
		if y < 20:
			for x in range(2, 18, 4):
				box(v, Vector3i(x, y + 1, 9), Vector3i(2, 3, 3),
					["plastic_white", "plastic_blue", "curtain_green"][(x + y) % 3])
	return v


static func garage_car() -> VoxelVolume:
	var car := Build.car("metal_teal", 64)
	box(car, Vector3i(2, 8, 2), Vector3i(8, 1, 15), "")
	box(car, Vector3i(4, 4, 5), Vector3i(5, 4, 8), "metal_dark")
	box(car, Vector3i(4, 7, 6), Vector3i(4, 1, 6), "metal")
	box(car, Vector3i(0, 5, 0), Vector3i(1, 4, 19), "metal_dark")
	box(car, Vector3i(0, 4, 0), Vector3i(1, 1, 19), "metal")
	for z in [3, 15]:
		car.fill_cylinder(Vector3(0, 7, z), 2.55, 1, 0, VoxMat.id("metal"))
		car.fill_cylinder(Vector3(0, 7, z), 1.65, 1, 0, VoxMat.id("lamp"))
	for z in range(6, 14, 2):
		box(car, Vector3i(0, 6, z), Vector3i(1, 2, 1), "metal")
	box(car, Vector3i(0, 5, 7), Vector3i(1, 1, 5), "metal_white")
	return car


static func roof_station(parent: Node3D) -> void:
	var v := Build.vol(Vector3i(50, 28, 40))
	box(v, Vector3i.ZERO, Vector3i(50, 1, 40), "concrete")
	box(v, Vector3i(0, 1, 0), Vector3i(50, 24, 2), "brick_tan")
	box(v, Vector3i(0, 1, 2), Vector3i(2, 24, 36), "panel_grey")
	box(v, Vector3i(48, 1, 2), Vector3i(2, 24, 36), "panel_grey")
	box(v, Vector3i(0, 1, 38), Vector3i(50, 24, 2), "panel_grey")
	box(v, Vector3i(20, 1, 38), Vector3i(10, 21, 2), "")
	Build.window(v, 2, 38, 2, 4, 9, 13, 12, "metal_teal", 1)
	Build.window(v, 2, 38, 2, 33, 9, 13, 12, "metal_teal", 1)
	Build.window(v, 0, 48, 2, 11, 9, 17, 12, "metal_teal", 1)
	box(v, Vector3i(0, 25, 0), Vector3i(50, 3, 40), "roof_bitumen")
	box(v, Vector3i(16, 22, 39), Vector3i(18, 3, 1), "metal_dark")
	VoxelFont.draw(v, "ПОСТ", Vector3i(16, 25, 39), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	box(v, Vector3i(7, 24, 16), Vector3i(17, 1, 2), "lamp")
	box(v, Vector3i(40, 1, 4), Vector3i(7, 17, 8), "metal_dark")
	for y in [6, 11, 15]:
		box(v, Vector3i(40, y, 12), Vector3i(5, 1, 1), "metal_teal")
	box(v, Vector3i(3, 1, 4), Vector3i(7, 10, 8), "metal_green")
	box(v, Vector3i(3, 10, 4), Vector3i(7, 1, 8), "wood_light")
	model(parent, v, ROOF_STATION, true, 0.0, "roof_watch_station")
	DistrictDoor.install(parent, ROOF_STATION + Vector3(-0.49, 0.1, 1.90), 0.0, "door_metal")
	var mast := Build.vol(Vector3i(20, 38, 20))
	box(mast, Vector3i(9, 0, 9), Vector3i(2, 33, 2), "metal_dark")
	for y in [25, 32]:
		box(mast, Vector3i(2, y, 9), Vector3i(16, 1, 2), "metal")
		for x in [4, 9, 14]:
			box(mast, Vector3i(x, y, 5), Vector3i(1, 1, 10), "metal")
	box(mast, Vector3i(9, 33, 9), Vector3i(2, 3, 2), "metal_red")
	model(parent, mast, ROOF_STATION + Vector3(-1.2, 2.8, -0.7))


static func watch_terminal(parent: Node3D) -> Vector3:
	var floor := ROOF_STATION + Vector3(0, 0.1, -1.14)
	var desk := Build.vol(Vector3i(21, 8, 11))
	box(desk, Vector3i(0, 7, 0), Vector3i(21, 1, 11), "wood_light")
	box(desk, Vector3i(0, 0, 0), Vector3i(4, 7, 10), "metal_teal")
	box(desk, Vector3i(17, 0, 0), Vector3i(4, 7, 10), "metal_teal")
	box(desk, Vector3i(4, 1, 1), Vector3i(13, 2, 2), "metal_dark")
	for y in [2, 5]:
		box(desk, Vector3i(1, y, 10), Vector3i(2, 1, 1), "metal")
	model(parent, desk, floor, true, 0.0, "cctv_workbench")

	const CELL := 0.04
	var terminal := Build.vol(Vector3i(49, 27, 27))
	# Monitor bezel, foot and recessed display.
	box(terminal, Vector3i(11, 0, 8), Vector3i(17, 2, 8), "metal_dark")
	box(terminal, Vector3i(17, 2, 10), Vector3i(5, 5, 4), "metal")
	box(terminal, Vector3i(4, 6, 3), Vector3i(31, 19, 12), "metal_dark")
	box(terminal, Vector3i(3, 7, 13), Vector3i(33, 18, 3), "metal")
	box(terminal, Vector3i(5, 9, 16), Vector3i(29, 14, 1), "tank_black")
	box(terminal, Vector3i(7, 10, 16), Vector3i(25, 12, 1), "metal_blue")
	box(terminal, Vector3i(7, 19, 16), Vector3i(25, 3, 1), "metal_teal")
	box(terminal, Vector3i(8, 20, 16), Vector3i(7, 1, 1), "sign_glow")
	for x in [8, 16, 24]:
		box(terminal, Vector3i(x, 12, 16), Vector3i(6, 5, 1), "tank_black")
		box(terminal, Vector3i(x + 1, 14, 16), Vector3i(4, 2, 1), "metal_green")
		box(terminal, Vector3i(x + 1, 12, 16), Vector3i(1, 1, 1), "brand_green")
	box(terminal, Vector3i(32, 7, 16), Vector3i(1, 1, 1), "lamp")
	for y in [14, 17, 20]:
		box(terminal, Vector3i(35, y, 6), Vector3i(1, 1, 6), "tank_black")
	# Keyboard, mouse, and the separate video recorder with vented casing.
	box(terminal, Vector3i(6, 0, 19), Vector3i(26, 2, 7), "metal_dark")
	for x in range(8, 30, 2):
		for z in [20, 22, 24]:
			box(terminal, Vector3i(x, 2, z), Vector3i(1, 1, 1), "pvc")
	box(terminal, Vector3i(13, 2, 25), Vector3i(10, 1, 1), "pvc")
	box(terminal, Vector3i(35, 0, 21), Vector3i(5, 1, 6), "tank_black")
	box(terminal, Vector3i(36, 1, 22), Vector3i(3, 2, 4), "metal")
	box(terminal, Vector3i(39, 0, 2), Vector3i(9, 16, 15), "metal_dark")
	box(terminal, Vector3i(40, 3, 17), Vector3i(7, 12, 1), "metal_blue")
	for y in [5, 7, 9]:
		box(terminal, Vector3i(41, y, 17), Vector3i(5, 1, 1), "tank_black")
	box(terminal, Vector3i(41, 12, 17), Vector3i(1, 1, 1), "brand_green")
	box(terminal, Vector3i(44, 12, 17), Vector3i(1, 1, 1), "lamp")
	var computer := VoxModel.instance(terminal, CELL, Vector3(24.5, 0, 13.5))
	computer.position = floor + Vector3.UP * 0.8
	parent.add_child(computer)
	return computer.position + Vector3(-0.08, 0.62, 0.25)


static func radio_table(parent: Node3D, dock: Vector3) -> void:
	var stand := Build.vol(Vector3i(7, 9, 6))
	box(stand, Vector3i(0, 8, 0), Vector3i(7, 1, 6), "wood_light")
	box(stand, Vector3i(0, 0, 0), Vector3i(1, 8, 6), "metal_teal")
	box(stand, Vector3i(6, 0, 0), Vector3i(1, 8, 6), "metal_teal")
	model(parent, stand, dock - Vector3.UP * 0.90, true, 0.0, "Столик радиоузла")


static func camera_model() -> ArrayMesh:
	var v := Build.vol(Vector3i(16, 12, 23))
	box(v, Vector3i(2, 2, 3), Vector3i(12, 8, 18), "metal_white")
	box(v, Vector3i(1, 9, 1), Vector3i(14, 2, 21), "metal")
	box(v, Vector3i(1, 4, 2), Vector3i(1, 6, 19), "metal")
	box(v, Vector3i(14, 4, 2), Vector3i(1, 6, 19), "metal")
	box(v, Vector3i(2, 2, 2), Vector3i(12, 7, 2), "tank_black")
	v.fill_cylinder(Vector3(8, 5, 1), 3.0, 2, 2, VoxMat.id("metal_dark"))
	v.fill_cylinder(Vector3(8, 5, 0), 1.8, 1, 2, VoxMat.id("metal_blue"))
	box(v, Vector3i(3, 3, 1), Vector3i(1, 1, 1), "metal_red")
	for z in [15, 18]:
		box(v, Vector3i(3, 9, z), Vector3i(10, 1, 1), "metal_dark")
	box(v, Vector3i(6, 0, 16), Vector3i(4, 3, 5), "metal_dark")
	return VoxModel.mesh(v, 0.036, Vector3(8, 5.5, 11.5))


static func camera_mount(parent: Node3D, anchor: Vector3, at: Vector3) -> void:
	var length := ceili(anchor.distance_to(at) / 0.04) + 1
	var v := Build.vol(Vector3i(6, length, 6))
	box(v, Vector3i(2, 0, 2), Vector3i(2, length, 2), "metal_dark")
	box(v, Vector3i(0, 0, 0), Vector3i(6, 2, 6), "metal")
	box(v, Vector3i(1, length - 2, 1), Vector3i(4, 2, 4), "metal")
	var instance := VoxModel.instance(v, 0.04, Vector3(3, 0, 3))
	instance.position = anchor
	instance.basis = Fx.basis_y(anchor.direction_to(at))
	parent.add_child(instance)


static func rug() -> VoxelVolume:
	var v := Build.vol(Vector3i(19, 23, 1))
	for y in 23:
		for x in 19:
			var edge := mini(mini(x, 18 - x), mini(y, 22 - y))
			var diamond := absi(x - 9) + absi(y - 11)
			var swatch := "curtain_red"
			if edge == 0:
				swatch = "curtain_beige"
			elif edge == 2 or diamond == 8 or diamond == 4:
				swatch = "wood_light"
			elif edge == 3 or diamond < 4 or (absi(x - 9) + y) % 8 == 0:
				swatch = "curtain_green"
			if y != 0 or x % 2 == 0:
				v.set_voxel(Vector3i(x, y, 0), VoxMat.id(swatch))
	return v


static func vending() -> VoxelVolume:
	var v := Build.vol(Vector3i(12, 21, 8))
	box(v, Vector3i.ZERO, Vector3i(12, 21, 7), "metal_teal")
	box(v, Vector3i(0, 0, 0), Vector3i(12, 2, 8), "metal_dark")
	box(v, Vector3i(0, 19, 0), Vector3i(12, 2, 8), "metal_dark")
	for x in [0, 11]:
		box(v, Vector3i(x, 2, 7), Vector3i(1, 17, 1), "metal")
	box(v, Vector3i(2, 9, 7), Vector3i(5, 3, 1), "tank_black")
	box(v, Vector3i(3, 10, 7), Vector3i(3, 1, 1), "metal_teal")
	box(v, Vector3i(1, 13, 7), Vector3i(10, 6, 1), "metal_white")
	VoxelFont.draw(v, "ГАЗ", Vector3i(0, 17, 7), Vector3i(1, 0, 0), VoxMat.id("brand_red"))
	box(v, Vector3i(8, 9, 7), Vector3i(2, 2, 1), "metal_yellow")
	box(v, Vector3i(3, 3, 6), Vector3i(6, 6, 1), "tank_black")
	return v


static func booth() -> VoxelVolume:
	var v := Build.vol(Vector3i(16, 24, 17))
	box(v, Vector3i.ZERO, Vector3i(16, 1, 17), "metal_dark")
	box(v, Vector3i(0, 1, 0), Vector3i(16, 21, 2), "plastic_blue")
	for x in [0, 14]:
		box(v, Vector3i(x, 1, 2), Vector3i(2, 21, 15), "plastic_blue")
		for z in [4, 8, 12, 16]:
			box(v, Vector3i(x, 2, z), Vector3i(2, 18, 1), "metal_blue")
	box(v, Vector3i(0, 22, 0), Vector3i(16, 2, 17), "pvc")
	box(v, Vector3i(5, 1, 2), Vector3i(6, 5, 5), "pvc")
	box(v, Vector3i(5, 8, 2), Vector3i(6, 4, 3), "plastic_white")
	return v


static func doghouse() -> VoxelVolume:
	var v := Build.vol(Vector3i(20, 17, 20))
	box(v, Vector3i.ZERO, Vector3i(20, 12, 2), "wood")
	for x in [0, 18]:
		box(v, Vector3i(x, 0, 2), Vector3i(2, 12, 18), "wood_dark")
	for step in 5:
		for x: int in [step, 19 - step]:
			box(v, Vector3i(x, 11 + step, 0), Vector3i(1, 2, 20), "roof_tile")
	box(v, Vector3i(5, 16, 0), Vector3i(10, 1, 20), "roof_tile")
	for x in [2, 15]:
		box(v, Vector3i(x, 0, 18), Vector3i(3, 10, 2), "wood_light")
	return v


static func lilac() -> VoxelVolume:
	var v := Build.vol(Vector3i(24, 22, 24))
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	for i in 10:
		var x := rng.randi_range(5, 18)
		var z := rng.randi_range(5, 18)
		var y := rng.randi_range(8, 16)
		box(v, Vector3i(x, 0, z), Vector3i(1, y, 1), "wood_dark")
		v.fill_sphere(Vector3(x, y, z), 5.2, VoxMat.id("foliage"))
		for cluster in 3:
			var tip := Vector3i(x + rng.randi_range(-3, 3), y + rng.randi_range(2, 5), z + rng.randi_range(-3, 3))
			box(v, tip, Vector3i(2, 2, 2), "curtain_red" if cluster == 0 else "curtain_beige")
	return v


static func ladder(parent: Node3D, bottom: Vector3, top: Vector3, axis := Vector3.RIGHT) -> void:
	const SIZE := 0.05
	var height := ceili((top.y - bottom.y) / SIZE)
	var volume := Build.vol(Vector3i(18, height, 6))
	for x in [1, 15]:
		box(volume, Vector3i(x, 0, 1), Vector3i(2, height, 2), "metal_teal")
		for y in range(2, height - 2, 26):
			box(volume, Vector3i(x, y, 0), Vector3i(2, 2, 6), "metal_dark")
			box(volume, Vector3i(x, y, 3), Vector3i(1, 1, 1), "metal")
	for y in range(5, height, 6):
		box(volume, Vector3i(2, y, 1), Vector3i(14, 1, 2), "metal")
		for x in range(4, 15, 3):
			box(volume, Vector3i(x, y, 0), Vector3i(1, 1, 1), "metal_white")
	var instance := VoxModel.instance(volume, SIZE, Vector3(9, 0, 2))
	instance.position = bottom
	instance.rotation.y = -PI * 0.5 if absf(axis.z) > 0.5 else 0.0
	instance.visibility_range_end = 95.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func beam(parent: Node3D, from: Vector3, to: Vector3, radius: float, tint: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = from.distance_to(to)
	cylinder.radial_segments = 6
	cylinder.rings = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.76
	cylinder.material = material
	instance.mesh = cylinder
	instance.position = (from + to) * 0.5
	instance.basis = Fx.basis_y((to - from).normalized())
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
