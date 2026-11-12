extends Control
const Art = preload("res://sample/pixel_art.gd")
func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720),Color("151720"))
	var font := UIKit.font()
	draw_string(font,Vector2(20,34),"完整单位像素图鉴 · 含训练家与召唤物",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("f9e2af"))
	var index := 0
	for species in SpeciesDB.SPECIES:
		var x := 18.0+(index%8)*157
		var y := 64.0+(index/8)*207
		draw_rect(Rect2(x,y,146,195),Color("242632"))
		draw_texture_rect(Art.tile(Art.unit_index(species)),Rect2(x+25,y+12,96,96),false)
		draw_string(font,Vector2(x+8,y+143),SpeciesDB.name_of(species),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("cdd6f4"))
		draw_string(font,Vector2(x+8,y+173),species,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("a6adc8"))
		index += 1
