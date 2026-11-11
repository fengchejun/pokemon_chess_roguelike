extends RefCounted
static var source: Texture2D
static var cache: Dictionary = {}

static func tile(index: int) -> AtlasTexture:
	if source == null:
		source = load("res://assets/pixel_sample/atlas-v1.png")
	if not cache.has(index):
		var part := AtlasTexture.new()
		part.atlas = source
		var step := Vector2(source.get_width(), source.get_height()) / 4.0
		part.region = Rect2(Vector2(index % 4, index / 4) * step, step)
		part.filter_clip = true
		cache[index] = part
	return cache[index]

static func terrain_index(value: int) -> int:
	match value:
		TerrainDB.PLAIN: return 2
		TerrainDB.GRASS, TerrainDB.SHALLOW_GRASS, TerrainDB.TREE: return 0
		TerrainDB.WATER: return 1
		TerrainDB.OBSTACLE: return 3
	return -1

static func unit_index(species: String) -> int:
	return {"fire_starter": 4, "water_starter": 5, "grass_starter": 6, "electric_starter": 7}.get(species, -1)
