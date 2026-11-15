class_name SchoolWeather
extends Node3D

var controller: SchoolSecrets
var _poll := 0.0
var _drip := 2.0


func _process(delta: float) -> void:
	var at := controller.player.global_position
	_poll -= delta
	_drip -= delta
	if _poll <= 0.0:
		_poll = 0.33
		var pump := Vector3(50.25, -2.2, -45.8)
		var near_pump := at.y < 0.1 and at.distance_squared_to(pump) < 930.0
		controller.world.sfx.loop("school_pump", "school_pump", pump, near_pump, -15.0)
	if _drip <= 0.0:
		_drip = 2.9
		var tap := Vector3(-16.05, 6.9, -17.55)
		if at.distance_squared_to(tap) < 49.0:
			controller.world.sfx.play("school_drip", tap, -12.0)
