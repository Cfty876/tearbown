class_name MapFog
extends RefCounted

const CELLS := 64
const UNSEEN := Color(0.04, 0.08, 0.10, 0.51)
var _layers := {}
var _last := {}


func texture(floor_id: int) -> ImageTexture:
	return _layer(floor_id).texture


func explored(floor_id: int, uv: Vector2) -> bool:
	var image: Image = _layer(floor_id).image
	return image.get_pixelv(_cell(uv)).a < 0.01


func _cell(uv: Vector2) -> Vector2i:
	return Vector2i(uv * CELLS).clamp(Vector2i.ZERO, Vector2i.ONE * (CELLS - 1))


func _layer(floor_id: int) -> Dictionary:
	if not _layers.has(floor_id):
		var mask := Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
		mask.fill(UNSEEN)
		_layers[floor_id] = {"image": mask, "texture": ImageTexture.create_from_image(mask)}
	return _layers[floor_id]


func reveal(floor_id: int, uv: Vector2, radius: float) -> bool:
	var cell := _cell(uv)
	if _last.get(floor_id, Vector2i(-1, -1)) == cell:
		return false
	_last[floor_id] = cell
	var layer := _layer(floor_id)
	var pixels := maxi(1, ceili(radius * CELLS))
	var image: Image = layer.image
	var changed := false
	for y in range(maxi(0, cell.y - pixels), mini(CELLS, cell.y + pixels + 1)):
		for x in range(maxi(0, cell.x - pixels), mini(CELLS, cell.x + pixels + 1)):
			if (Vector2i(x, y) - cell).length_squared() <= pixels * pixels and image.get_pixel(x, y).a > 0.0:
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed = true
	if changed:
		layer.texture.update(image)
	return changed
