class_name ToolConstruction
extends Node3D

const CLOTH_SHADER := preload("res://shaders/chameleon_cloth.gdshader")
const LIMIT := 32
const MAX_LENGTH := 7.0
const MAX_BOARD_LENGTH := 5.0
const MAX_BOARD_WIDTH := 0.85
const PATCH_EDGE := 5
const RANGE := 8.0
const THICKNESS := 0.08

var world: VoxelWorld
var network_enabled := false
var round_number := 0
var _pieces := {}
var _next_id := 1


class FabricSurface extends StaticBody3D:
	var piece_id: int
	var manager: ToolConstruction

	func strike() -> void:
		manager.break_piece(piece_id)


static func shape_between(first: Vector3, last: Vector3, normal: Vector3, width: float, roll: float) -> Transform3D:
	var span := last - first
	var along := span.normalized() if span.length_squared() > 0.0001 else Vector3.UP
	var across := along.cross(normal)
	if across.length_squared() < 0.001:
		across = along.cross(Vector3.RIGHT if absf(along.x) < 0.85 else Vector3.UP)
	across = across.normalized().rotated(along, roll)
	var face := across.cross(along).normalized()
	var scale_value := Vector3(width, clampf(span.length(), 0.1, MAX_LENGTH), THICKNESS)
	return Transform3D(Basis(across, along, face) * Basis.from_scale(scale_value), first + span * 0.5 + normal * 0.045)


static func sample_patch(anchor: VoxelObject, at: Vector3, normal: Vector3, tangent: Vector3, up: Vector3, fallback: Color) -> String:
	var bytes := PackedByteArray()
	var half := (PATCH_EDGE - 1) * 0.5
	for row in PATCH_EDGE:
		for col in PATCH_EDGE:
			var point := at + (tangent * (col - half) + up * (row - half)) * VoxelObject.VS
			var voxel := anchor.voxel_at_hit(point, normal)
			var tint := VoxMat.color_of(voxel) if voxel > 0 else fallback
			bytes.append(tint.r8)
			bytes.append(tint.g8)
			bytes.append(tint.b8)
	return Marshalls.raw_to_base64(bytes)


func placed_piece(id: int) -> Node3D:
	return _pieces.get(id) as Node3D


static func board_volume(size: Vector3i) -> VoxelVolume:
	var volume := Build.vol(size)
	volume.fill_planks(Vector3i.ZERO, size, 0, 1, 2, VoxMat.ids("wood"), 17)
	var trim := VoxMat.id("wood_dark")
	var inset := clampi(roundi(size.y * 0.11), 1, 4)
	var band := maxi(1, roundi(size.y * 0.055))
	for edge in [inset, size.y - inset - band]:
		volume.fill_box(Vector3i(0, edge, 0), Vector3i(size.x, edge + band, 1), trim)
	return volume


