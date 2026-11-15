extends Node

signal changed
const MANIFEST := "https://tearbown.vercel.app/desktop-release.json"
const INSTALLATIONS := "https://tearbown.vercel.app/api/installations"
const INSTALLATION_FILE := "user://installations.cfg"
const DOWNLOADS := "https://tearbown.vercel.app/#downloads"
const RELEASE_BASE := "https://github.com/Cfty876/tearbown/releases/download/"
const LIMIT := 500 * 1024 * 1024
const CACHE_DIR := "user://updates"
const WINDOWS_RELEASE_FILES := [
	"BREAKPOINT.exe", "BREAKPOINT.pck", "voxcore.dll",
	"libnobodywho-godot-x86_64-pc-windows-msvc-release.dll",
	"COPYRIGHT-Godot.txt", "LICENSE-Godot.txt", "LICENSE-NobodyWho.txt",
]

var installation_enabled := false
var installation_status := ""
var offered_version := ""
var _installation_token := ""
var _installation_request: HTTPRequest
var _installation_pending := false

var status := "Готово к проверке."
var candidate := {}
var _check: HTTPRequest
var _download: HTTPRequest
var _checking := false
var _working := false
var _temporary := ""
var _verified := ""
var _verified_sha := ""
var _verify: Thread
var _compare: Thread
var _patch := {}
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
	_installation_request = HTTPRequest.new()
	_installation_request.use_threads = true
	_installation_request.timeout = 12
	_installation_request.max_redirects = 0
	_installation_request.body_size_limit = 2048
	add_child(_installation_request)
	_installation_request.request_completed.connect(_installation_reply)
	var prefs := ConfigFile.new()
	if prefs.load(INSTALLATION_FILE) == OK:
		_installation_token = str(prefs.get_value("installations", "token", ""))
		installation_enabled = bool(prefs.get_value("installations", "enabled", false)) and _valid_hash(_installation_token)
	var poll := Timer.new()
	poll.wait_time = 300.0
	poll.autostart = true
	poll.timeout.connect(_report_installation)
	add_child(poll)
	_report_installation.call_deferred()
	set_process(false)


func supported() -> bool:
	return (OS.get_name() == "Windows" or OS.get_name() == "macOS") and not OS.has_feature("editor")


func set_installation_enabled(enabled: bool) -> void:
	if not supported() or enabled == installation_enabled:
		return
	var next_token := _installation_token
	if enabled and not _valid_hash(next_token):
		next_token = Crypto.new().generate_random_bytes(32).hex_encode()
	if not _save_installation(enabled, next_token):
		installation_status = "Не удалось сохранить выбор."
		changed.emit()
		return
	installation_enabled = enabled
	_installation_token = next_token
	offered_version = ""
	_installation_request.cancel_request()
	_installation_pending = false
	_report_installation()


func _save_installation(enabled: bool, token: String) -> bool:
	var prefs := ConfigFile.new()
	prefs.set_value("installations", "enabled", enabled)
	prefs.set_value("installations", "token", token)
	return prefs.save(INSTALLATION_FILE) == OK


func _report_installation() -> void:
	if _installation_pending or not _valid_hash(_installation_token):
		return
	var data := {
		"operation": "check" if installation_enabled else "remove",
		"platform": OS.get_name(), "version": version(), "token": _installation_token,
	}
	_installation_pending = _installation_request.request(_publisher_url(INSTALLATIONS), ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(data)) == OK
	installation_status = "Подключаемся…" if _installation_pending else "Реестр временно недоступен."
	changed.emit()


