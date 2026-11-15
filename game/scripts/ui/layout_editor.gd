class_name LayoutEditor
extends CanvasLayer

const PICK := Layers.SOLID | Layers.SECRET | Layers.CLOTH
const REACH := 280.0

var world: VoxelWorld
var player: Player
var hud: Hud
var active := false

var _camera: Camera3D
var _marker: MeshInstance3D
var _panel: PanelContainer
var _list: ItemList
var _search: LineEdit
var _title: Label
var _status: Label
var _note: TextEdit
var _fields: Array[SpinBox] = []
var _geometry := {}
var _ordered: Array[Node3D] = []
var _listed: Array[Node3D] = []
var _selection: Node3D
var _drafts := {}
var _fragments: Array[Dictionary] = []
var _undo: Array[Dictionary] = []
var _flying := false
var _yaw := 0.0
var _pitch := 0.0
var _dragging := false
var _drag_before := Transform3D.IDENTITY
var _drag_plane: Plane
var _drag_offset := Vector3.ZERO
var _region_mode := false
var _corners: Array[Vector3] = []
var _corner_objects: Array[Node3D] = []
var _last_file := ""
var _busy := false
var _tools_visible := true
var _avatar_visible := true
var _hud_visible := true
var _occlusion := true


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_panel()
	hide()


func open() -> void:
	if active or player.dead or player.vehicle or player.transit_active or player.hide_spot >= 0:
		return
	active = true
	player.release_grab(false)
	player.tools.cancel_placement()
	_tools_visible = player.tools.visible
	_hud_visible = hud.visible
	_occlusion = get_viewport().use_occlusion_culling
	player.tools.hide()
	if is_instance_valid(player.avatar):
		_avatar_visible = player.avatar.visible
		player.avatar.hide()
	hud.hide()
	get_viewport().use_occlusion_culling = false
	get_tree().paused = true
	_camera = Camera3D.new()
	_camera.fov = player.camera.fov
	_camera.near = 0.04
	_camera.far = 580.0
	world.add_child(_camera)
	_camera.global_transform = player.camera.global_transform
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x
	_camera.make_current()
	_marker = MeshInstance3D.new()
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_marker)
	_collect()
	for object: Node3D in _ordered:
		_preview_draft(object)
	for fragment: Dictionary in _fragments:
		if is_instance_valid(fragment.source):
			_mount_fragment(fragment)
			_preview_draft(fragment.node)
	_update_list()
	_show_selection()
	_say("ЛКМ — выбрать и перетащить. ПКМ + WASD — полёт.")
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _preview_draft(object: Node3D) -> void:
	var id := str(_geometry[object].id)
	if _drafts.has(id):
		_set_pose(object, _drafts[id].after)


func close() -> void:
	if not active or _busy:
		return
	_end_drag()
	# Return parents before their children so every authored transform is restored.
	for object: Node3D in _ordered:
		if is_instance_valid(object) and _drafts.has(_geometry[object].id):
			_set_pose(object, _geometry[object].original)
	for fragment: Dictionary in _fragments:
		_unmount_fragment(fragment)
	active = false
	_selection = null
	_corners.clear()
	_corner_objects.clear()
	_region_mode = false
	_flying = false
	player.camera.make_current()
	_camera.queue_free()
	_marker.queue_free()
	player.tools.visible = _tools_visible
	if is_instance_valid(player.avatar):
		player.avatar.visible = _avatar_visible
	hud.visible = _hud_visible
	get_viewport().use_occlusion_culling = _occlusion
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if player.touch_mode else Input.MOUSE_MODE_CAPTURED


func _collect() -> void:
	_geometry.clear()
	_ordered.clear()
	_visit(world)
	if is_instance_valid(world.secrets):
		_visit(world.secrets)


func _visit(root: Node) -> void:
	for child in root.get_children():
		if child is VoxelObject:
			_register(child, child.label if not child.label.is_empty() else "Воксельный объект")
			for prop in child.get_children():
				if prop is VoxelObject:
					_register(prop, prop.label if not prop.label.is_empty() else "Прикреплённый объект")
		elif child is AnimatableBody3D or child is StaticBody3D:
			var label := str(child.get_meta("secret_label", child.get_meta("layout_label", child.name)))
			_register(child, label if not label.is_empty() else str(child.get_meta("secret_key", child.name)))
			_visit(child)
		elif child is Node3D and not (child is Camera3D or child is GeometryInstance3D):
			_visit(child)


