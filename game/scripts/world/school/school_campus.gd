class_name SchoolCampus
extends RefCounted

const APPROACH := Rect2(-5.6, 12.4, 11.2, 40.0)
const BUS_STOP := Vector2(-16.9, 70.3)
const BUS_STOP_WALK := Rect2(-23.4, 64.8, 6.5, 1.7)
const ROADS := [
	Rect2(-65, 51, 144, 10), Rect2(-66, -74, 9, 125),
	Rect2(58, -46, 5, 97), Rect2(34, 35, 26, 6), Rect2(47, 40, 6, 19),
]
const WALKS := [
	APPROACH, Rect2(-17, 14, 34, 9), Rect2(-40, 31, 99, 3.5),
	Rect2(-57, 1.2, 16, 4.8), Rect2(-32.0, 1.0, 3.0, 5.2), Rect2(-44, -29, 3, 81), Rect2(-41.0, -11.2, 12.0, 3.0), Rect2(5.6, 13.2, 4.4, 3.5), Rect2(-56, -36, 113, 4),
	Rect2(30, -50, 5, 47), Rect2(33, -49.5, 18, 3.2), Rect2(60, -60, 7, 14),
	Rect2(-5, -37, 10, 31), Rect2(-33, 41, 4, 3.3), Rect2(-11, 41, 42, 3.3), Rect2(31, 20, 27, 4.5),
	Rect2(33, 22, 4, 29), Rect2(64, -30, 4, 81), Rect2(64, 18, 8, 3.2), Rect2(68, 21.2, 9.1, 2.2),
	Rect2(-55, 62, 126, 2.8), BUS_STOP_WALK, Rect2(-3, 60, 6, 16), Rect2(-35, 44, 3.2, 7),
	Rect2(-54, -44, 3.1, 12), Rect2(5, -68, 3.4, 36), Rect2(8, -65, 11, 3),
	Rect2(36, -74, 4.2, 40), Rect2(8, -73, 29, 3), Rect2(-54, -74, 59, 2.4),
]
const GARDEN_GATE := Vector3(-19.0, 2.0, 39.0)
const DECOY := Vector3(16.0, 2.0, -55.5)
const EXTRA_WALKS := [
	Rect2(-29, 35, 3, 16), Rect2(-29, 47, 18, 3), Rect2(-14, 34.5, 3, 15.5),
	Rect2(-26, 38, 15, 2), Rect2(-40, 24, 11, 2.5),
	Rect2(37, -69, 25, 2.5), Rect2(59.5, -69, 2.5, 9),
	Rect2(10, -58, 10, 2.5), Rect2(12, -57, 2.5, 9),
	Rect2(-14, 64.8, 2.5, 10), Rect2(30, 63, 12, 2.5),
	Rect2(39.5, 61, 2.5, 12), Rect2(5, 45, 26, 2.5),
]
const PADS := {
	"Сад библиотеки": Rect2(-29, 35, 18, 15),
	"Тихий двор юннатов": Rect2(40.5, -73, 18, 5.5),
	"Настольный теннис": Rect2(-11, 66, 7, 9),
	"Восточная беседка": Rect2(33, 65.5, 6, 6),
	"Летний класс": Rect2(-37.9, 11, 7.6, 12.0),
	"Спортивный карман": Rect2(-53.5, -22.5, 8.6, 15.0),
	"Сквер": Rect2(7.5, 25, 10, 14),
	"Учебный полигон": Rect2(9.5, 65.6, 20.4, 10.3),
	"Остановка": Rect2(-27, 66, 12, 6.4),
	"Служебный двор": Rect2(68.5, 23, 7.7, 20),
	"Лесная беседка": Rect2(10.5, -52, 7.1, 12),
}
const GATE := Vector3(22.9, 2.0, 64.75)
const DRILL := Vector3(14.9, 2.0, 68.1)
const DUCT_STANDS := [-37.5, -15.0, 7.0, 29.0]
const SHUTTER := Vector3(71.9, 2.0, 28.1)
const FENCE_HALF := 78.7

var grid := SchoolGrid.new(Rect2i(-795, -795, 1590, 1590))
var skipped := PackedStringArray()
var props := 0
var placed_objects := {}


static func grid_rect(rect: Rect2) -> Rect2i:
	return Rect2i(Vector2i((rect.position * 10).round()), Vector2i((rect.size * 10).round()))


