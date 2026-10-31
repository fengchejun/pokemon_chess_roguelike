extends PanelContainer

var jagged := false

func _draw() -> void:
	if not jagged:
		return
	var points := PackedVector2Array()
	var w := size.x
	var h := size.y
	var step := 13.0
	points.append(Vector2(3, 3))
	for x in range(1, int(w / step)):
		points.append(Vector2(x * step, 3 if x % 2 == 0 else 9))
	points.append(Vector2(w - 3, 3))
	for y in range(1, int(h / step)):
		points.append(Vector2(w - (3 if y % 2 == 0 else 9), y * step))
	points.append(Vector2(w - 3, h - 3))
	for x in range(int(w / step) - 1, 0, -1):
		points.append(Vector2(x * step, h - (3 if x % 2 == 0 else 9)))
	points.append(Vector2(3, h - 3))
	for y in range(int(h / step) - 1, 0, -1):
		points.append(Vector2(3 if y % 2 == 0 else 9, y * step))
	draw_colored_polygon(points, Color("fff0d6"))
	points.append(points[0])
	draw_polyline(points, Color("8a4838"), 3.0, true)
