class_name HideLevel
## Small network arena built from the same voxel prefabs as the rest of the game.

const HALF := 15.0
const SPAWNS := [Vector3(0, 1.05, 11.5), Vector3(0, 1.05, -11.5)]
var world: VoxelWorld
var spawn := Vector3.ZERO
var _sandbox := false


func _init(voxel_world: VoxelWorld, sandbox := false) -> void:
	world = voxel_world
	_sandbox = sandbox
	spawn = SPAWNS[0 if sandbox or WebSession.is_host else 1]


func build() -> void:
	for z in 6:
		for x in 6:
			var tile_size := Vector3i(50, 10, 50)
			var floor_tile := Build.vol(tile_size)
			floor_tile.fill_box(Vector3i.ZERO, Vector3i(50, 9, 50), VoxMat.id("concrete"))
			floor_tile.fill_box(Vector3i(0, 9, 0), Vector3i(50, 10, 50), VoxMat.id("gravel"))
			Build.place(world, floor_tile, Vector3(-12.5 + x * 5.0, 0, -12.5 + z * 5.0),
				true, 0.0, "Покрытие", tile_size)
	for i in 4:
		var corner := Vector3(-8.0 + float(i % 2) * 16.0, 1.0, -6.5 + float(i / 2) * 13.0)
		_shed(corner, i)
	for i in 14:
		var x := -11.0 + float(i % 7) * 3.55
		var z := -2.65 if i < 7 else 3.2
		var crate := Build.vol(Vector3i(11, 13 + i % 4, 13))
		crate.fill_box(Vector3i.ZERO, crate.get_size(), VoxMat.id("wood"))
		Build.place(world, crate, Vector3(x, 1.0, z), false, float(i * 17 % 33), "Ящик")
	for at in [Vector3(-12.2, 1, -0.7), Vector3(12.2, 1, 0.7), Vector3(0, 1, -7)]:
		var cover := Build.vol(Vector3i(38, 23, 8))
		cover.fill_box(Vector3i.ZERO, cover.get_size(), VoxMat.id("brick"))
		Build.place(world, cover, at, true, 0.0, "Перегородка")
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.STATIC
	ground.position.y = -0.55
	var foundation := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	foundation.shape = box
	ground.add_child(foundation)
	world.add_child(ground)
	if _sandbox:
		var car := Build.place(world, Build.car("metal_blue", 17),
			Vector3(7.5, 1.02, 11.0), false, 0.0, "Машина")
		VoxelVehicle.attach(car, Build.car_hubs(), Vector3.LEFT)


func _shed(at: Vector3, index: int) -> void:
	var v := Build.vol(Vector3i(58, 35, 54))
	Build.walls(v, 0, 0, 58, 54, 0, 31, 3, "brick", 23 + index)
	Build.door(v, 2, 51, 3, 22, 0, 14, 23)
	Build.window(v, 2, 0, 3, 12, 12, 17, 11)
	Build.window(v, 0, 0, 3, 26, 12, 14, 11)
	v.fill_box(Vector3i(0, 31, 0), Vector3i(58, 34, 54), VoxMat.id("wood_dark"))
	v.fill_box(Vector3i(4, 0, 8), Vector3i(31, 20, 11), VoxMat.id("wood"))
	Build.place(world, v, at, true, float(index % 2) * 180.0, "Укрытие")
