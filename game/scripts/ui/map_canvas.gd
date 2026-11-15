class_name MapCanvas
extends Control

signal pin_selected(at: Vector2, floor_id: int)
signal open_requested

const TEXT_SIZE := 14
const OUTLINE := Color("#142129")
const AUTO_FLOOR := -10
const STEPS := 64
var data: MapSession
var miniature := false
var floor_selection := AUTO_FLOOR
var category := -1
var zoom := 1.0
var _center := Vector2.ZERO
var _aim := Vector2.UP
var _heading := 0.0
var _time := 0.0
var _tick := 0.0
var _drag := false
var _drag_distance := 0.0
var _point := Vector2.ZERO
var _touch_id := -1
var _circle := PackedVector2Array()
var _outline := PackedVector2Array()
var _world_outline := PackedVector2Array()
var _uv := PackedVector2Array()
var _used := PackedVector2Array()
var drawn_markers := 0
var draw_usec := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	clip_contents = not miniature
	MapMarker.preload_icons()
	for i in STEPS:
		_circle.append(Vector2.from_angle(TAU * i / STEPS))
	resized.connect(queue_redraw)
	data.changed.connect(queue_redraw)


func recenter() -> void:
	zoom = 1.0
	_center = Vector2.ZERO
	queue_redraw()


func floor_id() -> int:
	return data.current_floor if floor_selection == AUTO_FLOOR else floor_selection


func _diameter() -> float:
	return minf(size.x, size.y) - (36.0 if miniature else 0.0)


func _scale() -> float:
	if miniature:
		return maxf(1.0, _diameter()) / data.style.zoom_metres[int(GameState.map_options.zoom)]
	return maxf(1.0, _diameter() - 24.0) / (data.atlas.half * 2.0) * zoom


func to_map(world_xz: Vector2) -> Vector2:
	return size * 0.5 + (world_xz - _center).rotated(_heading) * _scale()


func to_world(screen: Vector2) -> Vector2:
	return _center + ((screen - size * 0.5) / _scale()).rotated(-_heading)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not data._ready_atlas:
		return
	_time += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0 / data.style.redraw_hz
	var player := data.gadgets.world.player
	var aim := MapSession.xz(player.aim_dir()).normalized()
	if aim.length_squared() > 0.01:
		_aim = aim
	if miniature:
		var pos := MapSession.xz(player.global_position)
		var reduced: bool = GameState.map_options.reduced_motion
		_center = pos if reduced or _center.distance_squared_to(pos) > 256.0 else _center.lerp(pos, 0.55)
		var wanted := -PI * 0.5 - _aim.angle() if GameState.map_options.rotate else 0.0
		_heading = wanted if reduced else lerp_angle(_heading, wanted, 0.58)
	queue_redraw()


func _draw() -> void:
	if not data or not data._ready_atlas or _diameter() < 4.0:
		return
	var start := Time.get_ticks_usec()
	var colors := MapStyle.palette()
	var center := size * 0.5
	var radius := _diameter() * 0.5
	drawn_markers = 0
	if miniature:
		draw_circle(center + Vector2(1, 4), radius + 9.0, Color("#080f13bd"), true, -1, true)
		draw_circle(center, radius + 8.0, colors[0], true, -1, true)
		draw_arc(center, radius + 7.0, 0, TAU, STEPS, colors[1], 1.0, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), colors[0])
	_outline.resize(STEPS if miniature else 4)
	for i in _outline.size():
		_outline[i] = center + _circle[i] * radius if miniature else size * Vector2(float(i in [1, 2]), float(i >= 2))
	var h := data.atlas.half
	_world_outline.resize(4)
	_world_outline[0] = to_map(Vector2(-h, -h))
	_world_outline[1] = to_map(Vector2(h, -h))
	_world_outline[2] = to_map(Vector2(h, h))
	_world_outline[3] = to_map(Vector2(-h, h))
	var polygon := _outline
	if not miniature:
		var inside := Rect2(_world_outline[0], _world_outline[2] - _world_outline[0]).intersection(Rect2(Vector2.ZERO, size))
		polygon = PackedVector2Array([inside.position, Vector2(inside.end.x, inside.position.y), inside.end, Vector2(inside.position.x, inside.end.y)]) if inside.has_area() else PackedVector2Array()
	elif not _all_inside_world():
		var clipped := Geometry2D.intersect_polygons(_outline, _world_outline)
		polygon = clipped[0] if not clipped.is_empty() else PackedVector2Array()
	if polygon.size() >= 3:
		_uv.resize(polygon.size())
		var inverse := 1.0 / _scale()
		var x_axis := Vector2.RIGHT.rotated(-_heading) * inverse
		var y_axis := Vector2.DOWN.rotated(-_heading) * inverse
		for i in polygon.size():
			var delta := polygon[i] - center
			_uv[i] = data.atlas.uv(_center + x_axis * delta.x + y_axis * delta.y)
		var tint := Color("#c9e4ff") if GameState.map_options.style == 1 else Color.WHITE
		draw_colored_polygon(polygon, tint, _uv, data.atlas.texture(floor_id(), GameState.map_options.style == 2))
		if GameState.map_options.fog or floor_id() < 0:
			draw_colored_polygon(polygon, Color.WHITE, _uv, data.fog.texture(floor_id()))
	_draw_room_boundary()
	_draw_route()
	_draw_markers()
	var player := data.gadgets.world.player
	var at := to_map(MapSession.xz(player.global_position))
	if floor_id() == data.current_floor and _inside(at, 10.0):
		var tint := Color("#8bc7ee") if is_instance_valid(player.vehicle) else (Color("#f5d49a") if player.crouching else Color("#f6faf8"))
		var heading := _aim.rotated(_heading)
		draw_arc(at, 11.0, 0, TAU, 22, Color("#18282d"), 2.0, true)
		MapMarker.arrow(self, at, heading, tint, 8.6)
	_draw_compass(colors, radius)
	draw_usec = Time.get_ticks_usec() - start


