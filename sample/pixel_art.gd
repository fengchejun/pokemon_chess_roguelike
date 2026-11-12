extends RefCounted
static var source: Texture2D
static var cache: Dictionary = {}
const EXTRA := {"trainer":0,"tree_summon":1,"rock_starter":2,"ice_starter":3,"wind_starter":4,
	"fire_wild1":5,"fire_wild2":6,"water_wild1":7,"water_wild2":8,"grass_wild1":9,
	"grass_wild2":10,"electric_wild1":11,"electric_wild2":12,"rock_wild1":13,
	"rock_wild2":14,"ice_wild1":3,"torkoal":15,"cloyster":16,"ampharos":17,"wind_wild1":4}
const FILES := ["trainer","709","74","361","16","37","58","54","60","43","69","81","100","95","75","324","91","181"]

static func tile(index: int) -> AtlasTexture:
	if index >= 100:
		if not cache.has(index):
			var texture: Texture2D = load("res://assets/pixel_sample/units/%s.png" % FILES[index-100])
			var image := texture.get_image()
			var bounds := image.get_used_rect()
			var side := maxi(bounds.size.x,bounds.size.y)+6
			var crop := Rect2(Vector2(bounds.position)+Vector2(bounds.size)*0.5-Vector2.ONE*side*0.5,Vector2.ONE*side)
			var part := AtlasTexture.new()
			part.atlas = texture
			part.region = crop
			part.filter_clip = true
			cache[index] = part
		return cache[index]
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
	if EXTRA.has(species): return 100+int(EXTRA[species])
	return {"fire_starter": 4, "water_starter": 5, "grass_starter": 6, "electric_starter": 7}.get(species, -1)