func preview_material(fabric: bool, tint: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(tint.lightened(0.20), 0.45) if fabric else Color(0.91, 0.67, 0.39, 0.4)
	return mat


func _fabric_material(packet: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOTH_SHADER
	var tint := Color.from_string(str(packet.get("color", "")), Color.GRAY)
	mat.set_shader_parameter("fabric_tint", tint)
	mat.set_shader_parameter("source_material", clampi(int(packet.get("source_material", 0)), 0, VoxMat.EMISSIVE))
	mat.set_shader_parameter("motif", clampi(int(packet.get("motif", 0)), 0, 7))
	var mapping: Variant = packet.get("mapping", [])
	if mapping is Array and mapping.size() == 6:
		mat.set_shader_parameter("print_axes", Vector4(float(mapping[0]), float(mapping[1]), float(mapping[2]), float(mapping[3])))
		mat.set_shader_parameter("print_origin", Vector2(float(mapping[4]), float(mapping[5])))
	var patch := str(packet.get("patch", ""))
	var pixels := Marshalls.base64_to_raw(patch) if patch.length() == PATCH_EDGE * PATCH_EDGE * 4 else PackedByteArray()
	if pixels.size() == PATCH_EDGE * PATCH_EDGE * 3:
		var sample := Image.create_from_data(PATCH_EDGE, PATCH_EDGE, false, Image.FORMAT_RGB8, pixels)
		mat.set_shader_parameter("borrowed_patch", ImageTexture.create_from_image(sample))
		mat.set_shader_parameter("has_patch", true)
	return mat


func submit(fabric: bool, xf: Transform3D, tint: Color, anchor: VoxelObject, actor: Vector3, motif := 0, patch := "", mapping: Array = [], source_material := 0) -> bool:
	if not _valid_shape(xf, fabric, actor):
		return false
	var packet := {"k": "place", "cloth": fabric, "x": _pack(xf.basis.x), "y": _pack(xf.basis.y),
		"z": _pack(xf.basis.z), "p": _pack(xf.origin), "color": tint.to_html(false),
		"anchor": anchor.network_id if is_instance_valid(anchor) else 0, "round": round_number,
		"motif": motif, "patch": patch, "mapping": mapping, "source_material": source_material}
	if network_enabled and not WebSession.is_host:
		packet["k"] = "place_request"
		return WebSession.send(packet)
	_accept(packet, xf, anchor)
	return true


func receive(packet: Dictionary, actor: Vector3) -> void:
	if int(packet.get("round", -1)) != round_number:
		return
	match str(packet.get("k", "")):
		"place_request":
			if WebSession.is_host:
				var xf := _transform(packet)
				if _valid_shape(xf, bool(packet.get("cloth", false)), actor):
					_accept(packet, xf)
		"place":
			if not WebSession.is_host:
				_spawn(packet, _transform(packet))
		"place_gone":
			if not WebSession.is_host:
				_remove(int(packet.get("id", 0)))


func _valid_shape(xf: Transform3D, fabric: bool, actor: Vector3) -> bool:
	if not xf.is_finite() or actor.distance_to(xf.origin) > RANGE + 1.0:
		return false
	var size := xf.basis.get_scale()
	var max_length := MAX_LENGTH if fabric else MAX_BOARD_LENGTH
	var max_width := 2.85 if fabric else MAX_BOARD_WIDTH
	if size.x < 0.19 or size.x > max_width + 0.001 or size.y < 0.36 or size.y > max_length + 0.001 or not is_equal_approx(size.z, THICKNESS):
		return false
	if fabric:
		return true
	var local := xf.affine_inverse() * (actor + Vector3.UP * 0.9)
	return absf(local.x) > 0.5 + 0.32 / size.x or absf(local.y) > 0.5 + 0.8 / size.y or absf(local.z) > 0.5 + 0.32 / size.z


func _accept(packet: Dictionary, xf: Transform3D, anchor: VoxelObject = null) -> void:
	if _pieces.size() >= LIMIT:
		break_piece(int(_pieces.keys()[0]))
	packet["k"] = "place"
	packet["id"] = _next_id
	_next_id += 1
	_spawn(packet, xf, anchor)
	if network_enabled:
		WebSession.send(packet)


func _spawn(packet: Dictionary, xf: Transform3D, anchor: VoxelObject = null) -> void:
	var id := int(packet.get("id", 0))
	if id <= 0 or _pieces.has(id):
		return
	if not is_instance_valid(anchor):
		anchor = world.network_objects.get(int(packet.get("anchor", 0))) as VoxelObject
	var parent: Node3D = anchor if is_instance_valid(anchor) else self
	var pose := Transform3D(xf.basis.orthonormalized(), xf.origin)
	var size := xf.basis.get_scale()
	var piece: Node3D
	if bool(packet.get("cloth", false)):
		piece = _spawn_fabric(id, packet, parent, pose, size)
	else:
		piece = _spawn_board(id, parent, pose, size)
	_pieces[id] = piece
	piece.tree_exited.connect(func(): _pieces.erase(id))
	world.sfx.play("click", xf.origin, -8.0, 0.83)


func _spawn_fabric(id: int, packet: Dictionary, parent: Node3D, pose: Transform3D, size: Vector3) -> FabricSurface:
	var body := FabricSurface.new()
	body.piece_id = id
	body.manager = self
	body.collision_layer = Layers.CLOTH
	body.collision_mask = 0
	body.transform = parent.global_transform.affine_inverse() * pose
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	var model := MeshInstance3D.new()
	var fabric_mesh := QuadMesh.new()
	fabric_mesh.size = Vector2(size.x, size.y)
	model.mesh = fabric_mesh
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.material_override = _fabric_material(packet)
	body.add_child(model)
	return body


func _spawn_board(id: int, parent: Node3D, pose: Transform3D, size: Vector3) -> VoxelObject:
	var dims := Vector3i(roundi(size.x / VoxelObject.VS), roundi(size.y / VoxelObject.VS), 1)
	var board := VoxelObject.new()
	board.setup(board_volume(dims), true, Vector3i(16, 16, 4))
	board.label = "Доска"
	# Placed pieces have their own ID range so detached bodies cannot take their IDs.
	board.network_id = -id if network_enabled else 0
	var support := parent as VoxelObject
	board.follow_static_transform = support != null and (not support.static_mode or support.follow_static_transform)
	pose.origin -= pose.basis * (Vector3(dims) * VoxelObject.VS * 0.5)
	board.transform = parent.global_transform.affine_inverse() * pose
	parent.add_child(board)
	return board


func break_piece(id: int) -> void:
	if not _pieces.has(id) or (network_enabled and not WebSession.is_host):
		return
	_remove(id)
	if network_enabled:
		WebSession.send({"k": "place_gone", "id": id, "round": round_number})


func _remove(id: int) -> void:
	var body := _pieces.get(id) as Node3D
	_pieces.erase(id)
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	world.sfx.play("cloth_rip" if body is FabricSurface else "wood_break", body.global_position, -5.0)
	world.fx.dust(body.global_position, Color("#ac9780"), 0.55)
	body.set_deferred("collision_layer", 0)
	body.queue_free()


func clear_round() -> void:
	for body in _pieces.values():
		if is_instance_valid(body):
			body.collision_layer = 0
			body.queue_free()
	_pieces.clear()


func _transform(packet: Dictionary) -> Transform3D:
	return Transform3D(Basis(_vec(packet.get("x")), _vec(packet.get("y")), _vec(packet.get("z"))), _vec(packet.get("p")))


func _pack(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _vec(v: Variant) -> Vector3:
	if not v is Array or v.size() != 3:
		return Vector3.INF
	return Vector3(float(v[0]), float(v[1]), float(v[2]))
