extends RefCounted

const Art = preload("res://sample/pixel_art.gd")
static var textures: Dictionary = {}

# Strong control takes precedence; badges continue to list concurrent statuses.
static func tint(unit: CombatUnit) -> Color:
	if unit.frozen: return Color(0.40, 0.85, 1.0, 0.58)
	if unit.paralyzed_ticks > 0: return Color(1.0, 0.85, 0.16, 0.48)
	if unit.root_pending or unit.move_cancelled:
		return Color(0.36, 0.78, 0.35, 0.48)
	if unit.burn_ticks > 0: return Color(1.0, 0.30, 0.12, 0.48)
	if unit.slow_ticks > 0 or unit.wet_layers > 0: return Color(0.24, 0.60, 1.0, 0.44)
	return Color(1, 1, 1, 0)

static func icons(unit: CombatUnit) -> Array:
	var result: Array = []
	if unit.imprison_ticks > 0 or unit.vine_ticks > 0: result.append("bind")
	if unit.shock_ticks > 0: result.append("shock")
	if unit.parasite_source_uid >= 0: result.append("parasite")
	return result

static func paint_icons(canvas: CanvasItem, origin: Vector2, unit: CombatUnit) -> void:
	var active := icons(unit)
	for i in active.size():
		canvas.draw_set_transform((origin + Vector2(i * 23, 0)).round())
		var color: Color = {"bind": Color("9cd57a"), "shock": Color("e5bdff"), "parasite": Color("bbdf67")}[active[i]]
		canvas.draw_rect(Rect2(0, 0, 20, 20), Color("252737"))
		canvas.draw_rect(Rect2(0, 0, 20, 20), Color(color, 0.85), false, 1)
		match active[i]:
			"bind":
				canvas.draw_arc(Vector2(10, 8), 4, PI, TAU, 12, color, 2)
				canvas.draw_rect(Rect2(5, 8, 10, 8), color)
				canvas.draw_rect(Rect2(9, 10, 2, 4), Color("252737"))
			"shock":
				canvas.draw_colored_polygon(PackedVector2Array([Vector2(11,3),Vector2(5,11),Vector2(9,11),Vector2(7,17),Vector2(15,8),Vector2(11,8),Vector2(14,3)]), color)
			"parasite":
				canvas.draw_line(Vector2(10, 16), Vector2(10, 8), color, 2)
				canvas.draw_colored_polygon(PackedVector2Array([Vector2(10,11),Vector2(4,9),Vector2(3,4),Vector2(8,5)]), color)
				canvas.draw_colored_polygon(PackedVector2Array([Vector2(10,10),Vector2(11,4),Vector2(17,3),Vector2(16,8)]), color)
	canvas.draw_set_transform(Vector2.ZERO)

static func texture(index: int, color: Color) -> Texture2D:
	if color.a <= 0: return Art.tile(index)
	var key := "%d:%s" % [index, color.to_html()]
	if textures.has(key): return textures[key]
	var source := Art.tile(index)
	var image := source.atlas.get_image().get_region(Rect2i(source.region))
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0: continue
			var mixed := pixel.lerp(Color(color.r, color.g, color.b, pixel.a), color.a)
			image.set_pixel(x, y, mixed)
	var result := ImageTexture.create_from_image(image)
	textures[key] = result
	return result