func reserve_routes() -> void:
	for key: String in SchoolGrid.SITES:
		grid.protect(key, SchoolGrid.SITES[key])
	for i in WALKS.size():
		grid.protect("walk/%d" % i, grid_rect(WALKS[i]))
	for i in EXTRA_WALKS.size():
		grid.protect("extra_walk/%d" % i, grid_rect(EXTRA_WALKS[i]))
	for i in ROADS.size():
		grid.protect("road/%d" % i, grid_rect(ROADS[i]))
	grid.protect("Садовая ширма и пульты", grid_rect(Rect2(-23, 37.5, 8, 3)))
	grid.protect("Звонок юннатов", grid_rect(Rect2(15.4, -56.1, 1.2, 1.2)))
	grid.protect("Крытая лестница", grid_rect(SchoolBasement.ENTRANCE))
	grid.protect("Парковка", grid_rect(Rect2(-40, 35, 8, 15)))
	for z: float in DUCT_STANDS:
		grid.protect("Опора трубы " + str(z), grid_rect(Rect2(63.0, z - 0.3, 0.7, 0.6)))
	grid.protect("Полоса препятствий", grid_rect(Rect2(-49, -35, 12, 6)))
	grid.protect("Уголь", grid_rect(Rect2(60, -52, 12, 4)))
	grid.protect("Полигон, ворота", grid_rect(Rect2(19.8, 63.6, 6.3, 2.3)))
	grid.protect("Ограда полигона, запад", grid_rect(Rect2(9.55, 64.85, 11.05, 0.35)))
	grid.protect("Ограда полигона, восток", grid_rect(Rect2(25.2, 64.85, 4.7, 0.35)))
	grid.protect("Полигон, пульт", grid_rect(Rect2(14.5, 67.7, 0.8, 0.9)))
	grid.protect("Заслонка и пульты", grid_rect(Rect2(70.8, 25.1, 2.2, 6.0)))
	grid.protect("Ограда техдвора", grid_rect(Rect2(71.65, 22.5, 0.7, 9.1)))
	for sign_value: int in [-1, 1]:
		var edge := sign_value * FENCE_HALF
		grid.protect("Граница X %d" % sign_value, grid_rect(Rect2(edge - 0.3, -FENCE_HALF, 0.6, 2.0 * FENCE_HALF)))
		grid.protect("Граница Z %d" % sign_value, grid_rect(Rect2(-FENCE_HALF, edge - 0.3, 2.0 * FENCE_HALF, 0.6)))


func _place(level: SchoolLevel, key: String, volume: VoxelVolume, point: Vector2, yaw := 0.0, front_clearance := 0, height := SchoolLevel.GROUND) -> bool:
	var size := volume.get_size() + Vector3i(0, 0, front_clearance)
	var rotated := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * AABB(Vector3.ZERO, Vector3(size))
	var offset := Vector2i(roundi(rotated.position.x), roundi(rotated.position.z))
	var footprint := Rect2i(Vector2i((point * 10.0).round()) + offset,
		Vector2i(roundi(rotated.size.x), roundi(rotated.size.z)))
	if not grid.claim(key, footprint):
		var shifted := _nearby(key, footprint)
		if not shifted.has_area():
			var blocked_by := PackedStringArray()
			for name: String in grid.placements:
				if footprint.intersects(grid.placements[name]):
					blocked_by.append(name)
			skipped.append("%s (%s)" % [key, ", ".join(blocked_by)])
			return false
		footprint = shifted
	var pivot := footprint.position - offset
	var origin := Vector3(pivot.x * 0.1, height, pivot.y * 0.1)
	if height > SchoolLevel.GROUND:
		var support_size := volume.get_size()
		support_size.y = roundi((height - SchoolLevel.GROUND) * 10.0)
		var support := Build.vol(support_size)
		SchoolLevel.box(support, Vector3i.ZERO, support_size, "concrete")
		level.place(support, Vector3(origin.x, SchoolLevel.GROUND, origin.z), "Основание поста", support_size, yaw)
	placed_objects[key] = level.place(volume, origin, key, Vector3i(48, 36, 48), yaw)
	props += 1
	return true


