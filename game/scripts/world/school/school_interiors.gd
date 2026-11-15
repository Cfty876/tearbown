class_name SchoolInteriors
extends RefCounted

const PANEL_COLORS := ["plaster_blue", "plaster_green", "plaster_yellow", "plaster_blue"]
const HANDOUTS := ["plastic_white", "curtain_red", "metal_blue", "metal_yellow"]
const CABINET := Vector3i(14, 24, 12)

static func b(v: VoxelVolume, p: Vector3i, d: Vector3i, mat: String) -> void:
	SchoolLevel.box(v, p, d, mat)


static func furnish(v: VoxelVolume, kind: String, area: Rect2i, side: int, floor: int, col: int, door_z: int, homeroom := false) -> Dictionary:
	var x := area.position.x
	var z := area.position.y
	var right := area.end.x
	var back := area.end.y
	var grid := SchoolGrid.new(area.grow(-1))
	var entry_x := right - 27 if col == 0 else x + 1
	grid.protect("Вход", Rect2i(entry_x, door_z - 3, 26, 22))
	# The turning bay joins the door to a permanent lengthwise aisle.
	var aisle := x + 17 if kind == "chem" else x + 29
	grid.protect("Проход", Rect2i(aisle, z + 1, 9, back - z - 2))
	if kind == "chem":
		grid.protect("Проход 2", Rect2i(x + 39, z + 1, 9, back - z - 2))
	var hides: Array[Dictionary] = []
	var student_chairs: Array[Vector3i] = []
	var teacher_chair := Vector3i.ZERO
	var trim: String = PANEL_COLORS[floor]
	b(v, Vector3i(x, 1, z), Vector3i(area.size.x, 1, area.size.y), "stone" if kind in ["chem", "prep", "medical", "photo"] else "wood")
	for edge in [z, back - 1]:
		b(v, Vector3i(x + 1, 8, edge), Vector3i(area.size.x - 2, 1, 1), trim)
	if side == 0 and col == 1 and kind in ["wood", "prep"]:
		grid.protect("Вытяжка", Rect2i(150, 173, 20, 32))
		if kind == "wood" and floor == 0:
			grid.protect("Доски для баррикады", Rect2i(128, 148, 29, 22))
	if kind == "chem":
		grid.protect("Бутыль", Rect2i(153, 53, 26, 28))
		grid.protect("Створ шкафа", Rect2i(147, 123, 23, 16))
	if kind == "library":
		grid.protect("Каскад", Rect2i(130, 530, 54, 25))
	if kind == "dovecote":
		grid.protect("Лаз", Rect2i(32, 515, 22, 28))
	for mark in SchoolTrapProps.room_clearances(side, floor, col, kind):
		grid.protect("Интерактив:" + str(mark), mark)

	if kind in ["class", "it", "physics", "bio", "chess", "art", "music", "medical", "office", "archive", "reading", "teachers"]:
		for offset in [0, -18, 18, -35, 35]:
			var cabinet_z := clampi(door_z + 2 + offset, z + 2, back - 16)
			var footprint_x := x + 3 if col == 0 else right - 26
			var footprint := Vector3i(footprint_x, 2, cabinet_z)
			if _can(v, grid, footprint, Vector3i(25, 24, 14)):
				var base := footprint + Vector3i(0 if col == 0 else 13, 0, 0)
				hides.append(_hide_wardrobe(v, base, col == 0))
				break

	match kind:
		"class", "it", "physics", "chem", "bio", "chess", "art", "music":
			var columns := [x + 4, x + 27, x + 48] if kind == "chem" else [x + 7, right - 22]
			var width := 12 if kind == "chem" else 15
			var board_at := Vector3i(x + 12, 12, z + 4)
			_teaching_wall(v, board_at, kind)
			var teacher := Vector3i(right - 22, 2, z + 15 if homeroom else z + 10)
			if homeroom and _can(v, grid, teacher - Vector3i(0, 0, 6), Vector3i(18, 14, 15)):
				_school_desk(v, teacher, 18, 9, kind, side + floor)
				teacher_chair = teacher + Vector3i(7, 0, -5)
				SchoolRooms.chair(v, teacher_chair, "wood", true)
			elif _can(v, grid, teacher, Vector3i(18, 12, 10)):
				_school_desk(v, teacher, 18, 9, kind, side + floor)
			for rz in range(z + 28, back - (15 if homeroom else 20), 18):
				for xx: int in columns:
					var seat := Vector3i(xx, 2, rz)
					if _can(v, grid, seat, Vector3i(width, 16, 14)):
						_school_desk(v, seat, width, 7, kind, rz + xx + floor)
						var chair := seat + Vector3i(3, 0, 9)
						_chair(v, chair, trim)
						if homeroom:
							student_chairs.append(chair)
			if kind == "chem":
				var sink := Vector3i(x + 4, 2, back - 27)
				if _can(v, grid, sink, Vector3i(13, 15, 9)):
					_sink(v, sink)
				_reagent_table(v, Vector3i(158, 2, 58))
			elif kind == "bio":
				var at := Vector3i(right - 13, 2, z + 15)
				if _can(v, grid, at, Vector3i(9, 28, 10)):
					_display(v, at)
		"wood", "metal", "prep", "weather", "photo", "radio", "server":
			var bench_kind := "saw" if kind == "wood" else ("lathe" if kind == "metal" else "lab")
			for rz in range(z + 8, back - 16, 20):
				for xx in [x + 4, right - 25]:
					var at := Vector3i(xx, 2, rz)
					var depth := 12 if kind in ["radio", "server"] else 11
					if not _can(v, grid, at, Vector3i(23, 25, depth)):
						continue
					if kind == "server":
						_server(v, at)
					elif kind in ["radio", "photo", "weather"]:
						_console(v, at, kind)
					else:
						SchoolRooms.workbench(v, at, bench_kind)
						b(v, at + Vector3i(17, 9, 6), Vector3i(4, 3, 3), "metal_dark")
			if kind in ["wood", "metal", "prep"]:
				var at := Vector3i(right - 15, 2, back - 14)
				if _can(v, grid, at, Vector3i(12, 24, 8)):
					_lockers(v, at, 2, trim)
		"library", "reading", "archive":
			for at in [Vector3i(x + 5, 2, z + 6), Vector3i(right - 27, 2, back - 12), Vector3i(x + 5, 2, back - 12)]:
				if _can(v, grid, at, Vector3i(22, 24, 6)):
					SchoolRooms.shelf(v, at, 22, 24, floor)
			for rz in range(z + 21, back - 17, 23):
				var at := Vector3i(x + 7, 2, rz)
				if _can(v, grid, at, Vector3i(18, 12, 15)):
					_school_desk(v, at, 18, 8, "class", rz)
					_chair(v, at + Vector3i(6, 0, 10), trim)
			if kind == "library":
				var gallery := Vector3i(right - 26, 23, back - 17)
				b(v, gallery, Vector3i(23, 2, 14), "metal_dark")
				b(v, gallery + Vector3i(0, 2, 0), Vector3i(23, 8, 1), "metal_teal")
		"dovecote":
			for rz in range(z + 8, back - 13, 16):
				var at := Vector3i(right - 15, 2, rz)
				if _can(v, grid, at, Vector3i(11, 23, 10)):
					_nesting(v, at)
		_:
			var at := Vector3i(right - 25, 2, z + 9)
			if _can(v, grid, at, Vector3i(21, 13, 16)):
				_school_desk(v, at, 21, 10, "office", z)
				_chair(v, at + Vector3i(6, 0, 11), trim)
			var corner := Vector3i(x + 4, 2, z + 10)
			if _can(v, grid, corner, Vector3i(20, 15, 10)):
				_couch(v, corner, "curtain_beige" if kind == "medical" else "wood_dark")
			var rack := Vector3i(right - 25, 2, back - 12)
			if _can(v, grid, rack, Vector3i(20, 24, 6)):
				SchoolRooms.shelf(v, rack, 20, 24, floor)

	# Side displays use the same occupancy and floor support checks as the desks.
	for xx in [x + 3, right - 20]:
		var detail := Vector3i(xx, 2, back - 11)
		if _can(v, grid, detail, Vector3i(16, 19, 7)):
			SchoolDetails.classroom_detail(v, detail, kind)
	# Skirting and high-level wall bands stay outside the furniture envelopes.
	for edge in [z, back - 1]:
		b(v, Vector3i(x, 2, edge), Vector3i(area.size.x, 1, 1), "wood_dark")
		b(v, Vector3i(x, 31, edge), Vector3i(area.size.x, 1, 1), trim)
	return {"area": area, "placements": grid.placements, "hides": hides,
		"teacher_chair": teacher_chair, "student_chairs": student_chairs, "door_z": door_z, "col": col}


