class_name LayoutFeedback
extends RefCounted

const DIRECTORY := "user://layout_feedback"


static func create(data: Dictionary, image: Image = null) -> String:
	if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK:
		return ""
	var id := "%d-%d" % [int(Time.get_unix_time_from_system() * 1000), randi() % 100000]
	var file := DIRECTORY.path_join(id + ".json")
	var report := FileAccess.open(file, FileAccess.WRITE)
	if report == null:
		return ""
	data["id"] = id
	data["time"] = Time.get_datetime_string_from_system()
	if image:
		if image.get_width() > 1600:
			image.resize(1600, roundi(image.get_height() * 1600.0 / image.get_width()), Image.INTERPOLATE_LANCZOS)
		var picture := DIRECTORY.path_join(id + ".jpg")
		if image.save_jpg(picture, 0.88) == OK:
			data["screenshot"] = ProjectSettings.globalize_path(picture)
	report.store_string(JSON.stringify(data, "\t", false))
	report.close()
	return ProjectSettings.globalize_path(file)


static func copy_message(file: String, data: Dictionary) -> void:
	var text := "BREAKPOINT · Правки карты %s\nОтчёт: %s" % [data.map_name, file]
	if data.has("comment") and not str(data.comment).is_empty():
		text += "\nКомментарий: " + data.comment
	if data.has("selection"):
		var selection: Dictionary = data.selection
		text += "\nВыделено: " + str(selection.get("label", selection.get("kind", "")))
		if selection.kind == "region":
			text += "\nГраницы (м): %s → %s" % [selection.min, selection.max]
		else:
			text += "\nID: " + str(selection.id)
	for i in mini(6, data.changes.size()):
		var edit: Dictionary = data.changes[i]
		text += "\n• %s: %s → %s м, поворот %s°" % [edit.label, edit.before.meters, edit.after.meters, edit.after.degrees]
	if data.changes.size() > 6:
		text += "\nОстальные перемещения в JSON."
	if data.has("screenshot"):
		text += "\nСнимок: " + data.screenshot
	text += "\nПроверь отчёт и внеси правки в исходную карту."
	DisplayServer.clipboard_set(text)


static func point(v: Vector3) -> Array[float]:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func pose(t: Transform3D) -> Dictionary:
	return {"meters": point(t.origin), "degrees": point(t.basis.get_euler() * (180.0 / PI))}