func _installation_reply(result: int, response: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_installation_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response != 200:
		installation_status = "Реестр временно недоступен. Игра повторит попытку."
		changed.emit()
		return
	if not installation_enabled:
		if _save_installation(false, ""):
			_installation_token = ""
		installation_status = "Установка удалена из списка."
		changed.emit()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	var from_publisher := str(data.get("target", "")) if data is Dictionary else ""
	var previous := offered_version
	offered_version = from_publisher if _is_newer(from_publisher, version()) else ""
	installation_status = "Установка зарегистрирована." if offered_version.is_empty() else "Издатель предложил обновление %s." % offered_version
	if offered_version != previous and not offered_version.is_empty():
		check(true)
	changed.emit()


static func _publisher_url(official: String) -> String:
	# A workstation launcher can forward these two requests through a loopback bridge.
	var origin := OS.get_environment("BREAKPOINT_PUBLISHER_LOOPBACK")
	var loopback := "http://127.0.0.1:"
	var port := origin.trim_prefix(loopback)
	if origin.begins_with(loopback) and port.is_valid_int() and str(int(port)) == port and int(port) >= 1024 and int(port) <= 65535:
		return origin + "/" + official.trim_prefix("https://tearbown.vercel.app/")
	return official

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
	if _check.request(_publisher_url(MANIFEST)) != OK:
		_checking = false
		_message("Сайт обновлений недоступен. Повтори попытку позже.")


func download() -> void:
	if not supported() or candidate.is_empty() or busy():
		return
	if _verified == _archive_path() and _verified_sha == str(candidate.sha) and FileAccess.file_exists(_verified):
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
	var full := _archive(upstream, filename)
	if full.is_empty():
		_message("Получены некорректные данные об архиве.")
		return
	if _version != latest:
		_verified = ""
	_version = latest
	candidate = full
	if key == "windows":
		var patches: Variant = upstream.get("patches")
		if patches is Dictionary:
			_patch = _read_patch(patches.get(version()), tag, int(full.size))
			if not _patch.is_empty():
				_compare = Thread.new()
				var files: Dictionary = _patch.requires
				var directory := OS.get_executable_path().get_base_dir()
				if _compare.start(_matches_install.bind(directory, files)) == OK:
					_checking = true
					_message("Проверяем, какие файлы уже установлены…")
					set_process(true)
					return
				_compare = null
				_patch.clear()
	_show_available()


static func _archive(info: Dictionary, filename: String) -> Dictionary:
	var bytes := int(info.get("size", 0))
	var sha := str(info.get("sha256", "")).to_lower()
	if bytes <= 0 or bytes > LIMIT or not _valid_hash(sha):
		return {}
	return {"url": info.url, "size": bytes, "sha": sha, "name": filename}


func _read_patch(info: Variant, tag: String, full_size: int) -> Dictionary:
	var filename := "BREAKPOINT-Windows-x64-from-%s.zip" % version()
	if not info is Dictionary or str(info.get("url", "")) != RELEASE_BASE + tag + "/" + filename:
		return {}
	var patch := _archive(info, filename)
	if patch.is_empty() or int(patch.size) >= full_size:
		return {}
	var files: Variant = info.get("requires")
	if not files is Dictionary or files.is_empty():
		return {}
	for name in files:
		if name not in WINDOWS_RELEASE_FILES or not _valid_hash(str(files[name])):
			return {}
	patch["requires"] = files
	return patch


static func _valid_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for digit in value:
		if not digit in "0123456789abcdef":
			return false
	return true


static func _matches_install(directory: String, files: Dictionary) -> bool:
	for name: String in files:
		if FileAccess.get_sha256(directory.path_join(name)) != files[name]:
			return false
	return true


func _show_available() -> void:
	var label := "Быстрое обновление" if candidate.has("requires") else "Полный архив"
	_message("%s %s  ·  %.1f МБ" % [label, _version, int(candidate.size) / 1048576.0])

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
	if _compare != null:
		if _compare.is_alive():
			return
		if bool(_compare.wait_to_finish()):
			candidate = _patch
		_patch = {}
		_compare = null
		_checking = false
		set_process(false)
		_show_available()
		return
	if _verify != null:
		if _verify.is_alive():
			return
		var actual := str(_verify.wait_to_finish())
		_verify = null
		if actual != str(candidate.sha):
			_failed_download("Контрольная сумма не совпала. Скачай архив ещё раз.")
			return
		var path := _archive_path()
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(_temporary), ProjectSettings.globalize_path(path)) != OK:
			_failed_download("Не удалось сохранить архив.")
			return
		_temporary = ""
		_verified = path
		_verified_sha = actual
		_working = false
		set_process(false)
		_open_archive()
	elif _working and _download.get_http_client_status() == HTTPClient.STATUS_BODY:
		var progress := clampi(int(100.0 * _download.get_downloaded_bytes() / int(candidate.size)), 0, 100)
		if progress != _last_progress:
			_last_progress = progress
			_message("Скачиваем версию %s… %d%%" % [_version, progress])


func _archive_path() -> String:
	return CACHE_DIR.path_join(_version + "-" + str(candidate.name))


func _open_archive() -> void:
	if OS.shell_open(ProjectSettings.globalize_path(_verified)) == OK:
		if candidate.has("requires"):
			_message("Обновление проверено. Закрой игру и распакуй файлы с заменой в папку BREAKPOINT.exe.")
		else:
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
	if _compare != null and _compare.is_started():
		_compare.wait_to_finish()
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