static func _can(v: VoxelVolume, grid: SchoolGrid, at: Vector3i, size: Vector3i, clearance := 0) -> bool:
	if not grid.fits_volume(v, at, size):
		return false
	return grid.reserve(at, size.x, size.z + clearance)


static func _school_desk(v: VoxelVolume, at: Vector3i, w: int, d: int, kind: String, seed: int) -> void:
	SchoolRooms.desk(v, at, w, d, "wood_dark" if kind in ["chem", "office"] else "wood_light")
	b(v, at + Vector3i(1, 2, 0), Vector3i(w - 2, 4, 1), "metal_teal")
	b(v, at + Vector3i(0, 0, 1), Vector3i(1, 1, d - 2), "metal_dark")
	b(v, at + Vector3i(w - 1, 0, 1), Vector3i(1, 1, d - 2), "metal_dark")
	if kind == "it":
		SchoolRooms.monitor(v, at + Vector3i(3, 8, 0))
	elif kind == "chem":
		for i in 3:
			b(v, at + Vector3i(2 + i * 3, 7, 2 + (seed + i) % 3), Vector3i(2, 1, 2), "wood_dark")
		b(v, at + Vector3i(2, 8, 1), Vector3i(2, 4, 2), "glass")
		b(v, at + Vector3i(5, 8, 2), Vector3i(2, 3, 2), "metal_blue")
	elif kind == "physics":
		b(v, at + Vector3i(1, 8, 0), Vector3i(5, 2, 3), "metal_dark")
		b(v, at + Vector3i(2, 10, 1), Vector3i(1, 5, 1), "metal")
		b(v, at + Vector3i(2, 14, 1), Vector3i(5, 1, 1), "metal")
		b(v, at + Vector3i(6, 12, 1), Vector3i(1, 3, 1), "metal_yellow")
	elif kind == "chess":
		for i in 6:
			for j in 6:
				b(v, at + Vector3i(3 + i, 8, j), Vector3i.ONE, "pvc" if (i + j) % 2 else "tank_black")
	else:
		b(v, at + Vector3i(2, 8, 2), Vector3i(4, 1, 3), HANDOUTS[posmod(seed, HANDOUTS.size())])
		b(v, at + Vector3i(w - 4, 8, 3), Vector3i(2, 2, 2), "wood_dark")


