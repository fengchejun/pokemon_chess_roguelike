extends SceneTree

func _initialize() -> void:
	call_deferred("run_sample")

func run_sample() -> void:
	root.size = Vector2i(1280, 720)
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	app.run.region_mode = false
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_preview([1, 2, 3])
	app.begin_battle([1, 2, 3], app.current_screen.map)
	root.theme = preload("res://sample/sample_theme.gd").build()
	app.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	await create_timer(4.0).timeout
	var battle = app.current_screen
	battle.battle_notice.finish_all()
	battle.select_unit(1)
	battle._on_choose_skill_pressed()
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("res://sample/battle-v1.png")
	print("SAMPLE_RENDERED ", image.get_size())
	if "--interactive" in OS.get_cmdline_user_args():
		return
	app.queue_free()
	await process_frame
	quit()
