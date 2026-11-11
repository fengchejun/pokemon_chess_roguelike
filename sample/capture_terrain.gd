extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1280,720)
	var page = preload("res://sample/terrain_catalogue.gd").new()
	page.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(page)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://sample/terrain-catalogue.png")
	print("TERRAIN_CATALOGUE 14 types rendered")
	quit()
