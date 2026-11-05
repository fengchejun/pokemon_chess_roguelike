extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(8101)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.enter_region_node("camp")
	app.run.storage.append(app.run._make_record("water_starter", 8))
	app.show_camp()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://outputs/camp_map")
	root.get_texture().get_image().save_png("res://outputs/camp_map/camp.png")
	app.current_screen._on_cell_clicked(app.current_screen.STORAGE_CELL)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://outputs/camp_map/storage.png")
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(4, 4)]])
	screen.state.trainer().cell = Vector2i(3, 3)
	app._switch(screen)
	await create_timer(1.5).timeout
	screen.selected_uid = Balance.TRAINER_UID
	screen._on_capture_pressed()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://outputs/camp_map/capture_range.png")
	quit()
