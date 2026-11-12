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
static var grass_sprite: Texture2D

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
	if value == TerrainDB.SHALLOW_GRASS: return BaseArt.tile(0)
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

const LIQUID_DEPTH := Vector2(0,6)
const EDGE_NEIGHBORS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func is_liquid(value: int) -> bool:
	return value in [TerrainDB.WATER, TerrainDB.DEEP, TerrainDB.LAVA]

static func surface(shape: PackedVector2Array, value: int) -> PackedVector2Array:
	var result := shape.duplicate()
	if is_liquid(value):
		for i in result.size(): result[i] += LIQUID_DEPTH
	return result

static func bank_edges(values: Array, cell: Vector2i) -> Array[int]:
	var edges: Array[int] = []
	for i in 4:
		var neighbor: Vector2i = cell + EDGE_NEIGHBORS[i]
		if GridSpec.is_inside(neighbor) and not is_liquid(values[GridSpec.index(neighbor)]): edges.append(i)
	return edges

static func draw_banks(canvas: CanvasItem, shape: PackedVector2Array, edges: Array[int], biome: String) -> void:
	var soil := Color("655442")
	match biome:
		"water": soil = Color("91764d")
		"fire": soil = Color("49414a")
		"rock": soil = Color("615d68")
	for i in edges:
		var a := shape[i]
		var b := shape[(i+1)%4]
		canvas.draw_colored_polygon(PackedVector2Array([a,b,b+LIQUID_DEPTH,a+LIQUID_DEPTH]),soil.darkened(0.12 if i in [0,3] else 0.3))
		canvas.draw_line(a,b,soil.lightened(0.18),1)
		canvas.draw_line(a+LIQUID_DEPTH,b+LIQUID_DEPTH,Color(0.08,0.09,0.12,0.7),1)

static func draw_grass(canvas: CanvasItem, center: Vector2) -> void:
	if grass_sprite == null: grass_sprite = load("res://assets/pixel_sample/grass-clump-v1.png")
	canvas.draw_texture_rect(grass_sprite,Rect2(center+Vector2(-47,-34),Vector2(94,52)),false)

static func immersion_line(value: int) -> float:
	return -8.0 if value == TerrainDB.DEEP else 4.0

static func water_cover_shape(shape: PackedVector2Array, line_y: float) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	for i in shape.size():
		var a := shape[i]
		var b := shape[(i+1)%shape.size()]
		if a.y >= line_y: clipped.append(a)
		if (a.y >= line_y) != (b.y >= line_y):
			clipped.append(a.lerp(b,(line_y-a.y)/(b.y-a.y)))
	# The lowered surface extends six pixels into the next cell. Ground draw order
	# hides that overlap, but this foreground pass runs AFTER all the ground.
	# Clip it to the logical tile too, so it cannot repaint the nearer bank.
	var tile_boundary := shape.duplicate()
	for i in tile_boundary.size(): tile_boundary[i] -= LIQUID_DEPTH
	var intersections := Geometry2D.intersect_polygons(clipped,tile_boundary)
	return intersections[0] if not intersections.is_empty() else PackedVector2Array()

static func draw_water_cover(canvas: CanvasItem, shape: PackedVector2Array, center: Vector2, value: int, biome: String) -> void:
	var line_y := center.y + immersion_line(value)
	var clipped := water_cover_shape(shape,line_y)
	if clipped.size() < 3: return
	var part := ground(value,biome)
	var atlas_size := Vector2(part.atlas.get_size())
	var mapping := Transform2D(shape[1]-shape[0],shape[3]-shape[0],shape[0]).affine_inverse()
	var uv := PackedVector2Array()
	for p in clipped: uv.append((part.region.position+(mapping*p)*part.region.size)/atlas_size)
	# Exact same texture coordinates as the floor: no rectangular patch over the actor.
	canvas.draw_polygon(clipped,PackedColorArray([Color(0.83,0.83,0.87)]),uv,part.atlas)
	var ripple := Color("548ba6") if value == TerrainDB.DEEP else Color("88c6cf")
	canvas.draw_line(Vector2(center.x-22,line_y+2),Vector2(center.x-10,line_y+2),ripple,1)
	canvas.draw_line(Vector2(center.x+10,line_y+2),Vector2(center.x+22,line_y+2),ripple,1)

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
