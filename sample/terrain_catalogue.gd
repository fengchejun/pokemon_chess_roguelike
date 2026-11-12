extends Control
const MaterialSet = preload("res://sample/simple_terrain.gd")
const Art = preload("res://sample/pixel_art.gd")

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("151720"))
	var font := UIKit.font()
	draw_string(font,Vector2(24,40),"全地形材质 · 简洁色块方案",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("f9e2af"))
	draw_string(font,Vector2(24,67),"14 种地形 · 无碎石噪点 · 以颜色和少量关键形状区分",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a6adc8"))
	for index in TerrainDB.ALL.size():
		var value: int = TerrainDB.ALL[index]
		var x := 18.0 + (index % 7) * 178
		var y := 106.0 + (index / 7) * 286
		draw_rect(Rect2(x,y,168,264),Color("1d2029"))
		draw_string(font,Vector2(x+12,y+29),TerrainDB.name_of(value),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("cdd6f4"))
		var c := Vector2(x+84,y+145)
		var shape := PackedVector2Array([c+Vector2(0,-38),c+Vector2(56,0),c+Vector2(0,38),c+Vector2(-56,0)])
		var wall := PackedVector2Array([shape[3],shape[2],shape[1],shape[1]+Vector2(0,14),shape[2]+Vector2(0,14),shape[3]+Vector2(0,14)])
		draw_colored_polygon(wall,Color("303440"))
		MaterialSet.paint(self,shape,value)
		if value in [TerrainDB.TREE,TerrainDB.OBSTACLE]:
			draw_texture_rect(Art.tile(12 if value==TerrainDB.TREE else 13),Rect2(c+Vector2(-48,-82),Vector2(96,96)),false)
		elif value==TerrainDB.ROCK_MOUNTAIN:
			MaterialSet.mountain(self,c)
		draw_string(font,Vector2(x+10,y+232),MaterialSet.CUES[value],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a6adc8"))
	draw_string(font,Vector2(24,702),"平地保持安静；危险地形、植被与障碍物用可辨认的结构表达。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a6adc8"))
