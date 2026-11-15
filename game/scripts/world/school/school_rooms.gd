class_name SchoolRooms
extends RefCounted

const LABELS := {
	"class": "КЛАСС", "music": "МУЗЫКА", "office": "КАБИНЕТ", "wood": "СТОЛЯРКА",
	"physics": "ФИЗИКА", "teachers": "УЧИТЕЛЬСКАЯ", "director": "ДИРЕКТОР",
	"chem": "ХИМИЯ", "prep": "ЛАБОРАНТСКАЯ", "it": "ИНФОРМАТИКА", "server": "СЕРВЕРНАЯ",
	"bio": "БИОЛОГИЯ", "radio": "РАДИОУЗЕЛ", "archive": "АРХИВ", "reading": "ЧИТАЛЬНЯ",
	"library": "БИБЛИОТЕКА", "weather": "МЕТЕОПОСТ", "dovecote": "ГОЛУБЯТНЯ",
	"chess": "ШАХМАТЫ", "photo": "ФОТОЛАБ", "art": "ИЗОСТУДИЯ", "metal": "СЛЕСАРКА",
	"medical": "МЕДПУНКТ"
}
const BOOKS := ["curtain_red", "metal_teal", "wood_light", "plastic_blue", "metal_yellow"]


static func title(kind: String) -> String:
	return LABELS.get(kind, "КАБИНЕТ")


static func b(v: VoxelVolume, p: Vector3i, d: Vector3i, mat: String) -> void:
	SchoolLevel.box(v, p, d, mat)


static func desk(v: VoxelVolume, p: Vector3i, w: int, depth: int, finish := "wood_light", height := 8) -> void:
	b(v, p + Vector3i(0, height - 1, 0), Vector3i(w, 1, depth), finish)
	for x in [0, w - 1]:
		for z in [0, depth - 1]:
			b(v, p + Vector3i(x, 0, z), Vector3i(1, height - 1, 1), "metal_dark")

	# Apron and cross-braces make the same table readable in every room.
	b(v, p + Vector3i(1, height - 3, 0), Vector3i(w - 2, 2, 1), "wood")
	for x in [0, w - 1]:
		b(v, p + Vector3i(x, 2, 0), Vector3i(1, 1, depth), "metal_teal")


static func chair(v: VoxelVolume, p: Vector3i, finish := "wood", toward_positive_z := false) -> void:
	desk(v, p, 4, 4, finish, 5)
	var back := 0 if toward_positive_z else 3
	b(v, p + Vector3i(0, 7, back), Vector3i(4, 2, 1), finish)
	for x in [0, 3]:
		b(v, p + Vector3i(x, 5, back), Vector3i(1, 2, 1), "metal_dark")


static func locker(v: VoxelVolume, p: Vector3i, finish: String) -> void:
	b(v, p, Vector3i(8, 19, 5), finish)
	for x in [1, 5]:
		b(v, p + Vector3i(x, 12, 5), Vector3i(2, 1, 1), "metal_dark")
		b(v, p + Vector3i(x + 1, 8, 5), Vector3i(1, 2, 1), "metal")


static func monitor(v: VoxelVolume, p: Vector3i) -> void:
	b(v, p + Vector3i(1, 0, 1), Vector3i(5, 1, 4), "metal_dark")
	b(v, p + Vector3i(2, 1, 1), Vector3i(3, 1, 3), "pvc")
	b(v, p + Vector3i(1, 2, 0), Vector3i(5, 5, 5), "pvc")
	b(v, p + Vector3i(0, 2, 3), Vector3i(7, 5, 2), "pvc")
	b(v, p + Vector3i(1, 3, 5), Vector3i(5, 3, 1), "tank_black")
	b(v, p + Vector3i(2, 4, 5), Vector3i(3, 1, 1), "metal_teal")
	b(v, p + Vector3i(5, 2, 5), Vector3i.ONE, "brand_green")
	b(v, p + Vector3i(0, 0, 6), Vector3i(7, 1, 2), "metal_dark")
	for x in [1, 3, 5]:
		b(v, p + Vector3i(x, 1, 6), Vector3i(1, 1, 2), "pvc")