func _register(object: Node3D, label: String) -> void:
	var origin := LayoutFeedback.point(object.get_meta("layout_origin", object.global_position))
	var key := str(object.get_meta("layout_fragment", "%s · %s · %s" % [label, object.get_meta("secret_key", ""), origin]))
	_geometry[object] = {"label": label, "id": key, "original": object.global_transform,
		"locked": object.has_meta("layout_locked") or (object is VoxelObject and label in ["Местность", "Грунт", "terrain", "ground"])}
	_ordered.append(object)


func _process(delta: float) -> void:
	if not active or not _flying:
		return
	var h := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var vertical := Input.get_axis("crouch", "jump")
	var direction := _camera.global_basis * Vector3(h.x, 0, h.y) + Vector3.UP * vertical
	var speed := 30.0 if Input.is_action_pressed("sprint") else 8.0
	_camera.position += direction.limit_length() * speed * delta


func _input(event: InputEvent) -> void:
	if not active or _busy:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _flying:
			_stop_fly()
		else:
			close()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and _flying:
		_stop_fly()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
		_end_drag()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not active or _busy:
		return
	if event is InputEventMouseMotion:
		if _flying:
			_yaw -= event.relative.x * 0.0022 * GameState.mouse_speed
			_pitch = clampf(_pitch - event.relative.y * 0.0022 * GameState.mouse_speed, -1.55, 1.55)
			_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		elif _dragging:
			_drag(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_end_drag()
			_flying = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo_move()
		elif event.keycode == KEY_B:
			_set_region(not _region_mode)


func _stop_fly() -> void:
	_flying = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _click(screen: Vector2) -> void:
	if _flying:
		screen = get_viewport().get_visible_rect().size * 0.5
	var ray := _camera.project_ray_origin(screen)
	var hit := world.raycast(ray, ray + _camera.project_ray_normal(screen) * REACH, PICK)
	if hit.is_empty():
		_say("Наведи на объект или выбери его в списке.")
		return
	var object := hit.collider as Node3D
	if _region_mode:
		if _corners.size() >= 2:
			_corners.clear()
			_corner_objects.clear()
		_corners.append(Vector3(hit.position).snapped(Vector3.ONE * 0.1))
		_corner_objects.append(object)
		_show_selection()
		return
	if not _geometry.has(object):
		_say("Эту поверхность можно отметить через «Область».")
		return
	_select(object)
	if _locked() or _flying:
		return
	_drag_before = object.global_transform
	var point: Vector3 = hit.position
	_drag_plane = Plane(_camera.global_basis.z, point)
	_drag_offset = object.global_position - point
	_dragging = true


func _drag(screen: Vector2) -> void:
	var point: Variant = _drag_plane.intersects_ray(_camera.project_ray_origin(screen), _camera.project_ray_normal(screen))
	if point == null:
		return
	var transform := _selection.global_transform
	transform.origin = _bounded(Vector3(point) + _drag_offset)
	_set_pose(_selection, transform)
	_show_selection()


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	if is_instance_valid(_selection):
		_commit(_selection, _drag_before)


func _set_pose(object: Node3D, transform: Transform3D) -> void:
	if object is VoxelObject:
		object.set_layout_pose(transform)
	else:
		object.global_transform = transform
		if object is PhysicsBody3D:
			PhysicsServer3D.body_set_state(object.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	object.reset_physics_interpolation()


func _bounded(point: Vector3) -> Vector3:
	var edge := player.border + 4.0
	return point.snapped(Vector3.ONE * 0.1).clamp(Vector3(-edge, -24, -edge), Vector3(edge, 100, edge))


func _commit(object: Node3D, before: Transform3D) -> void:
	var after := object.global_transform
	if after.is_equal_approx(before):
		return
	var entry: Dictionary = _geometry[object]
	_undo.append({"id": entry.id, "before": before})
	_record(object, after)
	_last_file = LayoutFeedback.create(_payload("transform", object))
	_say("Изменение записано в очередь." if not _last_file.is_empty() else "Не удалось записать изменение.")


func _record(object: Node3D, after: Transform3D) -> void:
	var entry: Dictionary = _geometry[object]
	if after.is_equal_approx(entry.original):
		_drafts.erase(entry.id)
	else:
		_drafts[entry.id] = {"after": after, "before": entry.original, "label": entry.label}


func _undo_move() -> void:
	while not _undo.is_empty():
		var change: Dictionary = _undo.pop_back()
		if change.has("fragment"):
			_undo_fragment(change.fragment)
			return
		for object: Node3D in _ordered:
			if not is_instance_valid(object) or _geometry[object].id != change.id:
				continue
			_set_pose(object, change.before)
			_record(object, change.before)
			_last_file = LayoutFeedback.create(_payload("undo", object))
			_show_selection()
			_say("Изменение отменено. Отмена записана в очередь.")
			return
	_say("В этом сеансе ещё нечего отменять.")


func _extract() -> void:
	if not _region_mode or _corners.size() != 2:
		_say("Для фрагмента отметь два противоположных угла на одной модели.")
		return
	var source := _corner_objects[0] as VoxelObject
	if not is_instance_valid(source) or source != _corner_objects[1] or not _geometry.has(source):
		_say("Оба угла фрагмента должны принадлежать одной воксельной модели.")
		return
	if bool(_geometry[source].locked) or source.has_meta("layout_fragment"):
		_say("На этой поверхности можно оставить отметку области.")
		return
	var a := source.to_voxel(_corners[0])
	var b := source.to_voxel(_corners[1])
	var low := (Vector3i(a.min(b).floor()) - Vector3i.ONE).max(Vector3i.ZERO)
	var high := (Vector3i(a.max(b).ceil()) + Vector3i.ONE).min(source.volume.get_size())
	var size := high - low
	if size.x <= 0 or size.y <= 0 or size.z <= 0 or size.x * size.y * size.z > 160000:
		_say("Выдели меньший фрагмент, например стол или шкаф.")
		return
	var volume := Build.vol(size)
	var cells: Array[Vector3i] = []
	var values := PackedByteArray()
	for z in range(low.z, high.z):
		for y in range(low.y, high.y):
			for x in range(low.x, high.x):
				var cell := Vector3i(x, y, z)
				var voxel := source.volume.get_voxel(cell)
				if voxel == 0 or VoxMat.material_of(voxel) == VoxMat.UNBREAKABLE:
					continue
				cells.append(cell)
				values.append(voxel)
				volume.set_voxel(cell - low, voxel)
	if cells.is_empty() or cells.size() == source.voxel_count():
		_say("Целую модель можно передвинуть через список объектов.")
		return
	var source_id := str(_geometry[source].id)
	var id := "%s / фрагмент %s → %s" % [source_id, low, high]
	for previous in _fragments:
		if previous.id == id:
			_say("Этот фрагмент уже вынесен отдельно.")
			return
	var fragment := {"id": id, "source": source, "source_id": source_id, "min": low, "max": high,
		"cells": cells, "values": values, "volume": volume, "node": null}
	_fragments.append(fragment)
	_mount_fragment(fragment)
	_undo.append({"fragment": fragment})
	_select(fragment.node)
	_update_list()
	_last_file = LayoutFeedback.create(_payload("fragment", fragment.node))
	_say("Фрагмент выбран. Его можно передвинуть или повернуть как отдельную модель.")


func _mount_fragment(fragment: Dictionary) -> void:
	var source := fragment.source as VoxelObject
	for cell: Vector3i in fragment.cells:
		source.volume.set_voxel(cell, 0)
	_refresh(source, fragment)
	var body := VoxelObject.new().setup(fragment.volume, true)
	body.label = "Фрагмент · " + source.label
	body.set_meta("layout_fragment", fragment.id)
	body.transform = Transform3D(source.global_basis, source.voxel_to_world(Vector3(fragment.min)))
	world.add_child(body)
	fragment["node"] = body
	_register(body, body.label)


func _unmount_fragment(fragment: Dictionary) -> void:
	var source := fragment.source as VoxelObject
	if is_instance_valid(source):
		for i in fragment.cells.size():
			source.volume.set_voxel(fragment.cells[i], fragment.values[i])
		_refresh(source, fragment)
	var body := fragment.node as VoxelObject
	if is_instance_valid(body):
		_ordered.erase(body)
		_geometry.erase(body)
		body.queue_free()
	fragment["node"] = null


func _refresh(source: VoxelObject, fragment: Dictionary) -> void:
	source.mark_dirty(fragment.min, fragment.max)
	while source.has_dirty():
		source.rebuild_next()


func _undo_fragment(fragment: Dictionary) -> void:
	_drafts.erase(fragment.id)
	if _selection == fragment.node:
		_selection = fragment.source
	_unmount_fragment(fragment)
	_fragments.erase(fragment)
	_last_file = LayoutFeedback.create(_payload("undo_fragment", fragment.source))
	_update_list()
	_show_selection()
	_say("Фрагмент возвращён на место.")


func _apply_fields() -> void:
	if _locked():
		return
	var before := _selection.global_transform
	var pos := _bounded(Vector3(_fields[0].value, _fields[1].value, _fields[2].value))
	var angles := Vector3(_fields[3].value, _fields[4].value, _fields[5].value) * (PI / 180.0)
	var basis := Basis.from_euler(angles).scaled_local(before.basis.get_scale())
	_set_pose(_selection, Transform3D(basis, pos))
	_commit(_selection, before)
	_show_selection()


func _select(object: Node3D) -> void:
	_selection = object
	_region_mode = false
	_corners.clear()
	_corner_objects.clear()
	var index := _listed.find(object)
	if index >= 0:
		_list.select(index)
		_list.ensure_current_is_visible()
	_show_selection()


func _locked() -> bool:
	return not is_instance_valid(_selection) or bool(_geometry[_selection].locked)


func _set_region(on: bool) -> void:
	_region_mode = on
	_corners.clear()
	_corner_objects.clear()
	_show_selection()


func _show_selection() -> void:
	if not active:
		return
	_marker.hide()
	if _region_mode:
		_title.text = "Область · %d / 2 угла" % _corners.size()
		if not _corners.is_empty():
			_draw_box(_region(), Transform3D.IDENTITY, Color("#ffc46d"))
	elif is_instance_valid(_selection):
		var entry: Dictionary = _geometry[_selection]
		_title.text = str(entry.label) + (" · основание" if entry.locked else "")
		var xf := _selection.global_transform
		var rotation := xf.basis.get_euler() * (180.0 / PI)
		for i in 3:
			_fields[i].set_value_no_signal(xf.origin[i])
			_fields[i + 3].set_value_no_signal(rotation[i])
		var size := Vector3.ONE * 0.5
		var origin := -size * 0.5
		if _selection is VoxelObject:
			size = Vector3(_selection.volume.get_size()) * VoxelObject.VS
			origin = Vector3.ZERO
		_draw_box(AABB(origin, size).grow(0.025), xf, Color("#7de3ec"))
	else:
		_title.text = "Объект не выбран"
	for field in _fields:
		field.editable = not _region_mode and not _locked()


func _region() -> AABB:
	var a := _corners[0]
	var b := _corners[-1]
	return AABB(a.min(b), (b - a).abs()).grow(0.13)


func _draw_box(box: AABB, xf: Transform3D, tint: Color) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for corner in 8:
		for bit in [1, 2, 4]:
			if corner & bit:
				continue
			mesh.surface_add_vertex(xf * box.get_endpoint(corner))
			mesh.surface_add_vertex(xf * box.get_endpoint(corner | bit))
	mesh.surface_end()
	_marker.mesh = mesh
	_marker.show()


func _payload(kind: String, object: Node3D = null) -> Dictionary:
	var changes := []
	for id: String in _drafts:
		var edit: Dictionary = _drafts[id]
		changes.append({"id": id, "label": edit.label, "before": LayoutFeedback.pose(edit.before), "after": LayoutFeedback.pose(edit.after)})
	var entry := {"format": 1, "map": GameState.level, "map_name": str(GameState.MAPS.get(GameState.level, [GameState.level])[0]),
		"kind": kind, "comment": _note.text.strip_edges(), "changes": changes,
		"camera": LayoutFeedback.pose(_camera.global_transform)}
	var fragments := []
	for fragment: Dictionary in _fragments:
		fragments.append({"id": fragment.id, "source": fragment.source_id,
			"min_voxel": LayoutFeedback.point(Vector3(fragment.min)), "max_voxel_exclusive": LayoutFeedback.point(Vector3(fragment.max))})
	if not fragments.is_empty():
		entry["fragments"] = fragments
	if _region_mode and _corners.size() == 2:
		var area := _region()
		entry["selection"] = {"kind": "region", "label": "Выделенная область", "min": LayoutFeedback.point(area.position),
			"max": LayoutFeedback.point(area.end)}
	elif is_instance_valid(object):
		var original: Dictionary = _geometry[object]
		entry["selection"] = {"kind": "object", "id": original.id, "label": original.label,
			"before": LayoutFeedback.pose(original.original), "after": LayoutFeedback.pose(object.global_transform)}
	return entry


func _submit() -> void:
	if _busy:
		return
	if _region_mode and _corners.size() != 2:
		_say("Отметь оба угла области.")
		return
	if not is_instance_valid(_selection) and _corners.size() != 2 and _drafts.is_empty() and _note.text.strip_edges().is_empty():
		_say("Выбери объект или напиши комментарий.")
		return
	_end_drag()
	var data := _payload("review", _selection)
	_busy = true
	_panel.hide()
	var image: Image
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		image = get_viewport().get_texture().get_image()
	_panel.show()
	_busy = false
	_last_file = LayoutFeedback.create(data, image)
	if _last_file.is_empty():
		_say("Не удалось записать отчёт.")
		return
	LayoutFeedback.copy_message(_last_file, data)
	_say("Отчёт сохранён. Вставь сообщение в чат через Ctrl+V.")


func _update_list(_filter := "") -> void:
	_list.clear()
	_listed.clear()
	var text := _search.text.to_lower().strip_edges()
	var by_distance := _ordered.duplicate()
	by_distance.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		if bool(_geometry[a].locked) != bool(_geometry[b].locked):
			return not bool(_geometry[a].locked)
		return a.global_position.distance_squared_to(_camera.global_position) < b.global_position.distance_squared_to(_camera.global_position))
	for object: Node3D in by_distance:
		if not is_instance_valid(object):
			continue
		var label := str(_geometry[object].label)
		if not text.is_empty() and not label.to_lower().contains(text):
			continue
		_list.add_item("%s   %s" % [label, object.global_position.snapped(Vector3.ONE * 0.1)])
		_listed.append(object)


func _say(message: String) -> void:
	_status.text = message


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -555
	_panel.offset_right = -22
	_panel.offset_top = 22
	_panel.offset_bottom = -22
	_panel.add_theme_stylebox_override("panel", MenuStyle.panel(Color("#141d25f4")))
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_panel.add_child(content)
	content.add_child(MenuStyle.label("BREAKPOINT   /   ПРАВКИ", 31, MenuStyle.GOLD))
	var help := MenuStyle.label("ПКМ + WASD — полёт · Space / Ctrl — высота\nShift — быстрее · ЛКМ — выбрать или перетащить\nB — область · Ctrl+Z — отмена · Esc — выход", 19, MenuStyle.MUTED)
	content.add_child(help)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск объектов по названию"
	_search.custom_minimum_size.y = 44
	_search.text_changed.connect(_update_list)
	content.add_child(_search)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 130
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int): _select(_listed[i]))
	content.add_child(_list)
	_title = MenuStyle.label("", 23)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_title)
	var grid := GridContainer.new()
	grid.columns = 4
	content.add_child(grid)
	for row in ["Позиция, м", "Поворот, °"]:
		grid.add_child(MenuStyle.label(row, 17))
		for axis in ["X", "Y", "Z"]:
			var spin := SpinBox.new()
			spin.prefix = axis
			spin.min_value = -999.0
			spin.max_value = 999.0
			spin.step = 0.1
			spin.custom_minimum_size.x = 115
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(spin)
			_fields.append(spin)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	actions.add_child(MenuStyle.button("Применить", _apply_fields, false, 47))
	actions.add_child(MenuStyle.button("Область", func(): _set_region(not _region_mode), false, 47))
	actions.add_child(MenuStyle.button("Фрагмент", _extract, false, 47))
	_note = TextEdit.new()
	_note.placeholder_text = "Комментарий. Например: разверни ворота к дороге."
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.custom_minimum_size.y = 115
	content.add_child(_note)
	content.add_child(MenuStyle.button("Сохранить и скопировать в чат", _submit, true, 56))
	var exit_row := HBoxContainer.new()
	content.add_child(exit_row)
	exit_row.add_child(MenuStyle.button("Папка отчётов", func():
		DirAccess.make_dir_recursive_absolute(LayoutFeedback.DIRECTORY)
		OS.shell_open(ProjectSettings.globalize_path(LayoutFeedback.DIRECTORY)), false, 47))
	exit_row.add_child(MenuStyle.button("Выйти", close, false, 47))
	_status = MenuStyle.label("", 18, MenuStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 48
	content.add_child(_status)
