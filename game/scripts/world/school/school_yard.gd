class_name SchoolYard
extends RefCounted

const TILE := 200
const TILES := 8
const YARD := 800
const ORIGIN := Vector3(-80, -1.3, -80)
const SURFACE := 32
const FOUNDATION := 3
const GATE := Vector3(0, 2, 53)
const GREENHOUSE_LOW := Vector3(20.4, 2.22, -52.5)
const GREENHOUSE_TOP := Vector3(20.4, 5.22, -52.5)

var _ground_tiles := {}


static func ground(level: SchoolLevel) -> void:
	var grid := SchoolYard.new()
	grid._ground(level)


func _ground(level: SchoolLevel) -> void:
	for z in TILES:
		for x in TILES:
			var v := Build.vol(Vector3i(TILE, SURFACE + 1, TILE))
			SchoolLevel.box(v, Vector3i.ZERO, Vector3i(TILE, FOUNDATION, TILE), "bedrock")
			SchoolLevel.box(v, Vector3i(0, FOUNDATION, 0), Vector3i(TILE, SURFACE - FOUNDATION, TILE), "dirt")
			SchoolLevel.box(v, Vector3i(0, SURFACE, 0), Vector3i(TILE, 1, TILE), "grass")
			_ground_tiles[Vector2i(x, z)] = v
	for area: Rect2 in SchoolCampus.ROADS:
		_paint(area, "asphalt")
	for area: Rect2 in SchoolCampus.WALKS + SchoolCampus.EXTRA_WALKS:
		_paint(area, "stone")
		_paint(Rect2(area.position + Vector2(0.1, 0.1), area.size - Vector2(0.2, 0.2)), "sidewalk")
	for area: Rect2 in SchoolCampus.PADS.values():
		_paint(area, "concrete")
	# Set paving into the ground, so seams never create floating collision surfaces.
	for area: Rect2 in SchoolCampus.WALKS + SchoolCampus.EXTRA_WALKS:
		var along_x := area.size.x > area.size.y
		var length := area.size.x if along_x else area.size.y
		for step in range(1, floori(length)):
			var joint := Rect2(area.position, Vector2(0.1, area.size.y) if along_x else Vector2(area.size.x, 0.1))
			joint.position += Vector2(step, 0) if along_x else Vector2(0, step)
			_paint(joint, "stone")
	_paint(Rect2(-40, 35, 8, 15), "asphalt")
	for x in [-10.9, 10.6]:
		for z in [16.5, 21.3, 31.5, 42.2]:
			_paint(Rect2(x, z, 0.35, 1.1), "brick_tan")
	_paint(Rect2(-5.6, 12.4, 11.2, 1.4), "concrete")
	for z in range(15, 39, 4):
		_paint(Rect2(-5.45, z, 10.9, 0.16), "stone")
	for x in range(-60, 76, 7):
		_paint(Rect2(x, 55.85, 4.2, 0.14), "road_line")
	for z in range(-60, 47, 7):
		_paint(Rect2(-61.8, z, 0.14, 3.8), "road_line")
	for stripe in 12:
		_paint(Rect2(-2.7, 51.2 + stripe * 0.74, 5.4, 0.36), "road_line")
	for z in range(37, 48, 3):
		_paint(Rect2(-38.5, z, 7.7, 0.12), "road_line")
	# Brick-red running lanes follow the footprint in the reference image.
	_paint(Rect2(-54, -70, 59, 33), "grass")
	for column in range(-106, 12):
		for row in range(-138, -74):
			var x := column * 0.5
			var z := row * 0.5
			var dx := maxf(0.0, absf(x + 24.0) - 13.0)
			var distance := Vector2(dx, z + 53.0).length()
			if distance >= 11.0 and distance <= 16.0:
				_paint(Rect2(x, z, 0.5, 0.5), "brick")
	for radius: float in [12.25, 13.55, 14.85]:
		for side: int in [-1, 1]:
			_paint(Rect2(-37, -53 + radius * side, 26, 0.1), "road_line")
			var steps := ceili(PI * radius / 0.12)
			for i in range(steps + 1):
				var a := PI * float(i) / steps - PI * 0.5
				_paint(Rect2(-24 + side * (13 + cos(a) * radius),
					-53 + sin(a) * radius, 0.20, 0.20), "road_line")
	for area in [Rect2(-44, -63, 40, 0.14), Rect2(-44, -44, 40, 0.14), Rect2(-44, -63, 0.14, 19),
			Rect2(-4, -63, 0.14, 19), Rect2(-24, -63, 0.14, 19), Rect2(-44, -58, 6, 0.14),
			Rect2(-44, -49, 6, 0.14), Rect2(-38, -58, 0.14, 9), Rect2(-10, -58, 6, 0.14),
			Rect2(-10, -49, 6, 0.14), Rect2(-10, -58, 0.14, 9)]:
		_paint(area, "road_line")
	for i in 72:
		var angle := i * TAU / 72.0
		_paint(Rect2(-24.0 + cos(angle) * 2.85, -53.5 + sin(angle) * 2.85, 0.18, 0.18), "road_line")
	# Hollow out the lower soil where the sealed basement intersects the terrain.
	for rects: Array in SchoolBasement.TUNNELS.values():
		for footprint: Rect2i in rects:
			_paint(Rect2(footprint), "", 0, 11)
	for hole: Vector2 in SchoolBasement.shafts():
		var depth := mini(SURFACE + 1, roundi((SchoolBasement.shaft_top(hole) - ORIGIN.y) * 10))
		var footprint := SchoolBasement.shaft_footprint(hole)
		_paint(Rect2(Vector2(footprint.position) * 0.1, Vector2(footprint.size) * 0.1), "", 0, depth)
		var aperture := Vector2(2, 2)
		_paint(Rect2(hole - Vector2.ONE, aperture), "", depth)
	_paint(Rect2(39, 6.3, 12.9, 7.8), "", 24)
	_paint(SchoolBasement.GARAGE_PIT, "", roundi((SchoolBasement.GARAGE_PIT_BASE - ORIGIN.y) * 10))
	_paint(SchoolBasement.ENTRANCE, "")
	for tile: Vector2i in _ground_tiles:
		var ground := level.place(_ground_tiles[tile], ORIGIN + Vector3(tile.x * 20, 0, tile.y * 20),
			"Школьный двор", Vector3i(100, SURFACE + 1, 100))
		ground.set_meta("layout_locked", true)
	_floor_guard(level)


