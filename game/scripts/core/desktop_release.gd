extends Node

signal changed
const MANIFEST := "https://tearbown.vercel.app/desktop-release.json"
const DOWNLOADS := "https://tearbown.vercel.app/#downloads"
const RELEASE_BASE := "https://github.com/Cfty876/tearbown/releases/download/"
const LIMIT := 500 * 1024 * 1024
const CACHE_DIR := "user://updates"

var status := "Готово к проверке."
var candidate := {}
var _check: HTTPRequest
var _download: HTTPRequest
var _checking := false
var _working := false
var _temporary := ""
var _verified := ""
var _verify: Thread
var _version := ""
var _checked_at := -300000
var _last_progress := -1


func _ready() -> void:
	if not supported():
		set_process(false)
		return
	_check = HTTPRequest.new()
	_download = HTTPRequest.new()
	add_child(_check)
	add_child(_download)
	_check.use_threads = true
	_check.timeout = 8
	_check.body_size_limit = 32768
	_download.use_threads = true
	_download.timeout = 420
	_check.request_completed.connect(_checked)
	_download.request_completed.connect(_downloaded)
	set_process(false)


func supported() -> bool:
	return (OS.get_name() == "Windows" or OS.get_name() == "macOS") and not OS.has_feature("editor")


func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func busy() -> bool:
	return _checking or _working


func check(force := false) -> void:
	var now := Time.get_ticks_msec()
	if not supported() or busy() or (not force and now - _checked_at < 300000):
		return
	_checked_at = now
	_checking = true
	_message("Проверяем обновления…")
	if _check.request(MANIFEST) != OK:
		_checking = false
		_message("Сайт обновлений недоступен. Повтори попытку позже.")


func download() -> void:
	if not supported() or candidate.is_empty() or busy():
		return
	if not _verified.is_empty() and FileAccess.file_exists(_verified):
		_open_archive()
		return
	var folder := ProjectSettings.globalize_path(CACHE_DIR)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		_message("Не удалось создать папку для обновления.")
		return
	_temporary = CACHE_DIR.path_join("download.part")
	_download.download_file = _temporary
	_download.body_size_limit = int(candidate.size)
	_last_progress = -1
	_working = true
	_message("Скачиваем версию %s…" % _version)
	set_process(true)
	if _download.request(candidate.url) != OK:
		_failed_download("Не удалось начать скачивание.")


func _checked(result: int, response: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_checking = false
	if result != HTTPRequest.RESULT_SUCCESS or response != 200:
		_message("Сайт обновлений недоступен. Повтори попытку позже.")
		return
	var manifest: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not manifest is Dictionary:
		_message("Не удалось прочитать данные об обновлении.")
		return
	var latest := str(manifest.get("version", ""))
	var tag := str(manifest.get("tag", ""))
	var platforms: Variant = manifest.get("platforms")
	if _parts(latest).is_empty() or tag != "breakpoint-v" + latest or not platforms is Dictionary:
		_message("Получены некорректные данные об обновлении.")
		return
	if not _is_newer(latest, version()):
		candidate.clear()
		_verified = ""
		_message("Установлена актуальная версия %s." % version())
		return
	var key := "macos" if OS.get_name() == "macOS" else "windows"
	var filename := "BREAKPOINT-macOS.zip" if key == "macos" else "BREAKPOINT-Windows-x64.zip"
	var upstream: Variant = platforms.get(key)
	if not upstream is Dictionary or str(upstream.get("url", "")) != RELEASE_BASE + tag + "/" + filename:
		_message("Обновление для этой системы ещё не опубликовано.")
		return
	var size := int(upstream.get("size", 0))
	var sha := str(upstream.get("sha256", "")).to_lower()
	if size <= 0 or size > LIMIT or sha.length() != 64 or not sha.is_valid_hex_number(false):
		_message("Получены некорректные данные об архиве.")
		return
	if _version != latest or str(candidate.get("sha", "")) != sha:
		_verified = ""
	_version = latest
	candidate = {"url": upstream.url, "size": size, "sha": sha, "name": filename}
	_message("Доступна версия %s  ·  %.0f МБ" % [latest, size / 1048576.0])


func _downloaded(result: int, response: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response != 200:
		_failed_download("Скачивание прервалось. Попробуй снова.")
		return
	if _file_size(_temporary) != int(candidate.size):
		_failed_download("Размер архива не совпал. Попробуй скачать снова.")
		return
	_message("Проверяем целостность архива…")
	_verify = Thread.new()
	var part := _temporary
	if _verify.start(func() -> String: return FileAccess.get_sha256(part)) != OK:
		_verify = null
		_failed_download("Не удалось проверить архив.")


func _process(_delta: float) -> void:
	if _verify != null:
		if _verify.is_alive():
			return
		var actual := str(_verify.wait_to_finish())
		_verify = null
		if actual != str(candidate.sha):
			_failed_download("Контрольная сумма не совпала. Скачай архив ещё раз.")
			return
		var path := CACHE_DIR.path_join(_version + "-" + str(candidate.name))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(_temporary), ProjectSettings.globalize_path(path)) != OK:
			_failed_download("Не удалось сохранить архив.")
			return
		_temporary = ""
		_verified = path
		_working = false
		set_process(false)
		_open_archive()
	elif _working and _download.get_http_client_status() == HTTPClient.STATUS_BODY:
		var progress := clampi(int(100.0 * _download.get_downloaded_bytes() / int(candidate.size)), 0, 100)
		if progress != _last_progress:
			_last_progress = progress
			_message("Скачиваем версию %s… %d%%" % [_version, progress])


func _open_archive() -> void:
	if OS.shell_open(ProjectSettings.globalize_path(_verified)) == OK:
		_message("Архив проверен и открыт. Закрой игру перед заменой файлов.")
	else:
		OS.shell_open(ProjectSettings.globalize_path(CACHE_DIR))
		_message("Архив проверен. Открой его из папки обновлений.")


func _failed_download(reason: String) -> void:
	if not _temporary.is_empty() and FileAccess.file_exists(_temporary):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_temporary))
	_temporary = ""
	_working = false
	set_process(false)
	_message(reason)


func _exit_tree() -> void:
	if _verify != null and _verify.is_started():
		_verify.wait_to_finish()


func _message(value: String) -> void:
	status = value
	changed.emit()


static func _file_size(path: String) -> int:
	var archive := FileAccess.open(path, FileAccess.READ)
	return archive.get_length() if archive != null else -1


static func _parts(value: String) -> PackedInt32Array:
	var parts := value.split(".")
	if parts.size() != 3:
		return PackedInt32Array()
	var result := PackedInt32Array()
	for part in parts:
		if part.is_empty() or part.length() > 4 or not part.is_valid_int() or str(int(part)) != part or int(part) < 0:
			return PackedInt32Array()
		result.append(int(part))
	return result


static func _is_newer(latest: String, current: String) -> bool:
	var a := _parts(latest)
	var b := _parts(current)
	if a.size() != 3 or b.size() != 3:
		return false
	for i in 3:
		if a[i] != b[i]:
			return a[i] > b[i]
	return false
