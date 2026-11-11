extends RefCounted
## Deliberately sparse material grammar: broad color planes, no noise textures.
const COLORS := {
	TerrainDB.PLAIN: Color("9f784f"), TerrainDB.WATER: Color("347f9b"),
	TerrainDB.DEEP: Color("203f60"), TerrainDB.GRASS: Color("376247"),
	TerrainDB.OBSTACLE: Color("716b67"), TerrainDB.LAVA: Color("533239"),
	TerrainDB.FRAGILE: Color("987043"), TerrainDB.PIT: Color("302f38"),
	TerrainDB.ICE: Color("82b6c9"), TerrainDB.VINES: Color("405c40"),
	TerrainDB.TREE: Color("586d42"), TerrainDB.SHALLOW_GRASS: Color("7d8b4c"),
	TerrainDB.BLUE_FIRE: Color("304862"), TerrainDB.ROCK_MOUNTAIN: Color("687782"),
}
const CUES := {
	0:"暖棕土面",1:"浅蓝 · 短波纹",2:"深蓝 · 内侧暗面",3:"深绿 · 成簇草叶",4:"灰褐 · 块状岩石",5:"暗岩 · 单道熔流",6:"赭黄 · 主裂缝",7:"黑色内凹坑缘",8:"冰蓝 · 斜向硬反光",9:"暗绿 · 两根藤条",10:"林地 · 直立树木",11:"橄榄绿 · 稀疏短草",12:"炭蓝 · 青色火焰",13:"冷灰 · 高耸棱峰",
}

static func points(center: Vector2, offsets: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in offsets: p.append(center + Vector2(v[0],v[1]))
	return p

static func paint(canvas: CanvasItem, shape: PackedVector2Array, value: int, alternate: bool = false) -> void:
	var base: Color = COLORS.get(value, Color.MAGENTA)
	if alternate: base = base.lightened(0.025)
	var c := (shape[0] + shape[2]) * 0.5
	canvas.draw_colored_polygon(shape, base)
	canvas.draw_line(shape[0],shape[1],base.lightened(0.15),1)
	canvas.draw_line(shape[0],shape[3],base.lightened(0.15),1)
	canvas.draw_line(shape[1],shape[2],base.darkened(0.23),1)
	canvas.draw_line(shape[3],shape[2],base.darkened(0.23),1)
	match value:
		TerrainDB.WATER:
			canvas.draw_line(c + Vector2(-24,-5), c + Vector2(-2,-5), Color("75b7cb"),2)
			canvas.draw_line(c + Vector2(10,12), c + Vector2(26,12), Color("559bb6"),2)
		TerrainDB.DEEP:
			canvas.draw_colored_polygon(points(c,[[-33,0],[-4,-20],[30,0],[3,20]]),Color("193650"))
			canvas.draw_line(c + Vector2(-20,-9), c + Vector2(-2,-9),Color("365d7c"),2)
		TerrainDB.GRASS, TerrainDB.SHALLOW_GRASS:
			var tall := value == TerrainDB.GRASS
			for x in ([-24,0,22] if tall else [-25,24]):
				var at := c + Vector2(x,8 if x else -8)
				canvas.draw_polyline(PackedVector2Array([at+Vector2(-5,-6 if tall else -3),at,at+Vector2(3,-11 if tall else -5)]),base.lightened(0.18),2)
		TerrainDB.LAVA:
			var flow := points(c,[[-40,-4],[-14,-5],[4,1],[24,-2],[39,4],[13,9],[-7,7],[-29,4]])
			canvas.draw_colored_polygon(flow,Color("d66b35"))
			canvas.draw_polyline(points(c,[[-34,-1],[-12,0],[2,5],[25,3]]),Color("f3bb5c"),3)
		TerrainDB.FRAGILE:
			canvas.draw_polyline(points(c,[[-32,-10],[-11,-3],[-3,9],[24,13]]),Color("4b382e"),3)
			canvas.draw_line(c+Vector2(-11,-3),c+Vector2(5,-18),Color("4b382e"),2)
		TerrainDB.PIT:
			var inside := PackedVector2Array()
			for p in shape: inside.append(c+(p-c)*0.78)
			canvas.draw_colored_polygon(inside,Color("10131e"))
			canvas.draw_line(inside[3],inside[0],Color("514b52"),4)
			canvas.draw_line(inside[0],inside[1],Color("22222f"),5)
		TerrainDB.ICE:
			canvas.draw_colored_polygon(points(c,[[-34,1],[-24,8],[14,-12],[7,-17]]),Color("bedfe5"))
			canvas.draw_line(c+Vector2(1,19),c+Vector2(27,3),Color("a8d3dd"),3)
		TerrainDB.VINES:
			for offset in [-8,10]:
				var vine := points(c,[[-32,offset+1],[-16,offset-7],[1,offset],[18,offset-5],[31,offset]])
				canvas.draw_polyline(vine,Color("243f32"),7)
				canvas.draw_polyline(vine,Color("7c9b58"),3)
		TerrainDB.BLUE_FIRE:
			canvas.draw_colored_polygon(points(c,[[-14,9],[-19,-2],[-8,1],[0,-20],[5,-3],[14,-10],[17,6],[6,14]]),Color("39a9d2"))
			canvas.draw_colored_polygon(points(c,[[-5,9],[-5,0],[2,-8],[7,7],[2,12]]),Color("a0e3ed"))
		TerrainDB.ROCK_MOUNTAIN:
			canvas.draw_colored_polygon(points(c,[[-33,1],[-3,-20],[28,0],[5,18]]),base.darkened(0.15))
		TerrainDB.TREE:
			canvas.draw_line(c+Vector2(-14,-1),c+Vector2(18,12),Color("6d6944"),4)
		TerrainDB.OBSTACLE:
			canvas.draw_colored_polygon(points(c,[[-24,-3],[-5,-15],[20,-1],[3,12]]),base.lightened(0.06))

static func mountain(canvas: CanvasItem, c: Vector2, alpha: float = 1.0) -> void:
	canvas.draw_colored_polygon(points(c,[[-46,17],[-24,-22],[-11,-52],[1,-82],[23,-48],[33,-15],[48,17]]),Color(0.24,0.29,0.34,alpha))
	canvas.draw_colored_polygon(points(c,[[-46,17],[-11,-52],[1,-82],[4,-19],[-2,17]]),Color(0.56,0.62,0.66,alpha))
	canvas.draw_colored_polygon(points(c,[[4,-19],[1,-82],[23,-48],[33,-15],[48,17],[-2,17]]),Color(0.37,0.44,0.51,alpha))
	canvas.draw_line(c+Vector2(-25,-12),c+Vector2(3,-29),Color(0.65,0.69,0.7,alpha),3)
