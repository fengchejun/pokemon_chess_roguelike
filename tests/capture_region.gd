extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.enter_region_node("camp")
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_camp.png")
	app.enter_region_node("event_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await process_frame
	await process_frame
	var gathering = app.current_screen
	for unit in gathering.state.alive_units("player"):
		var options: Dictionary = gathering.state.move_options(unit)
		var found := false
		for cell in gathering.state.food_cells:
			if options.has(cell):
				gathering.select_unit(unit.uid)
				gathering._on_move_pressed()
				gathering._on_board_clicked(cell)
				found = true
				break
		if found:
			break
	for wait_index in range(2):
		gathering.do_end_turn()
		while gathering.busy:
			await create_timer(.05).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_gathering_1280.png")
	print("WINDOW_GATHERED_FOOD ", gathering.state.food_collected)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_gathering_1600.png")
	gathering.leave_node_button.pressed.emit()
	await process_frame
	await process_frame
	app.continue_after_settlement()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_return.png")
	print("WINDOW_RETURN_SCREEN ", app.current_screen.name)
	app.queue_free()
	await process_frame
	quit()
