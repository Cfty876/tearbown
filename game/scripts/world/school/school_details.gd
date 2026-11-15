class_name SchoolDetails
extends RefCounted
## Small, destructible school props. Dimensions are kept inside their placement envelopes.


static func b(v: VoxelVolume, p: Vector3i, size: Vector3i, material: String) -> void:
	SchoolLevel.box(v, p, size, material)


static func picnic() -> VoxelVolume:
	var v := Build.vol(Vector3i(32, 12, 28))
	for x in [4, 25]:
		b(v, Vector3i(x, 0, 2), Vector3i(3, 2, 24), "metal_teal")
		for z in [8, 18]:
			b(v, Vector3i(x, 2, z), Vector3i(2, 7, 2), "metal_dark")
	for z in [2, 23]:
		b(v, Vector3i(0, 5, z), Vector3i(32, 1, 4), "wood")
	for z in range(8, 21, 3):
		b(v, Vector3i(0, 9, z), Vector3i(32, 1, 2), "wood_light")
	b(v, Vector3i(8, 10, 12), Vector3i(5, 1, 4), "curtain_red")
	b(v, Vector3i(18, 10, 14), Vector3i(3, 2, 3), "metal_white")
	return v


static func pergola() -> VoxelVolume:
	var v := Build.vol(Vector3i(54, 34, 42))
	for x in [1, 50]:
		for z in [1, 38]:
			b(v, Vector3i(x, 0, z), Vector3i(3, 32, 3), "wood_dark")
	for x in [0, 50]:
		b(v, Vector3i(x, 29, 0), Vector3i(4, 3, 42), "wood")
	for z in range(0, 42, 5):
		b(v, Vector3i(0, 32, z), Vector3i(54, 2, 2), "wood_light")
	for x in [1, 51]:
		for z in range(6, 36, 5):
			b(v, Vector3i(x, 2, z), Vector3i(2, 20, 1), "wood")
		for y in [4, 10, 16, 21]:
			b(v, Vector3i(x, y, 3), Vector3i(2, 1, 36), "wood_light")
	# Vines sit on the trellis, leaving the center open as an escape route.
	for z in [4, 18, 30]:
		b(v, Vector3i(0, 21, z), Vector3i(5, 7, 7), "leaf_dark")
		b(v, Vector3i(48, 26, z), Vector3i(6, 6, 6), "birch_leaf")
	return v


static func table_tennis() -> VoxelVolume:
	var v := Build.vol(Vector3i(28, 12, 16))
	SchoolRooms.desk(v, Vector3i.ZERO, 28, 16, "metal_blue", 8)
	for z in [0, 15]:
		b(v, Vector3i(0, 7, z), Vector3i(28, 1, 1), "metal_white")
	for x in [0, 27]:
		b(v, Vector3i(x, 7, 0), Vector3i(1, 1, 16), "metal_white")
	b(v, Vector3i(0, 7, 8), Vector3i(28, 1, 1), "metal_white")
	for z in range(0, 16, 2):
		b(v, Vector3i(14, 8, z), Vector3i(1, 3, 1), "metal_dark")
	b(v, Vector3i(14, 11, 0), Vector3i(1, 1, 16), "metal_white")
	return v


static func bin() -> VoxelVolume:
	var v := Build.vol(Vector3i(9, 13, 9))
	b(v, Vector3i(1, 0, 1), Vector3i(7, 2, 7), "metal_dark")
	for x in [0, 7]:
		b(v, Vector3i(x, 2, 0), Vector3i(2, 9, 9), "metal_teal")
	for z in [0, 7]:
		b(v, Vector3i(1, 2, z), Vector3i(7, 9, 2), "metal_teal")
	b(v, Vector3i(0, 11, 0), Vector3i(9, 2, 9), "metal_dark")
	b(v, Vector3i(2, 11, 2), Vector3i(5, 2, 5), "")
	for y in [3, 6, 9]:
		b(v, Vector3i(2, y, 8), Vector3i(5, 1, 1), "metal")
	return v


