class_name SchoolTrapProps
extends RefCounted

const POOL_DRAIN := Vector2(44.4, 9.4)
const FIELD_HATCH := Vector2(-24, -54)
const GARAGE_PIT := Vector2(50.5, 66.4)
const MODES := {
	"cement": ["shot", Vector3(-26.4, -3.7, 12.3), ""],
	"air": ["shot", Vector3(33.2, -3.7, -10.8), ""],
	"gas": ["shot", Vector3(27.1, 2.2, -25.4), ""],
	"saw": ["use", Vector3(-14.4, 2.2, -8.7), "Включить циркулярную пилу"],
	"tools": ["use", Vector3(26.8, 2.2, -18.8), "Взять тяжёлый инструмент"],
	"medkit": ["use", Vector3(14.3, 2.2, 27.1), "Воспользоваться аптечкой"],
	"steam": ["use", Vector3(53.3, 2.2, -9.2), "Сбросить пар из котла"],
	"dishes": ["shot", Vector3(46.8, 3.0, -2.0), ""],
	"springboard": ["use", Vector3(48.2, 2.2, 15.5), "Прыгнуть с трамплина"],
	"tesla": ["use", Vector3(-26.4, 6.0, -12.5), "Подать напряжение на катушку"],
	"picture": ["use", Vector3(-25.4, 6.0, 28.7), "Откинуть картину"],
	"safe": ["use", Vector3(-25.4, 6.0, 29.17), "Открыть сейф директора"],
	"director_key": ["use", Vector3(-25.4, 7.49, 28.94), "Забрать ключ ПАЗа и щитовой"],
	"phone": ["use", Vector3(-24.5, 6.0, 21.8), "Позвонить на пост охраны"],
	"spotlight": ["shot", Vector3(47.2, 12.4, 12.8), ""],
	"fixer": ["both", Vector3(-13.9, 13.6, -11.6), "Бросить склянку с фиксажем"],
	"reel": ["shot", Vector3(42.6, 14.4, 2.2), ""],
	"coal": ["use", Vector3(62.1, 2.08, -49.35), "Затаиться в угле"],
	"mains": ["both", Vector3(70.2, 2.0, -33.9), "Переключить питание школы"],
	"guard_key": ["use", Vector3(-7.9, 3.0, 2.34), "Забрать ключ от люка"],
	"fan": ["use", Vector3(-15.2, 6.0, -9.2), "Подняться по вытяжке на третий этаж"],
	"wheel": ["use", Vector3(-11.8, -3.7, 2.3), "Повернуть колесо гардероба"],
	"microphone": ["use", Vector3(-25.1, 9.8, 12.9), "Школьное радио · удерживай V для эфира"],
	"loose_tile": ["use", Vector3(-24.35, 18.51, 27.9), ""],
	"garage_lift": ["use", Vector3(47.7, 2.2, 66.1), "Переключить гаражный подъёмник"],
}


static func room_clearances(side: int, floor: int, col: int, kind: String) -> Array[Rect2i]:
	var list: Array[Rect2i] = []
	for key: String in MODES:
		var at: Vector3 = MODES[key][1]
		var zone := SchoolGrid.origin("west" if side == 0 else "east", 2.0 + floor * 3.8)
		if absf(at.y - zone.y - 0.2) > 0.24:
			continue
		if kind == "chem" or (kind == "photo" and col == 1):
			continue
		var x := roundi((at.x - zone.x) * 10.0)
		var z := roundi((at.z - zone.z) * 10.0)
		if (col == 0 and x >= 67) or (col == 1 and x < 123):
			continue
		list.append(Rect2i(x - 14, z - 13, 28, 31))
	if kind == "photo" and side == 0 and floor == 3:
		list.append(Rect2i(138, 161, 29, 34))
	return list


static func b(v: VoxelVolume, a: Vector3i, d: Vector3i, mat: String) -> void:
	SchoolLevel.box(v, a, d, mat)