func _all_inside_world() -> bool:
	var h := data.atlas.half
	var reach := _diameter() * 0.5 / _scale()
	return absf(_center.x) + reach <= h and absf(_center.y) + reach <= h


func _draw_room_boundary() -> void:
	if not WebSession.connected or int(WebSession.rules.zone) == 0:
		return
	var half := data.gadgets.world.player.border
	var corners := [to_map(Vector2(-half, -half)), to_map(Vector2(half, -half)), to_map(Vector2(half, half)), to_map(Vector2(-half, half))]
	for i in 4:
		var segment := _clip_segment(corners[i], corners[(i + 1) % 4])
		if segment.size() == 2:
			draw_line(segment[0], segment[1], Color("#73d7f4"), 2.0, true)


func _draw_route() -> void:
	if data.target_floor != floor_id() or data.route.size() < 2:
		return
	var route_color := MapStyle.tint(MapStyle.PING)
	for i in range(1, data.route.size()):
		var a := to_map(data.route[i - 1])
		var b := to_map(data.route[i])
		if not _inside(a, 1.0) or not _inside(b, 1.0):
			var part := _clip_segment(a, b)
			if part.is_empty():
				continue
			a = part[0]
			b = part[1]
		if data.route_status == "Направление к метке":
			draw_dashed_line(a, b, route_color, 1.8, 5.0, true, true)
		else:
			draw_line(a, b, OUTLINE, 4.0, true)
			draw_line(a, b, route_color, 2.0, true)


func _clip_segment(a: Vector2, b: Vector2) -> PackedVector2Array:
	var d := b - a
	var enter := 0.0
	var exit := 1.0
	if miniature:
		var relative := a - size * 0.5
		var r := _diameter() * 0.5 - 2.0
		var square := d.length_squared()
		var dot := relative.dot(d)
		var disc := dot * dot - square * (relative.length_squared() - r * r)
		if disc <= 0.0 or square < 0.001:
			return PackedVector2Array()
		enter = maxf(0.0, (-dot - sqrt(disc)) / square)
		exit = minf(1.0, (-dot + sqrt(disc)) / square)
	else:
		for axis in 2:
			if absf(d[axis]) < 0.001:
				if a[axis] < 1.0 or a[axis] > size[axis] - 1.0:
					return PackedVector2Array()
				continue
			var near := (1.0 - a[axis]) / d[axis]
			var far := (size[axis] - 1.0 - a[axis]) / d[axis]
			enter = maxf(enter, minf(near, far))
			exit = minf(exit, maxf(near, far))
	return PackedVector2Array([a + d * enter, a + d * exit]) if enter < exit else PackedVector2Array()


func _draw_markers() -> void:
	_used.clear()
	if data.target.is_finite() and data.target_floor == floor_id():
		_marker(MapSession.marker(data.target, MapStyle.PING, floor_id(), "Твоя метка"), true)
	var cap := data.style.mini_limit if miniature else data.style.large_limit
	var floor_layer := floor_id()
	var mask: int = GameState.map_options.markers
	for kind in MapStyle.PRIORITY:
		if (kind != MapStyle.HORN and (mask & (1 << kind)) == 0) or (category >= 0 and category != kind):
			continue
		for m: Dictionary in data.buckets[kind]:
			if (int(m.floor) != floor_layer and (kind != MapStyle.HORN or not miniature)) \
					or (m.get("detail", false) and (miniature or zoom < 1.3)):
				continue
			_marker(m, kind in [MapStyle.HORN, MapStyle.PING, MapStyle.THREAT, MapStyle.ALLY, MapStyle.OBJECTIVE])
			if drawn_markers >= cap:
				return