static func _chair(v: VoxelVolume, at: Vector3i, color: String) -> void:
	SchoolRooms.chair(v, at, "wood")
	b(v, at + Vector3i(0, 6, 3), Vector3i(4, 2, 1), color)
	for x in [0, 3]:
		b(v, at + Vector3i(x, 0, 0), Vector3i(1, 4, 1), "metal_dark")


static func _teaching_wall(v: VoxelVolume, at: Vector3i, kind: String) -> void:
	b(v, at, Vector3i(39, 12, 2), "wood_dark")
	b(v, at + Vector3i(1, 1, 2), Vector3i(37, 10, 1), "metal_green")
	b(v, at + Vector3i(1, 0, 3), Vector3i(37, 1, 1), "wood_light")
	VoxelFont.draw(v, "120" if kind == "class" else SchoolRooms.title(kind).left(6),
		at + Vector3i(4, 8, 2), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	b(v, at + Vector3i(33, 2, 3), Vector3i(2, 1, 1), "plastic_white")
	# Chalk marks, eraser and a clock above the board.
	for i in 4:
		b(v, at + Vector3i(4 + i * 7, 2, 3), Vector3i(4, 1, 1), "metal_white")
	b(v, at + Vector3i(28, 1, 3), Vector3i(3, 1, 1), "tank_black")
	b(v, at + Vector3i(16, 14, 0), Vector3i(7, 7, 2), "wood_dark")
	b(v, at + Vector3i(17, 15, 2), Vector3i(5, 5, 1), "pvc")
	b(v, at + Vector3i(19, 17, 2), Vector3i(1, 3, 1), "tank_black")
	b(v, at + Vector3i(19, 17, 2), Vector3i(2, 1, 1), "tank_black")


static func _wardrobe(v: VoxelVolume, at: Vector3i) -> void:
	b(v, at, Vector3i(14, 24, 2), "wood_dark")
	for x in [0, 12]:
		b(v, at + Vector3i(x, 0, 2), Vector3i(2, 24, 10), "wood_dark")
	b(v, at + Vector3i(2, 22, 2), Vector3i(10, 2, 10), "wood_light")
	b(v, at + Vector3i(2, 19, 4), Vector3i(10, 1, 2), "metal")
	b(v, at + Vector3i(3, 21, 11), Vector3i(5, 1, 1), "metal_teal")


static func _reagent_table(v: VoxelVolume, at: Vector3i) -> void:
	SchoolRooms.desk(v, at, 18, 14, "wood_dark", 10)
	for i in 4:
		b(v, at + Vector3i(i * 3, 9, (i * 2) % 8), Vector3i(3, 1, 4), "wood")
	b(v, at + Vector3i(2, 4, 0), Vector3i(14, 4, 2), "metal_teal")
	b(v, at + Vector3i(1, 6, 0), Vector3i(4, 1, 1), "metal")


static func _sink(v: VoxelVolume, at: Vector3i) -> void:
	b(v, at, Vector3i(13, 8, 9), "metal_teal")
	b(v, at + Vector3i(0, 8, 0), Vector3i(13, 2, 9), "pvc")
	b(v, at + Vector3i(2, 9, 2), Vector3i(9, 1, 5), "")
	b(v, at + Vector3i(6, 10, 1), Vector3i(1, 4, 1), "metal")
	b(v, at + Vector3i(6, 13, 1), Vector3i(1, 1, 4), "metal")


static func _display(v: VoxelVolume, at: Vector3i) -> void:
	b(v, at, Vector3i(9, 11, 10), "wood_dark")
	for x in [0, 8]:
		b(v, at + Vector3i(x, 11, 0), Vector3i(1, 15, 10), "glass")
	b(v, at + Vector3i(0, 11, 9), Vector3i(9, 15, 1), "glass")
	b(v, at + Vector3i(3, 11, 3), Vector3i(3, 11, 3), "wood_light")
	b(v, at + Vector3i(2, 21, 2), Vector3i(5, 4, 5), "wood_light")
	b(v, at + Vector3i(0, 26, 0), Vector3i(9, 2, 10), "wood_dark")


static func _lockers(v: VoxelVolume, at: Vector3i, count: int, color: String) -> void:
	for i in count:
		var p := at + Vector3i(i * 6, 0, 0)
		b(v, p, Vector3i(6, 21, 7), color)
		b(v, p + Vector3i(1, 3, 7), Vector3i(4, 16, 1), "metal_teal")
		for y in [14, 16]:
			b(v, p + Vector3i(2, y, 7), Vector3i(2, 1, 1), "tank_black")
		b(v, p + Vector3i(4, 8, 8), Vector3i(1, 2, 1), "metal")


static func _server(v: VoxelVolume, at: Vector3i) -> void:
	for x in [0, 10]:
		b(v, at + Vector3i(x, 0, 0), Vector3i(8, 23, 9), "metal_dark")
		for y in range(4, 22, 4):
			b(v, at + Vector3i(x + 1, y, 8), Vector3i(6, 2, 1), "tank_black")
			b(v, at + Vector3i(x + 1, y, 9), Vector3i(1, 1, 1), "brand_green")


static func _console(v: VoxelVolume, at: Vector3i, kind: String) -> void:
	SchoolRooms.desk(v, at, 20, 9, "wood_dark")
	match kind:
		"radio":
			b(v, at + Vector3i(1, 8, 1), Vector3i(15, 3, 6), "metal_dark")
			for x in range(2, 16, 3):
				b(v, at + Vector3i(x, 11, 3), Vector3i(1, 1, 3), "metal_teal")
			b(v, at + Vector3i(18, 8, 1), Vector3i(1, 6, 1), "metal")
			b(v, at + Vector3i(17, 13, 2), Vector3i(3, 2, 2), "tank_black")
		"photo":
			for x in [1, 8, 15]:
				b(v, at + Vector3i(x, 8, 2), Vector3i(5, 2, 6), "metal_red")
				b(v, at + Vector3i(x + 1, 9, 3), Vector3i(3, 1, 4), "metal_dark")
		_:
			b(v, at + Vector3i(5, 8, 2), Vector3i(8, 7, 4), "metal_teal")
			b(v, at + Vector3i(6, 11, 6), Vector3i(6, 3, 1), "glass")


static func _nesting(v: VoxelVolume, at: Vector3i) -> void:
	for y in [0, 7, 14]:
		b(v, at + Vector3i(0, y, 0), Vector3i(11, 1, 10), "wood_dark")
		for x in [0, 5, 10]:
			b(v, at + Vector3i(x, y + 1, 0), Vector3i(1, 6, 10), "wood")
		b(v, at + Vector3i(1, y + 1, 8), Vector3i(9, 1, 2), "wood_light")


static func _couch(v: VoxelVolume, at: Vector3i, color: String) -> void:
	SchoolRooms.desk(v, at, 20, 9, "wood_dark", 4)
	b(v, at + Vector3i(0, 4, 0), Vector3i(20, 2, 9), color)
	b(v, at + Vector3i(0, 6, 0), Vector3i(20, 6, 2), color)
	for x in [0, 18]:
		b(v, at + Vector3i(x, 6, 2), Vector3i(2, 2, 7), color)


static func fume_cabinet(v: VoxelVolume) -> void:
	# The glass is only on the sides. The entire middle is a walkable aperture.
	for x in [148, 168]:
		b(v, Vector3i(x, 2, 132), Vector3i(2, 25, 19), "wood_dark")
		b(v, Vector3i(x, 7, 135), Vector3i(2, 15, 13), "glass")
		for z in [132, 149]:
			b(v, Vector3i(x, 2, z), Vector3i(2, 25, 2), "wood_light")
	b(v, Vector3i(148, 24, 132), Vector3i(22, 4, 19), "wood_dark")
	b(v, Vector3i(152, 25, 131), Vector3i(13, 2, 1), "metal_teal")
	for x in range(153, 165, 3):
		b(v, Vector3i(x, 25, 130), Vector3i(1, 2, 1), "metal")
	for x in [146, 170]:
		for z in [134, 143]:
			b(v, Vector3i(x, 12, z), Vector3i(2, 4, 3), "glass")


static func corridor(v: VoxelVolume, side: int, floor: int, homeroom: Dictionary = {}) -> Dictionary:
	var grid := SchoolGrid.new(Rect2i(70, 3, 50, 594))
	grid.claim("Ось", Rect2i(85, 3, 20, 594))
	for edge in [0, 1]:
		for row in range(5):
			var middle: int = (SchoolLevel.ROWS[row] + SchoolLevel.ROWS[row + 1]) / 2
			grid.protect("Дверь %d:%d" % [edge, row], Rect2i(70 if edge == 0 else 105, middle - 17, 15, 34))
	grid.protect("Вход МУЖ", Rect2i(105, 362, 15, 26))
	grid.protect("Вход ЖЕН", Rect2i(105, 427, 15, 26))
	grid.protect("Переход слева", Rect2i(70, 237, 15, 104))
	grid.protect("Переход справа", Rect2i(105, 237, 15, 104))
	if not homeroom.is_empty():
		var side_x := 72 if homeroom.col == 0 else 112
		var start_z: int = homeroom.door_z - 29
		grid.protect("Скамья класса", Rect2i(side_x - 1, start_z, 8, 27))
		b(v, Vector3i(side_x, 6, start_z), Vector3i(6, 1, 27), "wood_light")
		b(v, Vector3i(side_x if homeroom.col == 0 else side_x + 5, 7, start_z), Vector3i(1, 3, 27), "wood")
		for dz in [1, 12, 24]:
			b(v, Vector3i(side_x, 2, start_z + dz), Vector3i(6, 4, 2), "metal_teal")
		homeroom["bench"] = Vector3i(side_x + 3, 2, start_z)
	var locker_at := Vector3i(70, 2, 221)
	var locker_fits := _can(v, grid, locker_at, Vector3i(12, 24, 14))
	assert(locker_fits, "Special corridor locker needs its wall slot")
	var locker := _hide_wardrobe(v, locker_at, true, true)
	for z in range(4, 595, 1):
		b(v, Vector3i(70, 1, z), Vector3i(50, 1, 1), "wood" if z % 13 == 0 else "wood_light")

	for x in [71, 118]:
		b(v, Vector3i(x, 1, 3), Vector3i(1, 1, 594), PANEL_COLORS[floor])
	for z in [12, 99, 148, 211, 356, 404, 470, 565]:
		for side_index in 2:
			var at := Vector3i(71 if side_index == 0 else 110, 2, z)
			if not _can(v, grid, at, Vector3i(8, 24, 13)):
				continue
			if (z + side + floor + side_index) % 3 == 0:
				# Side-facing bench along the wall, with a shoe rack below.
				b(v, at + Vector3i(0, 4, 0), Vector3i(6, 2, 12), "wood_dark")
				for dz in [0, 10]:
					b(v, at + Vector3i(0, 0, dz), Vector3i(6, 4, 2), "metal_teal")
			else:
				b(v, at, Vector3i(6, 21, 12), PANEL_COLORS[floor])
				for dz in [0, 6]:
					b(v, at + Vector3i(2, 15, dz + 2), Vector3i(5, 1, 3), "metal_dark")
					b(v, at + Vector3i(3, 7, dz + 1), Vector3i(4, 2, 1), "metal")

	for z in [120, 180, 376, 480]:
		var at := Vector3i(72 if (z + floor) % 3 else 110, 2, z)
		if _can(v, grid, at, Vector3i(7, 24, 10)):
			b(v, at, Vector3i(7, 8, 10), "wood_dark")
			b(v, at + Vector3i(0, 8, 0), Vector3i(7, 1, 10), "wood_light")
			b(v, at + Vector3i(1, 9, 2), Vector3i(5, 12, 6), "glass")
			b(v, at + Vector3i(3, 9, 4), Vector3i(1, 7, 2), "metal_yellow")
			b(v, at + Vector3i(2, 16, 3), Vector3i(3, 2, 4), "metal_yellow")
			b(v, at + Vector3i(0, 21, 0), Vector3i(7, 1, 10), "wood_dark")
	for x in [70, 119]:
		for z in [22, 107, 167, 220, 366, 454, 550]:
			if not grid.claim("Стенд %d:%d" % [x, z], Rect2i(x, z, 1, 14)):
				continue
			b(v, Vector3i(x, 13, z), Vector3i(1, 12, 14), "wood_dark")
			b(v, Vector3i(x, 14, z + 1), Vector3i(1, 10, 12), "curtain_beige")
			for k in [2, 6, 9]:
				b(v, Vector3i(x, 16 + k % 3, z + k), Vector3i(1, 4, 2), HANDOUTS[(k + floor) % 4])
	for z in [35, 155, 363, 508]:
		for x in [70, 117]:
			if not _can(v, grid, Vector3i(x, 2, z), Vector3i(2, 5, 11)):
				continue
			b(v, Vector3i(x, 2, z), Vector3i(2, 4, 11), "metal_dark")
			for k in range(0, 11, 2):
				b(v, Vector3i(x, 3, z + k), Vector3i(2, 4, 1), "metal")

	return locker


static func commons(v: VoxelVolume, area: Rect2i, door: int, outside: int) -> Dictionary:
	var grid := SchoolGrid.new(area.grow(-1))
	var x0 := area.position.x
	var x1 := area.end.x
	var z0 := area.position.y
	var z1 := area.end.y
	var low := mini(door, outside) - 3
	var high := maxi(door, outside) + 34
	grid.protect("Сквозной проход", Rect2i(x0, low, area.size.x, high - low))
	for z in range(z0 + 1, z1 - 1, 5):
		b(v, Vector3i(x0, 1, z), Vector3i(area.size.x, 1, mini(5, z1 - z)), "stone" if z % 2 else "concrete")
	for z in [z0 + 6, z1 - 15]:
		var couch := Vector3i(x0 + 7, 2, z)
		if _can(v, grid, couch, Vector3i(20, 15, 10)):
			_couch(v, couch, "curtain_green")
		var desk := Vector3i(x1 - 23, 2, z)
		if _can(v, grid, desk, Vector3i(14, 9, 8)):
			SchoolRooms.desk(v, desk, 14, 8, "wood_light", 7)
		b(v, Vector3i(x0 + 26, 34, z + 4), Vector3i(13, 2, 5), "lamp")
	var hides: Array[Dictionary] = []
	for z in range(z0 + 4, z1 - 27, 3):
		var spot := Vector3i(x0 + 30, 2, z)
		if _can(v, grid, spot, Vector3i(25, 24, 14)):
			hides.append(_hide_wardrobe(v, spot, true))
			break
	return {"area": area, "placements": grid.placements, "hides": hides}


static func _hide_wardrobe(v: VoxelVolume, base: Vector3i, faces_east: bool, locker := false) -> Dictionary:
	var yaw := PI * 0.5 if faces_east else -PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var pivot := Vector3(base) + (Vector3(0, 0, CABINET.x) if faces_east else Vector3(CABINET.z, 0, 0))
	var cabinet := Build.vol(CABINET)
	if locker:
		_locker_shell(cabinet)
	else:
		_wardrobe(cabinet, Vector3i.ZERO)
	for x in CABINET.x:
		for y in CABINET.y:
			for z in CABINET.z:
				var cell := Vector3i(x, y, z)
				var voxel := cabinet.get_voxel(cell)
				if voxel != 0:
					v.set_voxel(Vector3i((pivot + basis * (Vector3(cell) + Vector3.ONE * 0.5)).floor()), voxel)
	return {"bath": false, "school": true, "yaw": yaw, "locker": locker,
		"panel": pivot + basis * Vector3(2, 1, 12.1),
		"center": pivot + basis * Vector3(7, 1.55 if locker else 0.55, 6),
		"front": pivot + basis * Vector3(7, 0.55, 20)}


static func _locker_shell(v: VoxelVolume) -> void:
	b(v, Vector3i(0, 0, 0), Vector3i(14, 24, 2), "metal_dark")
	for x in [0, 12]:
		b(v, Vector3i(x, 0, 2), Vector3i(2, 24, 10), "metal_green")
		b(v, Vector3i(x, 2, 11), Vector3i(2, 20, 1), "metal")
	b(v, Vector3i(0, 22, 2), Vector3i(14, 2, 10), "metal_teal")
	b(v, Vector3i(2, 0, 2), Vector3i(10, 1, 10), "metal_dark")
	b(v, Vector3i(2, 21, 4), Vector3i(10, 1, 7), "metal")


static func guard_lobby(v: VoxelVolume) -> void:
	for x in range(4, 198, 9):
		for z in range(4, 117, 9):
			b(v, Vector3i(x, 1, z), Vector3i(8, 1, 8), "stone" if (x + z) % 2 else "concrete")
	for x in [10, 56]:
		b(v, Vector3i(x, 2, 66), Vector3i(2, 28, 29), "metal_teal")
		b(v, Vector3i(x, 12, 67), Vector3i(1, 14, 26), "glass")
	b(v, Vector3i(10, 2, 65), Vector3i(48, 11, 2), "wood_dark")
	b(v, Vector3i(10, 25, 65), Vector3i(48, 3, 2), "metal_teal")
	b(v, Vector3i(10, 11, 65), Vector3i(8, 13, 2), "glass")
	b(v, Vector3i(50, 11, 65), Vector3i(8, 13, 2), "glass")
	# Clear view and room to use the desk through the booth's wide service window.
	VoxelFont.draw(v, "ПОСТ", Vector3i(24, 28, 94), Vector3i(1, 0, 0), VoxMat.id("metal_white"))
	for x in [135, 160, 180]:
		b(v, Vector3i(x, 14, 114), Vector3i(13, 15, 2), "wood_dark")
		b(v, Vector3i(x + 1, 15, 116), Vector3i(11, 13, 1), "pvc")
		for y in [18, 21, 24]:
			b(v, Vector3i(x + 3, y, 116), Vector3i(7, 1, 1), "metal_teal")


static func attic_trim(v: VoxelVolume) -> void:
	for pos in [Vector3i(8, 2, 504), Vector3i(56, 2, 551), Vector3i(8, 2, 570)]:
		b(v, pos, Vector3i(10, 4, 10), "roof_tile")
		b(v, pos + Vector3i(1, 4, 2), Vector3i(6, 1, 8), "wood_dark")
	for z in [508, 546, 578]:
		b(v, Vector3i(3, 30, z), Vector3i(64, 3, 4), "wood_dark")
	for z in [498, 553, 568]:
		b(v, Vector3i(21, 1, z), Vector3i(7, 1, 2), "curtain_beige")
