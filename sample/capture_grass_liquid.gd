extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280,720)
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1,2,3]))
	app.run.region_mode = false
	app.run.offered_floor_themes = ["grass"]
	app.run.choose_floor_theme("grass")
	app.show_preview([1,2,3])
	app.begin_battle([1,2,3],app.current_screen.map)
	var board := BoardView.new()
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	board.position = Vector2(200,72)
	board.biome = "grass"
	board.terrain.resize(64)
	board.terrain.fill(TerrainDB.PLAIN)
	for cell in [Vector2i(1,1),Vector2i(2,1),Vector2i(1,2),Vector2i(2,2)]: board.terrain[GridSpec.index(cell)] = TerrainDB.GRASS
	for cell in [Vector2i(3,1),Vector2i(3,2)]: board.terrain[GridSpec.index(cell)] = TerrainDB.SHALLOW_GRASS
	for cell in [Vector2i(4,1),Vector2i(5,1),Vector2i(4,2),Vector2i(5,2)]: board.terrain[GridSpec.index(cell)] = TerrainDB.WATER
	for cell in [Vector2i(4,3),Vector2i(5,3),Vector2i(4,4),Vector2i(5,4)]: board.terrain[GridSpec.index(cell)] = TerrainDB.DEEP
	for cell in [Vector2i(2,5),Vector2i(3,5),Vector2i(2,6),Vector2i(3,6)]: board.terrain[GridSpec.index(cell)] = TerrainDB.LAVA
	var unit = app.current_screen.board.units.filter(func(u): return u.uid == 1)[0]
	unit.cell = Vector2i(2,2)
	board.units = [unit]
	app.queue_free()
	await process_frame
	root.add_child(board)
	var title := Label.new()
	title.text = "草丛遮挡与下沉液面 · 实际棋盘渲染"
	title.position = Vector2(24,18)
	title.add_theme_font_override("font",UIKit.font())
	title.add_theme_font_size_override("font_size",23)
	root.add_child(title)
	var note := Label.new()
	note.text = "草簇不透明，单位半透明\n浅草沿用草地纹理\n\n水面 / 深水 / 岩浆\n下沉 6 px，露出岸壁\n相邻液体没有内侧壁"
	note.position = Vector2(24,160)
	note.add_theme_font_override("font",UIKit.font())
	note.add_theme_font_size_override("font_size",16)
	root.add_child(note)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://sample/grass-liquid-preview.png")
	print("GRASS_LIQUID_RENDERED")
	quit()
