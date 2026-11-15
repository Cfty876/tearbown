class_name RoomActor
extends RefCounted

var avatar: VoxelAvatar
var proxy: Player
var at := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var crouch := false
var running := false
var seen := false
var hidden := -1
var serial := -1
var step := -1
var spray_until := 0
var horn_at := -2000
var ping_at := -2000
var question_at := -2000
