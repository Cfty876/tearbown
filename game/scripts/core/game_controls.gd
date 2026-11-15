class_name GameControls
extends RefCounted

const BINDINGS := {
	"move_forward": ["Вперёд", KEY_W], "move_back": ["Назад", KEY_S],
	"move_left": ["Влево", KEY_A], "move_right": ["Вправо", KEY_D],
	"jump": ["Прыжок / ручник", KEY_SPACE], "sprint": ["Бег", KEY_SHIFT],
	"crouch": ["Присесть", KEY_CTRL], "grab": ["Взаимодействие", KEY_E],
	"teleport": ["Телепорт", KEY_T], "tool_inventory": ["Колесо снаряжения", KEY_TAB],
	"build_rotate_left": ["Наклон установки влево", KEY_Q], "build_rotate_right": ["Наклон установки вправо", KEY_R],
	"previous_tool": ["Предыдущий инструмент", KEY_X],
	"cassette_library": ["Кассеты бумбокса", KEY_B],
	"place_boombox": ["Поставить бумбокс", KEY_G],
	"secret_shot": ["Выстрел из пневматики", KEY_F],
	"voice_chat": ["Голосовая связь (удерживать)", KEY_V],
	"bot_chat": ["Чат с ботом", KEY_J],
	"open_map": ["Полноэкранная карта", KEY_M],
	"map_zoom": ["Масштаб мини-карты", KEY_N],
	"toggle_help": ["Справка", KEY_F1], "toggle_stats": ["Статистика", KEY_F3],
	"quality": ["Смена качества", KEY_F4], "reset_level": ["Перезапуск карты", KEY_F5],
	"bench": ["Проверка производительности", KEY_F6],
}


static func install(custom: Dictionary) -> void:
	for action in BINDINGS:
		bind(action, int(custom.get(action, BINDINGS[action][1])))
	for i in PlayerTools.NUMBERED_TOOLS:
		bind("tool_%d" % (i + 1), KEY_1 + i)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", click)


static func bind(action: String, key: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	_add_key(action, key)
	if action == "crouch" and key == KEY_CTRL:
		_add_key(action, KEY_C)


static func key_name(action: String) -> String:
	var key := int(GameState.bindings.get(action, BINDINGS[action][1]))
	return OS.get_keycode_string(key as Key)


static func _add_key(action: String, key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key as Key
	InputMap.action_add_event(action, event)
