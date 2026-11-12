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
	app.run.seed = 20261111
	app.run.offered_floor_themes = ["grass"]
	app.run.choose_floor_theme("grass")
	app.show_preview([1,2,3])
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("res://sample/merged-preview.png")
	app.begin_battle([1,2,3],app.current_screen.map)
	await create_timer(4).timeout
	app.current_screen.battle_notice.finish_all()
	app.current_screen.select_unit(1)
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("res://sample/merged-battle.png")
	print("MAIN_PIXEL_MERGE_RENDERED")
	quit()
