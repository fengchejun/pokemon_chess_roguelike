extends RefCounted

static func paint(canvas: CanvasItem, center: Vector2) -> void:
	# Stepped silhouettes keep the small flower legible beside pixel sprites.
	canvas.draw_set_transform(center.round())
	canvas.draw_set_transform(center + Vector2(0, 4), 0, Vector2(1, 0.22))
	canvas.draw_circle(Vector2.ZERO, 20, Color(0.04, 0.06, 0.04, 0.20))
	canvas.draw_set_transform(center.round())
	canvas.draw_rect(Rect2(-3, -28, 6, 31), Color("254c38"))
	canvas.draw_rect(Rect2(-1, -26, 3, 27), Color("75a94a"))
	for side in [-1, 1]:
		var leaf := PackedVector2Array([Vector2(0, -7), Vector2(side * 6, -20), Vector2(side * 20, -22), Vector2(side * 16, -10), Vector2(side * 6, -5)])
		canvas.draw_colored_polygon(leaf, Color("305b3e"))
		canvas.draw_line(Vector2(side * 3, -8), Vector2(side * 15, -18), Color("8bc45a"), 3)
	var head := Vector2(0, -33)
	for offset in [Vector2(0,-13),Vector2(12,-6),Vector2(12,7),Vector2(0,13),Vector2(-12,7),Vector2(-12,-6)]:
		var p: Vector2 = head + offset
		canvas.draw_rect(Rect2(p-Vector2(7,7),Vector2(14,14)),Color("8c652c"))
		canvas.draw_rect(Rect2(p-Vector2(5,6),Vector2(10,11)),Color("f4c84b"))
		canvas.draw_rect(Rect2(p-Vector2(3,5),Vector2(6,4)),Color("fff19a"))
	canvas.draw_rect(Rect2(-8,-41,16,16),Color("5b4536"))
	canvas.draw_rect(Rect2(-6,-39,12,12),Color("a47b39"))
	var bolt := PackedVector2Array([Vector2(1,-43),Vector2(-6,-32),Vector2(-1,-32),Vector2(-3,-23),Vector2(7,-35),Vector2(2,-35),Vector2(5,-43)])
	canvas.draw_colored_polygon(bolt,Color("fff6b3"))
	for offset in [Vector2(-25,-34),Vector2(24,-24)]:
		canvas.draw_line(offset+Vector2(-3,0),offset+Vector2(3,0),Color("ffe477"),2)
		canvas.draw_line(offset+Vector2(0,-3),offset+Vector2(0,3),Color("ffe477"),2)
	canvas.draw_set_transform(Vector2.ZERO)