static func volume(key: String) -> VoxelVolume:
	match key:
		"cement":
			var v := Build.vol(Vector3i(12, 10, 9))
			b(v, Vector3i(1, 0, 1), Vector3i(10, 4, 7), "curtain_beige")
			b(v, Vector3i(0, 2, 2), Vector3i(12, 4, 5), "wood_light")
			b(v, Vector3i(2, 5, 1), Vector3i(8, 3, 7), "curtain_beige")
			b(v, Vector3i(4, 2, 8), Vector3i(4, 3, 1), "plaster")
			return v
		"air", "gas":
			var v := Build.vol(Vector3i(8, 17, 8))
			var coat := "metal_blue" if key == "air" else "metal_red"
			v.fill_cylinder(Vector3(4, 0, 4), 3.5, 3, 1, VoxMat.id("metal_dark"))
			v.fill_cylinder(Vector3(4, 2, 4), 3.4, 11, 1, VoxMat.id(coat))
			v.fill_cylinder(Vector3(4, 13, 4), 2.5, 2, 1, VoxMat.id(coat))
			b(v, Vector3i(3, 15, 3), Vector3i(2, 2, 2), "metal_yellow")
			b(v, Vector3i(3, 7, 7), Vector3i(2, 3, 1), "pvc")
			return v
		"saw":
			var v := Build.vol(Vector3i(21, 16, 13))
			SchoolRooms.workbench(v, Vector3i.ZERO, "saw")
			b(v, Vector3i(2, 8, 11), Vector3i(4, 3, 2), "metal_yellow")
			b(v, Vector3i(3, 9, 12), Vector3i(1, 1, 1), "metal_red")
			return v
		"tools":
			var v := Build.vol(Vector3i(15, 18, 10))
			b(v, Vector3i.ZERO, Vector3i(15, 8, 10), "metal_blue")
			b(v, Vector3i(1, 8, 1), Vector3i(13, 1, 8), "wood_dark")
			for y in [2, 5]:
				b(v, Vector3i(4, y, 9), Vector3i(7, 1, 1), "metal")
			for x in [3, 8]:
				b(v, Vector3i(x, 9, 2), Vector3i(1, 7, 1), "wood_light")
				b(v, Vector3i(x - 1, 15, 1), Vector3i(3, 2, 3), "metal_dark")
			return v
		"medkit":
			var v := Build.vol(Vector3i(13, 15, 9))
			b(v, Vector3i.ZERO, Vector3i(13, 8, 9), "wood_dark")
			b(v, Vector3i(1, 8, 1), Vector3i(11, 6, 7), "pvc")
			b(v, Vector3i(5, 9, 8), Vector3i(2, 4, 1), "metal_red")
			b(v, Vector3i(4, 10, 8), Vector3i(4, 2, 1), "metal_red")
			b(v, Vector3i(4, 14, 3), Vector3i(5, 1, 2), "metal_dark")
			return v
		"steam":
			var v := Build.vol(Vector3i(15, 15, 13))
			v.fill_cylinder(Vector3(7, 1, 6), 5.7, 9, 1, VoxMat.id("metal_dark"))
			v.fill_cylinder(Vector3(7, 10, 6), 5.8, 2, 1, VoxMat.id("metal"))
			b(v, Vector3i(5, 12, 5), Vector3i(5, 2, 3), "metal_dark")
			b(v, Vector3i(5, 7, 11), Vector3i(5, 2, 2), "metal_red")
			return v
		"dishes":
			var v := Build.vol(Vector3i(12, 6, 10))
			b(v, Vector3i.ZERO, Vector3i(12, 1, 10), "metal_teal")
			for i in 5:
				v.fill_cylinder(Vector3(4 + i % 2, 1 + i, 4), 3.4, 1, 1, VoxMat.id("pvc"))
			return v
		"springboard":
			var v := Build.vol(Vector3i(13, 15, 34))
			for z in [5, 25]:
				b(v, Vector3i(2, 0, z), Vector3i(2, 12, 2), "metal_dark")
				b(v, Vector3i(9, 0, z), Vector3i(2, 12, 2), "metal_dark")
			b(v, Vector3i(1, 12, 1), Vector3i(11, 2, 32), "metal_teal")
			for z in range(2, 31, 3):
				b(v, Vector3i(2, 14, z), Vector3i(9, 1, 1), "pvc")
			return v
		"tesla":
			var v := Build.vol(Vector3i(16, 23, 13))
			b(v, Vector3i.ZERO, Vector3i(16, 5, 13), "metal_dark")
			b(v, Vector3i(2, 1, 12), Vector3i(3, 3, 1), "metal_red")
			v.fill_cylinder(Vector3(8, 5, 6), 3.5, 13, 1, VoxMat.id("wood_dark"))
			for y in range(5, 17, 2):
				v.fill_cylinder(Vector3(8, y, 6), 4.1, 1, 1, VoxMat.id("metal_yellow"))
			v.fill_ellipsoid_noise(Vector3(8, 19, 6), Vector3(5, 2.2, 5),
				VoxMat.ids("metal"), 1.0, 0.1, 120)
			return v
		"picture":
			var v := Build.vol(Vector3i(15, 16, 3))
			b(v, Vector3i.ZERO, Vector3i(15, 16, 3), "wood_dark")
			b(v, Vector3i(1, 1, 0), Vector3i(13, 14, 1), "wood_light")
			for i in 9:
				b(v, Vector3i(i + 3, 3 + i % 3, 0), Vector3i(1, 6 + i % 2, 1), "plaster_blue")
			return v
		"safe":
			var v := Build.vol(Vector3i(13, 15, 7))
			b(v, Vector3i.ZERO, Vector3i(13, 15, 7), "metal_dark")
			b(v, Vector3i(1, 2, 0), Vector3i(11, 12, 1), "metal_green")
			v.fill_cylinder(Vector3(7, 8, 0), 2.6, 1, 2, VoxMat.id("metal"))
			b(v, Vector3i(4, 5, 0), Vector3i(1, 3, 1), "metal_yellow")
			return v
		"safe_open":
			var v := Build.vol(Vector3i(13, 15, 7))
			b(v, Vector3i.ZERO, v.get_size(), "metal_dark")
			b(v, Vector3i(1, 3, 0), Vector3i(11, 11, 6), "")
			b(v, Vector3i(1, 3, 0), Vector3i(11, 1, 5), "metal_green")
			b(v, Vector3i(2, 10, 3), Vector3i(9, 1, 3), "metal_green")
			return v
		"safe_door":
			var v := Build.vol(Vector3i(12, 13, 2))
			b(v, Vector3i.ZERO, v.get_size(), "metal_green")
			b(v, Vector3i(1, 2, 1), Vector3i(10, 9, 1), "metal_dark")
			b(v, Vector3i(8, 6, 0), Vector3i(2, 2, 1), "metal_yellow")
			return v
		"phone":
			var v := Build.vol(Vector3i(13, 13, 12))
			SchoolRooms.desk(v, Vector3i.ZERO, 13, 12, "wood_dark")
			b(v, Vector3i(2, 8, 2), Vector3i(9, 3, 7), "tank_black")
			b(v, Vector3i(2, 11, 3), Vector3i(9, 1, 2), "metal_dark")
			for x in [2, 9]:
				b(v, Vector3i(x, 11, 2), Vector3i(2, 2, 4), "tank_black")
			v.fill_cylinder(Vector3(7, 11, 7), 2, 1, 1, VoxMat.id("metal"))
			return v
		"spotlight":
			var v := Build.vol(Vector3i(13, 9, 13))
			v.fill_cylinder(Vector3(6, 4, 0), 4.4, 10, 2, VoxMat.id("metal_dark"))
			v.fill_cylinder(Vector3(6, 4, 10), 3.4, 1, 2, VoxMat.id("lamp"))
			b(v, Vector3i(4, 7, 3), Vector3i(4, 2, 5), "metal_teal")
			return v
		"fixer":
			var v := Build.vol(Vector3i(9, 18, 8))
			b(v, Vector3i.ZERO, Vector3i(9, 8, 8), "wood_dark")
			v.fill_cylinder(Vector3(4, 8, 4), 3.0, 7, 1, VoxMat.id("glass"))
			v.fill_cylinder(Vector3(4, 8, 4), 2.0, 6, 1, VoxMat.id("metal_blue"))
			b(v, Vector3i(3, 15, 3), Vector3i(2, 3, 2), "pvc")
			return v
		"reel":
			var v := Build.vol(Vector3i(13, 9, 13))
			for y in [0, 3, 6]:
				v.fill_cylinder(Vector3(6, y, 6), 5.7, 2, 1, VoxMat.id("metal"))
				v.fill_cylinder(Vector3(6, y + 2, 6), 4.1, 1, 1, VoxMat.id("tank_black"))
			b(v, Vector3i(8, 8, 5), Vector3i(5, 1, 3), "wood_dark")
			return v
		"coal":
			var v := Build.vol(Vector3i(11, 13, 6))
			b(v, Vector3i(4, 0, 2), Vector3i(2, 9, 2), "wood")
			b(v, Vector3i(2, 9, 0), Vector3i(6, 4, 5), "metal_dark")
			return v
		"mains":
			var v := Build.vol(Vector3i(15, 22, 9))
			b(v, Vector3i.ZERO, Vector3i(15, 22, 9), "metal_green")
			b(v, Vector3i(2, 4, 8), Vector3i(11, 17, 1), "metal_dark")
			b(v, Vector3i(5, 13, 8), Vector3i(5, 5, 1), "metal_yellow")
			b(v, Vector3i(7, 7, 8), Vector3i(2, 4, 1), "metal_red")
			return v
		"guard_key", "director_key":
			var v := Build.vol(Vector3i(6, 3, 4))
			var metal := "metal_yellow" if key == "guard_key" else "metal"
			b(v, Vector3i(0, 0, 1), Vector3i(5, 1, 2), metal)
			b(v, Vector3i(3, 0, 0), Vector3i(2, 1, 1), metal)
			b(v, Vector3i(0, 0, 2), Vector3i(2, 1, 2), "metal_teal" if key == "guard_key" else "metal_red")
			return v
		"fan":
			var v := Build.vol(Vector3i(14, 22, 12))
			b(v, Vector3i.ZERO, Vector3i(14, 22, 12), "metal_teal")
			b(v, Vector3i(1, 4, 11), Vector3i(12, 14, 1), "tank_black")
			for y in range(5, 18, 3):
				b(v, Vector3i(2, y, 11), Vector3i(10, 1, 1), "metal")
			b(v, Vector3i(6, 19, 11), Vector3i(2, 2, 1), "lamp")
			return v
		"wheel":
			var v := Build.vol(Vector3i(12, 18, 8))
			b(v, Vector3i(4, 0, 1), Vector3i(4, 13, 5), "metal_dark")
			for y in [6, 15]:
				b(v, Vector3i(1, y, 6), Vector3i(10, 2, 2), "metal")
			for x in [1, 9]:
				b(v, Vector3i(x, 8, 6), Vector3i(2, 7, 2), "metal")
			b(v, Vector3i(5, 8, 7), Vector3i(2, 8, 1), "metal_red")
			b(v, Vector3i(2, 10, 7), Vector3i(8, 2, 1), "metal")
			return v
		"garage_lift":
			var v := Build.vol(Vector3i(12, 14, 9))
			b(v, Vector3i.ZERO, Vector3i(12, 14, 9), "metal_blue")
			b(v, Vector3i(1, 5, 8), Vector3i(10, 8, 1), "metal_dark")
			for x in [3, 7]:
				b(v, Vector3i(x, 8, 8), Vector3i(2, 2, 1), "metal_yellow" if x == 3 else "metal_red")
			return v
		"microphone":
			var v := Build.vol(Vector3i(11, 14, 10))
			SchoolRooms.desk(v, Vector3i.ZERO, 11, 10, "wood_dark")
			b(v, Vector3i(3, 8, 2), Vector3i(6, 1, 5), "metal_dark")
			b(v, Vector3i(5, 9, 4), Vector3i(1, 4, 1), "metal")
			b(v, Vector3i(3, 12, 4), Vector3i(5, 2, 2), "tank_black")
			b(v, Vector3i(3, 9, 6), Vector3i(1, 1, 1), "metal_red")
			return v
		"loose_tile":
			var v := Build.vol(Vector3i(13, 1, 12))
			b(v, Vector3i.ZERO, v.get_size(), "roof_tile")
			b(v, Vector3i(1, 0, 1), Vector3i(11, 1, 3), "metal_dark")
			return v
	return Build.vol(Vector3i.ONE)


