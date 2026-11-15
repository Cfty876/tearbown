extends Node
## Модель скачивается отдельно от игры. HTTP и вычисление SHA-256 идут в фоне.

signal changed

const FILE_NAME := "qwen2.5-0.5b-instruct-q4_k_m.gguf"
const FILE_BYTES := 491400032
const SHA256 := "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
const REVISION := "9217f5db79a29953eb74d5343926648285ec7e67"
const URL := "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/" + REVISION + "/" + FILE_NAME
const CHAT_CLASS := &"NobodyWhoChat"
const SAMPLER_CLASS := &"NobodyWhoSamplerPresets"

var state := "missing"
var message := ""
var _request: HTTPRequest
var _hash: Thread
var _checking := ""
var _part := ""
var _download := ""
var _verified := ""
var _invalid := {}
var _chat: Variant
var _busy_owner := 0
var _cancelled := false
var _load_failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.accept_gzip = false
	_request.max_redirects = 8
	_request.body_size_limit = FILE_BYTES
	_request.timeout = 1800.0
	_request.request_completed.connect(_download_finished)
	add_child(_request)
	_download = ProjectSettings.globalize_path("user://models/" + FILE_NAME)
	if not supported():
		state = "unsupported"
	elif not _find_model().is_empty():
		state = "installed"
	print("[bot-language] startup: ", state)


func supported() -> bool:
	return OS.get_name() == "Windows" and ClassDB.class_exists(CHAT_CLASS)


func downloaded_bytes() -> int:
	return _request.get_downloaded_bytes() if state == "downloading" else 0


func busy() -> bool:
	return _busy_owner != 0


func installed() -> bool:
	return state in ["installed", "loading", "ready"] or (state == "verifying" and _part.is_empty())


func download() -> void:
	if not supported() or installed() or state in ["downloading", "verifying"]:
		return
	var dir := _download.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		_set_state("error", "Не удалось открыть папку загрузки.")
		return
	var disk := DirAccess.open(dir)
	if disk == null or disk.get_space_left() < FILE_BYTES + 8 * 1024 * 1024:
		_set_state("error", "Для модели нужно около 500 МБ свободного места.")
		return
	_part = _download + ".%d.part" % OS.get_process_id()
	_request.download_file = _part
	var result := _request.request(URL, ["Accept: application/octet-stream"])
	if result != OK:
		_discard_partial()
		_set_state("error", "Не удалось начать загрузку. Повтори попытку.")
		return
	_set_state("downloading")


func cancel_download() -> void:
	if state != "downloading":
		return
	_request.cancel_request()
	_discard_partial()
	_set_state("missing", "Загрузка отменена.")


func warmup() -> void:
	if state != "installed" or _load_failed or _chat != null:
		return
	if not _verified.is_empty():
		_load_model()
		return
	var path := _find_model()
	if path.is_empty():
		_set_state("missing")
		return
	_verify(path)


func retry() -> void:
	if state != "load_error":
		return
	_load_failed = false
	_set_state("installed")
	warmup()


func generate(owner: int, history: Array, max_tokens: int, choices := "") -> String:
	if state != "ready" or busy() or owner <= 0:
		return ""
	_busy_owner = owner
	_cancelled = false
	var sampler: Variant
	if choices.is_empty():
		sampler = ClassDB.class_call_static(SAMPLER_CLASS, &"temperature", 0.52)
	else:
		sampler = ClassDB.class_call_static(SAMPLER_CLASS, &"constrain_with_regex", choices)
	var stream: Variant = _chat.complete(history, {"sampler": sampler})
	var answer := ""
	if stream != null:
		for index in max_tokens:
			var token: Variant = await stream.next_token()
			if token == null or _cancelled:
				break
			answer += str(token)
			if not choices.is_empty() and not answer.strip_edges().is_empty():
				break
		_chat.stop_generation()
		# Дожидаемся остановки, прежде чем запускать следующий запрос.
		await stream.completed()
	var result := "" if _cancelled else answer.strip_edges()
	_busy_owner = 0
	_cancelled = false
	return result


func cancel(owner: int) -> void:
	if owner != _busy_owner or _chat == null:
		return
	_cancelled = true
	_chat.stop_generation()


func _find_model() -> String:
	var candidates := [_download]
	if OS.has_environment("BREAKPOINT_MODEL_DIR"):
		candidates.append(OS.get_environment("BREAKPOINT_MODEL_DIR").path_join(FILE_NAME))
	var install_dir := OS.get_executable_path().get_base_dir()
	candidates.append(install_dir.path_join("models/" + FILE_NAME))
	candidates.append(install_dir.get_base_dir().path_join("models/" + FILE_NAME))
	for path: String in candidates:
		if not path.is_empty() and not _invalid.has(path) and FileAccess.file_exists(path) and FileAccess.get_size(path) == FILE_BYTES:
			return path
	return ""


func _download_finished(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if state != "downloading":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(_part) or FileAccess.get_size(_part) != FILE_BYTES:
		_discard_partial()
		_set_state("error", "Загрузка прервалась. Проверь подключение и свободное место.")
		return
	_verify(_part)


func _verify(path: String) -> void:
	_checking = path
	_hash = Thread.new()
	if _hash.start(func() -> String: return FileAccess.get_sha256(path)) != OK:
		_hash = null
		_discard_partial()
		_set_state("error", "Не удалось проверить файл модели.")
		return
	_set_state("verifying")
	set_process(true)


func _process(_delta: float) -> void:
	if _hash == null or _hash.is_alive():
		return
	var digest: String = _hash.wait_to_finish()
	_hash = null
	set_process(false)
	if digest != SHA256:
		_invalid[_checking] = true
		_discard_partial()
		_set_state("error", "Контрольная сумма не совпала. Скачай модель заново.")
		return
	if _checking == _part:
		if DirAccess.rename_absolute(_part, _download) != OK:
			_discard_partial()
			_set_state("error", "Не удалось сохранить проверенную модель.")
			return
		_part = ""
		_invalid.erase(_download)
		_verified = _download
		_set_state("installed")
	else:
		_verified = _checking
		_load_model()


func _load_model() -> void:
	_set_state("loading")
	var threads := clampi(OS.get_processor_count() / 3, 1, 2)
	_chat = await ClassDB.class_call_static(CHAT_CLASS, &"create", _verified,
		{"n_ctx": 768, "use_gpu": false, "n_threads": threads})
	if _chat == null:
		_load_failed = true
		_set_state("load_error", "Движок не смог открыть модель. Можно повторить запуск.")
	else:
		_set_state("ready")


func _set_state(next: String, detail := "") -> void:
	state = next
	message = detail
	if state in ["ready", "error", "load_error"]:
		print("[bot-language] ", state, " ", detail)
	changed.emit()


func _discard_partial() -> void:
	if not _part.is_empty() and FileAccess.file_exists(_part):
		DirAccess.remove_absolute(_part)
	_part = ""


func _exit_tree() -> void:
	if _chat != null and busy():
		_chat.stop_generation()
	if _request != null:
		_request.cancel_request()
	if _hash != null:
		_hash.wait_to_finish()
	_discard_partial()