static func trolley() -> VoxelVolume:
	var v := Build.vol(Vector3i(22, 19, 12))
	for x in [2, 18]:
		for z in [0, 10]:
			v.fill_cylinder(Vector3(x, 2, z), 2, 2, 2, VoxMat.id("rubber"))
	for y in [4, 12]:
		b(v, Vector3i(1, y, 1), Vector3i(20, 1, 10), "wood")
	for x in [1, 20]:
		for z in [1, 10]:
			b(v, Vector3i(x, 4, z), Vector3i(1, 14, 1), "metal_teal")
	b(v, Vector3i(20, 17, 1), Vector3i(1, 1, 10), "metal_dark")
	for x in [3, 11]:
		b(v, Vector3i(x, 13, 3), Vector3i(6, 3, 6), "brick")
		b(v, Vector3i(x + 1, 16, 4), Vector3i(4, 3, 4), "birch_leaf")
	return v


static func equipment_cabinet() -> VoxelVolume:
	var v := Build.vol(Vector3i(20, 28, 16))
	b(v, Vector3i.ZERO, Vector3i(20, 2, 16), "concrete")
	SchoolInteriors._wardrobe(v, Vector3i(3, 2, 1))
	b(v, Vector3i(2, 26, 0), Vector3i(16, 2, 15), "metal_teal")
	return v


static func planter_tree(seed: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(24, 32, 24))
	b(v, Vector3i(1, 0, 1), Vector3i(22, 4, 22), "brick_tan")
	b(v, Vector3i(3, 3, 3), Vector3i(18, 1, 18), "dirt")
	b(v, Vector3i(11, 4, 11), Vector3i(2, 16, 2), "wood_dark")
	v.fill_ellipsoid_noise(Vector3(12, 23, 12), Vector3(10, 8, 10), VoxMat.ids("birch_leaf"), 0.94, 0.14, seed)
	return v


static func bicycle() -> VoxelVolume:
	var v := Build.vol(Vector3i(21, 14, 6))
	for x in [4, 16]:
		v.fill_cylinder(Vector3(x, 4, 2), 4, 2, 2, VoxMat.id("rubber"))
		v.fill_cylinder(Vector3(x, 4, 2), 2.6, 2, 2, 0)
		b(v, Vector3i(x - 2, 4, 2), Vector3i(5, 1, 2), "metal")
	for i in 8:
		b(v, Vector3i(5 + i, 4 + i / 2, 2), Vector3i(2, 1, 2), "metal_blue")
		b(v, Vector3i(9 + i, 8 - i / 2, 2), Vector3i(2, 1, 2), "metal_blue")
	b(v, Vector3i(7, 5, 2), Vector3i(1, 7, 2), "metal")
	b(v, Vector3i(5, 11, 1), Vector3i(5, 1, 4), "tank_black")
	b(v, Vector3i(16, 5, 2), Vector3i(1, 8, 2), "metal")
	b(v, Vector3i(16, 12, 0), Vector3i(1, 1, 6), "metal_dark")
	return v


static func classroom_detail(v: VoxelVolume, at: Vector3i, kind: String) -> void:
	# Wall-backed display has a 16 x 7 footprint and a clear front aisle.
	SchoolRooms.desk(v, at, 16, 7, "wood_dark", 8)
	match kind:
		"bio":
			b(v, at + Vector3i(2, 8, 1), Vector3i(12, 7, 5), "glass")
			b(v, at + Vector3i(3, 8, 2), Vector3i(10, 1, 3), "dirt")
			for x in [4, 8, 11]:
				b(v, at + Vector3i(x, 9, 3), Vector3i(1, 4, 1), "brand_green")
		"art":
			b(v, at + Vector3i(2, 8, 1), Vector3i(11, 9, 1), "wood")
			b(v, at + Vector3i(3, 9, 2), Vector3i(9, 7, 1), "curtain_beige")
			b(v, at + Vector3i(4, 10, 3), Vector3i(5, 2, 1), "metal_blue")
			b(v, at + Vector3i(9, 13, 3), Vector3i(2, 2, 1), "metal_yellow")
		"music":
			for x in [1, 10]:
				b(v, at + Vector3i(x, 8, 1), Vector3i(5, 9, 4), "wood_dark")
				v.fill_cylinder(Vector3(at + Vector3i(x + 2, 12, 5)), 2, 1, 2, VoxMat.id("tank_black"))
		_:
			for x in [1, 7, 12]:
				b(v, at + Vector3i(x, 8, 2), Vector3i(3, 2, 4), SchoolRooms.BOOKS[x % 5])
			b(v, at + Vector3i(3, 11, 1), Vector3i(1, 5, 1), "metal_dark")
			b(v, at + Vector3i(1, 15, 0), Vector3i(5, 1, 3), "metal_teal")