static func lid(kind: String) -> VoxelVolume:
	var v := Build.vol(Vector3i(20, 2, 20))
	var base := "metal_dark" if kind == "pool" else "dirt"
	b(v, Vector3i.ZERO, Vector3i(20, 1, 20), base)
	if kind == "pool":
		for x in range(1, 20, 3):
			b(v, Vector3i(x, 1, 1), Vector3i(1, 1, 18), "metal")
		for z in [0, 19]:
			b(v, Vector3i(0, 1, z), Vector3i(20, 1, 1), "metal_dark")
	elif kind == "lobby":
		b(v, Vector3i(0, 1, 0), Vector3i(20, 1, 20), "curtain_red")
		for x in [1, 18]:
			b(v, Vector3i(x, 1, 1), Vector3i(1, 1, 18), "curtain_beige")
	else:
		b(v, Vector3i(0, 1, 0), Vector3i(20, 1, 20), "grass")
	return v


static func piano() -> VoxelVolume:
	var v := Build.vol(Vector3i(23, 14, 13))
	for x in [1, 20]:
		b(v, Vector3i(x, 0, 1), Vector3i(2, 8, 11), "wood_dark")
	b(v, Vector3i(0, 8, 0), Vector3i(23, 6, 9), "wood_dark")
	b(v, Vector3i(1, 7, 8), Vector3i(21, 3, 5), "wood_dark")
	for x in range(2, 21):
		b(v, Vector3i(x, 10, 9), Vector3i(1, 1, 3), "pvc")
		if x % 3:
			b(v, Vector3i(x, 11, 9), Vector3i(1, 1, 1), "tank_black")
	return v


static func mock_rifle() -> VoxelVolume:
	var v := Build.vol(Vector3i(11, 4, 3))
	b(v, Vector3i(0, 1, 1), Vector3i(7, 2, 1), "wood_dark")
	b(v, Vector3i(6, 2, 1), Vector3i(5, 1, 1), "wood")
	b(v, Vector3i(4, 0, 1), Vector3i(2, 2, 1), "wood")
	return v
