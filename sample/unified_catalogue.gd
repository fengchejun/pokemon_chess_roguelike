extends Control
const Materials = preload("res://sample/unified_materials.gd")
const Art = preload("res://sample/pixel_art.gd")
const CUES := ["细土与碎石","浅蓝水纹","深蓝水纹","密集草叶","块状岩障","暗岩与熔流","断裂土层","内凹深坑","冰面切线","交织藤蔓","林地与树冠","稀疏浅草","炭地与蓝焰","冷灰高岩峰"]

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("151720"))
	var font := UIKit.font()
	draw_string(font,Vector2(20,36),"统一像素材质 · 地形与巢穴",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("f9e2af"))
	draw_string(font,Vector2(20,64),"14种地形 + 巢穴完好 / 受损 / 摧毁 · 沿用第一版像素颗粒、轮廓与光源",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a6adc8"))
	for index in 17:
		var x := 16.0 + (index % 6) * 208
		var y := 84.0 + (index / 6) * 201
		draw_rect(Rect2(x,y,196,192),Color("1d2029"))
		var name: String = TerrainDB.name_of(TerrainDB.ALL[index]) if index < 14 else ["巢穴 · 完好","巢穴 · 受损","巢穴 · 摧毁"][index-14]
		draw_string(font,Vector2(x+10,y+25),name,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("cdd6f4"))
		var c := Vector2(x+98,y+112)
		var shape := PackedVector2Array([c+Vector2(0,-38),c+Vector2(56,0),c+Vector2(0,38),c+Vector2(-56,0)])
		var wall := PackedVector2Array([shape[3],shape[2],shape[1],shape[1]+Vector2(0,12),shape[2]+Vector2(0,12),shape[3]+Vector2(0,12)])
		draw_colored_polygon(wall,Color("303440"))
		if index < 14:
			var value: int = TerrainDB.ALL[index]
			Materials.paint(self,Materials.surface(shape,value),value)
			if Materials.is_liquid(value): Materials.draw_banks(self,shape,[0,3],"rock")
			if value==TerrainDB.GRASS: Materials.draw_grass(self,c,false)
			if value in [TerrainDB.TREE,TerrainDB.OBSTACLE]:
				draw_texture_rect(Art.tile(12 if value==TerrainDB.TREE else 13),Rect2(c+Vector2(-43,-74),Vector2(86,86)),false)
			elif value==TerrainDB.ROCK_MOUNTAIN:
				draw_texture_rect(Materials.tile(9),Rect2(c+Vector2(-46,-75),Vector2(92,98)),false)
			elif value==TerrainDB.BLUE_FIRE:
				draw_texture_rect(Materials.tile(10),Rect2(c+Vector2(-23,-39),Vector2(46,46)),false)
			draw_string(font,Vector2(x+10,y+180),CUES[value],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a6adc8"))
		else:
			Materials.paint(self,shape,TerrainDB.PLAIN)
			Materials.draw_nest(self,font,c,{"alive":index!=16,"hp":30 if index==14 else 10 if index==15 else 0,"max_hp":30})
			if index==16: draw_string(font,Vector2(x+10,y+180),"保留废墟 · 不再显示血条",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a6adc8"))
	draw_string(font,Vector2(1060,690),"同套图集 · 实机同源绘制",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a6adc8"))