static func shelf(v: VoxelVolume, p: Vector3i, w := 14, height := 22, seed := 0) -> void:
	b(v, p, Vector3i(1, height, 5), "wood_dark")
	b(v, p + Vector3i(w - 1, 0, 0), Vector3i(1, height, 5), "wood_dark")
	b(v, p, Vector3i(w, height, 1), "wood_dark")
	for y in range(2, height - 2, 5):
		b(v, p + Vector3i(0, y, 0), Vector3i(w, 1, 5), "wood")
		for x in range(1, w - 1):
			var h := 2 + (x + y + seed) % 3
			if (x + 2 * y + seed) % 5 != 0:
				b(v, p + Vector3i(x, y + 1, 1), Vector3i(1, h, 3), BOOKS[(x + y + seed) % BOOKS.size()])

	b(v, p + Vector3i(0, height - 1, 0), Vector3i(w, 1, 5), "wood_light")
	for x in range(3, w - 2, 5):
		b(v, p + Vector3i(x, 4, 4), Vector3i(1, 1, 1), "curtain_beige")


static func workbench(v: VoxelVolume, p: Vector3i, machine: String) -> void:
	desk(v, p, 23, 10, "wood_dark", 9)
	match machine:
		"lathe":
			b(v, p + Vector3i(2, 9, 3), Vector3i(19, 3, 5), "metal_teal")
			b(v, p + Vector3i(3, 12, 3), Vector3i(5, 6, 5), "metal_green")
			b(v, p + Vector3i(16, 12, 3), Vector3i(4, 5, 5), "metal_green")
			v.fill_cylinder(Vector3(p + Vector3i(8, 14, 5)), 1.8, 9, 0, VoxMat.id("metal"))
		"saw":
			b(v, p + Vector3i(5, 9, 2), Vector3i(10, 2, 7), "metal_teal")
			v.fill_cylinder(Vector3(p + Vector3i(10, 10, 6)), 3.5, 1, 0, VoxMat.id("metal"))
			b(v, p + Vector3i(15, 9, 2), Vector3i(5, 1, 3), "wood_light")
		_:
			b(v, p + Vector3i(1, 9, 1), Vector3i(19, 2, 4), "pvc")
			for x in range(3, 21, 4):
				b(v, p + Vector3i(x, 11, 2), Vector3i(2, 2 + x % 4, 2),
					"plastic_blue" if x % 3 else "brand_green")


static func canteen(v: VoxelVolume) -> void:
	b(v, Vector3i(3, 1, 3), Vector3i(224, 1, 157), "stone")
	for z in [28, 61, 94, 127]:
		for x in [20, 66, 112]:
			desk(v, Vector3i(x, 2, z), 27, 11, "pvc")
			for offset in [4, 16]:
				b(v, Vector3i(x + offset, 10, z + 2), Vector3i(6, 1, 5), "metal_teal")
				b(v, Vector3i(x + offset + 1, 11, z + 3), Vector3i(3, 1, 3), "plastic_white")
				b(v, Vector3i(x + offset + 4, 11, z + 5), Vector3i(1, 2, 1), "metal")
			for k in [0, 10, 20]:
				chair(v, Vector3i(x + k, 2, z + 13), "metal_teal")
				chair(v, Vector3i(x + k, 2, z - 6), "metal_teal")
	b(v, Vector3i(158, 2, 3), Vector3i(3, 24, 122), "plaster")
	Build.door(v, 0, 158, 3, 93, 2, 17, 23)
	b(v, Vector3i(163, 2, 52), Vector3i(30, 9, 10), "metal_white")
	b(v, Vector3i(163, 11, 62), Vector3i(30, 7, 1), "glass")
	for z in [15, 32, 82]:
		v.fill_cylinder(Vector3(178, 2, z), 5.4, 10, 1, VoxMat.id("metal"))
		v.fill_cylinder(Vector3(178, 12, z), 5.8, 1, 1, VoxMat.id("metal_dark"))
		for y in [5, 9]:
			v.fill_cylinder(Vector3(178, y, z), 5.6, 1, 1, VoxMat.id("metal"))
		b(v, Vector3i(183, 7, z - 1), Vector3i(2, 2, 3), "metal_teal")
		b(v, Vector3i(177, 13, z - 2), Vector3i(3, 2, 5), "metal")
	b(v, Vector3i(199, 2, 118), Vector3i(25, 27, 3), "pvc")
	b(v, Vector3i(199, 2, 121), Vector3i(3, 27, 35), "pvc")
	Build.door(v, 2, 118, 3, 205, 2, 13, 22)
	for x in [207, 216]:
		b(v, Vector3i(x, 14, 140), Vector3i(4, 9, 5), "curtain_beige")
		b(v, Vector3i(x + 1, 23, 141), Vector3i(1, 3, 1), "metal")


