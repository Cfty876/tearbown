class_name DistrictHides
extends Node3D

signal search_requested(spot_id: int)

var player: Player
var spots: Array[Dictionary] = []
var remote_spot := -1
var remote_spots: Array[int] = []
var search_all := false
var _model_open := {}
var _animations := {}
var _entry_point := Vector3.ZERO


func _ready() -> void:
	var wardrobe := Build.vol(Vector3i(10, 22, 3))
	wardrobe.fill_box(Vector3i.ZERO, Vector3i(10, 22, 1), VoxMat.id("wood_dark"))
	wardrobe.fill_box(Vector3i(1, 1, 1), Vector3i(9, 21, 2), VoxMat.id("wood"))
	wardrobe.fill_box(Vector3i(7, 9, 2), Vector3i(9, 11, 3), VoxMat.id("metal"))
	var wood_mesh := VoxModel.mesh(wardrobe, 0.1, Vector3.ZERO)
	var school_wood := _school_panel(false)
	var school_metal := _school_panel(true)
	var cloth := Build.vol(Vector3i(16, 18, 2))
	for x in 16:
		var shade := VoxMat.id("curtain_green" if x % 4 < 2 else "curtain_beige")
		cloth.fill_box(Vector3i(x, 0, x % 2), Vector3i(x + 1, 18, x % 2 + 1), shade)
	var cloth_mesh := VoxModel.mesh(cloth, 0.1, Vector3.ZERO)
	var cap := Build.vol(Vector3i(9, 18, 2))
	for x in 9:
		cap.fill_box(Vector3i(x, 0, x % 2), Vector3i(x + 1, 18, x % 2 + 1),
			VoxMat.id("curtain_green" if x % 4 < 2 else "curtain_beige"))
	var cap_mesh := VoxModel.mesh(cap, 0.1, Vector3.ZERO)
	for info in spots:
		var building: VoxelObject = info.building
		var model := MeshInstance3D.new()
		model.mesh = cloth_mesh if info.bath else wood_mesh
		if info.get("school", false):
			model.mesh = school_metal if info.get("locker", false) else school_wood
		model.position = info.panel * 0.1
		model.rotation.y = -PI * 0.5 if info.bath else float(info.get("yaw", 0.0))
		model.visibility_range_end = 21.0
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		building.add_child(model)
		if info.bath:
			model.scale.x = 0.17
			var rim := (Vector3(info.panel) - Vector3(8.5, 4, 1.4)) * 0.1
			var covers: Array[MeshInstance3D] = [model]
			for side in [[cloth_mesh, Vector3(0.05, 0.4, 1.68), PI * 0.5],
					[cap_mesh, Vector3(0.88, 0.4, 0.13), PI],
					[cap_mesh, Vector3(0.0, 0.4, 1.70), 0.0]]:
				var cover := MeshInstance3D.new()
				cover.mesh = side[0]
				cover.position = rim + Vector3(side[1])
				cover.rotation.y = side[2]
				cover.scale.x = 0.02
				cover.visibility_range_end = model.visibility_range_end
				cover.cast_shadow = model.cast_shadow
				building.add_child(cover)
				covers.append(cover)
			var canopy := MeshInstance3D.new()
			canopy.mesh = cap_mesh
			canopy.position = rim + Vector3(0, 2.16, 1.70)
			canopy.rotation.x = -PI * 0.5
			canopy.scale.x = 0.02
			canopy.visibility_range_end = model.visibility_range_end
			canopy.cast_shadow = model.cast_shadow
			building.add_child(canopy)
			covers.append(canopy)
			info["covers"] = covers
		info["model"] = model


static func _school_panel(metal: bool) -> Mesh:
	var panel := Build.vol(Vector3i(10, 20, 3))
	DistrictSecretProps.box(panel, Vector3i.ZERO, Vector3i(10, 20, 1), "metal_dark" if metal else "wood_dark")
	DistrictSecretProps.box(panel, Vector3i(1, 1, 1), Vector3i(8, 18, 1), "metal_teal" if metal else "wood")
	DistrictSecretProps.box(panel, Vector3i(7, 8, 2), Vector3i(2, 3, 1), "metal")
	if metal:
		for y in [14, 16, 18]:
			DistrictSecretProps.box(panel, Vector3i(2, y, 1), Vector3i(5, 1, 1), "tank_black")
		DistrictSecretProps.box(panel, Vector3i(2, 10, 2), Vector3i(3, 2, 1), "curtain_beige")
	else:
		for y in [3, 14]:
			DistrictSecretProps.box(panel, Vector3i(2, y, 1), Vector3i(6, 3, 1), "wood_light")
	return VoxModel.mesh(panel, 0.1, Vector3.ZERO)


