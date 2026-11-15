class_name GadgetModels
extends RefCounted


static func volume(item: int) -> VoxelVolume:
	var v := Build.vol(Vector3i(19, 29, 19))
	match item:
		GameGadgets.FLASH:
			_ring(v, 1, 21, 6.5, "metal_white")
			for y in [2, 9, 17, 21]:
				_ring(v, y, 2, 6.9, "metal_dark")
			for y in [6, 13]:
				for x in [6, 11]:
					_box(v, Vector3i(x, y, 15), Vector3i(2, 2, 1), "metal_dark")
					_box(v, Vector3i(15, y, x), Vector3i(1, 2, 2), "metal_dark")
			_ring(v, 23, 3, 3.3, "metal")
			_box(v, Vector3i(9, 22, 7), Vector3i(8, 2, 3), "metal")
			_box(v, Vector3i(14, 24, 7), Vector3i(2, 3, 3), "metal_yellow")
		GameGadgets.FIRE:
			_ring(v, 1, 16, 6.5, "glass")
			_ring(v, 2, 13, 5.8, "wood_dark")
			_ring(v, 14, 4, 6.2, "metal_green")
			_ring(v, 18, 2, 4.5, "metal_green")
			_ring(v, 20, 5, 2.8, "metal_green")
			_box(v, Vector3i(5, 6, 14), Vector3i(8, 7, 2), "curtain_beige")
			_box(v, Vector3i(8, 23, 8), Vector3i(4, 5, 3), "curtain_red")
			_box(v, Vector3i(11, 25, 8), Vector3i(3, 2, 3), "wood_light")
		GameGadgets.SODA:
			_ring(v, 3, 20, 6.5, "metal_teal")
			for y in [3, 22]:
				_ring(v, y, 1, 6.6, "metal")
			_box(v, Vector3i(6, 8, 15), Vector3i(7, 9, 1), "pvc")
			for y in [10, 13, 16]:
				_box(v, Vector3i(7 + (y % 2), y, 16), Vector3i(4, 1, 1), "metal_red")
			_box(v, Vector3i(7, 23, 8), Vector3i(5, 1, 3), "metal_dark")
		GameGadgets.CLOCK:
			for y in [1, 20]:
				_box(v, Vector3i(6, y, 7), Vector3i(7, 8, 4), "wood_dark")
				_box(v, Vector3i(7, y + 1, 11), Vector3i(5, 1, 1), "metal_yellow")
			v.fill_cylinder(Vector3(9, 14, 6), 8.1, 5, 2, VoxMat.id("metal_yellow"))
			v.fill_cylinder(Vector3(9, 14, 10), 6.7, 2, 2, VoxMat.id("pvc"))
			for p in [Vector2i(9, 9), Vector2i(9, 19), Vector2i(4, 14), Vector2i(14, 14)]:
				_box(v, Vector3i(p.x, p.y, 12), Vector3i(1, 1, 1), "metal_dark")
			_box(v, Vector3i(9, 14, 12), Vector3i(1, 5, 1), "metal_dark")
			_box(v, Vector3i(9, 14, 12), Vector3i(4, 1, 1), "metal_red")
			_box(v, Vector3i(16, 13, 7), Vector3i(3, 3, 3), "metal")
	return v


static func _ring(v: VoxelVolume, y: int, height: int, radius: float, swatch: String) -> void:
	v.fill_cylinder(Vector3(9, y, 9), radius, height, 1, VoxMat.id(swatch))


static func _box(v: VoxelVolume, at: Vector3i, extent: Vector3i, swatch: String) -> void:
	v.fill_box(at, at + extent, VoxMat.id(swatch))
