class_name RoomBarrier
extends Node3D

func build(half: float) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.23, 0.74, 1.0, 0.16)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = 34.0
	material.distance_fade_max_distance = 9.0
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.STATIC
	wall.collision_mask = 0
	add_child(wall)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var depth := 0.36
		var span := half * 2.0 + depth
		var size := Vector3(depth, 100, span) if axis.x != 0 else Vector3(span, 100, depth)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = axis * (half + depth * 0.5) + Vector3.UP * 17.0
		wall.add_child(collision)
		var visible_wall := MeshInstance3D.new()
		var plane := QuadMesh.new()
		plane.size = Vector2(span, 89.0)
		visible_wall.mesh = plane
		visible_wall.material_override = material
		visible_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visible_wall.position = axis * half + Vector3.UP * 22.0
		visible_wall.rotation.y = PI * 0.5 if axis.x != 0 else 0.0
		wall.add_child(visible_wall)
