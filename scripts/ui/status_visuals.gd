extends RefCounted

const Art = preload("res://sample/pixel_art.gd")
static var textures: Dictionary = {}

# Strong control takes precedence; badges continue to list concurrent statuses.
static func tint(unit: CombatUnit) -> Color:
	if unit.frozen: return Color(0.40, 0.85, 1.0, 0.58)
	if unit.paralyzed_ticks > 0: return Color(1.0, 0.85, 0.16, 0.48)
	if unit.imprison_ticks > 0 or unit.vine_ticks > 0 or unit.root_pending or unit.move_cancelled:
		return Color(0.36, 0.78, 0.35, 0.48)
	if unit.burn_ticks > 0: return Color(1.0, 0.30, 0.12, 0.48)
	if unit.shock_ticks > 0: return Color(0.76, 0.42, 1.0, 0.48)
	if unit.slow_ticks > 0 or unit.wet_layers > 0: return Color(0.24, 0.60, 1.0, 0.44)
	if unit.parasite_source_uid >= 0: return Color(0.70, 0.83, 0.22, 0.46)
	return Color(1, 1, 1, 0)

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
