extends RefCounted
const BaseArt = preload("res://sample/pixel_art.gd")
const SUPPLEMENT := {
	TerrainDB.DEEP:0, TerrainDB.LAVA:1, TerrainDB.FRAGILE:2, TerrainDB.PIT:3,
	TerrainDB.ICE:4, TerrainDB.VINES:5, TerrainDB.SHALLOW_GRASS:6,
	TerrainDB.BLUE_FIRE:7, TerrainDB.ROCK_MOUNTAIN:8,
}
const ORIGINAL := {
	TerrainDB.PLAIN:2, TerrainDB.WATER:1, TerrainDB.GRASS:0,
	TerrainDB.TREE:0, TerrainDB.OBSTACLE:2,
}
static var biome_atlas: Texture2D
static var biome_cache: Dictionary = {}
static var atlas: Texture2D
static var cache: Dictionary = {}

static func tile(index: int) -> AtlasTexture:
	if atlas == null: atlas = load("res://assets/pixel_sample/terrain-nest-v1.png")
	if not cache.has(index):
		var part := AtlasTexture.new()
		part.atlas = atlas
		var step := Vector2(atlas.get_size()) / 4.0
		part.region = Rect2(Vector2(index % 4,index / 4) * step, step)
		part.filter_clip = true
		cache[index] = part
	return cache[index]

static func biome_tile(index: int) -> AtlasTexture:
	if biome_atlas == null: biome_atlas = load("res://assets/pixel_sample/biome-ground-v1.png")
	if not biome_cache.has(index):
		var part := AtlasTexture.new()
		part.atlas = biome_atlas
		var step := Vector2(biome_atlas.get_size()) / 2.0
		part.region = Rect2(Vector2(index % 2,index / 2) * step,step)
		part.filter_clip = true
		biome_cache[index] = part
	return biome_cache[index]

static func ground(value: int, biome: String = "rock") -> AtlasTexture:
	if value == TerrainDB.LAVA: return biome_tile(2)
	if value in [TerrainDB.PLAIN, TerrainDB.OBSTACLE]:
		match biome:
			"grass": return biome_tile(0)
			"water": return biome_tile(1)
			"fire": return tile(1)
	if ORIGINAL.has(value): return BaseArt.tile(ORIGINAL[value])
	return tile(SUPPLEMENT.get(value,14))

static func paint(canvas: CanvasItem, shape: PackedVector2Array, value: int, biome: String = "rock") -> void:
	var part := ground(value, biome)
	var r := part.region
	var size := Vector2(part.atlas.get_size())
	var uv := PackedVector2Array([r.position/size,Vector2(r.end.x,r.position.y)/size,r.end/size,Vector2(r.position.x,r.end.y)/size])
	canvas.draw_polygon(shape,PackedColorArray([Color(0.83,0.83,0.87)]),uv,part.atlas)
	canvas.draw_polyline(shape+PackedVector2Array([shape[0]]),Color(0.12,0.13,0.16,0.65),1)

static func nest_index(data: Dictionary) -> int:
	if not data.get("alive",false) or int(data.get("hp",0)) <= 0: return 13
	return 12 if int(data.get("hp",0)) * 2 <= int(data.get("max_hp",1)) else 11

static func draw_nest(canvas: CanvasItem, font: Font, center: Vector2, data: Dictionary) -> void:
	canvas.draw_texture_rect(tile(nest_index(data)),Rect2(center+Vector2(-50,-69),Vector2(100,100)),false)
	if nest_index(data) == 13: return
	var maximum := maxi(1,int(data.get("max_hp",1)))
	var life := clampi(int(data.get("hp",0)),0,maximum)
	var color := Color("f9e2af") if int(data.get("guards",0)) > 0 else Color("c39aef")
	canvas.draw_rect(Rect2(center+Vector2(-28,25),Vector2(56,6)),Color("232330"))
	canvas.draw_rect(Rect2(center+Vector2(-27,26),Vector2(54.0*life/maximum,4)),color)
	canvas.draw_string(font,center+Vector2(-24,42),"%d/%d" % [life,maximum],HORIZONTAL_ALIGNMENT_CENTER,48,11,Color("e8e3ee"))