static func pool(v: VoxelVolume) -> void:
	b(v, Vector3i(5, 1, 164), Vector3i(218, 1, 168), "plaster_blue")
	b(v, Vector3i(40, 0, 213), Vector3i(129, 2, 78), "")
	for x in [38, 169]:
		b(v, Vector3i(x, 2, 211), Vector3i(2, 3, 82), "pvc")
	for z in [211, 291]:
		b(v, Vector3i(40, 2, z), Vector3i(129, 3, 2), "pvc")
	b(v, Vector3i(50, 2, 211), Vector3i(18, 3, 2), "")
	for x in [43, 49]:
		b(v, Vector3i(x, 2, 209), Vector3i(1, 11, 1), "metal")
		b(v, Vector3i(x, 12, 209), Vector3i(1, 1, 5), "metal")
	for x in [28, 180]:
		b(v, Vector3i(x, 1, 173), Vector3i(2, 1, 151), "metal_teal")
	for z in [195, 245, 281, 308]:
		b(v, Vector3i(185, 1, z), Vector3i(8, 1, 2), "metal_dark")
		for x in [186, 189, 192]:
			b(v, Vector3i(x, 1, z), Vector3i(1, 1, 2), "metal")
	for z in range(185, 322, 17):
		locker(v, Vector3i(200, 2, z), "metal_blue")


static func gym(v: VoxelVolume) -> void:
	b(v, Vector3i(3, 1, 3), Vector3i(224, 1, 157), "wood_dark")
	for z in range(8, 157, 5):
		b(v, Vector3i(4, 1, z), Vector3i(222, 1, 1), "wood")
	for z in [12, 148]:
		b(v, Vector3i(15, 1, z), Vector3i(202, 1, 2), "pvc")
	for x in [15, 215]:
		b(v, Vector3i(x, 1, 12), Vector3i(2, 1, 136), "pvc")
	b(v, Vector3i(115, 1, 14), Vector3i(2, 1, 134), "metal_yellow")
	for i in 72:
		var a := TAU * i / 72.0
		b(v, Vector3i(115 + roundi(cos(a) * 25), 1, 79 + roundi(sin(a) * 25)), Vector3i(2, 1, 2), "metal_white")
	for x in range(21, 203, 22):
		desk(v, Vector3i(x, 2, 4), 16, 7, "wood_light", 5)
		b(v, Vector3i(x, 7, 4), Vector3i(16, 3, 1), "wood")
		b(v, Vector3i(x, 9, 4), Vector3i(16, 1, 1), "wood_dark")
	for x: int in [8, 217]:
		for z in [27, 45]:
			b(v, Vector3i(x, 2, z), Vector3i(2, 32, 2), "wood_dark")
			for y in [2, 30]:
				b(v, Vector3i(x - 1, y, z - 1), Vector3i(4, 2, 4), "metal_dark")
			for y in [8, 29]:
				var left := 3 if x == 8 else x + 2
				var length := 5 if x == 8 else 8
				b(v, Vector3i(left, y, z), Vector3i(length, 2, 2), "metal_teal")
		for y in range(6, 33, 4):
			b(v, Vector3i(x, y, 28), Vector3i(2, 1, 18), "wood_light")


