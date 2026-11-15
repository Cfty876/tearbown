class_name MapAtlas
extends RefCounted
## Карта строится из тех же размеров, что и геометрия уровня.

const PIXELS := 512
const GROUND := Color("#2e4943")
const DARK := Color("#1b3039")
const SCHOOL_NAMES := {"west": "Корпус А", "east": "Корпус Б", "annex": "Спорткорпус",
	"stadium": "Стадион", "greenhouse": "Теплица", "boiler": "Котельная",
	"workshop": "Мастерские", "garage": "Гараж"}
const DISTRICT_NAMES := {"foodmart": "Пятёрочка", "pharmacy": "Аптека", "autoshop": "СТО",
	"block1": "Дом 1", "block2": "Дом 2", "block3": "Дом 3", "block4": "Дом 4", "block5": "Дом 5"}
const COMPACT_NAMES := {"house": "Дом", "barn": "Амбар", "tower": "Башня", "garage": "Гараж", "greenhouse": "Теплица", "Укрытие": "Укрытие"}
const UPPER := ["west", "east", "bridge", "sports_bridge", "annex"]

var half := 40.0
var school := false
var sites: Array[Dictionary] = []
var roads: Array[Rect2] = []
var walks: Array[Rect2] = []
var tunnels: Array[Rect2] = []
var rooms: Array[Dictionary] = []
var _textures := {}
var _district: Texture2D
var _trees := PackedVector2Array()


func collect(main, world: VoxelWorld) -> void:
	half = world.player.border + 0.6
	school = main.level is SchoolLevel
	if school:
		for key: String in SchoolGrid.SITES:
			var r: Rect2i = SchoolGrid.SITES[key]
			var area := Rect2(Vector2(r.position) * 0.1, Vector2(r.size) * 0.1)
			sites.append({"area": area, "name": SCHOOL_NAMES.get(key, ""), "key": key})
		roads.assign(SchoolCampus.ROADS)
		walks.assign(SchoolCampus.WALKS + SchoolCampus.EXTRA_WALKS)
		for group in SchoolBasement.TUNNELS.values():
			for r: Rect2i in group:
				tunnels.append(Rect2(r))
		for room: Dictionary in main.level.rooms:
			if not room.plan.has("area"):
				continue
			var at: Vector3 = room.at
			var area: Rect2i = room.plan.area
			var span := Vector2(area.size) * 0.1
			var title := SchoolRooms.title(room.type).capitalize() if room.type in ["chem", "physics", "it", "library", "medical", "teachers", "art", "wood"] else ""
			rooms.append({"area": Rect2(Vector2(at.x, at.z) - span * 0.5, span), "floor": int(room.floor) - 1, "title": title})
	elif main.level is DistrictLevel:
		_district = main.level.map_surface()
		for area: Rect2i in DistrictSecretMap.PASSAGES:
			tunnels.append(Rect2(area))
		for key: String in main.level.buildings:
			var node = main.level.buildings[key]
			if is_instance_valid(node) and node is VoxelObject:
				_add(node, DISTRICT_NAMES.get(key, ""), key)
	else:
		for node in world.objects:
			if COMPACT_NAMES.has(node.label):
				_add(node, COMPACT_NAMES[node.label], node.label)
	if _district == null:
		for node in world.objects:
			if is_instance_valid(node) and node.is_tree:
				var pos := node.world_center()
				_trees.append(Vector2(pos.x, pos.z))


func _add(node: VoxelObject, caption: String, key: String) -> void:
	var box := node.global_transform * AABB(Vector3.ZERO, Vector3(node.volume.get_size()) * VoxelObject.VS)
	sites.append({"area": Rect2(box.position.x, box.position.z, box.size.x, box.size.z), "name": caption, "key": key})


func uv(point: Vector2) -> Vector2:
	return point / (half * 2.0) + Vector2.ONE * 0.5


