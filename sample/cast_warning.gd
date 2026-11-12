extends RefCounted

static func cells_for(cast: Dictionary, terrain: Array) -> Array:
	var locked: Array = cast.get("cells",[])
	if locked.is_empty(): return []
	var result: Array = []
	var skill := String(cast.get("skill_id",""))
	if skill == "fire_burst":
		for x in range(-1,2):
			for y in range(-1,2):
				var cell: Vector2i = locked[0]+Vector2i(x,y)
				if GridSpec.is_inside(cell): result.append(cell)
	elif skill == "herbal_heal": result = SkillResolver.support_area(locked[0],2,false)
	else: result = locked.duplicate()
	if skill == "tsunami" and terrain.size() == 64:
		result = result.filter(func(c): return TerrainDB.is_water_body(terrain[GridSpec.index(c)]))
	return result

static func paint(canvas: CanvasItem, shape: PackedVector2Array, healing: bool, enemy: bool, pulse: bool) -> void:
	var color := Color("a6e3a1") if healing else Color("ffbd69") if not enemy else Color("ff715d")
	canvas.draw_colored_polygon(shape,Color(color,0.34 if pulse else 0.25))
	canvas.draw_polyline(shape+PackedVector2Array([shape[0]]),color,2,false)
	var center := (shape[0]+shape[2])*0.5
	var inner := PackedVector2Array()
	for point in shape: inner.append(center+(point-center)*0.82)
	canvas.draw_polyline(inner+PackedVector2Array([inner[0]]),Color(color,0.65),1,false)
	# Short diagonal corner brackets leave the middle readable.
	for i in 4:
		canvas.draw_line(shape[i].lerp(shape[(i+3)%4],0.22),shape[i],color,3,false)
		canvas.draw_line(shape[i],shape[i].lerp(shape[(i+1)%4],0.22),color,3,false)
	# Project a pixel warning/medical cross onto the ground plane.
	var glyph := [Rect2(-2,-11,4,14),Rect2(-2,6,4,4)]
	if healing: glyph = [Rect2(-2,-9,4,18),Rect2(-8,-2,16,4)]
	for rect in glyph:
		var polygon := PackedVector2Array()
		for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			polygon.append(center+Vector2(p.x+p.y*0.18,p.y*0.85))
		canvas.draw_colored_polygon(polygon,color)