func _nearby(key: String, area: Rect2i) -> Rect2i:
	# Search outwards in half-meter steps, bounded to this part of the yard.
	for distance in range(1, 9):
		for x in range(-distance, distance + 1):
			var z := distance - absi(x)
			for sign_z in [1, -1]:
				if z == 0 and sign_z < 0:
					continue
				var candidate := Rect2i(area.position + Vector2i(x, z * sign_z) * 5, area.size)
				if grid.claim(key, candidate):
					return candidate
	return Rect2i()


func furnish(level: SchoolLevel) -> void:
	_place(level, "Летний класс", _shelter("ЛЕТНИЙ КЛАСС", "metal_teal"), Vector2(-37.9, 15.2))
	_place(level, "Остановка", _shelter("ШКОЛЬНАЯ", "metal_blue"), BUS_STOP, PI)
	_place(level, "Лесная беседка", _shelter("ЮННАТЫ", "metal_green"), Vector2(11.0, -49.0))
	_place(level, "Навес с учебным оборудованием", _shelter("ПОСТ 02", "metal_red"), Vector2(17.9, 73.0), -PI, 0, 2.2)
	_place(level, "Зона отработки эвакуации", _drill_wall(), Vector2(23.5, 69.5))
	_place(level, "Турники спортивного дворика", _sports(), Vector2(-51.8, -21.3))
	_place(level, "Хозяйственный навес", _service_shelter(), Vector2(68.9, 29.4))
	_place(level, "Площадка для отдыха", _tables(), Vector2(10.1, 35.7))
	_place(level, "Клумба у главного входа", _planter(34, 14, 32), Vector2(-9.45, 10.9))
	_place(level, "Клумба у библиотеки", _planter(34, 16, 16), Vector2(6.05, 10.75))
	_place(level, "Цветник вдоль корпуса А", _planter(17, 27, 54), Vector2(-32.4, 7.2))
	_place(level, "Сад учебных грядок", _planter(45, 52, 71), Vector2(12.5, -44.2))
	_place(level, "Клумба во внутреннем дворе", _planter(42, 31, 18), Vector2(5.4, -19.3))
	_place(level, "Велопарковка", _bike_rack(), Vector2(-11.0, 24.8))
	_place(level, "Велопарковка спорткорпуса", _bike_rack(), Vector2(48.4, 26.2))
	for i in 6:
		_place(level, "Секция полосы укрытий %d" % (i + 1), _hedge(i), Vector2(-51.8 + (i % 2) * 4.4, -14.0 + (i / 2) * 3.4))
	for i in 5:
		_place(level, "Контейнер техдвора %d" % (i + 1), _container(i), Vector2(68.5 + (i % 2) * 2.25, 33.0 + (i / 2) * 2.5))
	_place(level, "Сквер, западный откос", _berm(67, 32, 136), Vector2(-29.8, 66.5))
	_place(level, "Сквер, восточный откос", _berm(86, 43, 381), Vector2(30.5, 74.8))
	_place(level, "Вал у котельной", _berm(94, 34, 212), Vector2(46.9, -69.5))
	_place(level, "Насыпь у учебного двора", _berm(59, 37, 228), Vector2(73.3, 8.6))
	for i in 9:
		var positions := [Vector2(-36.6, 9.0), Vector2(-9.2, 26.7), Vector2(6.5, 24.8),
			Vector2(-36.4, -13.0), Vector2(25.5, 35.5), Vector2(53.1, -30.4),
			Vector2(8.9, -61.8), Vector2(-8.6, 45.8), Vector2(28.8, 66.4)]
		_place(level, "Скамья %d" % (i + 1), _bench(), positions[i])
	for data in [[Vector2(-53.1, -29.3), "СТАДИОН"], [Vector2(-48.2, 6.4), "УБЕЖИЩЕ"],
			[Vector2(35.2, 44.9), "ГАРАЖ"],
			[Vector2(40.5, -43.9), "ТЕПЛИЦА"], [Vector2(41.5, -32.0), "КОТЕЛЬНАЯ"]]:
		_place(level, "Указатель " + data[1], _sign(data[1]), data[0])
	_enrich(level)
	var lamp_number := 0
	for p: Vector3 in [Vector3(-9.2, 2, 12), Vector3(8.8, 2, 12), Vector3(-35.6, 2, 16),
			Vector3(-49.4, 2, -24), Vector3(31.4, 2, 28), Vector3(10.5, 2, 66),
			Vector3(27.8, 2, 73), Vector3(BUS_STOP.x - 5.4, 2, BUS_STOP.y - 2.3), Vector3(68.9, 2, 26), Vector3(13.1, 2, -47)]:
		var post := Build.vol(Vector3i(6, 33, 6))
		SchoolLevel.box(post, Vector3i.ZERO, Vector3i(6, 2, 6), "concrete")
		SchoolLevel.box(post, Vector3i(2, 2, 2), Vector3i(2, 29, 2), "metal_dark")
		SchoolLevel.box(post, Vector3i(1, 30, 0), Vector3i(4, 1, 6), "lamp")
		SchoolLevel.box(post, Vector3i(0, 31, 0), Vector3i(6, 2, 6), "metal_teal")
		lamp_number += 1
		var name := "Фонарь пешеходной дорожки %d" % lamp_number
		if _place(level, name, post, Vector2(p.x - 0.3, p.z - 0.3)):
			level.mount_light(placed_objects[name], Vector3i(3, 30, 2), Color("#ffd6a5"), 1.65, 10.4)