func layer_at(y: float) -> int:
	if y < -0.60 and not tunnels.is_empty():
		return -1
	return clampi(floori((y - 2.2 + 0.45) / 3.8), 0, 4) if school else 0


func layers() -> Array[int]:
	return [-1, 0, 1, 2, 3, 4] if school else ([0] if tunnels.is_empty() else [-1, 0])


static func floor_name(id: int) -> String:
	if id < 0:
		return "Подвал"
	if id == 0:
		return "Поверхность"
	return "Крыша" if id == 4 else "Этаж %d" % (id + 1)


func texture(floor_id: int, monochrome := false) -> Texture2D:
	if monochrome:
		var key := "mono/%d" % floor_id
		if not _textures.has(key):
			var grey := texture(floor_id).get_image()
			grey.convert(Image.FORMAT_L8)
			_textures[key] = ImageTexture.create_from_image(grey)
		return _textures[key]
	if _textures.has(floor_id):
		return _textures[floor_id]
	var image := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	image.fill(GROUND if floor_id == 0 else DARK)
	if floor_id == 0 and _district != null:
		var source := _district.get_image()
		source.resize(PIXELS, PIXELS, Image.INTERPOLATE_BILINEAR)
		image.blit_rect(source, Rect2i(0, 0, PIXELS, PIXELS), Vector2i.ZERO)
	if floor_id == 0:
		for r in roads:
			_stamp(image, r, Color("#667175"))
			_stamp(image, r.grow(-0.30), Color("#424e54"))
		for r in walks:
			_stamp(image, r, Color("#7d847c"))
		for p in _trees:
			_stamp(image, Rect2(p - Vector2.ONE * 1.4, Vector2.ONE * 2.8), Color("#244139"))
			_stamp(image, Rect2(p - Vector2.ONE * 0.65, Vector2.ONE * 1.3), Color("#527460"))
	if floor_id >= 0:
		for site in sites:
			if floor_id > 0 and site.key not in UPPER:
				continue
			var r: Rect2 = site.area
			var is_field: bool = site.key in ["stadium", "stands", "maze"]
			_stamp(image, r.grow(0.65), Color("#18292c"))
			_stamp(image, r, Color("#56775c") if is_field else Color("#89968f"))
			_stamp(image, r.grow(-0.43), Color("#416d54") if is_field else Color("#5b6d71"))
			if is_field and r.size.x > 25.0:
				_pitch(image, r.grow(-4.5))
		for room in rooms:
			if int(room.floor) == floor_id:
				_stamp(image, room.area.grow(-0.22), Color("#738186"))
				_stamp(image, room.area.grow(-0.50), Color("#62747c"))
	else:
		for r in tunnels:
			_stamp(image, r.grow(0.26), Color("#425d69"))
		for r in tunnels:
			_stamp(image, r, Color("#65848e"))
	for i in range(32, PIXELS, 32):
		var line := Color("#779298")
		for j in range(5, PIXELS - 5, 8):
			image.set_pixel(i, j, line)
			image.set_pixel(j, i, line)
	_textures[floor_id] = ImageTexture.create_from_image(image)
	return _textures[floor_id]


func _pitch(image: Image, r: Rect2) -> void:
	for line in [Rect2(r.position, Vector2(r.size.x, 0.4)), Rect2(r.end.x - 0.4, r.position.y, 0.4, r.size.y),
			Rect2(r.position.x, r.end.y - 0.4, r.size.x, 0.4), Rect2(r.position, Vector2(0.4, r.size.y)),
			Rect2(r.get_center().x, r.position.y, 0.4, r.size.y)]:
		_stamp(image, line, Color("#aab994"))


func _stamp(image: Image, r: Rect2, tint: Color) -> void:
	if not r.has_area():
		return
	var area := Rect2i(Vector2i(uv(r.position) * PIXELS), Vector2i((r.size * PIXELS / (half * 2.0)).ceil()))
	area = area.intersection(Rect2i(0, 0, PIXELS, PIXELS))
	if area.has_area():
		image.fill_rect(area, tint)
