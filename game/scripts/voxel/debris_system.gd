class_name DebrisSystem
extends Node3D
## Pooled single-voxel debris: server-side rigid boxes drawn by one MultiMesh.
## The pool is a ring buffer, so heavy destruction recycles the oldest cubes
## instead of letting the body count grow.

const MAX := 700
const STRIDE := 16  # 12 transform floats + 4 color floats

var active_count := 0

var _bodies: Array[RID] = []
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _color := PackedColorArray()
var _active := PackedByteArray()
var _sleeping := PackedByteArray()
var _next := 0
var _limit := MAX
var _frame := 0
var _mm: MultiMesh
var _buf := PackedFloat32Array()
var _shapes := {}


func _ready() -> void:
	_bodies.resize(MAX)
	_life.resize(MAX)
	_size.resize(MAX)
	_color.resize(MAX)
	_active.resize(MAX)
	_sleeping.resize(MAX)
	_buf.resize(MAX * STRIDE)
	_buf.fill(0.0)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = box
	_mm.instance_count = MAX
	_mm.buffer = _buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = VoxMat.debris_material
	mmi.custom_aabb = AABB(Vector3(-1000, -200, -1000), Vector3(2000, 1000, 2000))
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	# Bodies are created up front (outside any space) so the first explosion does
	# not pay for hundreds of body_create calls.
	for i in MAX:
		var b := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_set_collision_layer(b, Layers.DEBRIS)
		PhysicsServer3D.body_set_collision_mask(b, Layers.STATIC | Layers.DYNAMIC)
		PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
		PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.15)
		PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.6)
		PhysicsServer3D.body_add_shape(b, _shape(VoxelObject.VS))
		_bodies[i] = b
		_size[i] = VoxelObject.VS


func _exit_tree() -> void:
	for b in _bodies:
		if b.is_valid():
			PhysicsServer3D.free_rid(b)
	_bodies.clear()
	for s in _shapes.values():
		PhysicsServer3D.free_rid(s)
	_shapes.clear()


func _shape(size: float) -> RID:
	var key := roundi(size * 100.0)
	if not _shapes.has(key):
		var s := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(s, Vector3.ONE * size * 0.5)
		_shapes[key] = s
	return _shapes[key]


func set_budget(limit: int) -> void:
	var capped := clampi(limit, 1, MAX)
	for i in range(capped, _limit):
		if _active[i] != 0:
			_retire(i)
	_limit = capped
	_next %= _limit
	_mm.visible_instance_count = _limit


func _retire(i: int) -> void:
	_active[i] = 0
	active_count -= 1
	PhysicsServer3D.body_set_space(_bodies[i], RID())
	for k in 12:
		_buf[i * STRIDE + k] = 0.0


func spawn(pos: Vector3, color: Color, size: float, vel: Vector3) -> void:
	var i := _next
	_next = (_next + 1) % _limit
	var b := _bodies[i]
	if not is_equal_approx(_size[i], size):
		PhysicsServer3D.body_clear_shapes(b)
		PhysicsServer3D.body_add_shape(b, _shape(size))
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_MASS, maxf(size * size * size * 1500.0, 0.3))
	if _active[i] == 0:
		PhysicsServer3D.body_set_space(b, get_world_3d().space)
		active_count += 1
	var basis := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, pos))
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, vel)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
		Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)))
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	_active[i] = 1
	_sleeping[i] = 0
	_life[i] = randf_range(7.0, 13.0)
	_size[i] = size
	_color[i] = color


func blast(pos: Vector3, reach: float, power: float) -> void:
	for i in _limit:
		if _active[i] == 0:
			continue
		var t: Transform3D = PhysicsServer3D.body_get_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM)
		var d := t.origin.distance_to(pos)
		if d > reach:
			continue
		var dir := (t.origin - pos).normalized() + Vector3.UP * 0.3
		var m := _size[i] * _size[i] * _size[i] * 1500.0
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_SLEEPING, false)
		PhysicsServer3D.body_apply_central_impulse(_bodies[i], dir * power * 2.0 * (1.0 - d / reach) * m)
		_sleeping[i] = 0


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame += 1
	var check := _frame % 8
	for i in _limit:
		if _active[i] == 0:
			continue
		_life[i] -= delta
		var o := i * STRIDE
		if _life[i] <= 0.0:
			_retire(i)
			continue
		var b := _bodies[i]
		if i % 8 == check:
			_sleeping[i] = 1 if PhysicsServer3D.body_get_state(b, PhysicsServer3D.BODY_STATE_SLEEPING) else 0
		# Sleeping cubes keep their last transform unless they are fading out.
		if _sleeping[i] == 1 and _life[i] > 1.0:
			continue
		var t: Transform3D = PhysicsServer3D.body_get_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var s := _size[i] * clampf(_life[i], 0.0, 1.0)
		var bx := t.basis.x * s
		var by := t.basis.y * s
		var bz := t.basis.z * s
		_buf[o] = bx.x
		_buf[o + 1] = by.x
		_buf[o + 2] = bz.x
		_buf[o + 3] = t.origin.x
		_buf[o + 4] = bx.y
		_buf[o + 5] = by.y
		_buf[o + 6] = bz.y
		_buf[o + 7] = t.origin.y
		_buf[o + 8] = bx.z
		_buf[o + 9] = by.z
		_buf[o + 10] = bz.z
		_buf[o + 11] = t.origin.z
		var c := _color[i]
		_buf[o + 12] = c.r
		_buf[o + 13] = c.g
		_buf[o + 14] = c.b
		_buf[o + 15] = 1.0
	_mm.buffer = _buf
	VoxelWorld.instance.stats.debris_usec = Time.get_ticks_usec() - t0
