extends Node

signal packet(data: Dictionary)
var connected := false
var is_host := false
var code := ""
var last_error := ""
var _browser
var _listener
var _pending: Array[Dictionary] = []


func _ready() -> void:
	if OS.has_feature("web"):
		_browser = JavaScriptBridge.get_interface("BreakpointRooms")
		if _browser:
			_listener = JavaScriptBridge.create_callback(_from_browser)
			_browser.attach(_listener)


func available() -> bool:
	return _browser != null


func show_rooms() -> void:
	if _browser:
		_browser.show()


func send(data: Dictionary, reliable := true) -> bool:
	return connected and bool(_browser.send(JSON.stringify(data), reliable))


func drain() -> void:
	for data in _pending:
		packet.emit(data)
	_pending.clear()


func leave() -> void:
	if _browser:
		_browser.close()
	connected = false
	_pending.clear()


func _from_browser(args: Array) -> void:
	if args.size() != 2:
		return
	var kind := str(args[0])
	var raw := str(args[1])
	if kind == "closed":
		connected = false
		last_error = raw
		GameState.to_menu.call_deferred()
		return
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		return
	if kind == "open":
		connected = true
		is_host = bool(data.get("host", false))
		code = str(data.get("code", ""))
		last_error = ""
		GameState.start.call_deferred(GameState.LEVEL_HIDE)
	elif kind == "packet" and connected:
		if packet.get_connections().is_empty():
			if _pending.size() < 128:
				_pending.append(data)
		else:
			packet.emit(data)
