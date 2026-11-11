extends Control
const Materials = preload("res://sample/unified_materials.gd")
const THEMES := ["grass","water","rock","fire"]
const DESCRIPTIONS := ["密林 · 泥土地面","深潭 · 湖岸沙面","岩窟 · 碎石地面","火谷 · 冷却火山岩"]

func diamond(c: Vector2, width: float = 56.0, height: float = 38.0) -> PackedVector2Array:
	return PackedVector2Array([c+Vector2(0,-height),c+Vector2(width,0),c+Vector2(0,height),c+Vector2(-width,0)])

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("151720"))
	var font := UIKit.font()
	draw_string(font,Vector2(24,38),"地区地表 · 普通地面与危险地形分开设计",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("f9e2af"))
	draw_string(font,Vector2(24,65),"同样的平地规则，不同的地区材质；真正的熔岩在所有地区保持高亮液态。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a6adc8"))
	for index in 4:
		var theme: String = THEMES[index]
		var x := 20.0 + index*314
		draw_rect(Rect2(x,88,298,590),Color("1d2029"))
		draw_string(font,Vector2(x+14,119),DESCRIPTIONS[index],HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("cdd6f4"))
		var c := Vector2(x+149,196)
		Materials.paint(self,diamond(c,72,48),TerrainDB.PLAIN,theme)
		draw_string(font,Vector2(x+14,270),"普通地面 · 可正常行走",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a6e3a1"))
		for gy in 3:
			for gx in 3:
				var center := Vector2(x+149+(gx-gy)*40,310+(gx+gy)*26)
				Materials.paint(self,diamond(center,40,26),TerrainDB.PLAIN,theme)
		draw_string(font,Vector2(x+14,476),"真正的熔岩 · 危险地形",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f38ba8"))
		Materials.paint(self,diamond(Vector2(x+149,549),72,48),TerrainDB.LAVA,theme)
		draw_string(font,Vector2(x+14,638),"色调随地区，机制按地形类型。",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("a6adc8"))