func _marker(item: Dictionary, guide: bool) -> void:
	var at := to_map(item.at)
	var kind: int = item.kind
	var radius := 6.0 if miniature else 8.5
	if not _inside(at, 12.0):
		if not guide or not miniature:
			return
		var direction := (at - size * 0.5).normalized()
		at = size * 0.5 + direction * (_diameter() * 0.5 - 13.0)
		if not _reserve(at):
			return
		MapMarker.arrow(self, at, direction, MapStyle.tint(kind), radius)
		drawn_markers += 1
		return
	if miniature and at.distance_squared_to(size * 0.5) < 14.0 * 14.0:
		if kind != MapStyle.HORN:
			return
		at += Vector2(0.0, -17.0)
	if not _reserve(at):
		return
	var pulse := 0.0 if GameState.map_options.reduced_motion else fposmod(_time * 0.9, 1.0)
	MapMarker.paint(self, at, kind, radius, pulse)
	if miniature and kind == MapStyle.HORN and int(item.floor) != floor_id():
		var hint := "−1" if int(item.floor) < 0 else str(int(item.floor) + 1)
		_text(at + Vector2(9.0, -5.0), hint, 12, MapStyle.tint(kind))
	if not miniature and kind in [MapStyle.POINT, MapStyle.PING, MapStyle.OBJECTIVE, MapStyle.HORN] and _inside(at + Vector2(92, 0), 10.0):
		_text(at + Vector2(13, 5), str(item.title), 16, MapStyle.palette()[3])
	drawn_markers += 1


func _reserve(at: Vector2) -> bool:
	var limit := 16.0 if miniature else 23.0
	for old in _used:
		if old.distance_squared_to(at) < limit * limit:
			return false
	_used.append(at)
	return true


func _inside(at: Vector2, inset: float) -> bool:
	if miniature:
		var r := _diameter() * 0.5 - inset
		return r > 0.0 and at.distance_squared_to(size * 0.5) <= r * r
	return Rect2(Vector2.ZERO, size).grow(-inset).has_point(at)


func _draw_compass(colors: Array, radius: float) -> void:
	var center := size * 0.5
	if miniature:
		draw_arc(center, radius + 1.0, 0, TAU, STEPS, colors[1], 1.2, true)
		for i in 16:
			var heading := Vector2.from_angle(float(i) * TAU / 16.0)
			draw_line(center + heading * (radius + 1.0), center + heading * (radius + (6.0 if i % 4 == 0 else 3.0)), colors[1], 1.0, true)
		var north := center + Vector2.UP.rotated(_heading) * (radius + 10.0)
		draw_circle(north, 9.0, colors[0], true, -1, true)
		_text(north + Vector2(-5, 5), "С", TEXT_SIZE, colors[2])
		var floor_label := MapAtlas.floor_name(floor_id())
		var label_width := ThemeDB.fallback_font.get_string_size(floor_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_text(Vector2(center.x - label_width * 0.5, size.y - 2), floor_label, 11, colors[3])
	else:
		_text(Vector2(18, 27), "↑ С", 17, colors[2])
	var metres := 10.0 if miniature else (20.0 if zoom < 2.4 else 10.0)
	var width := metres * _scale()
	var edge := Vector2(center.x - width * 0.5, center.y + radius * 0.64) if miniature else Vector2(22, size.y - 23)
	draw_line(edge, edge + Vector2(width, 0), colors[3], 1.6, true)
	draw_line(edge - Vector2(0, 3), edge + Vector2(0, 3), colors[3], 1.6, true)
	draw_line(edge + Vector2(width, -3), edge + Vector2(width, 3), colors[3], 1.6, true)
	_text(edge + Vector2(1, 15), "%d м" % int(metres), 12, colors[3])


func _text(at: Vector2, text: String, font_size: int, tint: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, OUTLINE)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


func zoom_by(factor: float, pivot: Vector2) -> void:
	var anchor := to_world(pivot)
	zoom = clampf(zoom * factor, 0.75, 5.0)
	_center += anchor - to_world(pivot)
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	_center = _center.clamp(Vector2.ONE * -data.atlas.half, Vector2.ONE * data.atlas.half)


func _gui_input(e: InputEvent) -> void:
	if miniature:
		if e is InputEventScreenTouch and e.pressed:
			open_requested.emit()
			accept_event()
		return
	if e is InputEventMouseButton:
		if e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.22 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.22, e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			data.clear_pin()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_pointer(e.pressed, e.position)
		else:
			return
	elif e is InputEventMouseMotion and _drag and _touch_id == -1:
		_pan(e.relative)
	elif e is InputEventScreenTouch and (_touch_id in [-1, e.index]):
		_touch_id = e.index if e.pressed else -1
		_pointer(e.pressed, e.position)
	elif e is InputEventScreenDrag and e.index == _touch_id and _drag:
		_pan(e.relative)
	else:
		return
	accept_event()


func _pointer(down: bool, at: Vector2) -> void:
	if down:
		_drag = true
		_drag_distance = 0.0
		_point = at
	elif _drag:
		_drag = false
		if _drag_distance <= 7.0 and _point.distance_to(at) <= 10.0:
			pin_selected.emit(to_world(at), floor_id())


func _pan(offset: Vector2) -> void:
	_drag_distance += offset.length()
	_center -= offset / _scale()
	_clamp_center()
	queue_redraw()