func _floor_guard(level: SchoolLevel) -> void:
	var bottom := StaticBody3D.new()
	bottom.name = "Защитное основание школы"
	bottom.position = Vector3(0, -4.65, 0)
	bottom.collision_layer = Layers.STATIC
	bottom.collision_mask = 0
	bottom.set_meta("layout_locked", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(160, 0.5, 160)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	bottom.add_child(collider)
	level.world.add_child(bottom)


func _paint(area: Rect2, swatch: String, from_cell := 0, to_cell := SURFACE + 1) -> void:
	var start := Vector2i((area.position * 10.0).round()) + Vector2i(YARD, YARD)
	var end := Vector2i((area.end * 10.0).round()) + Vector2i(YARD, YARD)
	var stop := end - Vector2i.ONE
	for z in range(maxi(0, floori(start.y / 200.0)), mini(TILES, floori(stop.y / 200.0) + 1)):
		for x in range(maxi(0, floori(start.x / 200.0)), mini(TILES, floori(stop.x / 200.0) + 1)):
			var tile := Vector2i(x, z)
			var tile_start := tile * TILE
			var mn := (start - tile_start).max(Vector2i.ZERO)
			var mx := (end - tile_start).min(Vector2i(TILE, TILE))
			var low := from_cell if swatch.is_empty() else SURFACE
			var h := to_cell - low if swatch.is_empty() else 1
			SchoolLevel.box(_ground_tiles[tile], Vector3i(mn.x, low, mn.y),
				Vector3i(mx.x - mn.x, h, mx.y - mn.y), swatch)


static func build(level: SchoolLevel) -> void:
	_stadium(level)
	_greenhouse(level)
	_boiler(level)
	_workshop(level)
	_garage(level)
	_pool_liner(level)
	level.campus.reserve_routes()
	level.campus.furnish(level)
	_fence_and_forest(level)
	for p in [Vector3(-8, 2, 9), Vector3(8, 2, 9), Vector3(-6, 2, 29), Vector3(5, 2, 45),
			Vector3(-34, 2, 32), Vector3(34, 2, 36), Vector3(38, 2, -31), Vector3(58, 2, -32),
			Vector3(-49, 2, -39), Vector3(3, 2, -39), Vector3(2, 2, -69), Vector3(61, 2, 53)]:
		var pole := Build.lamp_post()
		var pole_object := Build.place(level.world, pole, p, true, 90.0, "Фонарь")
		var lamp := level.mount_light(pole_object, Vector3i(10, 55, 1), Color("#a6c5f0"), 2.6, 15.0)
		if p.z <= -38.0:
			level.yard_lights.append(lamp)
	var sign := Build.vol(Vector3i(72, 34, 4))
	for x in [0, 67]:
		SchoolLevel.box(sign, Vector3i(x, 0, 0), Vector3i(5, 3, 4), "concrete_dark")
		SchoolLevel.box(sign, Vector3i(x + 1, 3, 1), Vector3i(3, 31, 2), "metal_dark")
	SchoolLevel.box(sign, Vector3i(0, 18, 1), Vector3i(72, 16, 2), "metal_blue")
	VoxelFont.draw(sign, "ШКОЛА 120", Vector3i(9, 29, 3), Vector3i(1, 0, 0), VoxMat.id("sign_glow"))
	Build.place(level.world, sign, GATE + Vector3(-8.6, 0, -1), true, 0, "Школьная вывеска")


static func _puddle(parent: Node3D, at: Vector3, size: Vector2, color: Color, alpha: float) -> void:
	var shape := PlaneMesh.new()
	shape.size = size
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(color, alpha)
	surface.metallic = 0.67
	surface.roughness = 0.11
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shape.material = surface
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end = 80.0
	parent.add_child(mesh)


static func _stadium(level: SchoolLevel) -> void:
	var goal := Build.vol(Vector3i(27, 26, 76))
	for z in [0, 73]:
		SchoolLevel.box(goal, Vector3i(22, 0, z), Vector3i(3, 25, 3), "metal_white")
	SchoolLevel.box(goal, Vector3i(22, 23, 0), Vector3i(3, 3, 76), "metal_white")
	for z in range(1, 75, 5):
		SchoolLevel.box(goal, Vector3i(1, 0, z), Vector3i(1, 22, 1), "metal")
		SchoolLevel.box(goal, Vector3i(1, 23, z), Vector3i(22, 1, 1), "metal")
	for y in range(2, 24, 4):
		SchoolLevel.box(goal, Vector3i(1, y, 0), Vector3i(1, 1, 76), "metal")
	Build.place(level.world, goal, Vector3(-44.5, 2, -53.5), true, 0, "Футбольные ворота")
	Build.place(level.world, goal, Vector3(-3.5, 2, -53.5), true, 180, "Футбольные ворота")
	var stand := Build.vol(Vector3i(200, 25, 46))
	for row in 5:
		SchoolLevel.box(stand, Vector3i(0, 0, row * 8), Vector3i(200, 3 + row * 5, 8), "concrete")
		SchoolLevel.box(stand, Vector3i(0, 3 + row * 5, row * 8 + 4), Vector3i(200, 1, 3), "metal_blue")
	Build.place(level.world, stand, SchoolGrid.center("stands", 2), true, 180, "Трибуны")
	for i in 3:
		var bars := DistrictProps.climber(i)
		Build.place(level.world, bars, Vector3(-47 + i * 4, 2, -32.6), true, 90, "Полоса препятствий")
	var maze := Build.vol(Vector3i(125, 18, 65))
	for i in 7:
		var x := 5 + i * 17
		var z := 5 if i % 2 else 22
		SchoolLevel.box(maze, Vector3i(x, 0, z), Vector3i(3, 17, 38), "concrete_dark")
	Build.place(level.world, maze, SchoolGrid.center("maze", 2), true, 0, "Лабиринт")


static func _greenhouse(level: SchoolLevel) -> void:
	var v := Build.vol(Vector3i(168, 68, 176))
	SchoolLevel.box(v, Vector3i.ZERO, Vector3i(168, 2, 176), "stone")
	Build.walls(v, 0, 0, 168, 176, 2, 62, 2, "metal_teal", 4)
	for x in [0, 166]:
		for z in range(4, 172, 14):
			for y in [6, 34]:
				Build.window(v, 0, x, 2, z, y, 12, 24, "metal_teal", 1 if x else -1)
	for z in [0, 174]:
		for x in range(3, 160, 14):
			for y in [7, 35]:
				Build.window(v, 2, z, 2, x, y, 12, 23, "metal_teal", 1 if z else -1)
	Build.door(v, 2, 174, 2, 71, 2, 23, 24, "metal_teal")
	SchoolLevel.box(v, Vector3i(0, 62, 0), Vector3i(168, 2, 176), "glass")
	for x in range(0, 168, 14):
		SchoolLevel.box(v, Vector3i(x, 63, 0), Vector3i(1, 2, 176), "metal_teal")
	for z in range(0, 176, 15):
		SchoolLevel.box(v, Vector3i(0, 63, z), Vector3i(168, 2, 1), "metal_dark")
	SchoolLevel.box(v, Vector3i(4, 29, 12), Vector3i(42, 3, 150), "metal_dark")
	SchoolLevel.box(v, Vector3i(7, 29, 123), Vector3i(14, 3, 13), "")
	for z in range(16, 159, 20):
		SchoolLevel.box(v, Vector3i(45, 32, z), Vector3i(1, 10, 1), "metal_teal")
	SchoolLevel.box(v, Vector3i(45, 41, 13), Vector3i(1, 1, 149), "metal_teal")
	for x in [8, 51, 113, 149]:
		for z in [25, 57, 100, 138]:
			SchoolLevel.box(v, Vector3i(x, 2, z), Vector3i(8, 5, 19), "brick")
			SchoolLevel.box(v, Vector3i(x + 1, 6, z + 1), Vector3i(6, 1, 17), "dirt")
			_tomatoes(level, SchoolGrid.origin("greenhouse", 2.7) + Vector3((x + 4) * 0.1, 0, (z + 9) * 0.1), x + z)
	level.fixture(v, Vector3i(70, 61, 90), Vector3(26, 7.95, -56), Color("#a3c8b3"), 1.9, 12)
	level.place(v, SchoolGrid.origin("greenhouse", 2), "Теплица юннатов")


static func _tomatoes(level: SchoolLevel, at: Vector3, seed: int) -> void:
	var bush := Build.vol(Vector3i(13, 17, 20))
	for i in 4:
		var z := 2 + i * 5
		SchoolLevel.box(bush, Vector3i(6, 0, z), Vector3i(1, 15, 1), "wood_dark")
		bush.fill_ellipsoid_noise(Vector3(6, 8 + i % 2 * 3, z), Vector3(6.1, 7.0, 5.0),
			VoxMat.ids("foliage"), 0.87, 0.21, seed + i)
		for y in [4, 10]:
			SchoolLevel.box(bush, Vector3i(3 + i % 3, y, z), Vector3i(2, 2, 2), "plastic_red")
	var plant := VoxModel.instance(bush, 0.1, Vector3(6.5, 0, 10))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/school_foliage.gdshader")
	plant.material_override = mat
	plant.position = at
	plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.world.add_child(plant)
	level.greenhouse_cover.append(at + Vector3.UP * 0.55)


static func _boiler(level: SchoolLevel) -> void:
	var v := Build.vol(Vector3i(161, 61, 142))
	SchoolLevel.box(v, Vector3i.ZERO, Vector3i(161, 2, 142), "concrete")
	Build.walls(v, 0, 0, 161, 142, 2, 57, 3, "brick", 19)
	Build.door(v, 2, 139, 3, 65, 2, 31, 29, "metal_dark")
	for x in [15, 106]:
		Build.window(v, 2, 139, 3, x, 22, 28, 20, "metal_dark", 1)
	SchoolLevel.box(v, Vector3i(0, 57, 0), Vector3i(161, 4, 142), "roof_bitumen")
	SchoolLevel._shaft_hole(v, Vector3(44, 2, -60), SchoolLevel.BOILER_HATCH)
	for x in [26, 114]:
		v.fill_cylinder(Vector3(x, 3, 22), 12.0, 28, 1, VoxMat.id("metal_dark"))
		v.fill_cylinder(Vector3(x, 30, 22), 9.5, 3, 1, VoxMat.id("metal"))
		v.fill_cylinder(Vector3(x, 33, 24), 3.5, 10, 1, VoxMat.id("metal_teal"))
		SchoolLevel.box(v, Vector3i(x - 5, 12, 32), Vector3i(10, 11, 4), "metal_red")
		SchoolLevel.box(v, Vector3i(x - 4, 14, 36), Vector3i(8, 7, 1), "tank_black")
	SchoolLevel.box(v, Vector3i(14, 37, 21), Vector3i(112, 7, 6), "metal_teal")
	VoxelFont.draw(v, "КОТЕЛЬНАЯ", Vector3i(45, 45, 141), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	var stack := Build.vol(Vector3i(38, 220, 38))
	for n in range(0, 220, 10):
		stack.fill_cylinder(Vector3(19, n, 19), 15.5 - n * 0.026, 10, 1, VoxMat.id("brick" if n < 190 else "metal_dark"))
	stack.fill_cylinder(Vector3(19, 0, 19), 5.1, 220, 1, 0)
	for y in [46, 110, 169, 208]:
		stack.fill_cylinder(Vector3(19, y, 19), 16 - y * 0.027, 2, 1, VoxMat.id("metal_dark"))
	var boiler_at := SchoolGrid.origin("boiler", 2)
	var stack_at := Vector3(56.9, 2, -63.1)
	var joint := Vector3i(((stack_at - boiler_at) * 10.0).round())
	for z in range(-joint.z, stack.get_size().z):
		for y in v.get_size().y:
			for x in mini(stack.get_size().x, v.get_size().x - joint.x):
				var cell := Vector3i(x, y, z)
				if stack.get_voxel(cell) != 0:
					v.set_voxel(joint + cell, 0)
	level.fixture(v, Vector3i(80, 37, 80), Vector3(52, 5.42, -52), Color("#ffb97b"), 2.2, 11)
	level.place(v, boiler_at, "Котельная")
	level.place(stack, stack_at, "Дымовая труба", Vector3i(38, 55, 38))
	for x: float in [62.1, 65.8, 69.5]:
		var coal := Build.vol(Vector3i(34, 19, 26))
		coal.fill_ellipsoid_noise(Vector3(17, 0, 13), Vector3(17, 16, 13),
			VoxMat.ids("tank_black"), 0.91, 0.17, roundi(x))
		Build.place(level.world, coal, Vector3(x, 2, -50.6), true, 0, "Угольный склад")
	var chips := Build.vol(Vector3i(44, 12, 39))
	SchoolLevel.box(chips, Vector3i.ZERO, Vector3i(44, 1, 39), "wood_dark")
	for x in [0, 42]:
		SchoolLevel.box(chips, Vector3i(x, 1, 0), Vector3i(2, 11, 39), "wood")
	SchoolLevel.box(chips, Vector3i(0, 1, 0), Vector3i(44, 11, 2), "wood")
	chips.fill_ellipsoid_noise(Vector3(22, 0, 20), Vector3(18, 4.3, 15),
		VoxMat.ids("wood_light"), 0.9, 0.2, 74)
	SchoolLevel.box(chips, Vector3i(9, 1, 10), Vector3i(26, 11, 29), "")
	Build.place(level.world, chips, SchoolGrid.center("chips", 2.01) + Vector3.FORWARD * 0.42, true, 0, "Бункер щепы")


static func _workshop(level: SchoolLevel) -> void:
	var v := Build.vol(Vector3i(155, 55, 125))
	SchoolLevel.box(v, Vector3i.ZERO, Vector3i(155, 2, 125), "concrete")
	Build.walls(v, 0, 0, 155, 125, 2, 51, 3, "brick_tan", 33)
	Build.door(v, 2, 122, 3, 67, 2, 25, 24, "metal_dark")
	Build.door(v, 2, 0, 3, 67, 2, 25, 24, "metal_dark")
	for z in [15, 52, 90]:
		Build.window(v, 0, 0, 3, z, 14, 22, 21, "metal_teal")
		Build.window(v, 0, 152, 3, z, 14, 22, 21, "metal_teal", 1)
		SchoolRooms.workbench(v, Vector3i(10, 2, z), "saw")
		SchoolRooms.workbench(v, Vector3i(116, 2, z), "lathe")
	SchoolLevel.box(v, Vector3i(0, 51, 0), Vector3i(155, 4, 125), "roof_bitumen")
	# The line passes through the upper east wall of the workshop.
	SchoolLevel.box(v, Vector3i(152, 38, 69), Vector3i(3, 17, 22), "")
	SchoolLevel.box(v, Vector3i(65, 50, 69), Vector3i(90, 5, 22), "")
	VoxelFont.draw(v, "МАСТЕРСКИЕ", Vector3i(43, 42, 124), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	level.fixture(v, Vector3i(80, 50, 53), Vector3(50, 6.7, 39.3), Color("#ffcc9a"), 2.4, 13)
	level.place(v, SchoolGrid.origin("workshop", 2), "Отдельный корпус мастерских")
	var transformer := Build.vol(Vector3i(60, 28, 43))
	SchoolLevel.box(transformer, Vector3i.ZERO, Vector3i(60, 3, 43), "concrete")
	SchoolLevel.box(transformer, Vector3i(5, 3, 5), Vector3i(50, 17, 34), "metal_green")
	for x in [12, 28, 44]:
		transformer.fill_cylinder(Vector3(x, 20, 19), 2.8, 8, 1, VoxMat.id("metal_dark"))
	SchoolLevel.box(transformer, Vector3i(20, 8, 39), Vector3i(20, 8, 2), "metal_yellow")
	Build.place(level.world, transformer, SchoolGrid.center("transformer", 2), true, 0, "Трансформаторная")
	for z in [-37.2, -30.5]:
		Build.place(level.world, DistrictProps.chain_link(87), Vector3(66, 2, z), true, 0, "Ограда")


static func _garage(level: SchoolLevel) -> void:
	var v := Build.vol(Vector3i(150, 69, 147))
	SchoolLevel.box(v, Vector3i.ZERO, Vector3i(150, 2, 147), "concrete_dark")
	# Floor opening follows the inner dimensions of the pit lining.
	var pit_rect := SchoolBasement.GARAGE_PIT
	var pit_cells := SchoolCampus.grid_rect(pit_rect)
	var local := pit_cells.position - Vector2i(430, 590)
	SchoolLevel.box(v, Vector3i(local.x + 2, 0, local.y + 2), Vector3i(pit_cells.size.x - 4, 2, pit_cells.size.y - 4), "")
	Build.walls(v, 0, 0, 150, 147, 2, 65, 3, "brick", 66)
	Build.door(v, 2, 0, 3, 37, 2, 74, 33, "metal_dark")
	Build.door(v, 0, 0, 3, 91, 2, 16, 23, "metal_teal")
	SchoolLevel.box(v, Vector3i(0, 65, 0), Vector3i(150, 4, 147), "roof_bitumen")
	for z in [12, 28, 44]:
		SchoolRooms.locker(v, Vector3i(132, 2, z), "metal_teal")
	SchoolRooms.chair(v, Vector3i(121, 2, 105), "wood")
	VoxelFont.draw(v, "ГАРАЖ", Vector3i(94, 58, 0), Vector3i(-1, 0, 0), VoxMat.id("metal_white"))
	level.fixture(v, Vector3i(80, 64, 90), Vector3(51, 8.10, 68), Color("#f3c593"), 2.0, 12.0)
	var routes := SchoolNpcRoutes.new(v, SchoolGrid.origin("garage", 2), Rect2i(4, 4, 140, 138))
	# The parked ПАЗ and lift occupy this lane even though their voxels are separate.
	routes.block(Rect2i(41, 40, 58, 105))
	level.npc_jobs["mechanic"] = routes
	level.place(v, SchoolGrid.origin("garage", 2), "Гараж ПАЗ")
	var pit_size := SchoolCampus.grid_rect(SchoolBasement.GARAGE_PIT).size
	var pit_h := roundi((SchoolLevel.GROUND - SchoolBasement.GARAGE_PIT_BASE) * 10.0)
	var pit := Build.vol(Vector3i(pit_size.x, pit_h, pit_size.y))
	SchoolLevel.box(pit, Vector3i.ZERO, Vector3i(pit_size.x, 2, pit_size.y), "concrete_dark")
	for x in [0, pit_size.x - 2]:
		SchoolLevel.box(pit, Vector3i(x, 2, 0), Vector3i(2, pit_h - 2, pit_size.y), "concrete")
	for z in [0, pit_size.y - 2]:
		SchoolLevel.box(pit, Vector3i(2, 2, z), Vector3i(pit_size.x - 4, pit_h - 2, 2), "concrete")
	var pit_origin := SchoolBasement.GARAGE_PIT.position
	SchoolLevel.box(pit, Vector3i(1, pit_h - 7, 10), Vector3i(1, 1, 3), "lamp")
	level.fixture(pit, Vector3i(1, pit_h - 7, 11), Vector3(pit_origin.x + 0.33, 1.05, pit_origin.y + 1.15),
		Color("#ffe5b7"), 0.95, 5.5)
	level.place(pit, Vector3(pit_origin.x, SchoolBasement.GARAGE_PIT_BASE, pit_origin.y), "Смотровая яма")
	var bus := Build.vol(Vector3i(68, 30, 25))
	SchoolLevel.box(bus, Vector3i(0, 6, 0), Vector3i(68, 22, 25), "pvc")
	SchoolLevel.box(bus, Vector3i(2, 7, 2), Vector3i(64, 19, 21), "")
	for z in [0, 24]:
		SchoolLevel.box(bus, Vector3i(0, 11, z), Vector3i(68, 3, 1), "metal_teal")
		for x in range(3, 63, 8):
			SchoolLevel.box(bus, Vector3i(x, 16, z), Vector3i(6, 8, 1), "glass")
	SchoolLevel.box(bus, Vector3i(0, 17, 2), Vector3i(1, 8, 21), "glass")
	SchoolLevel.box(bus, Vector3i(67, 17, 3), Vector3i(1, 7, 19), "glass")
	for z in [4, 20]:
		bus.fill_cylinder(Vector3(0, 11, z), 1.8, 1, 0, VoxMat.id("lamp"))
	for x in [12, 54]:
		for z in [0, 22]:
			bus.fill_cylinder(Vector3(x, 4.4, z), 4.5, 3, 2, VoxMat.id("rubber"))
			bus.fill_cylinder(Vector3(x, 4.4, z), 2.0, 3, 2, VoxMat.id("metal"))
	for x in range(14, 62, 7):
		SchoolLevel.box(bus, Vector3i(x, 7, 4), Vector3i(3, 6, 5), "metal_blue")
		SchoolLevel.box(bus, Vector3i(x, 7, 16), Vector3i(3, 6, 5), "metal_blue")
	var bus_body := Build.place(level.world, bus, Vector3(50.5, 2.2, 66.4), false, -90, "Школьный автобус ПАЗ")
	VoxelVehicle.attach(bus_body, [Vector3(1.2, 0.44, 0.15), Vector3(1.2, 0.44, 2.35),
		Vector3(5.4, 0.44, 0.15), Vector3(5.4, 0.44, 2.35)], Vector3.LEFT, 0.45)


static func _pool_liner(level: SchoolLevel) -> void:
	var shell := Build.vol(Vector3i(129, 11, 78))
	SchoolLevel.box(shell, Vector3i.ZERO, Vector3i(129, 2, 78), "plaster_blue")
	for x in [0, 127]:
		SchoolLevel.box(shell, Vector3i(x, 2, 0), Vector3i(2, 9, 78), "plaster_blue")
	for z in [0, 76]:
		SchoolLevel.box(shell, Vector3i(0, 2, z), Vector3i(129, 9, 2), "plaster_blue")
	SchoolLevel.box(shell, Vector3i(10, 2, 0), Vector3i(18, 9, 2), "")
	for step in 5:
		SchoolLevel.box(shell, Vector3i(10, 2, step * 3), Vector3i(18, 9 - step * 2, 3), "plaster_blue")
	SchoolLevel._shaft_hole(shell, Vector3(39, 1.1, 6.3), SchoolTrapProps.POOL_DRAIN)
	level.place(shell, Vector3(39, 1.1, 6.3), "Чаша бассейна")
	_puddle(level.world, Vector3(45.45, 1.86, 10.2), Vector2(12.58, 7.42), Color("#437596"), 0.68)


static func _fence_and_forest(level: SchoolLevel) -> void:
	_perimeter(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12007
	var clear := level.campus.grid
	for i in 25:
		_tree(level, clear, rng, Vector3(-73.5 + i * 6.06, 2, rng.randf_range(-77.4, -76.4)), true)
	for i in 23:
		var z := -71 + i * 6.4
		_tree(level, clear, rng, Vector3(76.8, 2, z), true)
		_tree(level, clear, rng, Vector3(-73.0, 2, z), true)
	for z in range(-26, 75, 7):
		for x in [-53.2, -47.0, -34.8, 68.8]:
			if x < -40.0 and z >= -9 and z <= -4:
				continue
			_tree(level, clear, rng, Vector3(x + rng.randf_range(-0.85, 0.85), 2, z + rng.randf_range(-1.4, 1.4)), z % 3 == 0)
	for pos in [Vector3(-6.7, 2, 24), Vector3(6.5, 2, 27), Vector3(-6.5, 2, -19), Vector3(6, 2, -23),
			Vector3(-44, 2, 43), Vector3(-46, 2, 49), Vector3(7.5, 2, 46), Vector3(-8.8, 2, 47.5),
			Vector3(64, 2, 30), Vector3(67, 2, 44), Vector3(69, 2, 67), Vector3(-6, 2, -29)]:
		_tree(level, clear, rng, pos, false)
	for pos in [Vector3(-36.0, 2.08, 38.5), Vector3(-36.0, 2.08, 44.5)]:
		var car := Build.place(level.world, Build.car("metal_blue", rng.randi()), pos, false, 0, "Машина")
		VoxelVehicle.attach(car, Build.car_hubs(), Vector3.LEFT)


static func _perimeter(level: SchoolLevel) -> void:
	var half := SchoolCampus.FENCE_HALF
	var length := roundi(half * 20.0)
	for side in 4:
		var yaw := -side * PI * 0.5
		var basis := Basis(Vector3.UP, yaw)
		var corner := Vector3(-half, SchoolLevel.GROUND, -half)
		for offset in range(3, length, 120):
			var width := mini(120, length - offset)
			var panel := Build.vol(Vector3i(width, 34, 3))
			for y in [0, 1, 5, 17, 31, 33]:
				SchoolLevel.box(panel, Vector3i(0, y, 0), Vector3i(width, 1, 3), "bedrock")
			for x in range(0, width, 3):
				SchoolLevel.box(panel, Vector3i(x, 2, 1), Vector3i(1, 31, 1), "bedrock")
			for x in range(0, width, 30):
				SchoolLevel.box(panel, Vector3i(x, 0, 0), Vector3i(mini(3, width - x), 34, 3), "bedrock")
			if offset + width == length:
				SchoolLevel.box(panel, Vector3i(width - 3, 0, 0), Vector3i(3, 34, 3), "bedrock")
			var start := basis * (corner + Vector3(offset * 0.1, 0, 0))
			var fence := level.place(panel, start, "Ограда периметра", Vector3i(120, 34, 3), yaw)
			fence.set_meta("layout_locked", true)
		# The same line blocks overflight and excavation. Keep collision continuous at corners.
		var barrier := StaticBody3D.new()
		barrier.position = basis * Vector3(0, 95.0, -half + 0.15)
		barrier.rotation.y = yaw
		barrier.collision_layer = Layers.STATIC
		barrier.collision_mask = 0
		barrier.set_meta("layout_locked", true)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(half * 2.0 + 0.4, 200.0, 0.12)
		collider.shape = shape
		barrier.add_child(collider)
		level.world.add_child(barrier)


static func _tree(level: SchoolLevel, clear: SchoolGrid, rng: RandomNumberGenerator, pos: Vector3, pine: bool) -> void:
	var footprint := Rect2i(roundi(pos.x * 10) - 16, roundi(pos.z * 10) - 16, 32, 32)
	if SchoolCampus.grid_rect(SchoolBasement.ENTRANCE.grow(2.4)).intersects(footprint):
		return
	if not clear.claim(str(footprint.position), footprint):
		return
	var tree := Build.pine_tree(rng.randi(), rng.randi_range(66, 119), rng.randi_range(11, 18)) if pine else DistrictProps.linden(rng.randi())
	Build.place(level.world, tree, pos, true, rng.randf_range(0, 360), "Сосна" if pine else "Липа")


static func underground_props(level: SchoolLevel) -> void:
	var range_parts := Build.vol(Vector3i(496, 29, 55))
	for x in [15, 114, 214, 314, 414, 490]:
		for z in [5, 25, 44]:
			SchoolLevel.box(range_parts, Vector3i(x, 2, z), Vector3i(3, 22, 8), "wood_dark")
			SchoolLevel.box(range_parts, Vector3i(x - 1, 9, z + 1), Vector3i(1, 11, 6), "pvc")
			SchoolLevel.box(range_parts, Vector3i(x - 2, 13, z + 3), Vector3i(1, 4, 2), "metal_red")
	VoxelFont.draw(range_parts, "50 МЕТРОВ", Vector3i(12, 25, 0), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	level.place(range_parts, Vector3(3.1, SchoolLevel.BASEMENT, -9.8), "Тир ОБЖ")
	var store := Build.vol(Vector3i(110, 24, 35))
	for i in 6:
		var x := 5 + i * 16
		SchoolRooms.shelf(store, Vector3i(x, 0, 2), 14, 19, i)
		SchoolLevel.box(store, Vector3i(x + 3, 2, 19), Vector3i(9, 6, 9), "metal_green")
		SchoolLevel.box(store, Vector3i(x + 6, 10, 16), Vector3i(2, 5, 2), "tank_black")
		SchoolLevel.box(store, Vector3i(x + 4, 13, 17), Vector3i(5, 2, 2), "metal_dark")
	level.place(store, Vector3(-26, -3.7, -9.8), "Склад ОБЖ")
	for z in [-28, -40, -52]:
		_puddle(level.world, Vector3(-15, -3.46, z), Vector2(4.7, 11.9), Color("#2d4b58"), 0.72)
	for section: Vector2i in [Vector2i(-52, 13), Vector2i(-39, 14), Vector2i(-25, 13)]:
		var length := section.y * 10
		var pipe := Build.vol(Vector3i(6, 22, length))
		pipe.fill_cylinder(Vector3(3, 18, 0), 2.5, length, 2, VoxMat.id("metal_teal"))
		for z in range(14, length - 6, 46):
			SchoolLevel.box(pipe, Vector3i(0, 0, z), Vector3i(6, 2, 8), "metal_dark")
			SchoolLevel.box(pipe, Vector3i(1, 2, z + 2), Vector3i(4, 15, 4), "metal_dark")
			pipe.fill_cylinder(Vector3(3, 18, z + 3), 3.0, 3, 2, VoxMat.id("metal"))
		level.place(pipe, Vector3(48.2, -3.7, section.x), "Теплотрасса")