func _enrich(level: SchoolLevel) -> void:
	for data in [
		["Пергола у библиотеки", Vector2(-25.8, 42.2)],
		["Беседка восточного сада", Vector2(33.2, 66.2)],
		["Зелёный проход юннатов", Vector2(40.8, -72.5)]]:
		_place(level, data[0], SchoolDetails.pergola(), data[1])
	for i in 6:
		var points := [Vector2(-25.2, 34.6), Vector2(-18.4, 43.5), Vector2(48, -72.3),
			Vector2(53, -72.3), Vector2(17, 47.6), Vector2(-37.6, 20.0)]
		_place(level, "Стол отдыха %d" % i, SchoolDetails.picnic(), points[i])
	for i in 2:
		_place(level, "Теннисный стол %d" % i, SchoolDetails.table_tennis(), Vector2(-10.2, 67 + i * 4.2))
	for i in 4:
		_place(level, "Садовая тележка %d" % i, SchoolDetails.trolley(),
			[Vector2(17, -60), Vector2(39, -58), Vector2(65.5, -58), Vector2(38, 42)][i])
	for i in 8:
		_place(level, "Урна %d" % i, SchoolDetails.bin(),
			[Vector2(-8, 28), Vector2(8, 28), Vector2(-31, 23), Vector2(-46, -24),
			Vector2(-17, 71), Vector2(32, 44), Vector2(38, -42), Vector2(60, 64)][i])
	for i in 9:
		_place(level, "Дерево в кадке %d" % i, SchoolDetails.planter_tree(800 + i),
			[Vector2(-17, 41), Vector2(-17, 35), Vector2(8.5, 48.5), Vector2(26, 48),
			Vector2(33, 70.6), Vector2(53, -66), Vector2(40, -65), Vector2(-52, 24), Vector2(-51, 40)][i])
	for i in 4:
		_place(level, "Велосипед %d" % i, SchoolDetails.bicycle(), Vector2(-11.0 + i * 0.8, 26.0), PI * 0.5)
	for i in 4:
		var key := "Шкаф уличного инвентаря %d" % i
		var at: Vector2 = [Vector2(-36.5, 13.0), Vector2(15, -51.5), Vector2(68.7, 39.5), Vector2(62.6, 69.4)][i]
		if _place(level, key, SchoolDetails.equipment_cabinet(), at, -PI if i == 3 else 0.0, 13):
			var body: VoxelObject = placed_objects[key]
			level.hide_spots.append({"bath": false, "school": true, "building": body,
				"panel": Vector3(5, 3, 13.1), "center": Vector3(10, 2.55, 7),
				"front": Vector3(10, 2, 21)})
	_place(level, "Указатель ТЕННИС", _sign("ТЕННИС"), Vector2(-4.4, 75.8), -PI, 0, 2.0)
	_place(level, "Указатель ЮННАТЫ", _sign("ЮННАТЫ"), Vector2(10, -59.1))
	for i in 6:
		_place(level, "Низкая изгородь сада %d" % i, _hedge(i), [Vector2(-52, 26), Vector2(-52, 30), Vector2(-52, 34), Vector2(20, 48), Vector2(24, 48), Vector2(28, 48)][i])


