class_name SchoolGrid
extends RefCounted
## All footprints use 10 cm cells. Adjoining edges are legal; intersecting footprints are not.

const SITES := {
	"west": Rect2i(-290, -290, 190, 600),
	"east": Rect2i(100, -290, 190, 600),
	"bridge": Rect2i(-100, -60, 200, 120),
	"entry": Rect2i(-56, 60, 112, 64),
	"sports_bridge": Rect2i(290, -25, 60, 50),
	"annex": Rect2i(350, -150, 230, 340),
	"stadium": Rect2i(-540, -700, 590, 330),
	"stands": Rect2i(-350, -750, 200, 46),
	"maze": Rect2i(-144, -368, 125, 65),
	"greenhouse": Rect2i(190, -650, 168, 176),
	"boiler": Rect2i(440, -600, 161, 142),
	"workshop": Rect2i(420, 340, 155, 125),
	"garage": Rect2i(430, 590, 150, 147),
	"transformer": Rect2i(630, -362, 60, 43),
	"chips": Rect2i(611, -486, 44, 39),
}

var bounds: Rect2i
var placements := {}


func _init(area: Rect2i) -> void:
	bounds = area


func claim(key: String, rect: Rect2i) -> bool:
	if placements.has(key) or not bounds.encloses(rect) or rect.size.x <= 0 or rect.size.y <= 0:
		return false
	for existing: Rect2i in placements.values():
		if rect.intersects(existing):
			return false
	placements[key] = rect
	return true


func reserve(origin: Vector3i, width: int, depth: int) -> bool:
	return claim(str(origin), Rect2i(origin.x, origin.z, width, depth))


func protect(key: String, rect: Rect2i) -> void:
	var clipped := bounds.intersection(rect)
	if clipped.has_area():
		placements[key] = clipped


func fits_volume(volume: VoxelVolume, at: Vector3i, extent: Vector3i) -> bool:
	var limit := volume.get_size()
	if at.x < 0 or at.y < 0 or at.z < 0:
		return false
	var end := at + extent
	if end.x > limit.x or end.y > limit.y or end.z > limit.z:
		return false
	for x in range(at.x, end.x):
		for z in range(at.z, end.z):
			if at.y > 0 and volume.get_voxel(Vector3i(x, at.y - 1, z)) == 0:
				return false
			for y in range(at.y, end.y):
				if volume.get_voxel(Vector3i(x, y, z)) != 0:
					return false
	return true


static func origin(key: String, y: float) -> Vector3:
	var site: Rect2i = SITES[key]
	return Vector3(site.position.x * 0.1, y, site.position.y * 0.1)


static func center(key: String, y: float) -> Vector3:
	var site: Rect2i = SITES[key]
	var middle := Vector2(site.position) + Vector2(site.size) * 0.5
	return Vector3(middle.x * 0.1, y, middle.y * 0.1)


static func validate() -> Array[String]:
	var grid := SchoolGrid.new(Rect2i(-800, -800, 1600, 1600))
	var conflicts: Array[String] = []
	for key: String in SITES:
		if not grid.claim(key, SITES[key]):
			conflicts.append(key)
	return conflicts
