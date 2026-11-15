class_name CassetteLibrary
extends RefCounted

const DIR := "user://cassettes"
const CATALOG := DIR + "/catalog.cfg"
const MAX_BYTES := 20 * 1024 * 1024
const FORMATS := ["mp3", "ogg", "wav"]

var entries: Array[Dictionary] = []
var selected := ""


func _init() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CATALOG) != OK:
		return
	for section: String in cfg.get_sections():
		var ext := str(cfg.get_value(section, "ext", ""))
		if section.length() == 64 and section.is_valid_hex_number() and ext in FORMATS and FileAccess.file_exists(_path(section, ext)):
			entries.append({"id": section, "ext": ext, "title": str(cfg.get_value(section, "title", "Кассета")),
				"color": cfg.get_value(section, "color", Color.WHITE)})
	if not entries.is_empty():
		selected = str(cfg.get_value("library", "selected", entries[0].id))
		if current().is_empty():
			selected = entries[0].id


func current() -> Dictionary:
	for entry in entries:
		if entry.id == selected:
			return entry
	return {}


func select(id: String) -> void:
	selected = id
	_save()


func import_file(path: String, title := "") -> String:
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null or input.get_length() > MAX_BYTES:
		return "Выбери MP3, OGG или WAV размером до 20 МБ."
	return import_bytes(input.get_buffer(input.get_length()), path.get_file(), title)


func import_bytes(bytes: PackedByteArray, filename: String, title := "") -> String:
	var ext := filename.get_extension().to_lower()
	if ext not in FORMATS or bytes.size() > MAX_BYTES:
		return "Выбери MP3, OGG или WAV размером до 20 МБ."
	if decode(bytes, ext) == null:
		return "Не удалось прочитать аудиофайл."
	var id := digest(bytes)
	for entry in entries:
		if entry.id == id:
			select(id)
			return ""
	if DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return "Не удалось открыть папку кассет."
	var output := FileAccess.open(_path(id, ext), FileAccess.WRITE)
	if output == null:
		return "Не удалось сохранить кассету."
	output.store_buffer(bytes)
	output.close()
	entries.append({"id": id, "ext": ext, "title": title if not title.is_empty() else filename.get_file().get_basename(),
		"color": _new_color()})
	selected = id
	if _save() != OK:
		entries.pop_back()
		selected = "" if entries.is_empty() else entries[0].id
		DirAccess.remove_absolute(_path(id, ext))
		return "Не удалось сохранить каталог кассет."
	return ""


func _new_color() -> Color:
	var used := {}
	for entry in entries:
		var color: Color = entry.color
		used[color.to_html(false)] = true
	var best := Color.WHITE
	var separation := -1.0
	for i in 72:
		var tint := Color.from_hsv(randf(), randf_range(0.49, 0.82), randf_range(0.69, 0.97))
		if used.has(tint.to_html(false)):
			continue
		var closest := 10.0
		for entry in entries:
			var other: Color = entry.color
			closest = minf(closest, Vector3(tint.r - other.r, tint.g - other.g, tint.b - other.b).length_squared())
		if closest > separation:
			best = tint
			separation = closest
	return best


func read(entry: Dictionary) -> PackedByteArray:
	var input := FileAccess.open(_path(entry.id, entry.ext), FileAccess.READ)
	if input == null or input.get_length() > MAX_BYTES:
		return PackedByteArray()
	return input.get_buffer(input.get_length())


static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func decode(bytes: PackedByteArray, ext: String) -> AudioStream:
	if bytes.size() < 12 or bytes.size() > MAX_BYTES:
		return null
	var stream: AudioStream
	match ext:
		"mp3": stream = AudioStreamMP3.load_from_buffer(bytes)
		"ogg": stream = AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav": stream = AudioStreamWAV.load_from_buffer(bytes)
	return stream if stream != null and stream.get_length() > 0.0 else null


func _path(id: String, ext: String) -> String:
	return "%s/%s.%s" % [DIR, id, ext]


func _save() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("library", "selected", selected)
	for entry in entries:
		for field in ["title", "ext", "color"]:
			cfg.set_value(entry.id, field, entry[field])
	return cfg.save(CATALOG)