func target() -> int:
	if player.hide_spot >= 0:
		return player.hide_spot
	var at := player.camera.global_position
	var direction := player.aim_dir()
	var best := 2.35 * 2.35
	var candidate := -1
	for i in spots.size():
		var info := spots[i]
		var building := info.building as VoxelObject
		if not is_instance_valid(building):
			continue
		var panel := panel_focus(info)
		var offset := panel - at
		var distance := offset.length_squared()
		if distance < best and direction.dot(offset.normalized()) > 0.58:
			best = distance
			candidate = i
	if candidate >= 0 and not _accessible(candidate, player.global_position):
		return -1
	return candidate


func panel_focus(info: Dictionary) -> Vector3:
	var offset := Basis(Vector3.UP, float(info.get("yaw", 0.0))) * Vector3(0.38, 0.9, 0.38)
	return info.building.to_global(Vector3(info.panel) * 0.1 + offset)


func hint(id := -2) -> String:
	if id == -2:
		id = target()
	if id < 0:
		return ""
	if player.hide_spot >= 0:
		return "%s — выйти из укрытия" % GameControls.key_name("grab")
	if search_all or id == remote_spot or id in remote_spots:
		return "%s — проверить укрытие" % GameControls.key_name("grab")
	return "%s — %s" % [GameControls.key_name("grab"), "залезть в ванну" if spots[id].bath else "залезть в шкаф"]


func interact() -> bool:
	var id := target()
	if id < 0:
		return false
	var info := spots[id]
	var building := info.building as VoxelObject
	if not is_instance_valid(building):
		reset_player()
		return false
	if (search_all or id == remote_spot or id in remote_spots) and player.hide_spot < 0:
		search_requested.emit(id)
		return true
	if player.hide_spot >= 0:
		var out := building.to_global(Vector3(info.front) * 0.1)
		var landing := player._clear_exit(_entry_point + Vector3.UP * 0.6)
		if not landing.is_finite():
			for offset: Vector3 in [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4)]:
				landing = player._clear_exit(out + building.global_basis * offset + Vector3.UP * 0.7)
				if landing.is_finite():
					break
		if not landing.is_finite():
			get_tree().call_group("hud", "message", "Выход из укрытия перекрыт", 2.0)
			return true
		player.global_position = landing
		reset_player()
	else:
		var center := building.to_global(Vector3(info.center) * 0.1)
		player._set_crouch(bool(info.bath))
		if not _has_room(center):
			get_tree().call_group("hud", "message", "В укрытии нет места", 1.8)
			return true
		player.release_grab(false)
		player.tools.cancel_placement()
		_entry_point = player.global_position
		player.hide_spot = id
		player.global_position = center
		player.velocity = Vector3.ZERO
		_update_model(id, true)
	player.reset_physics_interpolation()
	VoxelWorld.instance.sfx.play("hide_slide" if info.bath else "hide_wood", player.global_position, -11.0)
	return true


func reset_player() -> void:
	var id := player.hide_spot
	player.hide_spot = -1
	if id >= 0:
		_update_model(id, id == remote_spot or id in remote_spots)


func set_remote(id: int) -> void:
	if id == remote_spot:
		return
	var old := remote_spot
	remote_spot = id if id >= 0 and id < spots.size() else -1
	if old >= 0:
		_update_model(old, old == player.hide_spot)
	if remote_spot >= 0:
		_update_model(remote_spot, true)


func set_remote_spots(ids: Array[int]) -> void:
	var old := remote_spots
	remote_spots = ids
	for id in old:
		if id not in ids:
			_update_model(id, id == player.hide_spot or id == remote_spot)
	for id in ids:
		if id not in old:
			_update_model(id, true)


func _accessible(id: int, at: Vector3) -> bool:
	if id < 0 or id >= spots.size():
		return false
	var info := spots[id]
	var building := info.building as VoxelObject
	if not is_instance_valid(building):
		return false
	var front := building.to_global(Vector3(info.front) * 0.1)
	if at.distance_squared_to(front) > 4.0:
		return false
	return VoxelWorld.instance.raycast(at + Vector3.UP * 0.9, front + Vector3.UP * 0.8).is_empty()


func _has_room(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.10 if player.crouching else 1.79
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * shape.height * 0.5)
	query.collision_mask = Layers.SOLID
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _update_model(id: int, occupied: bool) -> void:
	var info := spots[id]
	var model := info.model as MeshInstance3D
	if not is_instance_valid(model) or _model_open.get(id) == occupied:
		return
	_model_open[id] = occupied
	if _animations.has(id):
		(_animations[id] as Tween).kill()
	var animation := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if info.bath:
		animation.set_parallel()
		for cover: MeshInstance3D in info.covers:
			animation.tween_property(cover, "scale:x", 1.0 if occupied else (0.17 if cover == model else 0.02), 0.3)
	else:
		var yaw := float(info.get("yaw", 0.0))
		animation.tween_property(model, "rotation:y", yaw - 0.97, 0.17)
		animation.tween_property(model, "rotation:y", yaw, 0.21)
	_animations[id] = animation