static func _shelter(title: String, trim: String) -> VoxelVolume:
	var v := Build.vol(Vector3i(65, 36, 38))
	SchoolLevel.box(v, Vector3i(0, 0, 0), Vector3i(65, 2, 38), "stone")
	for x in [1, 61]:
		for z in [2, 34]:
			SchoolLevel.box(v, Vector3i(x, 2, z), Vector3i(3, 32, 3), trim)
	SchoolLevel.box(v, Vector3i(0, 32, 0), Vector3i(65, 2, 38), trim)
	SchoolLevel.box(v, Vector3i(1, 34, 1), Vector3i(63, 2, 36), "roof_bitumen")
	SchoolLevel.box(v, Vector3i(2, 2, 2), Vector3i(61, 12, 2), "brick_tan")
	for x in range(5, 60, 5):
		SchoolLevel.box(v, Vector3i(x, 14, 2), Vector3i(1, 18, 1), trim)
	SchoolLevel.box(v, Vector3i(7, 5, 5), Vector3i(50, 1, 5), "wood")
	for x in [10, 32, 55]:
		SchoolLevel.box(v, Vector3i(x, 2, 6), Vector3i(2, 3, 3), "metal_dark")
	SchoolLevel.box(v, Vector3i(2, 24, 36), Vector3i(57, 8, 1), trim)
	VoxelFont.draw(v, title, Vector3i(6, 30, 37), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	SchoolLevel.box(v, Vector3i(23, 31, 17), Vector3i(18, 1, 3), "lamp")
	return v


static func _planter(width: int, depth: int, seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(width, 13, depth))
	SchoolLevel.box(v, Vector3i.ZERO, Vector3i(width, 4, depth), "brick_tan")
	SchoolLevel.box(v, Vector3i(2, 3, 2), Vector3i(width - 4, 1, depth - 4), "dirt")
	for z in range(3, depth - 2, 4):
		for x in range(3, width - 2, 4):
			var n := (seed + x * 7 + z * 11) % 9
			SchoolLevel.box(v, Vector3i(x, 4, z), Vector3i(2, 2 + n / 2, 2), "birch_leaf" if n % 2 == 0 else "leaf_dark")
			if n % 3 == 1:
				SchoolLevel.box(v, Vector3i(x, 6 + n / 2, z), Vector3i(1, 1, 1), "metal_yellow" if n > 3 else "curtain_red")
	return v


static func _sports() -> VoxelVolume:
	var v := Build.vol(Vector3i(57, 33, 37))
	SchoolLevel.box(v, Vector3i.ZERO, Vector3i(57, 1, 37), "rubber")
	for x in [3, 25, 51]:
		for z in [4, 32]:
			SchoolLevel.box(v, Vector3i(x, 1, z), Vector3i(3, 29, 3), "metal_blue")
	for x in [5, 27, 51]:
		for z in range(6, 34, 6):
			SchoolLevel.box(v, Vector3i(x, 28, z), Vector3i(2, 2, 2), "metal_yellow")
	SchoolLevel.box(v, Vector3i(4, 28, 4), Vector3i(49, 2, 2), "metal_dark")
	SchoolLevel.box(v, Vector3i(4, 28, 32), Vector3i(49, 2, 2), "metal_dark")
	for x in [4, 51]:
		SchoolLevel.box(v, Vector3i(x, 27, 4), Vector3i(2, 2, 29), "metal_yellow")
	return v


static func _drill_wall() -> VoxelVolume:
	var v := Build.vol(Vector3i(45, 23, 44))
	for z in [1, 38]:
		SchoolLevel.box(v, Vector3i(0, 0, z), Vector3i(43, 20, 3), "wood_dark")
		for x in range(1, 43, 7):
			SchoolLevel.box(v, Vector3i(x, 0, z), Vector3i(1, 21, 3), "wood_light")
	for x in [1, 40]:
		SchoolLevel.box(v, Vector3i(x, 0, 2), Vector3i(3, 15, 12), "concrete_dark")
		SchoolLevel.box(v, Vector3i(x, 0, 28), Vector3i(3, 15, 11), "concrete_dark")
	return v


static func _service_shelter() -> VoxelVolume:
	var v := _shelter("ТЕХНИКА", "metal_teal")
	SchoolLevel.box(v, Vector3i(4, 2, 3), Vector3i(55, 15, 4), "metal_dark")
	for x in [10, 42]:
		SchoolLevel.box(v, Vector3i(x, 2, 7), Vector3i(8, 12, 11), "metal")
	return v


static func _tables() -> VoxelVolume:
	var v := Build.vol(Vector3i(50, 12, 42))
	for z in [4, 26]:
		SchoolRooms.desk(v, Vector3i(4, 0, z), 13, 9, "wood", 8)
		SchoolRooms.desk(v, Vector3i(30, 0, z), 13, 9, "wood", 8)
		for x in [6, 32]:
			for i in 4:
				for j in 4:
					SchoolLevel.box(v, Vector3i(x + i, 8, z + j + 2), Vector3i(1, 1, 1),
						"concrete_dark" if (i + j) % 2 else "concrete")
	return v


static func _bike_rack() -> VoxelVolume:
	var v := Build.vol(Vector3i(36, 13, 10))
	SchoolLevel.box(v, Vector3i(0, 0, 0), Vector3i(36, 1, 10), "stone")
	for x in [3, 11, 19, 27, 34]:
		for z in [1, 8]:
			SchoolLevel.box(v, Vector3i(x, 1, z), Vector3i(1, 10, 1), "metal_teal")
		SchoolLevel.box(v, Vector3i(x, 10, 1), Vector3i(1, 2, 8), "metal")
	return v


static func _hedge(i: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(28, 16, 14))
	SchoolLevel.box(v, Vector3i(0, 0, 0), Vector3i(28, 2, 14), "brick_tan")
	v.fill_ellipsoid_noise(Vector3(14, 6, 7), Vector3(15, 10, 7), VoxMat.ids("leaf_dark"), 0.96, 0.19, i + 48)
	v.fill_ellipsoid_noise(Vector3(13, 9, 7), Vector3(12, 6, 7), VoxMat.ids("birch_leaf"), 0.7, 0.21, i + 42)
	return v


static func _container(i: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(15, 13, 16))
	SchoolLevel.box(v, Vector3i(1, 0, 0), Vector3i(13, 2, 15), "wood_dark")
	SchoolLevel.box(v, Vector3i(0, 2, 1), Vector3i(15, 10, 15), "metal_green" if i % 2 else "metal_blue")
	for x in [0, 4, 10, 14]:
		SchoolLevel.box(v, Vector3i(x, 2, 0), Vector3i(1, 11, 16), "metal_dark")
	return v


static func _berm(w: int, d: int, seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(w, 10, d))
	v.fill_ellipsoid_noise(Vector3(w * 0.5, 0, d * 0.5), Vector3(w * 0.52, 7, d * 0.57),
		VoxMat.ids("grass"), 1.01, 0.17, seed)
	for n in 5:
		var x := roundi(w * (0.2 + 0.15 * n))
		var z := d / 2 + n % 2 * 3
		SchoolLevel.box(v, Vector3i(x, 5, z), Vector3i(3, 3, 3), "foliage")
	return v


static func _bench() -> VoxelVolume:
	var v := Build.vol(Vector3i(25, 12, 8))
	for x in [2, 21]:
		SchoolLevel.box(v, Vector3i(x, 0, 1), Vector3i(2, 5, 6), "metal_dark")
		SchoolLevel.box(v, Vector3i(x, 4, 0), Vector3i(2, 8, 2), "metal_dark")
	for z in [1, 3, 5]:
		SchoolLevel.box(v, Vector3i(0, 5, z), Vector3i(25, 1, 2), "wood_light")
	for y in [7, 10]:
		SchoolLevel.box(v, Vector3i(0, y, 0), Vector3i(25, 2, 1), "wood")
	return v


static func _sign(title: String) -> VoxelVolume:
	var width := VoxelFont.text_width(title) + 6
	var v := Build.vol(Vector3i(width, 24, 3))
	for x in [1, width - 3]:
		SchoolLevel.box(v, Vector3i(x, 0, 0), Vector3i(2, 24, 2), "metal_dark")
	SchoolLevel.box(v, Vector3i(0, 15, 0), Vector3i(width, 9, 2), "metal_teal")
	VoxelFont.draw(v, title, Vector3i(3, 21, 2), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	return v
