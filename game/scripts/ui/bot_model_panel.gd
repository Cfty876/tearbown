class_name BotModelPanel
extends PanelContainer

var _label: Label
var _progress: ProgressBar
var _action: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(Color("#131d26f5")))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	labels.add_child(MenuStyle.label("Локальная модель бота", 21, MenuStyle.GOLD))
	_label = MenuStyle.label("", 17, MenuStyle.MUTED)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(_label)
	_action = MenuStyle.button("", _activate, false, 42)
	row.add_child(_action)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 5
	_progress.show_percentage = false
	_progress.max_value = BotLanguage.FILE_BYTES
	body.add_child(_progress)
	BotLanguage.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var state: String = BotLanguage.state
	set_process(state == "downloading")
	_progress.visible = state == "downloading"
	_action.show()
	match state:
		"unsupported":
			_label.text = "Расширенный чат доступен в Windows-сборке."
			_action.hide()
		"downloading":
			_action.text = "Отменить"
			_process(0.0)
		"verifying", "loading":
			_label.text = "Проверяем файл модели…" if state == "verifying" else "Подключаем модель…"
			_action.hide()
		"installed":
			_label.text = "Qwen установлен. После подключения работает офлайн."
			_action.text = "Подключить"
		"ready":
			_label.text = "Qwen подключён. Чат и выбор тактики работают офлайн."
			_action.hide()
		"load_error":
			_label.text = BotLanguage.message
			_action.text = "Повторить"
		_:
			_label.text = BotLanguage.message if not BotLanguage.message.is_empty() else "491 МБ. Добавляет свободный диалог и выбор тактики."
			_action.text = "Скачать"


func _activate() -> void:
	match BotLanguage.state:
		"downloading": BotLanguage.cancel_download()
		"installed": BotLanguage.warmup()
		"load_error": BotLanguage.retry()
		_: BotLanguage.download()


func _process(_delta: float) -> void:
	var bytes: int = BotLanguage.downloaded_bytes()
	_progress.value = bytes
	var size_mb := "%.0f из 491 МБ" % (bytes / 1000000.0)
	if _label.text != size_mb:
		_label.text = size_mb