static func changing(v: VoxelVolume) -> void:
	b(v, Vector3i(4, 1, 165), Vector3i(221, 1, 169), "plaster_blue")
	for z in range(176, 321, 13):
		locker(v, Vector3i(14, 2, z), "metal_teal")
		locker(v, Vector3i(55, 2, z), "metal_blue")
	for z in [188, 227, 267]:
		desk(v, Vector3i(33, 2, z), 10, 24, "wood_dark", 5)
	for z in range(179, 321, 18):
		b(v, Vector3i(176, 2, z), Vector3i(44, 21, 2), "pvc")
		b(v, Vector3i(215, 17, z + 4), Vector3i(1, 6, 1), "metal")
		b(v, Vector3i(210, 22, z + 4), Vector3i(6, 1, 1), "metal")


static func theatre(v: VoxelVolume) -> void:
	b(v, Vector3i(4, 1, 163), Vector3i(221, 1, 171), "wood_dark")
	b(v, Vector3i(21, 2, 267), Vector3i(190, 5, 41), "wood_light")
	for step in 3:
		b(v, Vector3i(94, 2, 260 + step * 2), Vector3i(40, 1 + step * 2, 2), "wood_light")
	for z in [182, 195, 208, 221, 234, 247]:
		for x in range(28, 203, 10):
			if x < 103 or x > 126:
				chair(v, Vector3i(x, 2, z), "curtain_red", true)
	# The wings meet the exterior walls. The only opening is through the screen.
	for wing in [Vector2i(3, 61), Vector2i(165, 227)]:
		b(v, Vector3i(wing.x, 2, 305), Vector3i(wing.y - wing.x, 36, 3), "wood_dark")
		b(v, Vector3i(wing.x, 7, 304), Vector3i(wing.y - wing.x, 29, 1), "curtain_red")
		for x in range(wing.x + 4, wing.y - 2, 5):
			b(v, Vector3i(x, 7, 303), Vector3i(2, 29, 1), "curtain_red")
	b(v, Vector3i(61, 2, 305), Vector3i(104, 9, 3), "wood_dark")
	b(v, Vector3i(12, 2, 312), Vector3i(24, 11, 13), "wood")
	for x in [46, 161, 188]:
		shelf(v, Vector3i(x, 2, 329), 20, 19, x)
	for x in [63, 137]:
		b(v, Vector3i(x, 2, 315), Vector3i(29, 24, 3), "wood_dark")
		b(v, Vector3i(x + 3, 2, 318), Vector3i(4, 9, 5), "metal_dark")
		b(v, Vector3i(x + 6, 11, 318), Vector3i(16, 12, 1), "curtain_red")
	b(v, Vector3i(10, 29, 171), Vector3i(31, 9, 18), "metal_dark")
	for x in [13, 35]:
		b(v, Vector3i(x, 29, 162), Vector3i(3, 4, 9), "metal_teal")
	b(v, Vector3i(3, 29, 177), Vector3i(7, 4, 3), "metal_teal")


static func studio(v: VoxelVolume) -> void:
	b(v, Vector3i(44, 2, 163), Vector3i(2, 20, 13), "plaster_blue")
	b(v, Vector3i(44, 2, 176), Vector3i(59, 9, 2), "plaster_blue")
	desk(v, Vector3i(56, 2, 167), 29, 6, "wood_dark")
	b(v, Vector3i(62, 10, 169), Vector3i(13, 7, 5), "metal_dark")
	b(v, Vector3i(65, 12, 174), Vector3i(5, 4, 2), "metal_blue")
	for x in [50, 91, 138, 185]:
		b(v, Vector3i(x + 1, 9, 275), Vector3i(3, 3, 6), "metal_teal")
		b(v, Vector3i(x, 12, 278), Vector3i(5, 4, 4), "metal_dark")
		b(v, Vector3i(x + 1, 12, 282), Vector3i(3, 3, 1), "lamp")
